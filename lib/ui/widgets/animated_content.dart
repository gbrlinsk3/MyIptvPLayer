import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Guarda quais [AnimatedContent.revealId] já foram revelados dentro de um
/// trecho da interface (por exemplo, uma página), para a entrada tocar só na
/// primeira vez e não repetir quando o conteúdo é remontado (troca de aba,
/// rolagem de listas virtualizadas etc.).
class RevealScope extends StatefulWidget {
  const RevealScope({super.key, required this.child});

  final Widget child;

  /// O escopo mais próximo, ou `null`. Não registra dependência.
  static RevealScopeState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_RevealInherited>()?.state;

  @override
  State<RevealScope> createState() => RevealScopeState();
}

class RevealScopeState extends State<RevealScope> {
  final Set<Object> _revelados = <Object>{};

  bool jaRevelado(Object id) => _revelados.contains(id);

  void marcarRevelado(Object id) => _revelados.add(id);

  @override
  Widget build(BuildContext context) => _RevealInherited(state: this, child: widget.child);
}

class _RevealInherited extends InheritedWidget {
  const _RevealInherited({required this.state, required super.child});

  final RevealScopeState state;

  @override
  bool updateShouldNotify(_RevealInherited old) => false;
}

/// Entrada com fade + deslocamento (e desfoque opcional) ao montar, inspirada
/// no AnimatedContent do React Bits.
///
/// Só usa Transform/Opacity, então o layout não muda. Com um [RevealScope]
/// acima e [revealId] != null, a entrada toca apenas na primeira vez que aquele
/// id aparece no escopo; depois o conteúdo já nasce no estado final. Com
/// `MediaQuery.disableAnimations` ligado também nasce no estado final.
///
/// O deslocamento vai de [distance] px (na [direction]; negativo com [reverse])
/// até 0.
class AnimatedContent extends StatefulWidget {
  const AnimatedContent({
    super.key,
    required this.child,
    this.distance = 32,
    this.direction = Axis.vertical,
    this.reverse = false,
    this.duration = const Duration(milliseconds: 500),
    this.delay = Duration.zero,
    this.curve = Curves.easeOutCubic,
    this.initialOpacity = 0,
    this.blur = 0,
    this.revealId,
  });

  final Widget child;
  final double distance;
  final Axis direction;

  /// Vem do lado oposto (de cima / da esquerda).
  final bool reverse;
  final Duration duration;
  final Duration delay;
  final Curve curve;
  final double initialOpacity;

  /// Sigma inicial do desfoque (0 = sem desfoque).
  final double blur;

  /// Identifica este conteúdo dentro de um [RevealScope].
  final Object? revealId;

  @override
  State<AnimatedContent> createState() => _AnimatedContentState();
}

class _AnimatedContentState extends State<AnimatedContent> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this);
  bool _inicializado = false;

  Duration get _total => widget.delay + widget.duration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inicializado) {
      if (MediaQuery.disableAnimationsOf(context) && _ctl.isAnimating) {
        _ctl.stop();
        _ctl.value = 1;
      }
      return;
    }
    _inicializado = true;
    final escopo = RevealScope.maybeOf(context);
    final id = widget.revealId;
    final jaRevelado = escopo != null && id != null && escopo.jaRevelado(id);
    if (escopo != null && id != null) escopo.marcarRevelado(id);

    if (jaRevelado || MediaQuery.disableAnimationsOf(context) || widget.duration <= Duration.zero) {
      _ctl.value = 1;
      return;
    }
    _ctl.duration = _total;
    _ctl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalUs = _total.inMicroseconds;
    final inicio = totalUs <= 0 ? 0.0 : widget.delay.inMicroseconds / totalUs;
    final curva = Interval(inicio.clamp(0.0, 1.0), 1, curve: widget.curve);
    return AnimatedBuilder(
      animation: _ctl,
      child: widget.child,
      builder: (context, filho) {
        final t = curva.transform(_ctl.value);
        final resta = 1 - t;
        final deslocamento = (widget.reverse ? -widget.distance : widget.distance) * resta;
        final offset = widget.direction == Axis.vertical ? Offset(0, deslocamento) : Offset(deslocamento, 0);
        final opacidade = widget.initialOpacity + (1 - widget.initialOpacity) * t;
        final sigma = widget.blur * resta;
        return ImageFiltered(
          enabled: widget.blur > 0 && sigma > 0.01,
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Opacity(
            opacity: opacidade.clamp(0.0, 1.0),
            child: Transform.translate(offset: offset, child: filho),
          ),
        );
      },
    );
  }
}
