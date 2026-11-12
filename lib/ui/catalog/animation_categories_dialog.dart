import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../state/app_scope.dart';

/// Escolhe categorias (de filmes `m:<id>` e de séries `s:<id>`) para um banner
/// do Início. Devolve null se cancelar.
Future<Set<String>?> pickBannerCategories(
  BuildContext context, {
  required Set<String> initial,
  required String bannerName,
}) {
  return showDialog<Set<String>>(
    context: context,
    builder: (_) => _Dialog(initial: initial, bannerName: bannerName),
  );
}

class _Dialog extends StatefulWidget {
  const _Dialog({required this.initial, required this.bannerName});

  final Set<String> initial;
  final String bannerName;

  @override
  State<_Dialog> createState() => _DialogState();
}

class _DialogState extends State<_Dialog> {
  late Set<String> _selected;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initial};
  }

  @override
  Widget build(BuildContext context) {
    final catalog = AppScope.read(context).catalog;
    final q = _filter.trim().toLowerCase();

    Widget group(CatalogKind kind, String prefix) {
      final cats = catalog
          .section(kind)
          .categories
          .where((c) => q.isEmpty || c.name.toLowerCase().contains(q))
          .toList();
      if (cats.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
            child: Text(
              kind.label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
          ),
          for (final c in cats)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.accent,
              value: _selected.contains('$prefix:${c.id}'),
              title: Text(c.name, style: const TextStyle(fontSize: 13)),
              onChanged: (v) => setState(() {
                final key = '$prefix:${c.id}';
                v == true ? _selected.add(key) : _selected.remove(key);
              }),
            ),
        ],
      );
    }

    final empty = catalog.section(CatalogKind.movies).categories.isEmpty &&
        catalog.section(CatalogKind.series).categories.isEmpty;

    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Categorias do banner', style: AppFonts.title(24)),
              const SizedBox(height: 6),
              Text(
                'Os títulos dessas categorias aparecem no banner '
                '"${widget.bannerName}" do Início (3 sorteados).',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() => _filter = v),
                decoration: InputDecoration(
                  hintText: 'Filtrar categorias',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Flexible(
                child: empty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Baixe filmes e séries primeiro (abra o Início ou o '
                          'Catálogo).',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            group(CatalogKind.movies, 'm'),
                            group(CatalogKind.series, 's'),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('Limpar'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: const Text('Salvar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
