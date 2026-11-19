import 'dart:async';

import 'package:flutter/material.dart';

import '../../catalog/title_matcher.dart' show looseKey;
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/carryover_store.dart';
import '../../data/catalog_models.dart';
import '../../data/models.dart';
import '../../state/app_scope.dart';
import '../catalog/poster_image.dart';
import '../widgets/common.dart';
import '../widgets/sliding_tabs.dart';

/// "Dados anteriores" (aba temporária da barra lateral): o que foi guardado na
/// troca de Xtream do mesmo provedor e não achou par seguro no catálogo novo.
/// Cada item pode ser religado a um título/canal/categoria do catálogo atual
/// (janela com busca) ou descartado; "Excluir aba" descarta tudo.
class CarryoverPage extends StatefulWidget {
  const CarryoverPage({super.key});

  @override
  State<CarryoverPage> createState() => _CarryoverPageState();
}

class _CarryoverPageState extends State<CarryoverPage> {
  CarryGroup? _tab;

  static const _labels = {
    CarryGroup.progress: 'Histórico',
    CarryGroup.favorites: 'Favoritos',
    CarryGroup.channels: 'Canais',
    CarryGroup.hidden: 'Categorias ocultas',
  };

  Future<void> _deleteAll() async {
    final app = AppScope.read(context);
    final go = await confirmDialog(
      context,
      title: 'Excluir a aba "Dados anteriores"?',
      message: 'Os ${app.carryoverCount} itens que ainda não foram religados '
          'serão descartados. O que você já religou continua no perfil.',
      action: 'Excluir aba',
    );
    if (go) await app.clearCarryover();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final data = app.carryover ?? Carryover();
    // Aba aberta: a escolhida, ou a primeira que tem itens.
    var tab = _tab;
    if (tab == null || data.listOf(tab).isEmpty) {
      tab = CarryGroup.values.firstWhere(
        (g) => data.listOf(g).isNotEmpty,
        orElse: () => CarryGroup.progress,
      );
    }
    final items = data.listOf(tab);
    final total = data.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('DADOS ANTERIORES', style: AppFonts.title(34, spacing: 1.5)),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '$total ${total == 1 ? 'item' : 'itens'} para revisar',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _deleteAll,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Excluir aba'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 2, 24, 4),
          child: Text(
            'Itens da conta Xtream anterior que não foram encontrados no catálogo '
            'novo. Religue cada um ao título certo ou descarte. Quando terminar, '
            'a aba some sozinha (ou use "Excluir aba").',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
          child: SlidingTabs(
            labels: [
              for (final g in CarryGroup.values)
                '${_labels[g]} · ${data.listOf(g).length}',
            ],
            selected: CarryGroup.values.indexOf(tab),
            onChanged: (i) => setState(() => _tab = CarryGroup.values[i]),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    'Nada para revisar aqui.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _EntryRow(
                    key: ValueKey('${tab!.name}:$i:${items[i]['name']}'),
                    group: tab,
                    entry: items[i],
                  ),
                ),
        ),
      ],
    );
  }
}

/// Uma linha: imagem/ícone, nome, o que era, e os botões Religar / Descartar.
class _EntryRow extends StatefulWidget {
  const _EntryRow({super.key, required this.group, required this.entry});

  final CarryGroup group;
  final Map<String, dynamic> entry;

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  bool _hover = false;
  bool _busy = false;

  Map<String, dynamic> get e => widget.entry;

  String get _name {
    final n = e['name'] as String? ?? '';
    final y = e['year'] as String?;
    return y == null || y.isEmpty || n.contains(y) ? n : '$n ($y)';
  }

  /// Tipo de catálogo do título (histórico/favoritos).
  CatalogKind get _kind => switch (e['kind']) {
        'vod' => CatalogKind.movies,
        _ => CatalogKind.series,
      };

  String get _detail {
    switch (widget.group) {
      case CarryGroup.progress:
        final isMovie = e['kind'] == 'vod';
        final where = isMovie ? 'Filme' : 'Série · T${e['season']} E${e['episode']}';
        if ((e['watched'] as int? ?? 0) == 1) return '$where · assistido';
        final pos = e['position_ms'] as int? ?? 0;
        final dur = e['duration_ms'] as int? ?? 0;
        if (pos <= 0) return where;
        final of = dur > 0 ? ' de ${formatDuration(Duration(milliseconds: dur))}' : '';
        return '$where · parou em ${formatDuration(Duration(milliseconds: pos))}$of';
      case CarryGroup.favorites:
        return e['kind'] == 'vod' ? 'Filme favorito' : 'Série favorita';
      case CarryGroup.channels:
        return 'Canal favorito';
      case CarryGroup.hidden:
        return switch (e['kind']) {
          'live' => 'Categoria oculta · TV ao vivo',
          'vod' => 'Categoria oculta · Filmes',
          _ => 'Categoria oculta · Séries',
        };
    }
  }

  IconData get _icon => switch (widget.group) {
        CarryGroup.channels => Icons.live_tv_rounded,
        CarryGroup.hidden => Icons.visibility_off_outlined,
        _ => e['kind'] == 'vod' ? Icons.movie_outlined : Icons.tv_rounded,
      };

  void _toast(String msg) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _relink() async {
    final app = AppScope.read(context);
    final initial = looseKey(e['name'] as String? ?? '');
    switch (widget.group) {
      case CarryGroup.progress:
      case CarryGroup.favorites:
        final kind = _kind;
        final target = await showRelinkDialog<CatalogTitle>(
          context,
          title: 'Religar "$_name"',
          hint: widget.group == CarryGroup.progress && e['kind'] == 'episode'
              ? 'Escolha a série; o episódio T${e['season']} E${e['episode']} é achado sozinho.'
              : null,
          initialQuery: initial,
          search: (q) => app.catalog.searchByName(kind, q),
          tile: (t) => _ResultTile(
            leading: _Thumb(url: t.image, name: t.name, icon: _icon),
            title: t.name,
            subtitle: [
              kind == CatalogKind.movies ? 'Filme' : 'Série',
              if (t.year != null && t.year!.isNotEmpty) t.year!,
            ].join(' · '),
          ),
        );
        if (target == null || !mounted) return;
        setState(() => _busy = true);
        final err = await app.relinkCarryoverTitle(widget.group, e, target);
        if (!mounted) return;
        setState(() => _busy = false);
        _toast(err ?? '"${target.name}" religado.');
      case CarryGroup.channels:
        final channel = await showRelinkDialog<LiveChannel>(
          context,
          title: 'Religar o canal "$_name"',
          initialQuery: initial,
          search: (q) async {
            final words = _words(q);
            return [
              for (final ch in app.allChannels)
                if (words.every(ch.searchKey.contains)) ch,
            ].take(60).toList();
          },
          tile: (ch) => _ResultTile(
            leading: _Thumb(url: ch.icon, name: ch.name, icon: Icons.live_tv_rounded),
            title: ch.name,
          ),
        );
        if (channel == null || !mounted) return;
        await app.relinkCarryoverChannel(e, channel);
        if (mounted) _toast('"${channel.name}" adicionado aos favoritos.');
      case CarryGroup.hidden:
        final kindKey = e['kind'] as String;
        final cats = kindKey == 'live'
            ? app.allLiveCategories
            : app.catalog
                .section(kindKey == 'vod' ? CatalogKind.movies : CatalogKind.series)
                .categories;
        final cat = await showRelinkDialog<LiveCategory>(
          context,
          title: 'Ocultar de novo "$_name"',
          initialQuery: initial,
          search: (q) async {
            final words = _words(q);
            return [
              for (final c in cats)
                if (words.every(foldText(c.name).contains)) c,
            ];
          },
          tile: (c) => _ResultTile(
            leading: _Thumb(url: null, name: c.name, icon: Icons.folder_outlined),
            title: c.name,
          ),
        );
        if (cat == null || !mounted) return;
        await app.relinkCarryoverCategory(e, kindKey, cat.id);
        if (mounted) _toast('Categoria "${cat.name}" oculta.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _hover ? AppColors.hover : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            _Thumb(url: e['image'] as String?, name: _name, icon: _icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (_busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              FilledButton.tonalIcon(
                onPressed: _relink,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Religar'),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: () => app.discardCarryover(widget.group, e),
                child: const Text('Descartar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

List<String> _words(String q) => [
      for (final w in foldText(q).split(RegExp(r'\s+')))
        if (w.isNotEmpty) w,
    ];

/// Imagem pequena (pôster/logo) ou um ícone quando não há imagem.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.name, required this.icon});

  final String? url;
  final String name;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 40,
        height: 56,
        child: url == null || url!.isEmpty
            ? ColoredBox(
                color: AppColors.accentSoft,
                child: Icon(icon, size: 20, color: AppColors.accent),
              )
            : PosterImage(url: url, name: name, cacheWidth: 120),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.leading, required this.title, this.subtitle});

  final Widget leading;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Janela "Religar": campo de busca (já com o nome antigo) e a lista de
/// resultados; um clique escolhe. Devolve null se cancelar.
Future<T?> showRelinkDialog<T>(
  BuildContext context, {
  required String title,
  required String initialQuery,
  required Future<List<T>> Function(String query) search,
  required Widget Function(T item) tile,
  String? hint,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => _RelinkDialog<T>(
      title: title,
      hint: hint,
      initialQuery: initialQuery,
      search: search,
      tile: tile,
    ),
  );
}

class _RelinkDialog<T> extends StatefulWidget {
  const _RelinkDialog({
    required this.title,
    required this.initialQuery,
    required this.search,
    required this.tile,
    this.hint,
  });

  final String title;
  final String initialQuery;
  final Future<List<T>> Function(String query) search;
  final Widget Function(T item) tile;
  final String? hint;

  @override
  State<_RelinkDialog<T>> createState() => _RelinkDialogState<T>();
}

class _RelinkDialogState<T> extends State<_RelinkDialog<T>> {
  late final TextEditingController _q =
      TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  List<T> _results = const [];
  bool _loading = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _run);
  }

  Future<void> _run() async {
    final seq = ++_seq;
    final q = _q.text.trim();
    if (q.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _loading = true);
    final list = await widget.search(q);
    if (!mounted || seq != _seq) return;
    setState(() {
      _results = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.hint != null) ...[
              Text(
                widget.hint!,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _q,
              autofocus: true,
              onChanged: _onChanged,
              decoration: fieldDecoration(
                hint: 'Buscar no catálogo atual',
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading && _results.isEmpty
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            'Nada encontrado. Tente outras palavras.',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, i) => InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => Navigator.of(context).pop(_results[i]),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 5,
                              ),
                              child: widget.tile(_results[i]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
