import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_nav.dart';
import '../models/models.dart';
import '../views/pdr/incoming_call_page.dart';

/// Alerte système type appel entrant (plein écran au-dessus des autres apps).
class PdrCallAlert {
  PdrCallAlert._();

  static const _channel = MethodChannel('fast_cash/incoming_call');
  static bool _ready = false;
  static bool _permsWarm = false;
  static int? _presentedId;
  static Map<String, dynamic>? _seedById;
  static void Function(int operationId, Map<String, dynamic>? seed)? onOpenCall;

  static Future<void> init() async {
    if (_ready) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onIncomingCallIntent') {
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        _openFromNative(args);
      }
    });
    try {
      final pending = await _channel.invokeMethod<dynamic>('consumePendingCall');
      if (pending is Map) {
        _openFromNative(Map<String, dynamic>.from(pending));
      }
    } catch (_) {}
    _ready = true;
    // Permissions en arrière-plan : ne jamais bloquer l’apparition de l’appel.
    unawaited(ensurePermissions());
  }

  static Future<void> ensurePermissions() async {
    if (!Platform.isAndroid || _permsWarm) return;
    _permsWarm = true;
    try {
      await Permission.notification.request();
    } catch (_) {}
    try {
      final canFsi = await _channel.invokeMethod<bool>('canUseFullScreenIntent');
      if (canFsi == false) {
        await _channel.invokeMethod<void>('requestFullScreenIntentPermission');
      }
    } catch (_) {}
    try {
      await Permission.systemAlertWindow.request();
    } catch (_) {}
  }

  static Map<String, dynamic> seedFromOperation(CashOperation operation, int waitSeconds) {
    return {...operation.toJson(), 'timeline': const <dynamic>[], 'wait': waitSeconds};
  }

  /// Sonnerie native immédiate (appelable aussi depuis l’isolate watchdog).
  static Future<void> ringNative({
    required int operationId,
    required String title,
    required String body,
    required String callerName,
    required int waitSeconds,
    required String payloadJson,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('ringNow', {
        'operationId': operationId,
        'title': title,
        'body': body,
        'callerName': callerName,
        'waitSeconds': waitSeconds,
        'payloadJson': payloadJson,
      });
    } catch (e) {
      debugLog('ringNative failed: $e');
    }
  }

  static Future<void> showIncomingCall({
    required CashOperation operation,
    required int waitSeconds,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!_ready) unawaited(init());

    final seed = seedFromOperation(operation, waitSeconds);
    _seedById = seed;
    final typeLabel = operation.isWithdrawal ? 'Retrait' : 'Dépôt';
    final amount = operation.amount.toStringAsFixed(operation.currency == 'CDF' ? 0 : 2);
    final title = 'Appel entrant Fast-Cash';
    final body = '$typeLabel · ${operation.userName} · $amount ${operation.currency}';
    final payloadJson = jsonEncode(seed);

    // 1) Écran Flutter tout de suite (si app déjà active).
    openCallScreen(operation.id, seed: seed);

    // 2) Notif FSI + bring-to-front natif (sans await permissions).
    unawaited(ringNative(
      operationId: operation.id,
      title: title,
      body: body,
      callerName: operation.userName,
      waitSeconds: waitSeconds,
      payloadJson: payloadJson,
    ));
  }

  static Future<void> dismiss() async {
    _presentedId = null;
    _seedById = null;
    if (Platform.isAndroid) {
      try {
        // Annule la notif + retire KEEP_SCREEN_ON (le téléphone peut se mettre en veille).
        await _channel.invokeMethod<void>('dismissIncomingCall');
      } catch (_) {
        try {
          await _channel.invokeMethod<void>('clearIncomingCallWindow');
        } catch (_) {}
      }
    }
  }

  static void _openFromNative(Map<String, dynamic> args) {
    final id = args['operationId'];
    final operationId = id is int ? id : int.tryParse('$id');
    if (operationId == null) return;
    Map<String, dynamic>? seed;
    final raw = args['payloadJson'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) seed = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    if (seed != null) _seedById = seed;
    openCallScreen(operationId, seed: seed);
  }

  static void openCallScreen(int operationId, {Map<String, dynamic>? seed, int attempt = 0}) {
    onOpenCall?.call(operationId, seed ?? _seedById);
    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      if (attempt >= 30) return;
      Future<void>.delayed(Duration(milliseconds: attempt < 5 ? 80 : 200), () {
        openCallScreen(operationId, seed: seed ?? _seedById, attempt: attempt + 1);
      });
      return;
    }
    if (_presentedId == operationId) return;
    _presentedId = operationId;
    nav
        .pushNamed(
          IncomingCallPage.routeName,
          arguments: {
            'operationId': operationId,
            'seed': seed ?? _seedById,
          },
        )
        .whenComplete(() {
      if (_presentedId == operationId) _presentedId = null;
    });
  }

  static void debugLog(String message) {
    if (kDebugMode) debugPrint('[PdrCallAlert] $message');
  }
}
