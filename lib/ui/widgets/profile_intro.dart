import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/theme.dart';

/// Animação de abertura depois de escolher o perfil, estilo "cinema": tela
/// escura, o logo (3 cubos) surge, depois a luz do projetor pisca e acende,
/// um brilho atravessa o logo e o nome aparece. Ao fim da cena chama [onDone];
/// quem usa troca a cena pelo Início com a transição "derreter" do Morph Slider
/// (`MorphReveal`). [boundaryKey] marca a cena para ser capturada como imagem.
/// Não pode ser pulada e cobre a tela enquanto o perfil carrega por baixo.
class ProfileIntro extends StatefulWidget {
  const ProfileIntro({
    super.key,
    required this.onDone,
    this.boundaryKey,
    this.duration = defaultDuration,
    this.startSound,
  });

  /// Espera máxima pelo som antes de a cena começar sem ele.
  static const soundTimeout = Duration(milliseconds: 800);

  /// Liga o som e termina quando ele começa a tocar; a cena parte junto.
  /// Sem ele a cena começa na hora.
  final Future<void> Function()? startSound;

  /// Fração da linha do tempo da cena (pensada para 3 s) em que ela termina:
  /// o resto seria a saída, que agora é a transição "derreter".
  static const sceneEnd = 0.78;

  /// Cena completa (0,78 de 3 s).
  static const defaultDuration = Duration(milliseconds: 2340);

  final VoidCallback onDone;
  final GlobalKey? boundaryKey;
  final Duration duration;

  @override
  State<ProfileIntro> createState() => _ProfileIntroState();
}

/// Fundo da sala escura (o mesmo nos dois temas).
const _cinemaBg = Color(0xFF0B0A09);

class _ProfileIntroState extends State<ProfileIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) widget.onDone();
        });

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final sound = widget.startSound;
    if (sound != null) {
      try {
        await sound().timeout(ProfileIntro.soundTimeout);
      } catch (e) {
        debugPrint('Abertura: sem som ($e)');
      }
    }
    if (mounted) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(AppColors.accent);
    final top = hsl
        .withLightness((hsl.lightness + 0.14).clamp(0.0, 0.9))
        .toColor();
    final right = hsl
        .withLightness((hsl.lightness - 0.16).clamp(0.1, 1.0))
        .toColor();
    // Bloqueia cliques no que está por baixo durante a animação.
    return AbsorbPointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value * ProfileIntro.sceneEnd;
          final nameIn = Curves.easeOut.transform(
            ((t - 0.52) / 0.16).clamp(0.0, 1.0),
          );
          return RepaintBoundary(
            key: widget.boundaryKey,
            child: ColoredBox(
                color: _cinemaBg,
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
                      alignment: const Alignment(0, 0.62),
                      child: Opacity(
                        opacity: nameIn,
                        child: Transform.translate(
                          offset: Offset(0, 10 * (1 - nameIn)),
                          // Material transparente: sem ele o Text fora de um
                          // Scaffold sai com o sublinhado amarelo de depuração.
                          child: Material(
                            type: MaterialType.transparency,
                            child: Text(
                              AppInfo.fullName,
                              style: AppFonts.title(
                                32,
                                spacing: 3,
                              ).copyWith(color: const Color(0xFFF1EFE8)),
                            ),
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
  static Offset _cubeCenter(List<int> c) =>
      _proj(c[0] + .5, c[1] + .5, c[2] + .5);

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
    final mid = Offset(size.width / 2, size.height / 2 + u * 0.4);
    final logoOrigin = mid - _logoCenter * u;
    Offset logoPos(int i) => logoOrigin + _cubeCenter(_logo[i]) * u;

    // O logo surge primeiro; a luz só vem depois e pisca antes de firmar.
    final lit = Curves.easeOut.transform(_seg(t, 0.05, 0.28));
    final ramp = Curves.easeOut.transform(_seg(t, 0.30, 0.50));
    final flicker = t < 0.44 && t >= 0.30
        ? (((t - 0.30) / 0.035).floor().isEven ? 0.85 : 0.0)
        : 1.0;
    final beamIn = t < 0.30 ? 0.0 : (t < 0.44 ? 1.0 : ramp) * flicker;

    // Feixe do projetor: desce do alto e se abre até o logo.
    if (beamIn > 0) {
      final bottom = mid.dy + u * 2.2;
      final path = Path()
        ..moveTo(mid.dx - u * 0.25, -4)
        ..lineTo(mid.dx + u * 0.25, -4)
        ..lineTo(mid.dx + u * 3.2, bottom)
        ..lineTo(mid.dx - u * 3.2, bottom)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(mid.dx, 0),
            Offset(mid.dx, bottom),
            [
              Colors.white.withValues(alpha: 0.0),
              Colors.white.withValues(alpha: 0.10 * beamIn),
              Colors.white.withValues(alpha: 0.0),
            ],
            const [0.0, 0.5, 0.95],
          ),
      );
    }

    // Halo atrás do logo (acompanha a luz).
    if (beamIn > 0) {
      final r = u * 3.2;
      canvas.drawCircle(
        mid,
        r,
        Paint()
          ..shader = ui.Gradient.radial(mid, r, [
            left.withValues(alpha: 0.28 * beamIn),
            left.withValues(alpha: 0),
          ]),
      );
    }

    // Logo (3 cubos) que acende, com um brilho diagonal que o atravessa.
    if (lit > 0) {
      final k = 0.94 + 0.06 * lit;
      canvas.saveLayer(null, Paint());
      for (final i in const [2, 1, 0]) {
        _cube(canvas, mid + (logoPos(i) - mid) * k, u * k, lit);
      }
      final sweep = Curves.easeInOut.transform(_seg(t, 0.52, 0.76));
      if (sweep > 0 && sweep < 1) {
        final cx = mid.dx + (sweep * 2 - 1) * u * 3.2;
        canvas.save();
        canvas.translate(cx, mid.dy);
        canvas.skew(-0.45, 0);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: u * 1.4, height: u * 6),
          Paint()
            ..blendMode = BlendMode.srcATop
            ..shader = ui.Gradient.linear(
              Offset(-u * 0.7, 0),
              Offset(u * 0.7, 0),
              [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: 0.7),
                Colors.white.withValues(alpha: 0),
              ],
              const [0.0, 0.5, 1.0],
            ),
        );
        canvas.restore();
      }
      canvas.restore();
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
