import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog_models.dart';

/// Lista de episódios dentro do player (lado direito). Mostra todos os itens
/// da fila atual e destaca o que está tocando.
class PlayerEpisodesPanel extends StatefulWidget {
  const PlayerEpisodesPanel({
    super.key,
    required this.items,
    required this.current,
    required this.onSelect,
    required this.onClose,
  });

  final List<PlayItem> items;
  final int current;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  @override
  State<PlayerEpisodesPanel> createState() => _PlayerEpisodesPanelState();
}

class _PlayerEpisodesPanelState extends State<PlayerEpisodesPanel> {
  static const _rowHeight = 56.0;
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset:
        ((widget.current - 2) * _rowHeight).clamp(0.0, double.infinity),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.items.isEmpty ? '' : widget.items.first.title;
    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: const Color(0xF2141312),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 24)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.title(20, color: Colors.white, spacing: 1),
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemExtent: _rowHeight,
              itemCount: widget.items.length,
              itemBuilder: (context, i) {
                final it = widget.items[i];
                final now = i == widget.current;
                return InkWell(
                  onTap: now ? null : () => widget.onSelect(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: now ? AppColors.accent.withValues(alpha: 0.18) : null,
                      border: Border(
                        left: BorderSide(
                          color: now ? AppColors.accent : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26,
                          child: now
                              ? Icon(Icons.equalizer, size: 20, color: AppColors.accent)
                              : Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            it.subtitle ?? it.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: now ? Colors.white : Colors.white70,
                              fontSize: 13,
                              fontWeight: now ? FontWeight.w700 : FontWeight.w500,
                            ),
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
    );
  }
}
