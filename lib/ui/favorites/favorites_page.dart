import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../data/models.dart';
import '../../state/app_scope.dart';
import '../catalog/title_details_panel.dart';
import '../catalog/title_widgets.dart';
import '../live_tv/channel_card.dart';
import '../live_tv/live_player_page.dart';

/// Favoritos: filmes, séries e canais. Abas Todos / Filmes / Séries / Canais;
/// dentro de "Todos", primeiro filmes e séries (do mais recente para o mais
/// antigo) e depois os canais. Tirar o coração de um cartão o remove da lista.
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<CatalogTitle> _movies = const [];
  List<CatalogTitle> _series = const [];
  bool _loaded = false;
  int _tab = 0;
  ValueNotifier<int>? _revision;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_revision == null) {
      final catalog = AppScope.read(context).catalog;
      _revision = catalog.favoritesRevision..addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _revision?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final catalog = AppScope.read(context).catalog;
    final movies = await catalog.favoriteTitles(CatalogKind.movies);
    final series = await catalog.favoriteTitles(CatalogKind.series);
    if (!mounted) return;
    setState(() {
      _movies = movies;
      _series = series;
      _loaded = true;
    });
  }

  void _openChannel(LiveChannel ch, List<LiveChannel> list) {
    AppScope.read(context).selectChannel(ch);
    openLivePlayer(context, list);
  }

  Widget _channelGrid(List<LiveChannel> channels) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 250,
          mainAxisExtent: ChannelCard.height,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => ChannelCard(
            key: ValueKey('fav-ch:${channels[i].streamId}'),
            channel: channels[i],
            onTap: () => _openChannel(channels[i], channels),
          ),
          childCount: channels.length,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    // Canais favoritos (só de categorias visíveis), na ordem da lista do provedor.
    final channels = app.favoriteChannelList;
    final titles = switch (_tab) {
      1 => _movies,
      2 => _series,
      3 => const <CatalogTitle>[],
      _ => [..._movies, ..._series],
    };
    final showChannels = _tab == 0 || _tab == 3;
    final shownChannels = showChannels ? channels : const <LiveChannel>[];
    final total = _movies.length + _series.length + channels.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('FAVORITOS', style: AppFonts.title(34, spacing: 1.5)),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '$total ${total == 1 ? 'item' : 'itens'}',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Wrap(
            spacing: 8,
            children: [
              for (final (i, label, n) in [
                (0, 'Todos', total),
                (1, 'Filmes', _movies.length),
                (2, 'Séries', _series.length),
                (3, 'Canais', channels.length),
              ])
                ChoiceChip(
                  label: Text('$label · $n'),
                  selected: _tab == i,
                  onSelected: (_) => setState(() => _tab = i),
                ),
            ],
          ),
        ),
        Expanded(
          child: !_loaded
              ? const SizedBox.shrink()
              : titles.isEmpty && shownChannels.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Nada por aqui ainda. Passe o mouse sobre um filme, '
                          'série ou canal e toque no coração para favoritar.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    )
                  : CustomScrollView(
                      slivers: [
                        if (titles.isNotEmpty)
                          TitleGrid.sliver(
                            titles: titles,
                            onOpen: (t) => showTitleDetails(context, t),
                          ),
                        if (titles.isNotEmpty && shownChannels.isNotEmpty)
                          const SliverToBoxAdapter(child: SizedBox(height: 16)),
                        if (shownChannels.isNotEmpty) _channelGrid(shownChannels),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ),
        ),
      ],
    );
  }
}
