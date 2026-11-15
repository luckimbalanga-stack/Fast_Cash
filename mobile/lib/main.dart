import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';

import 'controllers/app_controller.dart';
import 'core/app_nav.dart';
import 'models/models.dart';
import 'services/pdr_call_alert.dart';
import 'services/pdr_watchdog.dart';
import 'theme/app_theme.dart';
import 'views/auth/auth_pages.dart';
import 'views/pdr/incoming_call_page.dart';
import 'views/pdr/pdr_pages.dart';
import 'views/user/user_shell.dart';
import 'widgets/update_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Init non bloquant : ne doit pas retarder le premier frame.
  unawaited(() async {
    try {
      await PdrCallAlert.init();
      await PdrWatchdog.init();
    } catch (_) {}
  }());
  runApp(const FastCashApp());
}

class FastCashApp extends StatelessWidget {
  const FastCashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final controller = AppController()..bootstrap();
        PdrWatchdog.onOfferFound = controller.handleWatchdogOffer;
        PdrCallAlert.onOpenCall = (id, seed) {
          if (seed != null) {
            try {
              controller.upsertIncomingSeed(CashOperation.fromJson(seed));
            } catch (_) {}
          }
          if (controller.operationById(id) == null) {
            unawaited(controller.refreshLight());
          }
        };
        return controller;
      },
      child: MaterialApp(
        title: 'Fast-Cash',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        navigatorKey: appNavigatorKey,
        home: const RootGate(),
        builder: (context, child) => WithForegroundTask(child: child ?? const SizedBox.shrink()),
        onGenerateRoute: (settings) {
          if (settings.name == IncomingCallPage.routeName) {
            final args = settings.arguments;
            int? id;
            Map<String, dynamic>? seed;
            if (args is int) {
              id = args;
            } else if (args is Map) {
              final rawId = args['operationId'];
              id = rawId is int ? rawId : int.tryParse('$rawId');
              final rawSeed = args['seed'];
              if (rawSeed is Map) seed = Map<String, dynamic>.from(rawSeed);
            }
            if (id != null) {
              final operationId = id;
              return MaterialPageRoute<void>(
                settings: settings,
                fullscreenDialog: true,
                builder: (_) => IncomingCallPage(operationId: operationId, seed: seed),
              );
            }
          }
          return null;
        },
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
    if (!controller.sessionReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.brand)),
      );
    }
    final role = controller.role;
    return switch (role) {
      'user' => const UserShell(),
      'pdr' => const PdrShell(),
      _ => const WelcomePage(),
    };
  }
}
