import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_theme.dart';

/// `MultyPlayerActivity` / `FullScreenActivity` de la app original.
///
/// La original usa ExoPlayer/Media3 (HLS + DASH + hooks de DRM, según los
/// literales `updateDrmInitData`, `dashif.org`, `aomedia.org` del DEX).
/// Aquí se usa **media_kit** (libmpv), que cubre HLS/DASH en Android, desktop
/// y web con una sola API.
///
/// Se incluye `wakelock_plus`, igual que la generación B (aparece en su
/// `AssetManifest.json` con `no_sleep.js`): mantener la pantalla encendida
/// durante la reproducción.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    required this.url,
    required this.title,
    this.kind = 'live',
    this.epgChannelId,
    super.key,
  });

  final String url;
  final String title;
  final String kind;
  final String? epgChannelId;

  bool get isLive => kind != 'vod';

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(
      bufferSize: 32 * 1024 * 1024,
      logLevel: MPVLogLevel.warn,
    ),
  );
  late final VideoController _controller = VideoController(_player);
  String? _error;
  bool _controlsVisible = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    WakelockPlus.enable().catchError((_) {});
    _player.stream.error.listen((e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    });
    _player.stream.playing.listen((_) {
      if (mounted) setState(() => _loading = false);
    });
    _player.stream.completed.listen((_) {
      if (mounted) setState(() => _loading = false);
    });
    _open();
  }

  Future<void> _open() async {
    if (widget.url.trim().isEmpty) {
      setState(() {
        _error = 'URL vacía';
        _loading = false;
      });
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await _player.open(Media(widget.url), play: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo abrir la fuente: $e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable().catchError((_) {});
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => setState(() => _controlsVisible = !_controlsVisible),
            child: Video(
              controller: _controller,
              controls: NoVideoControls,
              fill: Colors.black,
              errorBuilder: (context, message) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.accent),
                  ),
                ),
              ),
            ),
          ),

          if (_loading && _error == null)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppTheme.accent),
              ),
            ),

          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_rounded,
                        size: 44, color: AppTheme.accent),
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'El backend de referencia genera segmentos MPEG-TS '
                      'sintéticos: estructuralmente válidos pero sin imagen '
                      'decodificable. Es a propósito — este proyecto no '
                      'redistribuye contenido de terceros.\n\n'
                      'Para ver imagen real, apunta una fuente M3U propia '
                      'o activa PASSTHROUGH=1 en el backend con contenido '
                      'del que tengas licencia.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.5,
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _open,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),

          // Controles
          AnimatedOpacity(
            opacity: _controlsVisible ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent, Colors.black87],
                    stops: [0.0, 0.28, 0.78],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_rounded),
                              onPressed: () => Navigator.of(context).maybePop(),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    [
                                      widget.isLive ? 'EN DIRECTO' : 'VOD',
                                      if (widget.epgChannelId?.isNotEmpty ?? false)
                                        widget.epgChannelId!,
                                    ].join(' · '),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Pantalla completa',
                              icon: const Icon(Icons.fullscreen_rounded),
                              onPressed: () {
                                SystemChrome.setEnabledSystemUIMode(
                                  SystemUiMode.immersiveSticky,
                                );
                                SystemChrome.setPreferredOrientations([
                                  DeviceOrientation.landscapeLeft,
                                  DeviceOrientation.landscapeRight,
                                ]);
                              },
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _BottomBar(player: _player, isLive: widget.isLive),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.player, required this.isLive});

  final Player player;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          IconButton(
            iconSize: 34,
            icon: const Icon(Icons.play_arrow_rounded),
            onPressed: () => player.playOrPause(),
          ),
          if (!isLive) ...[
            IconButton(
              icon: const Icon(Icons.replay_10_rounded),
              onPressed: () => player.seekBy(const Duration(seconds: -10)),
            ),
            IconButton(
              icon: const Icon(Icons.forward_30_rounded),
              onPressed: () => player.seekBy(const Duration(seconds: 30)),
            ),
          ],
          const Spacer(),
          StreamBuilder<double>(
            stream: player.stream.volume,
            initialData: 100.0,
            builder: (context, snap) {
              final muted = (snap.data ?? 100) <= 0;
              return IconButton(
                tooltip: muted ? 'Activar sonido' : 'Silenciar',
                icon: Icon(muted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded),
                onPressed: () => player.setVolume(muted ? 100 : 0),
              );
            },
          ),
          IconButton(
            tooltip: 'Reiniciar',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () => player.seek(Duration.zero),
          ),
        ],
      ),
    );
  }
}
