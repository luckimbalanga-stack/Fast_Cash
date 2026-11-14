import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../models/models.dart';
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
  int? _shownCallId;
  bool _openingCall = false;

  int _offerSeconds(AppController controller) => controller.settings.pdrOfferSeconds.clamp(5, 120);

  CashOperation? _liveIncoming(AppController controller) {
    final wait = _offerSeconds(controller);
    final candidates = controller.operations.where((op) => IncomingRequestCall.isLive(op, wait)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return candidates.isEmpty ? null : candidates.first;
  }

  Future<void> _ensureIncomingCall(CashOperation? incoming) async {
    if (!mounted || _openingCall) return;
    if (incoming == null) return;
    if (_shownCallId == incoming.id) return;

    _openingCall = true;
    _shownCallId = incoming.id;
    final operationId = incoming.id;
    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<AppController>();

    try {
      await showGeneralDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: Colors.black,
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return PopScope(
            canPop: false,
            child: Consumer<AppController>(
              builder: (context, liveController, _) {
                final wait = _offerSeconds(liveController);
                final current = liveController.operationById(operationId);
                if (current == null || !IncomingRequestCall.isLive(current, wait)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (dialogContext.mounted && Navigator.of(dialogContext, rootNavigator: true).canPop()) {
                      Navigator.of(dialogContext, rootNavigator: true).pop();
                    }
                  });
                  return const SizedBox.shrink();
                }
                return IncomingRequestCall(
                  key: ValueKey('incoming-$operationId-$wait'),
                  operation: current,
                  waitSeconds: wait,
                  onExpired: () {
                    if (dialogContext.mounted && Navigator.of(dialogContext, rootNavigator: true).canPop()) {
                      Navigator.of(dialogContext, rootNavigator: true).pop();
                    }
                  },
                  onAccept: () async {
                    try {
                      await liveController.postAction(operationId, 'accept');
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Demande acceptée. Elle apparaît dans Acceptées.')),
                      );
                    } on ApiException catch (error) {
                      messenger.showSnackBar(SnackBar(content: Text(error.message), backgroundColor: AppColors.danger));
                      rethrow;
                    }
                  },
                  onRefuse: () async {
                    try {
                      await liveController.postAction(operationId, 'refuse');
                    } on ApiException catch (error) {
                      messenger.showSnackBar(SnackBar(content: Text(error.message), backgroundColor: AppColors.danger));
                      rethrow;
                    }
                  },
                );
              },
            ),
          );
        },
      );
    } finally {
      if (_shownCallId == operationId) _shownCallId = null;
      _openingCall = false;
      if (mounted && _liveIncoming(controller) != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ensureIncomingCall(_liveIncoming(controller));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final incoming = _liveIncoming(controller);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureIncomingCall(incoming));

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
    final today = controller.operations.where((operation) {
      final date = DateTime.parse(operation.createdAt).toLocal();
      final now = DateTime.now();
      return date.year == now.year && date.month == now.month && date.day == now.day;
    }).length;
    final accepted = controller.operations.where(_isAcceptedRequest).length;
    final completed = controller.operations.where(_isCompletedRequest).length;
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
          _Stat(value: '$accepted', label: 'Acceptées', color: const Color(0xFFE8F1FF)),
          const SizedBox(width: 8),
          _Stat(value: '$completed', label: 'Terminées', color: AppColors.mintSoft),
          const SizedBox(width: 8),
          _Stat(value: '$today', label: 'Aujourd’hui', color: AppColors.brandSoft),
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
        SoftCard(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PdrRequestsPage())),
          child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.handshake_outlined, color: AppColors.brand), title: const Text('Demandes acceptées'), subtitle: Text(accepted == 0 ? 'Aucune opération en cours' : '$accepted opération${accepted > 1 ? 's' : ''} en cours'), trailing: const Icon(Icons.chevron_right)),
        ),
        SoftCard(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PdrRequestsPage(initialTab: 1))),
          child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.check_circle_outline, color: AppColors.brand), title: const Text('Demandes terminées'), subtitle: Text(completed == 0 ? 'Aucune opération clôturée' : '$completed opération${completed > 1 ? 's' : ''} clôturée${completed > 1 ? 's' : ''}'), trailing: const Icon(Icons.chevron_right)),
        ),
        SoftCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PdrScanPage())), child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.qr_code_scanner, color: AppColors.brand), title: Text('Vérifier un jeton'), subtitle: Text('Uniquement pour les demandes que vous avez acceptées'), trailing: Icon(Icons.chevron_right))),
        SoftCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiquidityPage())), child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.account_balance_wallet_outlined, color: AppColors.brand), title: Text('Mes liquidités'), subtitle: Text('Solde disponible USD et CDF'), trailing: Icon(Icons.chevron_right))),
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

bool _isAcceptedRequest(CashOperation operation) => const {
      'pin_required',
      'accepted',
      'payment_pending',
      'payment_confirmed',
      'cash_delivered',
    }.contains(operation.status);

bool _isCompletedRequest(CashOperation operation) => operation.status == 'completed';

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
  CashOperation? result;
  String? errorMessage;
  bool manual = false;
  bool _busy = false;
  String? _lastScanned;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCode?.trim();
    if (initial != null && initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _processCode(initial));
    }
  }

  @override
  void dispose() {
    camera.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (manual || _busy) return;
    final value = capture.barcodes
        .map((item) => item.rawValue?.trim())
        .whereType<String>()
        .firstWhere((item) => item.isNotEmpty, orElse: () => '');
    if (value.isEmpty || value == _lastScanned) return;
    await _processCode(value);
  }

  Future<void> _processCode(String raw) async {
    if (_busy) return;
    final normalized = raw.trim().toUpperCase();
    if (normalized.isEmpty) return;
    _busy = true;
    _lastScanned = normalized;
    setState(() {
      code.text = normalized;
      result = null;
      errorMessage = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<AppController>();
    try {
      final preview = await controller.lookupToken(normalized);
      if (!mounted) return;
      if (preview['redeemable'] != true) {
        final message = preview['error']?.toString() ?? 'Ce jeton ne peut pas être validé.';
        setState(() {
          errorMessage = message;
          result = CashOperation.fromJson(preview);
        });
        messenger.showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.danger));
        return;
      }
      final completed = await controller.redeemToken(normalized);
      if (!mounted) return;
      setState(() => result = completed);
      final done = completed.isWithdrawal ? 'Retrait effectué' : 'Dépôt effectué';
      messenger.showSnackBar(SnackBar(content: Text(done), backgroundColor: AppColors.mint));
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException ? error.message : 'Lecture du jeton impossible.';
      setState(() => errorMessage = message);
      messenger.showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.danger));
      _lastScanned = null;
    } finally {
      if (mounted) setState(() => _busy = false);
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    final doneLabel = result == null
        ? null
        : result!.isWithdrawal
            ? 'Retrait effectué'
            : 'Dépôt effectué';
    return Scaffold(
      appBar: canPop ? AppBar(title: const Text('Vérifier le jeton')) : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const Text('Vérifier le token PDR', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.night)),
          const SizedBox(height: 6),
          const Text('Scannez le QR code du client : la demande est validée automatiquement.', style: TextStyle(color: AppColors.muted, height: 1.35)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _ModeButton(
                label: 'Scanner',
                icon: Icons.qr_code_scanner_rounded,
                selected: !manual,
                onTap: _busy
                    ? null
                    : () => setState(() {
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
                onTap: _busy
                    ? null
                    : () => setState(() {
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
                  if (_busy)
                    ColoredBox(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                ]),
              ),
            ),
          if (manual) ...[
            TextField(
              controller: code,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {
                result = null;
                errorMessage = null;
              }),
              decoration: InputDecoration(
                hintText: 'FC-4829-7714',
                filled: true,
                fillColor: AppColors.mist,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: _busy ? 'Traitement…' : 'Valider le code',
              onPressed: _busy || code.text.trim().isEmpty ? null : () => _processCode(code.text),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator(color: AppColors.brand)),
            ],
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
              Expanded(
                child: Text(
                  'Le scan lance la recherche puis clôture automatiquement la demande. Seul le PDR qui a accepté peut valider ce ticket.',
                  style: TextStyle(height: 1.35),
                ),
              ),
            ]),
          ),
          if (result != null) ...[
            const SizedBox(height: 12),
            SoftCard(
              color: result!.status == 'completed' ? AppColors.mintSoft : Colors.white,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (result!.status == 'completed' && doneLabel != null) ...[
                  Text(doneLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.mint)),
                  const SizedBox(height: 8),
                ],
                Text(result!.userName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(formatMoney(result!.amount, result!.currency), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.brand)),
                Text('Jeton ${result!.tokenCode ?? code.text}'),
                Text('Statut : ${statusLabel(result!.status, type: result!.type)}', style: const TextStyle(color: AppColors.muted)),
                if (errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(errorMessage!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ] else if (errorMessage != null) ...[
            const SizedBox(height: 12),
            SoftCard(
              color: AppColors.dangerSoft,
              child: Text(errorMessage!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
            ),
          ],
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
  final VoidCallback? onTap;

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

class LiquidityPage extends StatelessWidget {
  const LiquidityPage({super.key});

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
          else
            SoftCard(
              color: AppColors.mintSoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Disponibles', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
                  const SizedBox(height: 10),
                  Text(formatMoney(pdr.usdAvailable, 'USD'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.night)),
                  const SizedBox(height: 6),
                  Text(formatMoney(pdr.cdfAvailable, 'CDF'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.night)),
                ],
              ),
            ),
        ],
      ),
    );
  }
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
    final historyStatuses = statusLabels.keys.where((key) => key != 'pending').toList();
    final items = context.watch<AppController>().operations.where((operation) {
      if (operation.status == 'pending') return false;
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
          value: status == 'pending' ? null : status,
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
          final operation = controller.operationById(item.operationId!);
          final wait = controller.settings.pdrOfferSeconds.clamp(5, 120);
          if (operation != null && IncomingRequestCall.isLive(operation, wait)) {
            Navigator.pop(context);
            return;
          }
          Navigator.push(context, MaterialPageRoute(builder: (_) => PdrRequestPage(operationId: item.operationId!)));
        },
      ),
    );
  }
}
