import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../data/models.dart';
import '../../catalog/catalog_controller.dart' show CatalogSection;
import '../../state/app_scope.dart';
import '../shell/lazy_pages.dart';
import '../live_tv/manage_categories_panel.dart';
import '../widgets/manage_categories_button.dart';
import 'title_details_panel.dart';
import 'title_widgets.dart';

/// Catálogo: abas Filmes | Séries, fileiras por categoria (estilo Netflix),
/// "Ver tudo" por categoria e painel de detalhes.
class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key, required this.active});

  /// true quando esta página está aberta no menu. O download só começa então.
  final bool active;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  CatalogKind _kind = CatalogKind.movies;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).catalog.activeKind = _kind;
    if (widget.active) _ensureFresh();
  }

  @override
  void didUpdateWidget(CatalogPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _ensureFresh();
  }

  void _ensureFresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppScope.read(context).catalog.ensureFresh(_kind);
    });
  }

  void _selectKind(CatalogKind kind) {
    if (kind == _kind) return;
    AppScope.read(context).catalog.activeKind = kind;
    setState(() => _kind = kind);
    _ensureFresh();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = AppScope.of(context).catalog;
    final section = catalog.section(_kind);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 16, 8),
          child: Row(
            children: [
              _KindTab(
                label: 'Filmes',
                selected: _kind == CatalogKind.movies,
                onTap: () => _selectKind(CatalogKind.movies),
              ),
              const SizedBox(width: 8),
              _KindTab(
                label: 'Séries',
                selected: _kind == CatalogKind.series,
                onTap: () => _selectKind(CatalogKind.series),
              ),
              const Spacer(),
              IconButton(
                tooltip: section.syncing ? 'Atualizando…' : 'Atualizar lista',
                onPressed: section.syncing ? null : () => catalog.refresh(_kind),
                icon: Icon(Icons.refresh, size: 20, color: AppColors.textMuted),
              ),
              ManageCategoriesButton(
                key: ValueKey('manage:${_kind.key}'),
                hintKey: _kind.key,
                onPressed: () => showManageCatalogCategories(context, _kind),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          // Só a aba aberta existe; a outra é descartada 6 s depois de sair.
          child: LazyPages(
            index: _kind.index,
            onDrop: () => AppScope.read(context).catalog.trimCache(),
            builders: [
              (_) => _KindView(
                    key: const ValueKey('movies'),
                    kind: CatalogKind.movies,
                  ),
              (_) => _KindView(
                    key: const ValueKey('series'),
                    kind: CatalogKind.series,
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KindTab extends StatelessWidget {
  const _KindTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppColors.text : AppColors.textMuted,
                ),
                child: Text(label),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: 3,
                width: selected ? 28 : 0,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Conteúdo de uma aba: estados de carregamento, fileiras, busca e "Ver tudo".
class _KindView extends StatefulWidget {
  const _KindView({super.key, required this.kind});

  final CatalogKind kind;

  @override
  State<_KindView> createState() => _KindViewState();
}

class _KindViewState extends State<_KindView> {
  LiveCategory? _openCategory;

  CatalogKind get kind => widget.kind;

  void _open(CatalogTitle title) => showTitleDetails(context, title);

  @override
  Widget build(BuildContext context) {
    final catalog = AppScope.of(context).catalog;
    final section = catalog.section(kind);
    final label = kind.label.toLowerCase();

    if (section.total == 0) {
      if (section.syncing) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 16),
              Text('Baixando a lista de $label…'),
              const SizedBox(height: 4),
              Text(
                'Listas grandes podem levar alguns instantes na primeira vez.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        );
      }
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                section.error ?? 'Nenhum título de $label encontrado.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: section.error != null
                      ? AppColors.danger
                      : AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => catalog.refresh(kind),
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
    }

    Widget body;
    if (_openCategory != null) {
      body = _CategoryGrid(
        key: ValueKey('${kind.key}:all:${_openCategory!.id}'),
        kind: kind,
        category: _openCategory!,
        onBack: () => setState(() => _openCategory = null),
        onOpen: _open,
      );
    } else {
      body = KeyedSubtree(key: ValueKey('${kind.key}:rows'), child: _rows(section));
    }
    // Troca entre fileiras, grade da categoria e busca com fade suave.
    body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      child: body,
    );

    return Column(
      children: [
        if (section.syncing) const LinearProgressIndicator(minHeight: 2),
        if (section.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                section.error!,
                style: TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ),
          ),
        Expanded(child: body),
      ],
    );
  }

  Widget _rows(CatalogSection section) {
    final catalog = AppScope.of(context).catalog;
    final cats = section.visibleCategories;
    if (cats.isEmpty) {
      return Center(
        child: Text(
          'Todas as categorias estão ocultas. Use "Gerenciar categorias" para mostrar.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    // Categorias sem título nenhum não entram (evita fileira que some depois de
    // carregar e faz a rolagem "pular"). As fileiras especiais só entram na lista
    // depois de consultadas, pelo mesmo motivo.
    final rows = cats.where((c) => (section.counts[c.id] ?? 0) > 0).toList();
    return FutureBuilder<List<CatalogTitle>>(
      future: catalog.recentTitles(kind),
      builder: (context, recent) {
          // Se as listas em memória forem limpas (outra página descartada) e os
          // futuros mudarem, mantém os dados antigos em vez de esvaziar a tela:
          // esvaziar recriava a ListView e a rolagem voltava para o topo.
          final ready =
              recent.connectionState == ConnectionState.done || recent.hasData;
          if (!ready) return const SizedBox.shrink();
          final hasRecent = (recent.data ?? const []).isNotEmpty;
          final special = [if (hasRecent) 1];
          return ListView.builder(
            padding: const EdgeInsets.only(top: 16, bottom: 24),
            itemCount: special.length + rows.length,
            itemBuilder: (context, i) {
              if (i < special.length) {
                return TitleRow(
                  key: ValueKey('${kind.key}:recent'),
                  label: 'Adicionados recentemente',
                  future: catalog.recentTitles(kind),
                  onOpen: _open,
                );
              }
              final cat = rows[i - special.length];
              return TitleRow(
                key: ValueKey('${kind.key}:row:${cat.id}'),
                label: '${cat.name}  ·  ${section.counts[cat.id] ?? 0}',
                future: catalog.rowTitles(kind, cat.id),
                onOpen: _open,
                onSeeAll: () => setState(() => _openCategory = cat),
              );
            },
          );
      },
    );
  }
}

class _CategoryGrid extends StatefulWidget {
  const _CategoryGrid({
    super.key,
    required this.kind,
    required this.category,
    required this.onBack,
    required this.onOpen,
  });

  final CatalogKind kind;
  final LiveCategory category;
  final VoidCallback onBack;
  final ValueChanged<CatalogTitle> onOpen;

  @override
  State<_CategoryGrid> createState() => _CategoryGridState();
}

class _CategoryGridState extends State<_CategoryGrid> {
  late final Future<List<CatalogTitle>> _future =
      AppScope.read(context).catalog.allTitles(widget.kind, widget.category.id);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 24, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Voltar',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  widget.category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<CatalogTitle>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return TitleGrid(
                titles: snap.data ?? const [],
                onOpen: widget.onOpen,
              );
            },
          ),
        ),
      ],
    );
  }
}
