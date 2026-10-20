import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/source_repository.dart';

/// Réplica de la arquitectura de cliente de Drama Live.
///
/// Equivalencias con la app original (ver docs/02-ARQUITECTURA.md):
///
///   original (generación A, Kotlin)          réplica
///   ─────────────────────────────            ─────────────────────────
///   MyApplication                       →    main() + ChangeNotifierProviders
///   StartActivity (launcher)            →    SplashScreen  ("/")
///   IntroActivity (onboarding)          →    SourceScreen  ("/source")
///   HomeActivity (shell)                →    HomeShell     ("/app")
///   LiveActivity                        →    LiveScreen    ("/live")
///   MultyPlayerActivity / FullScreen    →    PlayerScreen  ("/video_player")
///   ProfileActivity                     →    ProfileScreen ("/profile")
///   ajustes                             →    SettingsScreen("/settings")
///
/// Lo que deliberadamente no se replica: los 15 SDKs publicitarios, el
/// reporting de crashes a un tercero, la telemetría y el branding.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DramaLiveReplicaApp());
}

class DramaLiveReplicaApp extends StatefulWidget {
  const DramaLiveReplicaApp({super.key});

  @override
  State<DramaLiveReplicaApp> createState() => _DramaLiveReplicaAppState();
}

class _DramaLiveReplicaAppState extends State<DramaLiveReplicaApp> {
  late final SettingsRepository _settings = SettingsRepository();
  late final SourceRepository _sources = SourceRepository(_settings);
  late final AppRouter _router = AppRouter();

  @override
  void initState() {
    super.initState();
    _settings.load().then((_) => _sources.load());
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsRepository>.value(value: _settings),
        ChangeNotifierProvider<SourceRepository>.value(value: _sources),
      ],
      child: MaterialApp.router(
        title: 'Drama Live — réplica (análisis)',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        routerConfig: _router.config(context),
      ),
    );
  }
}
