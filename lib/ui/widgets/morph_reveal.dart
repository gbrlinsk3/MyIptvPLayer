import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'morph_image_switcher.dart';

/// Troca de uma imagem por outra com a transição "derretendo" do Morph Slider
/// (React Bits), no tamanho da tela. Usada ao fim da abertura: [from] é a cena
/// capturada e [to] é o Início capturado.
///
/// Usa o mesmo shader dos banners (`shaders/morph.frag`). Se o shader não
/// carregar ou falhar, chama [onDone] na hora (a cena simplesmente some).
/// Quem cria é dono das imagens e as libera depois de [onDone].
class MorphReveal extends StatefulWidget {
  const MorphReveal({
    super.key,
    required this.from,
    required this.to,
    required this.onDone,
    this.duration = const Duration(milliseconds: 1100),
    this.curve = Curves.easeInOutCubic,
  });

  final ui.Image from;
  final ui.Image to;
  final VoidCallback onDone;
  final Duration duration;
  final Curve curve;

  @override
  State<MorphReveal> createState() => _MorphRevealState();
}

class _MorphRevealState extends State<MorphReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) widget.onDone();
        });
  ui.FragmentShader? _shader;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    MorphImageSwitcher.loadProgram().then((program) {
      if (!mounted) return;
      if (program == null) {
        widget.onDone();
        return;
      }
      setState(() => _shader = program.fragmentShader());
      _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _shader?.dispose();
    super.dispose();
  }

  void _fail() {
    if (_failed) return;
    _failed = true;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    // Bloqueia cliques no Início até a transição acabar.
    return AbsorbPointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _RevealPainter(
            from: widget.from,
            to: widget.to,
            shader: _shader,
            controller: _c,
            curve: widget.curve,
            onError: _fail,
          ),
        ),
      ),
    );
  }
}

class _RevealPainter extends CustomPainter {
  _RevealPainter({
    required this.from,
    required this.to,
    required this.shader,
    required this.controller,
    required this.curve,
    required this.onError,
  }) : super(repaint: controller);

  final ui.Image from;
  final ui.Image to;
  final ui.FragmentShader? shader;
  final AnimationController controller;
  final Curve curve;
  final VoidCallback onError;

  void _plain(Canvas canvas, Size size, ui.Image image) {
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final s = shader;
    final p = curve.transform(controller.value.clamp(0.0, 1.0));
    // Antes do shader carregar a cena continua na tela.
    if (s == null || p <= 0) {
      _plain(canvas, size, from);
      return;
    }
    if (p >= 1) {
      _plain(canvas, size, to);
      return;
    }
    try {
      // As duas imagens têm o tamanho da tela: coordenada = pixel / tamanho.
      s
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, p)
        ..setFloat(3, 1) // borda se repete (preenche tudo)
        ..setFloat(4, 1 / size.width)
        ..setFloat(5, 1 / size.height)
        ..setFloat(6, 0)
        ..setFloat(7, 0)
        ..setFloat(8, 1 / size.width)
        ..setFloat(9, 1 / size.height)
        ..setFloat(10, 0)
        ..setFloat(11, 0)
        ..setImageSampler(0, from)
        ..setImageSampler(1, to);
      canvas.drawRect(Offset.zero & size, Paint()..shader = s);
    } catch (e) {
      debugPrint('MorphReveal: falha no shader ($e)');
      _plain(canvas, size, to);
      WidgetsBinding.instance.addPostFrameCallback((_) => onError());
    }
  }

  @override
  bool shouldRepaint(_RevealPainter old) =>
      old.from != from || old.to != to || old.shader != shader;
}
