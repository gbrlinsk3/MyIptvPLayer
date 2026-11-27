import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'edge_scroll_marks.dart';

/// Rolagem suave pela roda do mouse. No Windows cada dente da roda chega como
/// um salto de cerca de 100 px; aqui ele vira um movimento de mola sem repique,
/// e dentes seguidos somam no destino sem perder a velocidade. O touchpad (que
/// arrasta a página) e a barra de traços continuam diretos, assim como a roda
/// com "reduzir animações" ligado no Windows.

/// Rapidez da mola na roda: cerca de 90 % do caminho em 200 ms.
const double wheelScrollOmega = 20;

class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    this.holding,
    super.keepScrollOffset,
    super.debugLabel,
  });

  /// Verdadeiro enquanto o usuário arrasta a barra de rolagem: a página
  /// acompanha o ponteiro sem suavização.
  final ValueListenable<bool>? holding;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) =>
      SmoothScrollPosition(
        holding: holding,
        physics: physics,
        context: context,
        keepScrollOffset: keepScrollOffset,
        oldPosition: oldPosition,
      );
}

class SmoothScrollPosition extends ScrollPositionWithSingleContext {
  SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.keepScrollOffset,
    super.oldPosition,
    this.holding,
  });

  final ValueListenable<bool>? holding;

  /// Destino do movimento em curso; `null` quando parada ou em outro tipo de
  /// rolagem.
  double? get glideTarget {
    final current = activity;
    return current is _GlideActivity ? current.target : null;
  }

  /// Sem suavização: arrastando a barra ou com animações desligadas.
  bool get directScroll =>
      (holding?.value ?? false) ||
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
          .disableAnimations;

  @override
  void pointerScroll(double delta) {
    if (delta == 0 || directScroll) {
      super.pointerScroll(delta);
      return;
    }
    glideTo(wheelDestination(delta));
  }

  /// Onde a página vai parar com mais este giro da roda.
  double wheelDestination(double delta) => ((glideTarget ?? pixels) + delta)
      .clamp(minScrollExtent, maxScrollExtent)
      .toDouble();

  /// Leva a página até [target], mantendo a velocidade se já estiver andando.
  void glideTo(double target, {double omega = wheelScrollOmega}) {
    final current = activity;
    if (target == pixels && current is! _GlideActivity) return;
    updateUserScrollDirection(
      target > pixels ? ScrollDirection.reverse : ScrollDirection.forward,
    );
    if (current is _GlideActivity) {
      current
        ..target = target
        ..omega = omega;
      return;
    }
    beginActivity(
      _GlideActivity(
        this,
        position: this,
        vsync: context.vsync,
        target: target,
        omega: omega,
      ),
    );
  }
}

/// Mola com amortecimento crítico (chega sem passar do ponto), calculada de
/// forma exata a cada quadro: vale igual a 60 ou 144 Hz.
class _GlideActivity extends ScrollActivity {
  _GlideActivity(
    super.delegate, {
    required this.position,
    required TickerProvider vsync,
    required this.target,
    required this.omega,
  }) {
    _ticker = vsync.createTicker(_tick)..start();
  }

  final ScrollPosition position;
  double target;
  double omega;
  double _velocity = 0;
  Duration _last = Duration.zero;
  late final Ticker _ticker;
  bool _disposed = false;

  void _tick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) dt = 1 / 120; // o primeiro quadro já anda
    final end = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    final distance = position.pixels - end;
    final decay = math.exp(-omega * dt);
    final k = (_velocity + omega * distance) * dt;
    var next = end + (distance + k) * decay;
    _velocity = (_velocity - omega * k) * decay;
    final done = (next - end) * distance <= 0 ||
        ((next - end).abs() < 0.5 && _velocity.abs() < 30);
    if (done) next = end;
    final over = delegate.setPixels(next);
    if (!_disposed && (done || over != 0)) delegate.goBallistic(0);
  }

  @override
  bool get shouldIgnorePointer => false; // clicar vale mesmo em movimento

  @override
  bool get isScrolling => true;

  @override
  double get velocity => _velocity;

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    super.dispose();
  }
}

/// Dá a rolagem suave a uma lista que não tem controlador próprio.
class SmoothScroll extends StatefulWidget {
  const SmoothScroll({super.key, required this.builder});

  final Widget Function(BuildContext context, ScrollController controller)
      builder;

  @override
  State<SmoothScroll> createState() => _SmoothScrollState();
}

class _SmoothScrollState extends State<SmoothScroll> {
  final _controller =
      SmoothScrollController(holding: EdgeScrollMarks.segurando);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
