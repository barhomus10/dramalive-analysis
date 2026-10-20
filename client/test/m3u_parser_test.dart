import 'package:flutter_test/flutter_test.dart';

import 'package:dramalive_replica/data/providers/m3u_parser.dart';

/// Pruebas del parser M3U/M3U8 (la fuente más común de un panel IPTV).
///
/// No requieren red ni backend: todo es texto de entrada fijo.
void main() {
  const sample = '''#EXTM3U
#EXTINF:-1 tvg-id="c1" tvg-logo="https://logos.example/c1.png" group-title="Noticias",Channel One
https://cdn.example/live/u/p/1.ts
#EXTINF:120 group-title="Cine",A Movie
https://cdn.example/movie/u/p/2.mp4
#EXTINF:-1 group-title="Noticias",Channel Two HD
https://cdn.example/live/u/p/3.ts
''';

  group('M3uParser.parse', () {
    test('extrae entradas con título, grupo, logo y tvg-id', () {
      final r = const M3uParser().parse(sample);

      expect(r.entries, hasLength(3));
      expect(r.errors, isEmpty);

      final first = r.entries[0];
      expect(first.title, 'Channel One');
      expect(first.group, 'Noticias');
      expect(first.tvgId, 'c1');
      expect(first.logo, 'https://logos.example/c1.png');
      expect(first.url, 'https://cdn.example/live/u/p/1.ts');
    });

    test('distingue live (-1) de VOD (duración > 0)', () {
      final r = const M3uParser().parse(sample);

      expect(r.entries[0].isLive, isTrue);
      expect(r.entries[0].durationSeconds, -1);
      expect(r.entries[1].isLive, isFalse);
      expect(r.entries[1].durationSeconds, 120);
    });

    test('lista los grupos en orden de aparición, sin duplicados', () {
      final r = const M3uParser().parse(sample);
      expect(r.groups, ['Noticias', 'Cine']);
    });

    test('una entrada sin group-title cae al grupo por defecto', () {
      final r = const M3uParser().parse('#EXTM3U\n'
          '#EXTINF:-1,Sin grupo\n'
          'https://cdn.example/live/u/p/9.ts\n');
      expect(r.entries, hasLength(1));
      expect(r.entries[0].group, 'Sin categoría');
    });

    test('cuerpo vacío -> resultado vacío con error descriptivo', () {
      final r = const M3uParser().parse('');
      expect(r.isEmpty, isTrue);
      expect(r.errors, contains('lista vacía'));
    });

    test('ignora líneas que no son #EXTINF ni URL', () {
      final r = const M3uParser().parse('#EXTM3U\n'
          '#EXTVLCOPT:algo=raro\n'
          '# un comentario\n'
          '#EXTINF:-1,Ok\n'
          'https://cdn.example/live/u/p/1.ts\n');
      expect(r.entries, hasLength(1));
      expect(r.entries[0].title, 'Ok');
    });
  });

  group('robustez del resolver (TDD)', () {
    test('tolera BOM UTF-8 al inicio sin marcar "falta cabecera"', () {
      final r =
          const M3uParser().parse('\u{FEFF}#EXTM3U\n#EXTINF:-1,A\nhttps://x/1.ts\n');
      expect(r.entries, hasLength(1));
      expect(r.errors, isEmpty);
    });

    test('deduplica URLs repetidas (misma URL = un solo canal)', () {
      final r = const M3uParser().parse('#EXTM3U\n'
          '#EXTINF:-1,Dup\n'
          'https://x/1.ts\n'
          '#EXTINF:-1,Dup otra vez\n'
          'https://x/1.ts\n');
      expect(r.entries, hasLength(1));
    });

    test('EXTVLCOPT mapea User-Agent y Referer a entry.headers', () {
      final r = const M3uParser().parse('#EXTM3U\n'
          '#EXTINF:-1,Con cabeceras\n'
          '#EXTVLCOPT:http-user-agent=MiAgent/1.0\n'
          '#EXTVLCOPT:http-referrer=https://origen.example/\n'
          'https://x/1.ts\n');
      expect(r.entries[0].headers['User-Agent'], 'MiAgent/1.0');
      expect(r.entries[0].headers['Referer'], 'https://origen.example/');
    });

    test('EXTGRP gana sobre group-title (comportamiento VLC)', () {
      final r = const M3uParser().parse('#EXTM3U\n'
          '#EXTINF:-1 group-title="DelAttr",Uno\n'
          '#EXTGRP:DelExtGrp\n'
          'https://x/1.ts\n');
      expect(r.entries[0].group, 'DelExtGrp');
    });
  });

  group('toM3u (serialización)', () {
    test('round-trip: lo serializado vuelve a parsearse igual', () {
      final original = const M3uParser().parse(sample);
      final text = toM3u(original.entries);
      final reparsed = const M3uParser().parse(text);

      expect(text, startsWith('#EXTM3U'));
      expect(reparsed.entries, hasLength(original.entries.length));
      expect(reparsed.entries[0].title, original.entries[0].title);
      expect(reparsed.entries[0].url, original.entries[0].url);
      expect(reparsed.entries[1].durationSeconds,
          original.entries[1].durationSeconds);
    });
  });

  group('M3uEntry.toChannel', () {
    test('mapea a Channel con stream_type live/movie según duración', () {
      final live = const M3uEntry(url: 'u1', title: 'T1');
      final vod = const M3uEntry(url: 'u2', title: 'T2', durationSeconds: 90);

      expect(live.toChannel(7).streamType, 'live');
      expect(vod.toChannel(8).streamType, 'movie');
      expect(live.toChannel(7).streamId, 7);
      expect(live.toChannel(7).name, 'T1');
    });
  });
}
