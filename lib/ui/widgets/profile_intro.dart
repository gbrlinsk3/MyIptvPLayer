import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/theme.dart';

/// Animação de abertura depois de escolher o perfil (a "marca" do programa):
/// 4 cubos lado a lado (3 viram o logo; o 4º some ao formar), um deslize
/// rápido junta os cubos no logo e o programa abre. Dura [duration], não pode
/// ser pulada e cobre a tela enquanto o perfil carrega por baixo.
class ProfileIntro extends StatefulWidget {
  const ProfileIntro({
    super.key,
    required this.onDone,
    this.duration = const Duration(milliseconds: 2500),
  });

  final VoidCallback onDone;
  final Duration duration;

  @override
  State<ProfileIntro> createState() => _ProfileIntroState();
}

class _ProfileIntroState extends State<ProfileIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) widget.onDone();
        })
        ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(AppColors.accent);
    final top =
        hsl.withLightness((hsl.lightness + 0.14).clamp(0.0, 0.9)).toColor();
    final right =
        hsl.withLightness((hsl.lightness - 0.16).clamp(0.1, 1.0)).toColor();
    // Bloqueia cliques no que está por baixo durante a animação.
    return AbsorbPointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          // Some no fim (últimos 8 %), revelando o programa.
          final fade = 1 - Curves.easeIn.transform(((t - 0.92) / 0.08).clamp(0.0, 1.0));
          final nameIn = Curves.easeOut.transform(((t - 0.76) / 0.14).clamp(0.0, 1.0));
          return Opacity(
            opacity: fade,
            child: ColoredBox(
              color: AppColors.bg,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: IntroPainter(
                        t: t,
                        top: top,
                        left: AppColors.accent,
                        right: right,
                      ),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.42),
                    child: Opacity(
                      opacity: nameIn,
                      child: Transform.translate(
                        offset: Offset(0, 10 * (1 - nameIn)),
                        child: Text(
                          AppInfo.name.toUpperCase(),
                          style: AppFonts.title(34, spacing: 6),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Desenha os cubos para o instante [t] (0..1) da animação.
class IntroPainter extends CustomPainter {
  const IntroPainter({
    required this.t,
    required this.top,
    required this.left,
    required this.right,
  });

  final double t;
  final Color top;
  final Color left;
  final Color right;

  static const _w = 0.8660254;
  static const _h = 0.5;

  // Cubos do logo na grade isométrica (x, y, z), na ordem da fileira
  // (esquerda → direita). O 4º não faz parte do logo.
  static const _logo = [
    [0, 1, 0],
    [0, 0, 1],
    [1, 0, 0],
  ];

  static Offset _proj(num x, num y, num z) =>
      Offset((x - y) * _w, (x + y) * _h - z);

  /// Centro do cubo na grade (em unidades) já projetado.
  static Offset _cubeCenter(List<int> c) => _proj(c[0] + .5, c[1] + .5, c[2] + .5);

  /// Centro da caixa que contém os 3 cubos do logo (em unidades).
  static Offset get _logoCenter {
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final c in _logo) {
      for (var dx = 0; dx <= 1; dx++) {
        for (var dy = 0; dy <= 1; dy++) {
          for (var dz = 0; dz <= 1; dz++) {
            final p = _proj(c[0] + dx, c[1] + dy, c[2] + dz);
            minX = math.min(minX, p.dx);
            maxX = math.max(maxX, p.dx);
            minY = math.min(minY, p.dy);
            maxY = math.max(maxY, p.dy);
          }
        }
      }
    }
    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final u = (size.shortestSide * 0.11).clamp(36.0, 90.0);
    final mid = Offset(size.width / 2, size.height / 2 - u * 0.5);
    final logoOrigin = mid - _logoCenter * u;
    final spacing = u * 2.3;

    // Posição (centro) de cada cubo: na fileira e no logo.
    Offset rowPos(int i) => Offset(mid.dx + (i - 1.5) * spacing, mid.dy);
    Offset logoPos(int i) => i < 3
        ? logoOrigin + _cubeCenter(_logo[i]) * u
        : mid; // o 4º vai para o centro do logo e some

    // Desenha de trás para a frente: o 4º (que some) fica atrás.
    for (final i in const [3, 2, 1, 0]) {
      // Entrada: cada cubo "salta" com atraso.
      final pop = Curves.easeOutBack.transform(_seg(t, 0.04 + 0.05 * i, 0.26 + 0.05 * i));
      if (pop <= 0) continue;
      // Deslize rápido: curva exponencial, com pequeno atraso por cubo.
      double dash(double tt) => Curves.easeInOutExpo
          .transform(_seg(tt, 0.50 + 0.015 * i, 0.72 + 0.015 * i));
      final a = rowPos(i), b = logoPos(i);

      Offset at(double tt) => Offset.lerp(a, b, dash(tt))!;
      // Quanto o 4º encolhe ao chegar.
      double shrink(double tt) =>
          i == 3 ? 1 - Curves.easeIn.transform(_seg(dash(tt), 0.55, 1.0)) : 1;

      // Rastro do deslize (cópias mais fracas para trás no tempo).
      if (dash(t) > 0 && dash(t) < 1) {
        for (var k = 3; k >= 1; k--) {
          final tt = t - 0.012 * k;
          _cube(canvas, at(tt), u * pop * shrink(tt), 0.20 / k);
        }
      }
      _cube(canvas, at(t), u * pop * shrink(t), 1);
    }

    // Brilho curto quando o logo se forma.
    final glow = math.sin(math.pi * _seg(t, 0.70, 0.86));
    if (glow > 0) {
      canvas.drawCircle(
        mid,
        u * 2.6,
        Paint()
          ..shader = RadialGradient(colors: [
            left.withValues(alpha: 0.30 * glow),
            left.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: mid, radius: u * 2.6)),
      );
    }
  }

  /// Cubo isométrico de aresta [s] com centro em [c].
  void _cube(Canvas canvas, Offset c, double s, double alpha) {
    if (s <= 0.5 || alpha <= 0) return;
    // Projeção do canto de origem em relação ao centro do cubo.
    final o = c - _proj(.5, .5, .5) * s;
    Offset pt(num x, num y, num z) => o + _proj(x, y, z) * s;
    Path poly(List<Offset> p) {
      final path = Path()..moveTo(p[0].dx, p[0].dy);
      for (final q in p.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      return path..close();
    }

    canvas.drawPath(
      poly([pt(1, 0, 0), pt(1, 1, 0), pt(1, 1, 1), pt(1, 0, 1)]),
      Paint()..color = right.withValues(alpha: alpha),
    );
    canvas.drawPath(
      poly([pt(0, 1, 0), pt(1, 1, 0), pt(1, 1, 1), pt(0, 1, 1)]),
      Paint()..color = left.withValues(alpha: alpha),
    );
    canvas.drawPath(
      poly([pt(0, 0, 1), pt(1, 0, 1), pt(1, 1, 1), pt(0, 1, 1)]),
      Paint()..color = top.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(covariant IntroPainter old) =>
      old.t != t || old.top != top || old.left != left || old.right != right;
}
