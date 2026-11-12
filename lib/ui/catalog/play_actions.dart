import 'package:flutter/material.dart';

import '../../data/catalog_models.dart';
import '../../state/app_scope.dart';
import 'title_details_panel.dart';
import 'vod_player_page.dart';

/// "Assistir" a partir de um cartão ou banner: filme toca direto (retomando de
/// onde parou); série abre o painel de detalhes (escolha de episódio).
Future<void> watchTitle(BuildContext context, CatalogTitle t) async {
  final app = AppScope.read(context);
  if (t.kind == CatalogKind.series) {
    await showTitleDetails(context, t);
    return;
  }
  // Cartões de "continuar assistindo" não trazem a extensão: pede ao servidor.
  var ext = t.ext;
  if (ext == null) {
    final d = await app.catalog.detailsOrNull(t.kind, t.id);
    ext = d?.ext;
  }
  final url = app.downloads.localPath(CatalogKind.movies, t.id) ??
      app.catalog.movieUrl(t.id, ext ?? 'mp4');
  if (url == null) return;
  final p = await app.catalog.movieProgress(t.id);
  if (!context.mounted) return;
  await playItems(
    context,
    items: [
      PlayItem(
        kind: CatalogKind.movies,
        id: t.id,
        title: t.name,
        url: url,
        image: t.image,
      ),
    ],
    startAt:
        (p != null && p.canResume) ? Duration(milliseconds: p.positionMs) : null,
  );
  app.catalog.bumpProgress();
}

/// "Clique aqui para continuar assistindo": toca direto. Filme retoma de onde
/// parou; série abre o player no episódio em andamento ou, se o último
/// terminou, no próximo ([CatalogTitle.resumeEpisodeId]).
Future<void> resumeTitle(BuildContext context, CatalogTitle t) async {
  if (t.kind == CatalogKind.movies) return watchTitle(context, t);
  final app = AppScope.read(context);
  final d = await app.catalog.detailsOrNull(t.kind, t.id);
  if (!context.mounted) return;
  final items = <PlayItem>[];
  var index = -1;
  for (final list in d?.seasons.values ?? const <List<Episode>>[]) {
    for (final e in list) {
      final url = app.downloads.localPath(CatalogKind.series, e.id) ??
          app.catalog.episodeUrl(e.id, e.ext);
      if (url == null) continue;
      if (e.id == t.resumeEpisodeId) index = items.length;
      items.add(PlayItem(
        kind: CatalogKind.series,
        id: e.id,
        title: t.name,
        subtitle: '${e.code} — ${e.title}',
        url: url,
        image: t.image,
        seriesId: t.id,
        season: e.season,
        episode: e.number,
      ));
    }
  }
  if (index < 0) {
    // Sem os episódios (falha de rede) ou o episódio saiu do catálogo: abre o
    // card para o usuário escolher.
    await showTitleDetails(context, t);
    return;
  }
  final p = (await app.catalog.episodeProgress(t.id))[items[index].id];
  if (!context.mounted) return;
  await playItems(
    context,
    items: items,
    index: index,
    startAt:
        (p != null && p.canResume) ? Duration(milliseconds: p.positionMs) : null,
  );
  app.catalog.bumpProgress();
}
