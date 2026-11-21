import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import '../../core/theme.dart';

/// Envoltório de aviso que se dispensa arrastando para baixo e, opcionalmente,
/// mostra um "pavio": uma barra fina no rodapé que encolhe conforme o tempo
/// restante do aviso acaba.
///
/// - Arrastar para baixo acompanha o dedo/mouse com um pouco de resistência
///   (para cima só cede alguns pixels). Soltar depois de 40% da altura, ou com
///   velocidade acima de 700 px/s, tira o aviso da tela e chama [onDismiss].
///   Soltar antes disso o devolve ao lugar com uma mola.
/// - Com [lifetime], o pavio vai de 100% a 0% e, ao zerar, chama [onTimeout]
///   (ou [onDismiss], se [onTimeout] for nulo). O tempo para com o mouse em
///   cima, durante o arrasto ou com [paused] ligado.
/// - [progress] (1 = cheio, 0 = acabou), se dado, substitui o tempo interno: o
///   pavio acompanha esse valor e o dono do aviso decide o que fazer ao zerar.
/// - Mudar [restartKey] reinicia o tempo e traz o aviso de volta.
///
/// Inspirado no SwipeToast do React Bits. Com `disableAnimations`, o aviso
/// sai e volta sem animar.
class SwipeToast extends StatefulWidget {
  const SwipeToast({
    super.key,
    required this.child,
    required this.onDismiss,
    this.lifetime,
    this.paused = false,
    this.onTimeout,
    this.fuseColor,
    this.restartKey,
    this.progress,
    this.dismissible = true,
  });

  final Widget child;

  /// Chamado depois que o aviso foi arrastado para fora (ou o tempo acabou e
  /// não há [onTimeout]).
  final VoidCallback onDismiss;

  /// Duração total do aviso; com ela aparece o pavio.
  final Duration? lifetime;

  /// Congela o tempo (além do mouse em cima).
  final bool paused;

  /// Chamado quando o tempo acaba. Se nulo, chama [onDismiss].
  final VoidCallback? onTimeout;

  /// Cor do pavio. Padrão: [AppColors.accent].
  final Color? fuseColor;

  /// Mudar este valor reinicia o tempo e reexibe o aviso.
  final Object? restartKey;

  /// Fração restante (1 a 0). Substitui o tempo interno e mostra o pavio.
  final ValueListenable<double>? progress;

  /// Falso desliga o arrasto para dispensar (o aviso só some pelo tempo ou
  /// pelo dono). O pavio continua.
  final bool dismissible;

  /// Fração da altura a partir da qual soltar dispensa o aviso.
  static const double dismissFraction = 0.4;

  /// Velocidade (px/s, para baixo) que dispensa o aviso mesmo com pouco arrasto.
  static const double dismissVelocity = 700;

  /// Quanto do movimento do ponteiro o aviso acompanha ao descer.
  static const double _follow = 0.9;

  /// Limite de quanto o aviso pode subir (com resistência).
  static const double _maxUp = 14;

  static const double fuseHeight = 2;

  @override
  State<SwipeToast> createState() => _SwipeToastState();
}

class _SwipeToastState extends State<SwipeToast> with TickerProviderStateMixin {
  // Deslocamento vertical do aviso (positivo = para baixo), animado por mola
  // ou pela saída.
  late final AnimationController _move = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );
  late final Ticker _clock = createTicker(_tick);

  // Tempo interno já gasto (sem contar o trecho atual do ticker).
  Duration _spentBefore = Duration.zero;
  Duration _spent = Duration.zero;
  final ValueNotifier<double> _fuse = ValueNotifier(1);

  bool _hover = false;
  bool _dragging = false;
  bool _dismissed = false;
  bool _fired = false;
  bool _reduce = false;
  double _drag = 0; // arrasto bruto do ponteiro, antes da resistência

  bool get _usesProgress => widget.progress != null;
  bool get _hasFuse => widget.lifetime != null || _usesProgress;

  @override
  void initState() {
    super.initState();
    widget.progress?.addListener(_onProgress);
    _syncFuse();
    _updateClock();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(SwipeToast old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress) {
      old.progress?.removeListener(_onProgress);
      widget.progress?.addListener(_onProgress);
    }
    if (old.restartKey != widget.restartKey) {
      _restart();
    } else if (old.lifetime != widget.lifetime) {
      _syncFuse();
    }
    _updateClock();
  }

  @override
  void dispose() {
    widget.progress?.removeListener(_onProgress);
    _clock.dispose();
    _move.dispose();
    _fuse.dispose();
    super.dispose();
  }

  // ---- tempo ------------------------------------------------------------

  void _restart() {
    _clock.stop();
    _spentBefore = Duration.zero;
    _spent = Duration.zero;
    _fired = false;
    _dismissed = false;
    _dragging = false;
    _drag = 0;
    _move.stop();
    _move.value = 0;
    _syncFuse();
  }

  void _syncFuse() {
    if (_usesProgress) {
      _fuse.value = widget.progress!.value.clamp(0.0, 1.0).toDouble();
      return;
    }
    final total = widget.lifetime;
    if (total == null || total <= Duration.zero) {
      _fuse.value = 1;
      return;
    }
    _fuse.value =
        (1 - _spent.inMicroseconds / total.inMicroseconds).clamp(0.0, 1.0).toDouble();
  }

  void _onProgress() => _syncFuse();

  bool get _shouldRun =>
      widget.lifetime != null &&
      !_usesProgress &&
      !widget.paused &&
      !_hover &&
      !_dragging &&
      !_dismissed &&
      !_fired;

  void _updateClock() {
    if (_shouldRun) {
      if (!_clock.isActive) {
        _spentBefore = _spent;
        _clock.start();
      }
    } else if (_clock.isActive) {
      _clock.stop();
    }
  }

  void _tick(Duration elapsed) {
    final total = widget.lifetime;
    if (total == null) return;
    _spent = _spentBefore + elapsed;
    _syncFuse();
    if (_spent >= total && !_fired) {
      _fired = true;
      _clock.stop();
      (widget.onTimeout ?? widget.onDismiss)();
    }
  }

  // ---- arrasto ----------------------------------------------------------

  double get _height {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.height : 0;
  }

  /// Aplica a resistência: para baixo acompanha 90%; para cima cede pouco.
  double _resist(double raw) {
    if (raw >= 0) return raw * SwipeToast._follow;
    const k = SwipeToast._maxUp;
    return -k * (1 - math.exp(raw / (k * 4)));
  }

  void _onDragStart(DragStartDetails d) {
    if (_dismissed) return;
    _move.stop();
    _dragging = true;
    _drag = _move.value / SwipeToast._follow;
    _updateClock();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_dismissed) return;
    _drag += d.delta.dy;
    _move.value = _resist(_drag);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dismissed) return;
    _dragging = false;
    final h = _height;
    final v = d.velocity.pixelsPerSecond.dy;
    final shown = _move.value;
    final far = h > 0 && shown > h * SwipeToast.dismissFraction;
    if (far || v > SwipeToast.dismissVelocity) {
      _exit(v);
    } else {
      _springBack(v);
    }
    _updateClock();
  }

  void _springBack(double velocity) {
    if (_reduce) {
      _move.value = 0;
      return;
    }
    _move.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 320, damping: 24),
        _move.value,
        0,
        velocity.clamp(-2000.0, 2000.0).toDouble(),
      ),
    );
  }

  void _exit(double velocity) {
    _dismissed = true;
    _clock.stop();
    if (_reduce) {
      widget.onDismiss();
      return;
    }
    final target = _height + 24;
    // Quanto mais rápido o gesto, mais curta a saída.
    final fast = velocity > SwipeToast.dismissVelocity;
    _move
        .animateTo(
          target,
          duration: Duration(milliseconds: fast ? 160 : 220),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
      if (mounted) widget.onDismiss();
    });
  }

  // ---- construção -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    Widget toast = AnimatedBuilder(
      animation: _move,
      builder: (context, child) {
        final h = _height;
        final dy = _move.value;
        // Esmaece só na saída, para o aviso não "piscar" ao ser arrastado.
        final fade = h <= 0 ? 1.0 : (1 - (dy / (h + 24)) * 0.6).clamp(0.0, 1.0);
        return Opacity(
          opacity: fade.toDouble(),
          child: Transform.translate(offset: Offset(0, dy), child: child),
        );
      },
      child: Stack(
        children: [
          widget.child,
          if (_hasFuse)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: SwipeToast.fuseHeight,
              child: IgnorePointer(
                child: ValueListenableBuilder<double>(
                  valueListenable: _fuse,
                  builder: (context, v, _) => Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      key: const ValueKey('swipe-toast-fuse'),
                      widthFactor: v,
                      heightFactor: 1,
                      child: ColoredBox(
                        color: widget.fuseColor ?? AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    toast = GestureDetector(
      onVerticalDragStart: widget.dismissible ? _onDragStart : null,
      onVerticalDragUpdate: widget.dismissible ? _onDragUpdate : null,
      onVerticalDragEnd: widget.dismissible ? _onDragEnd : null,
      onVerticalDragCancel: () {
        if (_dragging) {
          _dragging = false;
          _springBack(0);
          _updateClock();
        }
      },
      child: toast,
    );

    return MouseRegion(
      onEnter: (_) {
        _hover = true;
        _updateClock();
      },
      onExit: (_) {
        _hover = false;
        _updateClock();
      },
      child: toast,
    );
  }
}
