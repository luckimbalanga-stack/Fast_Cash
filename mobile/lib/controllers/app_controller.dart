import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
      notifyListeners();
    } catch (_) {}
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
    _startSync();
    notifyListeners();
  }

  void _startSync() {
    _sync?.cancel();
    _sync = Timer.periodic(const Duration(seconds: 4), (_) => refreshQuiet());
  }

  Future<void> refreshQuiet() async {
    if (token == null) return;
    try {
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

  void logout() {
    _sync?.cancel();
    token = null;
    role = 'guest';
    user = null;
    pdr = null;
    operations = [];
    notifications = [];
    ratings = [];
    selectedPhoneId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sync?.cancel();
    super.dispose();
  }
}
