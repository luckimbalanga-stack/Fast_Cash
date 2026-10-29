import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  const SizedBox(height: 12),
                  const Center(child: FastCashMark(size: 156, stacked: true)),
                  const SizedBox(height: 8),
                  const Text('Votre argent, votre monnaie, à proximité.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 15)),
                  const SizedBox(height: 18),
                  const _HeroArt(),
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      _Feature(icon: Icons.bolt_rounded, title: 'Rapide', text: 'Des transactions en quelques secondes'),
                      _Feature(icon: Icons.location_on_outlined, title: 'Proche', text: 'Un large réseau de PDR autour de vous'),
                      _Feature(icon: Icons.payments_outlined, title: 'Intégral', text: 'Tout le montant, dans la devise choisie'),
                    ],
                  ),
                  const SizedBox(height: 22),
                  PrimaryButton(label: 'Créer un compte', icon: Icons.arrow_forward_rounded, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage()))),
                  const SizedBox(height: 12),
                  GhostButton(label: 'Se connecter', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroArt extends StatelessWidget {
  const _HeroArt();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Image.asset(
        'assets/brand/hero.png',
        width: double.infinity,
        fit: BoxFit.fitWidth,
        semanticLabel: 'Un point de retrait Fast-Cash à proximité',
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            CircleAvatar(backgroundColor: AppColors.mist, child: Icon(icon, color: AppColors.night, size: 18)),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(height: 2),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.3)),
          ],
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final phone = TextEditingController();
  final code = TextEditingController();
  bool otpStep = false;
  bool busy = false;
  String? previewCode;
  String loginRole = 'user';

  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    final controller = context.read<AppController>();
    setState(() => busy = true);
    try {
      if (!otpStep) {
        final issued = await controller.requestUserOtp(phone.text, 'login');
        setState(() {
          otpStep = true;
          previewCode = issued['preview_code'] as String?;
          loginRole = issued['role'] as String? ?? 'user';
        });
      } else {
        if (loginRole == 'pdr') {
          await controller.verifyPdr(phone.text, code.text);
        } else {
          await controller.verifyUser(phone.text, code.text, 'login');
        }
        if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
      }
    } on Exception {
      if (mounted) {
        setState(() => busy = false);
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Center(child: FastCashMark(size: 168, stacked: true)),
          const SizedBox(height: 12),
          Text(otpStep ? 'Vérification OTP' : 'Connexion', textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.night)),
          const SizedBox(height: 8),
          Text(
            otpStep ? 'Saisissez le code envoyé au ${formatPhone('+243${phone.text}')}.' : 'Utilisez le numéro de téléphone de votre compte.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          if (!otpStep) PhoneField(controller: phone) else OtpBoxes(controller: code, onChanged: (_) {}),
          if (otpStep && previewCode != null) ...[
            const SizedBox(height: 12),
            Text('Passerelle SMS non branchée. Code de vérification : $previewCode', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.night, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            label: otpStep ? 'Vérifier' : 'Recevoir le code',
            icon: Icons.arrow_forward_rounded,
            busy: busy,
            onPressed: () => runAction(context, () async {
              await _next();
              if (mounted) setState(() => busy = false);
            }),
          ),
        ],
      ),
    );
  }
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final code = TextEditingController();
  int step = 0;
  bool busy = false;
  String? network;
  String? detected;
  String? previewCode;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    final controller = context.read<AppController>();
    setState(() => busy = true);
    try {
      if (step == 0) {
        if (name.text.trim().length < 2) throw Exception('name');
        setState(() => step = 1);
      } else if (step == 1) {
        final detectedMap = await controller.detectPhone(phone.text);
        network ??= detectedMap['network'] as String?;
        detected = detectedMap['detected_label'] as String?;
        final issued = await controller.requestUserOtp(phone.text, 'register', name: name.text.trim());
        setState(() {
          step = 2;
          previewCode = issued['preview_code'] as String?;
        });
      } else if (step == 2) {
        await controller.verifyUser(phone.text, code.text, 'register', name: name.text.trim(), network: network);
        if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Votre nom', 'Votre numéro', 'Vérification OTP'];
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => step == 0 ? Navigator.pop(context) : setState(() => step -= 1))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Center(child: FastCashMark(size: 108, stacked: true)),
          const SizedBox(height: 8),
          const Text('Votre argent, votre monnaie, à proximité.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset('assets/brand/hero.png', height: 156, width: double.infinity, fit: BoxFit.cover),
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(3, (index) {
              final active = index <= step;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 6,
                  decoration: BoxDecoration(color: active ? AppColors.brand : AppColors.line, borderRadius: BorderRadius.circular(8)),
                ),
              );
            }),
          ),
          const SizedBox(height: 22),
          Text(titles[step], style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.night)),
          const SizedBox(height: 8),
          Text(
            step == 2 ? 'Saisissez le code envoyé à votre numéro.' : 'Ces informations servent à créer votre espace Fast-Cash.',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          if (step == 0)
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.person_outline, color: AppColors.brand), hintText: 'Jean Mwamba', filled: true, fillColor: AppColors.mist, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
            ),
          if (step == 1) ...[
            PhoneField(controller: phone, onChanged: (_) => network = null),
            if (detected != null) ...[
              const SizedBox(height: 12),
              Text('Réseau présumé : $detected', style: const TextStyle(color: AppColors.muted)),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: network,
              decoration: InputDecoration(filled: true, fillColor: AppColors.mist, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), labelText: 'Corriger le réseau'),
              items: const [
                DropdownMenuItem(value: 'orange', child: Text('Orange Money')),
                DropdownMenuItem(value: 'airtel', child: Text('Airtel Money')),
                DropdownMenuItem(value: 'mpesa', child: Text('M-Pesa')),
                DropdownMenuItem(value: 'afrimoney', child: Text('AfriMoney')),
              ],
              onChanged: (value) => setState(() => network = value),
            ),
          ],
          if (step == 2) ...[
            OtpBoxes(controller: code, onChanged: (_) {}),
            if (previewCode != null) ...[
              const SizedBox(height: 12),
              Text('Passerelle SMS non branchée. Code de vérification : $previewCode', style: const TextStyle(color: AppColors.night, fontWeight: FontWeight.w700)),
            ],
          ],
          const SizedBox(height: 22),
          PrimaryButton(
            label: 'Continuer',
            icon: Icons.arrow_forward_rounded,
            busy: busy,
            onPressed: () => runAction(context, () async {
              if (step == 0 && name.text.trim().length < 2) {
                throw _short();
              }
              await _next();
            }),
          ),
        ],
      ),
    );
  }

  ApiException _short() => ApiException('Indiquez votre nom complet.');
}
