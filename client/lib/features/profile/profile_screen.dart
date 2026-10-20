import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/source_repository.dart';

/// `ProfileActivity` de la app original.
///
/// Aquí no hay cuenta de usuario ni avatar: el original los gestiona contra su
/// backend propio (`/profile`, con `ic_profile_male.png` /
/// `ic_profile_female.png` en los assets). La réplica muestra el estado de la
/// sesión contra la fuente activa, que es lo único que tiene sentido sin
/// backend de terceros.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SourceRepository>();
    final settings = context.watch<SettingsRepository>();
    final info = repo.catalog.userInfo;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppTheme.bgHigh,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_rounded,
                      size: 28, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        info?.username ?? repo.catalog.sourceLabel ?? 'Sin sesión',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        info == null
                            ? 'Esta fuente no requiere cuenta'
                            : '${info.status}${info.isTrial ? ' · prueba' : ''}',
                        style: const TextStyle(
                            fontSize: 12.5, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (info != null) ...[
          const _Title('Sesión en el panel'),
          _Row('Autenticado', info.auth ? 'sí' : 'no'),
          _Row('Estado', info.status),
          _Row(
            'Caduca',
            info.expires == null
                ? 'sin caducidad'
                : DateFormat.yMMMMd('es').add_Hm().format(info.expires!),
            warn: info.isExpired,
          ),
          _Row('Conexiones',
              '${info.activeConnections} / ${info.maxConnections}'),
          _Row('Formatos', info.allowedOutputFormats.join(', ')),
          const SizedBox(height: 16),
        ],
        const _Title('Entorno'),
        _Row('Backend', settings.env.backendBaseUrl),
        _Row('Versión', 'v${settings.env.appVersion}+${settings.env.buildNumber}'),
        _Row('Plataforma', settings.env.platform),
        _Row('HTTP sin cifrar', settings.allowCleartext ? 'PERMITIDO' : 'bloqueado',
            warn: settings.allowCleartext),
        _Row('Canales cargados', '${repo.catalog.channels.length}'),
        _Row('Grupos', '${repo.catalog.groups.length}'),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => context.push(AppRouter.settings),
          icon: const Icon(Icons.settings_rounded),
          label: const Text('Ajustes'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textPrimary,
            side: const BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () async {
            await settings.wipeCredentials();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Credenciales borradas del dispositivo')),
            );
            context.go(AppRouter.source);
          },
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Borrar credenciales guardadas'),
          style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
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

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: warn ? AppTheme.warning : AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
