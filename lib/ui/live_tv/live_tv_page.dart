import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/app_log.dart';
import '../../core/theme.dart';
import '../../data/channel_groups.dart';
import '../../data/models.dart';
import '../../playback/playback_errors.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../widgets/carousel_arrows.dart';
import '../widgets/click_spark.dart';
import '../widgets/edge_scroll_marks.dart';
import 'epg_panel.dart';
import '../window/title_bar.dart';
import 'fullscreen.dart';
import 'live_drawer.dart';
import 'live_recent_card.dart';
import 'playback_overlays.dart';
import 'player_controls.dart';

/// TV ao vivo no formato "cinema": o vídeo ocupa a área da aba, os controles
/// ficam sobre ele e somem sozinhos, e uma gaveta que sobe de baixo traz todos
/// os canais. Ao entrar na aba a gaveta aparece aberta (com os banners de
/// destaque) e nada toca até o usuário escolher um canal; sair da aba encerra
/// a reprodução.
///
/// Com vídeo tocando, a gaveta se arrasta pela alça e tem três encaixes:
/// baixo ([LiveDrawer.peekHeight]), médio (72 %) e tela cheia. Arrastar até o
/// fundo fecha; soltar em tela cheia para o vídeo e volta à página inicial.
class LiveTvPage extends StatefulWidget {
  const LiveTvPage({super.key, required this.active});

  /// true quando esta página está aberta no menu.
  final bool active;

  /// Velocidade (px/s) a partir da qual soltar a gaveta vai para o próximo
  /// encaixe na direção do arrasto.
  static const double flingSpeed = 700;

  /// Escolhe o encaixe ao soltar a gaveta com altura [h] e velocidade
  /// vertical [velocityDy] (positiva = para baixo). [snaps] em ordem
  /// crescente. Devolve null para fechar.
  static double? pickSnap(double h, double velocityDy, List<double> snaps) {
    if (h < snaps.first / 2) return null;
    if (velocityDy.abs() > flingSpeed) {
      if (velocityDy > 0) {
        final lower = snaps.where((s) => s < h - 8);
        return lower.isEmpty ? null : lower.last;
      }
      final upper = snaps.where((s) => s > h + 8);
      return upper.isEmpty ? snaps.last : upper.first;
    }
    return snaps.reduce((a, b) => (a - h).abs() <= (b - h).abs() ? a : b);
  }

  @override
  State<LiveTvPage> createState() => _LiveTvPageState();
}

class _LiveTvPageState extends State<LiveTvPage> {
  static const Duration _hideAfter = Duration(milliseconds: 4500);
  static const double _drawerFraction = 0.72;
  static const double _sidePad = 28;
  /// Altura da camada escura de "Todos os canais"; o botão de tela cheia fica acima dela.
  static const double _fullscreenLift = 76 + 56;
  static const int _maxRecentGroups = 24;

  static const Duration _snapTime = Duration(milliseconds: 250);

  late final AppController _app;
  final FocusNode _focus = FocusNode(debugLabel: 'LiveTvPage');
  final MenuController _versionsMenu = MenuController();
  Timer? _hideTimer;

  // Sessão de reprodução: começa no primeiro canal escolhido e termina ao
  // sair da aba.
  bool _session = false;
  bool _drawerOpen = true;
  bool _guideOpen = false;
  bool _menuOpen = false;
  bool _controlsVisible = true;
  int _playedNonce = -1;

  // Gaveta com vídeo: altura em px do encaixe atual (null = médio, 72 %).
  // Durante o arrasto vale _dragHeight. _snapDuration é a duração da
  // animação depois de soltar (null = a de abrir/fechar).
  double? _drawerHeight;
  double _dragHeight = 0;
  // Altura durante o arrasto: só a gaveta e o escurecimento a escutam, para a
  // página (vídeo, controles) não ser reconstruída a cada movimento.
  final ValueNotifier<double> _dragN = ValueNotifier<double>(0);
  bool _dragging = false;
  Duration? _snapDuration;
  double _area = 0; // altura da área da aba, atualizada no build

  // Avisou "fora do ar em todas as versões" nesta abertura.
  bool _offlineWarned = false;

  // Canal atual (grupo), fila de grupos de onde ele veio e as versões já
  // tentadas pela reserva automática.
  ChannelGroup? _group;
  List<ChannelGroup> _row = const [];
  Set<int> _tried = {};

  // Cache de "Recentes e favoritos": só refaz quando algo do cálculo muda.
  List<LiveChannel>? _forVisible;
  Set<int>? _forFavorites;
  List<int>? _forRecent;
  List<ChannelGroup> _recents = const [];

  @override
  void initState() {
    super.initState();
    _app = AppScope.read(context);
    _app.playback.addListener(_onPlayback);
    if (widget.active) _clearLiveFilters();
  }

  @override
  void didUpdateWidget(LiveTvPage old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active) {
      // Depois do frame: parar a reprodução notifica ouvintes e não pode
      // ocorrer durante a construção.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.active) _endSession();
      });
    } else if (!old.active && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active) _focus.requestFocus();
      });
      _clearLiveFilters();
    }
  }

  /// `visible` é filtrado por categoria ("Ver tudo" da página antiga) e por
  /// texto; esta página mostra todos os canais, então tira esses filtros.
  void _clearLiveFilters() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_app.selectedCategoryId != null) _app.selectCategory(null);
      if (_app.query.isNotEmpty) _app.setQuery('');
    });
  }

  @override
  void dispose() {
    _dragN.dispose();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => WindowChrome.hidden.value = false,
    );
    _hideTimer?.cancel();
    _app.playback.removeListener(_onPlayback);
    _focus.dispose();
    if (_session) {
      final app = _app;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _releasePlayback(app);
        app.setLiveFullBleed(false);
      });
    }
    super.dispose();
  }

  // ---- sessão -----------------------------------------------------------

  static void _releasePlayback(AppController app) {
    unawaited(app.playback.stop());
    app.catalog.endPlayback();
    unawaited(app.downloads.resumeAfterPlayback());
  }

  void _endSession() {
    if (!_session) return;
    _hideTimer?.cancel();
    _releasePlayback(_app);
    _app.setLiveFullBleed(false);
    setState(() {
      _session = false;
      _drawerOpen = true;
      _guideOpen = false;
      _menuOpen = false;
      _controlsVisible = true;
      _tried = {};
      _drawerHeight = null;
      _dragging = false;
      _snapDuration = null;
    });
    // Sem sessão a gaveta ocupa a tela: apaga os traços e deixa a próxima
    // ScrollMetricsNotification da gaveta (mudança de altura) reinformá-los.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) const PaginaRolagemNotification(null).dispatch(context);
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  void _play(LiveChannel ch, {String motivo = ''}) {
    if (!mounted) return;
    AppLog.info('TV', 'Abrindo ${ch.name} (${ch.streamId}) motivo: $motivo');
    final c = _app;
    final url = c.streamUrlFor(ch);
    if (url == null) {
      _snack('Não foi possível montar o endereço do canal.');
      return;
    }
    if (!_session) {
      c.downloads.suspendForPlayback();
      c.catalog.beginPlayback(); // sem trabalho novo em segundo plano
    }
    c.selectChannel(ch);
    _tried.add(ch.streamId);
    _offlineWarned = false;
    _playedNonce = c.playbackNonce;
    unawaited(
      c.playback.play(
        channelId: ch.streamId,
        nonce: c.playbackNonce,
        url: url,
        headers: c.playbackHeaders,
      ),
    );
    unawaited(c.noteRecentChannel(ch));
    final started = !_session;
    c.setLiveFullBleed(true);
    setState(() {
      _session = true;
      _drawerOpen = false;
      _snapDuration = null;
    });
    if (started) {
      // A gaveta deixa de reportar rolagem: apaga os traços já visíveis.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _session) {
          const PaginaRolagemNotification(null).dispatch(context);
        }
      });
    }
    _focus.requestFocus();
    _poke();
  }

  /// Cartão tocado na gaveta (ou na faixa de recentes).
  void _openGroup(ChannelGroup group, List<ChannelGroup> row) {
    _row = row;
    _group = group;
    _tried = {};
    _play(group.pick(_app.preferredVersionFor(group.key)), motivo: 'gaveta');
  }

  /// Pedido vindo de outra tela (Favoritos, busca...): toca exatamente o canal
  /// pedido, sem trocar de versão.
  void _playRequested(LiveChannel ch) {
    if (!mounted) return;
    final c = _app;
    var row = groupChannels(c.liveQueue);
    if (row.isEmpty) {
      row = groupChannels(
        c.visible.where((x) => x.categoryId == ch.categoryId),
      );
    }
    _playInRow(ch, row, 'pedido externo');
  }

  /// Canal escolhido no banner de destaques: a lista do destaque vira a fila.
  void _playFromBanner(LiveChannel ch, List<LiveChannel> list) {
    if (!mounted) return;
    _playInRow(ch, groupChannels(list), 'banner');
  }

  /// Toca exatamente [ch] com [row] como fila (o grupo dele entra no início se
  /// não estiver na fila).
  void _playInRow(LiveChannel ch, List<ChannelGroup> row, String motivo) {
    var i = row.indexWhere((g) => g.contains(ch.streamId));
    if (i < 0) {
      row = [
        groupChannels([ch]).first,
        ...row,
      ];
      i = 0;
    }
    _row = row;
    _group = row[i];
    _tried = {};
    _play(ch, motivo: motivo);
  }

  void _step(int delta) {
    final n = _row.length;
    if (n < 2) return;
    final i = _row.indexWhere((g) => g.key == _group?.key);
    final next = _row[((i < 0 ? 0 : i) + delta + n) % n];
    _group = next;
    _tried = {};
    _play(
      next.pick(_app.preferredVersionFor(next.key)),
      motivo: delta < 0 ? 'anterior' : 'próximo',
    );
  }

  void _chooseVersion(ChannelGroup group, LiveChannel version) {
    unawaited(_app.setPreferredVersion(group.key, version.streamId));
    _tried = {};
    _play(version, motivo: 'versão escolhida');
  }

  /// Reserva: se o canal esgotou as tentativas automáticas, tenta a próxima
  /// versão do grupo.
  void _onPlayback() {
    final c = _app;
    final p = c.playback;
    final sel = c.selected;
    final g = _group;
    if (!mounted || !_session || p.error == null || sel == null || g == null) {
      return;
    }
    if (p.openedChannelId != sel.streamId) return;
    LiveChannel? next;
    for (final v in g.versions) {
      if (!_tried.contains(v.streamId)) {
        next = v;
        break;
      }
    }
    final error = p.error!;
    if (next == null) {
      AppLog.info(
        'TV',
        'Versão ${g.labelOf(sel)} (${sel.streamId}) falhou: ${friendlyPlaybackError(error)}; sem mais versões de ${g.displayName} (esgotou)',
      );
      // O player já troca STREAM_OFFLINE pelo texto amigável; aceita os dois.
      final offline =
          isServerOffline(error) ||
          error == friendlyPlaybackError('STREAM_OFFLINE');
      if (offline && !_offlineWarned) {
        _offlineWarned = true;
        _snack('Canal fora do ar em todas as versões.');
      }
      return;
    }
    AppLog.info(
      'TV',
      'Versão ${g.labelOf(sel)} (${sel.streamId}) falhou: ${friendlyPlaybackError(error)}; tentando ${g.labelOf(next)} (${next.streamId}) de ${g.displayName}',
    );
    _snack('${g.labelOf(sel)} não respondeu. Tentando ${g.labelOf(next)}…');
    _play(next, motivo: 'reserva');
  }

  /// Consome pedidos externos de reprodução e os "tentar de novo" do painel de
  /// erro (que mudam o nonce).
  void _handleExternal(AppController c) {
    if (widget.active && c.takeLiveRequest()) {
      final ch = c.selected;
      AppLog.info(
        'TV',
        'Pedido externo de canal: ${ch?.name} (${ch?.streamId})',
      );
      if (ch != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _playRequested(ch));
      }
      return;
    }
    final sel = c.selected;
    if (_session && sel != null && c.playbackNonce != _playedNonce) {
      AppLog.info(
        'TV',
        'Nonce mudou ($_playedNonce -> ${c.playbackNonce}); repetindo ${sel.name} (${sel.streamId})',
      );
      _playedNonce = c.playbackNonce;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_session) return;
        _tried = {};
        _play(sel, motivo: 'repetir (nonce)');
      });
    }
  }

  // ---- controles --------------------------------------------------------

  void _poke() {
    _hideTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _hideTimer = Timer(_hideAfter, () {
      if (!mounted || _menuOpen || _guideOpen) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _setDrawer(bool open) {
    if (!_session && !open) return;
    if (_drawerOpen == open) {
      // Já aberta (por exemplo no encaixe baixo): ↑ leva ao encaixe médio.
      if (open && _session && _drawerHeight != null) {
        setState(() {
          _drawerHeight = null;
          _snapDuration = _snapTime;
        });
      }
      return;
    }
    setState(() {
      _drawerOpen = open;
      if (open) _drawerHeight = null; // abre no encaixe médio
      _snapDuration = null;
    });
    // A gaveta fechada sai do foco; o teclado volta para a página.
    _focus.requestFocus();
    if (!open) _poke();
  }

  // ---- arrasto da gaveta ------------------------------------------------

  double _mediumHeight(double area) => math.min(
    area,
    math.max(area * _drawerFraction, LiveDrawer.peekHeight + 48),
  );

  /// Encaixes em ordem crescente: baixo, médio e tela cheia.
  List<double> _snaps(double area) => [
    math.min(LiveDrawer.peekHeight, area),
    _mediumHeight(area),
    area,
  ];

  /// Altura atual da gaveta: a da página inicial (tudo), a do arrasto ou a do
  /// encaixe.
  double _currentDrawerHeight(double area) {
    if (!_session) return area;
    if (_dragging) return _dragHeight.clamp(0.0, area).toDouble();
    return math.min(_drawerHeight ?? _mediumHeight(area), area);
  }

  void _onDragStart(DragStartDetails d) {
    if (!_session) return;
    // Calcula antes de marcar _dragging: com ele ligado, _currentDrawerHeight
    // devolveria o _dragHeight antigo.
    final start = _currentDrawerHeight(_area);
    _dragN.value = start;
    setState(() {
      _dragHeight = start;
      _dragging = true;
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    _dragHeight = (_dragHeight - d.delta.dy).clamp(0.0, _area).toDouble();
    _dragN.value = _dragHeight;
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_dragging) return;
    final area = _area;
    final h = _dragHeight;
    final snaps = _snaps(area);
    final v = d.velocity.pixelsPerSecond.dy; // positivo = para baixo

    final target = LiveTvPage.pickSnap(h, v, snaps); // null = fecha

    if (target == null) {
      // Mantém a altura em que foi solto para a gaveta sair por baixo.
      setState(() {
        _dragging = false;
        _drawerHeight = h;
      });
      _setDrawer(false);
      return;
    }
    final full = target >= area - 0.5;
    setState(() {
      _dragging = false;
      _drawerHeight = target;
      _snapDuration = _snapTime;
    });
    if (full) {
      AppLog.info('TV', 'Gaveta em tela cheia: vídeo encerrado');
      _endSession();
    }
  }

  void _toggleGuide() {
    setState(() => _guideOpen = !_guideOpen);
    _poke();
  }

  bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Atalho de teclado: só com a aba aberta, com sessão e sem digitação.
  VoidCallback _key(VoidCallback action, {bool whenTyping = false}) {
    return () {
      if (!widget.active || !_session) return;
      if (!whenTyping && _typing) return;
      action();
    };
  }

  List<ChannelGroup> _recentGroups(AppController c) {
    if (identical(_forVisible, c.visible) &&
        identical(_forFavorites, c.favoriteChannels) &&
        identical(_forRecent, c.recentChannels)) {
      return _recents;
    }
    _forVisible = c.visible;
    _forFavorites = c.favoriteChannels;
    _forRecent = c.recentChannels;

    final visible = c.visible;
    final visibleIds = {for (final ch in visible) ch.streamId};
    final groupOf = <int, ChannelGroup>{
      for (final g in groupChannels(visible))
        for (final v in g.versions) v.streamId: g,
    };
    final picked = <ChannelGroup>[];
    final seen = <String>{};
    void add(LiveChannel ch) {
      final g = groupOf[ch.streamId];
      if (g != null && seen.add(g.key)) picked.add(g);
    }

    for (final id in c.recentChannels) {
      final ch = c.liveChannelById(id);
      if (ch != null && visibleIds.contains(ch.streamId)) add(ch);
    }
    for (final ch in visible) {
      if (c.favoriteChannels.contains(ch.streamId)) add(ch);
    }
    return _recents = picked.length > _maxRecentGroups
        ? picked.sublist(0, _maxRecentGroups)
        : picked;
  }

  // ---- construção -------------------------------------------------------

  /// Com o vídeo tocando a barra de título (busca, perfil, botões da janela)
  /// some e o player ocupa o espaço dela.
  void _syncChrome(bool hidden) {
    if (WindowChrome.hidden.value == hidden) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted && hidden) return;
      WindowChrome.hidden.value = hidden;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    _handleExternal(c);

    final reduce = MediaQuery.disableAnimationsOf(context);
    final slide = reduce ? Duration.zero : const Duration(milliseconds: 380);
    final fade = reduce ? Duration.zero : const Duration(milliseconds: 200);
    final session = _session;
    final controlsOn = session && !_drawerOpen && _controlsVisible;
    _syncChrome(session && widget.active);
    final hideCursor = session && !_drawerOpen && !_controlsVisible;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp): _key(
          () => _setDrawer(true),
        ),
        const SingleActivator(LogicalKeyboardKey.arrowDown): _key(
          () => _setDrawer(false),
        ),
        const SingleActivator(LogicalKeyboardKey.escape): _key(
          () => _setDrawer(false),
          whenTyping: true,
        ),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _key(() {
          if (!_drawerOpen) _step(-1);
        }),
        const SingleActivator(LogicalKeyboardKey.arrowRight): _key(() {
          if (!_drawerOpen) _step(1);
        }),
        const SingleActivator(LogicalKeyboardKey.keyF): _key(
          () => unawaited(enterVideoFullscreen(context, _app.playback)),
        ),
      },
      child: Focus(
        focusNode: _focus,
        autofocus: widget.active,
        child: MouseRegion(
          cursor: hideCursor ? SystemMouseCursors.none : MouseCursor.defer,
          onHover: (_) {
            if (_session) _poke();
          },
          child: ClipRect(
            child: LayoutBuilder(
              builder: (context, box) {
                _area = box.maxHeight;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: session ? Colors.black : AppColors.bg),
                    if (session) ...[
                      Video(
                        controller: c.playback.video,
                        controls: (_) => const SizedBox.shrink(),
                      ),
                      PlaybackOverlays(playback: c.playback),
                      _scrim(fade, box.maxHeight),
                      // Tela cheia: acima da camada escura de "Todos os canais".
                      Positioned.fill(
                        bottom: _fullscreenLift,
                        child: PlayerControls(
                          playback: c.playback,
                          fullscreen: false,
                          visible: controlsOn,
                          part: PlayerControlsPart.fullscreen,
                          onToggleFullscreen: () => unawaited(
                            enterVideoFullscreen(context, c.playback),
                          ),
                        ),
                      ),
                      _topBar(c, fade, controlsOn),
                      _bottomArea(c, fade, controlsOn),
                    ],
                    _drawer(c, box.maxHeight, slide),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Escurece o vídeo com a gaveta aberta (mais escuro quanto mais alta ela
  /// está, até 0,55); clicar nele fecha a gaveta.
  Widget _scrim(Duration fade, double area) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_drawerOpen,
        child: ValueListenableBuilder<double>(
          valueListenable: _dragN,
          builder: (context, _, child) {
            final level = area <= 0
                ? 1.0
                : (_currentDrawerHeight(area) / area)
                      .clamp(0.0, 1.0)
                      .toDouble();
            return AnimatedOpacity(
              opacity: _drawerOpen ? level : 0,
              // Durante o arrasto acompanha o dedo, sem animação.
              duration: _dragging ? Duration.zero : fade,
              child: child,
            );
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _setDrawer(false),
            child: const ColoredBox(color: Color.fromRGBO(0, 0, 0, 0.55)),
          ),
        ),
      ),
    );
  }

  Widget _drawer(AppController c, double area, Duration slide) {
    final session = _session;
    final open = !session || _drawerOpen;
    // No encaixe baixo (já solta) a lista volta ao início para mostrar
    // "Recentes e favoritos".
    final showTop =
        session &&
        _drawerOpen &&
        !_dragging &&
        _drawerHeight != null &&
        _drawerHeight! <= math.min(LiveDrawer.peekHeight, area) + 0.5;
    // Com sessão a gaveta ganha 1 px a mais nas laterais e embaixo: a borda
    // uniforme fica só em cima (o resto é cortado pela área).
    final edge = session ? -1.0 : 0.0;
    final duration = (_dragging || MediaQuery.disableAnimationsOf(context))
        ? Duration.zero
        : (_snapDuration ?? slide);
    final content = RepaintBoundary(
      child: NotificationListener<Notification>(
        // Com vídeo tocando, a rolagem da gaveta não chega ao ContentFrameLayout.
        onNotification: (n) =>
            _session &&
            (n is ScrollNotification || n is ScrollMetricsNotification),
        child: ExcludeFocus(
          excluding: !open,
          child: IgnorePointer(
            ignoring: !open,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: session
                    ? AppColors.bg.withValues(alpha: 0.96)
                    : AppColors.bg,
                borderRadius: session
                    ? const BorderRadius.vertical(top: Radius.circular(14))
                    : null,
                border: session ? Border.all(color: AppColors.border) : null,
              ),
              child: Material(
                type: MaterialType.transparency,
                // Layout de altura fixa: arrastar só desloca a gaveta (sem
                // recalcular as fileiras a cada quadro); o que sobra embaixo é
                // cortado pela área.
                child: LiveDrawer(
                  onOpen: _openGroup,
                  closable: session,
                  onClose: () => _setDrawer(false),
                  currentStreamId: session ? c.selected?.streamId : null,
                  showBanner: !session,
                  showTop: showTop,
                  onOpenChannel: _playFromBanner,
                  // A alça e o arrasto só existem com o vídeo tocando.
                  onDragStart: session ? _onDragStart : null,
                  onDragUpdate: session ? _onDragUpdate : null,
                  onDragEnd: session ? _onDragEnd : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final full = math.max(area, LiveDrawer.peekHeight) + (session ? 1 : 0);
    return ValueListenableBuilder<double>(
      valueListenable: _dragN,
      child: content,
      builder: (context, _, child) {
        final h = _currentDrawerHeight(area);
        return AnimatedPositioned(
          duration: duration,
          curve: Curves.easeOutCubic,
          left: edge,
          right: edge,
          height: full,
          // Aberta: o topo fica a [h] do fundo; fechada: sai por baixo.
          top: open ? area - h : area + 2,
          child: child!,
        );
      },
    );
  }

  Widget _topBar(AppController c, Duration fade, bool on) {
    final g = _group;
    final sel = c.selected;
    final fav = sel != null && c.isFavorite(sel.streamId);
    final multi = g != null && g.versions.length > 1;
    final versionLabel = g != null && sel != null ? g.labelOf(sel) : null;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: on ? 1 : 0,
        duration: fade,
        child: IgnorePointer(
          ignoring: !on,
          child: Container(
            padding: const EdgeInsets.fromLTRB(_sidePad, 44, _sidePad, 48),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.fromRGBO(0, 0, 0, 0.8),
                  Color.fromRGBO(0, 0, 0, 0),
                ],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Encerra o vídeo e volta à página inicial da TV ao vivo.
                _OverlayButton(
                  tooltip: 'Voltar à TV ao vivo',
                  onTap: _endSession,
                  child: const Icon(
                    Icons.arrow_back,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g?.displayName ?? sel?.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.title(
                          26,
                          spacing: 1,
                        ).copyWith(color: Colors.white),
                      ),
                      if (versionLabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Versão $versionLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color.fromRGBO(255, 255, 255, 0.75),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                _OverlayButton(
                  tooltip: fav
                      ? 'Remover dos favoritos'
                      : 'Adicionar aos favoritos',
                  onTap: sel == null
                      ? null
                      : () {
                          if (!fav) ClickSpark.noClique(context, shape: SparkShape.stars);
                          unawaited(c.toggleFavorite(sel));
                        },
                  child: Icon(
                    fav ? Icons.favorite : Icons.favorite_border,
                    size: 20,
                    color: fav ? AppColors.accent : Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                _OverlayButton(
                  tooltip: 'Canal anterior (←)',
                  onTap: () => _step(-1),
                  child: const Icon(
                    Icons.skip_previous,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                _OverlayButton(
                  tooltip: 'Próximo canal (→)',
                  onTap: () => _step(1),
                  child: const Icon(
                    Icons.skip_next,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                _OverlayButton(
                  tooltip: 'Guia de programação',
                  square: false,
                  active: _guideOpen,
                  onTap: _toggleGuide,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.event_note_outlined,
                        size: 18,
                        color: _guideOpen ? AppColors.accent : Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Guia',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _guideOpen ? AppColors.accent : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                if (multi && sel != null) ...[
                  const SizedBox(width: 8),
                  _versionsButton(g, sel),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _versionsButton(ChannelGroup g, LiveChannel sel) {
    return MenuAnchor(
      controller: _versionsMenu,
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: AppColors.border),
          ),
        ),
      ),
      onOpen: () => _menuOpen = true,
      onClose: () {
        _menuOpen = false;
        if (mounted) _poke();
      },
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Text(
            'Versões de ${g.displayName}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ),
        for (final v in g.versions)
          MenuItemButton(
            style: MenuItemButton.styleFrom(foregroundColor: AppColors.text),
            onPressed: () => _chooseVersion(g, v),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  g.labelOf(v),
                  style: TextStyle(
                    fontWeight: v.streamId == sel.streamId
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
                if (v.streamId == sel.streamId) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: AppColors.accent),
                    ),
                    child: Text(
                      'Em uso',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
      builder: (context, controller, _) => _OverlayButton(
        tooltip: 'Versões do canal',
        square: false,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              g.labelOf(sel),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 20, color: Colors.white),
          ],
        ),
      ),
    );
  }

  /// Faixa de baixo: volume e gravação, e abaixo o guia (se aberto) ou "Recentes e
  /// favoritos" com o botão que abre a gaveta. Fica acima da barra com a tela cheia.
  Widget _bottomArea(AppController c, Duration fade, bool on) {
    final Widget content;
    if (_guideOpen) {
      content = Container(
        margin: const EdgeInsets.symmetric(horizontal: _sidePad),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const EpgPanel(),
      );
    } else {
      final recents = _recentGroups(c);
      final current = c.selected?.streamId;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recents.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: _sidePad),
              child: Text(
                'Recentes e favoritos',
                style: TextStyle(
                  fontSize: 12,
                  color: Color.fromRGBO(255, 255, 255, 0.75),
                ),
              ),
            ),
            const SizedBox(height: 6),
            _RecentsRow(
              app: c,
              groups: recents,
              currentStreamId: current,
              onOpen: _openGroup,
            ),
            const SizedBox(height: 8),
          ],
          // Divisor; abaixo dele a tela escurece e o convite abre a gaveta
          // (clique ou arrasto para cima).
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: _sidePad),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Color.fromRGBO(255, 255, 255, 0.3),
            ),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _setDrawer(true),
              onVerticalDragUpdate: (d) {
                if (d.delta.dy < -2) _setDrawer(true);
              },
              child: SizedBox(
                height: 76,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Todos os canais',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'clique para expandir',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color.fromRGBO(255, 255, 255, 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedOpacity(
        opacity: on ? 1 : 0,
        duration: fade,
        child: IgnorePointer(
          ignoring: !on,
          child: Stack(
            children: [
              // O gradiente não recebe cliques; sobra ~56 px embaixo para a
              // barra do PlayerControls.
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.fromRGBO(0, 0, 0, 0),
                          Color.fromRGBO(0, 0, 0, 0.85),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Camada escura semitransparente do divisor até a borda de baixo.
              if (!_guideOpen)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 76 + 56,
                  child: const IgnorePointer(
                    child: ColoredBox(color: Color.fromRGBO(0, 0, 0, 0.35)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 40, bottom: 56),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Volume e gravação ficam acima de "Recentes e favoritos".
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _sidePad - 12,
                      ),
                      child: PlayerControls(
                        playback: c.playback,
                        fullscreen: false,
                        part: PlayerControlsPart.audioRec,
                        onToggleFullscreen: () {},
                      ),
                    ),
                    const SizedBox(height: 6),
                    content,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botão quadrado (ou retangular, com [square] falso) sobre o vídeo: fundo
/// preto translúcido e borda branca fina. [active] troca a borda para o
/// destaque.
class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.square = true,
    this.active = false,
  });

  final String tooltip;
  final VoidCallback? onTap;
  final Widget child;
  final bool square;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color.fromRGBO(0, 0, 0, 0.45),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: active
                ? AppColors.accent
                : const Color.fromRGBO(255, 255, 255, 0.2),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: square ? 40 : null,
            height: 40,
            child: square
                ? Center(child: child)
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(widthFactor: 1, child: child),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Fileira horizontal de cartões da faixa "Recentes e favoritos", com o mesmo
/// arraste e as mesmas setas das fileiras da gaveta.
class _RecentsRow extends StatefulWidget {
  const _RecentsRow({
    required this.app,
    required this.groups,
    required this.currentStreamId,
    required this.onOpen,
  });

  final AppController app;
  final List<ChannelGroup> groups;
  final int? currentStreamId;
  final void Function(ChannelGroup group, List<ChannelGroup> row) onOpen;

  @override
  State<_RecentsRow> createState() => _RecentsRowState();
}

class _RecentsRowState extends State<_RecentsRow> {
  static const double _gap = 12;
  static const double _height = LiveRecentCard.height + 8;

  final ScrollController _scroll = ScrollController();

  /// Índice do cartão sob o mouse; sem mouse, abre o do canal tocando (ou o
  /// primeiro).
  int? _hover;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups;
    final app = widget.app;
    const itemWidth = LiveRecentCard.collapsedWidth + _gap;
    // Um cartão (o expandido) é mais largo que os compactos.
    const extra = LiveRecentCard.expandedWidth - LiveRecentCard.collapsedWidth;
    var open = _hover ?? 0;
    if (_hover == null && widget.currentStreamId != null) {
      final cur = groups.indexWhere((g) => g.contains(widget.currentStreamId!));
      if (cur >= 0) open = cur;
    }
    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, box) {
          final comSetas =
              groups.length * itemWidth + extra >
              box.maxWidth - 2 * _LiveTvPageState._sidePad + _gap;
          const top = (_height - CarouselArrowButton.size) / 2;
          return Stack(
            children: [
              MouseRegion(
                onExit: (_) {
                  if (_hover != null) setState(() => _hover = null);
                },
                child: CarouselDragArea(
                  child: ListView.builder(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: _LiveTvPageState._sidePad,
                      vertical: 4,
                    ),
                    itemCount: groups.length,
                    itemBuilder: (context, i) {
                      final g = groups[i];
                      return Padding(
                        padding: const EdgeInsets.only(right: _gap),
                        child: LiveRecentCard(
                          key: ValueKey(g.key),
                          group: g,
                          current:
                              widget.currentStreamId != null &&
                              g.contains(widget.currentStreamId!),
                          favorite: groupIsFavorite(app, g),
                          recent: groupIsRecent(app, g),
                          expanded: i == open,
                          onEnter: () {
                            if (_hover != i) setState(() => _hover = i);
                          },
                          onTap: () => widget.onOpen(g, groups),
                          onToggleFavorite: () =>
                              unfavoriteGroupWithUndo(context, app, g),
                          onRemoveRecent: () => removeGroupFromRecents(app, g),
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (comSetas)
                Positioned(
                  left: 4,
                  top: top,
                  child: CarouselArrow(
                    controller: _scroll,
                    left: true,
                    passo: itemWidth * 3,
                  ),
                ),
              if (comSetas)
                Positioned(
                  right: 4,
                  top: top,
                  child: CarouselArrow(
                    controller: _scroll,
                    left: false,
                    passo: itemWidth * 3,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
