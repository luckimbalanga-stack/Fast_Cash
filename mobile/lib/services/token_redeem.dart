import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../core/api.dart';
import '../core/format.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// Service de validation de jeton (SRP) — hors de la couche vue.
class TokenRedeemService {
  TokenRedeemService(this.controller);

  final AppController controller;

  Future<TokenRedeemOutcome> redeem(String raw) async {
    final normalized = raw.trim().toUpperCase();
    if (normalized.isEmpty) {
      return TokenRedeemOutcome.failure(message: 'Saisissez un code de jeton.');
    }
    try {
      final completed = await controller.redeemToken(normalized);
      final done = completed.isWithdrawal ? 'Retrait effectué' : 'Dépôt effectué';
      return TokenRedeemOutcome.success(operation: completed, message: done);
    } on ApiException catch (error) {
      return TokenRedeemOutcome.failure(message: error.message);
    } catch (_) {
      return TokenRedeemOutcome.failure(message: 'Lecture du jeton impossible.');
    }
  }

  Future<bool> redeemAndShowDialog(BuildContext context, String raw) async {
    final outcome = await redeem(raw);
    if (!context.mounted) return false;
    await showTokenResultDialog(context, outcome);
    return outcome.ok;
  }
}

class TokenRedeemOutcome {
  TokenRedeemOutcome._({required this.ok, required this.message, this.operation});

  factory TokenRedeemOutcome.success({required CashOperation operation, required String message}) {
    return TokenRedeemOutcome._(ok: true, message: message, operation: operation);
  }

  factory TokenRedeemOutcome.failure({required String message, CashOperation? operation}) {
    return TokenRedeemOutcome._(ok: false, message: message, operation: operation);
  }

  final bool ok;
  final String message;
  final CashOperation? operation;
}

Future<void> showTokenResultDialog(BuildContext context, TokenRedeemOutcome outcome) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        outcome.ok ? 'Scan réussi — opération terminée' : 'Scan échoué',
        style: TextStyle(fontWeight: FontWeight.w800, color: outcome.ok ? AppColors.mint : AppColors.danger),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (outcome.message.isNotEmpty) Text(outcome.message, style: const TextStyle(height: 1.35)),
          if (outcome.operation != null) ...[
            if (outcome.message.isNotEmpty) const SizedBox(height: 12),
            Text(outcome.operation!.userName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              formatMoney(outcome.operation!.amount, outcome.operation!.currency),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.brand),
            ),
            const SizedBox(height: 6),
            Text(
              'Jeton ${outcome.operation!.tokenCode ?? outcome.operation!.reference}',
              style: const TextStyle(color: AppColors.muted),
            ),
            Text(
              '${outcome.operation!.isWithdrawal ? 'Retrait' : 'Dépôt'} · ${statusLabel(outcome.operation!.status, type: outcome.operation!.type)}',
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
