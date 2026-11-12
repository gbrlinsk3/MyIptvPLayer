import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/library_import.dart';
import '../../library/video_thumb.dart';
import '../../state/app_controller.dart';
import '../../playback/playback_controller.dart';
import '../../state/app_scope.dart';

/// Controles do ao vivo: volume/mudo, gravação e tela cheia.
/// Não há pause nem barra de progresso, de propósito (a "pausa" é só da
/// gravação).
/// Aparecem ao mover o mouse sobre o vídeo e somem depois de ~2,5 s parados.
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.playback,
    required this.fullscreen,
    required this.onToggleFullscreen,
  });

  final PlaybackController playback;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  bool _visible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _poke();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _poke() {
    _hideTimer?.cancel();
    if (!_visible) setState(() => _visible = true);
    _hideTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _hideNow() {
    _hideTimer?.cancel();
    if (mounted && _visible) setState(() => _visible = false);
  }

  static String _fmt(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final h = d.inHours;
    return '${h > 0 ? '${two(h)}:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _startRec() async {
    final app = AppScope.read(context);
    final name = app.selected?.name ?? 'Canal';
    final err = await widget.playback.startRecording(
      folder: app.downloads.folder,
      channelName: name,
    );
    if (err != null) _snack(err);
  }

  Future<void> _stopRec() async {
    final app = AppScope.read(context);
    final name = app.selected?.name ?? 'Canal';
    final files = await widget.playback.stopRecording();
    if (files.isEmpty) {
      _snack('Nada foi gravado (nenhum dado chegou do servidor).');
      return;
    }
    // Coloca os arquivos em Minha biblioteca (Arquivos).
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final when = '${two(now.day)}/${two(now.month)} ${two(now.hour)}:${two(now.minute)}';
    for (var i = 0; i < files.length; i++) {
      await app.imports.save(LibraryImport(
        filePath: files[i],
        title: '$name — gravação $when${files.length > 1 ? ' (${i + 1})' : ''}',
        kind: 'recording',
      ));
    }
    unawaited(_makeCovers(app, files));
    _snack(files.length == 1
        ? 'Gravação salva em Minha biblioteca: ${files.first}'
        : 'Gravação salva em Minha biblioteca (${files.length} arquivos, pasta de downloads).');
  }

  /// Capa de cada gravação: um quadro aleatório do próprio vídeo (em segundo
  /// plano; se falhar, o cartão fica sem capa).
  Future<void> _makeCovers(AppController app, List<String> files) async {
    for (final f in files) {
      final thumb = await generateVideoThumb(f);
      if (thumb == null) continue;
      for (final item in app.imports.items) {
        if (item.filePath == f) {
          item.image = thumb;
          await app.imports.save(item);
        }
      }
    }
  }

  Future<void> _resumeRec() async {
    final err = await widget.playback.resumeRecording();
    if (err != null) _snack(err);
  }

  IconData _volumeIcon(double volume) {
    if (volume <= 0) return Icons.volume_off;
    if (volume < 50) return Icons.volume_down;
    return Icons.volume_up;
  }

  @override
  Widget build(BuildContext context) {
    final bar = ListenableBuilder(
      listenable: widget.playback,
      builder: (context, _) {
        final p = widget.playback;
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 28, 12, 8),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xB3000000)],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: p.muted ? 'Ativar som' : 'Silenciar',
                onPressed: p.toggleMute,
                icon: Icon(_volumeIcon(p.volume), color: Colors.white, size: 22),
              ),
              SizedBox(
                width: 120,
                // Sem altura fixa o Slider ocupa toda a altura disponível,
                // esticando a barra e deixando-a no meio do vídeo.
                height: 40,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Colors.white,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: p.volume,
                    min: 0,
                    max: 100,
                    onChanged: p.setVolume,
                    onChangeEnd: (v) => AppScope.read(context).saveVolume(v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (p.recState == RecState.idle)
                IconButton(
                  tooltip: 'Gravar este canal',
                  onPressed: _startRec,
                  icon: const Icon(Icons.fiber_manual_record,
                      color: Color(0xFFE5484D), size: 22),
                )
              else ...[
                IconButton(
                  tooltip: p.recState == RecState.recording
                      ? 'Pausar gravação'
                      : 'Continuar gravação',
                  onPressed: p.recState == RecState.recording
                      ? p.pauseRecording
                      : _resumeRec,
                  icon: Icon(
                    p.recState == RecState.recording
                        ? Icons.pause
                        : Icons.fiber_manual_record,
                    color: p.recState == RecState.recording
                        ? Colors.white
                        : const Color(0xFFE5484D),
                    size: 22,
                  ),
                ),
                IconButton(
                  tooltip: 'Parar e salvar gravação',
                  onPressed: _stopRec,
                  icon: const Icon(Icons.stop, color: Colors.white, size: 22),
                ),
                Text(
                  _fmt(p.recElapsed),
                  style: const TextStyle(
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              const Spacer(),
              IconButton(
                tooltip:
                    widget.fullscreen ? 'Sair da tela cheia' : 'Tela cheia',
                onPressed: widget.onToggleFullscreen,
                icon: Icon(
                  widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          ),
        );
      },
    );

    // Marcador "REC" sempre visível (mesmo com os controles escondidos).
    final badge = ListenableBuilder(
      listenable: widget.playback,
      builder: (context, _) {
        final p = widget.playback;
        if (p.recState == RecState.idle) return const SizedBox.shrink();
        final rec = p.recState == RecState.recording;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xB3000000),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.fiber_manual_record,
                size: 12,
                color: rec ? const Color(0xFFE5484D) : Colors.white54,
              ),
              const SizedBox(width: 6),
              Text(
                p.recNotice ?? '${rec ? 'REC' : 'PAUSADO'}  ${_fmt(p.recElapsed)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );

    final controls = MouseRegion(
      onHover: (_) => _poke(),
      onEnter: (_) => _poke(),
      onExit: (_) => _hideNow(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: widget.onToggleFullscreen,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(ignoring: !_visible, child: bar),
          ),
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        controls,
        Positioned(top: 12, left: 12, child: IgnorePointer(child: badge)),
      ],
    );
  }
}
