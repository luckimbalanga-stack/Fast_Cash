import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

/// Écran plein type appel entrant : accepter / refuser dans le délai configuré.
class IncomingRequestCall extends StatefulWidget {
  const IncomingRequestCall({
    super.key,
    required this.operation,
    required this.waitSeconds,
    required this.onAccept,
    required this.onRefuse,
    this.onExpired,
  });

  final CashOperation operation;
  final int waitSeconds;
  final Future<void> Function() onAccept;
  final Future<void> Function() onRefuse;
  final VoidCallback? onExpired;

  static DateTime? deadlineOf(CashOperation operation, int waitSeconds) {
    final created = DateTime.tryParse(operation.createdAt)?.toLocal();
    if (created == null) return null;
    return created.add(Duration(seconds: waitSeconds));
  }

  static bool isLive(CashOperation operation, int waitSeconds, [DateTime? now]) {
    if (operation.status != 'pending') return false;
    final deadline = deadlineOf(operation, waitSeconds);
    if (deadline == null) return true;
    return (now ?? DateTime.now()).isBefore(deadline);
  }

  @override
  State<IncomingRequestCall> createState() => _IncomingRequestCallState();
}

class _IncomingRequestCallState extends State<IncomingRequestCall> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _tick;
  bool _busy = false;
  bool _expiredNotified = false;
  late int _secondsLeft;

  int get _wait => widget.waitSeconds.clamp(5, 120);

  @override
  void initState() {
    super.initState();
    _secondsLeft = _wait;
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _refreshCountdown();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _busy) return;
      _refreshCountdown();
    });
    unawaited(HapticFeedback.heavyImpact());
  }

  @override
  void didUpdateWidget(covariant IncomingRequestCall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.operation.id != widget.operation.id || oldWidget.waitSeconds != widget.waitSeconds) {
      _busy = false;
      _expiredNotified = false;
      _refreshCountdown();
      unawaited(HapticFeedback.heavyImpact());
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _refreshCountdown() {
    final deadline = IncomingRequestCall.deadlineOf(widget.operation, _wait);
    final left = deadline == null ? _wait : math.max(0, deadline.difference(DateTime.now()).inSeconds);
    if (left != _secondsLeft) {
      setState(() => _secondsLeft = left);
    }
    if (left <= 0 && !_expiredNotified) {
      _expiredNotified = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onExpired?.call();
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _secondsLeft <= 0) return;
    setState(() => _busy = true);
    try {
      await action();
      // Reste en chargement jusqu’à fermeture de l’appel (changement de statut).
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final op = widget.operation;
    final typeLabel = op.isWithdrawal ? 'Retrait' : 'Dépôt';
    final progress = (_secondsLeft / _wait).clamp(0.0, 1.0);

    return Material(
      color: const Color(0xF00B1628),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            children: [
              Text(
                'Demande entrante',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 28),
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  final scale = 1 + (_pulse.value * 0.08);
                  return Transform.scale(scale: scale, child: child);
                },
                child: Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.brand.withValues(alpha: 0.18),
                    border: Border.all(color: AppColors.brand, width: 2.5),
                  ),
                  child: Icon(
                    op.isWithdrawal ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    color: AppColors.brand,
                    size: 48,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                op.userName,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '$typeLabel · ${formatMoney(op.amount, op.currency)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.brand, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  children: [
                    _detail('Référence', op.reference),
                    _detail('Réseau', op.networkLabel),
                    _detail('Numéro', formatPhone(op.phone)),
                    _detail('Frais', formatMoney(op.fees, op.currency)),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 92,
                height: 92,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 92,
                      height: 92,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        color: _secondsLeft <= 5 ? AppColors.danger : AppColors.mint,
                      ),
                    ),
                    Text(
                      '$_secondsLeft',
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _secondsLeft > 0 ? 'Répondez avant la fin du délai' : 'Délai écoulé',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
              ),
              const SizedBox(height: 28),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: CircularProgressIndicator(color: AppColors.brand),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _CallAction(
                        label: 'Refuser',
                        color: AppColors.danger,
                        icon: Icons.call_end_rounded,
                        onPressed: _secondsLeft <= 0 ? null : () => _run(widget.onRefuse),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _CallAction(
                        label: 'Valider',
                        color: AppColors.mint,
                        icon: Icons.call_rounded,
                        onPressed: _secondsLeft <= 0 ? null : () => _run(widget.onAccept),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.55)))),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _CallAction extends StatelessWidget {
  const _CallAction({
    required this.label,
    required this.color,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Column(
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: Material(
            color: enabled ? color : color.withValues(alpha: 0.35),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: enabled ? 0.9 : 0.45), fontWeight: FontWeight.w700)),
      ],
    );
  }
}
