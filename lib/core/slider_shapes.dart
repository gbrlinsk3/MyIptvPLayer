import 'package:flutter/material.dart';

import 'theme.dart';

/// Botão dos controles deslizantes: bolinha no formato arredondado, quadrado no
/// formato quadrado.
class AppSliderThumbShape extends SliderComponentShape {
  const AppSliderThumbShape({this.radius = 10});

  /// Metade do lado (ou o raio da bolinha).
  final double radius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final color = ColorTween(
      begin: sliderTheme.disabledThumbColor,
      end: sliderTheme.thumbColor,
    ).evaluate(enableAnimation)!;
    final paint = Paint()..color = color;
    if (AppShape.rounded) {
      context.canvas.drawCircle(center, radius, paint);
    } else {
      context.canvas.drawRect(
        Rect.fromCircle(center: center, radius: radius),
        paint,
      );
    }
  }
}

/// Realce em volta do botão, no mesmo formato dele.
class AppSliderOverlayShape extends SliderComponentShape {
  const AppSliderOverlayShape({this.radius = 20});

  final double radius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final size = radius * activationAnimation.value;
    if (size <= 0) return;
    final paint = Paint()..color = sliderTheme.overlayColor ?? Colors.transparent;
    if (AppShape.rounded) {
      context.canvas.drawCircle(center, size, paint);
    } else {
      context.canvas.drawRect(
        Rect.fromCircle(center: center, radius: size),
        paint,
      );
    }
  }
}
