import 'package:flutter/foundation.dart';

import '../api_client.dart';
import '../models/models.dart';
import '../providers/m3u_parser.dart';
import '../providers/xtream_source.dart';
import 'settings_repository.dart';

/// Estado de la carga de una fuente.
enum LoadState { idle, loading, ready, error }

/// Catálogo resuelto, independiente de la fuente de la que venga.
///
/// Es la abstracción a la que la app original converge tras
/// `ACTIVATE_XTREAM` / `ACTIVATE_M3U` / `ACTIVATE_FG`: cuatro mecanismos de
/// entrada, una sola forma de pintar la UI.
class ResolvedCatalog {
  const ResolvedCatalog({
    this.groups = const [],
    this.channels = const [],
    this.userInfo,
    this.serverInfo,
    this.sourceLabel = '',
    this.warnings = const [],
  });

  final List<String> groups;
  final List<Channel> channels;
  final UserInfo? userInfo;
  final ServerInfo? serverInfo;
  final String sourceLabel;
  final List<String> warnings;

  static const empty = ResolvedCatalog();

  bool get isEmpty => channels.isEmpty;

  List<Channel> byGroup(String group) => group == _allGroup
      ? channels
      : channels.where((c) => c.categoryId == group).toList();

  static const String _allGroup = '__all__';
  static String get allGroup => _allGroup;
}

/// Repositorio de fuentes: alta, baja, activación y carga del catálogo.
class SourceRepository extends ChangeNotifier {
  SourceRepository(this._settings) {
    _client = ApiClient(
      onCleartextUse: (url) {
        final msg = 'Tráfico sin cifrar hacia ${url.host}';
        if (!_cleartextWarnings.contains(msg)) {
          _cleartextWarnings.add(msg);
          notifyListeners();
        }
      },
    );
    _xtream = XtreamSource(_client);
    _m3u = M3uSource(_client);
    _fg = FgSource(_client, enabled: false);
  }

  final SettingsRepository _settings;
  late final ApiClient _client;
  late final XtreamSource _xtream;
  late final M3uSource _m3u;
  late final FgSource _fg;

  final List<ContentSource> _sources = [];
  final Set<String> _cleartextWarnings = {};

  LoadState _state = LoadState.idle;
  String? _error;
  ResolvedCatalog _catalog = ResolvedCatalog.empty;
  String _activeId = '';

  List<ContentSource> get sources => List.unmodifiable(_sources);
  LoadState get state => _state;
  String? get error => _error;
  ResolvedCatalog get catalog => _catalog;
  String get activeId => _activeId;
  Set<String> get cleartextWarnings => Set.unmodifiable(_cleartextWarnings);

  ContentSource? get active =>
      _sources.where((s) => s.id == _activeId).firstOrNull;

  ApiClient get client => _client;
  XtreamSource get xtream => _xtream;

  /* ------------------------------------------------------------- lifecycle */

  Future<void> load() async {
    _sources
      ..clear()
      ..addAll(await _settings.loadSources());

    if (_sources.isEmpty) {
      // Fuente por defecto: el backend de referencia de este repo.
      _sources.add(ContentSource(
        id: 'mock',
        kind: SourceKind.xtream,
        label: 'Backend de referencia (local)',
        url: _settings.env.backendBaseUrl,
        username: 'demo',
        password: 'demo',
        allowCleartext: _settings.allowCleartext,
      ));
    }

    final preferred = _settings.lastSourceId;
    _activeId = _sources.any((s) => s.id == preferred)
        ? preferred
        : (_sources.firstWhere((s) => s.enabled, orElse: () => _sources.first)).id;

    notifyListeners();
    await refresh();
  }

  Future<void> persist() => _settings.saveSources(_sources);

  /* ------------------------------------------------------------- mutations */

  Future<ContentSource> addSource({
    required SourceKind kind,
    required String label,
    String url = '',
    String username = '',
    String password = '',
    String code = '',
    bool allowCleartext = false,
  }) async {
    final id = '${kind.name}-${DateTime.now().millisecondsSinceEpoch}';
    final s = ContentSource(
      id: id,
      kind: kind,
      label: label.trim().isEmpty ? kind.name : label.trim(),
      url: url.trim(),
      username: username.trim(),
      password: password,
      code: code.trim(),
      allowCleartext: allowCleartext,
    );
    _sources.add(s);
    _activeId = id;
    await _settings.setLastSourceId(id);
    await persist();
    notifyListeners();
    return s;
  }

  Future<void> removeSource(String id) async {
    _sources.removeWhere((s) => s.id == id);
    if (_activeId == id) {
      _activeId = _sources.isEmpty ? '' : _sources.first.id;
      await _settings.setLastSourceId(_activeId);
    }
    await persist();
    notifyListeners();
    if (_activeId.isEmpty) {
      _catalog = ResolvedCatalog.empty;
      _state = LoadState.idle;
    } else {
      await refresh();
    }
  }

  Future<void> setActive(String id) async {
    if (!_sources.any((s) => s.id == id)) return;
    _activeId = id;
    await _settings.setLastSourceId(id);
    notifyListeners();
    await refresh();
  }

  /* ----------------------------------------------------------------- load */

  Future<void> refresh() async {
    final s = active;
    if (s == null) {
      _state = LoadState.idle;
      _catalog = ResolvedCatalog.empty;
      notifyListeners();
      return;
    }

    _state = LoadState.loading;
    _error = null;
    notifyListeners();

    try {
      _catalog = switch (s.kind) {
        SourceKind.xtream => await _loadXtream(s),
        SourceKind.m3u || SourceKind.github => await _loadM3u(s),
        SourceKind.fg => await _loadFg(s),
      };
      _state = LoadState.ready;
    } on ApiException catch (e) {
      _state = LoadState.error;
      _error = e.message;
    } catch (e, st) {
      _state = LoadState.error;
      _error = 'Error inesperado: $e';
      debugPrintStack(stackTrace: st);
    }
    notifyListeners();
  }

  Future<ResolvedCatalog> _loadXtream(ContentSource s) async {
    final info = await _xtream.handshake(s);
    final categories = await _xtream.categories(s, 'live');
    final channels = await _xtream.streams(s, 'live');

    // El panel puede devolver categorías que no cubren todos los canales.
    final groups = <String>{for (final c in categories) c.name};
    final idToName = {for (final c in categories) c.id: c.name};
    for (final ch in channels) {
      final g = idToName[ch.categoryId];
      if (g != null) groups.add(g);
    }

    final warnings = <String>[];
    if (info.isExpired) warnings.add('La cuenta del panel caducó el ${info.expires}.');
    if (info.isTrial) warnings.add('Cuenta de prueba del panel.');
    if (s.allowCleartext || s.url.startsWith('http://')) {
      warnings.add('Esta fuente usa HTTP sin cifrar. Tus credenciales viajan '
          'en claro (ver hallazgo F-02).');
    }

    return ResolvedCatalog(
      groups: groups.toList(),
      // El catálogo usa el *nombre* del grupo como categoryId para que el
      // filtrado por grupo funcione igual que en una M3U.
      channels: channels
          .map((c) => Channel(
                streamId: c.streamId,
                name: c.name,
                streamType: c.streamType,
                icon: c.icon,
                epgChannelId: c.epgChannelId,
                categoryId: idToName[c.categoryId] ?? c.categoryId,
                num: c.num,
                tvArchive: c.tvArchive,
                tvArchiveDuration: c.tvArchiveDuration,
                containerExtension: c.containerExtension,
                plot: c.plot,
                rating: c.rating,
              ))
          .toList(),
      userInfo: info,
      sourceLabel: s.label,
      warnings: warnings,
    );
  }

  Future<ResolvedCatalog> _loadM3u(ContentSource s) async {
    final body = await _m3u.fetch(s);
    final parsed = const M3uParser().parse(body);

    // Una M3U no tiene ids estables: se asignan por posición y se guarda el
    // mapa id → URL para poder resolver la reproducción después.
    _m3uUrlByStreamId.clear();
    final channels = <Channel>[];
    for (var i = 0; i < parsed.entries.length; i++) {
      final e = parsed.entries[i];
      final id = i + 1;
      _m3uUrlByStreamId[id] = e.url;
      channels.add(Channel(
        streamId: id,
        name: e.title,
        streamType: e.isLive ? 'live' : 'movie',
        icon: e.logo,
        epgChannelId: e.tvgId,
        categoryId: e.group,
        num: id,
      ));
    }

    final warnings = [...parsed.errors];
    if (s.allowCleartext || s.url.startsWith('http://')) {
      warnings.add('Esta fuente usa HTTP sin cifrar (ver hallazgo F-02).');
    }

    return ResolvedCatalog(
      groups: parsed.groups,
      channels: channels,
      sourceLabel: s.label,
      warnings: warnings,
    );
  }

  Future<ResolvedCatalog> _loadFg(ContentSource s) async {
    final body = await _fg.fetch(s); // lanza si está deshabilitado
    final parsed = const M3uParser().parse(body);
    var nextId = 1;
    return ResolvedCatalog(
      groups: parsed.groups,
      channels: parsed.entries
          .map((e) => Channel(
                streamId: nextId++,
                name: e.title,
                icon: e.logo,
                epgChannelId: e.tvgId,
                categoryId: e.group,
              ))
          .toList(),
      sourceLabel: s.label,
      warnings: parsed.errors,
    );
  }

  /* ------------------------------------------------------------- playback */

  /// URL de reproducción de un canal de la fuente activa.
  ///
  /// Para M3U devuelve la URL tal cual (o con sus cabeceras, que el
  /// reproductor debe aplicar). Para Xtream compone la URL estándar.
  String? playbackUrlFor(Channel c) {
    final s = active;
    if (s == null) return null;
    return switch (s.kind) {
      SourceKind.xtream => _xtream.playbackUrl(s, c),
      SourceKind.m3u || SourceKind.github || SourceKind.fg =>
        _m3uUrlByStreamId[c.streamId],
    };
  }

  /// Las M3U no tienen id estable: se reconstruye el mapa en cada carga.
  final Map<int, String> _m3uUrlByStreamId = {};

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
