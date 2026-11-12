import 'dart:async';

import 'package:flutter/material.dart';

/// Várias páginas, mas só constrói a que está aberta (as outras nem existem
/// até serem visitadas). Ao sair de uma página ela fica viva por [keepFor]
/// (voltar logo em seguida é instantâneo) e depois é descartada, liberando
/// memória e animações. A página que entra aparece com fade e leve subida.
class LazyPages extends StatefulWidget {
  const LazyPages({
    super.key,
    required this.index,
    required this.builders,
    this.keepFor = const Duration(seconds: 6),
    this.onDrop,
  });

  final int index;
  final List<WidgetBuilder> builders;
  final Duration keepFor;

  /// Chamado quando alguma página foi descartada (para limpar caches).
  final VoidCallback? onDrop;

  @override
  State<LazyPages> createState() => _LazyPagesState();
}

class _LazyPagesState extends State<LazyPages> {
  final Set<int> _alive = {};
  final Map<int, DateTime> _leftAt = {};
  Timer? _sweeper;

  @override
  void initState() {
    super.initState();
    _alive.add(widget.index);
    _sweeper = Timer.periodic(const Duration(seconds: 1), (_) => _sweep());
  }

  @override
  void didUpdateWidget(LazyPages old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _alive.add(widget.index);
      _leftAt.remove(widget.index);
      _leftAt[old.index] = DateTime.now();
    }
  }

  void _sweep() {
    final now = DateTime.now();
    final drop = [
      for (final e in _leftAt.entries)
        if (e.key != widget.index && now.difference(e.value) >= widget.keepFor)
          e.key,
    ];
    if (drop.isEmpty || !mounted) return;
    setState(() {
      for (final i in drop) {
        _alive.remove(i);
        _leftAt.remove(i);
      }
    });
    widget.onDrop?.call();
  }

  @override
  void dispose() {
    _sweeper?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.builders.length; i++)
          if (_alive.contains(i))
            _Slot(
              key: ValueKey(i),
              active: i == widget.index,
              child: Builder(builder: widget.builders[i]),
            ),
      ],
    );
  }
}

class _Slot extends StatefulWidget {
  const _Slot({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void didUpdateWidget(_Slot old) {
    super.didUpdateWidget(old);
    if (!old.active && widget.active) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: !widget.active,
      child: TickerMode(
        enabled: widget.active,
        child: FadeTransition(
          opacity: _curve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.015),
              end: Offset.zero,
            ).animate(_curve),
            child: RepaintBoundary(child: widget.child),
          ),
        ),
      ),
    );
  }
}
