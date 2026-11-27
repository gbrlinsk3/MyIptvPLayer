import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Formato das faíscas do [ClickSpark].
enum SparkShape {
  /// Traços curtos que se afastam do ponto.
  dashes,

  /// Pontos com um rastro que some atrás.
  comets,

  /// Bolinhas que diminuem.
  dots,

  /// Estrelinhas de 4 pontas que piscam.
  stars,
}

/// Explosão curta de faíscas num ponto da tela, inspirada no ClickSpark do
/// React Bits. Desenha num `OverlayEntry` (ignora o ponteiro) e se remove ao
/// terminar. Com `MediaQuery.disableAnimations` ligado não desenha nada.
///
/// Não é um widget que envolve o app: chame [burst] (ou [fromContext]) na ação.
class ClickSpark {
  ClickSpark._();

  /// Quantas explosões estão montadas na tela agora (para testes).
  @visibleForTesting
  static int get ativas => _ativas;
  static int _ativas = 0;

  /// Dispara uma explosão em [globalPosition] (coordenadas globais da janela).
  static void burst(
    BuildContext context, {
    required Offset globalPosition,
    SparkShape shape = SparkShape.dashes,
    Color? color,
    int count = 8,
    double radius = 22,
    double size = 10,
    Duration duration = const Duration(milliseconds: 420),
  }) {
    final semAnimacao = context.getInheritedWidgetOfExactType<MediaQuery>()?.data.disableAnimations ?? false;
    if (semAnimacao || count <= 0 || duration <= Duration.zero) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final overlayBox = overlay.context.findRenderObject();
    final origem = overlayBox is RenderBox && overlayBox.hasSize
        ? overlayBox.globalToLocal(globalPosition)
        : globalPosition;

    late final OverlayEntry entry;
    var removido = false;
    void remover() {
      if (removido) return;
      removido = true;
      entry.remove();
      entry.dispose();
    }

    entry = OverlayEntry(
      builder: (_) => _SparkLayer(
        origem: origem,
        shape: shape,
        color: color ?? AppColors.accent,
        count: count,
        radius: radius,
        size: size,
        duration: duration,
        onDone: () {
          // Fora do quadro atual, para não mexer no Overlay durante o tick.
          WidgetsBinding.instance.addPostFrameCallback((_) => remover());
        },
      ),
    );
    overlay.insert(entry);
  }

  static Offset? _ultimoToque;
  static Stopwatch? _desdeToque;
  static bool _ouvindo = false;

  /// Passa a guardar onde foi o último toque/clique. Chame uma vez na partida
  /// do app; sem isso [noClique] não desenha nada.
  static void ouvirCliques() {
    if (_ouvindo) return;
    _ouvindo = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute((evento) {
      if (evento is PointerDownEvent) {
        _ultimoToque = evento.position;
        _desdeToque = Stopwatch()..start();
      }
    });
  }

  /// Faíscas no ponto do último clique, para ações de botões cujo [BuildContext]
  /// não é o do botão. Só vale para uma ação disparada por clique: se o último
  /// toque foi há mais de um segundo (ação pelo teclado), não desenha nada.
  static void noClique(
    BuildContext context, {
    SparkShape shape = SparkShape.dashes,
    Color? color,
    int count = 8,
    double radius = 24,
    double size = 10,
  }) {
    final ponto = _ultimoToque;
    final t = _desdeToque;
    if (ponto == null || t == null || t.elapsedMilliseconds > 1000) return;
    burst(
      context,
      globalPosition: ponto,
      shape: shape,
      color: color,
      count: count,
      radius: radius,
      size: size,
    );
  }

  /// Igual a [burst], no centro do widget de [ctx].
  static void fromContext(
    BuildContext ctx, {
    SparkShape shape = SparkShape.dashes,
    Color? color,
    int count = 8,
    double radius = 22,
    double size = 10,
    Duration duration = const Duration(milliseconds: 420),
  }) {
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    burst(
      ctx,
      globalPosition: box.localToGlobal(box.size.center(Offset.zero)),
      shape: shape,
      color: color,
      count: count,
      radius: radius,
      size: size,
      duration: duration,
    );
  }
}

class _SparkLayer extends StatefulWidget {
  const _SparkLayer({
    required this.origem,
    required this.shape,
    required this.color,
    required this.count,
    required this.radius,
    required this.size,
    required this.duration,
    required this.onDone,
  });

  final Offset origem;
  final SparkShape shape;
  final Color color;
  final int count;
  final double radius;
  final double size;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_SparkLayer> createState() => _SparkLayerState();
}

class _Faisca {
  _Faisca({required this.angulo, required this.alcance, required this.escala, required this.giro});
  final double angulo;
  final double alcance;
  final double escala;
  final double giro;
}

class _SparkLayerState extends State<_SparkLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this, duration: widget.duration);
  late final List<_Faisca> _faiscas;

  @override
  void initState() {
    super.initState();
    ClickSpark._ativas++;
    final rnd = math.Random();
    const aleatoriedade = 0.2;
    final passo = math.pi * 2 / widget.count;
    final fase = rnd.nextDouble() * passo;
    _faiscas = List.generate(widget.count, (i) {
      return _Faisca(
        angulo: fase + passo * i + (rnd.nextDouble() - 0.5) * aleatoriedade * passo,
        alcance: 1 + (rnd.nextDouble() - 0.5) * 0.7 * aleatoriedade,
        escala: 1 + (rnd.nextDouble() - 0.5) * 0.8 * aleatoriedade,
        giro: rnd.nextDouble() - 0.5,
      );
    });
    _ctl.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    _ctl.forward();
  }

  @override
  void dispose() {
    ClickSpark._ativas--;
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _SparkPainter(
              animacao: _ctl,
              origem: widget.origem,
              shape: widget.shape,
              color: widget.color,
              radius: widget.radius,
              size: widget.size,
              faiscas: _faiscas,
            ),
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.animacao,
    required this.origem,
    required this.shape,
    required this.color,
    required this.radius,
    required this.size,
    required this.faiscas,
  }) : super(repaint: animacao);

  final Animation<double> animacao;
  final Offset origem;
  final SparkShape shape;
  final Color color;
  final double radius;
  final double size;
  final List<_Faisca> faiscas;

  static double _suave(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  Offset _pos(_Faisca f, double distancia) =>
      origem + Offset(math.cos(f.angulo), math.sin(f.angulo)) * distancia;

  @override
  void paint(Canvas canvas, Size area) {
    final p = animacao.value.clamp(0.0, 1.0);
    final e = Curves.easeOutCubic.transform(p);
    final fade = 1 - _suave(shape == SparkShape.dashes ? 0.55 : 0.7, 1, p);
    if (fade <= 0) return;
    final espessura = math.max(1.5, size * 0.2);
    final tinta = Paint()
      ..color = color.withValues(alpha: color.a * fade)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (final f in faiscas) {
      final distancia = radius * f.alcance * e;
      switch (shape) {
        case SparkShape.dashes:
          final comprimento = size * f.escala * math.pow(1 - p, 1.6);
          final a = _pos(f, distancia);
          final b = _pos(f, distancia + math.max(0.01, comprimento));
          canvas.drawLine(
            a,
            b,
            tinta
              ..style = PaintingStyle.stroke
              ..strokeWidth = espessura * f.escala
              ..strokeCap = StrokeCap.round,
          );
        case SparkShape.comets:
          final cabeca = _pos(f, distancia);
          final recuo = Curves.easeOutCubic.transform(math.max(0.0, p - 0.18) / 0.82);
          final cauda = _pos(f, radius * f.alcance * recuo);
          final largura = espessura * f.escala;
          final dx = cabeca.dx - cauda.dx;
          final dy = cabeca.dy - cauda.dy;
          final len = math.sqrt(dx * dx + dy * dy);
          if (len > 0.01) {
            final nx = -dy / len * largura * 0.5;
            final ny = dx / len * largura * 0.5;
            final rastro = Path()
              ..moveTo(cauda.dx, cauda.dy)
              ..lineTo(cabeca.dx + nx, cabeca.dy + ny)
              ..lineTo(cabeca.dx - nx, cabeca.dy - ny)
              ..close();
            canvas.drawPath(
              rastro,
              Paint()
                ..isAntiAlias = true
                ..shader = LinearGradient(
                  colors: [color.withValues(alpha: 0), color.withValues(alpha: color.a * fade)],
                ).createShader(Rect.fromPoints(cauda, cabeca)),
            );
          }
          _bolinha(canvas, cabeca, largura * 0.5, tinta);
        case SparkShape.dots:
          final r = espessura * f.escala * 1.25 * (1 - 0.5 * e);
          _bolinha(canvas, _pos(f, distancia), r, tinta);
        case SparkShape.stars:
          final brilho = math.pow(math.sin(math.pi * (p * 1.1).clamp(0.0, 1.0)), 0.7).toDouble();
          final r = size * 0.6 * f.escala * brilho;
          if (r <= 0.05) continue;
          canvas.drawPath(
            _estrela(_pos(f, distancia), r, f.angulo + f.giro * p * math.pi * 0.5),
            tinta..style = PaintingStyle.fill,
          );
      }
    }
  }

  /// Ponta redonda ou quadrada, conforme o formato da interface.
  static void _bolinha(Canvas canvas, Offset c, double r, Paint tinta) {
    tinta.style = PaintingStyle.fill;
    if (AppShape.rounded) {
      canvas.drawCircle(c, r, tinta);
    } else {
      canvas.drawRect(Rect.fromCircle(center: c, radius: r), tinta);
    }
  }

  /// Estrela de 4 pontas com os lados côncavos.
  static Path _estrela(Offset c, double raio, double rotacao) {
    final aperto = raio * 0.16;
    final path = Path()..moveTo(c.dx + math.cos(rotacao) * raio, c.dy + math.sin(rotacao) * raio);
    for (var i = 1; i <= 4; i++) {
      final a = rotacao + i * math.pi / 2;
      final meio = a - math.pi / 4;
      path.quadraticBezierTo(
        c.dx + math.cos(meio) * aperto,
        c.dy + math.sin(meio) * aperto,
        c.dx + math.cos(a) * raio,
        c.dy + math.sin(a) * raio,
      );
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.origem != origem ||
      old.shape != shape ||
      old.color != color ||
      old.radius != radius ||
      old.size != size ||
      old.faiscas != faiscas;
}
