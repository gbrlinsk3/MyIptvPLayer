import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../state/app_scope.dart';
import '../widgets/animated_counter.dart';

/// Painel "Gerenciar assistidos" de uma série: temporada (menu), ações para a
/// temporada inteira fixas no alto e, abaixo do divisor, a lista de episódios
/// (só ela rola). Cada mudança vale na hora.
class ManageWatchedDialog extends StatefulWidget {
  const ManageWatchedDialog({
    super.key,
    required this.seriesId,
    required this.seasons,
    required this.initialSeason,
    required this.itemOf,
  });

  final int seriesId;
  final Map<int, List<Episode>> seasons;
  final int initialSeason;

  /// Item usado para gravar o progresso do episódio (null: sem URL, ignora).
  final PlayItem? Function(Episode) itemOf;

  @override
  State<ManageWatchedDialog> createState() => _ManageWatchedDialogState();
}

class _ManageWatchedDialogState extends State<ManageWatchedDialog> {
  late int _season = widget.seasons.containsKey(widget.initialSeason)
      ? widget.initialSeason
      : widget.seasons.keys.first;
  Map<int, WatchProgress> _progress = const {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await AppScope.read(context).catalog.episodeProgress(widget.seriesId);
    if (mounted) setState(() => _progress = m);
  }

  List<Episode> get _episodes => widget.seasons[_season] ?? const <Episode>[];

  Future<void> _set(Iterable<Episode> episodes, bool watched) async {
    if (_busy) return;
    setState(() => _busy = true);
    final catalog = AppScope.read(context).catalog;
    for (final e in episodes) {
      final item = widget.itemOf(e);
      if (item != null) await catalog.setWatched(item, watched);
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final seasons = widget.seasons.keys.toList();
    final episodes = _episodes;
    final done = episodes.where((e) => _progress[e.id]?.watched ?? false).length;
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          children: [
            // Parte fixa: título, temporada e ações da temporada.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'GERENCIAR ASSISTIDOS',
                      style: AppFonts.title(22, spacing: 1.2),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(AppShape.rounded ? 8 : 2),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _season,
                          isExpanded: true,
                          dropdownColor: AppColors.surface,
                          items: [
                            for (final s in seasons)
                              DropdownMenuItem(value: s, child: Text('Temporada $s')),
                          ],
                          onChanged: (s) {
                            if (s != null) setState(() => _season = s);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Largura mínima fixa: o menu de temporada não muda de tamanho quando o número muda.
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 150),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: AnimatedCounter(
                        value: done,
                        suffix: ' de ${episodes.length} assistidos',
                        semanticsLabel: '$done de ${episodes.length} assistidos',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _set(episodes, true),
                    icon: const Icon(Icons.done_all, size: 18),
                    label: const Text('Marcar todos desta temporada'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _set(episodes, false),
                    icon: const Icon(Icons.remove_done, size: 18),
                    label: const Text('Remover todos desta temporada'),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.border),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: episodes.length,
                itemBuilder: (context, i) {
                  final e = episodes[i];
                  final watched = _progress[e.id]?.watched ?? false;
                  return ListTile(
                    dense: true,
                    enabled: !_busy,
                    onTap: () => _set([e], !watched),
                    leading: Icon(
                      watched ? Icons.check_circle : Icons.check_circle_outline,
                      color: watched ? AppColors.accent : AppColors.textMuted,
                    ),
                    title: Text(
                      '${e.code} — ${e.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: watched ? AppColors.textMuted : AppColors.text,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
