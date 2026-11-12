import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Logo "Cubos": três cubos isométricos (o mesmo desenho do ícone do programa,
/// `extras/app_icon.ico`), pintados com a cor de destaque do perfil: face de
/// cima mais clara, lateral esquerda na cor de destaque e direita mais escura.
class CubosLogo extends StatelessWidget {
  const CubosLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(AppColors.accent);
    return CustomPaint(
      size: Size.square(size),
      painter: _CubosPainter(
        top: hsl.withLightness((hsl.lightness + 0.14).clamp(0.0, 0.9)).toColor(),
        left: AppColors.accent,
        right: hsl.withLightness((hsl.lightness - 0.16).clamp(0.1, 1.0)).toColor(),
      ),
    );
  }
}

class _CubosPainter extends CustomPainter {
  const _CubosPainter({required this.top, required this.left, required this.right});

  final Color top;
  final Color left;
  final Color right;

  static const _w = 0.8660254; // cos(30°)
  static const _h = 0.5; // sin(30°)

  // Cubos na grade isométrica (x, y, z): um em cima, dois embaixo.
  static const _cubes = [
    [0, 0, 1],
    [1, 0, 0],
    [0, 1, 0],
  ];

  static Offset _proj(num x, num y, num z) =>
      Offset((x - y) * _w, (x + y) * _h - z);

  @override
  void paint(Canvas canvas, Size size) {
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final c in _cubes) {
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
    final ext = math.max(maxX - minX, maxY - minY);
    final sc = size.width * 0.92 / ext;
    final ox = size.width / 2 - (minX + maxX) / 2 * sc;
    final oy = size.height / 2 - (minY + maxY) / 2 * sc;

    Offset pt(num x, num y, num z) {
      final p = _proj(x, y, z);
      return Offset(ox + p.dx * sc, oy + p.dy * sc);
    }

    Path poly(List<Offset> pts) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      return path..close();
    }

    final sorted = [..._cubes]..sort((a, b) => (a[0] + a[1] + a[2]).compareTo(b[0] + b[1] + b[2]));
    for (final c in sorted) {
      final x = c[0], y = c[1], z = c[2];
      canvas.drawPath(
        poly([pt(x + 1, y, z), pt(x + 1, y + 1, z), pt(x + 1, y + 1, z + 1), pt(x + 1, y, z + 1)]),
        Paint()..color = right,
      );
      canvas.drawPath(
        poly([pt(x, y + 1, z), pt(x + 1, y + 1, z), pt(x + 1, y + 1, z + 1), pt(x, y + 1, z + 1)]),
        Paint()..color = left,
      );
      canvas.drawPath(
        poly([pt(x, y, z + 1), pt(x + 1, y, z + 1), pt(x + 1, y + 1, z + 1), pt(x, y + 1, z + 1)]),
        Paint()..color = top,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CubosPainter old) =>
      old.top != top || old.left != left || old.right != right;
}
