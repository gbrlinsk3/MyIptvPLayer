import 'models.dart' show foldText;

/// Tipos de conteúdo sob demanda (VOD) do catálogo.
enum CatalogKind {
  movies,
  series;

  /// Tabela de itens no SQLite.
  String get itemsTable => this == movies ? 'vod_items' : 'series_items';

  /// Tabela de categorias no SQLite.
  String get categoriesTable =>
      this == movies ? 'vod_categories' : 'series_categories';

  /// Valor da coluna `kind` em `hidden_categories` e prefixo de ajustes.
  String get key => this == movies ? 'vod' : 'series';

  String get label => this == movies ? 'Filmes' : 'Séries';

  /// Valor da coluna `kind` em `watch_progress`.
  String get progressKind => this == movies ? 'vod' : 'episode';
}

/// Uma linha do histórico: a **última** vez que um filme ou episódio foi
/// assistido (o app não guarda um registro de cada sessão).
class HistoryRow {
  const HistoryRow({
    required this.progressKind,
    required this.itemId,
    required this.positionMs,
    required this.durationMs,
    required this.watched,
    required this.updatedAt,
    required this.title,
    this.subtitle,
    this.image,
    this.seriesId,
  });

  /// `vod` (filme) ou `episode`.
  final String progressKind;
  final int itemId;
  final int positionMs;
  final int durationMs;
  final bool watched;
  final int updatedAt;
  final String title;
  final String? subtitle;
  final String? image;
  final int? seriesId;

  bool get isMovie => progressKind == 'vod';

  double get fraction =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0).toDouble();

  /// Título para abrir os detalhes (para episódio, a série).
  CatalogTitle toTitle() => CatalogTitle(
        kind: isMovie ? CatalogKind.movies : CatalogKind.series,
        id: isMovie ? itemId : (seriesId ?? itemId),
        name: title,
        categoryId: '',
        image: image,
      );
}

/// Um filme ou uma série da lista (sem detalhes).
class CatalogTitle {
  CatalogTitle({
    required this.kind,
    required this.id,
    required this.name,
    required this.categoryId,
    this.image,
    this.rating,
    this.added,
    this.ext,
    this.year,
    this.plot,
    this.positionMs,
    this.durationMs,
    this.subtitle,
    this.updatedAt,
    this.resumeEpisodeId,
  }) : searchKey = foldText(name);

  final CatalogKind kind;

  /// stream_id (filme) ou series_id (série).
  final int id;
  final String name;
  final String categoryId;
  final String? image;

  /// Nota de 0 a 10, quando o provedor informa.
  final double? rating;

  /// Data de inclusão/atualização (segundos desde 1970), quando informada.
  final int? added;

  /// Extensão do arquivo do filme (container_extension). Nula para séries.
  final String? ext;
  final String? year;
  final String? plot;

  /// Só nas fileiras "Continuar assistindo": onde parou.
  final int? positionMs;
  final int? durationMs;
  final String? subtitle;

  /// Só em "continuar assistindo": quando foi assistido (ms desde 1970).
  final int? updatedAt;

  /// Só em séries do "continuar assistindo": o episódio a retomar (o que está
  /// em andamento ou, se o último terminou, o próximo).
  final int? resumeEpisodeId;

  final String searchKey;

  double? get progress {
    final p = positionMs;
    final d = durationMs;
    if (p == null || d == null || d <= 0) return null;
    return (p / d).clamp(0.0, 1.0).toDouble();
  }
}

/// O último episódio mexido de uma série (assistido ou em andamento): base do
/// "Continuar assistindo" das séries.
class SeriesActivity {
  const SeriesActivity({
    required this.seriesId,
    required this.episodeId,
    required this.season,
    required this.episode,
    required this.watched,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
    required this.title,
    this.subtitle,
    this.image,
  });

  final int seriesId;
  final int episodeId;
  final int? season;
  final int? episode;

  /// Terminado (ou marcado como assistido): o que vem a seguir é o próximo.
  final bool watched;
  final int positionMs;
  final int durationMs;
  final int updatedAt;
  final String title;
  final String? subtitle;
  final String? image;
}

/// Detalhes de um filme ou de uma série (get_vod_info / get_series_info).
class TitleDetails {
  const TitleDetails({
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.year,
    this.rating,
    this.durationLabel,
    this.durationSecs,
    this.backdrop,
    this.poster,
    this.ext,
    this.seasons = const {},
  });

  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? year;
  final double? rating;
  final String? durationLabel;
  final int? durationSecs;
  final String? backdrop;
  final String? poster;

  /// Extensão do arquivo (filmes).
  final String? ext;

  /// Temporada → episódios (séries).
  final Map<int, List<Episode>> seasons;
}

class Episode {
  const Episode({
    required this.id,
    required this.season,
    required this.number,
    required this.title,
    required this.ext,
    this.image,
    this.plot,
    this.durationSecs,
  });

  final int id;
  final int season;
  final int number;
  final String title;
  final String ext;
  final String? image;
  final String? plot;
  final int? durationSecs;

  String get code =>
      'T$season · E$number';
}

/// Progresso salvo de um filme ou episódio.
class WatchProgress {
  const WatchProgress({
    required this.positionMs,
    required this.durationMs,
    required this.watched,
  });

  final int positionMs;
  final int durationMs;
  final bool watched;

  /// Dá para retomar de onde parou (mesmo se já marcado como assistido: só
  /// volta ao início quando o vídeo foi assistido até o fim, que grava 0).
  bool get canResume => positionMs > 5000;

  double get fraction =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0).toDouble();
}

/// Algo que o player de filmes/séries sabe reproduzir.
class PlayItem {
  const PlayItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.url,
    this.subtitle,
    this.image,
    this.seriesId,
    this.season,
    this.episode,
  });

  final CatalogKind kind;

  /// stream_id do filme ou id do episódio.
  final int id;

  /// Filme: o nome. Episódio: o nome da série.
  final String title;
  final String? subtitle;
  final String url;

  /// Pôster (filme) ou capa da série (episódio).
  final String? image;
  final int? seriesId;
  final int? season;
  final int? episode;
}
