import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/catalog_models.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';

/// De onde o painel lê e para onde grava as categorias (TV ao vivo, filmes ou séries).
abstract class ManageSource {
  Listenable get listenable;
  List<LiveCategory> get categories;
  int rawCount(String id);
  bool isVisible(String id);
  Future<void> setVisible(Iterable<String> ids, bool visible);
}

class _LiveSource implements ManageSource {
  _LiveSource(this.c);

  final AppController c;

  @override
  Listenable get listenable => c;
  @override
  List<LiveCategory> get categories => c.manageableCategories;
  @override
  int rawCount(String id) => c.rawCountByCategory[id] ?? 0;
  @override
  bool isVisible(String id) => c.isCategoryVisible(id);
  @override
  Future<void> setVisible(Iterable<String> ids, bool visible) =>
      c.setCategoriesVisible(ids, visible);
}

class _CatalogSource implements ManageSource {
  _CatalogSource(this.c, this.kind);

  final AppController c;
  final CatalogKind kind;

  @override
  Listenable get listenable => c.catalog;
  @override
  List<LiveCategory> get categories => c.catalog.section(kind).manageable;
  @override
  int rawCount(String id) => c.catalog.section(kind).counts[id] ?? 0;
  @override
  bool isVisible(String id) => c.catalog.isVisible(kind, id);
  @override
  Future<void> setVisible(Iterable<String> ids, bool visible) =>
      c.catalog.setCategoriesVisible(kind, ids, visible);
}

/// Abre o painel lateral "Gerenciar categorias" (TV ao vivo).
/// Categorias marcadas ficam visíveis; as desmarcadas são ocultadas da lista
/// de categorias, da lista de canais e da busca.
Future<void> showManageCategories(BuildContext context) {
  return _showPanel(context, _LiveSource(AppScope.read(context)));
}

/// Mesmo painel para as categorias de filmes ou de séries.
Future<void> showManageCatalogCategories(BuildContext context, CatalogKind kind) {
  return _showPanel(context, _CatalogSource(AppScope.read(context), kind));
}

Future<void> _showPanel(BuildContext context, ManageSource source) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _ManagePanel(source: source),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _ManagePanel extends StatefulWidget {
  const _ManagePanel({required this.source});

  final ManageSource source;

  @override
  State<_ManagePanel> createState() => _ManagePanelState();
}

class _ManagePanelState extends State<_ManagePanel> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.source.listenable,
      builder: (context, _) => _buildPanel(context),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final c = widget.source;
    final all = c.categories;
    final q = foldText(_search.text.trim());
    final List<LiveCategory> filtered = q.isEmpty
        ? all
        : [
            for (final cat in all)
              if (foldText(cat.name).contains(q)) cat,
          ];
    final selectedCount = all.where((cat) => c.isVisible(cat.id)).length;
    final allFilteredOn =
        filtered.isNotEmpty && filtered.every((cat) => c.isVisible(cat.id));

    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 400,
          child: Material(
            color: AppColors.surface,
            elevation: 8,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.border),
            ),
            child: Column(
              children: [
                // ---- parte fixa -------------------------------------------
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Gerenciar categorias',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$selectedCount de ${all.length} selecionadas',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Buscar categoria',
                            isDense: true,
                            prefixIcon: const Icon(Icons.search, size: 18),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.border),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.accent),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: filtered.isEmpty
                            ? null
                            : () => c.setVisible(
                                  filtered.map((cat) => cat.id),
                                  !allFilteredOn,
                                ),
                        child: Text(
                          allFilteredOn ? 'Desmarcar todas' : 'Marcar todas',
                        ),
                      ),
                    ],
                  ),
                ),
                // Divisor invisível: separa a parte fixa da lista rolável.
                const SizedBox(height: 16),
                // ---- lista de categorias ----------------------------------
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'Nenhuma categoria encontrada.',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemExtent: 44,
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final cat = filtered[i];
                            final on = c.isVisible(cat.id);
                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => c.setVisible([cat.id], !on),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: on,
                                      onChanged: (v) => c.setVisible(
                                        [cat.id],
                                        v ?? false,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        cat.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: on
                                              ? AppColors.text
                                              : AppColors.textMuted,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${c.rawCount(cat.id)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
