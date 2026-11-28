import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/channel_groups.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../widgets/carousel_arrows.dart';
import '../widgets/manage_categories_button.dart';
import '../widgets/shimmer.dart';
import '../widgets/smooth_scroll.dart';
import '../widgets/split_text.dart';
import '../widgets/spotlight.dart';
import 'channel_group_card.dart';
import 'live_highlight_banner.dart';
import 'live_recent_card.dart';
import 'category_section.dart';
import 'manage_categories_panel.dart';
import 'now_playing_builder.dart';
import '../../core/format.dart';

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
/// Fileiras, nesta ordem: Recentes e favoritos, as categorias favoritas e as
/// outras. Cada categoria é um título que abre e fecha a fileira dela; fechada,
/// dá para segurar e arrastar dentro do bloco dela (favoritas ou outras). Com
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
    this.watchPrograms = true,
    this.onOpenChannel,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  /// Os cartões acompanham o programa no ar (falso com a gaveta fechada).
  final bool watchPrograms;

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
    this.favorite = false,
    this.recents = false,
  });

  final String title;
  final List<ChannelGroup> groups;

  /// Categoria da fileira (null em "Recentes e favoritos").
  final String? categoryId;

  /// Categoria favorita (o bloco de cima).
  final bool favorite;
  final bool recents;

  String get key => recents ? 'recents' : 'cat:$categoryId';

  /// Altura na lista, com a animação de abrir e fechar já terminada.
  double extentWhen(bool open) {
    if (recents) return _LiveDrawerState._recentsExtent;
    return open ? _LiveDrawerState._openExtent : _LiveDrawerState._closedExtent;
  }
}

/// As fileiras têm alturas conhecidas e bem diferentes (fechada e aberta):
/// sem isto a lista estimaria o próprio fim pela média das visíveis, e a roda
/// do mouse (que para no fim) travaria antes dele.
class _SectionsDelegate extends SliverChildBuilderDelegate {
  _SectionsDelegate(
    super.builder, {
    required this.extents,
    super.findChildIndexCallback,
  }) : super(childCount: extents.length);

  final List<double> extents;

  @override
  double? estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => extents
      .skip(lastIndex + 1)
      .fold<double>(trailingScrollOffset, (total, extent) => total + extent);
}

/// Uma categoria sendo arrastada. As medidas são as do começo do arraste.
class _Drag {
  _Drag({
    required this.id,
    required this.title,
    required this.count,
    required this.block,
    required this.extents,
    required this.from,
    required this.rect,
    required this.globalRect,
    required this.startScroll,
    required this.sections,
  }) : to = from;

  final String id;
  final String title;
  final String count;

  /// Ids do bloco, na ordem da tela, e a altura de cada um.
  final List<String> block;
  final List<double> extents;
  final int from;
  int to;

  /// O título no começo: relativo à lista e na tela.
  final Rect rect;
  final Rect globalRect;
  final double startScroll;

  /// As fileiras do começo: se mudarem, o arraste é cancelado.
  final List<_Section> sections;

  /// Quanto o mouse andou, nas medidas da lista e nas da tela.
  Offset offset = Offset.zero;
  Offset globalOffset = Offset.zero;
}

class _LiveDrawerState extends State<LiveDrawer>
    with SingleTickerProviderStateMixin {
  static const double _pad = 28;
  static const double _gap = 12;
  static const double _titleHeight = 32;
  static const double _rowPadding = 8;
  static const double _sectionBottom = 16;
  static const double _bottomSpace = 32;
  static const double _recentsRowHeight = LiveRecentCard.height + _rowPadding;
  static const double _categoryRowHeight =
      ChannelGroupCard.height + _rowPadding;
  static const double _recentsExtent =
      _titleHeight + _recentsRowHeight + _sectionBottom;
  static const double _closedExtent = CategoryHeader.height + 4;
  static const double _openExtent =
      CategoryHeader.height + _categoryRowHeight + _sectionBottom;
  static const double _skeletonExtent =
      _titleHeight + _categoryRowHeight + _sectionBottom;
  static const int _maxRecentGroups = 24;

  final ScrollController _scroll = SmoothScrollController();
  final GlobalKey _bannerKey = GlobalKey();

  /// Descida do banner quando ele reaparece. Na montagem ele já nasce no lugar:
  /// a página está entrando, e esmaecer o banner dentro dela custava quadros
  /// lentos.
  late final AnimationController _banner = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
  );
  late final Animation<Offset> _bannerSlide = Tween<Offset>(
    begin: const Offset(0, -0.25),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _banner, curve: Curves.easeOutCubic));
  late final Animation<double> _bannerFade = CurvedAnimation(
    parent: _banner,
    curve: Curves.easeOutCubic,
  );

  final TextEditingController _search = TextEditingController();
  String _query = '';

  bool _reduce = false;

  // Cache: só refaz quando algo que entra no cálculo muda (o app notifica por
  // muitos motivos, como o progresso da reprodução).
  List<LiveChannel>? _forVisible;
  List<LiveCategory>? _forCategories;
  Set<int>? _forFavorites;
  List<int>? _forRecent;
  Set<String>? _forFavoriteCategories;
  List<String>? _forOrder;
  List<_Section> _sections = const [];

  _Drag? _drag;

  /// Quanto a peça arrastada desceu. Separado do resto: mover o mouse redesenha
  /// só ela; a lista só é refeita quando o destino muda.
  final ValueNotifier<double> _dragDy = ValueNotifier(0);

  /// Posição de destino no bloco. Quando muda, só o deslocamento das fileiras é
  /// refeito, não a lista nem os cartões.
  final ValueNotifier<int> _dragTo = ValueNotifier(0);
  EdgeDraggingAutoScroller? _autoScroller;
  final GlobalKey _listKey = GlobalKey();

  // O banner existe nesta construção (para calcular o deslocamento até uma
  // categoria).
  bool _bannerShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(LiveDrawer old) {
    super.didUpdateWidget(old);
    if (!old.showTop && widget.showTop) _scrollToTop();
    if (!old.showBanner && widget.showBanner) {
      _enterBanner();
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

  void _enterBanner() {
    if (_reduce) {
      _banner.value = 1;
    } else {
      _banner.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _autoScroller?.stopAutoScroll();
    _dragDy.dispose();
    _dragTo.dispose();
    _banner.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  static String _canais(int n) => plural(n, 'canal', 'canais');

  void _refresh(AppController c) {
    if (identical(_forVisible, c.visible) &&
        identical(_forCategories, c.categories) &&
        identical(_forFavorites, c.favoriteChannels) &&
        identical(_forRecent, c.recentChannels) &&
        identical(_forFavoriteCategories, c.favoriteCategories) &&
        identical(_forOrder, c.categoryOrder)) {
      return;
    }
    _forVisible = c.visible;
    _forCategories = c.categories;
    _forFavorites = c.favoriteChannels;
    _forRecent = c.recentChannels;
    _forFavoriteCategories = c.favoriteCategories;
    _forOrder = c.categoryOrder;

    final visible = c.visible;
    final visibleIds = {for (final ch in visible) ch.streamId};
    final groupOf = <int, ChannelGroup>{
      for (final g in groupChannels(visible))
        for (final v in g.versions) v.streamId: g,
    };

    final sections = <_Section>[];

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
    for (final cat in c.drawerCategories) {
      final list = byCategory[cat.id];
      if (list == null || list.isEmpty) continue;
      sections.add(
        _Section(
          cat.name,
          groupChannels(list),
          categoryId: cat.id,
          favorite: c.favoriteCategories.contains(cat.id),
        ),
      );
    }

    _sections = sections;
  }

  bool get _searching => widget.closable && foldText(_query.trim()).isNotEmpty;

  /// Durante a busca todas as categorias com resultado ficam abertas.
  bool _isOpen(AppController c, _Section s) =>
      s.recents || _searching || c.isCategoryOpen(s.categoryId!);

  void _toggle(AppController c, String id) {
    setState(() => c.setCategoryOpen(id, !c.isCategoryOpen(id)));
  }

  /// Abre a categoria e rola a gaveta até o título dela. As fileiras têm
  /// altura conhecida, então o deslocamento é calculado (uma fileira fora da
  /// tela ainda não existe na árvore, o que impede `ensureVisible`); só a
  /// altura do banner é medida.
  void _seeCategory(String categoryId) {
    final c = AppScope.read(context);
    final sections = _visibleSections;
    final index = sections.indexWhere((s) => s.categoryId == categoryId);
    if (index < 0 || !_scroll.hasClients) return;
    setState(() => c.setCategoryOpen(categoryId, true));
    var offset = 0.0;
    if (_bannerShown) {
      offset += _bannerKey.currentContext?.size?.height ?? 0;
    }
    var total = offset + _bottomSpace;
    for (var i = 0; i < sections.length; i++) {
      final extent = sections[i].extentWhen(_isOpen(c, sections[i]));
      if (i < index) offset += extent;
      total += extent;
    }
    // O fim da lista vem das alturas: a rolagem só o estima, e a categoria
    // ainda está abrindo.
    final end = math.max(0.0, total - _scroll.position.viewportDimension);
    final target = math.min(offset, end);
    if (_reduce) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(target);
      });
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

  // ---- arrastar categorias ------------------------------------------------

  void _startDrag(AppController c, _Section section, BuildContext header) {
    final box = header.findRenderObject() as RenderBox?;
    final list = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || list == null || !_scroll.hasClients) return;
    final block = [
      for (final s in _sections)
        if (!s.recents && s.favorite == section.favorite) s,
    ];
    final from = block.indexWhere((s) => s.categoryId == section.categoryId);
    if (from < 0) return;
    _autoScroller = EdgeDraggingAutoScroller(
      Scrollable.of(header),
      velocityScalar: 20,
      onScrollViewScrolled: _autoScroll,
    );
    _scroll.addListener(_updateDragTarget);
    _dragDy.value = 0;
    _dragTo.value = from;
    setState(() {
      _drag = _Drag(
        id: section.categoryId!,
        title: section.title,
        count: _canais(section.groups.length),
        block: [for (final s in block) s.categoryId!],
        extents: [for (final s in block) s.extentWhen(_isOpen(c, s))],
        from: from,
        rect: box.localToGlobal(Offset.zero, ancestor: list) & box.size,
        globalRect: MatrixUtils.transformRect(
          box.getTransformTo(null),
          Offset.zero & box.size,
        ),
        startScroll: _scroll.offset,
        sections: _sections,
      );
    });
  }

  void _moveDrag(LongPressMoveUpdateDetails details) {
    final drag = _drag;
    if (drag == null) return;
    drag.offset = details.localOffsetFromOrigin;
    drag.globalOffset = details.offsetFromOrigin;
    _dragDy.value = drag.offset.dy;
    _updateDragTarget();
    _autoScroll();
  }

  /// Perto da borda de cima ou de baixo, a lista rola sozinha. É chamado de
  /// novo a cada passo: o Flutter guarda o alvo em relação ao começo da lista.
  void _autoScroll() {
    final drag = _drag;
    if (drag == null) return;
    // Com 1 ponto de largura: o Flutter confere o tamanho aplicando de novo a
    // escala da interface, e o título inteiro "não caberia". Só a altura conta.
    final target = drag.globalRect.shift(drag.globalOffset);
    _autoScroller?.startAutoScrollIfNecessary(
      Rect.fromLTWH(target.left, target.top, 1, target.height),
    );
  }

  /// Também é chamado quando a lista rola com o mouse parado.
  void _updateDragTarget() {
    final drag = _drag;
    if (drag == null || !_scroll.hasClients) return;
    final to = dragTargetIndex(
      drag.extents,
      drag.from,
      drag.offset.dy + _scroll.offset - drag.startScroll,
    );
    if (to == drag.to) return;
    drag.to = to;
    _dragTo.value = to;
  }

  void _endDrag(bool drop) {
    final drag = _drag;
    if (drag == null) return;
    setState(_stopDrag);
    if (drop && drag.to != drag.from) {
      unawaited(
        AppScope.read(context).moveCategory(drag.id, drag.block[drag.to]),
      );
    }
  }

  void _stopDrag() {
    _drag = null;
    _autoScroller?.stopAutoScroll();
    _autoScroller = null;
    _scroll.removeListener(_updateDragTarget);
  }

  /// Quanto a fileira sai do lugar para abrir espaço à arrastada.
  double _shiftOf(_Section s) {
    final drag = _drag;
    if (drag == null || s.recents) return 0;
    final i = drag.block.indexOf(s.categoryId!);
    if (i < 0) return 0;
    return dragShift(i, drag.from, drag.to, drag.extents[drag.from]);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    _refresh(c);
    final summary = c.visible.length == c.totalChannels
        ? _canais(c.totalChannels)
        : '${formatCount(c.visible.length)} de ${_canais(c.totalChannels)}';
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
            // Com o vídeo tocando a barra de cima some: a busca vem para cá.
            if (widget.closable) ...[
              SizedBox(width: 280, child: _searchField()),
              const SizedBox(width: 8),
            ],
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
                        borderRadius: AppShape.control,
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

  Widget _searchField() {
    return TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Buscar canais…',
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
        isDense: true,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textMuted),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpar',
                icon: Icon(Icons.close, size: 16, color: AppColors.textMuted),
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
        border: OutlineInputBorder(
          borderRadius: AppShape.control,
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppShape.control,
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppShape.control,
          borderSide: BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }

  /// Seções com a busca aplicada (só na gaveta aberta sobre o vídeo).
  List<_Section> get _visibleSections {
    final f = foldText(_query.trim());
    if (!_searching) return _sections;
    final out = <_Section>[];
    for (final s in _sections) {
      final g = [
        for (final x in s.groups)
          if (foldText(x.displayName).contains(f)) x,
      ];
      if (g.isNotEmpty) {
        out.add(
          _Section(
            s.title,
            g,
            categoryId: s.categoryId,
            favorite: s.favorite,
            recents: s.recents,
          ),
        );
      }
    }
    return out;
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

    final sections = _visibleSections;
    if (sections.isEmpty && !_bannerShown) {
      return Center(
        child: Text(
          'Nenhum canal encontrado.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }
    // A lista mudou no meio do arraste (canais atualizados): solta sem mover.
    if (_drag != null && !identical(_drag!.sections, _sections)) _stopDrag();
    final list = CustomScrollView(
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
        SliverList(
          delegate: _SectionsDelegate(
            (context, i) => _item(c, sections[i]),
            extents: [for (final s in sections) s.extentWhen(_isOpen(c, s))],
            // Reordenar não recria as fileiras (nem a rolagem lateral delas).
            findChildIndexCallback: (key) {
              final value = (key as ValueKey<String>).value;
              final i = sections.indexWhere((s) => s.key == value);
              return i < 0 ? null : i;
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: _bottomSpace)),
      ],
    );
    final drag = _drag;
    return LayoutBuilder(
      builder: (context, box) => Stack(
        key: _listKey,
        fit: StackFit.expand,
        children: [
          list,
          if (drag != null)
            ValueListenableBuilder<double>(
              valueListenable: _dragDy,
              // Camada própria: andar não redesenha a sombra da peça.
              child: RepaintBoundary(
                child: CategoryDragGhost(title: drag.title, count: drag.count),
              ),
              builder: (context, dy, ghost) => Positioned(
                left: drag.rect.left,
                width: drag.rect.width,
                height: drag.rect.height,
                top: (drag.rect.top + dy)
                    .clamp(0.0, math.max(0.0, box.maxHeight - drag.rect.height))
                    .toDouble(),
                child: ghost!,
              ),
            ),
        ],
      ),
    );
  }

  Widget _item(AppController c, _Section s) {
    final open = _isOpen(c, s);
    final draggable = !s.recents && !open && !_searching;
    return ValueListenableBuilder<int>(
      key: ValueKey(s.key),
      valueListenable: _dragTo,
      builder: (context, _, row) => TweenAnimationBuilder<double>(
        tween: Tween(end: _shiftOf(s)),
        // Ao soltar a lista já vem na ordem nova: sem voltar deslizando.
        duration: _drag == null || _reduce
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        builder: (context, dy, child) =>
            Transform.translate(offset: Offset(0, dy), child: child),
        child: row,
      ),
      // Camada própria: a fileira que desliza muda de lugar sem redesenhar os
      // cartões.
      child: RepaintBoundary(
        child: _SectionRow(
          section: s,
          open: open,
          dragged: !s.recents && _drag != null && _drag!.id == s.categoryId,
          currentStreamId: widget.currentStreamId,
          watchPrograms: widget.watchPrograms,
          onOpen: widget.onOpen,
          onToggle: s.recents || _searching
              ? null
              : () => _toggle(c, s.categoryId!),
          onToggleFavorite: s.recents
              ? null
              : () => unawaited(c.toggleFavoriteCategory(s.categoryId!)),
          onDragStart: draggable ? (header) => _startDrag(c, s, header) : null,
          onDragUpdate: _moveDrag,
          onDragEnd: _endDrag,
        ),
      ),
    );
  }
}

/// Uma seção: título com contador e a fileira horizontal de cartões.
class _SectionRow extends StatefulWidget {
  const _SectionRow({
    required this.section,
    required this.open,
    required this.dragged,
    required this.currentStreamId,
    required this.watchPrograms,
    required this.onOpen,
    required this.onToggle,
    required this.onToggleFavorite,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final _Section section;
  final bool open;

  /// Sendo arrastada: o lugar dela fica vazio.
  final bool dragged;
  final VoidCallback? onToggle;
  final VoidCallback? onToggleFavorite;
  final void Function(BuildContext header)? onDragStart;
  final GestureLongPressMoveUpdateCallback onDragUpdate;
  final void Function(bool drop) onDragEnd;
  final int? currentStreamId;
  final bool watchPrograms;
  final void Function(ChannelGroup group, List<ChannelGroup> row) onOpen;

  @override
  State<_SectionRow> createState() => _SectionRowState();
}

class _SectionRowState extends State<_SectionRow>
    with AutomaticKeepAliveClientMixin {
  /// A categoria arrastada não pode sair da árvore enquanto a lista rola: o
  /// gesto é dela.
  @override
  bool get wantKeepAlive => widget.dragged;

  @override
  void didUpdateWidget(_SectionRow old) {
    super.didUpdateWidget(old);
    if (old.dragged != widget.dragged) updateKeepAlive();
  }

  final ScrollController _scroll = ScrollController();

  /// As duas setas da fileira dividem uma cópia do fundo: não se sobrepõem e
  /// nada é desenhado entre uma e outra. Entre fileiras isso não vale (os
  /// cartões da de baixo vêm depois das setas da de cima).
  final BackdropKey _arrowGlass = BackdropKey();

  /// Índice do cartão de "Recentes e favoritos" sob o mouse (só nessa seção).
  int? _hover;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final section = widget.section;
    if (section.recents) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _recentsTitle(),
          _row(context),
          const SizedBox(height: _LiveDrawerState._sectionBottom),
        ],
      );
    }
    return Visibility(
      visible: !widget.dragged,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            // A seta do título fica na borda dos cartões.
            padding: const EdgeInsets.symmetric(
              horizontal: _LiveDrawerState._pad - 4,
            ),
            child: Builder(
              builder: (header) => CategoryHeader(
                title: section.title,
                count: _LiveDrawerState._canais(section.groups.length),
                open: widget.open,
                favorite: section.favorite,
                onToggle: widget.onToggle,
                onToggleFavorite: widget.onToggleFavorite!,
                onDragStart: widget.onDragStart == null
                    ? null
                    : (_) => widget.onDragStart!(header),
                onDragUpdate: widget.onDragUpdate,
                onDragEnd: widget.onDragEnd,
              ),
            ),
          ),
          CategoryReveal(
            open: widget.open,
            builder: (context) => Padding(
              padding: const EdgeInsets.only(
                bottom: _LiveDrawerState._sectionBottom,
              ),
              child: _row(context),
            ),
          ),
          if (!widget.open) const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _recentsTitle() {
    final section = widget.section;
    return SizedBox(
      height: _LiveDrawerState._titleHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _LiveDrawerState._pad),
        child: Row(
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
              _LiveDrawerState._canais(section.groups.length),
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  /// A fileira horizontal de cartões, com as setas.
  Widget _row(BuildContext context) {
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
    return SizedBox(
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
                                    if (_hover != i) {
                                      setState(() => _hover = i);
                                    }
                                  },
                                  onTap: () => widget.onOpen(g, groups),
                                  onToggleFavorite: () =>
                                      unfavoriteGroupWithUndo(context, c, g),
                                  onRemoveRecent: () =>
                                      removeGroupFromRecents(c, g),
                                )
                              : NowPlayingBuilder(
                                  key: ValueKey(g.key),
                                  source: c.epg.nowPlaying,
                                  versions: g.versions,
                                  account: c.account,
                                  active: widget.watchPrograms,
                                  builder: (context, program) =>
                                      ChannelGroupCard(
                                        group: g,
                                        current: current,
                                        program: program,
                                        favorite: groupIsFavorite(c, g),
                                        onToggleFavorite: () =>
                                            toggleGroupFavorite(c, g),
                                        onTap: () => widget.onOpen(g, groups),
                                      ),
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
                    group: _arrowGlass,
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
                    group: _arrowGlass,
                  ),
                ),
            ],
          );
        },
      ),
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
        itemExtent: _LiveDrawerState._skeletonExtent,
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
                  child: SkeletonBox(width: 160, height: 16),
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
