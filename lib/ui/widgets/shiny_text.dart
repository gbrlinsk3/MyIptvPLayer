import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Texto com uma faixa de brilho diagonal que passa em loop (inspirado no
/// ShinyText do React Bits).
///
/// Com [active] falso (ou `MediaQuery.disableAnimations` ligado) é só o texto
/// normal, sem controller rodando. A cor-base é a do [style]
/// (ou a do `DefaultTextStyle`); o brilho é [shineColor] ou branco.
class ShinyText extends StatefulWidget {
  const ShinyText({
    super.key,
    required this.text,
    this.style,
    this.active = true,
    this.speed = const Duration(milliseconds: 2200),
    this.shineColor,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final bool active;

  /// Duração de uma passada completa da faixa.
  final Duration speed;
  final Color? shineColor;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<ShinyText> createState() => _ShinyTextState();
}

class _ShinyTextState extends State<ShinyText> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this, duration: widget.speed);
  bool _semAnimacao = false;

  bool get _rodando => widget.active && !_semAnimacao;

  void _sincronizar() {
    if (_rodando) {
      if (!_ctl.isAnimating) _ctl.repeat();
    } else {
      _ctl.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _semAnimacao = MediaQuery.disableAnimationsOf(context);
    _sincronizar();
  }

  @override
  void didUpdateWidget(ShinyText old) {
    super.didUpdateWidget(old);
    if (widget.speed != old.speed) {
      _ctl.duration = widget.speed;
      if (_ctl.isAnimating) _ctl.repeat();
    }
    _sincronizar();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texto = Text(
      widget.text,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
    if (!_rodando) return texto;

    final base = DefaultTextStyle.of(context).style.merge(widget.style).color ?? AppColors.text;
    final brilho = widget.shineColor ?? Colors.white;
    return AnimatedBuilder(
      animation: _ctl,
      child: texto,
      builder: (context, filho) {
        // 0 → 1: a faixa entra pela esquerda e sai pela direita.
        final t = Curves.easeInOut.transform(_ctl.value);
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            final faixa = (bounds.width * 0.35).clamp(24.0, 160.0);
            final x = bounds.left - faixa + (bounds.width + faixa * 2) * t;
            // Gradiente inclinado: a faixa fica diagonal; fora dela vale a cor-base.
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [base, brilho, base],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(Rect.fromPoints(
              Offset(x, bounds.top),
              Offset(x + faixa, bounds.top + bounds.height * 0.6),
            ));
          },
          child: filho,
        );
      },
    );
  }
}
