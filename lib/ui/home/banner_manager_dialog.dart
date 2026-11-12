import 'dart:async';

import 'package:flutter/material.dart';

import '../../catalog/catalog_controller.dart' show SearchResults;
import '../../catalog/home_banners.dart';
import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../state/app_scope.dart';
import '../catalog/animation_categories_dialog.dart';

/// Gerenciador dos banners do Início: o 1º ("Continue de onde parou") é fixo;
/// dá para ter até 4 outros (5 no total), com nome, fonte e ordem à escolha.
Future<void> showBannerManager(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ManagerDialog(),
  );
}

class _ManagerDialog extends StatefulWidget {
  const _ManagerDialog();

  @override
  State<_ManagerDialog> createState() => _ManagerDialogState();
}

class _ManagerDialogState extends State<_ManagerDialog> {
  late List<BannerConfig> _list;
  // Chaves estáveis para os campos de nome não perderem o texto ao reordenar.
  final List<Key> _keys = [];

  @override
  void initState() {
    super.initState();
    _list = [
      for (final b in AppScope.read(context).catalog.banners) b.copy(),
    ];
    for (final _ in _list) {
      _keys.add(UniqueKey());
    }
  }

  void _add() {
    setState(() {
      _list.add(BannerConfig(name: 'Novo banner', source: BannerSource.newMovies));
      _keys.add(UniqueKey());
    });
  }

  void _move(int i, int d) {
    final j = i + d;
    if (j < 0 || j >= _list.length) return;
    setState(() {
      _list.insert(j, _list.removeAt(i));
      _keys.insert(j, _keys.removeAt(i));
    });
  }

  void _remove(int i) {
    setState(() {
      _list.removeAt(i);
      _keys.removeAt(i);
    });
  }

  String _summary(BannerConfig b) => switch (b.source) {
        BannerSource.categories => b.categories.isEmpty
            ? 'Nenhuma categoria escolhida (o banner não aparece)'
            : '${b.categories.length} categoria(s)',
        BannerSource.titles => b.titles.isEmpty
            ? 'Nenhum título escolhido (o banner não aparece)'
            : b.titles.map((t) => t.name).join(', '),
        _ => b.source.hint,
      };

  Future<void> _choose(BannerConfig b) async {
    if (b.source == BannerSource.categories) {
      final r = await pickBannerCategories(
        context,
        initial: b.categories,
        bannerName: b.name,
      );
      if (r != null) setState(() => b.categories = r);
    } else if (b.source == BannerSource.titles) {
      final r = await showDialog<List<BannerTitleRef>>(
        context: context,
        builder: (_) => _TitlePicker(initial: b.titles),
      );
      if (r != null) setState(() => b.titles = r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = AppScope.read(context).catalog;
    final muted = TextStyle(color: AppColors.textMuted, fontSize: 12);
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Banners do Início', style: AppFonts.title(24)),
              const SizedBox(height: 6),
              Text(
                'O primeiro banner não pode ser removido. Até 5 banners no '
                'total. Os dois banners menores à direita acompanham os slides.',
                style: muted,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _card(
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline,
                                size: 18, color: AppColors.textMuted),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Continue de onde parou  ·  principal (fixo)',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (var i = 0; i < _list.length; i++)
                        _card(
                          key: _keys[i],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: _list[i].name,
                                      maxLength: 28,
                                      onChanged: (v) => _list[i].name = v,
                                      decoration: const InputDecoration(
                                        labelText: 'Nome do banner',
                                        isDense: true,
                                        counterText: '',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Subir',
                                    onPressed: i == 0 ? null : () => _move(i, -1),
                                    icon: const Icon(Icons.arrow_upward, size: 18),
                                  ),
                                  IconButton(
                                    tooltip: 'Descer',
                                    onPressed: i == _list.length - 1
                                        ? null
                                        : () => _move(i, 1),
                                    icon: const Icon(Icons.arrow_downward, size: 18),
                                  ),
                                  IconButton(
                                    tooltip: 'Remover',
                                    onPressed: () => _remove(i),
                                    icon: const Icon(Icons.delete_outline, size: 18),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  DropdownButton<BannerSource>(
                                    value: _list[i].source,
                                    underline: const SizedBox.shrink(),
                                    items: [
                                      for (final s in BannerSource.values)
                                        DropdownMenuItem(
                                          value: s,
                                          child: Text(s.label),
                                        ),
                                    ],
                                    onChanged: (v) {
                                      if (v != null) {
                                        setState(() => _list[i].source = v);
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  if (_list[i].source == BannerSource.categories ||
                                      _list[i].source == BannerSource.titles)
                                    OutlinedButton(
                                      onPressed: () => _choose(_list[i]),
                                      child: Text(
                                        _list[i].source == BannerSource.titles
                                            ? 'Escolher títulos'
                                            : 'Escolher categorias',
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _summary(_list[i]),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: muted,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _list.length >= BannerConfig.maxExtra ? null : _add,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text('Adicionar (${1 + _list.length} de 5)'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() {
                      _list = BannerConfig.defaults(catalog.animationCategories);
                      _keys
                        ..clear()
                        ..addAll(_list.map((_) => UniqueKey()));
                    }),
                    child: const Text('Restaurar padrão'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      for (final b in _list) {
                        if (b.name.trim().isEmpty) b.name = b.source.label;
                        b.name = b.name.trim();
                      }
                      await catalog.setBanners(_list);
                      nav.pop();
                    },
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

  Widget _card({Key? key, required Widget child}) => Container(
        key: key,
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

/// Busca filmes e séries e marca até [BannerConfig.maxTitles] para o banner.
class _TitlePicker extends StatefulWidget {
  const _TitlePicker({required this.initial});

  final List<BannerTitleRef> initial;

  @override
  State<_TitlePicker> createState() => _TitlePickerState();
}

class _TitlePickerState extends State<_TitlePicker> {
  late final List<BannerTitleRef> _chosen = [...widget.initial];
  List<CatalogTitle> _results = const [];
  Timer? _debounce;
  int _seq = 0;
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  bool _has(CatalogTitle t) =>
      _chosen.any((r) => r.kind == t.kind && r.id == t.id);

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(q.trim()));
  }

  Future<void> _run(String q) async {
    if (q.length < 2) {
      setState(() => _results = const []);
      return;
    }
    final catalog = AppScope.read(context).catalog;
    final mine = ++_seq;
    setState(() => _loading = true);
    try {
      final data = await Future.wait([
        catalog.search(CatalogKind.movies, q),
        catalog.search(CatalogKind.series, q),
      ]);
      if (!mounted || mine != _seq) return;
      setState(() {
        _results = SearchResults.closest(data[0], data[1], limit: 40);
        _loading = false;
      });
    } catch (_) {
      if (mounted && mine == _seq) setState(() => _loading = false);
    }
  }

  void _toggle(CatalogTitle t) {
    setState(() {
      if (_has(t)) {
        _chosen.removeWhere((r) => r.kind == t.kind && r.id == t.id);
      } else if (_chosen.length < BannerConfig.maxTitles) {
        _chosen.add(BannerTitleRef(t.kind, t.id, t.name));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Escolher títulos', style: AppFonts.title(24)),
              const SizedBox(height: 6),
              Text(
                'Busque e marque até ${BannerConfig.maxTitles} filmes ou séries '
                '(${_chosen.length} marcados). O primeiro marcado aparece no '
                'banner grande.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'Buscar filmes e séries',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (_chosen.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final r in _chosen)
                        InputChip(
                          label: Text(r.name, overflow: TextOverflow.ellipsis),
                          onDeleted: () => setState(() => _chosen.remove(r)),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in _results)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppColors.accent,
                        value: _has(t),
                        title: Text(t.name, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          [
                            t.kind == CatalogKind.movies ? 'Filme' : 'Série',
                            if (t.year != null && t.year!.isNotEmpty) t.year!,
                          ].join(' · '),
                          style: const TextStyle(fontSize: 11),
                        ),
                        onChanged: (_) => _toggle(t),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(_chosen.clear),
                    child: const Text('Limpar'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_chosen),
                    child: const Text('Concluir'),
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
