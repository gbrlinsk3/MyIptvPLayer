import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Troca entre duas imagens de fundo com a transição "derretendo" do MorphSlider
/// (React Bits): as duas imagens são deslocadas por ruído e se misturam seguindo
/// esse ruído. É feita por um shader (`shaders/morph.frag`).
///
/// Preenche o espaço do pai (como um `Positioned.fill`). Quando [image] muda, a
/// nova imagem é carregada em segundo plano e só então a transição começa; até
/// lá a antiga continua na tela. Com [image] nulo aparece o [placeholder].
///
/// Cai para um cross-fade simples (mesmo [fit]/[alignment]) quando o shader não
/// carrega ou dá erro, ou quando as animações estão desativadas
/// (`MediaQuery.disableAnimationsOf`); nesse último caso a troca é direta.
class MorphImageSwitcher extends StatefulWidget {
  const MorphImageSwitcher({
    super.key,
    required this.image,
    this.duration = const Duration(milliseconds: 1100),
    this.curve = Curves.easeInOutCubic,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.placeholder,
  });

  final ImageProvider? image;
  final Duration duration;
  final Curve curve;
  final BoxFit fit;
  final Alignment alignment;

  /// Mostrado enquanto não há imagem (e nenhuma imagem anterior para segurar).
  final Widget? placeholder;

  /// Só para testes: força o caminho de cross-fade, como se o shader não
  /// tivesse carregado.
  @visibleForTesting
  static bool debugForceFallback = false;

  static Future<ui.FragmentProgram?>? _programFuture;

  /// Só para testes: descarta o shader em cache e o carrega de novo, devolvendo
  /// se ele ficou disponível (num `runAsync`, pois o carregamento é real).
  @visibleForTesting
  static Future<bool> debugReloadProgram() async {
    _programFuture = null;
    return (await _loadProgram()) != null;
  }

  /// Carrega o shader uma única vez. `null` se não for possível (o widget usa o
  /// cross-fade nesse caso).
  static Future<ui.FragmentProgram?> _loadProgram() {
    return _programFuture ??= () async {
      try {
        return await ui.FragmentProgram.fromAsset('shaders/morph.frag');
      } catch (e) {
        debugPrint('MorphImageSwitcher: shader indisponível ($e)');
        return null;
      }
    }();
  }

  @override
  State<MorphImageSwitcher> createState() => _MorphImageSwitcherState();
}

class _MorphImageSwitcherState extends State<MorphImageSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this)..addStatusListener(_onStatus);

  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  bool _shaderFailed = false;

  /// Imagem estável na tela e, durante a transição, a que está entrando. Cada
  /// uma é um clone (próprio) e é descartada por esta classe.
  ImageInfo? _current;
  ImageInfo? _incoming;

  ImageProvider? _resolved;
  ImageProvider? _loaded;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    MorphImageSwitcher._loadProgram().then((program) {
      if (mounted && program != null) setState(() => _program = program);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A primeira resolução precisa do contexto (ImageConfiguration).
    if (_resolved != widget.image || (_stream == null && widget.image != null)) {
      _resolve(widget.image);
    }
  }

  @override
  void didUpdateWidget(MorphImageSwitcher old) {
    super.didUpdateWidget(old);
    if (widget.image != _resolved) _resolve(widget.image);
  }

  @override
  void dispose() {
    _stopListening();
    _controller.dispose();
    _current?.dispose();
    _incoming?.dispose();
    _shader?.dispose();
    super.dispose();
  }

  void _stopListening() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  void _resolve(ImageProvider? provider) {
    _stopListening();
    _resolved = provider;
    _loaded = null;
    if (provider == null) {
      _controller.stop();
      _current?.dispose();
      _incoming?.dispose();
      _current = null;
      _incoming = null;
      return;
    }
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) => _onImage(provider, info),
      onError: (error, stack) => _onImageError(provider, error),
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _onImage(ImageProvider provider, ImageInfo info) {
    // Imagens animadas (GIF) emitem vários quadros: só o primeiro conta.
    if (!mounted || provider != _resolved || provider == _loaded) return;
    _loaded = provider;
    final mine = info.clone();
    if (_current == null) {
      setState(() => _current = mine);
      return;
    }
    if (_controller.isAnimating) _finish(); // fecha a transição anterior
    setState(() => _incoming = mine);
    if (_useShader) {
      _controller.duration = widget.duration;
      _controller.forward(from: 0);
    } else {
      // Sem shader: o cross-fade é do AnimatedSwitcher, aqui só troca de vez.
      _finish();
    }
  }

  void _onImageError(ImageProvider provider, Object error) {
    if (!mounted || provider != _resolved) return;
    // Sem imagem estável o fallback mostra o placeholder (errorBuilder); com
    // uma já na tela, ela continua. O shader em si não tem culpa: não o desliga.
    debugPrint('MorphImageSwitcher: erro ao carregar a imagem ($error)');
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finish();
  }

  /// Promove a imagem que entrava a estável e libera a antiga.
  void _finish() {
    final incoming = _incoming;
    if (incoming == null) return;
    final old = _current;
    _controller.stop();
    if (mounted) {
      setState(() {
        _current = incoming;
        _incoming = null;
      });
    } else {
      _current = incoming;
      _incoming = null;
    }
    old?.dispose();
  }

  bool get _useShader =>
      _program != null &&
      !_shaderFailed &&
      !MorphImageSwitcher.debugForceFallback &&
      !MediaQuery.disableAnimationsOf(context);

  void _onShaderError() {
    if (mounted && !_shaderFailed) setState(() => _shaderFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    if (image == null) return widget.placeholder ?? const SizedBox.shrink();

    final disable = MediaQuery.disableAnimationsOf(context);
    if (!_useShader || _current == null) {
      return _FadeFallback(
        image: image,
        duration: disable ? Duration.zero : widget.duration,
        curve: widget.curve,
        fit: widget.fit,
        alignment: widget.alignment,
        placeholder: widget.placeholder,
      );
    }
    return SizedBox.expand(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _MorphPainter(
            shader: _shader ??= _program!.fragmentShader(),
            controller: _controller,
            curve: widget.curve,
            from: _current!,
            to: _incoming,
            fit: widget.fit,
            alignment: widget.alignment,
            onError: _onShaderError,
          ),
        ),
      ),
    );
  }
}

/// Cross-fade simples, usado quando o shader não está disponível.
class _FadeFallback extends StatelessWidget {
  const _FadeFallback({
    required this.image,
    required this.duration,
    required this.curve,
    required this.fit,
    required this.alignment,
    this.placeholder,
  });

  final ImageProvider image;
  final Duration duration;
  final Curve curve;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: curve,
      switchOutCurve: curve,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      child: Image(
        key: ValueKey(image),
        image: image,
        fit: fit,
        alignment: alignment,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder ?? const SizedBox.shrink(),
      ),
    );
  }
}

class _MorphPainter extends CustomPainter {
  _MorphPainter({
    required this.shader,
    required this.controller,
    required this.curve,
    required this.from,
    required this.to,
    required this.fit,
    required this.alignment,
    required this.onError,
  }) : super(repaint: controller);

  final ui.FragmentShader shader;
  final AnimationController controller;
  final Curve curve;
  final ImageInfo from;
  final ImageInfo? to;
  final BoxFit fit;
  final Alignment alignment;
  final VoidCallback onError;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final incoming = to;
    final t = curve.transform(controller.value.clamp(0.0, 1.0));
    if (incoming == null || t >= 1 || (!controller.isAnimating && t <= 0)) {
      _plain(canvas, size, incoming != null && t >= 1 ? incoming : from);
      return;
    }
    try {
      final fromMap = _map(from, size);
      final toMap = _map(incoming, size);
      final edge = fromMap.covers && toMap.covers ? 1.0 : 0.0;
      shader
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, t)
        ..setFloat(3, edge)
        ..setFloat(4, fromMap.ax)
        ..setFloat(5, fromMap.ay)
        ..setFloat(6, fromMap.bx)
        ..setFloat(7, fromMap.by)
        ..setFloat(8, toMap.ax)
        ..setFloat(9, toMap.ay)
        ..setFloat(10, toMap.bx)
        ..setFloat(11, toMap.by)
        ..setImageSampler(0, from.image)
        ..setImageSampler(1, incoming.image);
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    } catch (e) {
      debugPrint('MorphImageSwitcher: falha no shader ($e)');
      _plain(canvas, size, incoming);
      SchedulerBinding.instance.addPostFrameCallback((_) => onError());
    }
  }

  void _plain(Canvas canvas, Size size, ImageInfo info) {
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: info.image,
      scale: info.scale,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
    );
  }

  /// Mapa pixel da tela -> coordenada (0..1) da imagem, igual ao que `paintImage`
  /// faria com [fit] e [alignment].
  _ImageMap _map(ImageInfo info, Size size) {
    final logical = Size(
      info.image.width / info.scale,
      info.image.height / info.scale,
    );
    final fitted = applyBoxFit(fit, logical, size);
    final dest = alignment.inscribe(fitted.destination, Offset.zero & size);
    final src = alignment.inscribe(fitted.source, Offset.zero & logical);
    final sx = src.width / dest.width;
    final sy = src.height / dest.height;
    return _ImageMap(
      ax: sx / logical.width,
      ay: sy / logical.height,
      bx: (src.left - dest.left * sx) / logical.width,
      by: (src.top - dest.top * sy) / logical.height,
      covers: dest.left <= 0.5 &&
          dest.top <= 0.5 &&
          dest.right >= size.width - 0.5 &&
          dest.bottom >= size.height - 0.5,
    );
  }

  @override
  bool shouldRepaint(_MorphPainter old) =>
      old.from.image != from.image ||
      old.to?.image != to?.image ||
      old.fit != fit ||
      old.alignment != alignment ||
      old.curve != curve ||
      old.shader != shader;
}

class _ImageMap {
  const _ImageMap({
    required this.ax,
    required this.ay,
    required this.bx,
    required this.by,
    required this.covers,
  });

  final double ax, ay, bx, by;

  /// A imagem cobre toda a área (sem faixas), então a borda pode se repetir.
  final bool covers;
}
