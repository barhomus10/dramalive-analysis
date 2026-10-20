import '../../core/config/env.dart';
import '../api_client.dart';
import '../models/models.dart';

/// Una fuente de contenido dada de alta.
///
/// Equivale a lo que la app original dispara como `ACTIVATE_XTREAM`,
/// `ACTIVATE_M3U` y `ACTIVATE_FG` (docs/04-MODELO-FUENTES.md §1).
enum SourceKind { xtream, m3u, fg, github }

class ContentSource {
  ContentSource({
    required this.id,
    required this.kind,
    required this.label,
    this.url = '',
    this.username = '',
    this.password = '',
    this.code = '',
    this.enabled = true,
    this.allowCleartext = false,
  });

  final String id;
  final SourceKind kind;
  String label;
  String url;
  String username;
  String password;

  /// FG Code (kind == fg).
  String code;

  bool enabled;

  /// Por defecto **false**. La app original permite HTTP plano en todo el
  /// backend (hallazgo F-02); aquí hay que activarlo a conciencia y por fuente.
  bool allowCleartext;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'label': label,
        'url': url,
        'username': username,
        // La contraseña se persiste porque el usuario necesita que su fuente
        // sobreviva a un reinicio. Se guarda en `shared_preferences`, que en
        // Android acaba en un XML del directorio privado de la app.
        //
        // MEJORA PENDIENTE respecto del original: cifrar en reposo con
        // flutter_secure_preferences (Keystore/Keychain). La app original
        // guarda las credenciales del panel del usuario en claro.
        'password': password,
        'code': code,
        'enabled': enabled,
        'allowCleartext': allowCleartext,
      };

  factory ContentSource.fromJson(Map<String, dynamic> j) => ContentSource(
        id: (j['id'] ?? '').toString(),
        kind: SourceKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => SourceKind.m3u,
        ),
        label: (j['label'] ?? 'Fuente').toString(),
        url: (j['url'] ?? '').toString(),
        username: (j['username'] ?? '').toString(),
        password: (j['password'] ?? '').toString(),
        code: (j['code'] ?? '').toString(),
        enabled: j['enabled'] != false,
        allowCleartext: j['allowCleartext'] == true,
      );
}

/// Fuente Xtream Codes.
///
/// Habla **directo** con el panel del usuario. La app original interpone
/// `mikkm.xyz/android/androidApi.php?url=…&username=…&password=…`, lo que hace
/// que las credenciales del usuario viajen en el query string a un dominio de
/// un tercero y sin cifrar (hallazgos F-02 y docs/04 §2.1). Aquí no.
class XtreamSource {
  XtreamSource(this._client);

  final ApiClient _client;

  Uri _api(ContentSource s) => Uri.parse(
        '${Env.normalizeSourceUrl(s.url)}/player_api.php',
      );

  Future<UserInfo> handshake(ContentSource s) async {
    final json = await _client.getJson(
      _api(s),
      query: {'username': s.username, 'password': s.password},
      allowCleartext: s.allowCleartext,
    );
    if (json is! Map<String, dynamic>) {
      throw ApiException('Respuesta inesperada del panel', url: _api(s).toString());
    }
    final user = json['user_info'];
    if (user is! Map<String, dynamic>) {
      throw ApiException('El panel no devolvió user_info', url: _api(s).toString());
    }
    final info = UserInfo.fromJson(user);
    if (!info.auth) {
      throw ApiException('El panel rechazó las credenciales (auth=0)',
          statusCode: 401, url: _api(s).toString());
    }
    return info;
  }

  Future<List<Category>> categories(ContentSource s, String kind) async {
    final action = switch (kind) {
      'live' => 'get_live_categories',
      'vod' => 'get_vod_categories',
      'series' => 'get_series_categories',
      _ => throw ApiException('kind desconocido: $kind'),
    };
    final json = await _action(s, action);
    return _asList(json).map(Category.fromJson).toList();
  }

  Future<List<Channel>> streams(ContentSource s, String kind, {String? categoryId}) async {
    final action = switch (kind) {
      'live' => 'get_live_streams',
      'vod' => 'get_vod_streams',
      _ => throw ApiException('kind desconocido: $kind'),
    };
    final json = await _action(s, action,
        categoryId == null ? null : {'category_id': categoryId});
    return _asList(json).map(Channel.fromJson).toList();
  }

  Future<List<Series>> series(ContentSource s, {String? categoryId}) async {
    final json = await _action(
        s, 'get_series', categoryId == null ? null : {'category_id': categoryId});
    return _asList(json).map(Series.fromJson).toList();
  }

  Future<List<EpgEntry>> epg(ContentSource s, Object streamId, {int limit = 4}) async {
    final json = await _action(s, 'get_short_epg', {
      'stream_id': '$streamId',
      'limit': '$limit',
    });
    if (json is Map<String, dynamic> && json['epg_listings'] is List) {
      return (json['epg_listings'] as List)
          .whereType<Map<String, dynamic>>()
          .map(EpgEntry.fromJson)
          .toList();
    }
    return const [];
  }

  /// URL de reproducción. Sigue el formato estándar del protocolo, que sí
  /// incluye usuario y contraseña en la ruta — es lo que espera cualquier
  /// panel Xtream. Se construye en local y nunca pasa por un tercero.
  String playbackUrl(ContentSource s, Channel c, {bool vod = false}) {
    final base = Env.normalizeSourceUrl(s.url);
    final ext = vod ? (c.containerExtension ?? 'mp4') : 'm3u8';
    final segment = vod ? 'movie' : 'live';
    return '$base/$segment/${Uri.encodeComponent(s.username)}/'
        '${Uri.encodeComponent(s.password)}/${c.streamId}.$ext';
  }

  Future<dynamic> _action(ContentSource s, String action,
      [Map<String, String>? extra]) {
    return _client.getJson(
      _api(s),
      query: {
        'username': s.username,
        'password': s.password,
        'action': action,
        ...?extra,
      },
      allowCleartext: s.allowCleartext,
    );
  }

  static List<Map<String, dynamic>> _asList(dynamic json) {
    if (json is List) {
      return json.whereType<Map<String, dynamic>>().toList();
    }
    if (json is Map<String, dynamic> && json['error'] != null) {
      throw ApiException(json['message']?.toString() ?? json['error'].toString());
    }
    return const [];
  }
}

/// Fuente M3U/M3U8 (y GitHub, que se reduce a M3U tras reescribir la URL).
class M3uSource {
  M3uSource(this._client);

  final ApiClient _client;

  /// Resuelve la URL efectiva: para [SourceKind.github] aplica la
  /// transformación a `raw.githubusercontent.com`; para el resto normaliza.
  Uri resolve(ContentSource s) {
    final raw = s.url.trim();
    if (s.kind == SourceKind.github) {
      final rewritten = Env.normalizeGithub(raw);
      if (rewritten == null) {
        throw ApiException(
          'URL de GitHub no reconocida. Formatos aceptados:\n'
          '  github.com/<owner>/<repo>/blob/<path>\n'
          '  github.com/<owner>/<repo>/raw/<path>\n'
          '  gist.github.com/<user>/<id>',
          url: raw,
        );
      }
      return Uri.parse(rewritten);
    }
    final normalized = Env.normalizeSourceUrl(raw);
    if (normalized.isEmpty) {
      throw ApiException('URL vacía', url: raw);
    }
    return Uri.parse(normalized);
  }

  Future<String> fetch(ContentSource s) =>
      _client.getText(resolve(s), allowCleartext: s.allowCleartext);
}

/// Fuente FG Code.
///
/// **Deshabilitada por defecto.** Depende de un servicio de terceros
/// (`fgcode.store` / `fgcode.org`) cuyo contrato no está publicado, y la app
/// original lo usa como mecanismo principal de distribución de listas
/// (docs/04 §4). Se incluye la forma del provider para completar el mapa
/// arquitectónico, pero la réplica no lo llama salvo que se active a mano.
class FgSource {
  FgSource(this._client, {this.enabled = false, this.baseUrl = 'https://fgcode.store'});

  final ApiClient _client;
  final bool enabled;
  final String baseUrl;

  Uri resolve(ContentSource s) {
    if (s.code.trim().isEmpty) {
      throw ApiException('Falta el código FG');
    }
    return Uri.parse('$baseUrl/${Uri.encodeComponent(s.code.trim())}');
  }

  Future<String> fetch(ContentSource s) async {
    if (!enabled) {
      throw ApiException(
        'FG Code está deshabilitado en esta réplica. Es un servicio de '
        'terceros sin contrato publicado; aporta una M3U propia en su lugar.',
      );
    }
    return _client.getText(resolve(s), allowCleartext: s.allowCleartext);
  }
}
