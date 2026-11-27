import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Fundo desfocado dos cartões da TV ao vivo: o logo do canal ampliado
/// (`cover`) e borrado, desenhado **uma vez** numa imagem pequena e depois só
/// esticado. Com `ImageFiltered` o desfoque era refeito a cada quadro em todos
/// os cartões à vista, e a rolagem travava.
class BlurredLogo extends StatefulWidget {
  const BlurredLogo({
    super.key,
    required this.url,
    required this.sigma,
    this.fallback,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  final String url;

  /// Mesma medida do `ImageFilter.blur`, em pixels da tela.
  final double sigma;

  /// Cor borrada no lugar do logo que não abre; sem ela, não desenha nada.
  final Color? fallback;

  /// Tamanho em que o logo é decodificado (como no `LiveLogo`).
  final int? memCacheWidth;
  final int? memCacheHeight;

  /// Desfoque dentro da imagem pronta: ela é `sigma / _bakedSigma` vezes menor
  /// que a área, o bastante para esticar sem marcar.
  static const double _bakedSigma = 6;

  /// A área é arredondada para múltiplos disto: um cartão que cresce animado
  /// redesenha poucas vezes.
  static const double _step = 8;

  /// Imagens guardadas, da usada há mais tempo para a mais recente. Cada uma
  /// tem poucos KB.
  static const int capacity = 400;
  static final Map<String, ui.Image> _cache = {};

  @visibleForTesting
  static int get cached => _cache.length;

  /// Solta as imagens prontas (hibernação).
  static void release() {
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
  }

  static ui.Image? _take(String key) {
    final image = _cache.remove(key);
    if (image != null) _cache[key] = image;
    return image;
  }

  static ui.Image _keep(String key, ui.Image image) {
    // Quem está na tela segura a própria cópia: descartar aqui não a apaga.
    while (_cache.length >= capacity) {
      _cache.remove(_cache.keys.first)!.dispose();
    }
    return _cache[key] = image;
  }

  static ui.Image _bake(
    ui.Image? source,
    Color? color,
    Size area,
    double sigma,
  ) {
    final shrink = sigma / _bakedSigma;
    final width = (area.width / shrink).ceil().clamp(1, 1024);
    final height = (area.height / shrink).ceil().clamp(1, 1024);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(width / area.width, height / area.height);
    canvas.saveLayer(
      null,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );
    final rect = Offset.zero & area;
    if (source != null) {
      paintImage(
        canvas: canvas,
        rect: rect,
        image: source,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    } else if (color != null) {
      canvas.drawRect(rect, Paint()..color = color);
    }
    canvas.restore();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  @override
  State<BlurredLogo> createState() => _BlurredLogoState();
}

class _BlurredLogoState extends State<BlurredLogo> {
  ImageStream? _stream;
  late final ImageStreamListener _listener =
      ImageStreamListener(_arrived, onError: _broke);
  ImageInfo? _info;
  bool _failed = false;

  /// O logo não estava pronto na primeira vez: entra num fade curto.
  bool _fade = false;
  bool _built = false;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(BlurredLogo old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url ||
        old.memCacheWidth != widget.memCacheWidth ||
        old.memCacheHeight != widget.memCacheHeight) {
      _drop();
      _resolve();
    }
  }

  @override
  void dispose() {
    _drop();
    super.dispose();
  }

  void _drop() {
    _stream?.removeListener(_listener);
    _stream = null;
    _info?.dispose();
    _info = null;
    _failed = false;
    _fade = false;
    _built = false;
  }

  void _resolve() {
    final url = widget.url;
    if (!(url.startsWith('http://') || url.startsWith('https://'))) {
      _failed = true;
      return;
    }
    final provider = ResizeImage.resizeIfNeeded(
      widget.memCacheWidth,
      widget.memCacheHeight,
      CachedNetworkImageProvider(url),
    );
    _resolving = true;
    _stream = provider.resolve(ImageConfiguration.empty)
      ..addListener(_listener);
    _resolving = false;
    if (_info == null && !_failed) _fade = true;
  }

  void _arrived(ImageInfo info, bool synchronous) {
    if (_info != null) {
      info.dispose(); // GIF: só o primeiro quadro interessa
      return;
    }
    _info = info;
    if (!_resolving && mounted) setState(() {});
  }

  void _broke(Object error, StackTrace? stack) {
    _failed = true;
    if (!_resolving && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double round(double v) =>
            (v / BlurredLogo._step).round().clamp(1, 1000) * BlurredLogo._step;
        final area = Size(
          round(constraints.maxWidth),
          round(constraints.maxHeight),
        );
        final suffix = '${widget.sigma}|${area.width}x${area.height}';
        final key = _failed
            ? 'cor|${widget.fallback?.toARGB32()}|$suffix'
            : '${widget.url}|$suffix';
        var image = BlurredLogo._take(key);
        if (image == null && (_failed ? widget.fallback != null : _info != null)) {
          image = BlurredLogo._keep(
            key,
            BlurredLogo._bake(
              _failed ? null : _info!.image,
              widget.fallback,
              area,
              widget.sigma,
            ),
          );
        }
        if (!_built) {
          _built = true;
          // Já pronta (recriada pela rolagem): aparece na hora.
          if (image != null) _fade = false;
        }
        if (image == null) return const SizedBox.expand();
        Widget draw(double opacity) => RawImage(
              image: image,
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              fit: BoxFit.fill,
              opacity: AlwaysStoppedAnimation(opacity),
              filterQuality: FilterQuality.medium,
            );
        if (!_fade || MediaQuery.disableAnimationsOf(context)) return draw(1);
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 120),
          builder: (context, t, _) => draw(t),
        );
      },
    );
  }
}
