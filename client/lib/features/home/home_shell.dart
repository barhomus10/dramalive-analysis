import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/source_repository.dart';
import '../../widgets/cleartext_banner.dart';

/// `HomeActivity` de la app original: el shell con navegación inferior.
///
/// Cuatro destinos, que se corresponden con los verticales detectados en el
/// bundle (`/live`, `/shows`, `/sport`, `/profile`).
class HomeShell extends StatelessWidget {
  const HomeShell({required this.child, super.key});

  final Widget child;

  static const _destinations = <(String, IconData, String)>[
    (AppRouter.live, Icons.live_tv_rounded, 'Directo'),
    (AppRouter.shows, Icons.movie_rounded, 'Shows'),
    (AppRouter.sport, Icons.sports_soccer_rounded, 'Sport'),
    (AppRouter.profile, Icons.person_rounded, 'Perfil'),
  ];

  int _indexFor(String location) {
    final i = _destinations.indexWhere((d) => location.startsWith(d.$1));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final index = _indexFor(location);
    final sources = context.watch<SourceRepository>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_destinations[index].$3),
        actions: [
          if (sources.state == LoadState.loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppTheme.accent),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Fuente activa',
            icon: const Icon(Icons.playlist_play_rounded),
            onPressed: () => context.push(AppRouter.source),
          ),
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => context.push(AppRouter.settings),
          ),
        ],
      ),
      body: Column(
        children: [
          const CleartextBanner(),
          if (sources.catalog.sourceLabel.isNotEmpty)
            Material(
              color: AppTheme.bgMid,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.source_rounded,
                        size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Fuente: ${sources.catalog.sourceLabel} · '
                        '${sources.catalog.channels.length} canales',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: sources.refresh,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Recargar'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_destinations[i].$1),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.$2),
              selectedIcon: Icon(d.$2, color: AppTheme.accent),
              label: d.$3,
            ),
        ],
      ),
    );
  }
}
