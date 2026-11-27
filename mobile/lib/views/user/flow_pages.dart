import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../controllers/app_controller.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'user_pages.dart';

class AmountPage extends StatefulWidget {
  const AmountPage({super.key, required this.type});
  final String type;

  @override
  State<AmountPage> createState() => _AmountPageState();
}

class _AmountPageState extends State<AmountPage> {
  final amount = TextEditingController();
  String currency = 'USD';
  bool busy = false;
  SearchResult? result;

  bool get isWithdrawal => widget.type == 'withdrawal';

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  double? get value {
    final parsed = double.tryParse(amount.text.replaceAll(',', '.').replaceAll(' ', ''));
    if (parsed == null || parsed <= 0) return null;
    if (currency == 'USD' && parsed < 1) return null;
    if (currency == 'CDF' && parsed < 1000) return null;
    return parsed;
  }

  Future<void> _search() async {
    final controller = context.read<AppController>();
    final phone = controller.activePhone;
    if (phone == null || value == null) return;
    setState(() => busy = true);
    try {
      final position = await _position();
      final found = await controller.searchPdr(
        lat: position.$1,
        lng: position.$2,
        kind: widget.type,
        currency: currency,
        amount: value!,
        network: phone.network,
        simulated: position.$3,
        maxM: controller.searchRadiusM,
      );
      setState(() => result = found);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<(double, double, bool)> _position() async {
    const kinLat = -4.3038;
    const kinLng = 15.3005;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return (kinLat, kinLng, true);
      }
      final current = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 8));
      final far = Geolocator.distanceBetween(current.latitude, current.longitude, kinLat, kinLng) > 30000;
      if (far) return (kinLat, kinLng, true);
      return (current.latitude, current.longitude, false);
    } catch (_) {
      return (kinLat, kinLng, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final phone = controller.activePhone;
    final rate = controller.settings.usdCdfRate;
    final indicative = value == null ? null : currency == 'USD' ? value! * rate : value! / rate;
    final canProceed = result != null && result!.results.isNotEmpty && phone != null && value != null;
    return Scaffold(
      appBar: AppBar(title: const FastCashMark(size: 34, wordmark: true), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              children: [
                Text(isWithdrawal ? 'Retirer de l’argent' : 'Déposer de l’argent', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.night)),
                const SizedBox(height: 6),
                Text(isWithdrawal ? 'Trouvez un PDR près de vous pour retirer votre argent dans la monnaie choisie.' : 'Trouvez un PDR capable de recevoir vos espèces, sans conversion imposée.', style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 16),
                SoftCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Expanded(child: Text('Numéro Mobile Money', style: TextStyle(color: AppColors.muted, fontSize: 12))),
                      TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NumbersPage())), child: const Text('Modifier')),
                    ]),
                    Text(formatPhone(phone?.phone ?? ''), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    if (phone != null) NetworkBadge(network: phone.network, label: phone.networkLabel),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: amount,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() => result = null),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]'))],
                          decoration: InputDecoration(labelText: isWithdrawal ? 'Montant à retirer' : 'Montant à déposer', filled: true, fillColor: AppColors.mist, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: currency,
                        items: const [DropdownMenuItem(value: 'USD', child: Text('USD')), DropdownMenuItem(value: 'CDF', child: Text('CDF'))],
                        onChanged: (value) => setState(() {
                          currency = value ?? 'USD';
                          result = null;
                        }),
                      ),
                    ]),
                    if (indicative != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('Équivalent indicatif : ${currency == 'USD' ? formatMoney(indicative, 'CDF') : formatMoney(indicative, 'USD')} — aucune conversion imposée.', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ),
                    const SizedBox(height: 12),
                    PrimaryButton(label: 'Rechercher un PDR', icon: Icons.arrow_forward_rounded, busy: busy, onPressed: value == null ? null : () => runAction(context, _search)),
                  ]),
                ),
                if (result != null) ...[
                  const SizedBox(height: 16),
                  if (result!.simulated)
                    const InfoBanner(text: 'Localisation indisponible. La recherche est centrée sur Gombe, Kinshasa.'),
                  _NearbyOffer(
                    type: widget.type,
                    count: result!.results.length,
                    amount: value!,
                    currency: currency,
                  ),
                ],
              ],
            ),
          ),
          if (canProceed)
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: PrimaryButton(
                  label: 'Procéder à la demande',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DispatchPage(
                          type: widget.type,
                          points: result!.results,
                          amount: value!,
                          currency: currency,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

}

class _NearbyOffer extends StatelessWidget {
  const _NearbyOffer({required this.type, required this.count, required this.amount, required this.currency});
  final String type;
  final int count;
  final double amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final phone = controller.activePhone;
    final fee = amount * controller.settings.feePercent / 100;
    final shownFee = currency == 'CDF' ? fee.roundToDouble() : double.parse(fee.toStringAsFixed(2));
    final total = type == 'withdrawal' ? amount + shownFee : amount;
    final noun = count <= 1 ? 'point de retrait a été trouvé' : 'points de retrait ont été trouvés';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SoftCard(
        color: AppColors.brandSoft,
        child: Text(
          count == 0
              ? 'Aucun point de retrait ouvert dans un rayon de ${formatRadiusLabel(controller.searchRadiusM)} pour ce montant.'
              : '$count $noun à votre proximité.',
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.night, height: 1.35),
        ),
      ),
      if (count > 0) ...[
        const SizedBox(height: 12),
        Text(type == 'withdrawal' ? 'Demande de retrait' : 'Demande de dépôt', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.night)),
        const SizedBox(height: 6),
        Text(type == 'withdrawal' ? 'Voici le montant qui sera débité si vous lancez la demande.' : 'Voici les espèces à remettre au point de retrait.', style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 12),
        SoftCard(
          child: Column(children: [
            _moneyLine(type == 'withdrawal' ? 'Montant à retirer' : 'Espèces à remettre', formatMoney(amount, currency)),
            _moneyLine('Réseau', phone?.networkLabel ?? ''),
            _moneyLine('Numéro', formatPhone(phone?.phone ?? '')),
            _moneyLine('Frais de service', formatMoney(shownFee, currency)),
            const Divider(),
            _moneyLine(type == 'withdrawal' ? 'Total à débiter' : 'Transfert Mobile Money', formatMoney(total, currency), strong: true),
          ]),
        ),
      ],
    ]);
  }
}

/// Chronologie horizontale des actions en arrière-plan (retrait / dépôt).
class BackgroundActionStrip extends StatefulWidget {
  const BackgroundActionStrip({super.key, required this.type, this.status, this.busy = false});

  final String type;
  final String? status;
  final bool busy;

  @override
  State<BackgroundActionStrip> createState() => _BackgroundActionStripState();
}

class _BackgroundActionStripState extends State<BackgroundActionStrip> {
  final _scroll = ScrollController();
  int _visible = 0;
  Timer? _reveal;

  List<String> get _labels {
    if (widget.type == 'deposit') {
      return [
        'Demande envoyée au PDR',
        'Demande acceptée par le PDR',
        'Dépôt réussi — ticket prêt',
      ];
    }
    return [
      'Demande envoyée au PDR',
      'Demande acceptée par le PDR',
      'Saisir le code PIN',
      'Retrait accepté',
    ];
  }

  int _targetCount(String? status) {
    final maxSteps = _labels.length;
    switch (status) {
      case 'pin_required':
        return 3;
      case 'accepted':
      case 'payment_pending':
      case 'payment_confirmed':
      case 'cash_delivered':
      case 'completed':
        return maxSteps;
      case 'refused':
      case 'cancelled':
        return _visible.clamp(1, maxSteps);
      default:
        return 1; // pending / null
    }
  }

  void _syncVisible() {
    final target = _targetCount(widget.status);
    if (target <= _visible) {
      if (target < _visible && widget.status == 'pending') {
        setState(() => _visible = target);
      }
      return;
    }
    _reveal?.cancel();
    _reveal = Timer.periodic(const Duration(milliseconds: 480), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_visible >= target) {
        timer.cancel();
        return;
      }
      setState(() => _visible += 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _visible = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _visible = 1);
      _syncVisible();
    });
  }

  @override
  void didUpdateWidget(covariant BackgroundActionStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status || oldWidget.type != widget.type) {
      _syncVisible();
    }
  }

  @override
  void dispose() {
    _reveal?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = _labels;
    final activeIndex = (_visible - 1).clamp(0, labels.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Actions en arrière-plan', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.night, fontSize: 13)),
        const SizedBox(height: 10),
        SizedBox(
          height: 78,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            itemCount: _visible,
            separatorBuilder: (_, __) => const Padding(
              padding: EdgeInsets.only(top: 18),
              child: Icon(Icons.chevron_right_rounded, color: AppColors.brand, size: 22),
            ),
            itemBuilder: (context, index) {
              final done = index < activeIndex || (!widget.busy && _visible >= labels.length && index == activeIndex) || (widget.status != null && widget.status != 'pending' && index < _visible - 1);
              final current = index == activeIndex && (widget.busy || widget.status == 'pending' || widget.status == 'pin_required');
              return TweenAnimationBuilder<double>(
                key: ValueKey('step-$index-${labels[index]}'),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(offset: Offset(18 * (1 - value), 0), child: child),
                ),
                child: _TimelineChip(label: labels[index], done: done && !current, current: current),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TimelineChip extends StatelessWidget {
  const _TimelineChip({required this.label, required this.done, required this.current});
  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final color = current ? AppColors.brand : done ? AppColors.mint : AppColors.muted;
    final soft = current ? AppColors.brandSoft : done ? AppColors.mintSoft : AppColors.mist;
    return Container(
      width: 148,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(current ? Icons.hourglass_top_rounded : done ? Icons.check_circle_rounded : Icons.radio_button_unchecked, size: 16, color: color),
            const SizedBox(width: 6),
            Text(current ? 'En cours' : done ? 'Fait' : 'À venir', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.night, height: 1.25)),
        ],
      ),
    );
  }
}

class DispatchPage extends StatefulWidget {
  const DispatchPage({
    super.key,
    required this.type,
    required this.points,
    required this.amount,
    required this.currency,
    this.initialCursor = 0,
    this.initialOperationId,
  });

  final String type;
  final List<PdrPoint> points;
  final double amount;
  final String currency;
  final int initialCursor;
  final int? initialOperationId;

  factory DispatchPage.fromActive(ActiveDispatch active) => DispatchPage(
        type: active.type,
        points: active.points,
        amount: active.amount,
        currency: active.currency,
        initialCursor: active.cursor,
        initialOperationId: active.operationId,
      );

  @override
  State<DispatchPage> createState() => _DispatchPageState();
}

class _DispatchPageState extends State<DispatchPage> {
  AppController? _controller;
  late int _cursor;
  int? _operationId;
  int? _handledSkipId;
  bool _advancing = false;
  bool _started = false;
  bool _exhausted = false;
  bool _popupShown = false;
  bool _leaving = false;
  bool _cancelling = false;
  String? _error;
  Timer? _timeout;
  Timer? _fastPoll;

  int get _waitSeconds => (_controller?.settings.pdrOfferSeconds ?? 30).clamp(5, 120);

  @override
  void initState() {
    super.initState();
    _cursor = widget.initialCursor;
    _operationId = widget.initialOperationId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_started) return;
      _started = true;
      _syncActiveDispatch();
      if (_operationId != null) {
        final existing = _controller?.operationById(_operationId!);
        if (existing != null && existing.status == 'pending') {
          _armTimeout(_operationId!);
          return;
        }
        if (existing != null && existing.status == 'pin_required') {
          setState(() {});
          return;
        }
        if (existing != null && existing.status == 'payment_confirmed') {
          _leaveTo(TokenPage(operation: existing));
          return;
        }
        if (existing != null && (existing.status == 'cash_delivered' || existing.status == 'completed')) {
          _leaveTo(ReceivedPage(operation: existing, celebrate: true));
          return;
        }
        if (existing != null && (existing.status == 'cancelled' || existing.status == 'refused')) {
          _cursor += 1;
          _operationId = null;
        }
      }
      _offerNext();
    });
  }

  void _syncActiveDispatch() {
    _controller?.setActiveDispatch(
      ActiveDispatch(
        type: widget.type,
        points: widget.points,
        amount: widget.amount,
        currency: widget.currency,
        cursor: _cursor,
        operationId: _operationId,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.read<AppController>();
    if (!identical(next, _controller)) {
      _controller?.removeListener(_onOperations);
      _fastPoll?.cancel();
      _controller?.resumeSync();
      _controller = next;
      _controller!.pauseSync();
      _controller!.addListener(_onOperations);
      // Poll léger ops/notifs uniquement pendant le chaînage.
      _fastPoll = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!mounted || _exhausted || _leaving) return;
        unawaited(_controller?.refreshLight() ?? Future.value());
      });
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _fastPoll?.cancel();
    _controller?.removeListener(_onOperations);
    _controller?.resumeSync();
    super.dispose();
  }

  void _clearTimeout() {
    _timeout?.cancel();
    _timeout = null;
  }

  void _armTimeout(int operationId) {
    _clearTimeout();
    final wait = _waitSeconds;
    _timeout = Timer(Duration(seconds: wait), () {
      if (!mounted || _operationId != operationId || _advancing || _exhausted) return;
      final operation = _controller?.operationById(operationId);
      if (operation != null && operation.status != 'pending') return;
      _skipCurrent(cancel: true);
    });
  }

  void _leaveTo(Widget page, {Duration delay = Duration.zero}) {
    if (_leaving || !mounted) return;
    _leaving = true;
    _clearTimeout();
    _fastPoll?.cancel();
    _controller?.clearActiveDispatch();
    _controller?.resumeSync();
    Future<void>.delayed(delay, () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => page));
    });
  }

  Future<void> _cancelRequest() async {
    if (_cancelling || _leaving) return;
    setState(() => _cancelling = true);
    _clearTimeout();
    final currentId = _operationId;
    try {
      if (currentId != null) {
        final operation = _controller?.operationById(currentId);
        // Annulation seulement avant le ticket (pending / PIN).
        final cancellable = operation == null ||
            operation.status == 'pending' ||
            operation.status == 'pin_required';
        if (cancellable) {
          await _controller?.postAction(currentId, 'cancel');
        }
      }
    } catch (_) {}
    _controller?.clearActiveDispatch();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  bool _shouldAdvancePast(CashOperation operation) {
    return operation.status == 'refused' || operation.status == 'cancelled';
  }

  void _onOperations() {
    if (!mounted || _operationId == null || _advancing || _exhausted || _leaving) return;
    final operation = _controller?.operationById(_operationId!);
    if (operation == null) return;
    if (_shouldAdvancePast(operation)) {
      if (_handledSkipId == operation.id) return;
      _clearTimeout();
      _handledSkipId = operation.id;
      _cursor += 1;
      _offerNext();
      return;
    }
    if (operation.status == 'payment_confirmed') {
      _leaveTo(TokenPage(operation: operation));
      return;
    }
    if (operation.status == 'cash_delivered' || operation.status == 'completed') {
      _leaveTo(ReceivedPage(operation: operation, celebrate: true));
      return;
    }
    if (operation.status != 'pending') {
      _clearTimeout();
    }
  }

  Future<void> _skipCurrent({required bool cancel}) async {
    if (_advancing) return;
    _clearTimeout();
    final currentId = _operationId;
    if (currentId != null) _handledSkipId = currentId;
    // Annulation en arrière-plan : on passe immédiatement au PDR suivant.
    if (cancel && currentId != null) {
      unawaited(() async {
        try {
          final operation = _controller?.operationById(currentId);
          if (operation == null || operation.status == 'pending') {
            await _controller?.postAction(currentId, 'cancel');
          }
        } catch (_) {}
      }());
    }
    if (!mounted) return;
    _cursor += 1;
    _syncActiveDispatch();
    await _offerNext();
  }

  Future<void> _showNoPdrPopup() async {
    if (_popupShown || !mounted) return;
    _popupShown = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Aucun PDR trouvé', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.night)),
          content: const Text(
            'Aucun point de retrait n’a validé votre demande dans le délai imparti. Réessayez un peu plus tard ou changez de montant.',
            style: TextStyle(color: AppColors.muted, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                if (mounted) Navigator.pop(context);
              },
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.brand)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _offerNext() async {
    if (_advancing) return;
    final phone = _controller?.activePhone;
    if (phone == null) {
      setState(() => _error = 'Choisissez un numéro Mobile Money vérifié.');
      return;
    }
    if (_cursor >= widget.points.length) {
      setState(() => _exhausted = true);
      _controller?.clearActiveDispatch();
      WidgetsBinding.instance.addPostFrameCallback((_) => _showNoPdrPopup());
      return;
    }
    _advancing = true;
    try {
      final point = widget.points[_cursor];
      final created = await _controller!.createOperation(
        pdrId: point.id,
        phone: phone.phone,
        amount: widget.amount,
        currency: widget.currency,
        type: widget.type,
      );
      if (!mounted) return;
      setState(() {
        _operationId = created.id;
        _error = null;
      });
      _syncActiveDispatch();
      if (created.status == 'pending') {
        _armTimeout(created.id);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error is ApiException ? error.message : 'La demande n’a pas pu être envoyée.');
      _cursor += 1;
      _syncActiveDispatch();
      _advancing = false;
      await _offerNext();
      return;
    } finally {
      _advancing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final operation = _operationId == null ? null : context.watch<AppController>().operationById(_operationId!);
    if (!_leaving && operation != null) {
      // Laisse le temps à la chronologie d’afficher « Retrait/Dépôt accepté ».
      const hold = Duration(milliseconds: 1600);
      if (operation.status == 'payment_confirmed') {
        _leaveTo(TokenPage(operation: operation), delay: hold);
      } else if (operation.status == 'cash_delivered' || operation.status == 'completed') {
        _leaveTo(ReceivedPage(operation: operation, celebrate: true), delay: hold);
      }
    }
    final waitingPin = operation?.status == 'pin_required';
    final buffering = !_exhausted && _error == null && !waitingPin;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        // Retour : la demande continue en arrière-plan (reprise via notifs).
        if (!_leaving && !_exhausted) _syncActiveDispatch();
      },
      child: Scaffold(
        appBar: AppBar(title: const FastCashMark(size: 34, wordmark: true), centerTitle: true),
        body: SafeArea(
          minimum: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(children: [
                    BackgroundActionStrip(
                      type: widget.type,
                      status: operation?.status,
                      busy: buffering || waitingPin,
                    ),
                    const Spacer(),
                    if (buffering) const SizedBox(width: 72, height: 72, child: CircularProgressIndicator(strokeWidth: 5, color: AppColors.brand)),
                    if (waitingPin) const Icon(Icons.lock_outline_rounded, size: 64, color: AppColors.brand),
                    const SizedBox(height: 22),
                    Text(
                      _exhausted ? 'Aucun point n’a accepté' : waitingPin ? 'Code PIN requis' : 'Demande en cours',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.night),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error ??
                          (_exhausted
                              ? 'Aucun point de retrait n’a accepté cette demande dans un rayon de ${formatRadiusLabel(context.read<AppController>().searchRadiusM)}.'
                              : waitingPin
                                  ? 'Un point de retrait a accepté. Saisissez votre code PIN à 4 chiffres pour continuer.'
                                  : 'Chaque point dispose de $_waitSeconds secondes pour valider. Sinon la demande passe au suivant.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted, height: 1.4),
                    ),
                    const Spacer(),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (waitingPin && operation != null)
                      PrimaryButton(label: 'Saisir le code PIN', icon: Icons.lock_outline_rounded, onPressed: () => showPinDialog(context, operation)),
                    if (!_exhausted && _error == null) ...[
                      if (waitingPin && operation != null) const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: TextButton(
                          onPressed: _cancelling ? null : () => runAction(context, _cancelRequest),
                          child: Text(
                            _cancelling ? 'Annulation…' : 'Annuler la demande',
                            style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                    if (_error != null && !_exhausted)
                      PrimaryButton(label: 'Retour', onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SummaryPage extends StatelessWidget {
  const SummaryPage({super.key, required this.type, required this.point, required this.amount, required this.currency});
  final String type;
  final PdrPoint point;
  final double amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final phone = controller.activePhone;
    final fee = amount * controller.settings.feePercent / 100;
    final shownFee = currency == 'CDF' ? fee.roundToDouble() : double.parse(fee.toStringAsFixed(2));
    final total = type == 'withdrawal' ? amount + shownFee : amount;
    return Scaffold(
      appBar: AppBar(title: const FastCashMark(size: 34, wordmark: true), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              children: [
                Text(type == 'withdrawal' ? 'Demande de retrait' : 'Demande de dépôt', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.night)),
                const SizedBox(height: 6),
                const Text('Vérifiez les informations avant d’envoyer votre demande.', style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 16),
                SoftCard(
                  child: Row(children: [
                    const KioskThumb(),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('PDR sélectionné', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700, fontSize: 12)),
                      Text(point.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text('${point.address}, ${point.commune}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ])),
                  ]),
                ),
                const SizedBox(height: 12),
                SoftCard(
                  child: Column(children: [
                    _line(type == 'withdrawal' ? 'Montant à retirer' : 'Espèces à remettre', formatMoney(amount, currency)),
                    _line('Réseau', phone?.networkLabel ?? ''),
                    _line('Numéro', formatPhone(phone?.phone ?? '')),
                    _line('Frais de service', formatMoney(shownFee, currency)),
                    const Divider(),
                    _line(type == 'withdrawal' ? 'Total à payer' : 'Transfert Mobile Money', formatMoney(total, currency), strong: true),
                  ]),
                ),
                const SizedBox(height: 8),
                const Text('Les frais sont distincts du montant remis en espèces. Aucun code PIN n’est demandé.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: PrimaryButton(
                label: 'Envoyer la demande',
                icon: Icons.arrow_forward_rounded,
                onPressed: phone == null
                    ? null
                    : () => runAction(context, () async {
                          final created = await context.read<AppController>().createOperation(pdrId: point.id, phone: phone.phone, amount: amount, currency: currency, type: type);
                          if (!context.mounted) return;
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => FollowPage(operationId: created.id)));
                        }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: strong ? AppColors.brand : AppColors.night)),
      ]),
    );
  }
}

Future<void> showPinDialog(BuildContext context, CashOperation operation) {
  final pin = TextEditingController();
  var busy = false;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setLocal) {
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Autoriser l’opération', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.night)),
                  const SizedBox(height: 6),
                  const Text('Saisissez les 4 chiffres de votre code PIN Mobile Money. Ce code prépare l’ordre opérateur et n’est pas enregistré.', style: TextStyle(color: AppColors.muted, height: 1.35)),
                  const SizedBox(height: 16),
                  _pinLine('Votre numéro', formatPhone(operation.phone)),
                  _pinLine('Numéro du point', formatPhone(operation.pdrPhone)),
                  _pinLine('Montant', formatMoney(operation.amount, operation.currency)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pin,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                    decoration: InputDecoration(
                      labelText: 'Code PIN à 4 chiffres',
                      filled: true,
                      fillColor: AppColors.mist,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('Plus tard'))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Confirmer',
                        busy: busy,
                        onPressed: busy
                            ? null
                            : () async {
                                if (pin.text.length != 4) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saisissez les 4 chiffres du code PIN.'), backgroundColor: AppColors.danger));
                                  return;
                                }
                                setLocal(() => busy = true);
                                final controller = context.read<AppController>();
                                final code = pin.text;
                                final id = operation.id;
                                // Fermer d’abord la boîte : sinon le rebuild vers l’écran jeton plante le Provider.
                                if (dialogContext.mounted) Navigator.pop(dialogContext);
                                try {
                                  await controller.postAction(id, 'authorize', body: {'pin': code});
                                } catch (error) {
                                  if (!context.mounted) return;
                                  final message = error is ApiException ? error.message : 'L’autorisation a échoué.';
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.danger));
                                  final fresh = context.read<AppController>().operationById(id);
                                  if (fresh != null && fresh.status == 'pin_required') {
                                    await showPinDialog(context, fresh);
                                  }
                                }
                              },
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(pin.dispose);
}

Widget _moneyLine(String label, String value, {bool strong = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
      Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: strong ? AppColors.brand : AppColors.night)),
    ]),
  );
}

Widget _pinLine(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.night)),
    ]),
  );
}

/// Page cible selon le statut (notif, historique, reprise).
Widget operationLandingPage(
  CashOperation operation, {
  bool celebrate = false,
  bool fromNotification = false,
}) {
  if (operation.status == 'payment_confirmed') {
    return TokenPage(operation: operation);
  }
  if (operation.status == 'cash_delivered' || operation.status == 'completed') {
    return ReceivedPage(operation: operation, celebrate: celebrate);
  }
  return FollowPage(operationId: operation.id, fromNotification: fromNotification);
}

class FollowPage extends StatefulWidget {
  const FollowPage({super.key, required this.operationId, this.fromNotification = false});
  final int operationId;
  final bool fromNotification;

  @override
  State<FollowPage> createState() => _FollowPageState();
}

class _FollowPageState extends State<FollowPage> {
  bool _leaving = false;
  bool? _openedTerminal;

  void _leaveTo(Widget page, {Duration delay = Duration.zero}) {
    if (_leaving || !mounted) return;
    _leaving = true;
    Future<void>.delayed(delay, () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => page));
    });
  }

  @override
  Widget build(BuildContext context) {
    final operation = context.watch<AppController>().operationById(widget.operationId);
    if (operation == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final terminal = operation.status == 'cash_delivered' || operation.status == 'completed';
    final ticket = operation.status == 'payment_confirmed';
    final alreadyDone = terminal || ticket;
    _openedTerminal ??= alreadyDone;
    if (!_leaving && alreadyDone) {
      // Notif / déjà terminé → immédiat. Transition live → court délai.
      final fromLive = !widget.fromNotification && _openedTerminal == false;
      final delay = fromLive ? const Duration(milliseconds: 1600) : Duration.zero;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _leaving) return;
        if (ticket) {
          _leaveTo(TokenPage(operation: operation), delay: delay);
        } else if (terminal) {
          _leaveTo(ReceivedPage(operation: operation, celebrate: fromLive), delay: delay);
        }
      });
    }
    return _StatusPage(operation: operation, showBackgroundActions: !widget.fromNotification);
  }
}

class _StatusPage extends StatelessWidget {
  const _StatusPage({required this.operation, this.showBackgroundActions = true});
  final CashOperation operation;
  final bool showBackgroundActions;

  @override
  Widget build(BuildContext context) {
    final refused = operation.status == 'refused';
    final waiting = operation.status == 'pending';
    final needsPin = operation.status == 'pin_required';
    final canCancel = waiting || needsPin;
    return Scaffold(
      appBar: AppBar(title: Text(operation.reference)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (showBackgroundActions) ...[
            BackgroundActionStrip(
              type: operation.type,
              status: operation.status,
              busy: waiting || needsPin,
            ),
            const SizedBox(height: 16),
          ],
          StatusPill(status: operation.status, type: operation.type),
          const SizedBox(height: 16),
          Text(_title(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.night)),
          const SizedBox(height: 8),
          Text(_body(), style: const TextStyle(color: AppColors.muted, height: 1.4)),
          const SizedBox(height: 16),
          SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(operation.pdrName, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('${operation.pdrAddress}, ${operation.pdrCommune}'),
            const SizedBox(height: 8),
            Text(formatMoney(operation.amount, operation.currency), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.brand)),
            Text('Frais ${formatMoney(operation.fees, operation.currency)} · ${operation.networkLabel}'),
          ])),
          const SizedBox(height: 16),
          if (waiting) const LinearProgressIndicator(color: AppColors.brand, backgroundColor: AppColors.brandSoft),
          if (needsPin)
            PrimaryButton(
              label: 'Saisir le code PIN',
              icon: Icons.lock_outline_rounded,
              onPressed: () => showPinDialog(context, operation),
            ),
          if (refused) _Alternatives(operation: operation),
        ],
      ),
      bottomNavigationBar: canCancel
          ? SafeArea(
              minimum: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: TextButton(
                    onPressed: () => runAction(context, () async {
                      await context.read<AppController>().postAction(operation.id, 'cancel');
                      if (context.mounted) Navigator.pop(context);
                    }),
                    child: const Text(
                      'Annuler la demande',
                      style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  String _title() {
    return switch (operation.status) {
      'pending' => 'En attente de validation',
      'refused' => 'Demande refusée',
      'pin_required' => 'Code PIN requis',
      'accepted' => 'Rendez-vous au point de retrait',
      'payment_confirmed' => operation.isWithdrawal ? 'Paiement confirmé' : 'Dépôt réussi',
      'cash_delivered' => 'Retrait effectué',
      'cancelled' => 'Demande annulée',
      'completed' => operation.isWithdrawal ? 'Retrait effectué' : 'Dépôt effectué',
      _ => 'Suivi de l’opération',
    };
  }

  String _body() {
    if (operation.status == 'pending') return 'La demande a été envoyée au ${operation.pdrName}. Cette page se met à jour dès que le vendeur répond.';
    if (operation.status == 'refused') return 'Le point sélectionné ne peut pas traiter cette demande. Choisissez un autre point de retrait.';
    if (operation.status == 'pin_required') return '${operation.pdrName} a accepté. Autorisez l’opération avec votre code PIN Mobile Money.';
    if (operation.status == 'payment_confirmed') {
      return operation.isWithdrawal
          ? 'Le paiement est confirmé. Présentez votre code QR au point de retrait.'
          : 'Votre dépôt est accepté. Présentez le ticket QR au ${operation.pdrName} pour finaliser.';
    }
    if (operation.status == 'cash_delivered' || (operation.isWithdrawal && operation.status == 'completed')) {
      return 'Retrait effectué au ${operation.pdrName}. Vous pouvez noter le point.';
    }
    if (!operation.isWithdrawal && operation.status == 'completed') {
      return 'Dépôt effectué au ${operation.pdrName}.';
    }
    if (operation.status == 'cancelled') return 'Cette demande a été annulée.';
    return 'Statut : ${statusLabel(operation.status, type: operation.type)}.';
  }
}

class _Alternatives extends StatefulWidget {
  const _Alternatives({required this.operation});
  final CashOperation operation;

  @override
  State<_Alternatives> createState() => _AlternativesState();
}

class _AlternativesState extends State<_Alternatives> {
  List<PdrPoint> points = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final controller = context.read<AppController>();
    final found = await controller.searchPdr(
      lat: -4.3038,
      lng: 15.3005,
      kind: widget.operation.type,
      currency: widget.operation.currency,
      amount: widget.operation.amount,
      network: widget.operation.network,
      simulated: true,
    );
    if (!mounted) return;
    setState(() => points = found.results.where((point) => point.id != widget.operation.pdrId && point.availableForRequest == true).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 12),
      ...points.map((point) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PdrTile(
              point: point,
              onDemand: () => runAction(context, () async {
                final created = await context.read<AppController>().createOperation(
                      pdrId: point.id,
                      phone: widget.operation.phone,
                      amount: widget.operation.amount,
                      currency: widget.operation.currency,
                      type: widget.operation.type,
                    );
                if (!context.mounted) return;
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => FollowPage(operationId: created.id)));
              }),
            ),
          )),
    ]);
  }
}

void goAppHome(BuildContext context) {
  Navigator.of(context).popUntil((route) => route.isFirst);
}

class TokenPage extends StatefulWidget {
  const TokenPage({super.key, required this.operation});
  final CashOperation operation;

  @override
  State<TokenPage> createState() => _TokenPageState();
}

class _TokenPageState extends State<TokenPage> {
  bool _leftToReceived = false;
  Timer? _fastPoll;

  @override
  void initState() {
    super.initState();
    // Poll rapide tant que le ticket est à l’écran (scan PDR → succès sans attendre 6–10 s).
    _fastPoll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _leftToReceived) return;
      unawaited(context.read<AppController>().refreshLight());
    });
  }

  @override
  void dispose() {
    _fastPoll?.cancel();
    super.dispose();
  }

  void _goReceivedIfDone(CashOperation live) {
    if (_leftToReceived) return;
    if (live.status != 'cash_delivered' && live.status != 'completed') return;
    _leftToReceived = true;
    _fastPoll?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ReceivedPage(operation: live, celebrate: true)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final live = context.watch<AppController>().operationById(widget.operation.id) ?? widget.operation;
    _goReceivedIfDone(live);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => goAppHome(context),
        ),
        title: const FastCashMark(size: 34, wordmark: true),
        centerTitle: true,
      ),
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 12),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            const Center(child: _SuccessBadge()),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: live.isWithdrawal ? 'Retrait prêt\n' : 'Dépôt réussi\n',
                  style: const TextStyle(color: AppColors.night),
                ),
                TextSpan(
                  text: live.isWithdrawal ? 'à présenter' : 'ticket à présenter',
                  style: const TextStyle(color: AppColors.brand),
                ),
              ]),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.1),
            ),
            const SizedBox(height: 8),
            Text(
              live.isWithdrawal
                  ? 'Présentez ce code QR au point de retrait\npour récupérer votre argent.'
                  : 'Présentez ce ticket QR au point de retrait\npour finaliser votre dépôt.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.35),
            ),
            const SizedBox(height: 16),
            SoftCard(
              child: Column(children: [
                _TokenQr(data: live.tokenCode ?? live.reference),
                const SizedBox(height: 8),
                Text(live.isWithdrawal ? 'Code de retrait' : 'Code de dépôt', style: const TextStyle(color: AppColors.muted)),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(live.tokenCode ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  IconButton(onPressed: () => Clipboard.setData(ClipboardData(text: live.tokenCode ?? '')), icon: const Icon(Icons.copy_rounded, color: AppColors.brand)),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: SoftCard(padding: const EdgeInsets.all(12), child: Column(children: [
                const Icon(Icons.account_balance_wallet_outlined, color: AppColors.brand),
                const SizedBox(height: 4),
                Text(live.isWithdrawal ? 'Montant à retirer' : 'Montant à déposer', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                Text(formatMoney(live.amount, live.currency), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]))),
              const SizedBox(width: 8),
              Expanded(child: SoftCard(padding: const EdgeInsets.all(12), child: Column(children: [
                const Icon(Icons.verified_rounded, color: AppColors.brand),
                const SizedBox(height: 4),
                const Text('Validité', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                Text(
                  live.tokenStatus == 'active' ? 'Jusqu’au scan' : (live.tokenStatus == 'used' ? 'Déjà scanné' : 'Actif'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ]))),
            ]),
            const SizedBox(height: 12),
            SoftCard(child: Row(children: [
              const KioskThumb(size: 78),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(live.pdrName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                Text('${live.pdrAddress}, ${live.pdrCommune}, Kinshasa', style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.3)),
                const SizedBox(height: 4),
                Text('Ouvert maintenant\n${live.pdrHours}', style: const TextStyle(fontSize: 12, height: 1.3)),
              ])),
            ])),
            const SizedBox(height: 16),
            Row(children: [
              if (NotificationFeed.destinationVisible(live.status)) ...[
                Expanded(
                  child: GhostButton(
                    label: 'Itinéraire',
                    icon: Icons.near_me_outlined,
                    onPressed: NotificationFeed.destinationEnabled(live.status)
                        ? () => openRoute(context, live)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: PrimaryButton(label: 'Voir détails', icon: Icons.receipt_long_outlined, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OperationDetailPage(operationId: live.id))))),
            ]),
            const SizedBox(height: 12),
            GhostButton(label: 'Retour', icon: Icons.home_outlined, onPressed: () => goAppHome(context)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
      child: const Icon(Icons.check_rounded, color: Colors.white, size: 46),
    );
  }
}

class _TokenQr extends StatelessWidget {
  const _TokenQr({required this.data});
  final String data;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      height: 210,
      child: CustomPaint(
        painter: const _CornerPainter(),
        child: Center(
          child: QrImageView(data: data, size: 168, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.night), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.night)),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const length = 22.0;
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];
    final signs = [
      (1.0, 1.0),
      (-1.0, 1.0),
      (-1.0, -1.0),
      (1.0, -1.0),
    ];
    for (var i = 0; i < corners.length; i++) {
      final origin = corners[i];
      final dx = signs[i].$1 * length;
      final dy = signs[i].$2 * length;
      canvas.drawLine(origin, origin + Offset(dx, 0), paint);
      canvas.drawLine(origin, origin + Offset(0, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ReceivedPage extends StatefulWidget {
  const ReceivedPage({super.key, required this.operation, this.celebrate = false});
  final CashOperation operation;
  /// Toast + popup note (première arrivée après scan). Faux à la réouverture via notif.
  final bool celebrate;

  @override
  State<ReceivedPage> createState() => _ReceivedPageState();
}

class _ReceivedPageState extends State<ReceivedPage> {
  bool _ratingPrompted = false;
  bool _successToastShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final controller = context.read<AppController>();
      // Récupère la notif « Retrait/Dépôt effectué » + statut à jour.
      await controller.refreshLight();
      if (!mounted) return;
      final live = controller.operationById(widget.operation.id) ?? widget.operation;
      if (widget.celebrate && !_successToastShown) {
        _successToastShown = true;
        final msg = live.isWithdrawal
            ? 'Retrait terminé avec succès.'
            : 'Dépôt terminé avec succès.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.night,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      if (_ratingPrompted) return;
      if (live.ratingStars != null) return;
      if (live.status != 'completed' && live.status != 'cash_delivered') return;
      _ratingPrompted = true;
      await showRatingDialog(context, live);
    });
  }

  @override
  Widget build(BuildContext context) {
    final live = context.watch<AppController>().operationById(widget.operation.id) ?? widget.operation;
    final title = live.isWithdrawal ? 'Retrait effectué' : 'Dépôt effectué';
    final body = live.isWithdrawal
        ? '${formatMoney(live.amount, live.currency)} ont été remis au ${live.pdrName}.'
        : '${formatMoney(live.amount, live.currency)} ont été déposés au ${live.pdrName}.';
    final needsRating = live.ratingStars == null;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => goAppHome(context)),
        title: const FastCashMark(size: 34, wordmark: true),
        centerTitle: true,
      ),
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Column(children: [
                  const Spacer(),
                  const Icon(Icons.check_circle, color: AppColors.mint, size: 72),
                  const SizedBox(height: 12),
                  Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.night)),
                  const SizedBox(height: 8),
                  Text(body, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.4)),
                  const Spacer(),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (needsRating) ...[
                    PrimaryButton(label: 'Noter le point', icon: Icons.star_rounded, onPressed: () => showRatingDialog(context, live)),
                    const SizedBox(height: 12),
                  ],
                  GhostButton(label: 'Retour', icon: Icons.home_outlined, onPressed: () => goAppHome(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showRatingDialog(BuildContext context, CashOperation operation) {
  var stars = 5;
  var busy = false;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setLocal) {
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Noter le point de retrait', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.night)),
                  const SizedBox(height: 8),
                  Text('Le scan a réussi. Quelle note donnez-vous à ${operation.pdrName} ?', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.35)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final selected = index < stars;
                      return IconButton(
                        onPressed: busy ? null : () => setLocal(() => stars = index + 1),
                        icon: Icon(selected ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.brand, size: 36),
                      );
                    }),
                  ),
                  Text(stars == 1 ? '1 étoile' : '$stars étoiles', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.night)),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Valider la note',
                    busy: busy,
                    onPressed: busy
                        ? null
                        : () => runAction(dialogContext, () async {
                            setLocal(() => busy = true);
                            try {
                              await dialogContext.read<AppController>().postAction(operation.id, 'rate', body: {'stars': stars, 'comment': ''});
                              if (dialogContext.mounted) Navigator.pop(dialogContext);
                            } catch (error) {
                              if (dialogContext.mounted) setLocal(() => busy = false);
                              rethrow;
                            }
                          }),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class RatingPage extends StatefulWidget {
  const RatingPage({super.key, required this.operation});
  final CashOperation operation;

  @override
  State<RatingPage> createState() => _RatingPageState();
}

class _RatingPageState extends State<RatingPage> {
  int stars = 5;
  final comment = TextEditingController();

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Évaluation')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              children: [
                Text('Comment s’est passée votre visite au ${widget.operation.pdrName} ?', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.night)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final selected = index < stars;
                    return IconButton(
                      onPressed: () => setState(() => stars = index + 1),
                      icon: Icon(selected ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.brand, size: 36),
                    );
                  }),
                ),
                TextField(
                  controller: comment,
                  maxLines: 4,
                  decoration: InputDecoration(hintText: 'Ajouter un commentaire', filled: true, fillColor: AppColors.mist, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: PrimaryButton(
                label: 'Valider l’évaluation',
                onPressed: () => runAction(context, () async {
                  await context.read<AppController>().postAction(widget.operation.id, 'rate', body: {'stars': stars, 'comment': comment.text});
                  if (!context.mounted) return;
                  Navigator.popUntil(context, (route) => route.isFirst);
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DepositConfirmedPage extends StatelessWidget {
  const DepositConfirmedPage({super.key, required this.operation});
  final CashOperation operation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => goAppHome(context)),
        title: const FastCashMark(size: 34, wordmark: true),
        centerTitle: true,
      ),
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Column(children: [
                  const Spacer(),
                  const Icon(Icons.payments_rounded, color: AppColors.mint, size: 72),
                  const SizedBox(height: 12),
                  const Text('Transfert préparé', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.night)),
                  const SizedBox(height: 8),
                  Text('L’ordre de ${formatMoney(operation.amount, operation.currency)} vers ${formatPhone(operation.phone)} (${operation.networkLabel}) est prêt. La session opérateur est clôturée.', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                  const Spacer(),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PrimaryButton(label: 'Évaluer le PDR', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RatingPage(operation: operation)))),
                  const SizedBox(height: 12),
                  GhostButton(label: 'Retour', icon: Icons.home_outlined, onPressed: () => goAppHome(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<(double, double)> _devicePosition() async {
  const kinLat = -4.3038;
  const kinLng = 15.3005;
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return (kinLat, kinLng);
    }
    final current = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 8));
    final far = Geolocator.distanceBetween(current.latitude, current.longitude, kinLat, kinLng) > 30000;
    if (far) return (kinLat, kinLng);
    return (current.latitude, current.longitude);
  } catch (_) {
    return (kinLat, kinLng);
  }
}

Future<void> openRoute(BuildContext context, CashOperation operation) async {
  final position = await _devicePosition();
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RoutePage(
        user: LatLng(position.$1, position.$2),
        pdr: LatLng(operation.pdrLat, operation.pdrLng),
        pdrName: operation.pdrName,
      ),
    ),
  );
}

class RoutePage extends StatefulWidget {
  const RoutePage({super.key, required this.user, required this.pdr, required this.pdrName});
  final LatLng user;
  final LatLng pdr;
  final String pdrName;

  @override
  State<RoutePage> createState() => _RoutePageState();
}

class _RoutePageState extends State<RoutePage> {
  final map = MapController();
  List<LatLng> route = [];
  bool road = false;

  @override
  void initState() {
    super.initState();
    route = [widget.user, widget.pdr];
    _loadRoad();
  }

  Future<void> _loadRoad() async {
    try {
      final uri = Uri.parse('https://router.project-osrm.org/route/v1/driving/${widget.user.longitude},${widget.user.latitude};${widget.pdr.longitude},${widget.pdr.latitude}?overview=full&geometries=geojson');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) return;
      final coords = ((routes.first as Map)['geometry'] as Map)['coordinates'] as List;
      final points = coords.map((item) {
        final pair = item as List;
        return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
      }).toList();
      if (!mounted || points.length < 2) return;
      setState(() {
        route = points;
        road = true;
      });
      _fit();
    } catch (_) {}
  }

  void _fit() {
    final bounds = LatLngBounds.fromPoints(route);
    map.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Itinéraire')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Text(road ? 'Parcours vers ${widget.pdrName}' : 'Parcours direct vers ${widget.pdrName}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.night)),
        ),
        Expanded(
          child: FlutterMap(
            mapController: map,
            options: MapOptions(initialCenter: widget.user, initialZoom: 14, onMapReady: _fit),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'cd.fastcash.fast_cash'),
              PolylineLayer(polylines: [Polyline(points: route, strokeWidth: 5, color: AppColors.brand)]),
              MarkerLayer(markers: [
                Marker(point: widget.user, width: 22, height: 22, child: Container(decoration: BoxDecoration(color: const Color(0xFF3B82F6), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)))),
                Marker(point: widget.pdr, width: 42, height: 42, child: const Icon(Icons.location_on, color: AppColors.brand, size: 40)),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}
