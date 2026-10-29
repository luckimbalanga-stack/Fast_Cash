import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

class FastCashMark extends StatelessWidget {
  const FastCashMark({super.key, this.size = 46, this.wordmark = false, this.stacked = false});

  final double size;
  final bool wordmark;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final asset = stacked
        ? 'assets/brand/logo.png'
        : wordmark
            ? 'assets/brand/lockup.png'
            : 'assets/brand/mark.png';
    return Image.asset(
      asset,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Fast-Cash',
    );
  }
}

class NotificationFeed extends StatelessWidget {
  const NotificationFeed({super.key, required this.items, required this.onOpen, required this.onReadAll});

  final List<AppNotification> items;
  final ValueChanged<AppNotification> onOpen;
  final VoidCallback onReadAll;

  @override
  Widget build(BuildContext context) {
    final unread = items.where((item) => !item.isRead).length;
    return ColoredBox(
      color: AppColors.mist,
      child: items.isEmpty ? _empty() : _list(unread),
    );
  }

  Widget _empty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DecoratedBox(
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x140E203B), blurRadius: 24, offset: Offset(0, 8))]),
            child: SizedBox(width: 88, height: 88, child: Icon(Icons.notifications_none_rounded, size: 40, color: AppColors.brand)),
          ),
          SizedBox(height: 18),
          Text('Aucune notification', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.night)),
          SizedBox(height: 8),
          Text('Les acceptations, refus et jetons de vos opérations s’afficheront ici.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.4)),
        ]),
      ),
    );
  }

  Widget _list(int unread) {
    final groups = <String, List<AppNotification>>{};
    for (final item in items) {
      groups.putIfAbsent(_dayLabel(item.createdAt), () => []).add(item);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.line)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Boîte de réception', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.night, fontSize: 16)),
              const SizedBox(height: 2),
              Text(unread == 0 ? 'Tout est à jour' : '$unread non lue${unread > 1 ? 's' : ''}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ])),
            if (unread > 0)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(20)),
                child: Text('$unread', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            TextButton(onPressed: unread == 0 ? null : onReadAll, child: const Text('Tout lu')),
          ]),
        ),
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
            child: Text(entry.key.toUpperCase(), style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
          ),
          ...entry.value.map(_card),
        ],
      ],
    );
  }

  Widget _card(AppNotification item) {
    final tone = _tone(item.title);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        elevation: 0,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => onOpen(item),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: item.isRead ? AppColors.line : tone.soft),
              boxShadow: const [BoxShadow(color: Color(0x0A0E203B), blurRadius: 16, offset: Offset(0, 6))],
            ),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 5, decoration: BoxDecoration(color: item.isRead ? AppColors.line : tone.color, borderRadius: const BorderRadius.horizontal(left: Radius.circular(22)))),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(color: tone.soft, borderRadius: BorderRadius.circular(16)),
                        child: Icon(tone.icon, color: tone.color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(item.title, style: TextStyle(fontWeight: item.isRead ? FontWeight.w700 : FontWeight.w800, color: AppColors.night))),
                          if (!item.isRead) Container(width: 8, height: 8, margin: const EdgeInsets.only(left: 8), decoration: BoxDecoration(color: tone.color, shape: BoxShape.circle)),
                        ]),
                        const SizedBox(height: 4),
                        Text(item.body, style: const TextStyle(color: AppColors.ink, height: 1.35)),
                        const SizedBox(height: 8),
                        Text(_when(item.createdAt), style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                      ])),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  _NoteTone _tone(String title) {
    final value = title.toLowerCase();
    if (value.contains('refus')) return const _NoteTone(Icons.cancel_outlined, AppColors.danger, AppColors.dangerSoft);
    if (value.contains('pin') || value.contains('accept')) return const _NoteTone(Icons.lock_outline_rounded, AppColors.brand, AppColors.brandSoft);
    if (value.contains('jeton')) return const _NoteTone(Icons.qr_code_rounded, AppColors.night, Color(0xFFE8EEF6));
    if (value.contains('espèce') || value.contains('depot') || value.contains('dépôt') || value.contains('paiement')) {
      return const _NoteTone(Icons.payments_outlined, Color(0xFF0E9F78), AppColors.mintSoft);
    }
    return const _NoteTone(Icons.notifications_none_rounded, AppColors.brand, AppColors.brandSoft);
  }

  String _dayLabel(String iso) {
    final date = DateTime.tryParse(iso)?.toLocal();
    if (date == null) return 'Récemment';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return 'Aujourd’hui';
    if (day == today.subtract(const Duration(days: 1))) return 'Hier';
    return '${date.day} ${months[date.month - 1]}';
  }

  String _when(String iso) {
    final date = DateTime.tryParse(iso)?.toLocal();
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'À l’instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 12) return 'Il y a ${diff.inHours} h';
    return formatDate(iso);
  }
}

class _NoteTone {
  const _NoteTone(this.icon, this.color, this.soft);
  final IconData icon;
  final Color color;
  final Color soft;
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: AppColors.waitingSoft, borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        const Icon(Icons.location_on_outlined, size: 18, color: Color(0xFF9A6700)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: Color(0xFF9A6700), fontSize: 12, fontWeight: FontWeight.w600, height: 1.35))),
      ]),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.icon, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          disabledBackgroundColor: const Color(0xFFFFD7BD),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label),
                  if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 18)],
                ],
              ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brand,
          side: const BorderSide(color: AppColors.brand, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
            Text(label),
          ],
        ),
      ),
    );
  }
}

class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color = Colors.white});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
        boxShadow: const [BoxShadow(color: Color(0x0A0E203B), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(22), onTap: onTap, child: card));
  }
}

class NetworkBadge extends StatelessWidget {
  const NetworkBadge({super.key, required this.network, required this.label});
  final String network;
  final String label;

  Color get color {
    switch (network) {
      case 'airtel':
        return const Color(0xFFE11D48);
      case 'mpesa':
        return const Color(0xFF16A34A);
      case 'afrimoney':
        return const Color(0xFF7C3AED);
      default:
        return AppColors.brand;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.swap_calls_rounded, color: color, size: 18),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: AppColors.night, fontWeight: FontWeight.w700, fontSize: 13)),
      ],
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.type});
  final String status;
  final String? type;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'completed' || 'cash_delivered' || 'payment_confirmed' || 'accepted' => AppColors.mint,
      'refused' || 'cancelled' => AppColors.danger,
      _ => AppColors.waiting,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(statusLabel(status, type: type), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class KioskThumb extends StatelessWidget {
  const KioskThumb({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.asset(
        'assets/brand/kiosk.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: 'Point de retrait Fast-Cash',
      ),
    );
  }
}

class PhoneField extends StatelessWidget {
  const PhoneField({super.key, required this.controller, this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: AppColors.mist, borderRadius: BorderRadius.circular(16)),
          child: const Row(children: [Text('🇨🇩', style: TextStyle(fontSize: 18)), SizedBox(width: 6), Text('+243', style: TextStyle(fontWeight: FontWeight.w700))]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            onChanged: onChanged,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
            decoration: InputDecoration(
              hintText: '81 234 56 78',
              filled: true,
              fillColor: AppColors.mist,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
      ],
    );
  }
}

class OtpBoxes extends StatelessWidget {
  const OtpBoxes({super.key, required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      maxLength: 6,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 16, color: AppColors.night),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        counterText: '',
        hintText: '••••••',
        filled: true,
        fillColor: AppColors.mist,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      ),
      onChanged: onChanged,
    );
  }
}

Future<void> runAction(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on ApiException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message), backgroundColor: AppColors.danger));
  }
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}
