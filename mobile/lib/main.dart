import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/bootstrap.dart';
import 'core/theme.dart';
import 'data/local_store.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'state/app_controller.dart';
import 'state/app_scope.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const MakasiBootstrap());
}

/// Charge la configuration partagée puis lance l'application.
class MakasiBootstrap extends StatefulWidget {
  const MakasiBootstrap({super.key});

  @override
  State<MakasiBootstrap> createState() => _MakasiBootstrapState();
}

class _MakasiBootstrapState extends State<MakasiBootstrap> {
  AppController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final boot = await Bootstrap.load();
      final prefs = await SharedPreferences.getInstance();
      final controller = AppController(
        bootstrap: boot,
        localStore: LocalStore(prefs),
      );
      await controller.start();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        theme: MakasiTheme.light,
        darkTheme: MakasiTheme.dark,
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: _StartupError(error: _error!),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return MaterialApp(
        theme: MakasiTheme.light,
        darkTheme: MakasiTheme.dark,
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: const SplashScreen(),
      );
    }

    return MakasiApp(controller: controller);
  }
}

class MakasiApp extends StatefulWidget {
  const MakasiApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<MakasiApp> createState() => _MakasiAppState();
}

class _MakasiAppState extends State<MakasiApp> {
  late final Listenable _rootListenable;

  @override
  void initState() {
    super.initState();
    _rootListenable = Listenable.merge([
      widget.controller.themeModeNotifier,
      widget.controller.onboardedNotifier,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AppScope(
      controller: controller,
      child: ListenableBuilder(
        listenable: _rootListenable,
        builder: (context, _) {
          final onboarded = controller.onboardedNotifier.value;
          return MaterialApp(
            title: 'Makasi AI',
            debugShowCheckedModeBanner: false,
            theme: MakasiTheme.light,
            darkTheme: MakasiTheme.dark,
            themeMode: controller.themeModeNotifier.value,
            home: onboarded
                ? const HomeScreen()
                : const AuthScreen(firstRun: true),
          );
        },
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 40),
                const SizedBox(height: 16),
                Text(
                  'Impossible de démarrer Makasi AI',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
