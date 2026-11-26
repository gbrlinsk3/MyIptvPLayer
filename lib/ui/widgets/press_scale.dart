import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Ponteiros apertados sobre um botão interno: quem está por fora não encolhe.
/// O Flutter entrega o evento primeiro ao widget mais de dentro.
final Set<int> _claimed = <int>{};

/// Encolhe [child] enquanto o botão principal do mouse está apertado sobre ele,
/// para confirmar o clique na hora. Só observa o ponteiro: não disputa o toque
/// com o filho. Arrastar (fileiras) solta o efeito.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});

  final Widget child;

  static const double pressedScale = 0.97;
  static const Duration duration = Duration(milliseconds: 120);
  static const Curve curve = Cubic(0.23, 1, 0.32, 1);

  /// Quanto o mouse pode andar apertado antes de virar arrasto.
  static const double dragSlop = 8;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  int? _pointer;
  Offset _start = Offset.zero;
  bool _pressed = false;

  void _down(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton || !_claimed.add(e.pointer)) return;
    _pointer = e.pointer;
    _start = e.position;
    setState(() => _pressed = true);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || !_pressed) return;
    if ((e.position - _start).distance > PressScale.dragSlop) {
      setState(() => _pressed = false);
    }
  }

  void _end(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _claimed.remove(e.pointer);
    _pointer = null;
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  void dispose() {
    _claimed.remove(_pointer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _end,
      onPointerCancel: _end,
      child: AnimatedScale(
        scale: _pressed ? PressScale.pressedScale : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : PressScale.duration,
        curve: PressScale.curve,
        child: widget.child,
      ),
    );
  }
}

/// Para botões dentro de um cartão com [PressScale] (coração, "X"): apertar
/// neles não encolhe o cartão, porque a ação não é abrir o cartão.
class PressShield extends StatelessWidget {
  const PressShield({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => _claimed.add(e.pointer),
      onPointerUp: (e) => _claimed.remove(e.pointer),
      onPointerCancel: (e) => _claimed.remove(e.pointer),
      child: child,
    );
  }
}
