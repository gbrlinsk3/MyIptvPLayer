import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_info.dart';
import '../core/theme.dart';
import '../state/app_scope.dart';
import 'account_page.dart';
import 'catalog/catalog_page.dart';
import 'dashboard_page.dart';
import 'library/library_page.dart';
import 'live_tv/live_tv_page.dart';
import 'favorites/favorites_page.dart';
import 'shell/lazy_pages.dart';
import 'shell/search_overlay.dart';
import 'shell/top_bar.dart';
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

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final index = c.shellIndex;
    final searching = _query.trim().length >= 2;
    final expanded = !c.sidebarCollapsed;
    return Scaffold(
      body: Stack(
        children: [
          // O conteúdo fica sempre ao lado do trilho de 68 px; a barra expandida
          // abre POR CIMA dele. Assim o conteúdo não é recalculado a cada quadro
          // da animação (era uma das causas de engasgo).
          Positioned.fill(
            left: _railWidth,
            child: Column(
              children: [
                TitleBar(
                  height: 64,
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
                Expanded(
                  child: Stack(
                    children: [
                      // Só a página aberta é construída; as visitadas ficam vivas
                      // por 6 s e depois são descartadas (memória e animações).
                      LazyPages(
                        index: index,
                        onDrop: () => c.catalog.trimCache(),
                        builders: [
                          (_) => DashboardPage(
                                onOpenCatalog: () => c.setShellIndex(2),
                              ),
                          (_) => const LiveTvPage(),
                          (_) => CatalogPage(active: c.shellIndex == 2),
                          (_) => const FavoritesPage(),
                          (_) => const LibraryPage(),
                          (_) => const AccountPage(),
                        ],
                      ),
                      Positioned.fill(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.easeOutCubic,
                          child: searching
                              ? SearchOverlay(
                                  key: const ValueKey('search'),
                                  query: _query,
                                )
                              : const SizedBox.shrink(key: ValueKey('nosearch')),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Toque fora da barra expandida recolhe.
          Positioned.fill(
            left: _railWidth,
            child: IgnorePointer(
              ignoring: !expanded,
              child: AnimatedOpacity(
                opacity: expanded ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: c.toggleSidebar,
                  child: const ColoredBox(color: Color(0x55000000)),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: _Sidebar(
              index: index,
              collapsed: c.sidebarCollapsed,
              onSelect: (i) {
                if (_query.isNotEmpty) _clearSearch();
                c.setShellIndex(i);
                if (!c.sidebarCollapsed) c.toggleSidebar();
              },
              onToggle: c.toggleSidebar,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.index,
    required this.collapsed,
    required this.onSelect,
    required this.onToggle,
  });

  final int index;
  final bool collapsed;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggle;

  Widget _section(String label, bool collapsed) {
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Divider(color: AppColors.border),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: collapsed ? 68 : 220,
      decoration: BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.border)),
        boxShadow: collapsed
            ? const []
            : const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 24,
                  offset: Offset(6, 0),
                ),
              ],
      ),
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      // Decide pelo tamanho real durante a animação: os rótulos só aparecem
      // quando cabem (antes estouravam alguns pixels ao expandir).
      child: LayoutBuilder(builder: (context, box) {
        final compact = collapsed || box.maxWidth < 170;
        return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Faixa de arrastar a janela.
          const DragToMoveArea(child: SizedBox(height: 24)),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Row(
              mainAxisAlignment:
                  compact ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                CubosLogo(size: 36),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppInfo.name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.title(22, spacing: 1.2),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _section('MENU', compact),
          _NavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: 'Início',
            selected: index == 0,
            collapsed: compact,
            onTap: () => onSelect(0),
          ),
          const SizedBox(height: 4),
          _NavItem(
            icon: Icons.live_tv_outlined,
            activeIcon: Icons.live_tv_rounded,
            label: 'TV ao vivo',
            selected: index == 1,
            collapsed: compact,
            onTap: () => onSelect(1),
          ),
          const SizedBox(height: 4),
          _NavItem(
            icon: Icons.local_movies_outlined,
            activeIcon: Icons.local_movies_rounded,
            label: 'Filmes e séries',
            selected: index == 2,
            collapsed: compact,
            onTap: () => onSelect(2),
          ),
          const SizedBox(height: 4),
          _NavItem(
            icon: Icons.favorite_border_rounded,
            activeIcon: Icons.favorite_rounded,
            label: 'Favoritos',
            selected: index == 3,
            collapsed: compact,
            onTap: () => onSelect(3),
          ),
          const SizedBox(height: 4),
          _NavItem(
            icon: Icons.folder_special_outlined,
            activeIcon: Icons.folder_special_rounded,
            label: 'Minha biblioteca',
            selected: index == 4,
            collapsed: compact,
            onTap: () => onSelect(4),
          ),
          _section('GERAL', compact),
          _NavItem(
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings_rounded,
            label: 'Conta e ajustes',
            selected: index == 5,
            collapsed: compact,
            onTap: () => onSelect(5),
          ),
          const Spacer(),
          Align(
            alignment: collapsed ? Alignment.center : Alignment.centerLeft,
            child: IconButton(
              tooltip: collapsed ? 'Expandir menu' : 'Recolher menu',
              onPressed: onToggle,
              icon: Icon(
                collapsed ? Icons.chevron_right : Icons.chevron_left,
                size: 20,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      );
      }),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color background = widget.selected
        ? AppColors.accentSoft
        : (_hover ? AppColors.hover : Colors.transparent);
    final Color foreground =
        widget.selected ? AppColors.accent : AppColors.text;

    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
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
              ],
            ],
          ),
        ),
        // Indicador lateral na cor de destaque do perfil.
        Positioned(
          left: -8,
          top: 9,
          bottom: 9,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: widget.selected ? 3 : 0,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(3),
              ),
            ),
          ),
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
            ? Tooltip(message: widget.label, child: content)
            : content,
      ),
    );
  }
}
