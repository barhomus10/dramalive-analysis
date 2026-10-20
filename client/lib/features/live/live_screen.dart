import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/source_repository.dart';
import '../../widgets/channel_tile.dart';

/// `LiveActivity` de la app original.
///
/// Lista de canales de la fuente activa, con filtro por grupo, búsqueda local y
/// EPG de la entrada actual/sgte.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  String _group = ResolvedCatalog.allGroup;
  String _query = '';
  final Map<int, (String, String)> _epgCache = {};

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SourceRepository>();

    return switch (repo.state) {
      LoadState.loading => const Center(child: CircularProgressIndicator()),
      LoadState.error => _ErrorView(
          message: repo.error ?? 'Error desconocido',
          onRetry: repo.refresh,
          onPickSource: () => context.push(AppRouter.source),
        ),
      LoadState.idle => _ErrorView(
          message: 'No hay ninguna fuente activa.',
          onRetry: repo.refresh,
          onPickSource: () => context.push(AppRouter.source),
        ),
      LoadState.ready => repo.catalog.isEmpty
          ? _ErrorView(
              message: 'La fuente "${repo.catalog.sourceLabel}" no devolvió '
                  'ningún canal.\n\n'
                  'Si es una M3U, revisa que sea accesible y que use '
                  '#EXTINF. Si es un panel Xtream, revisa las credenciales y '
                  'que la suscripción incluya canales en directo.',
              onRetry: repo.refresh,
              onPickSource: () => context.push(AppRouter.source),
            )
          : _buildList(repo),
    };
  }

  Widget _buildList(SourceRepository repo) {
    final catalog = repo.catalog;
    final all = catalog.byGroup(_group);
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? all
        : all
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.epgChannelId.toLowerCase().contains(q))
            .toList();

    return Column(
      children: [
        if (catalog.warnings.isNotEmpty) _Warnings(catalog.warnings),
        _GroupChips(
          groups: catalog.groups,
          selected: _group,
          onSelect: (g) => setState(() => _group = g),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar en ${visible.length} canales…',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() => _query = ''),
                    ),
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? const Center(
                  child: Text('Sin resultados',
                      style: TextStyle(color: AppTheme.textSecondary)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final c = visible[i];
                    final epg = _epgCache[c.streamId];
                    return ChannelTile(
                      channel: c,
                      epgNow: epg?.$1,
                      epgNext: epg?.$2,
                      onTap: () => _open(context, repo, c),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _open(
      BuildContext context, SourceRepository repo, Channel c) async {
    final url = repo.playbackUrlFor(c);
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo resolver la URL de reproducción de este '
              'canal con la fuente activa.'),
        ),
      );
      return;
    }
    _loadEpg(repo, c);
    // Ojo: NO usar Uri(path:...).toString() — percent-codifica las barras de
    // "/video_player" y GoRouter no reconoce la ruta.
    final query = Uri(queryParameters: {
      'url': url,
      'title': c.name,
      'kind': c.isVod ? 'vod' : 'live',
      if (c.epgChannelId.isNotEmpty) 'epg': c.epgChannelId,
    }).query;
    context.push('${AppRouter.player}?$query');
  }

  /// Carga la parrilla en segundo plano y la cachea por `streamId`.
  /// Solo para fuentes Xtream: una M3U no tiene EPG propio (necesitaría XMLTV).
  Future<void> _loadEpg(SourceRepository repo, Channel c) async {
    final s = repo.active;
    if (s == null) return;
    if (_epgCache.containsKey(c.streamId)) return;
    try {
      final entries = await repo.xtream.epg(s, c.streamId, limit: 2);
      if (entries.isEmpty || !mounted) return;
      setState(() {
        _epgCache[c.streamId] = (
          entries.first.title,
          entries.length > 1 ? entries[1].title : '',
        );
      });
    } catch (_) {
      // La EPG es decorativa: si falla, se ignora en silencio.
    }
  }
}

class _GroupChips extends StatelessWidget {
  const _GroupChips({
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  final List<String> groups;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _chip(ResolvedCatalog.allGroup, 'Todos', groups.length),
          for (final g in groups) _chip(g, g, null),
        ],
      ),
    );
  }

  Widget _chip(String value, String label, int? count) {
    final isSel = value == selected;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(count == null ? label : '$label ($count)'),
        selected: isSel,
        onSelected: (_) => onSelect(value),
        selectedColor: AppTheme.accent.withOpacity(0.28),
        backgroundColor: AppTheme.bgMid,
        side: BorderSide(
          color: isSel ? AppTheme.accent : Colors.white12,
        ),
        labelStyle: TextStyle(
          fontSize: 12.5,
          color: isSel ? AppTheme.textPrimary : AppTheme.textSecondary,
        ),
        showCheckmark: false,
      ),
    );
  }
}

class _Warnings extends StatelessWidget {
  const _Warnings(this.warnings);

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTheme.bgHigh,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      w,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onPickSource,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onPickSource;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 44, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.5, fontSize: 14),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                ),
                OutlinedButton.icon(
                  onPressed: onPickSource,
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: const Text('Elegir fuente'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimary,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
