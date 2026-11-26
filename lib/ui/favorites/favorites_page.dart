import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../data/models.dart';
import '../../state/app_scope.dart';
import '../catalog/title_details_panel.dart';
import '../catalog/title_widgets.dart';
import '../live_tv/channel_card.dart';
import '../live_tv/live_player_page.dart';
import '../widgets/sliding_tabs.dart';
import '../widgets/state_views.dart';
import '../../core/format.dart';

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
                  plural(total, 'item', 'itens'),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: SlidingTabs(
            labels: [
              'Todos · $total',
              'Filmes · ${formatCount(_movies.length)}',
              'Séries · ${formatCount(_series.length)}',
              'Canais · ${formatCount(channels.length)}',
            ],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
        Expanded(
          child: !_loaded
              ? const TitleGridSkeleton()
              : titles.isEmpty && shownChannels.isEmpty
                  ? EmptyState(
                      icon: Icons.favorite_border,
                      title: 'Nenhum favorito ainda',
                      text: 'Toque no coração em um título ou canal para salvar aqui.',
                      actionLabel: 'Explorar filmes e séries',
                      // Índice 2 do menu = "Filmes e séries" (ordem em shell.dart).
                      onAction: () => AppScope.read(context).setShellIndex(2),
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
