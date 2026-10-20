import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Excepción de red con suficiente contexto para pintarla en la UI.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.url, this.cause});

  final String message;
  final int? statusCode;
  final String? url;
  final Object? cause;

  bool get isAuth => statusCode == 401;
  bool get isRateLimited => statusCode == 429;
  bool get isNotFound => statusCode == 404;

  @override
  String toString() =>
      'ApiException($message${statusCode == null ? '' : ', HTTP $statusCode'})';
}

/// Cliente HTTP con reintentos, backoff exponencial y timeouts.
///
/// Diferencia clave con la app original (hallazgo F-02): aquí **no** se ponen
/// credenciales en el query string cuando hay alternativa, y el cliente avisa
/// si se le pide hablar en claro.
class ApiClient {
  ApiClient({
    http.Client? inner,
    this.connectTimeout = const Duration(seconds: 10),
    this.readTimeout = const Duration(seconds: 30),
    this.maxRetries = 2,
    this.userAgent = 'dramalive-replica/1.0.0',
    this.onCleartextUse,
  }) : _inner = inner ?? http.Client();

  final http.Client _inner;
  final Duration connectTimeout;
  final Duration readTimeout;
  final int maxRetries;
  final String userAgent;

  /// Callback para que la UI avise cuando se está hablando sin TLS.
  final void Function(Uri url)? onCleartextUse;

  /// Credenciales por defecto para el backend de referencia.
  String? username;
  String? password;

  void close() => _inner.close();

  Map<String, String> get _headers => {
        'User-Agent': userAgent,
        'Accept': 'application/json',
        if (username != null && password != null)
          // `Authorization: Basic` en lugar del query string del protocolo
          // Xtream. El backend de referencia acepta ambos (docs/05-API.md §1).
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      };

  /* ------------------------------------------------------------------ GET */

  /// GET con reintentos **solo** en errores de red y 5xx (idempotente).
  Future<dynamic> getJson(
    Uri url, {
    Map<String, String>? query,
    bool allowCleartext = false,
  }) async {
    final target = query == null || query.isEmpty
        ? url
        : url.replace(queryParameters: {...url.queryParameters, ...query});

    _guardCleartext(target, allowCleartext);

    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        final backoff = Duration(milliseconds: 500 * (1 << (attempt - 1)));
        await Future<void>.delayed(backoff.clamp(Duration.zero, const Duration(seconds: 2)));
      }
      try {
        final res = await _inner
            .get(target, headers: _headers)
            .timeout(connectTimeout + readTimeout);

        if (res.statusCode == 429) {
          final retry = int.tryParse(res.headers['retry-after'] ?? '') ?? 5;
          throw ApiException(
            'Límite de peticiones superado. Reintenta en ${retry}s.',
            statusCode: 429,
            url: target.toString(),
          );
        }
        if (res.statusCode >= 500) {
          lastError = ApiException('Error del servidor',
              statusCode: res.statusCode, url: target.toString());
          continue; // reintentable
        }
        if (res.statusCode == 401) {
          throw ApiException('Credenciales inválidas',
              statusCode: 401, url: target.toString());
        }
        if (res.statusCode >= 400) {
          throw ApiException(_messageFromBody(res.body) ?? 'Petición rechazada',
              statusCode: res.statusCode, url: target.toString());
        }
        return _decode(res.body, target);
      } on TimeoutException catch (e) {
        lastError = ApiException('Tiempo de espera agotado',
            url: target.toString(), cause: e);
      } on http.ClientException catch (e) {
        lastError =
            ApiException('Fallo de red: ${e.message}', url: target.toString(), cause: e);
      } on ApiException catch (e) {
        if (e.statusCode != null && e.statusCode! >= 500) {
          lastError = e;
          continue;
        }
        rethrow;
      }
    }
    throw lastError is ApiException
        ? lastError
        : ApiException('Fallo desconocido', url: target.toString(), cause: lastError);
  }

  /// GET de texto plano (para playlists M3U).
  Future<String> getText(Uri url, {bool allowCleartext = false}) async {
    _guardCleartext(url, allowCleartext);
    try {
      final res = await _inner
          .get(url, headers: {'User-Agent': userAgent})
          .timeout(connectTimeout + readTimeout);
      if (res.statusCode >= 400) {
        throw ApiException('HTTP ${res.statusCode} al descargar la lista',
            statusCode: res.statusCode, url: url.toString());
      }
      return res.body;
    } on TimeoutException catch (e) {
      throw ApiException('Tiempo de espera agotado al descargar',
          url: url.toString(), cause: e);
    } on http.ClientException catch (e) {
      throw ApiException('Fallo de red: ${e.message}',
          url: url.toString(), cause: e);
    }
  }

  /* -------------------------------------------------------------- helpers */

  void _guardCleartext(Uri url, bool allow) {
    if (url.scheme == 'http') {
      if (!allow) {
        throw ApiException(
          'Se rechazó una URL sin cifrar (${url.host}). '
          'Activa "Permitir HTTP" en Ajustes si es tu intención — '
          'el tráfico sin TLS expone tus credenciales (hallazgo F-02).',
          url: url.toString(),
        );
      }
      onCleartextUse?.call(url);
    }
  }

  dynamic _decode(String body, Uri url) {
    if (body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException catch (e) {
      // El backend real de la app original devuelve HTML 404 de Go cuando la
      // ruta no existe (docs/01 §5.1). Detectarlo da un mensaje mucho mejor.
      final looksHtml = body.trimLeft().startsWith('<');
      throw ApiException(
        looksHtml
            ? 'La respuesta no es JSON (probablemente una ruta inexistente '
                'devolviendo HTML). URL: ${url.path}'
            : 'JSON inválido: ${e.message}',
        url: url.toString(),
      );
    }
  }

  String? _messageFromBody(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) return (j['message'] ?? j['error'])?.toString();
    } catch (_) {}
    return null;
  }
}
