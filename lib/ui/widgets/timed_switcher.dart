import 'package:flutter/material.dart';

/// Como o [AnimatedSwitcher], mas quem sai usa a mesma duração de quem entra.
/// O [AnimatedSwitcher] fixa a duração de cada filho quando ele aparece; aqui
/// a duração vale para a troca inteira, o que permite uma troca rápida no
/// clique e uma lenta quando é automática.
class TimedSwitcher extends StatefulWidget {
  const TimedSwitcher({
    super.key,
    required this.duration,
    required this.child,
    this.switchInCurve = Curves.linear,
    this.switchOutCurve = Curves.linear,
    this.transitionBuilder = AnimatedSwitcher.defaultTransitionBuilder,
  });

  final Duration duration;
  final Widget child;
  final Curve switchInCurve;
  final Curve switchOutCurve;
  final AnimatedSwitcherTransitionBuilder transitionBuilder;

  @override
  State<TimedSwitcher> createState() => _TimedSwitcherState();
}

class _Entry {
  _Entry(this.serial, this.child, this.controller, this.animation);

  final int serial;
  Widget child;
  final AnimationController controller;
  final CurvedAnimation animation;

  void dispose() {
    animation.dispose();
    controller.dispose();
  }
}

class _TimedSwitcherState extends State<TimedSwitcher>
    with TickerProviderStateMixin {
  final List<_Entry> _leaving = [];
  late _Entry _current;
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    _current = _newEntry()..controller.value = 1;
  }

  _Entry _newEntry() {
    final controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    return _Entry(
      _serial++,
      widget.child,
      controller,
      CurvedAnimation(
        parent: controller,
        curve: widget.switchInCurve,
        reverseCurve: widget.switchOutCurve,
      ),
    );
  }

  @override
  void didUpdateWidget(TimedSwitcher old) {
    super.didUpdateWidget(old);
    if (Widget.canUpdate(widget.child, _current.child)) {
      _current.child = widget.child;
      return;
    }
    final leaving = _current;
    _current = _newEntry();
    if (leaving.controller.value == 0) {
      // Trocou de novo antes de aparecer: não há o que esmaecer.
      WidgetsBinding.instance.addPostFrameCallback((_) => leaving.dispose());
    } else {
      _leaving.add(leaving);
      leaving.controller.reverseDuration = widget.duration;
      leaving.controller.addStatusListener((status) {
        if (status != AnimationStatus.dismissed || !mounted) return;
        if (!_leaving.remove(leaving)) return;
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) => leaving.dispose());
      });
      leaving.controller.reverse();
    }
    _current.controller.forward();
  }

  @override
  void dispose() {
    for (final e in _leaving) {
      e.dispose();
    }
    _current.dispose();
    super.dispose();
  }

  Widget _build(_Entry e) => KeyedSubtree(
    key: ValueKey(e.serial),
    child: widget.transitionBuilder(e.child, e.animation),
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [for (final e in _leaving) _build(e), _build(_current)],
    );
  }
}
