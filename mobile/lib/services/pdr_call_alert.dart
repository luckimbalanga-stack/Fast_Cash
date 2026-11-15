import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_nav.dart';
import '../models/models.dart';
import '../views/pdr/incoming_call_page.dart';

/// Alerte système type appel entrant (plein écran + son/vibration).
class PdrCallAlert {
  PdrCallAlert._();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int? _activeCallId;
  static void Function(int operationId)? onOpenCall;

  static const _channelId = 'pdr_incoming_call';
  static const _channelName = 'Appels demandes Fast-Cash';
  static const _notifId = 71001;

  static Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onResponse,
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Affiche les demandes retrait/dépôt en plein écran comme un appel.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
    _ready = true;

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final payload = launch!.notificationResponse?.payload;
      final id = _parseId(payload);
      if (id != null) {
        // Laisse le bootstrap restaurer la session avant navigation.
        Future<void>.delayed(const Duration(milliseconds: 800), () => openCallScreen(id));
      }
    }
  }

  static Future<void> ensurePermissions() async {
    if (!Platform.isAndroid) return;
    await Permission.notification.request();
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestFullScreenIntentPermission();
  }

  static void _onResponse(NotificationResponse response) {
    final id = _parseId(response.payload);
    if (id != null) openCallScreen(id);
  }

  static int? _parseId(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      return map['operation_id'] as int?;
    } catch (_) {
      return int.tryParse(payload);
    }
  }

  static Future<void> showIncomingCall({
    required CashOperation operation,
    required int waitSeconds,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await init();
    await ensurePermissions();
    if (_activeCallId == operation.id) return;
    _activeCallId = operation.id;

    final typeLabel = operation.isWithdrawal ? 'Retrait' : 'Dépôt';
    final title = 'Appel entrant Fast-Cash';
    final body = '$typeLabel · ${operation.userName} · ${operation.amount.toStringAsFixed(operation.currency == 'CDF' ? 0 : 2)} ${operation.currency}';
    final payload = jsonEncode({'operation_id': operation.id, 'wait': waitSeconds});

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Demandes PDR en plein écran',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
      playSound: true,
      enableVibration: true,
      ticker: 'Demande Fast-Cash',
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction('refuse', 'Refuser', showsUserInterface: true, cancelNotification: true),
        const AndroidNotificationAction('accept', 'Valider', showsUserInterface: true, cancelNotification: true),
      ],
    );

    await _plugin.show(
      _notifId,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: const DarwinNotificationDetails(presentSound: true, presentAlert: true)),
      payload: payload,
    );

    // Si l’app est déjà active, ouvre aussi l’écran Flutter immédiatement.
    openCallScreen(operation.id);
  }

  static Future<void> dismiss() async {
    _activeCallId = null;
    _presentedId = null;
    await _plugin.cancel(_notifId);
  }

  static int? _presentedId;

  static void openCallScreen(int operationId) {
    onOpenCall?.call(operationId);
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    if (_presentedId == operationId) return;
    _presentedId = operationId;
    nav.pushNamed(IncomingCallPage.routeName, arguments: operationId).whenComplete(() {
      if (_presentedId == operationId) _presentedId = null;
    });
  }

  static void debugLog(String message) {
    if (kDebugMode) debugPrint('[PdrCallAlert] $message');
  }
}
