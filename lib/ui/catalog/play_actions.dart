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
