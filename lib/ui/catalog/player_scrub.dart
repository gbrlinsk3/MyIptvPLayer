import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/app_log.dart';

/// Gera quadros de prévia para a barra de tempo abrindo o MESMO arquivo em um
/// segundo player, sem som e pausado, e tirando "fotos" nos pontos pedidos.
/// Só é usado com arquivos locais (baixados): em streaming isso abriria uma
/// segunda conexão no provedor.
class ScrubPreviewer {
  ScrubPreviewer(this.path);

  final String path;

  /// Último quadro pronto: segundo (arredondado) e bytes da imagem.
  final ValueNotifier<({int second, Uint8List bytes})?> frame = ValueNotifier(null);

  Player? _player;
  // Mantido de propósito: o VideoController precisa existir para a captura.
  // ignore: unused_field
  VideoController? _video;
  bool _opened = false;
  bool _failed = false;
  bool _busy = false;
  bool _disposed = false;
  Duration? _latest;
  final Map<int, Uint8List> _cache = {};

  bool get failed => _failed;

  /// Pede o quadro mais próximo de [position]; pedidos em sequência são
  /// atropelados (só o último importa).
  void request(Duration position) {
    if (_failed || _disposed) return;
    _latest = position;
    if (!_busy) unawaited(_loop());
  }

  Future<void> _loop() async {
    _busy = true;
    try {
      while (_latest != null && !_disposed) {
        final target = _latest!;
        _latest = null;
        final bucket = (target.inSeconds ~/ 5) * 5;
        final cached = _cache[bucket];
        if (cached != null) {
          frame.value = (second: bucket, bytes: cached);
          continue;
        }
        await _ensureOpen();
        if (_failed || _disposed) break;
        final p = _player!;
        await p.seek(Duration(seconds: bucket));
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (_disposed) break;
        final bytes = await p.screenshot();
        if (_disposed) break;
        if (bytes != null && bytes.isNotEmpty) {
          if (_cache.length > 60) _cache.remove(_cache.keys.first);
          _cache[bucket] = bytes;
          frame.value = (second: bucket, bytes: bytes);
        }
      }
    } catch (e) {
      AppLog.warn('player.previa', e);
      _failed = true; // sem prévia; a barra continua só com o tempo
    } finally {
      _busy = false;
    }
  }

  Future<void> _ensureOpen() async {
    if (_opened) return;
    final p = Player();
    _player = p;
    _video = VideoController(p);
    await p.setVolume(0);
    await p.open(Media(path), play: false);
    // Espera o arquivo informar a duração (sinal de que abriu).
    await p.stream.duration
        .firstWhere((d) => d > Duration.zero)
        .timeout(const Duration(seconds: 8));
    _opened = true;
  }

  Future<void> dispose() async {
    _disposed = true;
    frame.dispose();
    _video = null;
    try {
      await _player?.dispose();
    } catch (e) {
      AppLog.warn('player.previa.dispose', e);
    }
  }
}

/// Barra de tempo do player com balão de prévia (tempo e, se houver, imagem)
/// ao passar o mouse.
class ScrubBar extends StatefulWidget {
  const ScrubBar({
    super.key,
    required this.value,
    required this.max,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
    this.previewer,
  });

  /// Posição e duração em milissegundos.
  final double value;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final ScrubPreviewer? previewer;

  @override
  State<ScrubBar> createState() => _ScrubBarState();
}

class _ScrubBarState extends State<ScrubBar> {
  double? _hoverFraction;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _hover(double dx, double width) {
    if (!widget.enabled || width <= 0) return;
    // O trilho do Slider tem uma margem de ~10 px de cada lado.
    final f = ((dx - 10) / (width - 20)).clamp(0.0, 1.0);
    setState(() => _hoverFraction = f);
    final prev = widget.previewer;
    if (prev != null) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 90), () {
        prev.request(Duration(milliseconds: (f * widget.max).round()));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final f = _hoverFraction;
        return MouseRegion(
          onHover: (e) => _hover(e.localPosition.dx, width),
          onExit: (_) => setState(() => _hoverFraction = null),
          child: SizedBox(
            height: 28,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: f == null ? 3 : 5,
                      activeTrackColor: AppColors.accent,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Colors.white,
                      overlayShape: SliderComponentShape.noOverlay,
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: f == null ? 5 : 7,
                      ),
                    ),
                    child: Slider(
                      value: widget.value.clamp(0.0, widget.max).toDouble(),
                      min: 0,
                      max: widget.max,
                      onChanged: widget.enabled ? widget.onChanged : null,
                      onChangeEnd: widget.onChangeEnd,
                    ),
                  ),
                ),
                if (f != null) _bubble(width, f),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bubble(double width, double f) {
    const imageW = 208.0;
    const imageH = 117.0;
    final prev = widget.previewer;
    final x = 10 + f * (width - 20);
    final time = formatDuration(Duration(milliseconds: (f * widget.max).round()));
    final hasPrev = prev != null && !prev.failed;
    final bubbleW = hasPrev ? imageW : 64.0;
    final left = (x - bubbleW / 2).clamp(0.0, (width - bubbleW).clamp(0.0, width));
    return Positioned(
      left: left,
      bottom: 34,
      width: bubbleW,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasPrev)
              Container(
                width: imageW,
                height: imageH,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                  boxShadow: const [
                    BoxShadow(color: Color(0x88000000), blurRadius: 16),
                  ],
                ),
                child: ValueListenableBuilder(
                  valueListenable: prev.frame,
                  builder: (context, fr, _) => fr == null
                      ? const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white54,
                            ),
                          ),
                        )
                      : Image.memory(
                          fr.bytes,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          cacheWidth: 416,
                        ),
                ),
              ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                time,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
