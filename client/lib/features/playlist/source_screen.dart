import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers/xtream_source.dart';
import '../../data/repositories/source_repository.dart';

/// Alta y gestión de fuentes.
///
/// Equivale a `/source` de la generación B y a los eventos `ACTIVATE_XTREAM`,
/// `ACTIVATE_M3U` y `ACTIVATE_FG` de la generación A
/// (docs/04-MODELO-FUENTES.md).
///
/// Diferencias deliberadas con el original:
///   • Xtream habla **directo** con el panel, sin el proxy `mikkm.xyz` que
///     filtra las credenciales a un tercero (F-02).
///   • No hay nombre por defecto mágico (`"shai"`) ni separador `---`.
///   • FG Code viene **deshabilitado**.
///   • No hay toggle de "aceptar SSL inválido"
///     (`xtream_accept_ssl_checkBox` en el original).
class SourceScreen extends StatelessWidget {
  const SourceScreen({super.key});

  static const _kinds = <(SourceKind, String, IconData, String)>[
    (
      SourceKind.xtream,
      'Panel Xtream Codes',
      Icons.dns_rounded,
      'Host + usuario + contraseña. Se habla directo con tu panel.'
    ),
    (
      SourceKind.m3u,
      'URL M3U / M3U8',
      Icons.playlist_play_rounded,
      'Cualquier lista M3U a la que tengas acceso legítimo.'
    ),
    (
      SourceKind.github,
      'Playlist en GitHub',
      Icons.code_rounded,
      'github.com/<owner>/<repo>/blob/<path> o un gist público.'
    ),
    (
      SourceKind.fg,
      'FG Code',
      Icons.lock_outline_rounded,
      'Deshabilitado: servicio de terceros sin contrato publicado.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SourceRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fuentes'),
        leading: repo.sources.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRouter.live),
              ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
        children: [
          const _Intro(),
          const SizedBox(height: 14),
          if (repo.sources.isNotEmpty) ...[
            const _SectionTitle('Fuentes dadas de alta'),
            for (final s in repo.sources)
              _SourceCard(
                source: s,
                active: s.id == repo.activeId,
                onActivate: () => repo.setActive(s.id),
                onDelete: () => _confirmDelete(context, repo, s),
              ),
            const SizedBox(height: 18),
          ],
          const _SectionTitle('Añadir una fuente'),
          for (final k in _kinds)
            _KindTile(
              kind: k.$1,
              title: k.$2,
              icon: k.$3,
              subtitle: k.$4,
              enabled: k.$1 != SourceKind.fg,
              onTap: () => _showForm(context, repo, k.$1),
            ),
          const SizedBox(height: 20),
          const _Legal(),
        ],
      ),
      floatingActionButton: repo.sources.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.go(AppRouter.live),
              icon: const Icon(Icons.live_tv_rounded),
              label: const Text('Ver canales'),
            ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SourceRepository repo,
    ContentSource s,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Eliminar "${s.label}"?'),
        content: const Text('Se borrarán también las credenciales guardadas '
            'de esta fuente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) await repo.removeSource(s.id);
  }

  Future<void> _showForm(
    BuildContext context,
    SourceRepository repo,
    SourceKind kind,
  ) async {
    final result = await showModalBottomSheet<ContentSource>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgMid,
      showDragHandle: true,
      builder: (ctx) => _SourceForm(kind: kind),
    );
    if (result == null || !context.mounted) return;

    final s = await repo.addSource(
      kind: result.kind,
      label: result.label,
      url: result.url,
      username: result.username,
      password: result.password,
      code: result.code,
      allowCleartext: result.allowCleartext,
    );
    await repo.refresh();

    if (!context.mounted) return;
    if (repo.state == LoadState.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${s.label}" cargada: '
            '${repo.catalog.channels.length} canales')),
      );
      context.go(AppRouter.live);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cargar "${s.label}": ${repo.error}'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }
}

/* ------------------------------------------------------------------ piezas */

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgHigh.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.accent),
              SizedBox(width: 8),
              Text('Esta app no incluye contenido',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Es un reproductor: reproduce las fuentes que tú aportes. '
            'A diferencia del producto analizado, no consulta ningún catálogo '
            'de terceros ni usa proxies intermedios con tus credenciales.\n\n'
            'Para probar sin configurar nada, activa la fuente "Backend de '
            'referencia (local)" con el servidor de este repo en marcha '
            '(`make backend`).',
            style: TextStyle(height: 1.5, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 2),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
          ),
        ),
      );
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.active,
    required this.onActivate,
    required this.onDelete,
  });

  final ContentSource source;
  final bool active;
  final VoidCallback onActivate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final icon = switch (source.kind) {
      SourceKind.xtream => Icons.dns_rounded,
      SourceKind.m3u => Icons.playlist_play_rounded,
      SourceKind.github => Icons.code_rounded,
      SourceKind.fg => Icons.lock_outline_rounded,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: active ? AppTheme.accent : Colors.transparent,
          width: 1.4,
        ),
      ),
      child: InkWell(
        onTap: onActivate,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Icon(icon, color: active ? AppTheme.accent : AppTheme.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(source.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        source.kind.name,
                        if (source.url.isNotEmpty) _host(source.url),
                        if (source.username.isNotEmpty) source.username,
                        if (source.allowCleartext) 'HTTP sin cifrar',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.check_circle_rounded,
                      size: 18, color: AppTheme.accent),
                ),
              IconButton(
                tooltip: 'Eliminar',
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.textSecondary),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _host(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({
    required this.kind,
    required this.title,
    required this.icon,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final SourceKind kind;
  final String title;
  final IconData icon;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        enabled: enabled,
        leading: Icon(icon,
            color: enabled ? AppTheme.accent : AppTheme.textSecondary),
        title: Text(title),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12, height: 1.35)),
        trailing: enabled
            ? const Icon(Icons.add_rounded)
            : const Icon(Icons.block_rounded, color: AppTheme.textSecondary),
        onTap: enabled ? onTap : null,
      ),
    );
  }
}

class _SourceForm extends StatefulWidget {
  const _SourceForm({required this.kind});
  final SourceKind kind;

  @override
  State<_SourceForm> createState() => _SourceFormState();
}

class _SourceFormState extends State<_SourceForm> {
  final _label = TextEditingController();
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _code = TextEditingController();
  bool _cleartext = false;
  bool _showPass = false;

  @override
  void dispose() {
    for (final c in [_label, _url, _user, _pass, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _needsCredentials => widget.kind == SourceKind.xtream;
  bool get _needsCode => widget.kind == SourceKind.fg;

  String? _validate() {
    if (_url.text.trim().isEmpty && !_needsCode) return 'Falta la URL';
    if (_needsCredentials) {
      if (_user.text.trim().isEmpty) return 'Falta el usuario';
      if (_pass.text.isEmpty) return 'Falta la contraseña';
    }
    if (_needsCode && _code.text.trim().isEmpty) return 'Falta el código FG';
    final u = _url.text.trim();
    if (u.startsWith('http://') && !_cleartext) {
      return 'Esa URL no usa TLS. Activa "Permitir HTTP sin cifrar" '
          'si es lo que quieres — asumiendo el riesgo (F-02).';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.kind) {
      SourceKind.xtream => 'Panel Xtream Codes',
      SourceKind.m3u => 'Lista M3U / M3U8',
      SourceKind.github => 'Playlist en GitHub',
      SourceKind.fg => 'FG Code',
    };

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              switch (widget.kind) {
                SourceKind.xtream =>
                  'Solo paneles de los que tengas credenciales legítimas. '
                      'La conexión es directa: nada pasa por un tercero.',
                SourceKind.m3u =>
                  'Se acepta #EXTINF con tvg-id, tvg-logo, group-title y '
                      '#EXTVLCOPT.',
                SourceKind.github =>
                  'Ejemplo: github.com/miuser/milista/blob/main/canales.m3u',
                SourceKind.fg => 'Deshabilitado en esta réplica.',
              },
              style: const TextStyle(
                  fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _label,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Mi lista',
              ),
            ),
            const SizedBox(height: 12),
            if (!_needsCode) ...[
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: switch (widget.kind) {
                    SourceKind.xtream => 'Host del panel',
                    SourceKind.m3u => 'URL de la lista',
                    _ => 'URL en GitHub',
                  },
                  hintText: switch (widget.kind) {
                    SourceKind.xtream => 'https://mi-panel.example.com',
                    SourceKind.m3u => 'https://…/lista.m3u8',
                    _ => 'https://github.com/…/lista.m3u',
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_needsCredentials) ...[
              TextField(
                controller: _user,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Usuario'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: !_showPass,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  suffixIcon: IconButton(
                    icon: Icon(_showPass
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded),
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Se guarda en el almacenamiento privado de la app. Pendiente: '
                'cifrarlo con Keystore/Keychain (la app original lo guarda en '
                'claro).',
                style: TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 12),
            ],
            if (_needsCode) ...[
              TextField(
                controller: _code,
                decoration: const InputDecoration(labelText: 'Código FG'),
              ),
              const SizedBox(height: 12),
            ],
            SwitchListTile.adaptive(
              value: _cleartext,
              onChanged: (v) => setState(() => _cleartext = v),
              title: const Text('Permitir HTTP sin cifrar'),
              subtitle: const Text(
                'Desactivado por defecto. La app original usa HTTP plano en '
                'todo su backend (hallazgo F-02).',
                style: TextStyle(fontSize: 11.5, height: 1.35),
              ),
              activeColor: AppTheme.warning,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                final err = _validate();
                if (err != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(err)),
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  ContentSource(
                    id: '',
                    kind: widget.kind,
                    label: _label.text.trim().isEmpty
                        ? widget.kind.name
                        : _label.text.trim(),
                    url: _url.text.trim(),
                    username: _user.text.trim(),
                    password: _pass.text,
                    code: _code.text.trim(),
                    allowCleartext: _cleartext,
                  ),
                );
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Añadir y cargar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legal extends StatelessWidget {
  const _Legal();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Aviso',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          SizedBox(height: 6),
          Text(
            'Usa solo fuentes a las que tengas derecho de acceso. Gran parte '
            'del ecosistema IPTV redistribuye canales de pago sin licencia, y '
            'consumirlo puede ser ilícito en tu país.\n\n'
            'Este repo no apunta a ninguna fuente de ese tipo ni replica el '
            'catálogo del producto analizado. Ver '
            'docs/00-LEGAL-Y-ALCANCE.md.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
