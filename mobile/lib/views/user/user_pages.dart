import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../controllers/app_controller.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'flow_pages.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String? commune;
  String? network;
  bool openOnly = true;
  LatLng? origin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppController>().loadDirectory();
      _locate();
    });
  }

  Future<void> _locate() async {
    const kinLat = -4.3038;
    const kinLng = 15.3005;
    var lat = kinLat;
    var lng = kinLng;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        final current = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 8));
        final far = Geolocator.distanceBetween(current.latitude, current.longitude, kinLat, kinLng) > 30000;
        if (!far) {
          lat = current.latitude;
          lng = current.longitude;
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => origin = LatLng(lat, lng));
  }

  double? _meters(PdrPoint point) {
    final here = origin;
    if (here == null) return point.distanceM;
    return const Distance().as(LengthUnit.Meter, here, LatLng(point.lat, point.lng));
  }

  @override
  Widget build(BuildContext context) {
    final points = context.watch<AppController>().directory.where((point) {
      if (commune != null && point.commune != commune) return false;
      if (openOnly && !point.isOpen) return false;
      if (network != null && !point.networks.contains(network)) return false;
      return true;
    }).toList();
    final communes = context.watch<AppController>().directory.map((point) => point.commune).toSet().toList()..sort();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const Text('Rechercher un PDR', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.night)),
        const SizedBox(height: 6),
        const Text('Points de retrait autour de vous, à Kinshasa.', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(label: const Text('Ouvert'), selected: openOnly, onSelected: (value) => setState(() => openOnly = value)),
            DropdownButton<String?>(
              value: commune,
              hint: const Text('Commune'),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('Toutes')), ...communes.map((item) => DropdownMenuItem(value: item, child: Text(item)))],
              onChanged: (value) => setState(() => commune = value),
            ),
            DropdownButton<String?>(
              value: network,
              hint: const Text('Réseau'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Tous')),
                DropdownMenuItem(value: 'orange', child: Text('Orange')),
                DropdownMenuItem(value: 'airtel', child: Text('Airtel')),
                DropdownMenuItem(value: 'mpesa', child: Text('M-Pesa')),
                DropdownMenuItem(value: 'afrimoney', child: Text('AfriMoney')),
              ],
              onChanged: (value) => setState(() => network = value),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(borderRadius: BorderRadius.circular(22), child: SizedBox(height: 240, child: PdrMap(points: points.where((point) => point.isOpen).toList(), center: origin ?? const LatLng(-4.34, 15.31), zoom: 13))),
        const SizedBox(height: 12),
        ...points.map((point) => Padding(padding: const EdgeInsets.only(bottom: 10), child: PdrTile(point: point, distanceM: _meters(point)))),
      ],
    );
  }
}

class PdrMap extends StatelessWidget {
  const PdrMap({super.key, required this.points, required this.center, this.zoom = 13, this.radiusM, this.onTap});
  final List<PdrPoint> points;
  final LatLng center;
  final double zoom;
  final int? radiusM;
  final ValueChanged<PdrPoint>? onTap;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: zoom),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'cd.fastcash.fast_cash'),
        if (radiusM != null)
          CircleLayer(circles: [
            CircleMarker(point: center, radius: radiusM!.toDouble(), useRadiusInMeter: true, color: AppColors.brand.withValues(alpha: 0.12), borderColor: AppColors.brand, borderStrokeWidth: 1.4),
          ]),
        MarkerLayer(
          markers: [
            Marker(point: center, width: 18, height: 18, child: Container(decoration: BoxDecoration(color: const Color(0xFF3B82F6), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
            ...points.map((point) {
              final available = point.availableForRequest ?? point.isOpen;
              return Marker(
                point: LatLng(point.lat, point.lng),
                width: 36,
                height: 36,
                child: GestureDetector(
                  onTap: () => onTap?.call(point),
                  child: Icon(Icons.location_on, color: available ? AppColors.mint : const Color(0xFF94A3B8), size: 34),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }
}

String _placeLine(PdrPoint point, double? distanceM) {
  final meters = distanceM ?? point.distanceM;
  final place = '${point.commune}, ${point.city}';
  if (meters == null) return place;
  return '$place · ${formatDistance(meters)}';
}

class PdrTile extends StatelessWidget {
  const PdrTile({super.key, required this.point, this.onDemand, this.distanceM});
  final PdrPoint point;
  final VoidCallback? onDemand;
  final double? distanceM;

  @override
  Widget build(BuildContext context) {
    final available = point.availableForRequest ?? point.isOpen;
    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KioskThumb(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(point.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                  Text(point.isOpen ? 'Ouvert' : 'Fermé', style: TextStyle(color: point.isOpen ? AppColors.mint : AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
                const SizedBox(height: 2),
                Text(_placeLine(point, distanceM), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 4),
                Text('★ ${point.ratingAvg.toStringAsFixed(1)} (${point.ratingCount} avis)', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                Text('USD ${groupDigits(point.usdAvailable)} · CDF ${groupDigits(point.cdfAvailable)}', style: const TextStyle(fontSize: 12, color: AppColors.night)),
                if (onDemand != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: available ? onDemand : null,
                      style: FilledButton.styleFrom(backgroundColor: AppColors.brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: const Text('Demander'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String type = 'all';
  String period = 'all';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final items = context.watch<AppController>().operations.where((operation) {
      if (type != 'all' && operation.type != type) return false;
      if (period == 'all') return true;
      final date = DateTime.parse(operation.createdAt).toLocal();
      final days = period == 'today' ? 0 : period == '7' ? 7 : 30;
      if (days == 0) return date.year == now.year && date.month == now.month && date.day == now.day;
      return now.difference(date).inDays <= days;
    }).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const Text('Historique', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.night)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('Tout'), selected: type == 'all', onSelected: (_) => setState(() => type = 'all')),
          ChoiceChip(label: const Text('Retraits'), selected: type == 'withdrawal', onSelected: (_) => setState(() => type = 'withdrawal')),
          ChoiceChip(label: const Text('Dépôts'), selected: type == 'deposit', onSelected: (_) => setState(() => type = 'deposit')),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('Aujourd’hui'), selected: period == 'today', onSelected: (_) => setState(() => period = 'today')),
          ChoiceChip(label: const Text('7 jours'), selected: period == '7', onSelected: (_) => setState(() => period = '7')),
          ChoiceChip(label: const Text('30 jours'), selected: period == '30', onSelected: (_) => setState(() => period = '30')),
          ChoiceChip(label: const Text('Tout'), selected: period == 'all', onSelected: (_) => setState(() => period = 'all')),
        ]),
        const SizedBox(height: 12),
        if (items.isEmpty) const Text('Aucune opération sur cette période.', style: TextStyle(color: AppColors.muted)),
        ...items.map((operation) {
          final hasToken = operation.isWithdrawal && (operation.tokenCode ?? '').isNotEmpty;
          final tokenReady = hasToken && operation.status == 'payment_confirmed' && operation.tokenStatus == 'active';
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SoftCard(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => tokenReady ? TokenPage(operation: operation) : OperationDetailPage(operationId: operation.id),
                ),
              ),
              child: Row(children: [
                CircleAvatar(backgroundColor: operation.isWithdrawal ? AppColors.brandSoft : AppColors.mintSoft, child: Icon(operation.isWithdrawal ? Icons.south_west : Icons.north_east, color: operation.isWithdrawal ? AppColors.brand : AppColors.mint)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(operation.isWithdrawal ? 'Retrait' : 'Dépôt', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${operation.pdrName} · ${formatDate(operation.createdAt)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  if (hasToken)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        tokenReady ? 'Jeton QR disponible' : 'Jeton ${operation.tokenCode}',
                        style: TextStyle(color: tokenReady ? AppColors.brand : AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(formatMoney(operation.amount, operation.currency), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  StatusPill(status: operation.status, type: operation.type),
                  if (tokenReady) ...[
                    const SizedBox(height: 4),
                    const Icon(Icons.qr_code_2_rounded, color: AppColors.brand, size: 18),
                  ],
                ]),
              ]),
            ),
          );
        }),
      ],
    );
  }
}

class OperationDetailPage extends StatelessWidget {
  const OperationDetailPage({super.key, required this.operationId});
  final int operationId;

  @override
  Widget build(BuildContext context) {
    final operation = context.watch<AppController>().operationById(operationId);
    if (operation == null) return const Scaffold(body: Center(child: Text('Opération introuvable')));
    final token = operation.tokenCode;
    final tokenReady = operation.isWithdrawal && token != null && token.isNotEmpty && operation.status == 'payment_confirmed' && operation.tokenStatus == 'active';
    final showQr = operation.isWithdrawal && token != null && token.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(operation.reference)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(formatMoney(operation.amount, operation.currency), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.night)),
          const SizedBox(height: 8),
          StatusPill(status: operation.status, type: operation.type),
          const SizedBox(height: 16),
          Text('${operation.pdrName}\n${operation.pdrAddress}, ${operation.pdrCommune}', style: const TextStyle(height: 1.4)),
          const SizedBox(height: 8),
          Text('Horaires : ${operation.pdrHours}', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 8),
          Text('${operation.networkLabel} · ${formatPhone(operation.phone)}', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 8),
          Text('Frais : ${formatMoney(operation.fees, operation.currency)}', style: const TextStyle(color: AppColors.muted)),
          Text('Total : ${formatMoney(operation.total, operation.currency)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          if (showQr) ...[
            const SizedBox(height: 16),
            SoftCard(
              child: Column(children: [
                Text(tokenReady ? 'Votre jeton de retrait' : 'Jeton de l’opération', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  tokenReady ? 'Présentez ce QR code au point de retrait.' : 'Conservé dans votre historique.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                QrImageView(
                  data: token,
                  size: 180,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.night),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.night),
                ),
                const SizedBox(height: 8),
                const Text('Code de retrait', style: TextStyle(color: AppColors.muted)),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(token, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  IconButton(
                    onPressed: () => Clipboard.setData(ClipboardData(text: token)),
                    icon: const Icon(Icons.copy_rounded, color: AppColors.brand),
                  ),
                ]),
                if (tokenReady)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Valable jusqu’au scan au PDR', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
              ]),
            ),
            if (tokenReady) ...[
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Ouvrir le ticket QR',
                icon: Icons.qr_code_2_rounded,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TokenPage(operation: operation))),
              ),
            ],
          ],
          const SizedBox(height: 16),
          GhostButton(label: 'Itinéraire', icon: Icons.near_me_outlined, onPressed: () => openRoute(context, operation)),
          const SizedBox(height: 20),
          const Text('Chronologie', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          ...operation.timeline.map((event) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  event.status == 'cash_delivered' || event.label.toLowerCase().contains('scan')
                      ? Icons.qr_code_scanner_rounded
                      : Icons.check_circle,
                  color: AppColors.brand,
                ),
                title: Text(event.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(formatDate(event.createdAt)),
              )),
        ],
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppController>().user;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Profil', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.night)),
        const SizedBox(height: 16),
        SoftCard(
          child: Row(children: [
            CircleAvatar(radius: 28, backgroundColor: AppColors.brandSoft, child: Text(initials(user?.name ?? ''), style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w800))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text(formatPhone(user?.phone ?? ''), style: const TextStyle(color: AppColors.muted)),
              Text('Inscrit le ${formatDate(user?.createdAt)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
        SoftCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NumbersPage())), child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.sim_card_outlined, color: AppColors.brand), title: Text('Mes numéros'), trailing: Icon(Icons.chevron_right))),
        const SizedBox(height: 12),
        const SoftCard(
          child: Text('Votre code PIN Mobile Money n’est demandé qu’au moment d’autoriser une opération. Fast-Cash ne l’enregistre pas.'),
        ),
        const SizedBox(height: 16),
        PrimaryButton(label: 'Se déconnecter', onPressed: () => context.read<AppController>().logout()),
      ],
    );
  }
}

class NumbersPage extends StatefulWidget {
  const NumbersPage({super.key});

  @override
  State<NumbersPage> createState() => _NumbersPageState();
}

class _NumbersPageState extends State<NumbersPage> {
  final phone = TextEditingController();
  String? network;
  String? detected;

  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final numbers = controller.user?.numbers ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Mes numéros')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Orange Money, Airtel Money, M-Pesa et AfriMoney.', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          ...numbers.map((number) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SoftCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(formatPhone(number.phone), style: const TextStyle(fontWeight: FontWeight.w800))),
                      if (number.isPrimary) const Text('Principal', style: TextStyle(color: AppColors.mint, fontWeight: FontWeight.w700, fontSize: 12)),
                    ]),
                    const SizedBox(height: 4),
                    NetworkBadge(network: number.network, label: number.verified ? number.networkLabel : '${number.networkLabel} · à vérifier'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (!number.verified) ActionChip(label: const Text('Vérifier OTP'), onPressed: () => _verify(number)),
                      if (number.verified && controller.selectedPhoneId != number.id) ActionChip(label: const Text('Utiliser'), onPressed: () => controller.useForTransaction(number.id)),
                      if (number.verified && !number.isPrimary) ActionChip(label: const Text('Principal'), onPressed: () => runAction(context, () => controller.setPrimary(number.id))),
                      ActionChip(label: const Text('Réseau'), onPressed: () => _editNetwork(number)),
                      if (!number.isPrimary) ActionChip(label: const Text('Supprimer'), onPressed: () => _delete(number)),
                    ]),
                  ]),
                ),
              )),
          const SizedBox(height: 8),
          const Text('Ajouter un numéro', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          PhoneField(controller: phone, onChanged: (value) => _detect(value)),
          if (detected != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Réseau présumé : $detected', style: const TextStyle(color: AppColors.muted))),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: network,
            decoration: InputDecoration(filled: true, fillColor: AppColors.mist, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), labelText: 'Réseau'),
            items: const [
              DropdownMenuItem(value: 'orange', child: Text('Orange Money')),
              DropdownMenuItem(value: 'airtel', child: Text('Airtel Money')),
              DropdownMenuItem(value: 'mpesa', child: Text('M-Pesa')),
              DropdownMenuItem(value: 'afrimoney', child: Text('AfriMoney')),
            ],
            onChanged: (value) => setState(() => network = value),
          ),
          const SizedBox(height: 12),
          PrimaryButton(label: 'Ajouter et vérifier', onPressed: () => runAction(context, () async {
            if (phone.text.length < 9) throw ApiException('Saisissez un numéro de 9 chiffres.');
            final chosen = network;
            if (chosen == null) throw ApiException('Sélectionnez le réseau Mobile Money.');
            final issued = await context.read<AppController>().requestPhoneChallenge(phone.text, chosen);
            if (!context.mounted) return;
            final added = await showPhoneOtpDialog(
              context,
              phoneNumber: issued['phone'] as String,
              network: issued['network'] as String,
              networkLabel: issued['network_label'] as String? ?? '',
              previewCode: issued['preview_code'] as String?,
            );
            if (added == true && context.mounted) {
              phone.clear();
              setState(() => detected = null);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numéro ajouté.')));
            }
          })),
        ],
      ),
    );
  }

  Future<void> _detect(String value) async {
    if (value.length < 9) return;
    try {
      final result = await context.read<AppController>().detectPhone(value);
      if (!mounted) return;
      setState(() {
        detected = result['detected_label'] as String?;
        network ??= result['network'] as String?;
      });
    } catch (_) {}
  }

  Future<void> _verify(PhoneNumber number) async {
    await runAction(context, () async {
      final issued = await context.read<AppController>().requestPhoneChallenge(number.phone, number.network);
      if (!mounted) return;
      final added = await showPhoneOtpDialog(
        context,
        phoneNumber: issued['phone'] as String,
        network: issued['network'] as String,
        networkLabel: issued['network_label'] as String? ?? number.networkLabel,
        previewCode: issued['preview_code'] as String?,
      );
      if (added == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numéro vérifié.')));
      }
    });
  }

  Future<void> _editNetwork(PhoneNumber number) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final entry in const {'orange': 'Orange Money', 'airtel': 'Airtel Money', 'mpesa': 'M-Pesa', 'afrimoney': 'AfriMoney'}.entries)
            ListTile(title: Text(entry.value), onTap: () => Navigator.pop(context, entry.key)),
        ]),
      ),
    );
    if (selected != null && mounted) {
      await runAction(context, () => context.read<AppController>().updateNetwork(number.id, selected));
    }
  }

  Future<void> _delete(PhoneNumber number) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce numéro ?'),
        content: Text(formatPhone(number.phone)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await runAction(context, () => context.read<AppController>().deletePhone(number.id));
    }
  }
}

Future<bool?> showPhoneOtpDialog(
  BuildContext context, {
  required String phoneNumber,
  required String network,
  required String networkLabel,
  String? previewCode,
}) {
  final code = TextEditingController();
  var busy = false;
  String? error;
  return showDialog<bool>(
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
                  const Text('Vérifier le numéro', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.night)),
                  const SizedBox(height: 6),
                  Text('Un code a été envoyé au ${formatPhone(phoneNumber)}. Saisissez-le pour confirmer que ce numéro vous appartient. Il ne sera ajouté qu’après cette vérification.', style: const TextStyle(color: AppColors.muted, height: 1.35)),
                  const SizedBox(height: 14),
                  Text(networkLabel, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.night)),
                  if (previewCode != null) ...[
                    const SizedBox(height: 10),
                    Text('Passerelle SMS non branchée. Code de vérification : $previewCode', style: const TextStyle(color: AppColors.night, fontWeight: FontWeight.w700, height: 1.35)),
                  ],
                  const SizedBox(height: 14),
                  OtpBoxes(controller: code, onChanged: (_) {}),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext, false), child: const Text('Annuler'))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Confirmer',
                        busy: busy,
                        onPressed: busy
                            ? null
                            : () async {
                                if (code.text.length != 6) {
                                  setLocal(() => error = 'Saisissez les 6 chiffres.');
                                  return;
                                }
                                setLocal(() {
                                  busy = true;
                                  error = null;
                                });
                                try {
                                  await dialogContext.read<AppController>().confirmPhone(phoneNumber, network, code.text);
                                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                                } on ApiException catch (failure) {
                                  if (dialogContext.mounted) {
                                    setLocal(() {
                                      busy = false;
                                      error = failure.message;
                                    });
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
  ).whenComplete(code.dispose);
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

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
          Navigator.push(context, MaterialPageRoute(builder: (_) => FollowPage(operationId: item.operationId!)));
        },
      ),
    );
  }
}
