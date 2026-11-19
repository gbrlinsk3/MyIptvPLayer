import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Brilho que passa sobre um esqueleto de carregamento. Envolve um conjunto de
/// [SkeletonBox]. O controlador para quando o TickerMode está desativado (tela
/// oculta) e é descartado junto com o widget.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (r) => LinearGradient(
          colors: const [Color(0x00FFFFFF), Color(0x12FFFFFF), Color(0x00FFFFFF)],
          stops: const [0.3, 0.5, 0.7],
          transform: _FaixaDeslocada(-1 + 2 * _c.value),
        ).createShader(r),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Desloca o gradiente horizontalmente pela fração [p] da largura do alvo.
class _FaixaDeslocada extends GradientTransform {
  const _FaixaDeslocada(this.p);

  final double p;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * p, 0, 0);
}

/// Bloco cinza de um esqueleto. Sem [width] ocupa a largura disponível; sem
/// [height] segue o tamanho do pai. Use dentro de um [Shimmer].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = 6,
  });

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.hover,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
