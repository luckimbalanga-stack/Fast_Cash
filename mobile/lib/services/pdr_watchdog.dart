import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Surveille les demandes pending hors premier plan tant que le PDR est ouvert.
class PdrWatchdog {
  PdrWatchdog._();

  static const _kApi = 'fc_watch_api';
  static const _kToken = 'fc_watch_token';
  static const _kOffer = 'fc_watch_offer';
  static const _kOpen = 'fc_watch_open';

  static bool _initialized = false;
  static void Function(Map<String, dynamic> data)? onOfferFound;

  static Future<void> init() async {
    if (!Platform.isAndroid || _initialized) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'pdr_watchdog',
        channelName: 'Surveillance Fast-Cash',
        channelDescription: 'Garde la session PDR prête à recevoir les appels de demandes.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Poll plus fréquent = détection plus rapide de la demande.
        eventAction: ForegroundTaskEventAction.repeat(1200),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  static void _onTaskData(Object data) {
    if (data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    onOfferFound?.call(map);
  }

  static Future<void> persistSession({
    required String apiBase,
    required String token,
    required int offerSeconds,
    required bool isOpen,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApi, apiBase);
    await prefs.setString(_kToken, token);
    await prefs.setInt(_kOffer, offerSeconds);
    await prefs.setBool(_kOpen, isOpen);
  }

  static Future<void> start({
    required String apiBase,
    required String token,
    required int offerSeconds,
    required bool isOpen,
  }) async {
    if (!Platform.isAndroid) return;
    await init();
    await persistSession(apiBase: apiBase, token: token, offerSeconds: offerSeconds, isOpen: isOpen);
    if (!isOpen) {
      await stop();
      return;
    }
    final running = await FlutterForegroundTask.isRunningService;
    if (running) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Fast-Cash PDR',
        notificationText: 'En écoute des demandes…',
      );
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Fast-Cash PDR',
      notificationText: 'En écoute des demandes…',
      callback: pdrWatchdogCallback,
    );
  }

  /// Efface les prefs de session immédiatement (sans attendre le stop service).
  static Future<void> clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kOpen, false);
      await prefs.remove(_kToken);
      await prefs.remove(_kApi);
      await prefs.remove(_kOffer);
    } catch (_) {}
  }

  static Future<void> stop() async {
    await clearSession();
    if (!Platform.isAndroid) return;
    try {
      final running = await FlutterForegroundTask.isRunningService
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (!running) return;
      await FlutterForegroundTask.stopService().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
void pdrWatchdogCallback() {
  FlutterForegroundTask.setTaskHandler(_PdrWatchHandler());
}

class _PdrWatchHandler extends TaskHandler {
  static const _channel = MethodChannel('fast_cash/incoming_call');
  int? _lastRangId;
  bool _polling = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // no-op
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_polling) return;
    _polling = true;
    _poll().whenComplete(() => _polling = false);
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  Future<void> _poll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final open = prefs.getBool('fc_watch_open') ?? false;
      final token = prefs.getString('fc_watch_token');
      final api = prefs.getString('fc_watch_api');
      final offer = prefs.getInt('fc_watch_offer') ?? 30;
      if (!open || token == null || token.isEmpty || api == null || api.isEmpty) return;

      final client = HttpClient();
      try {
        final uri = Uri.parse('$api/api/operations');
        final req = await client.getUrl(uri);
        req.headers.set('Authorization', 'Bearer $token');
        req.headers.set('Content-Type', 'application/json');
        // Timeout court pour ne pas rater la fenêtre d’offre.
        final res = await req.close().timeout(const Duration(seconds: 6));
        if (res.statusCode >= 400) return;
        final body = await res.transform(const Utf8Decoder()).join();
        final decoded = jsonDecode(body);
        if (decoded is! List) return;
        final now = DateTime.now();
        Map<String, dynamic>? best;
        DateTime? bestCreated;
        for (final raw in decoded) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          if (item['status'] != 'pending') continue;
          final createdRaw = item['created_at'] as String?;
          final created = createdRaw == null ? null : DateTime.tryParse(createdRaw)?.toLocal();
          if (created == null) continue;
          final deadline = created.add(Duration(seconds: offer.clamp(5, 120)));
          if (!now.isBefore(deadline)) continue;
          if (bestCreated == null || created.isBefore(bestCreated)) {
            bestCreated = created;
            best = item;
          }
        }
        if (best == null) {
          _lastRangId = null;
          return;
        }

        final opId = best['id'];
        final operationId = opId is int ? opId : int.tryParse('$opId');
        if (operationId == null) return;

        // Sonnerie native IMMÉDIATE depuis l’isolate (avant le round-trip UI).
        if (_lastRangId != operationId) {
          _lastRangId = operationId;
          final wait = offer.clamp(5, 120);
          final type = '${best['type']}' == 'withdrawal' ? 'Retrait' : 'Dépôt';
          final name = '${best['user_name'] ?? 'Client'}';
          final currency = '${best['currency'] ?? ''}';
          final amountRaw = best['amount'];
          final amount = amountRaw is num
              ? amountRaw.toStringAsFixed(currency == 'CDF' ? 0 : 2)
              : '$amountRaw';
          final seed = Map<String, dynamic>.from(best)..['wait'] = wait;
          final payloadJson = jsonEncode(seed);
          try {
            FlutterForegroundTask.wakeUpScreen();
          } catch (_) {}
          try {
            await _channel.invokeMethod<void>('ringNow', {
              'operationId': operationId,
              'title': 'Appel entrant Fast-Cash',
              'body': '$type · $name · $amount $currency',
              'callerName': name,
              'waitSeconds': wait,
              'payloadJson': payloadJson,
            });
          } catch (_) {}
          try {
            FlutterForegroundTask.launchApp();
          } catch (_) {}
        }

        FlutterForegroundTask.sendDataToMain({
          'operation_id': best['id'],
          'type': best['type'],
          'user_name': best['user_name'],
          'amount': best['amount'],
          'currency': best['currency'],
          'created_at': best['created_at'],
          'wait': offer,
          'raw': best,
        });
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      // Silence : le tick suivant réessayera.
    }
  }
}
