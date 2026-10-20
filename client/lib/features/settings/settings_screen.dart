import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/source_repository.dart';

/// Pantalla de ajustes.
///
/// Sustituye al "remote config" de la app original: en el producto analizado
/// los flags (ads, billing, fuentes, servidores de respaldo, lista de apps
/// prohibidas) los fija **el servidor**, y además se cuelan en el binario como
/// valores por defecto (ver la config embebida en `classes.dex`). Aquí los fija
/// el usuario, en local, y son visibles.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _backend = TextEditingController();
  String? _pingResult;
  bool _pinging = false;

  @override
  void initState() {
    super.initState();
    _backend.text = context.read<SettingsRepository>().env.backendBaseUrl;
  }

  @override
  void dispose() {
    _backend.dispose();
    super.dispose();
  }

  Future<void> _saveAndReload() async {
    final settings = context.read<SettingsRepository>();
    final repo = context.read<SourceRepository>();
    await settings.setBackendUrl(_backend.text);
    await repo.refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Backend → ${settings.env.backendBaseUrl}')),
    );
  }

  Future<void> _ping() async {
    final settings = context.read<SettingsRepository>();
    setState(() {
      _pinging = true;
      _pingResult = null;
    });
    try {
      final res = await http
          .get(Uri.parse(settings.env.healthUrl))
          .timeout(const Duration(seconds: 8));
      setState(() {
        _pingResult = res.statusCode == 200
            ? 'OK · HTTP 200 · ${_clip(res.body)}'
            : 'Fallo · HTTP ${res.statusCode} · ${_clip(res.body)}';
      });
    } catch (e) {
      setState(() => _pingResult = 'No hay conexión: $e');
    } finally {
      if (mounted) setState(() => _pinging = false);
    }
  }

  static String _clip(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').length > 150
          ? '${s.replaceAll(RegExp(r'\s+'), ' ').substring(0, 147)}…'
          : s.replaceAll(RegExp(r'\s+'), ' ');

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsRepository>();
    final repo = context.watch<SourceRepository>();

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          const _Title('Backend de referencia'),
          TextField(
            controller: _backend,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'http://localhost:8080',
              helperText: 'El servidor de backend/ en este repo',
              helperMaxLines: 2,
            ),
            onSubmitted: (_) => _saveAndReload(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _saveAndReload,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Guardar y recargar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pinging ? null : _ping,
                  icon: _pinging
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.monitor_heart_rounded, size: 18),
                  label: const Text('Probar /health'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimary,
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
              ),
            ],
          ),
          if (_pingResult != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.bgHigh.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                _pingResult!,
                style: const TextStyle(fontSize: 11.5, height: 1.4),
              ),
            ),
          ],

          const SizedBox(height: 20),
          const _Title('Seguridad'),
          SwitchListTile.adaptive(
            value: settings.allowCleartext,
            onChanged: (v) async {
              await settings.setAllowCleartext(v);
              await repo.refresh();
            },
            activeColor: AppTheme.warning,
            title: const Text('Permitir HTTP sin cifrar'),
            subtitle: const Text(
              'Apagado por defecto. La app original lo usa en TODO su backend y '
              'además envía las credenciales del panel a un proxy de terceros '
              '(hallazgos F-02 y docs/04 §2.1).',
              style: TextStyle(fontSize: 12, height: 1.45),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading:
                const Icon(Icons.delete_sweep_rounded, color: AppTheme.accent),
            title: const Text('Borrar credenciales guardadas'),
            subtitle: const Text(
              'Útil antes de compartir capturas, logs o el dispositivo.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            onTap: () async {
              await settings.wipeCredentials();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Credenciales borradas')),
              );
            },
          ),

          const SizedBox(height: 20),
          const _Title('Estado de la fuente activa'),
          _KV('Fuente',
              repo.catalog.sourceLabel.isEmpty ? '—' : repo.catalog.sourceLabel),
          _KV('Estado', repo.state.name),
          _KV('Canales', '${repo.catalog.channels.length}'),
          _KV('Grupos', '${repo.catalog.groups.length}'),
          if (repo.error != null) _KV('Último error', repo.error!, warn: true),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: repo.refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Recargar fuente'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textPrimary,
              side: const BorderSide(color: Colors.white24),
            ),
          ),

          const SizedBox(height: 24),
          const _Title('Sobre esta réplica'),
          const Text(
            'Cliente independiente construido a partir del análisis de Drama '
            'Live v13.0.3. No contiene código, assets, branding ni contenido '
            'del producto original.\n\n'
            'Sin SDKs publicitarios (el original integra 15), sin reporting de '
            'crashes a terceros, sin telemetría y sin compras in-app.\n\n'
            'Detalles en docs/02-ARQUITECTURA.md, '
            'docs/03-STACK-DEPENDENCIAS.md y docs/07-HALLAZGOS-SEGURIDAD.md.',
            style: TextStyle(
                fontSize: 12.5, height: 1.55, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
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

class _KV extends StatelessWidget {
  const _KV(this.k, this.v, {this.warn = false});
  final String k;
  final String v;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              k,
              style: const TextStyle(
                  fontSize: 12.5, color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: TextStyle(
                fontSize: 12.5,
                color: warn ? AppTheme.warning : AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
