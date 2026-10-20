import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/source_repository.dart';

/// `StartActivity` de la app original.
///
/// El original pinta el splash desde **HTML/CSS** (no desde Flutter) y lo
/// oculta al recibir el evento `flutter-first-frame`, con un fallback de 10 s
/// (docs/01 §4). Aquí se reproduce el degradado y el spinner, y se espera a
/// que los repositorios terminen de cargar.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _timeout = Duration(seconds: 10); // igual que el fallback original
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final settings = context.read<SettingsRepository>();
    final sources = context.read<SourceRepository>();

    await Future.any([
      Future.wait([
        if (!settings.isLoaded) settings.load(),
        sources.load(),
      ]),
      Future<void>.delayed(_timeout),
    ]);

    if (!mounted || _navigated) return;
    _navigated = true;

    final hasSource = sources.sources.isNotEmpty;
    context.go(hasSource ? AppRouter.live : AppRouter.source);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.splashGradient),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sin logotipo del producto original: se usa un glifo genérico.
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 2),
                ),
                child: const Icon(Icons.live_tv_rounded,
                    size: 56, color: Colors.white70),
              ),
              const SizedBox(height: 30),
              const Text(
                'RÉPLICA DE ANÁLISIS',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'v1.0.0 (build 1)',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 40),
              const SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation(AppTheme.accent),
                  backgroundColor: Color(0x1AFFFFFF),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Cargando…',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
