import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/app_nav.dart';
import '../core/version.dart';
import '../models/models.dart';
import '../services/pdr_call_alert.dart';
import '../services/pdr_watchdog.dart';
import '../views/pdr/incoming_call.dart';

class AppController extends ChangeNotifier {
  AppController({ApiClient? api}) : api = api ?? ApiClient();

  final ApiClient api;
  AppSettings settings = AppSettings.fallback;
  String? token;
  String role = 'guest';
  UserAccount? user;
  PdrPoint? pdr;
  int? selectedPhoneId;
  List<CashOperation> operations = [];
  List<AppNotification> notifications = [];
  List<PdrPoint> directory = [];
  List<RatingItem> ratings = [];
  Timer? _sync;
  bool _refreshing = false;
  bool _lightOnly = false;
  bool _syncPaused = false;
  DateTime? _lastFullRefresh;
  String installedVersion = '1.0.0';
  AppUpdateInfo? pendingUpdate;
  bool updatePromptShown = false;
  bool sessionReady = false;

  static const _kToken = 'fc_token';
  static const _kRole = 'fc_role';
  static const _kPdrId = 'fc_pdr_id';
  static const _kPhoneId = 'fc_phone_id';

  int get unread => notifications.where((item) => !item.isRead).length;

  PhoneNumber? get activePhone {
    final numbers = user?.numbers ?? [];
    for (final number in numbers) {
      if (number.id == selectedPhoneId && number.verified) return number;
    }
    return user?.primary;
  }

  CashOperation? operationById(int id) {
    for (final operation in operations) {
      if (operation.id == id) return operation;
    }
    return null;
  }

  Future<void> bootstrap() async {
    try {
      final info = await PackageInfo.fromPlatform();
      installedVersion = info.version;
    } catch (_) {}
    try {
      final json = await api.send('GET', '/api/settings');
      settings = AppSettings.fromJson(json as Map<String, dynamic>);
      pendingUpdate = _resolveUpdate(settings, installedVersion);
    } catch (_) {}
    try {
      await _restoreSession().timeout(const Duration(seconds: 120));
    } catch (_) {
      token = null;
      role = 'guest';
      user = null;
      pdr = null;
    }
    sessionReady = true;
    notifyListeners();
  }

  Future<void> _persistSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || role == 'guest') {
      await prefs.remove(_kToken);
      await prefs.remove(_kRole);
      await prefs.remove(_kPdrId);
      await prefs.remove(_kPhoneId);
      return;
    }
    await prefs.setString(_kToken, token!);
    await prefs.setString(_kRole, role);
    if (pdr != null) {
      await prefs.setInt(_kPdrId, pdr!.id);
    } else {
      await prefs.remove(_kPdrId);
    }
    if (selectedPhoneId != null) {
      await prefs.setInt(_kPhoneId, selectedPhoneId!);
    }
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(_kToken);
    final savedRole = prefs.getString(_kRole);
    if (savedToken == null || savedRole == null || savedRole == 'guest') return;
    token = savedToken;
    role = savedRole;
    selectedPhoneId = prefs.getInt(_kPhoneId);
    try {
      if (role == 'pdr') {
        final pdrId = prefs.getInt(_kPdrId);
        if (pdrId == null) throw StateError('pdr');
        final fresh = await api.send('GET', '/api/pdr/$pdrId', token: token);
        pdr = PdrPoint.fromJson(fresh as Map<String, dynamic>);
      }
      await refreshFull();
      if (role == 'user' && user == null) throw StateError('user');
      if (role == 'pdr' && pdr == null) throw StateError('pdr');
      _startSync();
      if (role == 'pdr') await _syncPdrWatchdog();
    } catch (_) {
      token = null;
      role = 'guest';
      user = null;
      pdr = null;
      await _persistSession();
    }
  }

  AppUpdateInfo? _resolveUpdate(AppSettings remote, String current) {
    final download = remote.appDownloadUrl.trim();
    if (download.isEmpty) return null;
    final behindLatest = compareVersions(current, remote.appVersion) < 0;
    final belowMin = compareVersions(current, remote.appMinVersion) < 0;
    if (!behindLatest && !belowMin) return null;
    return AppUpdateInfo(
      currentVersion: current,
      latestVersion: remote.appVersion,
      downloadUrl: download,
      message: remote.appUpdateMessage,
      forced: belowMin,
    );
  }

  void markUpdatePromptShown() {
    updatePromptShown = true;
  }

  void _applyUser(Map<String, dynamic> json) {
    user = UserAccount.fromJson(json);
    final current = activePhone;
    selectedPhoneId = current?.id;
  }

  Future<Map<String, dynamic>> requestUserOtp(String phone, String purpose, {String? name}) async {
    final json = await api.send('POST', '/api/auth/request-otp', body: {'phone': phone, 'purpose': purpose, 'name': name});
    return json as Map<String, dynamic>;
  }

  Future<void> verifyUser(String phone, String code, String purpose, {String? name, String? network}) async {
    final json = await api.send('POST', '/api/auth/verify', body: {
      'phone': phone,
      'code': code,
      'purpose': purpose,
      'name': name,
      'network': network,
    });
    final map = json as Map<String, dynamic>;
    token = map['token'] as String;
    role = 'user';
    _applyUser(map['user'] as Map<String, dynamic>);
    await refreshFull();
    await _persistSession();
    _startSync();
    notifyListeners();
  }

  Future<void> verifyPdr(String phone, String code) async {
    final json = await api.send('POST', '/api/auth/pdr/verify', body: {'phone': phone, 'code': code, 'purpose': 'pdr'});
    await applyPdrSession(json as Map<String, dynamic>);
  }

  /// Valide le mot de passe PDR et déclenche l’OTP (simulation console si SMS off).
  Future<Map<String, dynamic>> enterPdr(String phone, String password) async {
    final json = await api.send('POST', '/api/auth/pdr/enter', body: {
      'phone': phone,
      'password': password,
    });
    return json as Map<String, dynamic>;
  }

  Future<void> applyPdrSession(Map<String, dynamic> map) async {
    token = map['token'] as String;
    role = 'pdr';
    pdr = PdrPoint.fromJson(map['pdr'] as Map<String, dynamic>);
    await refreshFull();
    await _persistSession();
    _startSync();
    await _syncPdrWatchdog();
    notifyListeners();
  }

  Future<void> _syncPdrWatchdog() async {
    if (role != 'pdr' || token == null || pdr == null) {
      await PdrWatchdog.stop();
      await PdrCallAlert.dismiss();
      return;
    }
    await PdrCallAlert.ensurePermissions();
    await PdrWatchdog.start(
      apiBase: api.base,
      token: token!,
      offerSeconds: pdrOfferSeconds,
      isOpen: pdr!.isOpen,
    );
    _maybeRingIncoming();
  }

  CashOperation? liveIncomingOffer() {
    if (role != 'pdr' || pdr == null || !pdr!.isOpen) return null;
    final wait = pdrOfferSeconds;
    final candidates = operations.where((op) => IncomingRequestCall.isLive(op, wait)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return candidates.isEmpty ? null : candidates.first;
  }

  void _maybeRingIncoming() {
    final incoming = liveIncomingOffer();
    if (incoming == null) {
      unawaited(PdrCallAlert.dismiss());
      return;
    }
    unawaited(PdrCallAlert.showIncomingCall(operation: incoming, waitSeconds: pdrOfferSeconds));
  }

  /// Offre détectée par le service d’arrière-plan (app hors premier plan).
  void handleWatchdogOffer(Map<String, dynamic> data) {
    if (role != 'pdr' || pdr == null || !pdr!.isOpen) return;
    final raw = data['raw'];
    if (raw is Map) {
      try {
        final operation = CashOperation.fromJson(Map<String, dynamic>.from(raw));
        _upsertOperation(operation);
        notifyListeners();
        final wait = (data['wait'] is int) ? data['wait'] as int : pdrOfferSeconds;
        unawaited(PdrCallAlert.showIncomingCall(operation: operation, waitSeconds: wait.clamp(5, 120)));
        return;
      } catch (_) {}
    }
    unawaited(refreshLight());
    _maybeRingIncoming();
  }

  void pauseSync() {
    _syncPaused = true;
  }

  void resumeSync() {
    _syncPaused = false;
    _startSync();
  }

  void _startSync() {
    _sync?.cancel();
    if (token == null || role == 'guest') return;
    // PDR : le watchdog gère déjà l’appel entrant → sync UI plus espacé.
    final seconds = role == 'pdr' ? 8 : 10;
    _sync = Timer.periodic(Duration(seconds: seconds), (_) {
      if (_syncPaused) return;
      final dueFull = _lastFullRefresh == null || DateTime.now().difference(_lastFullRefresh!) > const Duration(minutes: 3);
      if (dueFull) {
        unawaited(refreshFull());
      } else {
        unawaited(refreshLight());
      }
    });
  }

  String _opsSignature(List<CashOperation> items) => items.map((item) => '${item.id}:${item.status}').join('|');

  String _notesSignature(List<AppNotification> items) => items.map((item) => '${item.id}:${item.isRead}').join('|');

  void _upsertOperation(CashOperation operation) {
    final index = operations.indexWhere((item) => item.id == operation.id);
    if (index >= 0) {
      operations = [...operations]..[index] = operation;
    } else {
      operations = [operation, ...operations];
    }
  }

  /// Injecte une demande reçue via notification / intent natif (hors sync).
  void upsertIncomingSeed(CashOperation operation) {
    _upsertOperation(operation);
    notifyListeners();
  }

  bool get _isLoggedIn => token != null && role != 'guest';

  /// Sync léger : opérations + notifications uniquement.
  Future<void> refreshLight() async {
    if (!_isLoggedIn || _refreshing) return;
    _refreshing = true;
    _lightOnly = true;
    try {
      final previousOps = _opsSignature(operations);
      final previousNotes = _notesSignature(notifications);
      final auth = token;
      if (auth == null) return;
      final opsPath = role == 'pdr'
          ? '/api/operations?limit=40&include_timeline=false'
          : '/api/operations?limit=40&include_timeline=false';
      final results = await Future.wait([
        api.send('GET', opsPath, token: auth),
        api.send('GET', '/api/notifications', token: auth),
      ]);
      if (!_isLoggedIn) return;
      operations = (results[0] as List).map((item) => CashOperation.fromJson(item as Map<String, dynamic>)).toList();
      notifications = (results[1] as List).map((item) => AppNotification.fromJson(item as Map<String, dynamic>)).toList();
      final changed = previousOps != _opsSignature(operations) || previousNotes != _notesSignature(notifications);
      if (changed) {
        notifyListeners();
        if (role == 'pdr') _maybeRingIncoming();
      }
    } catch (_) {
    } finally {
      _refreshing = false;
      _lightOnly = false;
    }
  }

  /// Sync complet : settings + profil/PDR + ops + notifs.
  Future<void> refreshFull() async {
    if (!_isLoggedIn) return;
    if (_refreshing && !_lightOnly) return;
    var wait = 0;
    while (_refreshing && _lightOnly && wait < 40) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      wait += 1;
    }
    if (_refreshing || !_isLoggedIn) return;
    _refreshing = true;
    try {
      final previousOps = _opsSignature(operations);
      final previousNotes = _notesSignature(notifications);
      final previousPdrOpen = pdr?.isOpen;
      final previousUserId = user?.id;
      final auth = token;
      if (auth == null) return;
      final futures = <Future>[
        api.send('GET', '/api/settings'),
        api.send('GET', '/api/operations?limit=60&include_timeline=false', token: auth),
        api.send('GET', '/api/notifications', token: auth),
      ];
      if (role == 'user') {
        futures.add(api.send('GET', '/api/users/me', token: auth));
      } else if (role == 'pdr' && pdr != null) {
        futures.add(api.send('GET', '/api/pdr/${pdr!.id}', token: auth));
      }
      final results = await Future.wait(futures);
      if (!_isLoggedIn) return;
      try {
        settings = AppSettings.fromJson(results[0] as Map<String, dynamic>);
        pendingUpdate = _resolveUpdate(settings, installedVersion);
      } catch (_) {}
      operations = (results[1] as List).map((item) => CashOperation.fromJson(item as Map<String, dynamic>)).toList();
      notifications = (results[2] as List).map((item) => AppNotification.fromJson(item as Map<String, dynamic>)).toList();
      if (role == 'user' && results.length > 3) {
        _applyUser(results[3] as Map<String, dynamic>);
      } else if (role == 'pdr' && pdr != null && results.length > 3) {
        pdr = PdrPoint.fromJson(results[3] as Map<String, dynamic>);
      }
      _lastFullRefresh = DateTime.now();
      final changed = previousOps != _opsSignature(operations) ||
          previousNotes != _notesSignature(notifications) ||
          previousPdrOpen != pdr?.isOpen ||
          previousUserId != user?.id;
      if (changed) notifyListeners();
      if (role == 'pdr') {
        if (previousPdrOpen != pdr?.isOpen) {
          unawaited(_syncPdrWatchdog());
        } else {
          _maybeRingIncoming();
        }
      }
    } catch (_) {
    } finally {
      _refreshing = false;
    }
  }

  /// Compat : sync léger par défaut (polling).
  Future<void> refreshQuiet() => refreshLight();

  Future<SearchResult> searchPdr({
    required double lat,
    required double lng,
    required String kind,
    required String currency,
    required double amount,
    required String network,
    required bool simulated,
    int? maxM,
  }) async {
    final cap = maxM == null ? '' : '&max_m=$maxM';
    final json = await api.send(
      'GET',
      '/api/pdr/search?lat=$lat&lng=$lng&kind=$kind&currency=$currency&amount=$amount&network=$network&simulated=$simulated$cap',
      token: token,
    );
    return SearchResult.fromJson(json as Map<String, dynamic>);
  }

  Future<void> loadDirectory() async {
    final json = await api.send('GET', '/api/pdr?status=active', token: token);
    directory = (json as List).map((item) => PdrPoint.fromJson(item as Map<String, dynamic>)).toList();
    notifyListeners();
  }

  int get searchRadiusM => settings.searchRadiusM;

  int get pdrOfferSeconds => settings.pdrOfferSeconds.clamp(5, 120);

  /// Compte les PDR ouverts dans un rayon (fermés ignorés, sans filtre liquidité).
  Future<({int total, int open})> scanZonePdrs({int? maxM}) async {
    final radius = maxM ?? searchRadiusM;
    const kinLat = -4.3038;
    const kinLng = 15.3005;
    var lat = kinLat;
    var lng = kinLng;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        final current = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 8));
        final far = Geolocator.distanceBetween(current.latitude, current.longitude, kinLat, kinLng) > 30000;
        if (!far) {
          lat = current.latitude;
          lng = current.longitude;
        }
      }
    } catch (_) {}
    await loadDirectory();
    // Plus proche d’abord parmi les ouverts uniquement.
    final openInRadius = <({PdrPoint point, double meters})>[];
    for (final point in directory) {
      if (!point.isOpen) continue;
      final meters = Geolocator.distanceBetween(lat, lng, point.lat, point.lng);
      if (meters > radius) continue;
      openInRadius.add((point: point, meters: meters));
    }
    openInRadius.sort((a, b) {
      final byDistance = a.meters.compareTo(b.meters);
      if (byDistance != 0) return byDistance;
      return b.point.ratingAvg.compareTo(a.point.ratingAvg);
    });
    final open = openInRadius.length;
    return (total: open, open: open);
  }

  Future<CashOperation> createOperation({required int pdrId, required String phone, required double amount, required String currency, required String type}) async {
    final json = await api.send('POST', '/api/operations', token: token, body: {
      'pdr_id': pdrId,
      'phone': phone,
      'amount': amount,
      'currency': currency,
      'type': type,
    });
    final operation = CashOperation.fromJson(json as Map<String, dynamic>);
    _upsertOperation(operation);
    notifyListeners();
    return operation;
  }

  Future<CashOperation> postAction(int id, String action, {Map<String, dynamic>? body}) async {
    final json = await api.send('POST', '/api/operations/$id/$action', token: token, body: body ?? {});
    final operation = CashOperation.fromJson(json as Map<String, dynamic>);
    _upsertOperation(operation);
    notifyListeners();
    return operation;
  }

  Future<Map<String, dynamic>> lookupToken(String code) async {
    final json = await api.send('GET', '/api/operations/token/${Uri.encodeComponent(code.trim().toUpperCase())}', token: token);
    return json as Map<String, dynamic>;
  }

  Future<CashOperation> redeemToken(String code) async {
    final json = await api.send('POST', '/api/operations/token/redeem', token: token, body: {'code': code.trim().toUpperCase()});
    final operation = CashOperation.fromJson(json as Map<String, dynamic>);
    _upsertOperation(operation);
    notifyListeners();
    return operation;
  }

  Future<Map<String, dynamic>> requestPhoneChallenge(String phone, String? network) async {
    final json = await api.send('POST', '/api/phones/challenge', token: token, body: {'phone': phone, 'network': network});
    return json as Map<String, dynamic>;
  }

  Future<void> confirmPhone(String phone, String network, String code) async {
    await api.send('POST', '/api/phones', token: token, body: {'phone': phone, 'network': network, 'code': code});
    await refreshFull();
  }

  Future<void> setPrimary(int id) async {
    await api.send('PATCH', '/api/phones/$id/primary', token: token, body: {});
    selectedPhoneId = id;
    await refreshFull();
  }

  void useForTransaction(int id) {
    selectedPhoneId = id;
    unawaited(_persistSession());
    notifyListeners();
  }

  Future<void> updateNetwork(int id, String network) async {
    await api.send('PATCH', '/api/phones/$id', token: token, body: {'network': network});
    await refreshFull();
  }

  Future<void> deletePhone(int id) async {
    await api.send('DELETE', '/api/phones/$id', token: token);
    await refreshFull();
  }

  Future<Map<String, dynamic>> detectPhone(String phone) async {
    final json = await api.send('GET', '/api/meta/detect?phone=${Uri.encodeComponent(phone)}', token: token);
    return json as Map<String, dynamic>;
  }

  Future<void> updateAvailability(Map<String, dynamic> body) async {
    if (pdr == null) return;
    final json = await api.send('POST', '/api/pdr/${pdr!.id}/availability', token: token, body: body);
    pdr = PdrPoint.fromJson(json as Map<String, dynamic>);
    await _syncPdrWatchdog();
    notifyListeners();
  }

  Future<void> loadRatings() async {
    if (pdr == null || token == null) return;
    final json = await api.send('GET', '/api/pdr/ratings?pdr_id=${pdr!.id}', token: token);
    ratings = (json as List).map((item) => RatingItem.fromJson(item as Map<String, dynamic>)).toList();
    notifyListeners();
  }

  Future<Map<String, dynamic>> rechargeLiquidity({
    required String network,
    required double amount,
    required String pin,
  }) async {
    if (pdr == null) throw Exception('Point de retrait introuvable.');
    final json = await api.send(
      'POST',
      '/api/pdr/${pdr!.id}/liquidity/recharge',
      token: token,
      body: {'network': network, 'amount': amount, 'pin': pin},
    ) as Map<String, dynamic>;
    pdr = PdrPoint.fromJson(json);
    await _syncPdrWatchdog();
    notifyListeners();
    return (json['recharge'] as Map<String, dynamic>?) ?? {'ok': false, 'added_cdf': 0};
  }

  Future<void> markRead(int id) async {
    await api.send('PATCH', '/api/notifications/$id/read', token: token, body: {});
    notifications = [
      for (final item in notifications)
        if (item.id == id)
          AppNotification(id: item.id, title: item.title, body: item.body, isRead: true, createdAt: item.createdAt, operationId: item.operationId)
        else
          item,
    ];
    notifyListeners();
  }

  Future<void> markAllRead() async {
    await api.send('POST', '/api/notifications/read-all', token: token, body: {});
    notifications = [
      for (final item in notifications)
        AppNotification(id: item.id, title: item.title, body: item.body, isRead: true, createdAt: item.createdAt, operationId: item.operationId),
    ];
    notifyListeners();
  }

  Future<void> logout() async {
    // Ne jamais await stopService() avant le clear : il peut bloquer et
    // empêcher notifyListeners() (impossible de se déconnecter).
    _sync?.cancel();
    _sync = null;
    _syncPaused = true;
    token = null;
    role = 'guest';
    user = null;
    pdr = null;
    operations = [];
    notifications = [];
    ratings = [];
    selectedPhoneId = null;
    notifyListeners();
    try {
      appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    } catch (_) {}
    try {
      await Future.wait([
        _persistSession(),
        PdrWatchdog.clearSession(),
      ]).timeout(const Duration(seconds: 3));
    } catch (_) {}
    unawaited(_shutdownBackgroundServices());
  }

  Future<void> _shutdownBackgroundServices() async {
    try {
      await PdrWatchdog.stop().timeout(const Duration(seconds: 4));
    } catch (_) {}
    try {
      await PdrCallAlert.dismiss().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  @override
  void dispose() {
    _sync?.cancel();
    super.dispose();
  }
}
