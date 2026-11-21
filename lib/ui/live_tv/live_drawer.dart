import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/channel_groups.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../widgets/carousel_arrows.dart';
import '../widgets/manage_categories_button.dart';
import '../widgets/shimmer.dart';
import '../widgets/split_text.dart';
import '../widgets/spotlight.dart';
import 'channel_group_card.dart';
import 'live_highlight_banner.dart';
import 'live_recent_card.dart';
import 'manage_categories_panel.dart';

// ---- ações de favorito/recente de um grupo ---------------------------------
// Usadas pela gaveta e pela faixa "Recentes e favoritos" sobre o vídeo.

/// Alguma versão do grupo está nos favoritos.
bool groupIsFavorite(AppController c, ChannelGroup g) =>
    g.versions.any((v) => c.isFavorite(v.streamId));

/// Alguma versão do grupo está na lista de recentes.
bool groupIsRecent(AppController c, ChannelGroup g) {
  final recent = c.recentChannels;
  return g.versions.any((v) => recent.contains(v.streamId));
}

/// Tira o grupo da lista de recentes (todas as versões presentes nela).
void removeGroupFromRecents(AppController c, ChannelGroup g) {
  final recent = c.recentChannels;
  for (final v in g.versions) {
    if (recent.contains(v.streamId)) {
      unawaited(c.removeRecentChannel(v.streamId));
    }
  }
}

/// Desfavorita todas as versões favoritas do grupo e avisa com "Desfazer",
/// que favorita de novo as mesmas versões.
void unfavoriteGroupWithUndo(
  BuildContext context,
  AppController c,
  ChannelGroup g,
) {
  final favs = [
    for (final v in g.versions)
      if (c.isFavorite(v.streamId)) v,
  ];
  if (favs.isEmpty) return;
  for (final v in favs) {
    unawaited(c.toggleFavorite(v));
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        persist: false,
        duration: const Duration(seconds: 5),
        content: const Text('Removido dos favoritos'),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () {
            for (final v in favs) {
              if (!c.isFavorite(v.streamId)) unawaited(c.toggleFavorite(v));
            }
          },
        ),
      ),
    );
}

/// Botão Favoritar do cartão de categoria: se o grupo é favorito, desfavorita
/// as versões favoritas; senão favorita a versão que seria tocada.
void toggleGroupFavorite(AppController c, ChannelGroup g) {
  if (groupIsFavorite(c, g)) {
    for (final v in g.versions) {
      if (c.isFavorite(v.streamId)) unawaited(c.toggleFavorite(v));
    }
  } else {
    unawaited(c.toggleFavorite(g.pick(c.preferredVersionFor(g.key))));
  }
}

/// Conteúdo da gaveta de canais da TV ao vivo: cabeçalho (título, atualizar,
/// categorias, fechar) e as fileiras de canais agrupados. O fundo, a altura e
/// a animação da gaveta ficam com a página; aqui o conteúdo preenche o espaço
/// recebido.
///
/// Fileiras, nesta ordem: Recentes e favoritos e uma por categoria. Com
/// [showBanner], o banner de destaques vem antes de tudo.
class LiveDrawer extends StatefulWidget {
  const LiveDrawer({
    super.key,
    required this.onOpen,
    required this.closable,
    this.onClose,
    this.currentStreamId,
    this.showBanner = false,
    this.showTop = false,
    this.onOpenChannel,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  /// Cartão tocado: o grupo e os grupos da fileira onde ele estava (a fila
  /// para "canal anterior/próximo").
  final void Function(ChannelGroup group, List<ChannelGroup> row) onOpen;

  /// Mostra o botão de fechar a gaveta.
  final bool closable;
  final VoidCallback? onClose;

  /// Canal que está tocando; o cartão do grupo dele fica marcado.
  final int? currentStreamId;

  /// Mostra o banner de destaques no topo da lista (some se não houver
  /// destaques ou [onOpenChannel]). Cada vez que passa de false para true, o
  /// banner entra vindo de cima.
  final bool showBanner;

  /// Quando passa de false para true (gaveta no encaixe baixo), a lista rola
  /// até o início para mostrar "Recentes e favoritos".
  final bool showTop;

  /// Canal escolhido no banner, com a lista do destaque como fila.
  final void Function(LiveChannel channel, List<LiveChannel> list)?
  onOpenChannel;

  /// Arrasto vertical da alça e do cabeçalho. A alça só aparece com
  /// [onDragUpdate].
  final GestureDragStartCallback? onDragStart;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;

  /// Altura da área da alça (margem de 8 + barra de 4 + 8).
  static const double handleHeight = 20;

  /// Altura do bloco do cabeçalho: padding 8 + linha de 48 + padding 8.
  static const double headerHeight = 64;

  /// Altura do bloco "Recentes e favoritos": título (32) + fileira com o
  /// cartão (144 + 8 de respiro) + 16 de espaço embaixo.
  static const double recentsHeight =
      _LiveDrawerState._titleHeight +
      LiveRecentCard.height +
      _LiveDrawerState._rowPadding +
      _LiveDrawerState._sectionBottom;

  /// Altura da gaveta no encaixe baixo (a "espiada"): alça + cabeçalho + a
  /// fileira "Recentes e favoritos". 20 + 64 + 200 = 284 px.
  static const double peekHeight = handleHeight + headerHeight + recentsHeight;

  @override
  State<LiveDrawer> createState() => _LiveDrawerState();
}

class _Section {
  const _Section(
    this.title,
    this.groups, {
    this.categoryId,
    this.recents = false,
  });

  final String title;
  final List<ChannelGroup> groups;

  /// Categoria da fileira (null em "Recentes e favoritos").
  final String? categoryId;
  final bool recents;

  double get extent => recents
      ? _LiveDrawerState._recentsExtent
      : _LiveDrawerState._categoryExtent;
}

class _LiveDrawerState extends State<LiveDrawer>
    with SingleTickerProviderStateMixin {
  static const double _pad = 28;
  static const double _gap = 12;
  static const double _titleHeight = 32;
  static const double _rowPadding = 8;
  static const double _sectionBottom = 16;
  static const double _recentsRowHeight = LiveRecentCard.height + _rowPadding;
  static const double _categoryRowHeight =
      ChannelGroupCard.height + _rowPadding;
  static const double _recentsExtent =
      _titleHeight + _recentsRowHeight + _sectionBottom;
  static const double _categoryExtent =
      _titleHeight + _categoryRowHeight + _sectionBottom;
  static const int _maxRecentGroups = 24;

  final ScrollController _scroll = ScrollController();
  final GlobalKey _bannerKey = GlobalKey();
  late final AnimationController _banner = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final Animation<Offset> _bannerSlide = Tween<Offset>(
    begin: const Offset(0, -0.25),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _banner, curve: Curves.easeOutCubic));
  late final Animation<double> _bannerFade = CurvedAnimation(
    parent: _banner,
    curve: Curves.easeOutCubic,
  );

  bool _reduce = false;
  bool _entryPending = false;

  // Cache: só refaz quando algo que entra no cálculo muda (o app notifica por
  // muitos motivos, como o progresso da reprodução).
  List<LiveChannel>? _forVisible;
  List<LiveCategory>? _forCategories;
  Set<int>? _forFavorites;
  List<int>? _forRecent;
  List<_Section> _sections = const [];
  Map<String, int> _sectionOfCategory = const {};

  // O banner existe nesta construção (para calcular o deslocamento até uma
  // categoria).
  bool _bannerShown = false;

  @override
  void initState() {
    super.initState();
    _entryPending = widget.showBanner;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    _runEntry();
  }

  @override
  void didUpdateWidget(LiveDrawer old) {
    super.didUpdateWidget(old);
    if (!old.showTop && widget.showTop) _scrollToTop();
    if (!old.showBanner && widget.showBanner) {
      _entryPending = true;
      _runEntry();
      // O banner fica no topo da lista: volta ao início para ele aparecer.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _scroll.offset <= 0) return;
      if (_reduce) {
        _scroll.jumpTo(0);
      } else {
        unawaited(
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    });
  }

  void _runEntry() {
    if (!_entryPending) return;
    _entryPending = false;
    if (_reduce) {
      _banner.value = 1;
    } else {
      _banner.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _banner.dispose();
    _scroll.dispose();
    super.dispose();
  }

  static String _canais(int n) => n == 1 ? '1 canal' : '$n canais';

  void _refresh(AppController c) {
    if (identical(_forVisible, c.visible) &&
        identical(_forCategories, c.categories) &&
        identical(_forFavorites, c.favoriteChannels) &&
        identical(_forRecent, c.recentChannels)) {
      return;
    }
    _forVisible = c.visible;
    _forCategories = c.categories;
    _forFavorites = c.favoriteChannels;
    _forRecent = c.recentChannels;

    final visible = c.visible;
    final visibleIds = {for (final ch in visible) ch.streamId};
    final groupOf = <int, ChannelGroup>{
      for (final g in groupChannels(visible))
        for (final v in g.versions) v.streamId: g,
    };

    final sections = <_Section>[];
    final ofCategory = <String, int>{};

    // 1) Recentes e favoritos: o grupo inteiro (todas as versões) de cada canal.
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
    if (picked.isNotEmpty) {
      sections.add(
        _Section(
          'Recentes e favoritos',
          picked.length > _maxRecentGroups
              ? picked.sublist(0, _maxRecentGroups)
              : picked,
          recents: true,
        ),
      );
    }

    // 2) Categorias.
    final byCategory = <String, List<LiveChannel>>{};
    for (final ch in visible) {
      (byCategory[ch.categoryId] ??= []).add(ch);
    }
    for (final cat in c.categories) {
      final list = byCategory[cat.id];
      if (list == null || list.isEmpty) continue;
      ofCategory[cat.id] = sections.length;
      sections.add(_Section(cat.name, groupChannels(list), categoryId: cat.id));
    }

    _sections = sections;
    _sectionOfCategory = ofCategory;
  }

  /// Rola a gaveta até o título da fileira da categoria. As fileiras têm
  /// altura conhecida, então o deslocamento é calculado (uma fileira fora da
  /// tela ainda não existe na árvore, o que impede `ensureVisible`); só a
  /// altura do banner é medida.
  void _seeCategory(String categoryId) {
    final index = _sectionOfCategory[categoryId];
    if (index == null || !_scroll.hasClients) return;
    var offset = 0.0;
    if (_bannerShown) {
      offset += _bannerKey.currentContext?.size?.height ?? 0;
    }
    for (var i = 0; i < index; i++) {
      offset += _sections[i].extent;
    }
    final target = offset
        .clamp(0.0, _scroll.position.maxScrollExtent)
        .toDouble();
    if (_reduce) {
      _scroll.jumpTo(target);
    } else {
      unawaited(
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    _refresh(c);
    final summary = c.visible.length == c.totalChannels
        ? _canais(c.totalChannels)
        : '${c.visible.length} de ${c.totalChannels} canais';
    final draggable = widget.onDragUpdate != null;

    final header = Padding(
      // Os botões têm 12 px de respiro interno: o ícone fica na borda das
      // fileiras.
      padding: const EdgeInsets.fromLTRB(_pad, 8, _pad - 12, 8),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            // Esquerda: ocupa o que sobra, para os botões ficarem sempre
            // colados à borda direita (com Flexible/Spacer o espaço livre
            // seria dividido e os botões ficariam no meio).
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'TV AO VIVO',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.title(28, spacing: 1.2),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Atualizar catálogo',
              onPressed: c.syncing ? null : c.refreshCatalog,
              icon: c.syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 20),
            ),
            ManageCategoriesButton(
              hintKey: 'live',
              iconColor: Theme.of(context).iconTheme.color,
              onPressed: () => showManageCategories(context),
            ),
            if (widget.closable)
              IconButton(
                tooltip: 'Fechar (Esc)',
                onPressed: widget.onClose,
                icon: const Icon(Icons.keyboard_arrow_down, size: 24),
              ),
          ],
        ),
      ),
    );

    final top = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (draggable)
          MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: SizedBox(
              height: LiveDrawer.handleHeight,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ExcludeSemantics(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          const SizedBox(height: 12),
        header,
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Alça e faixa do cabeçalho: área de arrasto (os botões ficam por
        // cima e continuam recebendo o clique).
        if (draggable)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: widget.onDragStart,
            onVerticalDragUpdate: widget.onDragUpdate,
            onVerticalDragEnd: widget.onDragEnd,
            child: top,
          )
        else
          top,
        if (c.syncError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(_pad, 0, _pad, 8),
            child: Text(
              c.syncError!,
              style: TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ),
        Expanded(child: _body(c)),
      ],
    );
  }

  Widget _body(AppController c) {
    _bannerShown = false;
    if (c.totalChannels == 0) {
      if (c.syncing) return const _DrawerSkeleton();
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nenhum canal carregado.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: c.refreshCatalog,
              child: const Text('Atualizar catálogo'),
            ),
          ],
        ),
      );
    }

    final highlights = c.highlights;
    final onOpenChannel = widget.onOpenChannel;
    _bannerShown =
        widget.showBanner && onOpenChannel != null && highlights.isNotEmpty;

    if (_sections.isEmpty && !_bannerShown) {
      return Center(
        child: Text(
          'Nenhum canal encontrado.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        if (_bannerShown)
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _bannerFade,
              child: SlideTransition(
                position: _bannerSlide,
                child: LiveHighlightBanner(
                  key: _bannerKey,
                  highlights: highlights,
                  onOpen: onOpenChannel!,
                  onSeeCategory: _seeCategory,
                ),
              ),
            ),
          ),
        SliverVariedExtentList(
          itemExtentBuilder: (i, dimensions) => _sections[i].extent,
          delegate: SliverChildBuilderDelegate((context, i) {
            final s = _sections[i];
            return _SectionRow(
              key: ValueKey('$i:${s.title}'),
              section: s,
              currentStreamId: widget.currentStreamId,
              onOpen: widget.onOpen,
            );
          }, childCount: _sections.length),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

/// Uma seção: título com contador e a fileira horizontal de cartões.
class _SectionRow extends StatefulWidget {
  const _SectionRow({
    super.key,
    required this.section,
    required this.currentStreamId,
    required this.onOpen,
  });

  final _Section section;
  final int? currentStreamId;
  final void Function(ChannelGroup group, List<ChannelGroup> row) onOpen;

  @override
  State<_SectionRow> createState() => _SectionRowState();
}

class _SectionRowState extends State<_SectionRow> {
  final ScrollController _scroll = ScrollController();

  /// Índice do cartão de "Recentes e favoritos" sob o mouse (só nessa seção).
  int? _hover;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final section = widget.section;
    final groups = section.groups;
    final recents = section.recents;
    // Em "Recentes e favoritos" só um cartão fica expandido: o do mouse, senão
    // o do canal tocando, senão o primeiro. Os demais ficam compactos.
    final cardWidth = recents
        ? LiveRecentCard.collapsedWidth
        : ChannelGroupCard.width;
    var open = _hover ?? 0;
    if (recents && _hover == null && widget.currentStreamId != null) {
      final cur = groups.indexWhere((g) => g.contains(widget.currentStreamId!));
      if (cur >= 0) open = cur;
    }
    final rowHeight = recents
        ? _LiveDrawerState._recentsRowHeight
        : _LiveDrawerState._categoryRowHeight;
    final itemWidth = cardWidth + _LiveDrawerState._gap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _LiveDrawerState._titleHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _LiveDrawerState._pad,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: SplitText(
                    text: section.title,
                    revealId: ('titulo-categoria-tv', section.title),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                    delayPerChar: const Duration(milliseconds: 22),
                    charDuration: const Duration(milliseconds: 360),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _LiveDrawerState._canais(groups.length),
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: rowHeight,
          child: LayoutBuilder(
            builder: (context, box) {
              // Sem rolagem quando tudo cabe: as setas somem.
              // Em Recentes, um cartão é mais largo (o expandido).
              final extra = recents
                  ? LiveRecentCard.expandedWidth - LiveRecentCard.collapsedWidth
                  : 0.0;
              final comSetas =
                  groups.length * itemWidth + extra >
                  box.maxWidth - 2 * _LiveDrawerState._pad + _LiveDrawerState._gap;
              final passo = itemWidth * 3;
              final top = (rowHeight - CarouselArrowButton.size) / 2;
              return Stack(
                children: [
                  MouseRegion(
                    onExit: (_) {
                      if (recents && _hover != null) {
                        setState(() => _hover = null);
                      }
                    },
                    child: CarouselDragArea(
                    child: SpotlightGroup(
                    child: ListView.builder(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      // Largura fixa por item, exceto em Recentes (os cartões
                      // mudam de largura ao expandir).
                      itemExtent: recents ? null : itemWidth,
                      padding: const EdgeInsets.symmetric(
                        horizontal: _LiveDrawerState._pad,
                        vertical: 4,
                      ),
                      itemCount: groups.length,
                      itemBuilder: (context, i) {
                        final g = groups[i];
                        final current =
                            widget.currentStreamId != null &&
                            g.contains(widget.currentStreamId!);
                        return Padding(
                          padding: const EdgeInsets.only(
                            right: _LiveDrawerState._gap,
                          ),
                          child: recents
                              ? LiveRecentCard(
                                  key: ValueKey(g.key),
                                  group: g,
                                  current: current,
                                  favorite: groupIsFavorite(c, g),
                                  recent: groupIsRecent(c, g),
                                  expanded: i == open,
                                  onEnter: () {
                                    if (_hover != i) setState(() => _hover = i);
                                  },
                                  onTap: () => widget.onOpen(g, groups),
                                  onToggleFavorite: () =>
                                      unfavoriteGroupWithUndo(context, c, g),
                                  onRemoveRecent: () =>
                                      removeGroupFromRecents(c, g),
                                )
                              : ChannelGroupCard(
                                  key: ValueKey(g.key),
                                  group: g,
                                  current: current,
                                  category: section.title,
                                  favorite: groupIsFavorite(c, g),
                                  onToggleFavorite: () =>
                                      toggleGroupFavorite(c, g),
                                  onTap: () => widget.onOpen(g, groups),
                                ),
                        );
                      },
                    ),
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
                        passo: passo,
                      ),
                    ),
                  if (comSetas)
                    Positioned(
                      right: 4,
                      top: top,
                      child: CarouselArrow(
                        controller: _scroll,
                        left: false,
                        passo: passo,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Esqueleto da gaveta enquanto a lista de canais baixa: três fileiras com o
/// tamanho dos cartões de categoria.
class _DrawerSkeleton extends StatelessWidget {
  const _DrawerSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemExtent: _LiveDrawerState._categoryExtent,
        itemCount: 3,
        itemBuilder: (context, i) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              height: _LiveDrawerState._titleHeight,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _LiveDrawerState._pad,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SkeletonBox(width: 160, height: 16, radius: 4),
                ),
              ),
            ),
            SizedBox(
              height: _LiveDrawerState._categoryRowHeight,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemExtent: ChannelGroupCard.width + _LiveDrawerState._gap,
                padding: const EdgeInsets.symmetric(
                  horizontal: _LiveDrawerState._pad,
                  vertical: 4,
                ),
                itemCount: 8,
                itemBuilder: (context, j) => const Padding(
                  padding: EdgeInsets.only(right: _LiveDrawerState._gap),
                  child: SkeletonBox(
                    width: ChannelGroupCard.width,
                    height: ChannelGroupCard.height,
                    radius: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
