import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../widgets/animated_content.dart';
import '../widgets/edge_scroll_marks.dart';

/// Várias páginas, mas só constrói a que está aberta (as outras nem existem
/// até serem visitadas). Ao sair de uma página ela fica viva por [keepFor]
/// (voltar logo em seguida é instantâneo) e depois é descartada, liberando
/// memória e animações. A página que entra aparece com fade e leve subida.
///
/// As páginas em [revealFirstOpen] têm uma entrada mais marcada (esmaecimento
/// com subida maior, `AnimatedContent`) só na primeira vez que abrem nesta
/// sessão; depois voltam a usar a transição curta de sempre. Sem desfoque: ele
/// redesenhava a página inteira a cada quadro (quadros de 130 a 290 ms).
///
/// As páginas em [warm] são montadas uma vez, escondidas, logo depois da
/// abertura: pedem as imagens antes do primeiro clique. Com [warmHold] em
/// true elas esperam: montar uma página custa um quadro lento, que apareceria
/// na animação de abertura. Saem depois de
/// [keepFor] (as imagens continuam no cache) ou quando são abertas, quando são
/// montadas de novo, já como página normal.
class LazyPages extends StatefulWidget {
  const LazyPages({
    super.key,
    required this.index,
    required this.builders,
    this.keepFor = const Duration(seconds: 6),
    this.onDrop,
    this.revealFirstOpen = const {},
    this.warm = const {},
    this.warmHold,
  });

  final int index;
  final List<WidgetBuilder> builders;
  final Duration keepFor;

  /// Chamado quando alguma página foi descartada (para limpar caches).
  final VoidCallback? onDrop;

  /// Índices com entrada especial na primeira abertura.
  final Set<int> revealFirstOpen;

  /// Índices pré-carregados na abertura.
  final Set<int> warm;

  /// Enquanto for true, o pré-carregamento não começa.
  final ValueListenable<bool>? warmHold;

  /// Espera antes do pré-carregamento: o primeiro quadro é da página aberta.
  static const warmDelay = Duration(milliseconds: 500);

  @override
  State<LazyPages> createState() => _LazyPagesState();
}

class _LazyPagesState extends State<LazyPages> {
  final Set<int> _alive = {};
  final Map<int, DateTime> _leftAt = {};

  /// Páginas que já fizeram a entrada da primeira abertura.
  final Set<int> _reveladas = {};
  Timer? _sweeper;
  Set<int> _warming = const {};
  Timer? _warmTimer;
  bool _warmed = false;

  @override
  void initState() {
    super.initState();
    _alive.add(widget.index);
    _sweeper = Timer.periodic(const Duration(seconds: 1), (_) => _sweep());
    if (widget.warm.isNotEmpty) {
      widget.warmHold?.addListener(_scheduleWarm);
      _scheduleWarm();
    }
  }

  /// Conta a espera a partir de agora, ou desiste dela se voltou a segurar.
  void _scheduleWarm() {
    if (_warmed) return;
    _warmTimer?.cancel();
    if (widget.warmHold?.value ?? false) return;
    _warmTimer = Timer(LazyPages.warmDelay, _warmUp);
  }

  void _warmUp() {
    _warmed = true;
    setState(() => _warming = widget.warm.difference(_alive));
    _warmTimer = Timer(widget.keepFor, () {
      setState(() => _warming = const {});
    });
  }

  @override
  void didUpdateWidget(LazyPages old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _alive.add(widget.index);
      _leftAt.remove(widget.index);
      _leftAt[old.index] = DateTime.now();
      _warming = _warming.difference({widget.index});
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
    _warmTimer?.cancel();
    widget.warmHold?.removeListener(_scheduleWarm);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.builders.length; i++)
          if (_alive.contains(i))
            _slot(i)
          else if (_warming.contains(i))
            _hidden(i),
      ],
    );
  }

  /// Montada e com layout, mas sem desenho, animação, foco nem avisos.
  Widget _hidden(int i) {
    return Offstage(
      key: ValueKey('warm_$i'),
      child: ExcludeFocus(
        child: TickerMode(
          enabled: false,
          child: NotificationListener<Notification>(
            onNotification: (_) => true,
            child: Builder(builder: widget.builders[i]),
          ),
        ),
      ),
    );
  }

  Widget _slot(int i) {
    final primeira =
        widget.revealFirstOpen.contains(i) && _reveladas.add(i);
    Widget filho = Builder(builder: widget.builders[i]);
    if (widget.revealFirstOpen.contains(i)) {
      // _reveladas fica no estado: a entrada toca uma vez, mesmo se a página
      // for descartada e construída de novo.
      filho = AnimatedContent(
        key: ValueKey('reveal_$i'),
        duration: primeira ? const Duration(milliseconds: 620) : Duration.zero,
        distance: 48,
        child: filho,
      );
    }
    return _Slot(
      key: ValueKey(i),
      active: i == widget.index,
      // Na primeira abertura a entrada própria substitui o fade curto.
      fadeIn: !primeira,
      child: filho,
    );
  }
}

class _Slot extends StatefulWidget {
  const _Slot({
    super.key,
    required this.active,
    required this.child,
    this.fadeIn = true,
  });

  final bool active;
  final bool fadeIn;
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
    if (widget.fadeIn) {
      _c.forward();
    } else {
      _c.value = 1;
    }
    if (widget.active) _anunciarPosicao();
  }

  @override
  void didUpdateWidget(_Slot old) {
    super.didUpdateWidget(old);
    if (!old.active && widget.active) {
      _c.forward(from: 0);
      _anunciarPosicao();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Ao ficar ativa, a página informa a posição da sua rolagem à tela de
  /// conteúdo (faixa de traços). Repete após um instante, para pegar conteúdo
  /// que ainda está carregando. Depois disso, mudanças de extensão chegam por
  /// `ScrollMetricsNotification`.
  void _anunciarPosicao() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) _anunciar();
    });
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted && widget.active) _anunciar();
    });
  }

  /// Procura a primeira rolagem vertical já medida dentro desta página e a
  /// envia para cima. Envia `null` quando não há nenhuma.
  void _anunciar() {
    ScrollPosition? achada;
    void visitar(Element e) {
      if (achada != null) return;
      if (e is StatefulElement) {
        final estado = e.state;
        if (estado is ScrollableState &&
            estado.widget.axis == Axis.vertical &&
            estado.position.hasContentDimensions) {
          achada = estado.position;
          return;
        }
      }
      e.visitChildren(visitar);
    }

    context.visitChildElements(visitar);
    final pos = achada;
    PaginaRolagemNotification(
      pos == null
          ? null
          : PosicaoRolagem(
              pixels: pos.pixels,
              maxScrollExtent: pos.maxScrollExtent,
              viewportDimension: pos.viewportDimension,
            ),
    ).dispatch(context);
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
            child: RepaintBoundary(
              // Página inativa (ainda viva) não deve mexer na faixa de traços
              // da página aberta: as notificações de rolagem são engolidas aqui.
              child: NotificationListener<ScrollNotification>(
                onNotification: (_) => !widget.active,
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: (_) => !widget.active,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
