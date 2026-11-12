import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../state/app_scope.dart';
import '../catalog/poster_image.dart';
import '../catalog/title_details_panel.dart';

/// Histórico: tudo que já foi assistido ou começado, agrupado por data.
/// Mostra só a **última** vez de cada filme/episódio.
class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

/// Item da lista achatada: cabeçalho de data ou linha do histórico.
class _Item {
  const _Item.header(this.label) : row = null;
  const _Item.row(this.row) : label = null;

  final String? label;
  final HistoryRow? row;
}

class _HistoryViewState extends State<HistoryView> {
  List<_Item> _items = const [];
  int _count = 0;
  bool _loaded = false;
  int _seenRevision = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final catalog = AppScope.of(context).catalog;
    if (_seenRevision != catalog.progressRevision) {
      _seenRevision = catalog.progressRevision;
      _load();
    }
  }

  Future<void> _load() async {
    final rows = await AppScope.read(context).catalog.history();
    if (!mounted) return;
    setState(() {
      _items = _group(rows);
      _count = rows.length;
      _loaded = true;
    });
  }

  static String _bucket(DateTime when, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(when.year, when.month, when.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    if (diff < 7) return 'Esta semana';
    if (diff < 30) return 'Este mês';
    return 'Mais antigos';
  }

  List<_Item> _group(List<HistoryRow> rows) {
    final now = DateTime.now();
    final out = <_Item>[];
    String? last;
    for (final r in rows) {
      final b = _bucket(DateTime.fromMillisecondsSinceEpoch(r.updatedAt), now);
      if (b != last) {
        out.add(_Item.header(b));
        last = b;
      }
      out.add(_Item.row(r));
    }
    return out;
  }

  Future<void> _clearAll() async {
    final catalog = AppScope.read(context).catalog;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar histórico?'),
        content: const Text(
          'Isso apaga o histórico de filmes e episódios e também o '
          '"Continuar assistindo" (as posições onde você parou). Arquivos '
          'baixados, favoritos e arquivos importados não são afetados. Não dá '
          'para desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (ok == true) await catalog.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Nada no histórico ainda. Filmes e episódios que você assistir '
          'aparecem aqui, com a data da última vez.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    final catalog = AppScope.read(context).catalog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                '$_count ${_count == 1 ? 'título' : 'títulos'} · só a última vez de cada um',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _clearAll,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Limpar histórico'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _items.length,
            itemBuilder: (context, i) {
              final it = _items[i];
              if (it.label != null) {
                return Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 8),
                  child: Text(
                    it.label!.toUpperCase(),
                    style: AppFonts.title(18, spacing: 1.2),
                  ),
                );
              }
              final r = it.row!;
              return _HistoryTile(
                key: ValueKey('${r.progressKind}:${r.itemId}'),
                row: r,
                onOpen: () => showTitleDetails(context, r.toTitle()),
                onToggleWatched: () => catalog.setHistoryWatched(r, !r.watched),
                onRemove: () => catalog.removeHistory(r),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatefulWidget {
  const _HistoryTile({
    super.key,
    required this.row,
    required this.onOpen,
    required this.onToggleWatched,
    required this.onRemove,
  });

  final HistoryRow row;
  final VoidCallback onOpen;
  final VoidCallback onToggleWatched;
  final VoidCallback onRemove;

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  bool _hover = false;

  static String _when(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} às ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final status = r.watched
        ? 'Assistido'
        : r.durationMs > 0
            ? '${(r.fraction * 100).round()}% assistido'
            : 'Em andamento';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover ? AppColors.accent : AppColors.border,
              width: _hover ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 84,
                  child: PosterImage(url: r.image, name: r.title, cacheWidth: 160),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                    if (r.subtitle != null && r.subtitle!.isNotEmpty)
                      Text(
                        r.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '${r.isMovie ? 'Filme' : 'Série'} · $status · ${_when(r.updatedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                    if (!r.watched && r.durationMs > 0) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 220,
                        child: LinearProgressIndicator(
                          value: r.fraction,
                          minHeight: 4,
                          backgroundColor: AppColors.border,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Mais opções',
                onSelected: (v) {
                  switch (v) {
                    case 'open':
                      widget.onOpen();
                    case 'watched':
                      widget.onToggleWatched();
                    case 'remove':
                      widget.onRemove();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'open', child: Text('Abrir (retomar ou reassistir)')),
                  PopupMenuItem(
                    value: 'watched',
                    child: Text(r.watched ? 'Marcar como não assistido' : 'Marcar como assistido'),
                  ),
                  const PopupMenuItem(value: 'remove', child: Text('Remover do histórico')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
