import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../controllers/app_controller.dart';
import '../../core/api.dart';
import '../../services/pdr_call_alert.dart';
import '../../theme/app_theme.dart';
import 'incoming_call.dart';

/// Écran d’appel plein écran (ouvert aussi depuis notification / verrouillage).
class IncomingCallPage extends StatefulWidget {
  const IncomingCallPage({super.key, required this.operationId});

  static const routeName = '/pdr-incoming-call';

  final int operationId;

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable());
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await PdrCallAlert.dismiss();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final wait = controller.settings.pdrOfferSeconds.clamp(5, 120);
    final operation = controller.operationById(widget.operationId);

    if (operation == null || !IncomingRequestCall.isLive(operation, wait)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
      return const Scaffold(
        backgroundColor: Color(0xFF0B1628),
        body: Center(child: CircularProgressIndicator(color: AppColors.brand)),
      );
    }

    return IncomingRequestCall(
      key: ValueKey('incoming-page-${operation.id}-$wait'),
      operation: operation,
      waitSeconds: wait,
      onExpired: () {
        unawaited(() async {
          try {
            if (operation.status == 'pending') {
              await controller.postAction(operation.id, 'cancel');
            }
          } catch (_) {}
          await _close();
        }());
      },
      onAccept: () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await controller.postAction(operation.id, 'accept');
          messenger.showSnackBar(
            const SnackBar(content: Text('Demande acceptée. Elle apparaît dans Acceptées.')),
          );
          await _close();
        } on ApiException catch (error) {
          messenger.showSnackBar(
            SnackBar(content: Text(error.message), backgroundColor: AppColors.danger),
          );
          rethrow;
        }
      },
      onRefuse: () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await controller.postAction(operation.id, 'refuse');
          await _close();
        } on ApiException catch (error) {
          messenger.showSnackBar(
            SnackBar(content: Text(error.message), backgroundColor: AppColors.danger),
          );
          rethrow;
        }
      },
    );
  }
}
