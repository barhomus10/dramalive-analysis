import '../models/models.dart';

/// Parser M3U/M3U8 extendido.
///
/// Gramática soportada (docs/04-MODELO-FUENTES.md §3):
///
///   #EXTM3U
///   #EXTINF:-1 tvg-id="x" tvg-name="X" tvg-logo="https://…" group-title="News",Nombre visible
///   #EXTGRP:News
///   #EXTVLCOPT:http-user-agent=Mozilla/5.0
///   #EXTVLCOPT:http-referrer=https://…
///   https://…/stream.m3u8
///
/// Reglas:
///   • duración -1 → directo; > 0 → VOD con duración.
///   • el nombre visible va **después** de la última coma de `#EXTINF`.
///   • `group-title` clasifica; `#EXTGRP` es la forma antigua y gana si ambos
///     aparecen (comportamiento de VLC).
///   • las líneas que no son `#` ni URL se ignoran.
///   • los `#EXTVLCOPT` se conservan como cabeceras por entrada.
class M3uEntry {
  const M3uEntry({
    required this.url,
    required this.title,
    this.group = 'Sin categoría',
    this.logo = '',
    this.tvgId = '',
    this.durationSeconds = -1,
    this.headers = const {},
  });

  final String url;
  final String title;
  final String group;
  final String logo;
  final String tvgId;
  final int durationSeconds;
  final Map<String, String> headers;

  bool get isLive => durationSeconds < 0;

  Channel toChannel(int streamId) => Channel(
        streamId: streamId,
        name: title,
        streamType: isLive ? 'live' : 'movie',
        icon: logo,
        epgChannelId: tvgId,
        categoryId: group,
        num: streamId,
      );
}

class M3uParseResult {
  const M3uParseResult({
    required this.entries,
    required this.groups,
    this.errors = const [],
  });

  final List<M3uEntry> entries;

  /// Grupos en orden de aparición.
  final List<String> groups;
  final List<String> errors;

  bool get isEmpty => entries.isEmpty;
}

class M3uParser {
  const M3uParser();

  static final RegExp _attr = RegExp(r'([\w-]+)="([^"]*)"');

  M3uParseResult parse(String body) {
    final errors = <String>[];
    final entries = <M3uEntry>[];
    final groups = <String>[];

    if (body.trim().isEmpty) {
      return M3uParseResult(entries: entries, groups: groups, errors: ['lista vacía']);
    }

    final lines = const LineSplitter().convert(body);
    if (!lines.any((l) => l.trim().toUpperCase().startsWith('#EXTM3U'))) {
      errors.add('falta la cabecera #EXTM3U — se intenta parsear igualmente');
    }

    String? pendingTitle;
    String pendingGroup = '';
    String pendingLogo = '';
    String pendingTvg = '';
    int pendingDuration = -1;
    final pendingHeaders = <String, String>{};

    void resetPending() {
      pendingTitle = null;
      pendingGroup = '';
      pendingLogo = '';
      pendingTvg = '';
      pendingDuration = -1;
      pendingHeaders.clear();
    }

    for (var raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.toUpperCase().startsWith('#EXTINF')) {
        final comma = line.indexOf(',');
        final attrsPart = comma >= 0 ? line.substring(0, comma) : line;
        pendingTitle = comma >= 0 ? line.substring(comma + 1).trim() : '';

        final colon = attrsPart.indexOf(':');
        final durPart = colon >= 0 ? attrsPart.substring(colon + 1).trim() : '-1';
        pendingDuration = int.tryParse(durPart.split(' ').first) ?? -1;

        for (final m in _attr.allMatches(attrsPart)) {
          final key = m.group(1)!.toLowerCase();
          final value = m.group(2)!;
          switch (key) {
            case 'group-title':
              pendingGroup = value;
            case 'tvg-logo':
              pendingLogo = value;
            case 'tvg-id':
              pendingTvg = value;
            case 'tvg-name':
              if (pendingTitle == null || pendingTitle!.isEmpty) {
                pendingTitle = value;
              }
          }
        }
        continue;
      }

      if (line.toUpperCase().startsWith('#EXTGRP:')) {
        // Gana sobre group-title (comportamiento VLC).
        pendingGroup = line.substring(8).trim();
        continue;
      }

      if (line.toUpperCase().startsWith('#EXTVLCOPT:')) {
        final opt = line.substring(11);
        final eq = opt.indexOf('=');
        if (eq > 0) {
          final k = opt.substring(0, eq).trim().toLowerCase();
          final v = opt.substring(eq + 1).trim();
          if (k == 'http-user-agent') {
            pendingHeaders['User-Agent'] = v;
          } else if (k == 'http-referrer' || k == 'http-referer') {
            pendingHeaders['Referer'] = v;
          } else {
            pendingHeaders[k] = v;
          }
        }
        continue;
      }

      if (line.startsWith('#')) continue; // #EXTM3U, #EXT-X-*, comentarios

      if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(line)) {
        errors.add('línea ignorada (no es una URL): ${_clip(line)}');
        continue;
      }

      // Es una URL: cierra la entrada pendiente.
      final title = (pendingTitle == null || pendingTitle!.isEmpty)
          ? _titleFromUrl(line)
          : pendingTitle!;
      final group = pendingGroup.isEmpty ? 'Sin categoría' : pendingGroup;
      if (!groups.contains(group)) groups.add(group);

      entries.add(M3uEntry(
        url: line,
        title: title,
        group: group,
        logo: pendingLogo,
        tvgId: pendingTvg,
        durationSeconds: pendingDuration,
        headers: Map.unmodifiable(pendingHeaders),
      ));
      resetPending();
    }

    if (entries.isEmpty && errors.isEmpty) {
      errors.add('no se encontró ninguna URL reproducible');
    }
    return M3uParseResult(entries: entries, groups: groups, errors: errors);
  }

  static String _titleFromUrl(String url) {
    try {
      final path = Uri.parse(url).pathSegments;
      if (path.isEmpty) return url;
      final last = path.last;
      final dot = last.lastIndexOf('.');
      return dot > 0 ? last.substring(0, dot) : last;
    } catch (_) {
      return url;
    }
  }

  static String _clip(String s) => s.length > 60 ? '${s.substring(0, 57)}…' : s;
}

/// Genera M3U a partir de una lista de canales (exportar/importar fuentes).
String toM3u(Iterable<M3uEntry> entries) {
  final b = StringBuffer('#EXTM3U\n');
  for (final e in entries) {
    b.write('#EXTINF:${e.durationSeconds}');
    if (e.tvgId.isNotEmpty) b.write(' tvg-id="${e.tvgId}"');
    b.write(' tvg-name="${e.title.replaceAll('"', "'")}"');
    if (e.logo.isNotEmpty) b.write(' tvg-logo="${e.logo}"');
    b.write(' group-title="${e.group.replaceAll('"', "'")}"');
    b.write(',${e.title}\n');
    e.headers.forEach((k, v) {
      final opt = switch (k.toLowerCase()) {
        'user-agent' => 'http-user-agent',
        'referer' => 'http-referrer',
        _ => k,
      };
      b.write('#EXTVLCOPT:$opt=$v\n');
    });
    b.write('${e.url}\n');
  }
  return b.toString();
}
