/// Modelos del dominio.
///
/// Los nombres de campo y —muy importante— **los tipos** reproducen el
/// contrato Xtream Codes real, con sus inconsistencias incluidas, para que un
/// cliente escrito contra el backend de referencia funcione también contra un
/// panel real. Ver docs/05-API.md.
///
/// Inconsistencias deliberadas que se respetan:
///   • `category_id` es **String** aunque sea numérico.
///   • `stream_id` es **int**.
///   • `auth` es **int** (1/0), no bool.
///   • `exp_date` es **String** con epoch en segundos.
///   • Los campos de EPG vienen en **base64**.
library;

import 'dart:convert';

class Category {
  const Category({
    required this.id,
    required this.name,
    this.parentId = 0,
  });

  final String id; // ← string, a propósito
  final String name;
  final int parentId;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['category_id']?.toString() ?? '',
        name: (json['category_name'] ?? '').toString(),
        parentId: _asInt(json['parent_id']),
      );
}

class Channel {
  const Channel({
    required this.streamId,
    required this.name,
    this.streamType = 'live',
    this.icon = '',
    this.epgChannelId = '',
    this.categoryId = '',
    this.num = 0,
    this.tvArchive = false,
    this.tvArchiveDuration = 0,
    this.containerExtension,
    this.plot,
    this.rating,
  });

  final int streamId; // ← int, a propósito
  final String name;
  final String streamType;
  final String icon;
  final String epgChannelId;
  final String categoryId;
  final int num;
  final bool tvArchive;
  final int tvArchiveDuration;
  final String? containerExtension;
  final String? plot;
  final String? rating;

  bool get isVod => streamType == 'movie' || containerExtension != null;

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
        streamId: _asInt(json['stream_id']),
        name: (json['name'] ?? '').toString(),
        streamType: (json['stream_type'] ?? 'live').toString(),
        icon: (json['stream_icon'] ?? json['cover'] ?? '').toString(),
        epgChannelId: (json['epg_channel_id'] ?? '').toString(),
        categoryId: json['category_id']?.toString() ?? '',
        num: _asInt(json['num']),
        tvArchive: _asInt(json['tv_archive']) == 1,
        tvArchiveDuration: _asInt(json['tv_archive_duration']),
        containerExtension: json['container_extension']?.toString(),
        plot: json['plot']?.toString(),
        rating: json['rating']?.toString(),
      );

  @override
  String toString() => 'Channel($streamId, $name)';
}

class Series {
  const Series({
    required this.seriesId,
    required this.name,
    this.cover = '',
    this.plot = '',
    this.genre = '',
    this.rating = '',
    this.categoryId = '',
  });

  final int seriesId;
  final String name;
  final String cover;
  final String plot;
  final String genre;
  final String rating;
  final String categoryId;

  factory Series.fromJson(Map<String, dynamic> json) => Series(
        seriesId: _asInt(json['series_id']),
        name: (json['name'] ?? '').toString(),
        cover: (json['cover'] ?? '').toString(),
        plot: (json['plot'] ?? '').toString(),
        genre: (json['genre'] ?? '').toString(),
        rating: (json['rating'] ?? '').toString(),
        categoryId: json['category_id']?.toString() ?? '',
      );
}

class Episode {
  const Episode({
    required this.id,
    required this.title,
    required this.streamId,
    this.episodeNum = 0,
    this.duration = '',
    this.containerExtension = 'mp4',
  });

  final String id;
  final String title;
  final int streamId;
  final int episodeNum;
  final String duration;
  final String containerExtension;

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
        id: json['id']?.toString() ?? '',
        title: (json['title'] ?? '').toString(),
        streamId: _asInt(json['stream_id']),
        episodeNum: _asInt(json['episode_num']),
        duration: (json['info']?['duration'] ?? '').toString(),
        containerExtension: (json['container_extension'] ?? 'mp4').toString(),
      );
}

class EpgEntry {
  const EpgEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.startTimestamp,
    required this.stopTimestamp,
  });

  final String id;
  final String title;
  final String description;
  final int startTimestamp;
  final int stopTimestamp;

  DateTime get start => DateTime.fromMillisecondsSinceEpoch(startTimestamp * 1000);
  DateTime get stop => DateTime.fromMillisecondsSinceEpoch(stopTimestamp * 1000);
  Duration get length => stop.difference(start);

  /// El protocolo Xtream entrega `title` y `description` en **base64**.
  /// Se decodifica con tolerancia: si no es base64 válido, se usa tal cual.
  factory EpgEntry.fromJson(Map<String, dynamic> json) => EpgEntry(
        id: json['id']?.toString() ?? '',
        title: _decodeMaybeB64(json['title']),
        description: _decodeMaybeB64(json['description']),
        startTimestamp: _asInt(json['start_timestamp']),
        stopTimestamp: _asInt(json['stop_timestamp']),
      );

  bool get isNow {
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(stop);
  }
}

class UserInfo {
  const UserInfo({
    required this.username,
    required this.auth,
    required this.status,
    required this.expDate,
    this.isTrial = false,
    this.maxConnections = 1,
    this.activeConnections = 0,
    this.allowedOutputFormats = const ['m3u8'],
  });

  final String username;
  final bool auth; // en el JSON viene como int 1/0
  final String status;
  final int expDate; // epoch segundos; 0 = sin caducidad
  final bool isTrial;
  final int maxConnections;
  final int activeConnections;
  final List<String> allowedOutputFormats;

  DateTime? get expires =>
      expDate <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(expDate * 1000);

  bool get isExpired {
    final e = expires;
    return e != null && e.isBefore(DateTime.now());
  }

  factory UserInfo.fromJson(Map<String, dynamic> json) => UserInfo(
        username: (json['username'] ?? '').toString(),
        auth: _asInt(json['auth']) == 1,
        status: (json['status'] ?? 'Unknown').toString(),
        expDate: _asInt(json['exp_date']),
        isTrial: json['is_trial']?.toString() == '1',
        maxConnections: _asInt(json['max_connections']),
        activeConnections: _asInt(json['active_cons']),
        allowedOutputFormats: (json['allowed_output_formats'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const ['m3u8'],
      );
}

class ServerInfo {
  const ServerInfo({
    required this.url,
    required this.port,
    required this.protocol,
    required this.timezone,
    required this.timestampNow,
  });

  final String url;
  final int port;
  final String protocol;
  final String timezone;
  final int timestampNow;

  factory ServerInfo.fromJson(Map<String, dynamic> json) => ServerInfo(
        url: (json['url'] ?? '').toString(),
        port: _asInt(json['port']),
        protocol: (json['server_protocol'] ?? 'http').toString(),
        timezone: (json['timezone'] ?? 'UTC').toString(),
        timestampNow: _asInt(json['timestamp_now']),
      );
}

/// Bloque de portada de `/catalog/featured`.
class FeaturedBlock {
  const FeaturedBlock({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle = '',
    this.items = const [],
    this.streamId,
  });

  final String id;
  final String type; // 'hero' | 'row'
  final String title;
  final String subtitle;
  final List<Channel> items;
  final int? streamId;

  factory FeaturedBlock.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return FeaturedBlock(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? 'row').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      streamId: json['stream_id'] == null ? null : _asInt(json['stream_id']),
      items: raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(Channel.fromJson)
              .toList(growable: false)
          : const [],
    );
  }
}

/* ------------------------------------------------------------------ utils */

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim()) ?? 0;
}

String _decodeMaybeB64(dynamic v) {
  if (v == null) return '';
  final s = v.toString();
  if (s.isEmpty) return '';
  try {
    final decoded = utf8.decode(base64.decode(s));
    // Un base64 válido puede decodificar a basura si el campo NO era base64.
    // Heurística: si contiene caracteres de control, no era base64.
    if (decoded.codeUnits.any((c) => c < 0x09 || (c > 0x0d && c < 0x20))) {
      return s;
    }
    return decoded;
  } catch (_) {
    return s;
  }
}
