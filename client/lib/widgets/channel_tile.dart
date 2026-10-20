import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/models/models.dart';

/// Fila de canal. Equivale a los items de `LiveActivity`.
///
/// No se usa el proxy de imágenes `images.weserv.nl` que emplea la app
/// original: los iconos se cargan directos desde su origen, y si fallan se
/// muestra un placeholder local. Pasar todas las URLs de los canales por un
/// proxy de terceros revelaría al operador del proxy todo lo que ves.
class ChannelTile extends StatelessWidget {
  const ChannelTile({
    required this.channel,
    required this.onTap,
    this.epgNow,
    this.epgNext,
    this.trailing,
    super.key,
  });

  final Channel channel;
  final VoidCallback onTap;
  final String? epgNow;
  final String? epgNext;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _Logo(url: channel.icon, name: channel.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (epgNow != null && epgNow!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        epgNow!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                    if (epgNext != null && epgNext!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'A continuación: $epgNext',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                    if (channel.tvArchive) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.replay_rounded,
                              size: 12, color: AppTheme.textSecondary),
                          const SizedBox(width: 3),
                          Text(
                            'Catch-up ${channel.tvArchiveDuration}d',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  const Icon(Icons.play_circle_outline_rounded,
                      color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.url, required this.name});

  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 44,
        child: url.isEmpty
            ? _fallback()
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : _fallback(),
              ),
      ),
    );
  }

  Widget _fallback() {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      color: AppTheme.bgHigh,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );
  }
}
