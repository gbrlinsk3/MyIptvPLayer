import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../../downloads/download_models.dart';
import '../downloads/download_button.dart';
import 'favorite_button.dart';
import 'poster_image.dart';
import 'title_details_page.dart';
import 'vod_player_page.dart';

/// Painel de detalhes que desliza da direita (filme ou série).
Future<void> showTitleDetails(BuildContext context, CatalogTitle title) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _DetailsPanel(title: title),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: RepaintBoundary(child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.35, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        )),
      );
    },
  );
}

class _DetailsPanel extends StatefulWidget {
  const _DetailsPanel({required this.title});

  final CatalogTitle title;

  @override
  State<_DetailsPanel> createState() => _DetailsPanelState();
}

class _DetailsPanelState extends State<_DetailsPanel> {
  late Future<TitleDetails> _details;
  late Future<Object?> _progress;
  int _season = -1;

  bool get _isMovie => widget.title.kind == CatalogKind.movies;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _details = app.catalog.details(widget.title.kind, widget.title.id);
    _loadProgress(app);
    _openLastSeason(app);
  }

  /// Séries abrem na temporada do último episódio assistido.
  void _openLastSeason(AppController app) {
    if (_isMovie) return;
    app.catalog.lastWatchedSeason(widget.title.id).then((s) {
      if (mounted && s != null && _season == -1) setState(() => _season = s);
    });
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

  void _retryDetails() {
    final app = AppScope.read(context);
    setState(() => _details = app.catalog.details(widget.title.kind, widget.title.id));
  }

  // ---- reprodução -----------------------------------------------------------------

  PlayItem? _movieItem(AppController app, TitleDetails d) {
    final ext = d.ext ?? widget.title.ext ?? 'mp4';
    // Arquivo baixado tem prioridade (toca sem internet).
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

  /// Fecha o painel e abre "Minha biblioteca".
  void _openLibrary() {
    final app = AppScope.read(context);
    Navigator.of(context).pop();
    app.setShellIndex(4);
  }

  List<Episode> _allEpisodes(TitleDetails d) => [
        for (final list in d.seasons.values) ...list,
      ];

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
    final all = _allEpisodes(d);
    final items = <PlayItem>[];
    var index = 0;
    for (final e in all) {
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

  // ---- interface ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 520,
          child: Material(
            color: AppColors.surface,
            elevation: 8,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.border),
            ),
            child: FutureBuilder<TitleDetails>(
              future: _details,
              builder: (context, snap) {
                final loading = snap.connectionState != ConnectionState.done;
                final d = snap.data;
                return FutureBuilder<Object?>(
                  future: _progress,
                  builder: (context, pSnap) => _content(
                    d,
                    loading: loading,
                    error: snap.hasError ? '${snap.error}' : null,
                    progress: pSnap.data,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(
    TitleDetails? d, {
    required bool loading,
    required String? error,
    required Object? progress,
  }) {
    final t = widget.title;
    final dd = d ?? const TitleDetails();
    final plot = d?.plot ?? t.plot;
    final backdrop = d?.backdrop ?? d?.poster ?? t.image;

    final meta = <String>[
      if ((d?.year ?? t.year) != null) (d?.year ?? t.year)!,
      if ((d?.rating ?? t.rating) != null)
        '★ ${(d?.rating ?? t.rating)!.toStringAsFixed(1)}',
      if (_isMovie && d?.durationLabel != null) d!.durationLabel!,
      if (d?.genre != null) d!.genre!,
    ];

    return Column(
      children: [
        // ---- imagem de topo --------------------------------------------------
        SizedBox(
          height: 230,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PosterImage(url: backdrop, name: t.name, cacheWidth: 1040),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.surface.withValues(alpha: 0),
                      AppColors.surface,
                    ],
                    stops: const [0.55, 1],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    FavoritePanelButton(title: widget.title),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      tooltip: 'Expandir informações',
                      onPressed: () {
                        // Substitui o painel pela tela expandida: uma só
                        // animação (o painel some por baixo do fade).
                        Navigator.of(context, rootNavigator: true)
                            .pushReplacement<void, void>(
                          titleDetailsRoute(widget.title),
                        );
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0x99000000),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.open_in_full, size: 18),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0x99000000),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // ---- corpo rolável ------------------------------------------------------
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Text(
                t.name,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  meta.join('  •  '),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (error != null)
                _errorBox(error)
              else ...[
                _actions(dd, progress),
                const SizedBox(height: 16),
                if (plot != null)
                  Text(plot, style: const TextStyle(fontSize: 13.5, height: 1.45)),
                if (dd.cast != null) ...[
                  const SizedBox(height: 12),
                  _labeled('Elenco', dd.cast!),
                ],
                if (dd.director != null) ...[
                  const SizedBox(height: 8),
                  _labeled('Direção', dd.director!),
                ],
                if (!_isMovie) ...[
                  const SizedBox(height: 20),
                  _episodes(dd, progress is Map<int, WatchProgress> ? progress : const {}),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _errorBox(String message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Não foi possível carregar os detalhes.',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.danger, fontSize: 12),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _retryDetails, child: const Text('Tentar de novo')),
      ],
    );
  }

  Widget _labeled(String label, String value) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(color: AppColors.textMuted),
          ),
          TextSpan(text: value),
        ],
      ),
      style: const TextStyle(fontSize: 12.5, height: 1.4),
    );
  }

  // ---- botões ----------------------------------------------------------------------------

  Widget _actions(TitleDetails d, Object? progress) {
    if (_isMovie) {
      final p = progress is WatchProgress ? progress : null;
      final resume = p != null && p.canResume;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => _playMovie(
              d,
              startAt: resume ? Duration(milliseconds: p.positionMs) : null,
            ),
            icon: const Icon(Icons.play_arrow),
            label: Text(
              resume
                  ? 'Continuar (${formatDuration(Duration(milliseconds: p.positionMs))})'
                  : 'Assistir',
            ),
          ),
          if (resume)
            OutlinedButton(
              onPressed: () => _playMovie(d),
              child: const Text('Do início'),
            ),
          DownloadButton(
            request: _movieRequest(d),
            onOpenLibrary: _openLibrary,
          ),
          TextButton.icon(
            onPressed: () => _toggleWatchedMovie(d, p?.watched ?? false),
            icon: Icon(
              (p?.watched ?? false)
                  ? Icons.check_circle
                  : Icons.check_circle_outline,
              size: 18,
            ),
            label: Text(
              (p?.watched ?? false) ? 'Assistido' : 'Marcar como assistido',
            ),
          ),
        ],
      );
    }

    final map = progress is Map<int, WatchProgress> ? progress : const <int, WatchProgress>{};
    final all = _allEpisodes(d);
    if (all.isEmpty) {
      return Text(
        'O provedor não informou episódios para esta série.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
      );
    }
    // Próximo a assistir: o primeiro episódio ainda não assistido.
    Episode target = all.first;
    for (final e in all) {
      if (!(map[e.id]?.watched ?? false)) {
        target = e;
        break;
      }
    }
    final p = map[target.id];
    final resume = p != null && p.canResume;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => _playEpisode(d, target, map),
          icon: const Icon(Icons.play_arrow),
          label: Text(
            resume
                ? 'Continuar ${target.code} (${formatDuration(Duration(milliseconds: p.positionMs))})'
                : 'Assistir ${target.code}',
          ),
        ),
        if (resume)
          OutlinedButton(
            onPressed: () => _playEpisode(d, target, map, fromStart: true),
            child: const Text('Do início'),
          ),
      ],
    );
  }

  // ---- episódios ---------------------------------------------------------------------------

  Widget _episodes(TitleDetails d, Map<int, WatchProgress> progress) {
    if (d.seasons.isEmpty) return const SizedBox.shrink();
    final seasons = d.seasons.keys.toList();
    final current = seasons.contains(_season) ? _season : seasons.first;
    final list = d.seasons[current] ?? const <Episode>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Episódios',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                AppScope.read(context).downloads.enqueueAll([
                  for (final e in list) _episodeRequest(d, e),
                ]);
              },
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Baixar temporada'),
            ),
            if (seasons.length > 1)
              PopupMenuButton<int>(
                tooltip: 'Temporada',
                color: AppColors.surface,
                onSelected: (v) => setState(() => _season = v),
                itemBuilder: (context) => [
                  for (final s in seasons)
                    PopupMenuItem<int>(value: s, child: Text('Temporada $s')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Temporada $current',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              )
            else
              Text(
                'Temporada $current',
                style: TextStyle(color: AppColors.textMuted),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final e in list) _episodeRow(d, e, progress),
      ],
    );
  }

  /// Miniatura própria do episódio, ou nulo se o provedor não deu uma utilizável.
  String? _ownImage(TitleDetails d, Episode e) {
    final u = e.image?.trim();
    if (u == null || !(u.startsWith('http://') || u.startsWith('https://'))) {
      return null;
    }
    if (u == widget.title.image || u == d.poster || u == d.backdrop) return null;
    return u;
  }

  Widget _episodeRow(TitleDetails d, Episode e, Map<int, WatchProgress> progress) {
    final p = progress[e.id];
    final watched = p?.watched ?? false;
    final minutes = e.durationSecs == null ? null : (e.durationSecs! / 60).round();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _playEpisode(d, e, progress),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              height: 63,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Fundo: banner da série. Por cima, a miniatura do episódio, só
                    // se o provedor informou uma própria (não vazia, nem a capa da
                    // série repetida); se faltar ou falhar ao carregar, fica o banner.
                    PosterImage(
                      url: d.backdrop ?? d.poster ?? widget.title.image,
                      name: e.code,
                      cacheWidth: 240,
                    ),
                    if (_ownImage(d, e) != null)
                      ChainImage(
                        key: ValueKey('ep:${e.id}'),
                        urls: [_ownImage(d, e)!],
                        cacheWidth: 240,
                      ),
                    if (p != null && p.canResume)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: p.fraction,
                          minHeight: 3,
                          backgroundColor: const Color(0x99000000),
                          color: AppColors.accent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.number}. ${e.title}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: watched ? AppColors.textMuted : AppColors.text,
                    ),
                  ),
                  if (minutes != null && minutes > 0)
                    Text(
                      '$minutes min',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  if (e.plot != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        e.plot!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            DownloadButton(
              request: _episodeRequest(d, e),
              compact: true,
              onOpenLibrary: _openLibrary,
            ),
            IconButton(
              tooltip: watched ? 'Desmarcar como assistido' : 'Marcar como assistido',
              onPressed: () => _toggleWatchedEpisode(e, watched),
              icon: Icon(
                watched ? Icons.check_circle : Icons.check_circle_outline,
                size: 20,
                color: watched ? AppColors.accent : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
