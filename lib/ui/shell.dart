import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_info.dart';
import '../core/theme.dart';
import '../state/app_controller.dart';
import '../state/app_scope.dart';
import 'account_page.dart';
import 'carryover/carryover_page.dart';
import 'catalog/catalog_page.dart';
import 'dashboard_page.dart';
import 'library/library_page.dart';
import 'live_tv/live_tv_page.dart';
import 'favorites/favorites_page.dart';
import 'shell/lazy_pages.dart';
import 'shell/search_overlay.dart';
import 'shell/top_bar.dart';
import 'widgets/animated_counter.dart';
import 'widgets/animated_content.dart';
import 'widgets/app_backdrop.dart';
import 'widgets/content_frame.dart';
import 'widgets/glass.dart';
import 'widgets/split_text.dart';
import 'window/title_bar.dart';
import 'widgets/cubos_logo.dart';

/// Estrutura principal: barra lateral (recolhida ao abrir), topo com busca e
/// perfil, e a página selecionada.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  // 0 Início, 1 TV ao vivo, 2 Catálogo, 3 Minha biblioteca, 4 Conta e ajustes.
  // A página e a barra lateral ficam no AppController (sobrevivem à troca de tema).

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _slideTimer?.cancel();
    _restTimer?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQuery(String value) => setState(() => _query = value);

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  static const double _railWidth = 68;

  /// Altura da barra do topo.
  static const double _topHeight = 64;

  /// Folgas da barra flutuante (recolhida: 6 + 56 + 6 = trilho de 68).
  static const double _barLeft = 6;
  static const double _barGap = 8;

  /// Duração do destaque deslizando até a aba nova (um pouco mais que a
  /// animação, que começa no quadro seguinte ao clique).
  static const Duration _slideTime = Duration(milliseconds: 310);

  /// Depois do deslize a barra espera isto antes de compactar (para quem quer
  /// trocar de aba de novo), a não ser que o mouse saia dela.
  static const Duration _restTime = Duration(seconds: 1);

  Timer? _slideTimer;
  Timer? _restTimer;
  bool _collapsePending = false; // escolheu uma aba e a barra vai compactar
  bool _slideDone = false; // o deslize terminou
  bool _mouseInSidebar = true;

  void _cancelCollapse() {
    _slideTimer?.cancel();
    _restTimer?.cancel();
    _collapsePending = false;
    _slideDone = false;
  }

  void _collapseNow(AppController c) {
    _cancelCollapse();
    if (!c.sidebarCollapsed) c.toggleSidebar();
  }

  /// Abre ou recolhe a barra pelo usuário (logo, setinha, fora da barra).
  void _toggleSidebar(AppController c) {
    _cancelCollapse();
    c.toggleSidebar();
  }

  void _onSidebarHover(AppController c, bool inside) {
    _mouseInSidebar = inside;
    // Saiu da barra depois do deslize: não há o que esperar, compacta já.
    if (!inside && _collapsePending && _slideDone) _collapseNow(c);
  }

  /// Escolha de uma aba na barra lateral. Com a barra expandida: o destaque
  /// desliza da aba anterior até a nova e a tela muda junto. Terminado o
  /// deslize, a barra espera 1 s (para o usuário poder trocar de aba de novo)
  /// e compacta; se o mouse não estiver sobre a barra, compacta na hora.
  void _selectTab(AppController c, int i) {
    if (_query.isNotEmpty) _clearSearch();
    final wasExpanded = !c.sidebarCollapsed;
    c.setShellIndex(i);
    if (!wasExpanded) return;
    _cancelCollapse(); // nova escolha: o relógio recomeça
    _collapsePending = true;
    final reduce = MediaQuery.disableAnimationsOf(context);
    _slideTimer = Timer(reduce ? Duration.zero : _slideTime, () {
      if (!mounted) return;
      _slideDone = true;
      if (!_mouseInSidebar) {
        _collapseNow(c);
      } else {
        _restTimer = Timer(_restTime, () {
          if (mounted) _collapseNow(c);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final index = c.shellIndex;
    final searching = _query.trim().length >= 2;
    final expanded = !c.sidebarCollapsed;
    return Scaffold(
      body: Stack(
        children: [
          // Imagem de fundo de todas as telas principais (os players pintam o
          // próprio fundo preto por cima).
          Positioned.fill(child: AppBackdrop(
              chosen: c.backgroundImage,
              blur: c.backgroundBlur,
              enabled: !c.minimalTheme || c.minimalBackground,
            )),
          // O conteúdo ocupa a janela inteira e cada página se põe ao lado do
          // trilho de 68 px; a barra expandida abre POR CIMA dele. Assim o
          // conteúdo não é recalculado a cada quadro da animação (era uma das
          // causas de engasgo).
          Positioned.fill(
            // Com vídeo tocando na TV ao vivo a barra do topo some e o player
            // ocupa esse espaço.
            child: ValueListenableBuilder<bool>(
              valueListenable: WindowChrome.hidden,
              // "Largura do catálogo": coluna centralizada (ou preenchida).
              builder: (context, hidden, _) => RevealScope(
                child: ContentFrame(
                  recuo: EdgeInsets.only(
                    left: _railWidth,
                    top: hidden ? 0 : _topHeight,
                  ),
                  // O Início usa a janela toda (banner em tela cheia).
                  sangra: index == 0 && !searching,
                  barra: hidden
                      ? null
                      : TitleBar(
                          height: _topHeight,
                          child: TopBarContent(
                            search: _search,
                            focus: _searchFocus,
                            onQuery: _onQuery,
                            onOpenAccount: () {
                              _clearSearch();
                              c.setShellIndex(5);
                            },
                          ),
                        ),
                  child: Stack(
                    children: [
                      // Só a página aberta é construída; as visitadas ficam
                      // vivas por 6 s e depois são descartadas (memória e
                      // animações). Com a busca aberta a página some: os
                      // resultados não têm fundo sólido e a imagem continua
                      // aparecendo.
                      IgnorePointer(
                        ignoring: searching,
                        child: ExcludeFocus(
                          excluding: searching,
                          child: AnimatedOpacity(
                            opacity: searching ? 0 : 1,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            child: LazyPages(
                              index: index,
                              onDrop: () => c.catalog.trimCache(),
                              // Início, TV ao vivo, Filmes e séries, Favoritos
                              // e Minha biblioteca: entrada suave na primeira
                              // abertura.
                              revealFirstOpen: const {0, 1, 2, 3, 4},
                              builders: [
                                (_) => DashboardPage(
                                      onOpenCatalog: c.requestCatalog,
                                      active: c.shellIndex == 0,
                                      covered: searching,
                                    ),
                                (_) => PageFrame(
                                      child: LiveTvPage(
                                        active: c.shellIndex == 1,
                                      ),
                                    ),
                                (_) => PageFrame(
                                      child: CatalogPage(
                                        active: c.shellIndex == 2,
                                      ),
                                    ),
                                (_) => const PageFrame(child: FavoritesPage()),
                                (_) => const PageFrame(child: LibraryPage()),
                                (_) => const PageFrame(child: AccountPage()),
                                (_) => const PageFrame(child: CarryoverPage()),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: PageFrame(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            switchInCurve: Curves.easeOutCubic,
                            child: searching
                                ? SearchOverlay(
                                    key: const ValueKey('search'),
                                    query: _query,
                                    onClose: _clearSearch,
                                  )
                                : const SizedBox.shrink(
                                    key: ValueKey('nosearch'),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Toque fora da barra expandida recolhe.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !expanded,
              child: AnimatedOpacity(
                opacity: expanded ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleSidebar(c),
                  child: const ColoredBox(color: Color(0x55000000)),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              onEnter: (_) => _onSidebarHover(c, true),
              onExit: (_) => _onSidebarHover(c, false),
              // Barra flutuante: solta das bordas da janela.
              child: Padding(
                padding: const EdgeInsets.fromLTRB(_barLeft, _barGap, 0, _barGap),
                child: _Sidebar(
                  index: index,
                  collapsed: c.sidebarCollapsed,
                  carryoverCount: c.carryoverCount,
                  onSelect: (i) => _selectTab(c, i),
                  onToggle: () => _toggleSidebar(c),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Posição das dicas da barra lateral: ao lado do botão, centrada na altura
/// dele (embaixo ela cobriria o item seguinte).
@visibleForTesting
Offset dicaAoLado(TooltipPositionContext c) => Offset(
      c.target.dx + c.targetSize.width / 2 + 8,
      c.target.dy - c.tooltipSize.height / 2,
    );

class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.index,
    required this.collapsed,
    required this.onSelect,
    required this.onToggle,
    required this.carryoverCount,
  });

  final int index;
  final bool collapsed;

  /// Itens em "Dados anteriores"; 0 = a aba temporária não aparece.
  final int carryoverCount;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggle;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  static const Duration _slide = Duration(milliseconds: 280);
  static const double _itemHeight = 42;

  // Destaque único da aba escolhida: um só retângulo que desliza de um item
  // para o outro (em vez de cada item pintar o próprio fundo).
  final GlobalKey _stackKey = GlobalKey();
  final Map<int, GlobalKey> _itemKeys = {};
  double? _top; // posição vertical do destaque, dentro da barra
  bool _sliding = false; // true só enquanto troca de aba (senão acompanha o layout)
  bool _measureQueued = false;

  GlobalKey _keyFor(int i) => _itemKeys.putIfAbsent(i, GlobalKey.new);

  @override
  void didUpdateWidget(_Sidebar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _sliding = !MediaQuery.disableAnimationsOf(context);
    }
  }

  /// Mede onde o item escolhido está (depois do layout) e move o destaque.
  void _queueMeasure() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (!mounted) return;
      final stack = _stackKey.currentContext?.findRenderObject();
      final item = _itemKeys[widget.index]?.currentContext?.findRenderObject();
      double? top;
      if (stack is RenderBox &&
          stack.attached &&
          item is RenderBox &&
          item.attached) {
        top = stack.globalToLocal(item.localToGlobal(Offset.zero)).dy;
      }
      final old = _top;
      final same = (old == null && top == null) ||
          (old != null && top != null && (old - top).abs() < 0.5);
      if (!same) setState(() => _top = top);
    });
  }

  Widget _section(String label, bool collapsed) {
    // Altura fixa nos dois modos: os itens não mudam de lugar quando a barra
    // abre ou fecha, e o destaque acompanha sem pulos.
    return SizedBox(
      height: 40,
      child: collapsed
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Divider(color: AppGlass.line)),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
    );
  }

  /// O retângulo de destaque e a barrinha lateral da aba escolhida.
  Widget _highlight() {
    final top = _top;
    if (top == null) return const SizedBox.shrink();
    return AnimatedPositioned(
      duration: _sliding ? _slide : Duration.zero,
      curve: Curves.easeInOutCubic,
      onEnd: () {
        if (_sliding) setState(() => _sliding = false);
      },
      left: 0,
      right: 0,
      top: top,
      height: _itemHeight,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppGlass.selected,
            borderRadius: AppShape.control,
            border: Border.all(color: AppGlass.selectedEdge),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.index;
    final collapsed = widget.collapsed;
    final carryoverCount = widget.carryoverCount;
    final onSelect = widget.onSelect;
    final onToggle = widget.onToggle;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: collapsed ? 56 : 220,
      child: _GlassPanel(
        open: !collapsed,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      // Decide pelo tamanho real durante a animação: os rótulos só aparecem
      // quando cabem (antes estouravam alguns pixels ao expandir).
      child: LayoutBuilder(builder: (context, box) {
        final compact = collapsed || box.maxWidth < 170;
        _queueMeasure();
        return Stack(
          key: _stackKey,
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            _highlight(),
            Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Faixa de arrastar a janela.
          const DragToMoveArea(child: SizedBox(height: 16)),
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 0 : 4, 4, compact ? 0 : 4, 8),
            child: Row(
              mainAxisAlignment:
                  compact ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                // Clicar no logo expande (ou recolhe) a barra.
                Tooltip(
                  message: collapsed ? 'Expandir menu' : 'Recolher menu',
                  positionDelegate: dicaAoLado,
                  waitDuration: const Duration(milliseconds: 500),
                  child: Semantics(
                    button: true,
                    label: collapsed ? 'Expandir menu' : 'Recolher menu',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onToggle,
                        child: CubosLogo(size: 36),
                      ),
                    ),
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  // Nome por extenso com a barra aberta; as letras sobem uma a
                  // uma toda vez que ela expande (o texto nasce a cada abertura).
                  Expanded(
                    child: SplitText(
                      text: AppInfo.fullName,
                      maxLines: 1,
                      style: AppFonts.title(22, spacing: 0.6),
                      delayPerChar: const Duration(milliseconds: 25),
                      charDuration: const Duration(milliseconds: 380),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _section('MENU', compact),
          _NavItem(
            key: _keyFor(0),
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: 'Início',
            selected: index == 0,
            collapsed: compact,
            onTap: () => onSelect(0),
          ),
          const SizedBox(height: 4),
          _NavItem(
            key: _keyFor(1),
            icon: Icons.live_tv_outlined,
            activeIcon: Icons.live_tv_rounded,
            label: 'TV ao vivo',
            selected: index == 1,
            collapsed: compact,
            onTap: () => onSelect(1),
          ),
          const SizedBox(height: 4),
          _NavItem(
            key: _keyFor(2),
            icon: Icons.local_movies_outlined,
            activeIcon: Icons.local_movies_rounded,
            label: 'Filmes e séries',
            selected: index == 2,
            collapsed: compact,
            onTap: () => onSelect(2),
          ),
          const SizedBox(height: 4),
          _NavItem(
            key: _keyFor(3),
            icon: Icons.favorite_border_rounded,
            activeIcon: Icons.favorite_rounded,
            label: 'Favoritos',
            selected: index == 3,
            collapsed: compact,
            onTap: () => onSelect(3),
          ),
          const SizedBox(height: 4),
          _NavItem(
            key: _keyFor(4),
            icon: Icons.folder_special_outlined,
            activeIcon: Icons.folder_special_rounded,
            label: 'Minha biblioteca',
            selected: index == 4,
            collapsed: compact,
            onTap: () => onSelect(4),
          ),
          _section('GERAL', compact),
          _NavItem(
            key: _keyFor(5),
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings_rounded,
            label: 'Conta e ajustes',
            selected: index == 5,
            collapsed: compact,
            onTap: () => onSelect(5),
          ),
          const Spacer(),
          // Aba temporária: só existe enquanto há dados da conta anterior
          // (troca de Xtream) para revisar.
          if (carryoverCount > 0) ...[
            _section('TEMPORÁRIO', compact),
            _NavItem(
              key: _keyFor(AppController.carryoverPage),
              icon: Icons.history_toggle_off_rounded,
              activeIcon: Icons.history_rounded,
              label: 'Dados anteriores',
              selected: index == AppController.carryoverPage,
              collapsed: compact,
              badge: carryoverCount,
              onTap: () => onSelect(AppController.carryoverPage),
            ),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: collapsed ? Alignment.center : Alignment.centerLeft,
            child: Tooltip(
              message: collapsed ? 'Expandir menu' : 'Recolher menu',
              positionDelegate: dicaAoLado,
              child: IconButton(
                onPressed: onToggle,
                icon: Icon(
                  collapsed ? Icons.chevron_right : Icons.chevron_left,
                  size: 20,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
          ],
        );
      }),
        ),
      ),
    );
  }
}

/// O [GlassSurface] da barra flutuante, que fica mais fechado ao abrir.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.open, required this.child});

  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    // No tema claro, sobre o banner em tela cheia (imagem escura), o vidro
    // fecha mais para os ícones escuros continuarem visíveis.
    return ValueListenableBuilder<bool>(
      valueListenable: WindowChrome.overMedia,
      builder: (context, overMedia, _) => TweenAnimationBuilder<double>(
        tween: Tween(end: overMedia && !AppColors.isDark ? 1 : 0),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, media, _) => TweenAnimationBuilder<double>(
          tween: Tween(end: open ? 1 : 0),
          duration: duration,
          curve: Curves.easeOutCubic,
          child: Material(type: MaterialType.transparency, child: child),
          builder: (context, t, child) => GlassSurface(
            // Só recolhida: aberta, ela cobre a busca e o véu, e precisa de
            // uma cópia própria do fundo.
            group: !open && t == 0 ? GlassGroups.bars : null,
            radius: AppShape.panel,
            shadow: true,
            fill: Color.lerp(
              Color.lerp(
                AppGlass.fill(open: false),
                AppGlass.dialog,
                media,
              ),
              AppGlass.fill(open: true),
              t,
            ),
            blur: ui.lerpDouble(
              AppGlass.blur(open: false),
              AppGlass.blur(open: true),
              t,
            ),
            child: child!,
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  /// Contador na cor de destaque (0 = sem contador).
  final int badge;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // O fundo da aba escolhida é o destaque único da barra, que desliza por
    // baixo dos itens; aqui só o hover das demais.
    // "Sem fundo" é a própria cor do hover com opacidade 0: animar a partir de
    // Colors.transparent (preto) passava por um cinza escuro no meio do caminho.
    final Color background = !widget.selected && _hover
        ? AppGlass.hover
        : AppGlass.hover.withValues(alpha: 0);
    final Color foreground =
        widget.selected ? AppColors.accentInk : AppColors.text;

    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 42,
          // Com contador, a margem direita encolhe para o rótulo caber inteiro.
          padding: widget.collapsed
              ? EdgeInsets.zero
              : EdgeInsets.only(left: 12, right: widget.badge > 0 ? 6 : 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppShape.control,
          ),
          child: Row(
            mainAxisAlignment: widget.collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(
                widget.selected ? widget.activeIcon : widget.icon,
                size: 21,
                color: foreground,
              ),
              if (!widget.collapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          widget.selected ? FontWeight.w700 : FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ),
                if (widget.badge > 0) _Badge(count: widget.badge),
              ],
            ],
          ),
        ),
        // Menu recolhido: o contador fica no canto do ícone.
        if (widget.collapsed && widget.badge > 0)
          Positioned(
            right: 2,
            top: 2,
            child: _Badge(count: widget.badge, small: true),
          ),
      ],
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.collapsed
            ? Tooltip(
                message: widget.label,
                positionDelegate: dicaAoLado,
                child: content,
              )
            : content,
      ),
    );
  }
}

/// Contador na cor de destaque do perfil.
class _Badge extends StatelessWidget {
  const _Badge({required this.count, this.small = false});

  final int count;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: small ? 17 : 20),
      height: small ? 17 : 20,
      padding: EdgeInsets.symmetric(horizontal: small ? 4 : 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: AppShape.control,
        border: small ? Border.all(color: AppColors.sidebar, width: 2) : null,
      ),
      child: AnimatedCounter(
        value: count,
        maxShown: 99,
        style: TextStyle(
          color: AppColors.onAccent,
          fontSize: small ? 9.5 : 10.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
