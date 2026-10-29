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
  int? ratingPromptId;

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

  void _offerRating(List<CashOperation> operations) {
    if (promptingId != null) return;
    final waiting = operations.where((operation) => operation.isWithdrawal && operation.status == 'cash_delivered' && operation.ratingStars == null);
    if (waiting.isEmpty) {
      ratingPromptId = null;
      return;
    }
    final operation = waiting.first;
    if (ratingPromptId == operation.id) return;
    ratingPromptId = operation.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showRatingDialog(context, operation);
      if (!mounted) return;
      final stillWaiting = context.read<AppController>().operationById(operation.id);
      final pending = stillWaiting != null && stillWaiting.status == 'cash_delivered' && stillWaiting.ratingStars == null;
      if (!pending) setState(() => ratingPromptId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final operations = context.watch<AppController>().operations;
    _offerPin(operations);
    _offerRating(operations);
    final pages = [
      HomePage(onSearch: () => openTab(1)),
      const SearchPage(),
      const HistoryPage(),
      const ProfilePage(),
    ];
    return Scaffold(
      body: pages[index],
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

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onSearch});
  final VoidCallback onSearch;

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
              icon: Badge(isLabelVisible: controller.unread > 0, label: Text('${controller.unread}'), child: const Icon(Icons.notifications_none_rounded)),
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
            Expanded(child: _ActionButton(icon: Icons.download_rounded, label: 'Retirer', onTap: () => _openFlow(context, 'withdrawal'))),
            const SizedBox(width: 12),
            Expanded(child: _ActionButton(icon: Icons.upload_rounded, label: 'Déposer', onTap: () => _openFlow(context, 'deposit'))),
          ],
        ),
        const SizedBox(height: 14),
        SoftCard(
          onTap: onSearch,
          child: Row(
            children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Trouver un PDR à proximité', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.night)),
                  SizedBox(height: 4),
                  Text('Localisez le point de retrait ou dépôt le plus proche de vous.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  SizedBox(height: 8),
                  Text('Voir la carte →', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700)),
                ]),
              ),
              const Icon(Icons.map_rounded, color: AppColors.brand, size: 42),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SoftCard(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NumbersPage())),
          child: Row(children: [
            const CircleAvatar(backgroundColor: AppColors.brandSoft, child: Icon(Icons.phone_outlined, color: AppColors.brand)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Mes numéros', style: TextStyle(fontWeight: FontWeight.w800)), Text('Gérez vos numéros et réseaux Mobile Money.', style: TextStyle(color: AppColors.muted, fontSize: 12))])),
            if (phone != null) NetworkBadge(network: phone.network, label: phone.networkLabel),
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
  const _ActionButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            const Spacer(),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
          ]),
        ),
      ),
    );
  }
}
