import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/version.dart';
import '../models/models.dart';

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
    await _restoreSession();
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
      await refreshQuiet();
      if (role == 'user' && user == null) throw StateError('user');
      if (role == 'pdr' && pdr == null) throw StateError('pdr');
      _startSync();
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
    await refreshQuiet();
    await _persistSession();
    _startSync();
    notifyListeners();
  }

  Future<void> verifyPdr(String phone, String code) async {
    final json = await api.send('POST', '/api/auth/pdr/verify', body: {'phone': phone, 'code': code, 'purpose': 'pdr'});
    final map = json as Map<String, dynamic>;
    token = map['token'] as String;
    role = 'pdr';
    pdr = PdrPoint.fromJson(map['pdr'] as Map<String, dynamic>);
    await refreshQuiet();
    await _persistSession();
    _startSync();
    notifyListeners();
  }

  /// Valide le mot de passe PDR et déclenche l’OTP (simulation console si SMS off).
  Future<Map<String, dynamic>> enterPdr(String phone, String password) async {
    final json = await api.send('POST', '/api/auth/pdr/enter', body: {
      'phone': phone,
      'password': password,
    });
    return json as Map<String, dynamic>;
  }

  void _startSync() {
    _sync?.cancel();
    // PDR : sync plus rapide pour l’appel entrant.
    final seconds = role == 'pdr' ? 2 : 4;
    _sync = Timer.periodic(Duration(seconds: seconds), (_) => refreshQuiet());
  }

  Future<void> refreshQuiet() async {
    if (token == null) return;
    try {
      try {
        final settingsJson = await api.send('GET', '/api/settings');
        settings = AppSettings.fromJson(settingsJson as Map<String, dynamic>);
        pendingUpdate = _resolveUpdate(settings, installedVersion);
      } catch (_) {}
      if (role == 'user') {
        final me = await api.send('GET', '/api/users/me', token: token);
        _applyUser(me as Map<String, dynamic>);
      } else if (role == 'pdr' && pdr != null) {
        final fresh = await api.send('GET', '/api/pdr/${pdr!.id}', token: token);
        pdr = PdrPoint.fromJson(fresh as Map<String, dynamic>);
        final ratingJson = await api.send('GET', '/api/pdr/ratings?pdr_id=${pdr!.id}', token: token);
        ratings = (ratingJson as List).map((item) => RatingItem.fromJson(item as Map<String, dynamic>)).toList();
      }
      final ops = await api.send('GET', '/api/operations', token: token);
      operations = (ops as List).map((item) => CashOperation.fromJson(item as Map<String, dynamic>)).toList();
      final notes = await api.send('GET', '/api/notifications', token: token);
      notifications = (notes as List).map((item) => AppNotification.fromJson(item as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (_) {}
  }

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

  /// Compte les PDR dans un rayon (info seule, sans lister les points).
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
    var total = 0;
    var open = 0;
    for (final point in directory) {
      final meters = Geolocator.distanceBetween(lat, lng, point.lat, point.lng);
      if (meters > radius) continue;
      total += 1;
      if (point.isOpen) open += 1;
    }
    return (total: total, open: open);
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
    await refreshQuiet();
    return operation;
  }

  Future<CashOperation> postAction(int id, String action, {Map<String, dynamic>? body}) async {
    final json = await api.send('POST', '/api/operations/$id/$action', token: token, body: body ?? {});
    await refreshQuiet();
    return CashOperation.fromJson(json as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> lookupToken(String code) async {
    final json = await api.send('GET', '/api/operations/token/${Uri.encodeComponent(code.trim().toUpperCase())}', token: token);
    return json as Map<String, dynamic>;
  }

  Future<CashOperation> redeemToken(String code) async {
    final json = await api.send('POST', '/api/operations/token/redeem', token: token, body: {'code': code.trim().toUpperCase()});
    await refreshQuiet();
    return CashOperation.fromJson(json as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> requestPhoneChallenge(String phone, String? network) async {
    final json = await api.send('POST', '/api/phones/challenge', token: token, body: {'phone': phone, 'network': network});
    return json as Map<String, dynamic>;
  }

  Future<void> confirmPhone(String phone, String network, String code) async {
    await api.send('POST', '/api/phones', token: token, body: {'phone': phone, 'network': network, 'code': code});
    await refreshQuiet();
  }

  Future<void> setPrimary(int id) async {
    await api.send('PATCH', '/api/phones/$id/primary', token: token, body: {});
    selectedPhoneId = id;
    await refreshQuiet();
  }

  void useForTransaction(int id) {
    selectedPhoneId = id;
    unawaited(_persistSession());
    notifyListeners();
  }

  Future<void> updateNetwork(int id, String network) async {
    await api.send('PATCH', '/api/phones/$id', token: token, body: {'network': network});
    await refreshQuiet();
  }

  Future<void> deletePhone(int id) async {
    await api.send('DELETE', '/api/phones/$id', token: token);
    await refreshQuiet();
  }

  Future<Map<String, dynamic>> detectPhone(String phone) async {
    final json = await api.send('GET', '/api/meta/detect?phone=${Uri.encodeComponent(phone)}', token: token);
    return json as Map<String, dynamic>;
  }

  Future<void> updateAvailability(Map<String, dynamic> body) async {
    if (pdr == null) return;
    final json = await api.send('POST', '/api/pdr/${pdr!.id}/availability', token: token, body: body);
    pdr = PdrPoint.fromJson(json as Map<String, dynamic>);
    notifyListeners();
  }

  Future<void> markRead(int id) async {
    await api.send('PATCH', '/api/notifications/$id/read', token: token, body: {});
    await refreshQuiet();
  }

  Future<void> markAllRead() async {
    await api.send('POST', '/api/notifications/read-all', token: token, body: {});
    await refreshQuiet();
  }

  Future<void> logout() async {
    _sync?.cancel();
    token = null;
    role = 'guest';
    user = null;
    pdr = null;
    operations = [];
    notifications = [];
    ratings = [];
    selectedPhoneId = null;
    await _persistSession();
    notifyListeners();
  }

  @override
  void dispose() {
    _sync?.cancel();
    super.dispose();
  }
}
