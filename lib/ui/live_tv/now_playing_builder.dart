import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../epg/now_playing.dart';

/// Acompanha o programa no ar de um canal enquanto o cartão está na tela. Com
/// [active] falso ou em tela oculta (TickerMode desligado) para de acompanhar.
class NowPlayingBuilder extends StatefulWidget {
  const NowPlayingBuilder({
    super.key,
    required this.source,
    required this.versions,
    required this.account,
    required this.builder,
    this.active = true,
  });

  final bool active;

  final NowPlaying source;
  final List<LiveChannel> versions;
  final SavedAccount? account;
  final Widget Function(BuildContext context, EpgProgram? program) builder;

  @override
  State<NowPlayingBuilder> createState() => _NowPlayingBuilderState();
}

class _NowPlayingBuilderState extends State<NowPlayingBuilder> {
  NowEntry? _entry;
  bool _watching = false;
  bool _visible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(NowPlayingBuilder old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source ||
        old.versions.first.streamId != widget.versions.first.streamId) {
      _stop(old.source);
      _entry = null;
    }
    _sync();
  }

  void _sync() {
    final on = _visible && widget.active;
    if (on && !_watching) {
      _watching = true;
      _entry = widget.source.watch(widget.versions, widget.account)
        ..addListener(_changed);
    } else if (!on) {
      _stop(widget.source);
    }
  }

  void _stop(NowPlaying source) {
    final entry = _entry;
    if (!_watching || entry == null) return;
    _watching = false;
    entry.removeListener(_changed);
    source.release(entry);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stop(widget.source);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _entry?.program);
}
