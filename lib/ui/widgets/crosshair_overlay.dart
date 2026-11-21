import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../core/theme.dart';

/// Estado observável do [CrosshairOverlay].
@immutable
class CrosshairState {
  const CrosshairState({this.position, this.lockedRect});

  /// Posição do ponteiro em coordenadas globais da janela; `null` = fora.
  final Offset? position;

  /// Retângulo global do alvo clicável em que a mira está travada, se houver.
  final Rect? lockedRect;

  @override
  bool operator ==(Object other) =>
      other is CrosshairState && other.position == position && other.lockedRect == lockedRect;

  @override
  int get hashCode => Object.hash(position, lockedRect);

  @override
  String toString() => 'CrosshairState($position, $lockedRect)';
}

/// Canal opcional para observar o estado de um [CrosshairOverlay] (testes,
/// diagnóstico). O overlay é quem escreve nele.
class CrosshairController extends ValueNotifier<CrosshairState> {
  CrosshairController() : super(const CrosshairState());
}

/// Cursor-mira para o app todo, inspirado no Crosshair do React Bits: duas
/// linhas de 1 px cruzando a janela pelo ponteiro, com o rótulo `x, y`. Sobre um
/// alvo clicável (uma região de mouse com cursor de clique) a mira "trava":
/// aparece um quadro com 4 cantoneiras em volta dele, com o rótulo `L × A`, e as
/// linhas passam a cruzar o centro do alvo.
///
/// Não consome eventos: o ponteiro é observado por uma rota global do
/// `GestureBinding` e a pintura fica sob `IgnorePointer`, então os cliques
/// chegam normalmente aos widgets. A procura do alvo faz no máximo um hit test
/// por quadro. Com [enabled] falso não há rota nem pintura, e o [child]
/// permanece na mesma posição da árvore (não perde estado ao ligar/desligar).
class CrosshairOverlay extends StatefulWidget {
  const CrosshairOverlay({
    super.key,
    required this.enabled,
    required this.child,
    this.controller,
  });

  final bool enabled;
  final Widget child;

  /// Recebe a posição e o alvo travado a cada mudança.
  final CrosshairController? controller;

  /// Chave do `CustomPaint` da mira (para testes).
  @visibleForTesting
  static const paintKey = ValueKey<String>('crosshair-paint');

  @override
  State<CrosshairOverlay> createState() => _CrosshairOverlayState();
}

class _CrosshairOverlayState extends State<CrosshairOverlay> with TickerProviderStateMixin {
  static const _animacao = Duration(milliseconds: 120);

  late final CrosshairController _proprio = CrosshairController();
  CrosshairController get _estado => widget.controller ?? _proprio;

  /// Posição global do ponteiro (null = fora) — dispara o repaint.
  final ValueNotifier<Offset?> _ponteiro = ValueNotifier<Offset?>(null);

  /// 0 = sem trava, 1 = travada (opacidade do quadro e do deslocamento das linhas).
  late final AnimationController _trava = AnimationController(vsync: this, duration: _animacao);

  /// 0 → 1: transição do quadro entre [_de] e [_para].
  late final AnimationController _mov = AnimationController(vsync: this, duration: _animacao);

  Rect? _de;
  Rect? _para;
  Offset _origem = Offset.zero;
  bool _rotaAtiva = false;
  bool _avaliacaoAgendada = false;
  bool _semAnimacao = false;

  bool get _ligada => widget.enabled;

  // ---- ciclo de vida -------------------------------------------------------

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _semAnimacao = MediaQuery.disableAnimationsOf(context);
    _sincronizar();
  }

  @override
  void didUpdateWidget(CrosshairOverlay old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _proprio).value = const CrosshairState();
      _publicar();
    }
    _sincronizar();
  }

  void _sincronizar() {
    if (_ligada == _rotaAtiva) return;
    _rotaAtiva = _ligada;
    if (_ligada) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_aoEvento);
    } else {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_aoEvento);
      _limpar();
    }
  }

  void _limpar() {
    _ponteiro.value = null;
    _de = _para = null;
    _trava.value = 0;
    _mov.value = 0;
    _estado.value = const CrosshairState();
  }

  @override
  void dispose() {
    if (_rotaAtiva) GestureBinding.instance.pointerRouter.removeGlobalRoute(_aoEvento);
    _ponteiro.dispose();
    _trava.dispose();
    _mov.dispose();
    _proprio.dispose();
    super.dispose();
  }

  // ---- ponteiro ------------------------------------------------------------

  void _aoEvento(PointerEvent e) {
    if (!mounted || !_ligada) return;
    if (e.kind != PointerDeviceKind.mouse) return;
    if (e is PointerRemovedEvent) {
      _sair();
      return;
    }
    if (e is! PointerHoverEvent && e is! PointerMoveEvent && e is! PointerDownEvent && e is! PointerUpEvent) {
      return;
    }
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) _origem = box.localToGlobal(Offset.zero);
    _ponteiro.value = e.position;
    _publicar();
    _agendarAvaliacao();
  }

  void _sair() {
    _ponteiro.value = null;
    _definirAlvo(null);
    _publicar();
  }

  void _publicar() {
    _estado.value = CrosshairState(position: _ponteiro.value, lockedRect: _para);
  }

  void _agendarAvaliacao() {
    SchedulerBinding.instance.ensureVisualUpdate();
    _agendarNoProximoQuadro();
  }

  /// Avalia depois do próximo quadro, sem pedir um quadro novo. Com a mira
  /// travada isso acompanha um alvo que cresce ou se move (cartão que expande
  /// no hover) enquanto há animação; parado, não custa nada.
  void _agendarNoProximoQuadro() {
    if (_avaliacaoAgendada) return;
    _avaliacaoAgendada = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _avaliar());
  }

  // ---- procura do alvo (no máximo um hit test por quadro) ------------------

  void _avaliar() {
    _avaliacaoAgendada = false;
    if (!mounted || !_ligada) return;
    final pos = _ponteiro.value;
    if (pos == null) return;
    final view = View.maybeOf(context);
    if (view == null) return;

    final resultado = HitTestResult();
    WidgetsBinding.instance.hitTestInView(resultado, pos, view.viewId);
    Rect? alvo;
    RenderMouseRegion? objeto;
    for (final entrada in resultado.path) {
      final t = entrada.target;
      if (t is RenderMouseRegion && t.attached && t.hasSize && _ehClique(t.cursor)) {
        // Com a ampliação da interface (UiScale) o tamanho local não é o da
        // janela: transforma o retângulo inteiro.
        alvo = MatrixUtils.transformRect(t.getTransformTo(null), Offset.zero & t.size);
        objeto = t;
        break;
      }
    }
    if (alvo != null && objeto == _alvoObjeto && _para != null && alvo != _para) {
      // Mesmo alvo, só mudou de lugar ou tamanho: o quadro acompanha direto.
      _de = _para = _ultimo = alvo;
      _mov.value = 1;
    } else {
      _definirAlvo(alvo);
    }
    _alvoObjeto = objeto;
    _publicar();
    if (_para != null) _agendarNoProximoQuadro();
  }

  /// Região de mouse em que a mira está travada (para reconhecer o mesmo alvo).
  RenderMouseRegion? _alvoObjeto;

  static bool _ehClique(MouseCursor cursor) {
    if (cursor == SystemMouseCursors.click) return true;
    if (cursor is WidgetStateMouseCursor) {
      return cursor.resolve(const <WidgetState>{}) == SystemMouseCursors.click ||
          cursor.resolve(const <WidgetState>{WidgetState.hovered}) == SystemMouseCursors.click;
    }
    return false;
  }

  void _definirAlvo(Rect? alvo) {
    if (alvo == _para) return;
    final anterior = _para;
    if (alvo == null) {
      // Mantém _para/_de para o quadro sumir no lugar onde estava.
      _para = null;
      _ultimo = anterior ?? _ultimo;
      if (_semAnimacao) {
        _trava.value = 0;
      } else {
        _trava.reverse();
      }
      return;
    }
    if (anterior == null) {
      final p = _ponteiro.value;
      _de = p == null ? alvo : Rect.fromCenter(center: p, width: 20, height: 20);
    } else {
      _de = _rectAtual() ?? anterior;
    }
    _para = alvo;
    _ultimo = alvo;
    if (_semAnimacao) {
      _mov.value = 1;
      _trava.value = 1;
    } else {
      _mov.forward(from: 0);
      _trava.forward();
    }
  }

  Rect? _ultimo;

  /// Retângulo do quadro neste instante (interpolando entre [_de] e [_para]).
  Rect? _rectAtual() {
    final destino = _para ?? _ultimo;
    if (destino == null) return null;
    final origem = _de ?? destino;
    if (_para == null) return destino;
    return Rect.lerp(origem, destino, Curves.easeOutCubic.transform(_mov.value));
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topLeft,
      fit: StackFit.passthrough,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (_) {
            // O alvo sob o ponteiro parado muda quando a página rola.
            if (_ligada && _ponteiro.value != null) _agendarAvaliacao();
            return false;
          },
          child: widget.child,
        ),
        if (_ligada)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: CrosshairOverlay.paintKey,
                  painter: _MiraPainter(
                    // _estado muda quando o alvo travado se move (quadro acompanha).
                    repaint: Listenable.merge([_ponteiro, _trava, _mov, _estado]),
                    ponteiro: () => _ponteiro.value,
                    origem: () => _origem,
                    trava: () => Curves.easeOut.transform(_trava.value),
                    quadro: _rectAtual,
                    alvoCentro: () => (_para ?? _ultimo)?.center,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MiraPainter extends CustomPainter {
  _MiraPainter({
    required Listenable repaint,
    required this.ponteiro,
    required this.origem,
    required this.trava,
    required this.quadro,
    required this.alvoCentro,
  }) : super(repaint: repaint);

  final Offset? Function() ponteiro;
  final Offset Function() origem;
  final double Function() trava;
  final Rect? Function() quadro;
  final Offset? Function() alvoCentro;

  @override
  void paint(Canvas canvas, Size size) {
    final global = ponteiro();
    if (global == null) return;
    final o = origem();
    final p = global - o;
    final travaT = trava();
    final cor = AppColors.accent;

    // As linhas vão do ponteiro ao centro do alvo conforme a trava.
    var centro = p;
    final alvo = alvoCentro();
    if (alvo != null && travaT > 0) centro = Offset.lerp(p, alvo - o, travaT)!;

    final linha = Paint()
      ..color = cor.withValues(alpha: 0.55)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final x = centro.dx.floorToDouble() + 0.5;
    final y = centro.dy.floorToDouble() + 0.5;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linha);
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linha);

    if (travaT < 0.999) {
      _rotulo(
        canvas,
        size,
        '${global.dx.round()}, ${global.dy.round()}',
        p + const Offset(12, 12),
        1 - travaT,
        cor,
      );
    }

    final r = quadro();
    if (r != null && travaT > 0.001) {
      final q = r.shift(-o).inflate(6);
      _cantoneiras(canvas, q, cor.withValues(alpha: travaT));
      _rotulo(
        canvas,
        size,
        '${r.width.round()} × ${r.height.round()}',
        Offset(q.center.dx, q.bottom + 6),
        travaT,
        cor,
        centralizar: true,
      );
    }
  }

  void _cantoneiras(Canvas canvas, Rect q, Color cor) {
    final braco = (q.shortestSide / 3).clamp(0.0, 14.0);
    final paint = Paint()
      ..color = cor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.square;
    final path = Path()
      ..moveTo(q.left, q.top + braco)
      ..lineTo(q.left, q.top)
      ..lineTo(q.left + braco, q.top)
      ..moveTo(q.right - braco, q.top)
      ..lineTo(q.right, q.top)
      ..lineTo(q.right, q.top + braco)
      ..moveTo(q.right, q.bottom - braco)
      ..lineTo(q.right, q.bottom)
      ..lineTo(q.right - braco, q.bottom)
      ..moveTo(q.left + braco, q.bottom)
      ..lineTo(q.left, q.bottom)
      ..lineTo(q.left, q.bottom - braco);
    canvas.drawPath(path, paint);
  }

  void _rotulo(
    Canvas canvas,
    Size area,
    String texto,
    Offset ancora,
    double opacidade,
    Color fundo, {
    bool centralizar = false,
  }) {
    if (opacidade <= 0.001) return;
    final fundoEscuro = ThemeData.estimateBrightnessForColor(fundo) == Brightness.dark;
    final tp = TextPainter(
      text: TextSpan(
        text: texto,
        style: TextStyle(
          fontSize: 11,
          height: 1.1,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: (fundoEscuro ? Colors.white : const Color(0xFF111111)).withValues(alpha: opacidade),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const margem = EdgeInsets.symmetric(horizontal: 5, vertical: 2);
    final w = tp.width + margem.horizontal;
    final h = tp.height + margem.vertical;
    var left = centralizar ? ancora.dx - w / 2 : ancora.dx;
    var top = ancora.dy;
    // Vira para dentro da janela quando encosta na borda.
    if (!centralizar && left + w > area.width - 4) left = ancora.dx - 24 - w;
    if (top + h > area.height - 4) top = centralizar ? ancora.dy - h - 12 - 6 : ancora.dy - 24 - h;
    left = left.clamp(4.0, (area.width - w - 4).clamp(4.0, double.infinity));
    top = top.clamp(4.0, (area.height - h - 4).clamp(4.0, double.infinity));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), const Radius.circular(3)),
      Paint()..color = fundo.withValues(alpha: 0.92 * opacidade),
    );
    tp.paint(canvas, Offset(left + margem.left, top + margem.top));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_MiraPainter old) => true;
}
