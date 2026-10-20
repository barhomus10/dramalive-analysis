import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/source_repository.dart';

/// Aviso persistente de tráfico sin cifrar.
///
/// La app original permite HTTP plano en **todo** el backend sin avisar
/// (hallazgo F-02). La réplica hace lo contrario: si hay cleartext activo,
/// hay una banda amarilla permanente en pantalla.
class CleartextBanner extends StatelessWidget {
  const CleartextBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsRepository>();
    final sources = context.watch<SourceRepository>();

    final cleartextOn = settings.allowCleartext ||
        settings.env.isCleartext ||
        sources.cleartextWarnings.isNotEmpty;
    if (!cleartextOn) return const SizedBox.shrink();

    return Material(
      color: AppTheme.warning.withOpacity(0.16),
      child: InkWell(
        onTap: () => _showDetail(context, settings, sources),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.no_encryption_gmailerrorred_rounded,
                  size: 18, color: AppTheme.warning),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Tráfico sin cifrar activo — tus credenciales viajan en claro',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppTheme.warning),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(
    BuildContext context,
    SettingsRepository settings,
    SourceRepository sources,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgMid,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Por qué ves este aviso',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'La app original de Drama Live habla con todo su backend por '
                'HTTP plano, y envía el usuario y la contraseña del panel IPTV '
                'en el query string a un dominio de un tercero (mikkm.xyz).\n\n'
                'Cualquiera en la misma red puede leerlas, y además puede '
                'modificar las respuestas — incluido el servidor del que la app '
                'se descarga las actualizaciones.\n\n'
                'Esta réplica lo desactiva por defecto. Si lo has activado tú, '
                'asumes ese riesgo.\n\n'
                'Detalle en docs/07-HALLAZGOS-SEGURIDAD.md (F-02).',
                style: TextStyle(height: 1.55, fontSize: 14),
              ),
              const SizedBox(height: 16),
              if (sources.cleartextWarnings.isNotEmpty) ...[
                const Text('Avisos de esta sesión:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                for (final w in sources.cleartextWarnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('· $w',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary)),
                  ),
                const SizedBox(height: 16),
              ],
              SwitchListTile.adaptive(
                value: settings.allowCleartext,
                onChanged: (v) async {
                  await settings.setAllowCleartext(v);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                title: const Text('Permitir HTTP sin cifrar'),
                subtitle: const Text('Desactivar exige recargar la fuente'),
                activeColor: AppTheme.accent,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
