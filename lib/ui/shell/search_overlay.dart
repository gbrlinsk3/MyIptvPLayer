import 'dart:async';

import 'package:flutter/material.dart';

import '../../catalog/catalog_controller.dart' show CatalogController, SearchResults;
import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../data/models.dart';
import '../../state/app_scope.dart';
import '../catalog/title_details_panel.dart';
import '../catalog/title_widgets.dart';
import '../live_tv/channel_card.dart';
import '../live_tv/live_player_page.dart';
import 'search_result_card.dart';

/// Resultados da busca do topo (filmes, séries e canais), por cima da página atual.
///
/// Desempenho: a busca roda num isolate; as listas de cada aba e as fileiras de
/// relacionados são montadas **uma vez** por resultado (não a cada rebuild); ao
/// digitar, os resultados anteriores continuam na tela até os novos chegarem
/// (nada de piscar uma tela vazia).
class SearchOverlay extends StatefulWidget {
  const SearchOverlay({super.key, required this.query});

  final String query;

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

/// Uma aba já pronta: resultados e relacionados (sem repetir os resultados).
class _TabView {
  _TabView({
    required this.shown,
    required this.movieRel,
    required this.seriesRel,
    this.channels = const [],
  })  : movieRelFuture = Future.value(movieRel),
        seriesRelFuture = Future.value(seriesRel);

  final List<CatalogTitle> shown;
  final List<LiveChannel> channels;
  final List<CatalogTitle> movieRel;
  final List<CatalogTitle> seriesRel;
  final Future<List<CatalogTitle>> movieRelFuture;
  final Future<List<CatalogTitle>> seriesRelFuture;
}

class _SearchOverlayState extends State<SearchOverlay> {
  Timer? _debounce;
  CatalogController? _catalog;
  String _active = '';
  int _seq = 0;
  bool _loading = false;

  /// 0 = Todos, 1 = Filmes, 2 = Séries, 3 = Canais.
  int _tab = 0;

  List<_TabView>? _views;
  bool _empty = true;

  /// Aba inicial conforme a tela de onde a busca foi aberta: TV ao vivo →
  /// Canais; Filmes e séries → a aba aberta lá (Filmes ou Séries); o resto →
  /// Todos.
  int _initialTab() {
    final app = AppScope.read(context);
    return switch (app.shellIndex) {
      1 => 3,
      2 => app.catalog.activeKind == CatalogKind.series ? 2 : 1,
      _ => 0,
    };
  }

  @override
  void initState() {
    super.initState();
    _tab = _initialTab();
    _schedule(immediate: true);
  }

  @override
  void didUpdateWidget(SearchOverlay old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _schedule();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _catalog?.cancelPrefetch();
    super.dispose();
  }

  void _schedule({bool immediate = false}) {
    _debounce?.cancel();
    void run() {
      final q = widget.query.trim();
      if (!mounted) return;
      final app = AppScope.read(context);
      final catalog = _catalog = app.catalog;
      final mine = ++_seq;
      setState(() => _loading = true);
      Future.wait([
        catalog.search(CatalogKind.movies, q),
        catalog.search(CatalogKind.series, q),
      ]).then((data) {
        // Resposta de uma busca antiga (já digitou mais): descarta.
        if (!mounted || mine != _seq) return;
        setState(() {
          _active = q;
          final channels = app.searchChannels(q);
          // Já começa a buscar as imagens horizontais dos primeiros resultados.
          catalog.prefetchBackdrops(
            SearchResults.closest(data[0], data[1], limit: 12),
          );
          _views = _buildViews(data[0], data[1], channels);
          _empty = data[0].isEmpty && data[1].isEmpty && channels.isEmpty;
          _loading = false;
        });
      }).catchError((Object _) {
        if (mounted && mine == _seq) setState(() => _loading = false);
      });
    }

    if (immediate) {
      run();
    } else {
      _debounce = Timer(const Duration(milliseconds: 250), run);
    }
  }

  static List<_TabView> _buildViews(
    SearchResults movies,
    SearchResults series,
    List<LiveChannel> channels,
  ) {
    // Resultado principal: filmes e séries juntos, do mais parecido ao menos
    // (se ninguém combina com tudo, os parciais mais próximos).
    final all = SearchResults.closest(movies, series, limit: 600);
    final onlyMovies = [for (final t in all) if (t.kind == CatalogKind.movies) t];
    final onlySeries = [for (final t in all) if (t.kind == CatalogKind.series) t];

    List<CatalogTitle> unseen(List<CatalogTitle> related, List<CatalogTitle> shown) {
      final ids = {for (final t in shown) '${t.kind.key}:${t.id}'};
      return [
        for (final t in related)
          if (!ids.contains('${t.kind.key}:${t.id}')) t,
      ];
    }

    return [
      // Todos: resultados, depois filmes e séries relacionados.
      _TabView(
        shown: all,
        movieRel: unseen(movies.related, all),
        seriesRel: unseen(series.related, all),
        channels: channels,
      ),
      // Filmes: só filmes relacionados (aparecem antes dos resultados).
      _TabView(
        shown: onlyMovies,
        movieRel: unseen(movies.related, onlyMovies),
        seriesRel: const [],
      ),
      // Séries: só séries relacionadas (aparecem antes dos resultados).
      _TabView(
        shown: onlySeries,
        movieRel: const [],
        seriesRel: unseen(series.related, onlySeries),
      ),
      // Canais: só canais ao vivo.
      _TabView(
        shown: const [],
        movieRel: const [],
        seriesRel: const [],
        channels: channels,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final views = _views;
    if (views == null) {
      return ColoredBox(
        color: AppColors.bg,
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    void open(CatalogTitle t) => showTitleDetails(context, t);
    final view = views[_tab];
    final shown = view.shown;
    final channelsTab = _tab == 3;
    final relatedFirst = _tab == 1 || _tab == 2;
    final hasRelated = view.movieRel.isNotEmpty || view.seriesRel.isNotEmpty;

    List<Widget> related() => [
          if (view.movieRel.isNotEmpty)
            SliverToBoxAdapter(
              child: TitleRow(
                key: ValueKey('s:mr:$_active:$_tab'),
                label: 'Filmes relacionados · ${view.movieRel.length}',
                future: view.movieRelFuture,
                onOpen: open,
              ),
            ),
          if (view.seriesRel.isNotEmpty)
            SliverToBoxAdapter(
              child: TitleRow(
                key: ValueKey('s:sr:$_active:$_tab'),
                label: 'Séries relacionadas · ${view.seriesRel.length}',
                future: view.seriesRelFuture,
                onOpen: open,
              ),
            ),
        ];

    void openChannel(LiveChannel ch, List<LiveChannel> list) {
      AppScope.read(context).selectChannel(ch);
      openLivePlayer(context, list);
    }

    // Aba Todos: até 12 canais com atalho para a aba Canais.
    List<Widget> channelSection() {
      final all = view.channels;
      if (all.isEmpty) return const [];
      final preview = all.length > 12 ? all.sublist(0, 12) : all;
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'CANAIS · ${all.length}',
                    style: AppFonts.title(20, spacing: 1),
                  ),
                ),
                if (all.length > preview.length)
                  TextButton(
                    onPressed: () => setState(() => _tab = 3),
                    child: const Text('Ver todos'),
                  ),
              ],
            ),
          ),
        ),
        _channelGrid(preview, all, openChannel),
      ];
    }

    Widget results() {
      // Aba Todos só com canais: a seção de canais já mostra o que há.
      if (shown.isEmpty && _tab == 0 && view.channels.isNotEmpty) {
        return const SliverToBoxAdapter(child: SizedBox.shrink());
      }
      if (shown.isEmpty) {
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Text(
              'Nenhum resultado direto nesta aba.',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
        );
      }
      return SliverLayoutBuilder(
        builder: (context, constraints) {
          const pad = 24.0, gap = 16.0, target = 300.0;
          final inner = constraints.crossAxisExtent - pad * 2;
          final cols = ((inner + gap) / (target + gap)).floor().clamp(1, 8);
          final w = (inner - gap * (cols - 1)) / cols;
          return SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: pad),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: gap,
                mainAxisSpacing: 12,
                mainAxisExtent: w * 9 / 16 + SearchResultCard.textHeight,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => SearchResultCard(
                  key: ValueKey('${shown[i].kind.key}:${shown[i].id}'),
                  title: shown[i],
                  onTap: () => open(shown[i]),
                ),
                childCount: shown.length,
                // Os cartões não mudam de posição: dispensa o trabalho extra
                // de manter vivos os que saem da tela.
                addAutomaticKeepAlives: false,
              ),
            ),
          );
        },
      );
    }

    return ColoredBox(
      color: AppColors.bg,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'RESULTADOS PARA “$_active”',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.title(22, spacing: 1),
                    ),
                  ),
                  if (_loading) ...[
                    const SizedBox(width: 12),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final (i, label) in const [
                    (0, 'Todos'),
                    (1, 'Filmes'),
                    (2, 'Séries'),
                    (3, 'Canais'),
                  ])
                    ChoiceChip(
                      label: Text(
                        '$label · ${switch (i) {
                          0 => views[0].shown.length + views[0].channels.length,
                          3 => views[0].channels.length,
                          _ => views[i].shown.length,
                        }}',
                      ),
                      selected: _tab == i,
                      onSelected: (_) => setState(() => _tab = i),
                    ),
                ],
              ),
            ),
          ),
          if (_empty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nada encontrado. A busca olha canais, filmes e séries '
                  'já baixados.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            )
          else if (channelsTab && views[3].channels.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Text(
                  'Nenhum canal encontrado.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            )
          else if (channelsTab)
            _channelGrid(views[3].channels, views[3].channels, openChannel)
          else ...[
            // Aba Todos: resultados, depois relacionados. Abas Filmes e Séries:
            // relacionados primeiro, depois os resultados.
            if (relatedFirst) ...related(),
            if (relatedFirst && hasRelated)
              const SliverToBoxAdapter(child: SearchDivider(label: 'Resultados')),
            results(),
            if (_tab == 0) ...channelSection(),
            if (!relatedFirst && hasRelated) ...[
              const SliverToBoxAdapter(
                child: SearchDivider(label: 'Também pode interessar'),
              ),
              ...related(),
            ],
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  /// Grade de canais (cartões 252×96, os mesmos da TV ao vivo).
  Widget _channelGrid(
    List<LiveChannel> shown,
    List<LiveChannel> playlist,
    void Function(LiveChannel, List<LiveChannel>) open,
  ) {
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
            key: ValueKey('ch:${shown[i].streamId}'),
            channel: shown[i],
            onTap: () => open(shown[i], playlist),
          ),
          childCount: shown.length,
          addAutomaticKeepAlives: false,
        ),
      ),
    );
  }
}
