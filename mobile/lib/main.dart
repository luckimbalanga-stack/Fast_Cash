import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/app_controller.dart';
import 'theme/app_theme.dart';
import 'views/auth/auth_pages.dart';
import 'views/pdr/pdr_pages.dart';
import 'views/user/user_shell.dart';
import 'widgets/update_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FastCashApp());
}

class FastCashApp extends StatelessWidget {
  const FastCashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppController()..bootstrap(),
      child: MaterialApp(
        title: 'Fast-Cash',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const RootGate(),
      ),
    );
  }
}

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptUpdate());
  }

  void _maybePromptUpdate() {
    final controller = context.read<AppController>();
    final update = controller.pendingUpdate;
    if (update == null || controller.updatePromptShown || !mounted) return;
    controller.markUpdatePromptShown();
    showAppUpdateDialog(context, update);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    if (controller.pendingUpdate != null && !controller.updatePromptShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptUpdate());
    }
    final role = controller.role;
    return switch (role) {
      'user' => const UserShell(),
      'pdr' => const PdrShell(),
      _ => const WelcomePage(),
    };
  }
}
