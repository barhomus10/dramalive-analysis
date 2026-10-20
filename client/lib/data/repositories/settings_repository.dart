import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/env.dart';
import '../providers/xtream_source.dart';

/// Persistencia de ajustes y fuentes.
///
/// Equivalente funcional del "remote config" de la app original (el getter
/// `gajj()` del bundle web y la config embebida en `classes.dex` del APK), con
/// dos diferencias importantes:
///
///   1. Aquí la config la controla el usuario, no un servidor remoto.
///   2. **No se guardan credenciales de terceros** ni tokens de crash
///      reporting. Ver hallazgo F-01.
class SettingsRepository extends ChangeNotifier {
  static const _kEnv = 'dla.env';
  static const _kSources = 'dla.sources';
  static const _kCleartext = 'dla.allowCleartext';
  static const _kBackend = 'dla.backendUrl';
  static const _kLastSourceId = 'dla.lastSourceId';

  Env _env = const Env(
    backendBaseUrl: Env.defaultBackend,
    appVersion: '1.0.0',
    buildNumber: '1',
    platform: 'unknown',
  );

  bool _allowCleartext = false;
  String _lastSourceId = '';
  bool _loaded = false;

  Env get env => _env;
  bool get allowCleartext => _allowCleartext;
  bool get isLoaded => _loaded;
  String get lastSourceId => _lastSourceId;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final backend = sp.getString(_kBackend);
    final cleartext = sp.getBool(_kCleartext) ?? false;
    _lastSourceId = sp.getString(_kLastSourceId) ?? '';

    _allowCleartext = cleartext;
    _env = _env.copyWith(
      backendBaseUrl: backend ?? Env.defaultBackend,
      allowCleartext: cleartext,
    );

    final raw = sp.getString(_kEnv);
    if (raw != null && raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _env = Env(
          backendBaseUrl: (j['backendBaseUrl'] ?? _env.backendBaseUrl).toString(),
          appVersion: (j['appVersion'] ?? _env.appVersion).toString(),
          buildNumber: (j['buildNumber'] ?? _env.buildNumber).toString(),
          platform: (j['platform'] ?? _env.platform).toString(),
          allowCleartext: j['allowCleartext'] == true,
        );
      } catch (e) {
        debugPrint('settings: env corrupto, se usa el por defecto ($e)');
      }
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> setBackendUrl(String url) async {
    final normalized = Env.normalizeSourceUrl(url, preferHttps: false);
    if (normalized.isEmpty) return;
    _env = _env.copyWith(backendBaseUrl: normalized);
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kBackend, normalized);
    await sp.setString(_kEnv, jsonEncode({
      'backendBaseUrl': _env.backendBaseUrl,
      'appVersion': _env.appVersion,
      'buildNumber': _env.buildNumber,
      'platform': _env.platform,
      'allowCleartext': _env.allowCleartext,
    }));
  }

  /// Cambia el permiso de tráfico en claro.
  ///
  /// La app original permite HTTP sin más (F-02). Aquí se exige confirmación
  /// explícita y la UI muestra un aviso persistente mientras esté activo.
  Future<void> setAllowCleartext(bool value) async {
    _allowCleartext = value;
    _env = _env.copyWith(allowCleartext: value);
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kCleartext, value);
  }

  Future<void> setLastSourceId(String id) async {
    _lastSourceId = id;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kLastSourceId, id);
  }

  /* ------------------------------------------------------------- sources */

  Future<List<ContentSource>> loadSources() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_kSources) ?? const [];
    final out = <ContentSource>[];
    for (final item in raw) {
      try {
        out.add(ContentSource.fromJson(jsonDecode(item) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('settings: fuente corrupta ignorada ($e)');
      }
    }
    return out;
  }

  Future<void> saveSources(List<ContentSource> sources) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(
      _kSources,
      sources.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }

  /// Borra credenciales guardadas. Útil antes de compartir capturas o logs.
  Future<void> wipeCredentials() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kSources);
    notifyListeners();
  }
}
