import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import 'channel_card.dart';
import 'live_highlight_banner.dart';
import 'live_player_page.dart';
import 'manage_categories_panel.dart';
import '../widgets/manage_categories_button.dart';

/// TV ao vivo no mesmo formato do catálogo: cada categoria é uma fileira
/// horizontal com o nome como divisor; o canal toca em uma página própria.
class LiveTvPage extends StatefulWidget {
  const LiveTvPage({super.key});

  @override
  State<LiveTvPage> createState() => _LiveTvPageState();
}

class _Group {
  const _Group(this.label, this.channels, {this.categoryId});

  final String label;
  final List<LiveChannel> channels;
  final String? categoryId;
}

class _LiveTvPageState extends State<LiveTvPage> {
  // Agrupamento em cache: só refaz quando a lista, as categorias ou os
  // favoritos mudam (o app notifica por muitos motivos).
  List<LiveChannel>? _forVisible;
  List<LiveCategory>? _forCategories;
  Set<int>? _forFavorites;
  List<_Group> _groups = const [];

  List<_Group> _groupsFor(AppController c) {
    if (identical(_forVisible, c.visible) &&
        identical(_forCategories, c.categories) &&
        identical(_forFavorites, c.favoriteChannels)) {
      return _groups;
    }
    _forVisible = c.visible;
    _forCategories = c.categories;
    _forFavorites = c.favoriteChannels;

    final byCategory = <String, List<LiveChannel>>{};
    for (final ch in c.visible) {
      (byCategory[ch.categoryId] ??= []).add(ch);
    }
    final groups = <_Group>[];
    final favs = [
      for (final ch in c.visible)
        if (c.favoriteChannels.contains(ch.streamId)) ch,
    ];
    if (favs.isNotEmpty) groups.add(_Group('Favoritos', favs));
    for (final cat in c.categories) {
      final list = byCategory[cat.id];
      if (list != null && list.isNotEmpty) {
        groups.add(_Group(cat.name, list, categoryId: cat.id));
      }
    }
    return _groups = groups;
  }

  void _open(LiveChannel channel, List<LiveChannel> list) {
    AppScope.read(context).selectChannel(channel);
    openLivePlayer(context, list);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final summary = c.visible.length == c.totalChannels
        ? '${c.totalChannels} canais'
        : '${c.visible.length} de ${c.totalChannels} canais';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
          child: Row(
            children: [
              Text('TV AO VIVO', style: AppFonts.title(34, spacing: 1.2)),
              const SizedBox(width: 14),
              Text(
                summary,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Atualizar catálogo',
                onPressed: c.syncing ? null : c.refreshCatalog,
                icon: c.syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
              ),
              ManageCategoriesButton(
                hintKey: 'live',
                iconColor: Theme.of(context).iconTheme.color,
                onPressed: () => showManageCategories(context),
              ),
            ],
          ),
        ),
        if (c.syncError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              c.syncError!,
              style: TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ),
        Expanded(child: _body(c)),
      ],
    );
  }

  Widget _body(AppController c) {
    if (c.totalChannels == 0) {
      return _Message(
        c.syncing
            ? 'Carregando canais…'
            : 'Nenhum canal carregado. Use o botão de atualizar acima.',
      );
    }
    if (c.visible.isEmpty) return const _Message('Nenhum canal encontrado.');

    // Uma categoria aberta ("Ver tudo"): todos os canais dela em grade.
    final open = c.selectedCategoryId;
    if (open != null) {
      String name = '';
      for (final cat in c.categories) {
        if (cat.id == open) name = cat.name;
      }
      final list = c.visible;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 24, 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => c.selectCategory(null),
                  icon: const Icon(Icons.chevron_left, size: 20),
                  label: const Text('Todas as categorias'),
                ),
                const SizedBox(width: 8),
                Text(name.toUpperCase(), style: AppFonts.title(22, spacing: 1.2)),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 250,
                mainAxisExtent: ChannelCard.height,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: list.length,
              itemBuilder: (context, i) => ChannelCard(
                channel: list[i],
                onTap: () => _open(list[i], list),
              ),
            ),
          ),
        ],
      );
    }

    final groups = _groupsFor(c);
    final highlights = c.highlights;
    return CustomScrollView(
      slivers: [
        if (highlights.isNotEmpty)
          SliverToBoxAdapter(
            child: LiveHighlightBanner(
              highlights: highlights,
              onOpen: _open,
              onSeeCategory: c.selectCategory,
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          sliver: SliverFixedExtentList(
            itemExtent: ChannelRow.extent,
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final g = groups[i];
                return ChannelRow(
                  label: g.label,
                  channels: g.channels,
                  onOpen: (ch) => _open(ch, g.channels),
                  onSeeAll: g.categoryId == null
                      ? null
                      : () => c.selectCategory(g.categoryId),
                );
              },
              childCount: groups.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
      ),
    );
  }
}
