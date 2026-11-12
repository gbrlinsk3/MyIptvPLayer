import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../downloads/download_models.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../downloads/download_button.dart';
import '../home/hero_buttons.dart';
import '../window/title_bar.dart';
import 'favorite_button.dart';
import 'poster_image.dart';
import 'vod_player_page.dart';
import '../widgets/common.dart';

/// Tela expandida com as informações de um filme ou série: imagem de fundo
/// grande, sinopse completa, elenco, ações e, nas séries, temporadas à direita
/// e episódios em cartões deitados embaixo.
Route<void> titleDetailsRoute(CatalogTitle title) {
  return PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, a, b) => TitleDetailsPage(title: title),
    // Só fade: mexer na escala de uma página inteira com imagem grande
    // obrigava a redesenhar tudo a cada quadro.
    transitionsBuilder: (context, animation, secondary, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: child,
    ),
  );
}

Future<void> showTitleDetailsPage(BuildContext context, CatalogTitle title) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    titleDetailsRoute(title),
  );
}

class TitleDetailsPage extends StatefulWidget {
  const TitleDetailsPage({super.key, required this.title});

  final CatalogTitle title;

  @override
  State<TitleDetailsPage> createState() => _TitleDetailsPageState();
}

class _TitleDetailsPageState extends State<TitleDetailsPage> {
  late Future<TitleDetails> _details;
  late Future<Object?> _progress;
  int _season = -1;
  final ScrollController _episodesScroll = ScrollController();

  // O conteúdo (textos e cartões) só é montado quando a animação de abertura
  // termina: durante ela só o fundo é desenhado, e a transição fica fluida.
  bool _ready = false;
  Animation<double>? _routeAnim;
  bool _hooked = false;

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _routeAnim?.removeStatusListener(_onRouteStatus);
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hooked) return;
    _hooked = true;
    final a = ModalRoute.of(context)?.animation;
    if (a == null || a.isCompleted) {
      _ready = true;
    } else {
      _routeAnim = a..addStatusListener(_onRouteStatus);
    }
  }

  void _selectSeason(int s) {
    setState(() => _season = s);
    if (_episodesScroll.hasClients) _episodesScroll.jumpTo(0);
  }

  bool get _isMovie => widget.title.kind == CatalogKind.movies;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _details = app.catalog.details(widget.title.kind, widget.title.id);
    _loadProgress(app);
    // Séries abrem na temporada do último episódio assistido.
    if (!_isMovie) {
      app.catalog.lastWatchedSeason(widget.title.id).then((s) {
        if (mounted && s != null && _season == -1) setState(() => _season = s);
      });
    }
  }

  @override
  void dispose() {
    _routeAnim?.removeStatusListener(_onRouteStatus);
    _episodesScroll.dispose();
    super.dispose();
  }

  void _loadProgress(AppController app) {
    _progress = _isMovie
        ? app.catalog.movieProgress(widget.title.id)
        : app.catalog.episodeProgress(widget.title.id);
  }

  void _reload() {
    final app = AppScope.read(context);
    setState(() => _loadProgress(app));
  }

  // ---- reprodução (mesma regra do painel lateral) -------------------------------

  PlayItem? _movieItem(AppController app, TitleDetails d) {
    final ext = d.ext ?? widget.title.ext ?? 'mp4';
    final url = app.downloads.localPath(CatalogKind.movies, widget.title.id) ??
        app.catalog.movieUrl(widget.title.id, ext);
    if (url == null) return null;
    return PlayItem(
      kind: CatalogKind.movies,
      id: widget.title.id,
      title: widget.title.name,
      url: url,
      image: widget.title.image ?? d.poster,
    );
  }

  PlayItem? _episodeItem(AppController app, Episode e) {
    final url = app.downloads.localPath(CatalogKind.series, e.id) ??
        app.catalog.episodeUrl(e.id, e.ext);
    if (url == null) return null;
    return PlayItem(
      kind: CatalogKind.series,
      id: e.id,
      title: widget.title.name,
      subtitle: '${e.code} — ${e.title}',
      url: url,
      image: widget.title.image,
      seriesId: widget.title.id,
      season: e.season,
      episode: e.number,
    );
  }

  List<Episode> _allEpisodes(TitleDetails d) => [
        for (final list in d.seasons.values) ...list,
      ];

  DownloadRequest _movieRequest(TitleDetails d) => DownloadRequest(
        kind: CatalogKind.movies,
        itemId: widget.title.id,
        title: widget.title.name,
        ext: d.ext ?? widget.title.ext ?? 'mp4',
        image: widget.title.image ?? d.poster,
        backdrop: d.backdrop,
      );

  DownloadRequest _episodeRequest(TitleDetails d, Episode e) => DownloadRequest(
        kind: CatalogKind.series,
        itemId: e.id,
        title: widget.title.name,
        subtitle: '${e.code} — ${e.title}',
        ext: e.ext,
        image: widget.title.image,
        backdrop: d.backdrop,
        seriesId: widget.title.id,
        season: e.season,
        episode: e.number,
      );

  Future<void> _playMovie(TitleDetails d, {Duration? startAt}) async {
    final app = AppScope.read(context);
    final item = _movieItem(app, d);
    if (item == null) return;
    await playItems(context, items: [item], startAt: startAt);
    if (mounted) _reload();
  }

  Future<void> _playEpisode(
    TitleDetails d,
    Episode episode,
    Map<int, WatchProgress> progress, {
    bool fromStart = false,
  }) async {
    final app = AppScope.read(context);
    final items = <PlayItem>[];
    var index = 0;
    for (final e in _allEpisodes(d)) {
      final item = _episodeItem(app, e);
      if (item == null) continue;
      if (e.id == episode.id) index = items.length;
      items.add(item);
    }
    if (items.isEmpty) return;
    final p = progress[episode.id];
    final start = (!fromStart && p != null && p.canResume)
        ? Duration(milliseconds: p.positionMs)
        : null;
    await playItems(context, items: items, index: index, startAt: start);
    if (mounted) _reload();
  }

  Future<void> _toggleWatchedMovie(TitleDetails d, bool watched) async {
    final app = AppScope.read(context);
    final item = _movieItem(app, d);
    if (item == null) return;
    await app.catalog.setWatched(item, !watched);
    if (mounted) _reload();
  }

  Future<void> _toggleWatchedEpisode(Episode e, bool watched) async {
    final app = AppScope.read(context);
    final item = _episodeItem(app, e);
    if (item == null) return;
    await app.catalog.setWatched(item, !watched);
    if (mounted) _reload();
  }

  /// Marca (ou desmarca) todos os episódios da série como assistidos.
  Future<void> _setAllWatched(TitleDetails d, bool watched) async {
    final ok = await confirmDialog(
      context,
      title: watched ? 'Marcar tudo como assistido?' : 'Desmarcar tudo?',
      message: watched
          ? 'Todos os episódios desta série serão marcados como assistidos.'
          : 'Todos os episódios deixam de constar como assistidos. A posição '
              'em que você parou em cada um é mantida.',
      action: watched ? 'Marcar todos' : 'Desmarcar todos',
    );
    if (!ok || !mounted) return;
    final app = AppScope.read(context);
    for (final e in _allEpisodes(d)) {
      final item = _episodeItem(app, e);
      if (item != null) await app.catalog.setWatched(item, watched);
    }
    if (mounted) _reload();
  }

  // ---- interface ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0D0C),
      body: Column(
        children: [
          TitleBar(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Voltar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Expanded(child: SizedBox.expand()),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<TitleDetails>(
              future: _details,
              builder: (context, snap) {
                final d = snap.data;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: _Backdrop(title: widget.title, details: d),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: [...previous, ?current],
                      ),
                      child: !_ready
                          ? const SizedBox.expand(key: ValueKey('wait'))
                          : FutureBuilder<Object?>(
                              key: const ValueKey('content'),
                              future: _progress,
                              builder: (context, pSnap) =>
                                  _body(d, snap, pSnap.data),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
    TitleDetails? d,
    AsyncSnapshot<TitleDetails> snap,
    Object? progress,
  ) {
    if (snap.connectionState != ConnectionState.done) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
        ),
      );
    }
    if (snap.hasError || d == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Não foi possível carregar os detalhes.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '${snap.error ?? ''}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 14),
            HeroGhostButton(
              label: 'Tentar de novo',
              onTap: () {
                final app = AppScope.read(context);
                setState(() => _details =
                    app.catalog.details(widget.title.kind, widget.title.id));
              },
            ),
          ],
        ),
      );
    }

    final map = progress is Map<int, WatchProgress>
        ? progress
        : const <int, WatchProgress>{};
    final seasons = d.seasons.keys.toList();
    final season = seasons.contains(_season)
        ? _season
        : (seasons.isEmpty ? -1 : seasons.first);
    final episodes = d.seasons[season] ?? const <Episode>[];

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 980;
        return Stack(
          children: [
            // Coluna de informações (esquerda), colada em cima dos episódios.
            Positioned(
              left: 56,
              top: 0,
              bottom: _isMovie ? 40 : 232,
              width: wide ? box.maxWidth * 0.5 : box.maxWidth - 112,
              child: Align(
                alignment: Alignment.bottomLeft,
                // Sem a barra de rolagem visível ao lado do texto.
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: _info(d, progress, map),
                  ),
                ),
              ),
            ),
            // Filme: "Baixar" (ícone + texto) no canto superior direito.
            if (_isMovie)
              Positioned(
                top: 16,
                right: 40,
                child: DownloadButton(
                  textStyle: true,
                  request: _movieRequest(d),
                  onOpenLibrary: () {
                    final app = AppScope.read(context);
                    Navigator.of(context).pop();
                    app.setShellIndex(4);
                  },
                ),
              ),
            // Série: desvanecer escuro à direita, só para dar contraste às
            // temporadas (não captura toques).
            if (!_isMovie && wide && seasons.isNotEmpty)
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: 340,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          const Color(0xFF0E0D0C).withValues(alpha: 0),
                          const Color(0xFF0E0D0C).withValues(alpha: 0.55),
                          const Color(0xFF0E0D0C).withValues(alpha: 0.88),
                        ],
                        stops: const [0, 0.55, 1],
                      ),
                    ),
                  ),
                ),
              ),
            // Temporadas (direita), como na referência.
            if (!_isMovie && wide && seasons.isNotEmpty)
              Positioned(
                right: 48,
                top: 24,
                bottom: 232,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final s in seasons)
                          _SeasonTab(
                            label: 'Temporada ${s.toString().padLeft(2, '0')}',
                            selected: s == season,
                            onTap: () => _selectSeason(s),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (!_isMovie)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 216,
                child: _episodesRow(d, season, seasons, episodes, map, wide),
              ),
          ],
        );
      },
    );
  }

  Widget _info(TitleDetails d, Object? progress, Map<int, WatchProgress> map) {
    final t = widget.title;
    final year = d.year ?? t.year;
    final rating = d.rating ?? t.rating;
    final chips = <String>[
      _isMovie ? 'Filme' : 'Série',
      if (year != null && year.isNotEmpty) year,
      if (d.genre != null && d.genre!.isNotEmpty) d.genre!,
      if (_isMovie && d.durationLabel != null && d.durationLabel!.isNotEmpty)
        d.durationLabel!,
      if (!_isMovie && d.seasons.isNotEmpty)
        '${d.seasons.length} ${d.seasons.length == 1 ? 'temporada' : 'temporadas'}',
      if (!_isMovie && _allEpisodes(d).isNotEmpty)
        '${_allEpisodes(d).length} episódios',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          t.name.toUpperCase(),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppFonts.title(60, color: Colors.white, spacing: 1),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (rating != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '★ ${rating.toStringAsFixed(1)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            for (final c in chips)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white38),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  c,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if ((d.plot ?? t.plot) != null)
          Text(
            (d.plot ?? t.plot)!,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 14, height: 1.55),
          ),
        if (d.cast != null && d.cast!.isNotEmpty) ...[
          const SizedBox(height: 14),
          _labeled('Elenco', d.cast!),
        ],
        if (d.director != null && d.director!.isNotEmpty) ...[
          const SizedBox(height: 6),
          _labeled('Direção', d.director!),
        ],
        const SizedBox(height: 22),
        _actions(d, progress, map),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _labeled(String label, String value) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label: ', style: const TextStyle(color: Colors.white54)),
          TextSpan(text: value, style: const TextStyle(color: Colors.white)),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12.5, height: 1.4),
    );
  }

  Widget _actions(TitleDetails d, Object? progress, Map<int, WatchProgress> map) {
    if (_isMovie) {
      final p = progress is WatchProgress ? progress : null;
      final resume = p != null && p.canResume;
      return Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          HeroPrimaryButton(
            label: resume
                ? 'Continuar ${formatDuration(Duration(milliseconds: p.positionMs))}'
                : 'Assistir',
            onTap: () => _playMovie(
              d,
              startAt: resume ? Duration(milliseconds: p.positionMs) : null,
            ),
          ),
          if (resume)
            HeroGhostButton(label: 'Do início', onTap: () => _playMovie(d)),
          FavoriteHeroButton(title: widget.title),
          HeroGhostButton(
            icon: (p?.watched ?? false)
                ? Icons.check_circle
                : Icons.check_circle_outline,
            label: (p?.watched ?? false) ? 'Assistido' : 'Marcar como assistido',
            onTap: () => _toggleWatchedMovie(d, p?.watched ?? false),
          ),
        ],
      );
    }

    final all = _allEpisodes(d);
    if (all.isEmpty) {
      return const Text(
        'O provedor não informou episódios para esta série.',
        style: TextStyle(color: Colors.white54),
      );
    }
    Episode target = all.first;
    for (final e in all) {
      if (!(map[e.id]?.watched ?? false)) {
        target = e;
        break;
      }
    }
    final p = map[target.id];
    final resume = p != null && p.canResume;
    const linkStyle = TextStyle(fontSize: 12);
    ButtonStyle link() => TextButton.styleFrom(
          foregroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            HeroPrimaryButton(
              label: resume
                  ? 'Continuar ${target.code}'
                  : 'Assistir ${target.code}',
              onTap: () => _playEpisode(d, target, map),
            ),
            if (resume)
              HeroGhostButton(
                label: 'Do início',
                onTap: () => _playEpisode(d, target, map, fromStart: true),
              ),
            FavoriteHeroButton(title: widget.title),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              style: link(),
              onPressed: () => _setAllWatched(d, true),
              icon: const Icon(Icons.done_all, size: 16),
              label: const Text('Marcar todos como assistidos', style: linkStyle),
            ),
            TextButton.icon(
              style: link(),
              onPressed: () => _setAllWatched(d, false),
              icon: const Icon(Icons.remove_done, size: 16),
              label: const Text('Desmarcar todos como assistidos', style: linkStyle),
            ),
          ],
        ),
      ],
    );
  }

  // ---- episódios -----------------------------------------------------------------------

  Widget _episodesRow(
    TitleDetails d,
    int season,
    List<int> seasons,
    List<Episode> episodes,
    Map<int, WatchProgress> map,
    bool wide,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 0, 48, 8),
          child: Row(
            children: [
              Text(
                'EPISÓDIOS',
                style: AppFonts.title(22, color: Colors.white, spacing: 1.2),
              ),
              const SizedBox(width: 12),
              // Janela estreita: sem a lista à direita, as temporadas viram menu.
              if (!wide && seasons.length > 1)
                PopupMenuButton<int>(
                  tooltip: 'Temporada',
                  color: AppColors.surface,
                  onSelected: _selectSeason,
                  itemBuilder: (context) => [
                    for (final s in seasons)
                      PopupMenuItem<int>(value: s, child: Text('Temporada $s')),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Temporada $season',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    ],
                  ),
                )
              else
                Text(
                  'Temporada $season',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => AppScope.read(context).downloads.enqueueAll([
                  for (final e in episodes) _episodeRequest(d, e),
                ]),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Baixar temporada'),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
              _RoundArrow(
                icon: Icons.chevron_left,
                onTap: () => _scrollEpisodes(-1),
              ),
              const SizedBox(width: 8),
              _RoundArrow(
                icon: Icons.chevron_right,
                onTap: () => _scrollEpisodes(1),
              ),
            ],
          ),
        ),
        Expanded(
          child: TweenAnimationBuilder<double>(
            key: ValueKey('season:$season'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            builder: (context, v, child) => Opacity(opacity: v, child: child),
            child: ListView.builder(
            controller: _episodesScroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(56, 6, 48, 6),
            itemCount: episodes.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(right: 14),
              child: RepaintBoundary(
                child: _EpisodeCard(
                key: ValueKey(episodes[i].id),
                episode: episodes[i],
                banner: d.backdrop ?? d.poster ?? widget.title.image,
                ownImage: _ownImage(d, episodes[i]),
                progress: map[episodes[i].id],
                request: _episodeRequest(d, episodes[i]),
                onPlay: () => _playEpisode(d, episodes[i], map),
                onToggleWatched: () => _toggleWatchedEpisode(
                  episodes[i],
                  map[episodes[i].id]?.watched ?? false,
                ),
              ),
              ),
            ),
          ),
          ),
        ),
      ],
    );
  }

  void _scrollEpisodes(int dir) {
    if (!_episodesScroll.hasClients) return;
    final target = (_episodesScroll.offset + dir * 520)
        .clamp(0.0, _episodesScroll.position.maxScrollExtent);
    _episodesScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  String? _ownImage(TitleDetails d, Episode e) {
    final u = e.image?.trim();
    if (u == null || !(u.startsWith('http://') || u.startsWith('https://'))) {
      return null;
    }
    if (u == widget.title.image || u == d.poster || u == d.backdrop) return null;
    return u;
  }
}

/// Fundo da tela: pôster borrado na hora, imagem horizontal grande por cima
/// quando chega (tenta a versão grande do TMDB e cai para o endereço original).
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.title, required this.details});

  final CatalogTitle title;
  final TitleDetails? details;

  @override
  Widget build(BuildContext context) {
    final bd = details?.backdrop;
    final poster = title.image ?? details?.poster;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (poster != null)
          SoftBlurBackdrop(url: poster)
        else
          const ColoredBox(color: Color(0xFF141312)),
        if (bd != null && bd.isNotEmpty)
          ChainImage(
            key: ValueKey(bd),
            urls: [
              if (tmdbSize(bd, 'w1280') != bd) tmdbSize(bd, 'w1280')!,
              bd,
            ],
            cacheWidth: 1600,
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xF0000000), Color(0xAA000000), Color(0x22000000)],
              stops: [0, 0.5, 1],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xFF0E0D0C)],
              stops: [0.45, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _SeasonTab extends StatefulWidget {
  const _SeasonTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SeasonTab> createState() => _SeasonTabState();
}

class _SeasonTabState extends State<_SeasonTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: AppFonts.title(
                  sel ? 28 : 22,
                  color: sel
                      ? Colors.white
                      : Colors.white.withValues(alpha: _hover ? 0.75 : 0.35),
                  spacing: 1,
                ),
                child: Text(widget.label.toUpperCase()),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(left: 12),
                width: sel ? 38 : 0,
                height: 2,
                color: AppColors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundArrow extends StatelessWidget {
  const _RoundArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white54),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _EpisodeCard extends StatefulWidget {
  const _EpisodeCard({
    super.key,
    required this.episode,
    required this.banner,
    required this.ownImage,
    required this.progress,
    required this.request,
    required this.onPlay,
    required this.onToggleWatched,
  });

  final Episode episode;
  final String? banner;
  final String? ownImage;
  final WatchProgress? progress;
  final DownloadRequest request;
  final VoidCallback onPlay;
  final VoidCallback onToggleWatched;

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.episode;
    final p = widget.progress;
    final watched = p?.watched ?? false;
    final minutes = e.durationSecs == null ? null : (e.durationSecs! / 60).round();
    return SizedBox(
      width: 240,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPlay,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedScale(
                scale: _hover ? 1.04 : 1,
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOutCubic,
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _hover ? AppColors.accent : Colors.white12,
                      width: _hover ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PosterImage(url: widget.banner, name: e.code, cacheWidth: 520),
                      if (widget.ownImage != null)
                        ChainImage(
                          key: ValueKey('pe:${e.id}'),
                          urls: [widget.ownImage!],
                          cacheWidth: 520,
                        ),
                      // Já assistido: imagem mais escura e o ícone de "assistido"
                      // sempre visível (sem precisar passar o mouse).
                      if (watched && !_hover) ...[
                        const ColoredBox(color: Color(0x99000000)),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Icon(
                            Icons.check_circle,
                            size: 22,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                      if (_hover) ...[
                        const _FadeIn(
                          child: ColoredBox(
                            color: Color(0x66000000),
                            child: Center(
                              child: Icon(
                                Icons.play_circle_fill_rounded,
                                size: 46,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        // Ações rápidas só existem enquanto o mouse está em cima
                        // (antes cada cartão mantinha um botão de download vivo).
                        Positioned(
                          top: 2,
                          right: 2,
                          child: _FadeIn(
                            child: Row(
                              children: [
                                DownloadButton(
                                  request: widget.request,
                                  compact: true,
                                ),
                                IconButton(
                                  tooltip: watched
                                      ? 'Desmarcar como assistido'
                                      : 'Marcar como assistido',
                                  onPressed: widget.onToggleWatched,
                                  icon: Icon(
                                    watched
                                        ? Icons.check_circle
                                        : Icons.check_circle_outline,
                                    size: 20,
                                    color:
                                        watched ? AppColors.accent : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (p != null && p.canResume)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: p.fraction,
                            minHeight: 4,
                            backgroundColor: const Color(0x99000000),
                            color: AppColors.accent,
                          ),
                        )
                      else if (watched)
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ColoredBox(
                            color: Color(0x99FFFFFF),
                            child: SizedBox(height: 3),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${e.number}. ${e.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: watched ? Colors.white38 : Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (minutes != null && minutes > 0)
                Text(
                  '$minutes min',
                  style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 150),
      builder: (context, v, child) => Opacity(opacity: v, child: child),
      child: child,
    );
  }
}
