import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Faz o filho ser "atraído" pelo ponteiro, inspirado no Magnet do React Bits.
///
/// Com o ponteiro a até [padding] px da borda do filho, ele se desloca na
/// direção do ponteiro: `offset = (ponteiro - centro) / strength`. Ao sair
/// dessa área volta à posição original com uma mola ([settle]).
///
/// A área expandida não existe como widget (não muda o layout nem rouba cliques):
/// o ponteiro é acompanhado por uma rota global do `GestureBinding`, que só
/// observa os eventos. O deslocamento é só um `Transform.translate`.
class Magnet extends StatefulWidget {
  const Magnet({
    super.key,
    required this.child,
    this.padding = 60,
    this.strength = 4,
    this.settle = const Duration(milliseconds: 500),
    this.enabled = true,
  });

  final Widget child;

  /// Distância além da borda do filho em que o ponteiro já atrai.
  final double padding;

  /// Quanto maior, mais fraco o deslocamento.
  final double strength;

  /// Duração da volta (mola) ao sair da área.
  final Duration settle;

  final bool enabled;

  @override
  State<Magnet> createState() => _MagnetState();
}

class _MagnetState extends State<Magnet> {
  Offset _alvo = Offset.zero;
  bool _seguindo = false;
  bool _rotaAtiva = false;

  bool get _ativo => widget.enabled && !MediaQuery.disableAnimationsOf(context);

  void _sincronizarRota() {
    final deve = _ativo;
    if (deve == _rotaAtiva) return;
    _rotaAtiva = deve;
    if (deve) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_aoEvento);
    } else {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_aoEvento);
      if (_alvo != Offset.zero) {
        setState(() {
          _alvo = Offset.zero;
          _seguindo = false;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sincronizarRota();
  }

  @override
  void didUpdateWidget(Magnet old) {
    super.didUpdateWidget(old);
    _sincronizarRota();
  }

  @override
  void dispose() {
    if (_rotaAtiva) GestureBinding.instance.pointerRouter.removeGlobalRoute(_aoEvento);
    super.dispose();
  }

  void _aoEvento(PointerEvent e) {
    if (!mounted) return;
    if (e.kind != PointerDeviceKind.mouse) return;
    if (e is PointerRemovedEvent) {
      _mover(Offset.zero, seguindo: false);
      return;
    }
    if (e is! PointerHoverEvent && e is! PointerMoveEvent && e is! PointerDownEvent && e is! PointerUpEvent) {
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final area = (box.localToGlobal(Offset.zero) & box.size).inflate(widget.padding);
    if (area.contains(e.position)) {
      final centro = box.localToGlobal(box.size.center(Offset.zero));
      final forca = widget.strength == 0 ? 1.0 : widget.strength;
      _mover((e.position - centro) / forca, seguindo: true);
    } else {
      _mover(Offset.zero, seguindo: false);
    }
  }

  void _mover(Offset alvo, {required bool seguindo}) {
    if (alvo == _alvo && seguindo == _seguindo) return;
    setState(() {
      _alvo = alvo;
      _seguindo = seguindo;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Seguindo o ponteiro: resposta curta; ao soltar: mola.
    return Padding(
      // Âncora estável: a caixa do Padding não se move com o deslocamento.
      padding: EdgeInsets.zero,
      child: TweenAnimationBuilder<Offset>(
        tween: Tween<Offset>(end: _alvo),
        duration: _seguindo ? const Duration(milliseconds: 140) : widget.settle,
        curve: _seguindo ? Curves.easeOut : Curves.elasticOut,
        builder: (context, offset, filho) => Transform.translate(offset: offset, child: filho),
        child: widget.child,
      ),
    );
  }
}
