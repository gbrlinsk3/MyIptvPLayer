import 'dart:convert';
import 'dart:typed_data';

import 'catalog_models.dart';
import 'models.dart';

/// Tudo aqui segue a convenção do Xtream Codes e NÃO foi verificado contra o
/// servidor do usuário. Os campos são lidos de forma tolerante (ausente = nulo).

class ParseTitlesJob {
  const ParseTitlesJob(this.bytes, this.kind);

  final Uint8List bytes;
  final CatalogKind kind;
}

String? _text(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  if (s.isEmpty || s == 'null') return null;
  return s;
}

double? _rating(Object? value) {
  final v = double.tryParse(_text(value) ?? '');
  if (v == null || v <= 0) return null;
  return v > 10 ? 10 : v;
}

int? _int(Object? value) => int.tryParse(_text(value) ?? '');

String? _year(Object? value) {
  final s = _text(value);
  if (s == null) return null;
  final m = RegExp(r'(19|20)\d{2}').firstMatch(s);
  return m?.group(0);
}

Object? _decode(Uint8List bytes) =>
    jsonDecode(utf8.decode(bytes, allowMalformed: true));

List<LiveCategory> parseVodCategories(Uint8List bytes) {
  final data = _decode(bytes);
  if (data is! List) return const [];
  final out = <LiveCategory>[];
  for (final item in data) {
    if (item is! Map) continue;
    final id = _text(item['category_id']);
    final name = _text(item['category_name']);
    if (id == null || name == null) continue;
    out.add(LiveCategory(id: id, name: name));
  }
  return out;
}

/// Lista de filmes (get_vod_streams) ou de séries (get_series).
List<CatalogTitle> parseTitles(ParseTitlesJob job) {
  final data = _decode(job.bytes);
  if (data is! List) return const [];
  final movies = job.kind == CatalogKind.movies;
  final out = <CatalogTitle>[];
  for (final item in data) {
    if (item is! Map) continue;
    final id = _int(movies ? item['stream_id'] : item['series_id']);
    if (id == null) continue;
    final name = _text(item['name']) ?? (movies ? 'Filme $id' : 'Série $id');
    final rating = _rating(item['rating']) ??
        (() {
          final five = double.tryParse(_text(item['rating_5based']) ?? '');
          return (five == null || five <= 0) ? null : five * 2;
        })();
    out.add(
      CatalogTitle(
        kind: job.kind,
        id: id,
        name: name,
        categoryId: _text(item['category_id']) ?? '',
        image: _text(movies ? item['stream_icon'] : item['cover']),
        rating: rating,
        added: _int(movies ? item['added'] : item['last_modified']),
        ext: movies ? (_text(item['container_extension']) ?? 'mp4') : null,
        year: movies
            ? _year(item['year'])
            : _year(item['releaseDate'] ?? item['release_date']),
        plot: movies ? null : _text(item['plot']),
      ),
    );
  }
  return out;
}

String? _firstBackdrop(Object? value) {
  if (value is List && value.isNotEmpty) return _text(value.first);
  return _text(value);
}

/// Resposta de get_vod_info.
TitleDetails parseVodInfo(Uint8List bytes) {
  final data = _decode(bytes);
  if (data is! Map) return const TitleDetails();
  final info = data['info'];
  final movieData = data['movie_data'];
  final i = info is Map ? info : const {};
  return TitleDetails(
    plot: _text(i['plot'] ?? i['description']),
    cast: _text(i['cast'] ?? i['actors']),
    director: _text(i['director']),
    genre: _text(i['genre']),
    year: _year(i['releasedate'] ?? i['release_date'] ?? i['year']),
    rating: _rating(i['rating']),
    durationLabel: _text(i['duration']),
    durationSecs: _int(i['duration_secs']),
    backdrop: _firstBackdrop(i['backdrop_path']),
    poster: _text(i['movie_image'] ?? i['cover_big']),
    ext: movieData is Map ? _text(movieData['container_extension']) : null,
  );
}

/// Resposta de get_series_info (temporadas e episódios).
TitleDetails parseSeriesInfo(Uint8List bytes) {
  final data = _decode(bytes);
  if (data is! Map) return const TitleDetails();
  final info = data['info'];
  final i = info is Map ? info : const {};

  final seasons = <int, List<Episode>>{};
  void addEpisode(Object? raw, int fallbackSeason) {
    if (raw is! Map) return;
    final id = _int(raw['id']);
    if (id == null) return;
    final number = _int(raw['episode_num']) ?? 0;
    final season = _int(raw['season']) ?? fallbackSeason;
    final epInfo = raw['info'];
    final ei = epInfo is Map ? epInfo : const {};
    seasons.putIfAbsent(season, () => []).add(
          Episode(
            id: id,
            season: season,
            number: number,
            title: _text(raw['title']) ?? 'Episódio $number',
            ext: _text(raw['container_extension']) ?? 'mp4',
            image: _text(ei['movie_image']),
            plot: _text(ei['plot']),
            durationSecs: _int(ei['duration_secs']),
          ),
        );
  }

  final episodes = data['episodes'];
  if (episodes is Map) {
    episodes.forEach((key, list) {
      final fallback = int.tryParse('$key') ?? 1;
      if (list is List) {
        for (final e in list) {
          addEpisode(e, fallback);
        }
      }
    });
  } else if (episodes is List) {
    for (var s = 0; s < episodes.length; s++) {
      final list = episodes[s];
      if (list is List) {
        for (final e in list) {
          addEpisode(e, s + 1);
        }
      }
    }
  }
  for (final list in seasons.values) {
    list.sort((a, b) => a.number.compareTo(b.number));
  }
  final ordered = Map.fromEntries(
    seasons.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );

  return TitleDetails(
    plot: _text(i['plot']),
    cast: _text(i['cast']),
    director: _text(i['director']),
    genre: _text(i['genre']),
    year: _year(i['releaseDate'] ?? i['release_date']),
    rating: _rating(i['rating']),
    backdrop: _firstBackdrop(i['backdrop_path']),
    poster: _text(i['cover']),
    seasons: ordered,
  );
}
