/// Configuración de entorno de la réplica.
///
/// Equivale al `aRy(baseUrl, version, build, ..., platform)` que construye la
/// app original en su `main()` (ver docs/01-RECON-WEB.md §5). La diferencia
/// clave: aquí **todo** es configurable en caliente desde la pantalla de
/// ajustes y nada apunta a infraestructura de terceros por defecto.
library;

class Env {
  const Env({
    required this.backendBaseUrl,
    required this.appVersion,
    required this.buildNumber,
    required this.platform,
    this.allowCleartext = false,
    this.requestTimeout = const Duration(seconds: 10),
    this.readTimeout = const Duration(seconds: 30),
    this.maxRetries = 2,
  });

  /// Backend de referencia de este repo (`backend/`).
  static const String defaultBackend = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:8080',
  );

  final String backendBaseUrl;
  final String appVersion;
  final String buildNumber;
  final String platform;

  /// La app original permite HTTP plano en todo el backend (hallazgo F-02).
  /// Aquí está **apagado por defecto**: hay que activarlo explícitamente y la
  /// UI muestra un aviso permanente cuando lo está.
  final bool allowCleartext;

  final Duration requestTimeout;
  final Duration readTimeout;

  /// Reintentos con backoff exponencial (500 ms → 2 s), solo en GET idempotentes.
  final int maxRetries;

  Env copyWith({
    String? backendBaseUrl,
    bool? allowCleartext,
  }) =>
      Env(
        backendBaseUrl: backendBaseUrl ?? this.backendBaseUrl,
        appVersion: appVersion,
        buildNumber: buildNumber,
        platform: platform,
        allowCleartext: allowCleartext ?? this.allowCleartext,
        requestTimeout: requestTimeout,
        readTimeout: readTimeout,
        maxRetries: maxRetries,
      );

  String get apiBase => '$backendBaseUrl/player_api.php';
  String get configUrl => '$backendBaseUrl/config/remote';
  String get featuredUrl => '$backendBaseUrl/catalog/featured';
  String get searchUrl => '$backendBaseUrl/catalog/search';
  String get sourcesUrl => '$backendBaseUrl/sources';
  String get healthUrl => '$backendBaseUrl/health';

  /// URL de reproducción en directo, con el formato Xtream estándar.
  /// `<base>/live/<user>/<pass>/<stream_id>.m3u8`
  String liveStreamUrl({
    required String username,
    required String password,
    required Object streamId,
    String extension = 'm3u8',
  }) =>
      '$backendBaseUrl/live/$username/$password/$streamId.$extension';

  String vodStreamUrl({
    required String username,
    required String password,
    required Object streamId,
    required String containerExtension,
  }) =>
      '$backendBaseUrl/movie/$username/$password/$streamId.$containerExtension';

  /// `github.com/<o>/<r>/(blob|raw)/<path>` → `raw.githubusercontent.com/...`
  ///
  /// Misma transformación que hace la app original (regex literal encontrada en
  /// `main.dart.js`), ampliada con soporte de gists.
  static String? normalizeGithub(String url) {
    final repo = RegExp(
      r'^https?://(?:www\.)?github\.com/([^/]+)/([^/]+)/(?:blob|raw)/(.+)$',
      caseSensitive: false,
    ).firstMatch(url.trim());
    if (repo != null) {
      return 'https://raw.githubusercontent.com/'
          '${repo.group(1)}/${repo.group(2)}/${repo.group(3)}';
    }
    final gist = RegExp(
      r'^https?://gist\.github\.com/([^/]+)/([a-f0-9]+)(?:/raw)?/?$',
      caseSensitive: false,
    ).firstMatch(url.trim());
    if (gist != null) {
      return 'https://gist.githubusercontent.com/'
          '${gist.group(1)}/${gist.group(2)}/raw';
    }
    return null;
  }

  /// Normalización de URL de fuente.
  ///
  /// La original hace: si no lleva esquema → añade `https://`; recorta el `/`
  /// final y lo vuelve a añadir. Se reproduce, pero **sin** el separador mágico
  /// `---` ni el nombre por defecto `shai` (ver docs/04-MODELO-FUENTES.md §2.1).
  static String normalizeSourceUrl(String raw, {bool preferHttps = true}) {
    var url = raw.trim();
    if (url.isEmpty) return url;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) {
      url = '${preferHttps ? 'https' : 'http'}://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  bool get isCleartext => backendBaseUrl.startsWith('http://');

  @override
  String toString() =>
      'Env($backendBaseUrl, v$appVersion+$buildNumber, $platform, cleartext=$allowCleartext)';
}
