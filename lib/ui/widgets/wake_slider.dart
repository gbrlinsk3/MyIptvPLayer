import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// Controle deslizante de barras finas, sem bolinha, feito para volume.
///
/// As barras até o valor ficam acesas ([fillColor]) e as demais apagadas
/// ([trackColor]). A velocidade do arraste levanta uma "esteira" de barras em
/// volta do ponteiro (mais larga atrás do que na frente, conforme [skew]) que
/// volta a baixar suavemente quando o movimento para.
///
/// - Clicar ou arrastar leva ao ponto tocado; a roda do mouse muda ±5.
/// - Teclado: setas ±5 (esquerda/baixo diminuem), Home = mínimo, End = máximo.
/// - [onChanged] recebe valores inteiros e só é chamado quando o valor muda;
///   [onChangeEnd] é chamado ao soltar e depois de roda/teclado.
/// - Anunciado como controle deslizante, com o valor em %.
///
/// Inspirado no WakeSlider do React Bits. Com `disableAnimations`, a esteira
/// não aparece e a posição vai direto ao valor.
class WakeSlider extends StatefulWidget {
  const WakeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    this.onChangeEnd,
    this.bars = 24,
    this.height = 28,
    this.restHeight = 6,
    this.gap = 3,
    this.fillColor,
    this.trackColor,
    this.sensitivity = 1,
    this.reach = 5,
    this.skew = 0.6,
    this.semanticLabel = 'Volume',
    this.width = 120,
    this.restoreFocusOnRelease = false,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  /// Quantidade de barras.
  final int bars;

  /// Altura máxima de uma barra (no pico da esteira).
  final double height;

  /// Altura de uma barra em repouso.
  final double restHeight;

  /// Espaço entre barras.
  final double gap;

  /// Cor das barras acesas. Padrão: branco.
  final Color? fillColor;

  /// Cor das barras apagadas. Padrão: branco com 24% de opacidade.
  final Color? trackColor;

  /// Multiplica a velocidade que alimenta a esteira (maior = reage mais).
  final double sensitivity;

  /// Alcance da esteira, em barras, na velocidade máxima.
  final int reach;

  /// Assimetria da esteira: 0 = simétrica; maior = mais larga atrás.
  final double skew;

  final String semanticLabel;
  final double width;

  /// Ao soltar o mouse, devolve o foco a quem o tinha antes do clique. Serve
  /// para players, onde as setas do teclado devem continuar trocando de canal
  /// ou avançando o vídeo, e não mexendo no volume.
  final bool restoreFocusOnRelease;

  /// Passo da roda do mouse e das setas.
  static const double step = 5;

  // Constantes da esteira (as mesmas do componente original).
  static const double _settle = 9.23;
  static const double _glide = 0.3;
  static const double _fullSpeed = 320; // % por segundo
  static const double _minReach = 1.5;
  static const double _flat = 0.002;

  @override
  State<WakeSlider> createState() => _WakeSliderState();
}

class _Repaint extends ChangeNotifier {
  void poke() => notifyListeners();
}

class _WakeSliderState extends State<WakeSlider>
    with SingleTickerProviderStateMixin {
  final _repaint = _Repaint();
  late final Ticker _ticker = createTicker(_tick);
  final FocusNode _focus = FocusNode(debugLabel: 'WakeSlider');
  FocusNode? _previousFocus;

  // Mola da cabeça (acompanha o valor, em % do curso) e filtro da velocidade.
  double _head = 0;
  double _headVel = 0;
  double _speed = 0;
  double _speedVel = 0;
  double _amp = 0;
  double _dir = 1;
  Duration _last = Duration.zero;

  bool _reduce = false;
  bool _dragging = false;
  double _latest = 0; // último valor entregue ao dono (evita chamadas repetidas)

  double get _pct => widget.max > widget.min
      ? ((widget.value - widget.min) / (widget.max - widget.min) * 100)
          .clamp(0.0, 100.0)
          .toDouble()
      : 0;

  @override
  void initState() {
    super.initState();
    _head = _pct;
    _latest = widget.value;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    if (_reduce) _settleNow();
  }

  @override
  void didUpdateWidget(WakeSlider old) {
    super.didUpdateWidget(old);
    _latest = widget.value;
    if (_reduce) {
      _settleNow();
    } else if (old.value != widget.value) {
      _wake();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    _repaint.dispose();
    super.dispose();
  }

  // ---- física -----------------------------------------------------------

  void _settleNow() {
    _head = _pct;
    _headVel = 0;
    _speed = 0;
    _speedVel = 0;
    _amp = 0;
    if (_ticker.isActive) _ticker.stop();
    _repaint.poke();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) {
      _repaint.poke();
      return;
    }
    dt = math.min(dt, 0.05);

    final target = _pct;
    const w0 = WakeSlider._settle / WakeSlider._glide; // mola criticamente amortecida
    const wv = 2000 / 100; // suavização da velocidade
    // Passos pequenos mantêm a integração estável mesmo com quadros lentos.
    const sub = 1 / 240;
    var restante = dt;
    while (restante > 1e-9) {
      final h = math.min(sub, restante);
      restante -= h;
      final accel = -w0 * w0 * (_head - target) - 2 * w0 * _headVel;
      _headVel += accel * h;
      _head += _headVel * h;
      final aSpeed = -wv * wv * (_speed - _headVel) - 2.5 * wv * _speedVel;
      _speedVel += aSpeed * h;
      _speed += _speedVel * h;
    }

    final amp = _ampOf(_speed);
    if (_speed.abs() > 1e-3) _dir = _speed.sign;
    _amp = amp;
    _repaint.poke();

    final parado = (_head - target).abs() < 0.02 &&
        _headVel.abs() < 0.05 &&
        _speed.abs() < 0.5 &&
        _speedVel.abs() < 1 &&
        amp < WakeSlider._flat;
    if (parado) {
      _head = target;
      _headVel = 0;
      _speed = 0;
      _speedVel = 0;
      _amp = 0;
      _ticker.stop();
      _repaint.poke();
    }
  }

  double _ampOf(double speed) {
    final s = (speed.abs() * widget.sensitivity / WakeSlider._fullSpeed)
        .clamp(0.0, 1.0)
        .toDouble();
    return s * s * (3 - 2 * s);
  }

  // ---- entrada ----------------------------------------------------------

  double _valueAt(double dx) {
    final box = context.findRenderObject();
    final w = box is RenderBox && box.hasSize ? box.size.width : widget.width;
    if (w <= 0) return widget.value;
    final ratio = (dx / w).clamp(0.0, 1.0).toDouble();
    return widget.min + ratio * (widget.max - widget.min);
  }

  /// Entrega [raw] ao dono (arredondado a inteiros) só se mudou.
  void _commit(double raw) {
    final v = raw.round().clamp(widget.min, widget.max).toDouble();
    if (v == _latest) return;
    _latest = v;
    widget.onChanged(v);
  }

  void _end() => widget.onChangeEnd?.call(_latest);

  void _onDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryButton) return;
    _dragging = true;
    _previousFocus = FocusManager.instance.primaryFocus;
    _focus.requestFocus();
    _commit(_valueAt(e.localPosition.dx));
  }

  void _onMove(PointerMoveEvent e) {
    if (!_dragging) return;
    _commit(_valueAt(e.localPosition.dx));
  }

  void _onUp(PointerEvent e) {
    if (!_dragging) return;
    _dragging = false;
    _end();
    final anterior = _previousFocus;
    _previousFocus = null;
    if (widget.restoreFocusOnRelease &&
        anterior != null &&
        anterior != _focus &&
        anterior.context != null &&
        anterior.canRequestFocus) {
      anterior.requestFocus();
    }
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final dy = (event as PointerScrollEvent).scrollDelta.dy;
      if (dy == 0) return;
      _nudge(dy < 0 ? WakeSlider.step : -WakeSlider.step);
    });
  }

  void _nudge(double delta) {
    _commit(_latest + delta);
    _end();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.arrowUp) {
      _nudge(WakeSlider.step);
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowDown) {
      _nudge(-WakeSlider.step);
    } else if (k == LogicalKeyboardKey.home) {
      _commit(widget.min);
      _end();
    } else if (k == LogicalKeyboardKey.end) {
      _commit(widget.max);
      _end();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---- construção -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final fill = widget.fillColor ?? Colors.white;
    final track = widget.trackColor ?? Colors.white24;
    final pct = _pct.round();

    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      value: '$pct%',
      increasedValue:
          '${(_pct + WakeSlider.step).clamp(0, 100).round()}%',
      decreasedValue:
          '${(_pct - WakeSlider.step).clamp(0, 100).round()}%',
      onIncrease: () => _nudge(WakeSlider.step),
      onDecrease: () => _nudge(-WakeSlider.step),
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: _onUp,
            onPointerSignal: _onSignal,
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: CustomPaint(
                painter: _WakePainter(
                  repaint: _repaint,
                  state: this,
                  fill: fill,
                  track: track,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WakePainter extends CustomPainter {
  _WakePainter({
    required Listenable repaint,
    required this.state,
    required this.fill,
    required this.track,
  }) : super(repaint: repaint);

  final _WakeSliderState state;
  final Color fill;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final w = state.widget;
    final n = w.bars;
    if (n <= 0 || size.isEmpty) return;

    final barW = math.max(1.0, (size.width - w.gap * (n - 1)) / n);
    final rest = math.min(w.restHeight, w.height - 1) / w.height;
    final h = (state._reduce ? state._pct : state._head) / 100 * (n - 1);
    final amp = state._reduce ? 0.0 : state._amp;
    final dir = state._dir;
    final r = WakeSlider._minReach + (w.reach - WakeSlider._minReach) * amp;
    final behind = r * (1 + w.skew);
    final ahead = r * (1 - 0.5 * w.skew);
    // Em mínimo (volume 0) nenhuma barra fica acesa.
    final lit = state._pct <= 0 ? -1 : h.round();

    final paintOn = Paint()..color = fill;
    final paintOff = Paint()..color = track;
    for (var i = 0; i < n; i++) {
      final d = i - h;
      final reach = d * dir < 0 ? behind : ahead;
      final lift = d.abs() < reach
          ? amp * math.pow(math.cos(math.pi * d / (2 * reach)), 2).toDouble()
          : 0.0;
      final scale = rest + lift * (1 - rest);
      final bh = scale * size.height;
      final x = i * (barW + w.gap);
      final rect = Rect.fromLTWH(x, (size.height - bh) / 2, barW, bh);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(AppShape.r(math.min(barW, bh) / 2)),
        ),
        i <= lit ? paintOn : paintOff,
      );
    }
  }

  @override
  bool shouldRepaint(_WakePainter old) => true;
}
