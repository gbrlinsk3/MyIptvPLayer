import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Rastreia o ponteiro dentro de uma área para que vários [SpotlightCard]
/// acendam juntos: o cartão sob o mouse brilha por inteiro e os vizinhos
/// acendem de leve na borda mais próxima. Não bloqueia cliques nem rolagem.
///
/// Inspirado no SpotlightCard do React Bits.
class SpotlightGroup extends StatefulWidget {
  const SpotlightGroup({super.key, required this.child});

  final Widget child;

  @override
  State<SpotlightGroup> createState() => _SpotlightGroupState();
}

class _SpotlightGroupState extends State<SpotlightGroup> {
  // Posição global do ponteiro; nula quando ele saiu da área.
  final ValueNotifier<Offset?> _pointer = ValueNotifier(null);

  @override
  void dispose() {
    _pointer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SpotlightScope(
      pointer: _pointer,
      child: MouseRegion(
        opaque: false,
        onHover: (e) => _pointer.value = e.position,
        onExit: (_) => _pointer.value = null,
        child: widget.child,
      ),
    );
  }
}

class _SpotlightScope extends InheritedWidget {
  const _SpotlightScope({required this.pointer, required super.child});

  final ValueNotifier<Offset?> pointer;

  static ValueNotifier<Offset?>? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<_SpotlightScope>()
      ?.pointer;

  @override
  bool updateShouldNotify(_SpotlightScope old) => pointer != old.pointer;
}

/// Cartão com um facho de luz que acompanha o mouse. Pinta por cima do filho
/// (sem receber toques) e só repinta, nunca reconstrói, quando o ponteiro anda.
///
/// Dentro de um [SpotlightGroup] o ponteiro é compartilhado; sem ele o cartão
/// usa o próprio [MouseRegion].
class SpotlightCard extends StatefulWidget {
  const SpotlightCard({
    super.key,
    required this.child,
    required this.borderRadius,
    this.spotlightSize = 150,
    this.proximity = 160,
    this.borderGlow = 0,
    this.color,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// Raio do facho, em pixels.
  final double spotlightSize;

  /// Distância (fora da borda) em que o cartão ainda acende; a intensidade cai
  /// de forma linear até 0 nesse limite.
  final double proximity;

  /// Opacidade (0 a 1) do brilho no contorno; 0 = sem brilho de borda.
  final double borderGlow;

  /// Cor do facho. Padrão: [AppColors.text] com alpha 0,12 no centro.
  final Color? color;

  /// Intensidade (0 a 1) do facho para um cartão ocupando [rect], com o
  /// ponteiro em [pointer] (ambos no mesmo sistema de coordenadas): 1 com o
  /// ponteiro dentro, caindo linearmente até 0 a [proximity] px da borda.
  static double intensityFor({
    required Rect rect,
    required Offset pointer,
    required double proximity,
  }) {
    final dx = math.max(math.max(rect.left - pointer.dx, pointer.dx - rect.right), 0);
    final dy = math.max(math.max(rect.top - pointer.dy, pointer.dy - rect.bottom), 0);
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= 0) return 1;
    if (proximity <= 0) return 0;
    return (1 - dist / proximity).clamp(0.0, 1.0).toDouble();
  }

  @override
  State<SpotlightCard> createState() => _SpotlightCardState();
}

class _SpotlightCardState extends State<SpotlightCard> {
  // Usado só quando não há SpotlightGroup acima.
  final ValueNotifier<Offset?> _own = ValueNotifier(null);

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  /// Ponteiro em coordenadas locais do cartão, ou nulo se não houver.
  Offset? _local(Offset? global) {
    if (global == null) return null;
    final rb = context.findRenderObject();
    if (rb is! RenderBox || !rb.attached || !rb.hasSize) return null;
    return rb.globalToLocal(global);
  }

  @override
  Widget build(BuildContext context) {
    final shared = _SpotlightScope.maybeOf(context);
    final pointer = shared ?? _own;
    Widget card = CustomPaint(
      key: const ValueKey('spotlight-paint'),
      foregroundPainter: _SpotlightPainter(
        pointer: pointer,
        localOf: _local,
        radius: widget.borderRadius,
        spotlightSize: widget.spotlightSize,
        proximity: widget.proximity,
        borderGlow: widget.borderGlow,
        color: widget.color ?? AppColors.text.withValues(alpha: 0.12),
      ),
      child: widget.child,
    );
    if (shared == null) {
      card = MouseRegion(
        opaque: false,
        onHover: (e) => _own.value = e.position,
        onExit: (_) => _own.value = null,
        child: card,
      );
    }
    return card;
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({
    required this.pointer,
    required this.localOf,
    required this.radius,
    required this.spotlightSize,
    required this.proximity,
    required this.borderGlow,
    required this.color,
  }) : super(repaint: pointer);

  final ValueListenable<Offset?> pointer;
  final Offset? Function(Offset? global) localOf;
  final BorderRadius radius;
  final double spotlightSize;
  final double proximity;
  final double borderGlow;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = localOf(pointer.value);
    if (p == null || size.isEmpty || spotlightSize <= 0) return;
    final rect = Offset.zero & size;
    final k = SpotlightCard.intensityFor(
      rect: rect,
      pointer: p,
      proximity: proximity,
    );
    if (k <= 0) return;
    final rrect = radius.toRRect(rect);

    // Queda suave (smoothstep) em vez de linear: o centro é denso e a borda do
    // facho se dissolve sem aro visível.
    Shader shader(Color c) => RadialGradient(
          colors: [
            c,
            c.withValues(alpha: c.a * 0.62),
            c.withValues(alpha: c.a * 0.22),
            c.withValues(alpha: 0),
          ],
          stops: const [0, 0.3, 0.65, 1],
        ).createShader(Rect.fromCircle(center: p, radius: spotlightSize));

    final centro = color.withValues(alpha: color.a * k);
    canvas.drawRRect(rrect, Paint()..shader = shader(centro));

    if (borderGlow > 0) {
      final brilho = color.withValues(alpha: (borderGlow * k).clamp(0.0, 1.0));
      canvas.drawRRect(
        rrect.deflate(0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..shader = shader(brilho),
      );
    }
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.pointer != pointer ||
      old.radius != radius ||
      old.spotlightSize != spotlightSize ||
      old.proximity != proximity ||
      old.borderGlow != borderGlow ||
      old.color != color;
}
