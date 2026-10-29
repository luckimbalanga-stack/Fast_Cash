import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';

class PdrShell extends StatefulWidget {
  const PdrShell({super.key});

  @override
  State<PdrShell> createState() => _PdrShellState();
}

class _PdrShellState extends State<PdrShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [const PdrHomePage(), const PdrRequestsPage(), const PdrScanPage(), const PdrHistoryPage(), const PdrProfilePage()];
    return Scaffold(
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.brandSoft,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: AppColors.brand), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.list_alt), selectedIcon: Icon(Icons.list_alt, color: AppColors.brand), label: 'Demandes'),
          NavigationDestination(icon: Icon(Icons.qr_code_scanner), selectedIcon: Icon(Icons.qr_code_scanner, color: AppColors.brand), label: 'Scanner'),
          NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history, color: AppColors.brand), label: 'Historique'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: AppColors.brand), label: 'Profil'),
        ],
      ),
    );
  }
}

class PdrHomePage extends StatelessWidget {
  const PdrHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final pdr = controller.pdr;
    if (pdr == null) return const SizedBox.shrink();
    final today = controller.operations.where((operation) {
      final date = DateTime.parse(operation.createdAt).toLocal();
      final now = DateTime.now();
      return date.year == now.year && date.month == now.month && date.day == now.day;
    }).length;
    final pending = controller.operations.where((operation) => operation.status == 'pending').length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(children: [
          const FastCashMark(size: 40, wordmark: true),
          const Spacer(),
          Tooltip(
            message: pdr.isOpen ? 'Ouvert' : 'Fermé',
            child: Switch(
              value: pdr.isOpen,
              thumbColor: const WidgetStatePropertyAll(Colors.white),
              trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? AppColors.brand : AppColors.danger),
              trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
              onChanged: (value) => runAction(context, () => controller.updateAvailability({'is_open': value})),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _PdrNotes())),
            icon: Badge(isLabelVisible: controller.unread > 0, label: Text('${controller.unread}'), child: const Icon(Icons.notifications_none_rounded)),
          ),
        ]),
        const SizedBox(height: 8),
        SoftCard(
          child: Row(children: [
            const KioskThumb(size: 84),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pdr.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.night)),
              Text('PDR ${pdr.code}', style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 4),
              Text(pdr.isOpen ? 'En service' : 'Indisponible', style: TextStyle(color: pdr.isOpen ? AppColors.mint : AppColors.danger, fontWeight: FontWeight.w700)),
              Text('${pdr.address}, ${pdr.commune}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              Text('★ ${pdr.ratingAvg.toStringAsFixed(1)} · ${pdr.ratingCount} avis', style: const TextStyle(fontSize: 12)),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _Stat(value: '$pending', label: 'Demandes en attente', color: AppColors.brandSoft),
          const SizedBox(width: 8),
          _Stat(value: '$today', label: 'Transactions du jour', color: const Color(0xFFE8F1FF)),
        ]),
        const SizedBox(height: 8),
        SoftCard(
          color: AppColors.mintSoft,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiquidityPage())),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Liquidités disponibles', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(formatMoney(pdr.usdAvailable, 'USD'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(formatMoney(pdr.cdfAvailable, 'CDF'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 8),
        SoftCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PdrRequestsPage())), child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.receipt_long, color: AppColors.brand), title: Text('Demandes'), subtitle: Text('Accepter ou refuser les clients'), trailing: Icon(Icons.chevron_right))),
        SoftCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PdrScanPage())), child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.qr_code_scanner, color: AppColors.brand), title: Text('Vérifier un jeton'), subtitle: Text('Scanner ou saisir un code'), trailing: Icon(Icons.chevron_right))),
        SoftCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiquidityPage())), child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.account_balance_wallet_outlined, color: AppColors.brand), title: Text('Mes liquidités'), subtitle: Text('Déclarer USD, CDF et les dépôts'), trailing: Icon(Icons.chevron_right))),
        SoftCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RatingsPage())), child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.star_outline, color: AppColors.brand), title: Text('Évaluations reçues'), trailing: Icon(Icons.chevron_right))),
      ],
    );
  }
}

class PdrProfilePage extends StatelessWidget {
  const PdrProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final pdr = context.watch<AppController>().pdr;
    if (pdr == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Profil', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.night)),
        const SizedBox(height: 16),
        SoftCard(
          child: Row(children: [
            const KioskThumb(size: 72),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pdr.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text('PDR ${pdr.code}', style: const TextStyle(color: AppColors.muted)),
              Text(pdr.managerName, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(formatPhone(pdr.phone), style: const TextStyle(color: AppColors.muted)),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
        SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${pdr.address}, ${pdr.commune}, ${pdr.city}'),
          const SizedBox(height: 6),
          Text('Horaires ${pdr.openingHours}', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 6),
          Text(pdr.isOpen ? 'Ouvert' : 'Fermé', style: TextStyle(color: pdr.isOpen ? AppColors.mint : AppColors.danger, fontWeight: FontWeight.w700)),
        ])),
        const SizedBox(height: 16),
        PrimaryButton(label: 'Se déconnecter', onPressed: () => context.read<AppController>().logout()),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(child: SoftCard(color: color, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.night)), Text(label, style: const TextStyle(fontSize: 12))])));
  }
}

class PdrRequestsPage extends StatelessWidget {
  const PdrRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        const SizedBox(height: 8),
        const Text('Demandes', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const TabBar(labelColor: AppColors.brand, indicatorColor: AppColors.brand, tabs: [Tab(text: 'En attente'), Tab(text: 'Acceptées'), Tab(text: 'Terminées')]),
        Expanded(
          child: TabBarView(children: [
            _RequestList(match: (operation) => operation.status == 'pending'),
            _RequestList(match: (operation) => const {'accepted', 'payment_pending', 'payment_confirmed', 'cash_delivered'}.contains(operation.status)),
            _RequestList(match: (operation) => const {'completed', 'refused', 'cancelled'}.contains(operation.status)),
          ]),
        ),
      ]),
    );
  }
}

class _RequestList extends StatelessWidget {
  const _RequestList({required this.match});
  final bool Function(CashOperation operation) match;

  @override
  Widget build(BuildContext context) {
    final items = context.watch<AppController>().operations.where(match).toList();
    if (items.isEmpty) return const Center(child: Text('Aucune demande', style: TextStyle(color: AppColors.muted)));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: items.map((operation) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SoftCard(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PdrRequestPage(operationId: operation.id))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(operation.userName, style: const TextStyle(fontWeight: FontWeight.w800))), StatusPill(status: operation.status, type: operation.type)]),
            Text('${operation.isWithdrawal ? 'Retrait' : 'Dépôt'} · ${formatMoney(operation.amount, operation.currency)}'),
            Text('${operation.reference} · ${formatDate(operation.createdAt)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
      )).toList(),
    );
  }
}

class PdrRequestPage extends StatelessWidget {
  const PdrRequestPage({super.key, required this.operationId});
  final int operationId;

  @override
  Widget build(BuildContext context) {
    final operation = context.watch<AppController>().operationById(operationId);
    if (operation == null) return const Scaffold(body: Center(child: Text('Demande introuvable')));
    return Scaffold(
      appBar: AppBar(title: Text(operation.reference)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(operation.userName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          StatusPill(status: operation.status, type: operation.type),
          const SizedBox(height: 16),
          _row('Type', operation.isWithdrawal ? 'Retrait' : 'Dépôt'),
          _row('Montant', formatMoney(operation.amount, operation.currency)),
          _row('Frais', formatMoney(operation.fees, operation.currency)),
          _row('Réseau', operation.networkLabel),
          _row('Numéro', formatPhone(operation.phone)),
          _row('Date', formatDate(operation.createdAt)),
          const SizedBox(height: 16),
          if (operation.status == 'pending') ...[
            PrimaryButton(label: 'Accepter', onPressed: () => runAction(context, () => context.read<AppController>().postAction(operation.id, 'accept'))),
            const SizedBox(height: 8),
            GhostButton(label: 'Refuser', onPressed: () => runAction(context, () => context.read<AppController>().postAction(operation.id, 'refuse'))),
          ],
          if (!operation.isWithdrawal && operation.status == 'accepted')
            PrimaryButton(label: 'Confirmer la réception des espèces', onPressed: () => runAction(context, () => context.read<AppController>().postAction(operation.id, 'confirm-cash'))),
          if (operation.isWithdrawal && operation.tokenCode != null && operation.status == 'payment_confirmed')
            PrimaryButton(label: 'Vérifier le jeton', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PdrScanPage(initialCode: operation.tokenCode)))),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))), Text(value, style: const TextStyle(fontWeight: FontWeight.w700))]),
      );
}

class PdrScanPage extends StatefulWidget {
  const PdrScanPage({super.key, this.initialCode});
  final String? initialCode;

  @override
  State<PdrScanPage> createState() => _PdrScanPageState();
}

class _PdrScanPageState extends State<PdrScanPage> {
  late final TextEditingController code = TextEditingController(text: widget.initialCode ?? '');
  final MobileScannerController camera = MobileScannerController(detectionSpeed: DetectionSpeed.normal, facing: CameraFacing.back);
  Map<String, dynamic>? preview;
  bool manual = false;
  bool _handlingScan = false;
  String? _lastScanned;

  @override
  void dispose() {
    camera.dispose();
    code.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _lookup() async {
    final result = await context.read<AppController>().lookupToken(code.text);
    setState(() => preview = result);
    return result;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (manual || _handlingScan) return;
    final value = capture.barcodes
        .map((item) => item.rawValue?.trim())
        .whereType<String>()
        .firstWhere((item) => item.isNotEmpty, orElse: () => '');
    if (value.isEmpty || value == _lastScanned) return;
    _handlingScan = true;
    _lastScanned = value;
    setState(() {
      code.text = value.toUpperCase();
      preview = null;
    });
    try {
      await _lookup();
    } catch (error) {
      if (mounted) {
        final message = error is ApiException ? error.message : 'Lecture du jeton impossible.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.danger));
      }
    } finally {
      _handlingScan = false;
    }
  }

  Future<void> _validate() async {
    final controller = context.read<AppController>();
    final current = preview ?? await _lookup();
    if (!mounted) return;
    if (current['redeemable'] != true) {
      throw ApiException(current['error']?.toString() ?? 'Ce jeton ne peut pas être validé.');
    }
    await controller.redeemToken(code.text);
    if (!mounted) return;
    setState(() {
      preview = null;
      _lastScanned = null;
    });
    code.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scan validé. L’opération passe à Scan effectué, puis Terminée après la note client.')));
  }

  Future<void> _refuse() async {
    final id = preview?['id'];
    if (id is int) await context.read<AppController>().postAction(id, 'cancel');
    if (!mounted) return;
    setState(() {
      preview = null;
      _lastScanned = null;
    });
    code.clear();
  }

  @override
  Widget build(BuildContext context) {
    final operation = preview == null ? null : CashOperation.fromJson(preview!);
    final canPop = Navigator.canPop(context);
    return Scaffold(
      appBar: canPop ? AppBar(title: const Text('Vérifier le jeton')) : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const Text('Vérifier le token PDR', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.night)),
          const SizedBox(height: 6),
          const Text('Scannez le QR code du client ou saisissez le code manuellement.', style: TextStyle(color: AppColors.muted, height: 1.35)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _ModeButton(
                label: 'Scanner',
                icon: Icons.qr_code_scanner_rounded,
                selected: !manual,
                onTap: () => setState(() {
                  manual = false;
                  camera.start();
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModeButton(
                label: 'Saisir un code',
                icon: Icons.dialpad_rounded,
                selected: manual,
                onTap: () => setState(() {
                  manual = true;
                  camera.stop();
                }),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          if (!manual)
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                height: 260,
                child: Stack(fit: StackFit.expand, children: [
                  MobileScanner(controller: camera, onDetect: _onDetect),
                  const IgnorePointer(child: Center(child: SizedBox(width: 200, height: 200, child: CustomPaint(painter: _ScanCorners())))),
                ]),
              ),
            ),
          if (manual) ...[
            const SizedBox(height: 0),
            TextField(
              controller: code,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() => preview = null),
              decoration: InputDecoration(
                hintText: 'FC-4829-7714',
                filled: true,
                fillColor: AppColors.mist,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            PrimaryButton(label: 'Vérifier le code', onPressed: code.text.trim().isEmpty ? null : () => runAction(context, () async { await _lookup(); })),
          ],
          if (!manual && code.text.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            SoftCard(child: Text('Code lu : ${code.text.trim().toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
          const SizedBox(height: 12),
          SoftCard(
            color: const Color(0xFFFFF7F2),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, color: AppColors.brand),
              SizedBox(width: 10),
              Expanded(child: Text('Autorisez la caméra puis scannez le QR du client.\nLe jeton reste valide jusqu’à la validation.', style: TextStyle(height: 1.35))),
            ]),
          ),
          if (operation != null) ...[
            const SizedBox(height: 12),
            SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(operation.userName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(formatMoney(operation.amount, operation.currency), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.brand)),
              Text('Jeton ${operation.tokenCode ?? code.text}'),
              Text('Statut : ${statusLabel(operation.status, type: operation.type)}', style: const TextStyle(color: AppColors.muted)),
              if (preview?['error'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(preview!['error'].toString(), style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700))),
            ])),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: GhostButton(label: 'Refuser', onPressed: code.text.trim().isEmpty ? null : () => runAction(context, _refuse))),
            const SizedBox(width: 8),
            Expanded(child: PrimaryButton(label: 'Valider l’opération', icon: Icons.arrow_forward_rounded, onPressed: code.text.trim().isEmpty ? null : () => runAction(context, _validate))),
          ]),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: selected
          ? FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18),
              label: Text(label),
              style: FilledButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
            )
          : TextButton.icon(onPressed: onTap, icon: Icon(icon, size: 18, color: AppColors.night), label: Text(label, style: const TextStyle(color: AppColors.night, fontWeight: FontWeight.w700))),
    );
  }
}

class _ScanCorners extends CustomPainter {
  const _ScanCorners();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const length = 28.0;
    final corners = [Offset.zero, Offset(size.width, 0), Offset(size.width, size.height), Offset(0, size.height)];
    final signs = [(1.0, 1.0), (-1.0, 1.0), (-1.0, -1.0), (1.0, -1.0)];
    for (var i = 0; i < corners.length; i++) {
      canvas.drawLine(corners[i], corners[i] + Offset(signs[i].$1 * length, 0), paint);
      canvas.drawLine(corners[i], corners[i] + Offset(0, signs[i].$2 * length), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LiquidityPage extends StatefulWidget {
  const LiquidityPage({super.key});

  @override
  State<LiquidityPage> createState() => _LiquidityPageState();
}

class _LiquidityPageState extends State<LiquidityPage> {
  late final usd = TextEditingController(text: context.read<AppController>().pdr?.usdDeclared.toString() ?? '0');
  late final cdf = TextEditingController(text: context.read<AppController>().pdr?.cdfDeclared.toStringAsFixed(0) ?? '0');
  late bool deposits = context.read<AppController>().pdr?.acceptsDeposits ?? true;
  late bool open = context.read<AppController>().pdr?.isOpen ?? true;
  late Set<String> networks = {...?context.read<AppController>().pdr?.networks};

  @override
  void dispose() {
    usd.dispose();
    cdf.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pdr = context.watch<AppController>().pdr;
    return Scaffold(
      appBar: AppBar(title: const Text('Liquidités')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (pdr != null) ...[
            _money('Déclarées', formatMoney(pdr.usdDeclared, 'USD'), formatMoney(pdr.cdfDeclared, 'CDF')),
            _money('Réservées', formatMoney(pdr.usdReserved, 'USD'), formatMoney(pdr.cdfReserved, 'CDF')),
            _money('Disponibles', formatMoney(pdr.usdAvailable, 'USD'), formatMoney(pdr.cdfAvailable, 'CDF')),
          ],
          const SizedBox(height: 12),
          TextField(controller: usd, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'USD déclarés')),
          TextField(controller: cdf, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'CDF déclarés')),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Accepter les dépôts'), value: deposits, onChanged: (value) => setState(() => deposits = value)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Point ouvert'), value: open, onChanged: (value) => setState(() => open = value)),
          const Text('Réseaux acceptés', style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 8, children: [
            for (final entry in const {'orange': 'Orange Money', 'airtel': 'Airtel Money', 'mpesa': 'M-Pesa', 'afrimoney': 'AfriMoney'}.entries)
              FilterChip(
                label: Text(entry.value),
                selected: networks.contains(entry.key),
                onSelected: (selected) => setState(() => selected ? networks.add(entry.key) : networks.remove(entry.key)),
              ),
          ]),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Enregistrer',
            onPressed: () => runAction(context, () => context.read<AppController>().updateAvailability({
                  'usd_declared': double.parse(usd.text.replaceAll(' ', '')),
                  'cdf_declared': double.parse(cdf.text.replaceAll(' ', '')),
                  'accepts_deposits': deposits,
                  'is_open': open,
                  'networks': networks.toList(),
                })),
          ),
        ],
      ),
    );
  }

  Widget _money(String title, String usd, String cdf) => SoftCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))), Text('$usd\n$cdf', textAlign: TextAlign.right)]),
      );
}

class PdrHistoryPage extends StatefulWidget {
  const PdrHistoryPage({super.key});

  @override
  State<PdrHistoryPage> createState() => _PdrHistoryPageState();
}

class _PdrHistoryPageState extends State<PdrHistoryPage> {
  String type = 'all';
  String? status;
  String? currency;

  @override
  Widget build(BuildContext context) {
    final items = context.watch<AppController>().operations.where((operation) {
      if (type != 'all' && operation.type != type) return false;
      if (status != null && operation.status != status) return false;
      if (currency != null && operation.currency != currency) return false;
      return true;
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Historique marchand', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('Tout'), selected: type == 'all', onSelected: (_) => setState(() => type = 'all')),
          ChoiceChip(label: const Text('Retraits'), selected: type == 'withdrawal', onSelected: (_) => setState(() => type = 'withdrawal')),
          ChoiceChip(label: const Text('Dépôts'), selected: type == 'deposit', onSelected: (_) => setState(() => type = 'deposit')),
          ChoiceChip(label: const Text('USD'), selected: currency == 'USD', onSelected: (_) => setState(() => currency = currency == 'USD' ? null : 'USD')),
          ChoiceChip(label: const Text('CDF'), selected: currency == 'CDF', onSelected: (_) => setState(() => currency = currency == 'CDF' ? null : 'CDF')),
        ]),
        const SizedBox(height: 8),
        DropdownButton<String?>(
          value: status,
          hint: const Text('Statut'),
          items: [const DropdownMenuItem<String?>(value: null, child: Text('Tous les statuts')), ...statusLabels.keys.map((key) => DropdownMenuItem(value: key, child: Text(statusLabels[key]!)))],
          onChanged: (value) => setState(() => status = value),
        ),
        ...items.map((operation) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${operation.userName} · ${formatMoney(operation.amount, operation.currency)}'),
              subtitle: Text('${operation.isWithdrawal ? 'Retrait' : 'Dépôt'} · ${formatDate(operation.createdAt)}'),
              trailing: StatusPill(status: operation.status, type: operation.type),
            )),
      ],
    );
  }
}

class RatingsPage extends StatelessWidget {
  const RatingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ratings = context.watch<AppController>().ratings;
    final pdr = context.watch<AppController>().pdr;
    return Scaffold(
      appBar: AppBar(title: const Text('Évaluations')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Note moyenne ${pdr?.ratingAvg.toStringAsFixed(1) ?? '-'} / 5', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ...ratings.map((rating) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(rating.userName, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('★' * rating.stars, style: const TextStyle(color: AppColors.brand)),
                  if (rating.comment.isNotEmpty) Text(rating.comment),
                  Text(formatDate(rating.createdAt), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ])),
              )),
        ],
      ),
    );
  }
}

class _PdrNotes extends StatelessWidget {
  const _PdrNotes();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: NotificationFeed(
        items: controller.notifications,
        onReadAll: () => runAction(context, controller.markAllRead),
        onOpen: (item) async {
          if (!item.isRead) await runAction(context, () => controller.markRead(item.id));
          if (!context.mounted || item.operationId == null) return;
          Navigator.push(context, MaterialPageRoute(builder: (_) => PdrRequestPage(operationId: item.operationId!)));
        },
      ),
    );
  }
}
