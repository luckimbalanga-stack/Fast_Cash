import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../core/format.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'flow_pages.dart';
import 'user_pages.dart';

class UserShell extends StatefulWidget {
  const UserShell({super.key});

  @override
  State<UserShell> createState() => UserShellState();
}

class UserShellState extends State<UserShell> {
  int index = 0;
  int? promptingId;
  final Set<int> _completionShown = {};

  void openTab(int value) => setState(() => index = value);

  void _offerPin(List<CashOperation> operations) {
    final waiting = operations.where((operation) => operation.status == 'pin_required');
    if (waiting.isEmpty) {
      promptingId = null;
      return;
    }
    final operation = waiting.first;
    if (promptingId == operation.id) return;
    promptingId = operation.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showPinDialog(context, operation);
      if (!mounted) return;
      final stillWaiting = context.read<AppController>().operationById(operation.id)?.status == 'pin_required';
      if (!stillWaiting) setState(() => promptingId = null);
    });
  }

  /// Dès qu’une op est terminée : ouvre la page succès (+ note PDR) même si le client a quitté le ticket.
  void _offerCompletion(List<CashOperation> operations) {
    if (promptingId != null) return;
    // Déjà sur ticket / reçu / autre page empilée — TokenPage / ReceivedPage gèrent.
    if (Navigator.of(context).canPop()) return;
    CashOperation? candidate;
    for (final operation in operations) {
      if (operation.status != 'cash_delivered' && operation.status != 'completed') continue;
      if (_completionShown.contains(operation.id)) continue;
      // Déjà noté : pas de réouverture auto.
      if (operation.ratingStars != null) continue;
      candidate = operation;
      break;
    }
    if (candidate == null) return;
    _completionShown.add(candidate.id);
    final operation = candidate;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || Navigator.of(context).canPop()) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReceivedPage(operation: operation, celebrate: true)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final operations = context.watch<AppController>().operations;
    _offerPin(operations);
    _offerCompletion(operations);
    final pages = [
      const HomePage(),
      const SearchPage(),
      const HistoryPage(),
      const ProfilePage(),
    ];
    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.brandSoft,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: openTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded, color: AppColors.brand), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.search), selectedIcon: Icon(Icons.search, color: AppColors.brand), label: 'Rechercher'),
          NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history, color: AppColors.brand), label: 'Historique'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: AppColors.brand), label: 'Profil'),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool scanning = false;

  Future<void> _scanZone() async {
    setState(() => scanning = true);
    try {
      final result = await context.read<AppController>().scanZonePdrs();
      if (!mounted) return;
      final radius = context.read<AppController>().searchRadiusM;
      await showZoneScanResult(context, total: result.total, open: result.open, radiusM: radius);
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final user = controller.user;
    final phone = controller.activePhone;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(
          children: [
            const FastCashMark(size: 42, wordmark: true),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
              icon: Badge(
                isLabelVisible: controller.unread > 0 || controller.hasActiveDispatch,
                label: controller.hasActiveDispatch
                    ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.6, color: Colors.white))
                    : Text('${controller.unread}'),
                child: const Icon(Icons.notifications_none_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            CircleAvatar(radius: 26, backgroundColor: AppColors.brandSoft, child: Text(initials(user?.name ?? ''), style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w800))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bonjour,', style: TextStyle(color: AppColors.muted)),
                  Text(user?.name ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.night)),
                  const Text('Votre argent, votre monnaie, à proximité.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SoftCard(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NumbersPage())),
          child: Row(
            children: [
              const Icon(Icons.smartphone_rounded, color: AppColors.brand),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Votre numéro actif', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  Text(formatPhone(phone?.phone ?? ''), style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
              if (phone != null) NetworkBadge(network: phone.network, label: phone.networkLabel),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.arrow_downward_rounded,
                label: 'Retrait',
                hint: 'Retirer de l’argent',
                onTap: () => _openFlow(context, 'withdrawal'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                icon: Icons.arrow_upward_rounded,
                label: 'Dépôt',
                hint: 'Déposer de l’argent',
                onTap: () => _openFlow(context, 'deposit'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SoftCard(
          onTap: scanning ? null : () => runAction(context, _scanZone),
          child: Row(
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Scanner votre zone pour identifier les PDR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.night)),
                  const SizedBox(height: 4),
                  const Text('Vérifiez s’il y a des points de retrait ouverts près de vous.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(scanning ? 'Scan en cours…' : 'Lancer le scan →', style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
                ]),
              ),
              Icon(scanning ? Icons.radar : Icons.my_location_rounded, color: AppColors.brand, size: 42),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SoftCard(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NumbersPage())),
          child: const Row(children: [
            CircleAvatar(backgroundColor: AppColors.brandSoft, child: Icon(Icons.phone_outlined, color: AppColors.brand)),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Mes numéros', style: TextStyle(fontWeight: FontWeight.w800)), Text('Gérez vos numéros et réseaux Mobile Money.', style: TextStyle(color: AppColors.muted, fontSize: 12))])),
            Icon(Icons.chevron_right),
          ]),
        ),
        const SizedBox(height: 12),
        SoftCard(
          onTap: () => context.findAncestorStateOfType<UserShellState>()?.openTab(2),
          child: const Row(children: [
            CircleAvatar(backgroundColor: AppColors.brandSoft, child: Icon(Icons.receipt_long_outlined, color: AppColors.brand)),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Mes transactions', style: TextStyle(fontWeight: FontWeight.w800)), Text('Consultez l’historique de vos retraits et dépôts.', style: TextStyle(color: AppColors.muted, fontSize: 12))])),
            Icon(Icons.chevron_right),
          ]),
        ),
      ],
    );
  }

  void _openFlow(BuildContext context, String type) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => AmountPage(type: type)));
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.hint, required this.onTap});
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brand,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 12),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 2),
              Text(hint, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
