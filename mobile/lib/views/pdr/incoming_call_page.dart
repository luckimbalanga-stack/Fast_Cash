import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../controllers/app_controller.dart';
import '../../core/api.dart';
import '../../models/models.dart';
import '../../services/pdr_call_alert.dart';
import '../../theme/app_theme.dart';
import 'incoming_call.dart';

/// Écran d’appel plein écran (ouvert aussi depuis notification / verrouillage).
class IncomingCallPage extends StatefulWidget {
  const IncomingCallPage({
    super.key,
    required this.operationId,
    this.seed,
  });

  static const routeName = '/pdr-incoming-call';

  final int operationId;
  final Map<String, dynamic>? seed;

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  bool _closing = false;
  CashOperation? _seedOp;

  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable());
    if (widget.seed != null) {
      try {
        _seedOp = CashOperation.fromJson(widget.seed!);
      } catch (_) {}
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<AppController>();
      if (_seedOp != null) {
        controller.upsertIncomingSeed(_seedOp!);
      }
      if (controller.operationById(widget.operationId) == null) {
        unawaited(controller.refreshLight());
      }
    });
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
    final operation = controller.operationById(widget.operationId) ?? _seedOp;

    if (operation == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B1628),
        body: Center(child: CircularProgressIndicator(color: AppColors.brand)),
      );
    }

    if (operation.status != 'pending') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
      return const Scaffold(
        backgroundColor: Color(0xFF0B1628),
        body: Center(child: CircularProgressIndicator(color: AppColors.brand)),
      );
    }

    return PopScope(
      canPop: false,
      child: IncomingRequestCall(
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
          final messenger = ScaffoldMessenger.maybeOf(context);
          try {
            await controller.postAction(operation.id, 'accept');
            messenger?.showSnackBar(
              const SnackBar(content: Text('Demande acceptée. Elle apparaît dans Acceptées.')),
            );
            await _close();
          } on ApiException catch (error) {
            messenger?.showSnackBar(
              SnackBar(content: Text(error.message), backgroundColor: AppColors.danger),
            );
            rethrow;
          }
        },
        onRefuse: () async {
          final messenger = ScaffoldMessenger.maybeOf(context);
          try {
            await controller.postAction(operation.id, 'refuse');
            await _close();
          } on ApiException catch (error) {
            messenger?.showSnackBar(
              SnackBar(content: Text(error.message), backgroundColor: AppColors.danger),
            );
            rethrow;
          }
        },
      ),
    );
  }
}
