import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// Botão circular de seta com comportamento de estilingue, para as setas do
/// banner. O visual base é o do `CarouselArrowButton` (fundo da superfície,
/// borda fina), mas em tamanho configurável.
///
/// - Clicar: o botão recua um pouco ao apertar, dispara para a frente com uma
///   mola e solta uma rajada de pontinhos na direção da seta; chama [onFire].
/// - Arrastar para qualquer lado: o botão segue o ponteiro esticando com
///   "rubberband" até [maxPull], desenhando dois elásticos finos. Soltar com o
///   puxão em [armAt] ou mais dispara para o lado oposto ao do puxão (rajada
///   maior) e chama [onFire]; menos que isso volta sem disparar.
/// - [enabled] falso: apagado e sem nenhuma ação.
/// - Teclado: Enter ou Espaço disparam como um clique.
///
/// Inspirado no SlingButton do React Bits. Com `disableAnimations` não há
/// mola nem rajada: o botão só dispara.
class SlingArrowButton extends StatefulWidget {
  const SlingArrowButton({
    super.key,
    required this.left,
    required this.enabled,
    required this.onFire,
    this.size = 44,
    this.maxPull = 36,
    this.armAt = 18,
  });

  /// Seta para a esquerda (anterior) ou para a direita (próximo).
  final bool left;
  final bool enabled;
  final VoidCallback onFire;
  final double size;

  /// Quanto o botão pode se afastar do lugar ao ser puxado (visual).
  final double maxPull;

  /// Puxão (em pixels do ponteiro) a partir do qual soltar dispara.
  final double armAt;

  /// Movimento do ponteiro, em pixels, que ainda conta como clique.
  static const double clickSlop = 6;

  @override
  State<SlingArrowButton> createState() => _SlingArrowButtonState();
}

class _Particle {
  _Particle({
    required this.axis,
    required this.angle,
    required this.distance,
    required this.radius,
    required this.life,
    required this.delay,
  });

  final double axis; // direção do disparo (de onde a rajada sai do botão)
  final double angle;
  final double distance;
  final double radius;
  final double life; // segundos
  final double delay; // segundos
  double age = 0;
}

class _Repaint extends ChangeNotifier {
  void poke() => notifyListeners();
}

class _SlingArrowButtonState extends State<SlingArrowButton>
    with SingleTickerProviderStateMixin {
  static const double _stiffness = 420;
  static const double _damping = 16; // subamortecida: passa um pouco do ponto
  static const double _pressDepth = 5;

  final _repaint = _Repaint();
  late final Ticker _ticker = createTicker(_tick);
  final FocusNode _focus = FocusNode(debugLabel: 'SlingArrowButton');
  final math.Random _rng = math.Random();

  // Deslocamento do botão em relação ao lugar de repouso.
  Offset _off = Offset.zero;
  Offset _vel = Offset.zero;
  Offset _target = Offset.zero;
  final List<_Particle> _particles = [];
  Duration _last = Duration.zero;

  Offset? _down;
  bool _dragging = false;
  double _pull = 0; // puxão bruto do ponteiro (distância desde o clique)
  Offset _pullDir = Offset.zero; // direção do puxão (vetor unitário)
  bool _hover = false;
  bool _focused = false;
  bool _reduce = false;

  /// Direção da seta no eixo X (-1 esquerda, +1 direita).
  double get _fwd => widget.left ? -1 : 1;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focused != _focus.hasFocus) {
        setState(() => _focused = _focus.hasFocus);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(SlingArrowButton old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && old.enabled) _reset();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _reset() {
    _down = null;
    _dragging = false;
    _pull = 0;
    _pullDir = Offset.zero;
    _target = Offset.zero;
    _off = Offset.zero;
    _vel = Offset.zero;
    _particles.clear();
    if (_ticker.isActive) _ticker.stop();
    _repaint.poke();
  }

  // ---- física -----------------------------------------------------------

  void _wake() {
    if (_reduce) return;
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

    if (!_dragging) {
      const sub = 1 / 240;
      var restante = dt;
      while (restante > 1e-9) {
        final h = math.min(sub, restante);
        restante -= h;
        _vel += ((_off - _target) * -_stiffness - _vel * _damping) * h;
        _off += _vel * h;
      }
    }
    for (final p in _particles) {
      p.age += dt;
    }
    _particles.removeWhere((p) => p.age >= p.life + p.delay);
    _repaint.poke();

    final mola = !_dragging &&
        ((_off - _target).distance > 0.05 || _vel.distance > 0.5);
    if (!mola && _particles.isEmpty && !_dragging) {
      _off = _target;
      _vel = Offset.zero;
      _ticker.stop();
    }
  }

  /// Puxão exibido: sobe rápido e satura em [SlingArrowButton.maxPull].
  double _display(double pull) {
    final m = widget.maxPull;
    if (m <= 0) return 0;
    return m * (1 - math.exp(-pull / m));
  }

  /// Rajada de [count] pontinhos saindo do botão na direção [angle] (padrão: a
  /// da seta). [power] > 1 deixa a rajada mais forte.
  void _burst(int count, double power, {double? angle}) {
    if (_reduce) return;
    final base = angle ?? (widget.left ? math.pi : 0.0);
    final cone = 70 * math.pi / 180;
    for (var i = 0; i < count; i++) {
      final lead = i == 0;
      final spread = lead ? 0.0 : (_rng.nextDouble() + _rng.nextDouble() - 1);
      _particles.add(
        _Particle(
          axis: base,
          angle: base + spread * cone / 2,
          distance: widget.size * (lead ? 0.75 : 0.3 + _rng.nextDouble() * 0.5) *
              power,
          radius: (widget.size / 14) * (lead ? 1 : 0.5 + _rng.nextDouble() * 0.6),
          life: 0.3 + _rng.nextDouble() * 0.15,
          delay: lead ? 0 : _rng.nextDouble() * 0.06,
        ),
      );
    }
    _wake();
  }

  // ---- ações ------------------------------------------------------------

  /// Clique (ou teclado): dispara para a frente com mola e rajada curta.
  void _click() {
    if (!widget.enabled) return;
    _target = Offset.zero;
    // Chute para a frente; a mola passa do ponto e volta.
    _vel = Offset(_fwd * 140, 0);
    _burst(6, 1);
    _wake();
    widget.onFire();
  }

  /// Soltou o estilingue esticado além de [SlingArrowButton.armAt]: o botão
  /// dispara para o lado oposto ao do puxão, seja qual for.
  void _fireFromPull(Offset dir) {
    _target = Offset.zero;
    final fire = -dir;
    _vel = fire * math.max(160.0, _off.distance * 14);
    _burst(10, 1.25, angle: math.atan2(fire.dy, fire.dx));
    _wake();
    widget.onFire();
  }

  void _onDown(PointerDownEvent e) {
    if (!widget.enabled) return;
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryButton) return;
    _down = e.position;
    _dragging = false;
    _pull = 0;
    _pullDir = Offset.zero;
    _target = Offset(-_fwd * math.min(_pressDepth, widget.maxPull), 0);
    _wake();
  }

  void _onMove(PointerMoveEvent e) {
    final down = _down;
    if (down == null) return;
    final delta = e.position - down;
    if (!_dragging && delta.distance > SlingArrowButton.clickSlop) {
      _dragging = true;
    }
    if (!_dragging) return;
    // Qualquer direção estica: o botão segue o ponteiro com resistência.
    _pull = delta.distance;
    _pullDir = delta / _pull;
    _off = _pullDir * _display(_pull);
    _vel = Offset.zero;
    _wake();
    _repaint.poke();
  }

  void _onUp(PointerUpEvent e) {
    final down = _down;
    if (down == null) return;
    final foiPuxao = _dragging;
    final pull = _pull;
    final dir = _pullDir;
    _down = null;
    _dragging = false;
    _pull = 0;
    _pullDir = Offset.zero;
    if (!foiPuxao) {
      _click();
    } else if (pull >= widget.armAt) {
      _fireFromPull(dir);
    } else {
      _target = Offset.zero;
      _vel = Offset.zero;
    }
    if (_reduce) {
      // Sem mola: volta ao lugar de uma vez.
      _off = Offset.zero;
      _vel = Offset.zero;
      _target = Offset.zero;
      _repaint.poke();
      return;
    }
    _wake();
  }

  void _onCancel(PointerCancelEvent e) {
    if (_down == null) return;
    _down = null;
    _dragging = false;
    _pull = 0;
    _pullDir = Offset.zero;
    _target = Offset.zero;
    if (_reduce) {
      _off = Offset.zero;
      _repaint.poke();
    }
    _wake();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.space) {
      _click();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- construção -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final label = widget.left ? 'Anterior' : 'Próximo';
    final enabled = widget.enabled;
    final s = widget.size;
    final contorno = _focused &&
        enabled &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    final pad = AnimatedBuilder(
      animation: _repaint,
      builder: (context, child) =>
          Transform.translate(offset: _off, child: child),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled && _hover
              ? AppColors.hover
              : AppColors.surface,
          border: Border.all(
            color: contorno ? AppColors.accent : AppColors.border,
            width: contorno ? 2 : 1,
          ),
        ),
        child: SizedBox(
          width: s,
          height: s,
          child: Icon(
            widget.left ? Icons.chevron_left : Icons.chevron_right,
            size: s * 22 / 36,
            color: enabled ? AppColors.text : AppColors.text.withAlpha(90),
          ),
        ),
      ),
    );

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        onTap: enabled ? _click : null,
        excludeSemantics: true,
        child: Focus(
          focusNode: _focus,
          canRequestFocus: enabled,
          onKeyEvent: _onKey,
          child: MouseRegion(
            cursor:
                enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              onPointerCancel: _onCancel,
              child: SizedBox(
                width: s,
                height: s,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _SlingPainter(
                            repaint: _repaint,
                            state: this,
                            accent: AppColors.accent,
                            muted: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(child: pad),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlingPainter extends CustomPainter {
  _SlingPainter({
    required Listenable repaint,
    required this.state,
    required this.accent,
    required this.muted,
  }) : super(repaint: repaint);

  final _SlingArrowButtonState state;
  final Color accent;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final w = state.widget;
    final center = size.center(Offset.zero);
    final off = state._off;
    final pos = off.distance;

    // Esticado: o lugar de repouso ganha um círculo só de borda (igual ao
    // contorno do botão) e duas tangentes o ligam ao botão, como uma correia.
    if (pos > 0.8) {
      final k = (pos / w.armAt).clamp(0.0, 1.0).toDouble();
      final armed = state._dragging && state._pull >= w.armAt;
      final color = (armed ? accent : muted).withValues(alpha: 0.35 + 0.65 * k);
      final line = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      final r = w.size / 2;
      final dir = off / pos; // para onde o botão foi puxado
      final perp = Offset(-dir.dy, dir.dx);
      final pad = center + off;
      canvas.drawCircle(center, r, line);
      for (final side in const [-1.0, 1.0]) {
        canvas.drawLine(center + perp * (side * r), pad + perp * (side * r), line);
      }
    }

    // Rajada: sai da frente do botão e se dissolve.
    for (final p in state._particles) {
      final origin =
          center + Offset(math.cos(p.axis), math.sin(p.axis)) * (w.size / 2);
      final t = ((p.age - p.delay) / p.life).clamp(0.0, 1.0).toDouble();
      if (p.age < p.delay) continue;
      final ease = 1 - math.pow(1 - t, 3).toDouble();
      final at = origin +
          Offset(math.cos(p.angle), math.sin(p.angle)) * (p.distance * ease);
      final r = p.radius * (1 - 0.7 * t);
      canvas.drawCircle(
        at,
        r,
        Paint()..color = accent.withValues(alpha: 1 - t),
      );
    }
  }

  @override
  bool shouldRepaint(_SlingPainter old) =>
      old.accent != accent || old.muted != muted;
}
