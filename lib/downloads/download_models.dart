import '../data/catalog_models.dart';

enum DownloadStatus {
  queued,
  downloading,
  paused,
  done,
  error;

  static DownloadStatus parse(String? v) => DownloadStatus.values.firstWhere(
        (s) => s.name == v,
        orElse: () => DownloadStatus.paused,
      );
}

/// O que baixar: um filme ou um episódio, com o necessário para montar o
/// endereço, o nome do arquivo e o cartão da biblioteca.
class DownloadRequest {
  const DownloadRequest({
    required this.kind,
    required this.itemId,
    required this.title,
    required this.ext,
    this.subtitle,
    this.image,
    this.backdrop,
    this.seriesId,
    this.season,
    this.episode,
  });

  final CatalogKind kind;

  /// stream_id do filme ou id do episódio.
  final int itemId;

  /// Filme: o nome. Episódio: o nome da série.
  final String title;
  final String ext;
  final String? subtitle;
  final String? image;
  final String? backdrop;
  final int? seriesId;
  final int? season;
  final int? episode;
}

/// Um download (em andamento, pausado, com erro ou concluído).
class DownloadEntry {
  DownloadEntry({
    this.id,
    required this.kind,
    required this.itemId,
    required this.title,
    required this.ext,
    required this.filePath,
    required this.status,
    required this.createdAt,
    this.subtitle,
    this.image,
    this.backdrop,
    this.seriesId,
    this.season,
    this.episode,
    this.totalBytes = 0,
    this.doneBytes = 0,
    this.error,
    this.completedAt,
  });

  int? id;
  final CatalogKind kind;
  final int itemId;
  final String title;
  final String ext;
  final String? subtitle;
  final String? image;

  /// Imagem horizontal (cartões deitados da biblioteca); pode faltar.
  final String? backdrop;
  final int? seriesId;
  final int? season;
  final int? episode;

  /// Caminho do arquivo final (durante o download o app grava em `<caminho>.part`).
  String filePath;
  int totalBytes;
  int doneBytes;
  DownloadStatus status;
  String? error;
  final int createdAt;
  int? completedAt;

  /// Velocidade atual em bytes/s (só em memória).
  double speed = 0;

  bool get isDone => status == DownloadStatus.done;
  bool get isMovie => kind == CatalogKind.movies;

  /// 0..1; nulo quando o servidor não informou o tamanho total.
  double? get fraction =>
      totalBytes > 0 ? (doneBytes / totalBytes).clamp(0.0, 1.0).toDouble() : null;

  String get key => '${kind.progressKind}:$itemId';

  String get code => (season != null && episode != null)
      ? 'T$season · E$episode'
      : '';

  Map<String, Object?> toRow() => {
        'kind': kind.progressKind,
        'item_id': itemId,
        'series_id': seriesId,
        'season': season,
        'episode': episode,
        'title': title,
        'subtitle': subtitle,
        'image': image,
        'backdrop': backdrop,
        'ext': ext,
        'file_path': filePath,
        'total_bytes': totalBytes,
        'done_bytes': doneBytes,
        'status': status.name,
        'error': error,
        'created_at': createdAt,
        'completed_at': completedAt,
      };

  static DownloadEntry fromRow(Map<String, Object?> r) => DownloadEntry(
        id: r['id'] as int?,
        kind: (r['kind'] as String?) == 'vod'
            ? CatalogKind.movies
            : CatalogKind.series,
        itemId: r['item_id'] as int,
        seriesId: r['series_id'] as int?,
        season: r['season'] as int?,
        episode: r['episode'] as int?,
        title: (r['title'] as String?) ?? '',
        subtitle: r['subtitle'] as String?,
        image: r['image'] as String?,
        backdrop: r['backdrop'] as String?,
        ext: (r['ext'] as String?) ?? 'mp4',
        filePath: r['file_path'] as String,
        totalBytes: (r['total_bytes'] as int?) ?? 0,
        doneBytes: (r['done_bytes'] as int?) ?? 0,
        status: DownloadStatus.parse(r['status'] as String?),
        error: r['error'] as String?,
        createdAt: (r['created_at'] as int?) ?? 0,
        completedAt: r['completed_at'] as int?,
      );
}
