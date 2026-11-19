import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/pdr_call_alert.dart';
import '../../services/token_redeem.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'incoming_call.dart';

class PdrShell extends StatefulWidget {
  const PdrShell({super.key});

  @override
  State<PdrShell> createState() => _PdrShellState();
}

class _PdrShellState extends State<PdrShell> {
  int index = 0;
  int? _alertedCallId;

  @override
  Widget build(BuildContext context) {
    final incomingId = context.select<AppController, int?>((c) => c.liveIncomingOffer()?.id);
    if (incomingId != null && incomingId != _alertedCallId) {
      _alertedCallId = incomingId;
      final controller = context.read<AppController>();
      final incoming = controller.operationById(incomingId);
      if (incoming != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(PdrCallAlert.showIncomingCall(
            operation: incoming,
            waitSeconds: controller.pdrOfferSeconds,
          ));
        });
      }
    } else if (incomingId == null) {
      _alertedCallId = null;
    }

    final pages = [const PdrHomePage(), const PdrRequestsPage(), const PdrScanPage(), const PdrHistoryPage(), const PdrProfilePage()];
    return Scaffold(
      body: SafeArea(child: pages[index]),
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
    final recent = controller.operations.where(_isWithinLast24Hours);
    final today = recent.length;
    final accepted = recent.where(_isAcceptedRequest).length;
    final completed = recent.where(_isCompletedRequest).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(children: [
          const FastCashMark(size: 40, wordmark: true),
          const Spacer(),
          Tooltip(
            message: !pdr.hasAvailableLiquidity
                ? 'Liquidité ≤ seuil de couverture : statut verrouillé fermé'
                : (pdr.isOpen ? 'Ouvert — touchez pour fermer' : 'Fermé — touchez pour ouvrir'),
            child: Switch(
              value: pdr.hasAvailableLiquidity && pdr.isOpen,
              thumbColor: const WidgetStatePropertyAll(Colors.white),
              trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? AppColors.brand : AppColors.danger),
              trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
              onChanged: !pdr.hasAvailableLiquidity
                  ? null
                  : (value) => runAction(context, () => controller.updateAvailability({'is_open': value})),
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
              if (!pdr.hasAvailableLiquidity)
                const Text('Liquidité insuffisante — statut verrouillé fermé', style: TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w600)),
              Text('${pdr.address}, ${pdr.commune}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              Text('★ ${pdr.ratingAvg.toStringAsFixed(1)} · ${pdr.ratingCount} avis', style: const TextStyle(fontSize: 12)),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _Stat(value: '$accepted', label: 'Acceptées\n(24 h)', color: const Color(0xFFE8F1FF)),
          const SizedBox(width: 8),
          _Stat(value: '$completed', label: 'Terminées\n(24 h)', color: AppColors.mintSoft),
          const SizedBox(width: 8),
          _Stat(value: '$today', label: 'Total\n(24 h)', color: AppColors.brandSoft),
        ]),
        const SizedBox(height: 8),
        SoftCard(
          color: AppColors.mintSoft,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiquidityPage())),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Liquidités disponibles', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(formatMoney(pdr.cdfAvailable, 'CDF'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(height: 8),
        SoftCard(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PdrRequestsPage())),
          child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.handshake_outlined, color: AppColors.brand), title: const Text('Demandes acceptées'), subtitle: Text(accepted == 0 ? 'Aucune opération en cours' : '$accepted opération${accepted > 1 ? 's' : ''} en cours'), trailing: const Icon(Icons.chevron_right)),
        ),
        SoftCard(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PdrRequestsPage(initialTab: 1))),
          child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.check_circle_outline, color: AppColors.brand), title: const Text('Demandes terminées'), subtitle: Text(completed == 0 ? 'Aucune opération clôturée' : '$completed opération${completed > 1 ? 's' : ''} clôturée${completed > 1 ? 's' : ''}'), trailing: const Icon(Icons.chevron_right)),
        ),
        SoftCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PdrScanPage())), child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.qr_code_scanner, color: AppColors.brand), title: Text('Vérifier un jeton'), subtitle: Text('Uniquement pour les demandes que vous avez acceptées'), trailing: Icon(Icons.chevron_right))),
        SoftCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiquidityPage())), child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.account_balance_wallet_outlined, color: AppColors.brand), title: Text('Mes liquidités'), subtitle: Text('Solde disponible CDF'), trailing: Icon(Icons.chevron_right))),
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
        PrimaryButton(
          label: 'Se déconnecter',
          onPressed: () {
            unawaited(context.read<AppController>().logout());
          },
        ),
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
    return Expanded(
      child: SoftCard(
        color: color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.night)),
            Text(label, style: const TextStyle(fontSize: 12, height: 1.2)),
          ],
        ),
      ),
    );
  }
}

bool _isAcceptedRequest(CashOperation operation) => const {
      'pin_required',
      'accepted',
      'payment_pending',
      'payment_confirmed', // ticket prêt (retrait après PIN / dépôt dès acceptation)
      'cash_delivered',
    }.contains(operation.status);

bool _isCompletedRequest(CashOperation operation) => operation.status == 'completed';

bool _isWithinLast24Hours(CashOperation operation) {
  final date = DateTime.tryParse(operation.createdAt)?.toLocal();
  if (date == null) return false;
  return DateTime.now().difference(date) <= const Duration(hours: 24);
}

class PdrRequestsPage extends StatelessWidget {
  const PdrRequestsPage({super.key, this.initialTab = 0});

  /// 0 = Acceptées, 1 = Terminées
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final operations = context.watch<AppController>().operations;
    final acceptedCount = operations.where(_isAcceptedRequest).length;
    final completedCount = operations.where(_isCompletedRequest).length;
    final canPop = Navigator.canPop(context);
    final content = DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      child: Column(children: [
        if (!canPop) ...[
          const SizedBox(height: 8),
          const Text('Demandes', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
        ],
        TabBar(
          labelColor: AppColors.brand,
          indicatorColor: AppColors.brand,
          tabs: [
            Tab(text: acceptedCount > 0 ? 'Acceptées ($acceptedCount)' : 'Acceptées'),
            Tab(text: completedCount > 0 ? 'Terminées ($completedCount)' : 'Terminées'),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            _RequestList(
              match: _isAcceptedRequest,
              emptyLabel: 'Aucune demande acceptée en cours',
            ),
            _RequestList(
              match: _isCompletedRequest,
              emptyLabel: 'Aucune demande terminée',
            ),
          ]),
        ),
      ]),
    );
    if (!canPop) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Demandes')),
      body: content,
    );
  }
}

class _RequestList extends StatelessWidget {
  const _RequestList({required this.match, this.emptyLabel = 'Aucune demande'});
  final bool Function(CashOperation operation) match;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final items = context.watch<AppController>().operations.where(match).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (items.isEmpty) return Center(child: Text(emptyLabel, style: const TextStyle(color: AppColors.muted)));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final operation = items[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SoftCard(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PdrRequestPage(operationId: operation.id))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(operation.userName, style: const TextStyle(fontWeight: FontWeight.w800))), StatusPill(status: operation.status, type: operation.type)]),
              Text('${operation.isWithdrawal ? 'Retrait' : 'Dépôt'} · ${formatMoney(operation.amount, operation.currency)}'),
              Text('${operation.reference} · ${formatDate(operation.createdAt)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
        );
      },
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
          if (operation.status == 'pending') ...[
            const SizedBox(height: 16),
            SoftCard(
              color: AppColors.waitingSoft,
              child: const Text(
                'Cette demande s’affiche comme un appel entrant. Validez ou refusez depuis l’écran d’appel.',
                style: TextStyle(height: 1.4),
              ),
            ),
          ],
          if (operation.status == 'pin_required') ...[
            const SizedBox(height: 16),
            SoftCard(
              color: AppColors.brandSoft,
              child: const Text(
                'En attente du code PIN Mobile Money du client. La demande reste visible dans Acceptées.',
                style: TextStyle(height: 1.4),
              ),
            ),
          ],
          if (operation.status == 'completed') ...[
            const SizedBox(height: 16),
            SoftCard(
              color: AppColors.mintSoft,
              child: const Text('Cette demande est terminée.', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
          const SizedBox(height: 16),
          if (operation.tokenCode != null && operation.status == 'payment_confirmed')
            PrimaryButton(
              label: operation.isWithdrawal ? 'Vérifier le jeton' : 'Scanner / saisir le ticket',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PdrManualTokenPage(initialCode: operation.tokenCode))),
            ),
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
  final MobileScannerController camera = MobileScannerController(detectionSpeed: DetectionSpeed.normal, facing: CameraFacing.back);
  bool _busy = false;
  String? _lastScanned;
  String? _lastCode;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCode?.trim();
    if (initial != null && initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => PdrManualTokenPage(initialCode: initial)));
      });
    }
  }

  @override
  void dispose() {
    camera.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final value = capture.barcodes
        .map((item) => item.rawValue?.trim())
        .whereType<String>()
        .firstWhere((item) => item.isNotEmpty, orElse: () => '');
    if (value.isEmpty || value == _lastScanned) return;
    await _processScan(value);
  }

  Future<void> _processScan(String raw) async {
    if (_busy) return;
    final normalized = raw.trim().toUpperCase();
    if (normalized.isEmpty) return;
    setState(() {
      _busy = true;
      _lastScanned = normalized;
      _lastCode = normalized;
    });
    try {
      await camera.stop();
      if (!mounted) return;
      final ok = await TokenRedeemService(context.read<AppController>()).redeemAndShowDialog(context, normalized);
      if (!mounted) return;
      if (!ok) _lastScanned = null;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await camera.start();
      } else {
        _busy = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return Scaffold(
      appBar: canPop ? AppBar(title: const Text('Scanner le jeton')) : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          if (!canPop) ...[
            const Text('Scanner le jeton', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.night)),
            const SizedBox(height: 6),
          ],
          const Text(
            'Scannez le QR code du client : la validation se fait automatiquement. Le résultat s’affiche dans une fenêtre.',
            style: TextStyle(color: AppColors.muted, height: 1.35),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 280,
              child: Stack(fit: StackFit.expand, children: [
                MobileScanner(controller: camera, onDetect: _onDetect),
                const IgnorePointer(child: Center(child: SizedBox(width: 200, height: 200, child: CustomPaint(painter: _ScanCorners())))),
                if (_busy)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
              ]),
            ),
          ),
          if (_lastCode != null) ...[
            const SizedBox(height: 12),
            SoftCard(child: Text('Dernier code lu : $_lastCode', style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
          const SizedBox(height: 12),
          SoftCard(
            color: const Color(0xFFFFF7F2),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, color: AppColors.brand),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Seul le PDR qui a accepté la demande peut valider ce ticket.',
                  style: TextStyle(height: 1.35),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Saisir le ticket manuellement',
            icon: Icons.dialpad_rounded,
            onPressed: _busy
                ? null
                : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PdrManualTokenPage())),
          ),
        ],
      ),
    );
  }
}

class PdrManualTokenPage extends StatefulWidget {
  const PdrManualTokenPage({super.key, this.initialCode});
  final String? initialCode;

  @override
  State<PdrManualTokenPage> createState() => _PdrManualTokenPageState();
}

class _PdrManualTokenPageState extends State<PdrManualTokenPage> {
  late final TextEditingController code = TextEditingController(text: widget.initialCode ?? '');
  bool _busy = false;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy || code.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await TokenRedeemService(context.read<AppController>()).redeemAndShowDialog(context, code.text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saisie manuelle')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Entrez le code du ticket puis appuyez sur Vérifier.',
            style: TextStyle(color: AppColors.muted, height: 1.35),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: code,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'FC-4829-7714',
              filled: true,
              fillColor: AppColors.mist,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: _busy ? 'Vérification…' : 'Vérifier',
            icon: Icons.verified_outlined,
            busy: _busy,
            onPressed: _busy || code.text.trim().isEmpty ? null : _verify,
          ),
        ],
      ),
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

class LiquidityPage extends StatelessWidget {
  const LiquidityPage({super.key});

  Future<void> _openRecharge(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _RechargeLiquidityDialog(),
    );
    if (!context.mounted || result == null) return;
    final ok = result['ok'] == true;
    final message = (result['message'] as String?) ?? (ok ? 'Recharge réussie.' : 'Transaction échouée.');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: ok ? AppColors.mint : AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pdr = context.watch<AppController>().pdr;
    return Scaffold(
      appBar: AppBar(title: const Text('Liquidités')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Solde disponible sur votre point de retrait.',
            style: TextStyle(color: AppColors.muted, height: 1.35),
          ),
          const SizedBox(height: 16),
          if (pdr == null)
            const SoftCard(child: Text('Point de retrait introuvable.'))
          else ...[
            SoftCard(
              color: AppColors.mintSoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Disponible (CDF)', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
                  const SizedBox(height: 10),
                  Text(formatMoney(pdr.cdfAvailable, 'CDF'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.night)),
                  const SizedBox(height: 12),
                  Text(
                    'Seuil du jour (${pdr.liquidityCoverPercent.toStringAsFixed(pdr.liquidityCoverPercent.truncateToDouble() == pdr.liquidityCoverPercent ? 0 : 1)} %) : ${formatMoney(pdr.liquidityCoverCdf, 'CDF')}',
                    style: const TextStyle(color: AppColors.muted, height: 1.35),
                  ),
                  if (!pdr.hasAvailableLiquidity) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Liquidité ≤ seuil de couverture : statut verrouillé sur fermé. Rajoutez de la liquidité pour pouvoir rouvrir le point.',
                      style: TextStyle(color: AppColors.danger, height: 1.35),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Rajouter liquidité',
              icon: Icons.add_card_outlined,
              onPressed: () => _openRecharge(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _RechargeLiquidityDialog extends StatefulWidget {
  const _RechargeLiquidityDialog();

  @override
  State<_RechargeLiquidityDialog> createState() => _RechargeLiquidityDialogState();
}

class _RechargeLiquidityDialogState extends State<_RechargeLiquidityDialog> {
  static const _operators = {
    'orange': 'Orange Money',
    'airtel': 'Airtel Money',
    'mpesa': 'M-Pesa',
    'afrimoney': 'AfriMoney',
  };

  String? network;
  final amountCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    amountCtrl.dispose();
    pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final selected = network;
    final amount = double.tryParse(amountCtrl.text.replaceAll(' ', '').replaceAll(',', '.'));
    final pin = pinCtrl.text.trim();
    if (selected == null) {
      setState(() => error = 'Choisissez un opérateur Mobile Money.');
      return;
    }
    if (amount == null || amount < 1000) {
      setState(() => error = 'Saisissez un montant d’au moins 1 000 CDF.');
      return;
    }
    if (pin.length < 4 || int.tryParse(pin) == null) {
      setState(() => error = 'Saisissez votre code PIN (4 à 6 chiffres).');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final recharge = await context.read<AppController>().rechargeLiquidity(
            network: selected,
            amount: amount,
            pin: pin,
          );
      if (!mounted) return;
      Navigator.pop(context, recharge);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = 'Impossible de finaliser la recharge.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rajouter liquidité'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Simulez une recharge Mobile Money vers votre compte virtuel CDF.',
              style: TextStyle(color: AppColors.muted, height: 1.35),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: network,
              decoration: const InputDecoration(labelText: 'Opérateur Mobile Money'),
              items: [
                for (final entry in _operators.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: busy ? null : (value) => setState(() => network = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Montant (CDF)', hintText: 'Ex. 50000'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              enabled: !busy,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'Code PIN Mobile Money', counterText: ''),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(color: AppColors.danger, height: 1.3)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Confirmer'),
        ),
      ],
    );
  }
}

class PdrHistoryPage extends StatefulWidget {
  const PdrHistoryPage({super.key});

  @override
  State<PdrHistoryPage> createState() => _PdrHistoryPageState();
}

class _PdrHistoryPageState extends State<PdrHistoryPage> {
  static const _finalStatuses = {'completed', 'cancelled', 'refused'};

  String type = 'all';
  String? status;
  String? currency;

  @override
  Widget build(BuildContext context) {
    const historyStatuses = ['completed', 'cancelled', 'refused'];
    final items = context.watch<AppController>().operations.where((operation) {
      if (!_finalStatuses.contains(operation.status)) return false;
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
          value: status != null && _finalStatuses.contains(status) ? status : null,
          hint: const Text('Statut'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Tous les statuts')),
            ...historyStatuses.map((key) => DropdownMenuItem(value: key, child: Text(statusLabels[key]!))),
          ],
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

class RatingsPage extends StatefulWidget {
  const RatingsPage({super.key});

  @override
  State<RatingsPage> createState() => _RatingsPageState();
}

class _RatingsPageState extends State<RatingsPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await context.read<AppController>().loadRatings();
      } catch (_) {}
      if (mounted) setState(() => _loading = false);
    });
  }

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
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppColors.brand)))
          else if (ratings.isEmpty)
            const Text('Aucun avis pour le moment.', style: TextStyle(color: AppColors.muted))
          else
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
          final operation = controller.operationById(item.operationId!);
          final wait = controller.settings.pdrOfferSeconds.clamp(5, 120);
          if (operation != null && IncomingRequestCall.isLive(operation, wait)) {
            Navigator.pop(context);
            await PdrCallAlert.showIncomingCall(operation: operation, waitSeconds: wait);
            return;
          }
          Navigator.push(context, MaterialPageRoute(builder: (_) => PdrRequestPage(operationId: item.operationId!)));
        },
      ),
    );
  }
}
