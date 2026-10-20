import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/home_shell.dart';
import '../../features/live/live_screen.dart';
import '../../features/player/player_screen.dart';
import '../../features/playlist/source_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/splash/splash_screen.dart';

/// Rutas de la réplica.
///
/// Se corresponden 1:1 con las rutas extraídas del bundle público de la
/// generación B (docs/01-RECON-WEB.md §6):
///
///   original            réplica               widget
///   ─────────           ───────────────       ─────────────
///   (splash nativo)     /                     SplashScreen
///   /auth               /source               SourceScreen   ← alta de fuentes
///   /app                /app                  HomeShell
///   /live               /app/live             LiveScreen
///   /shows              /app/shows            ShowsScreen (en HomeShell)
///   /sport              /app/sport            SportScreen (en HomeShell)
///   /profile            /app/profile          ProfileScreen
///   /settings           /settings             SettingsScreen
///   /video_player       /video_player         PlayerScreen
///
/// No se replican `/chat-friends` (XMPP, pendiente) ni `/our_apps`
/// (cross-promo del editor original: sin interés y fuera de alcance).
class AppRouter {
  AppRouter();

  static const String splash = '/';
  static const String source = '/source';
  static const String shell = '/app';
  static const String live = '/app/live';
  static const String shows = '/app/shows';
  static const String sport = '/app/sport';
  static const String profile = '/app/profile';
  static const String settings = '/settings';
  static const String player = '/video_player';

  final GlobalKey<NavigatorState> _root = GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _shell = GlobalKey<NavigatorState>();

  GoRouter config(BuildContext context) {
    return GoRouter(
      navigatorKey: _root,
      initialLocation: splash,
      debugLogDiagnostics: false,
      routes: [
        GoRoute(
          path: splash,
          name: 'splash',
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: source,
          name: 'source',
          builder: (context, state) => const SourceScreen(),
        ),
        GoRoute(
          path: settings,
          name: 'settings',
          builder: (context, state) => const SettingsScreen(),
        ),

        /// `/video_player?url=…&title=…&kind=live|vod`
        ///
        /// La app original pasa el stream por navegación interna; aquí va por
        /// query para que la ruta sea compartible y testeable.
        GoRoute(
          path: player,
          name: 'player',
          builder: (context, state) {
            final q = state.uri.queryParameters;
            return PlayerScreen(
              url: q['url'] ?? '',
              title: q['title'] ?? 'Sin título',
              kind: q['kind'] ?? 'live',
              epgChannelId: q['epg'],
            );
          },
        ),

        ShellRoute(
          navigatorKey: _shell,
          builder: (context, state, child) => HomeShell(child: child),
          routes: [
            GoRoute(
              path: live,
              name: 'live',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: LiveScreen()),
            ),
            GoRoute(
              path: shows,
              name: 'shows',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: _Placeholder(
                  title: 'Shows / VOD',
                  body: 'Catálogo VOD y series. Usa el backend de referencia '
                      '(acción get_vod_streams / get_series) o tu propia M3U.\n\n'
                      'Pantalla deliberadamente mínima: el interés del análisis '
                      'está en la capa de fuentes y en el reproductor.',
                ),
              ),
            ),
            GoRoute(
              path: sport,
              name: 'sport',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: _Placeholder(
                  title: 'Sport',
                  body: 'En la app original es un vertical aparte servido por '
                      'sport.eastgoessouth.online/sport/ (docs/02 §2).\n\n'
                      'La réplica no consume ese host.',
                ),
              ),
            ),
            GoRoute(
              path: profile,
              name: 'profile',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: ProfileScreen()),
            ),
          ],
        ),
      ],
      errorBuilder: (context, state) => _Placeholder(
        title: 'Ruta desconocida',
        body: state.uri.toString(),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(
          body,
          style: const TextStyle(height: 1.6, fontSize: 15),
        ),
      ),
    );
  }
}
