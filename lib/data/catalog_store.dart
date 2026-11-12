import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../catalog/smart_search.dart';
import 'catalog_models.dart';
import 'models.dart';

/// Acesso ao SQLite de filmes, séries e progresso. As tabelas são criadas em
/// [AppDatabase] (esquema versão 3).
class CatalogStore {
  CatalogStore(this._db);

  final Database _db;

  static const _hiddenSqlLimit = 900;

  // ---- catálogo ------------------------------------------------------------

  Future<List<LiveCategory>> loadCategories(CatalogKind kind) async {
    final rows = await _db.query(kind.categoriesTable, orderBy: 'position ASC');
    return [
      for (final r in rows)
        LiveCategory(id: r['id'] as String, name: r['name'] as String),
    ];
  }

  /// Quantidade de títulos por categoria.
  Future<Map<String, int>> counts(CatalogKind kind) async {
    final rows = await _db.rawQuery(
      'SELECT category_id, COUNT(*) AS n FROM ${kind.itemsTable} GROUP BY category_id',
    );
    return {
      for (final r in rows) r['category_id'] as String: (r['n'] as int?) ?? 0,
    };
  }

  /// Troca o catálogo do tipo numa única transação (se falhar, o anterior fica).
  Future<void> replaceCatalog(
    CatalogKind kind,
    List<LiveCategory> categories,
    List<CatalogTitle> titles,
  ) async {
    await _db.transaction((txn) async {
      await txn.delete(kind.itemsTable);
      await txn.delete(kind.categoriesTable);
      var batch = txn.batch();
      for (var i = 0; i < categories.length; i++) {
        batch.insert(
          kind.categoriesTable,
          {'id': categories[i].id, 'name': categories[i].name, 'position': i},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      // Em lotes, para não montar uma lista gigante de operações de uma vez.
      const chunk = 2000;
      for (var start = 0; start < titles.length; start += chunk) {
        batch = txn.batch();
        final end = start + chunk < titles.length ? start + chunk : titles.length;
        for (var i = start; i < end; i++) {
          final t = titles[i];
          batch.insert(
            kind.itemsTable,
            {
              'id': t.id,
              'name': t.name,
              'image': t.image,
              'category_id': t.categoryId,
              'rating': t.rating,
              'added': t.added,
              'ext': t.ext,
              'year': t.year,
              'plot': t.plot,
              'position': i,
              'search_key': t.searchKey,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }
    });
  }

  Future<void> clearKind(CatalogKind kind) async {
    await _db.transaction((txn) async {
      await txn.delete(kind.itemsTable);
      await txn.delete(kind.categoriesTable);
    });
  }

  CatalogTitle _title(CatalogKind kind, Map<String, Object?> r) {
    return CatalogTitle(
      kind: kind,
      id: r['id'] as int,
      name: r['name'] as String,
      categoryId: r['category_id'] as String,
      image: r['image'] as String?,
      rating: (r['rating'] as num?)?.toDouble(),
      added: r['added'] as int?,
      ext: r['ext'] as String?,
      year: r['year'] as String?,
      plot: r['plot'] as String?,
    );
  }

  /// Monta "AND category_id NOT IN (?, ?, …)" para as categorias ocultas.
  (String, List<Object?>) _notHidden(Set<String> hidden) {
    if (hidden.isEmpty) return ('', const []);
    final ids = hidden.take(_hiddenSqlLimit).toList();
    final marks = List.filled(ids.length, '?').join(',');
    return (' AND category_id NOT IN ($marks)', ids);
  }

  List<CatalogTitle> _filterHidden(List<CatalogTitle> list, Set<String> hidden) {
    // Só necessário no caso raro de mais de 900 categorias ocultas.
    if (hidden.length <= _hiddenSqlLimit) return list;
    return [
      for (final t in list)
        if (!hidden.contains(t.categoryId)) t,
    ];
  }

  Future<List<CatalogTitle>> titles(
    CatalogKind kind,
    String categoryId, {
    int limit = 40,
    int offset = 0,
  }) async {
    final rows = await _db.query(
      kind.itemsTable,
      where: 'category_id = ?',
      whereArgs: [categoryId],
      orderBy: 'position ASC',
      limit: limit,
      offset: offset,
    );
    return [for (final r in rows) _title(kind, r)];
  }

  /// Mais recentes (pela data informada pelo provedor), fora das categorias ocultas.
  Future<List<CatalogTitle>> recent(
    CatalogKind kind,
    Set<String> hidden, {
    int limit = 40,
  }) async {
    final (sql, args) = _notHidden(hidden);
    final rows = await _db.rawQuery(
      'SELECT * FROM ${kind.itemsTable} WHERE added IS NOT NULL AND added > 0$sql '
      'ORDER BY added DESC, position ASC LIMIT $limit',
      args,
    );
    return _filterHidden([for (final r in rows) _title(kind, r)], hidden);
  }

  /// Índice enxuto para a busca inteligente (feita em memória, em Dart).
  Future<List<SearchEntry>> searchIndex(CatalogKind kind) async {
    final rows = await _db.rawQuery(
      'SELECT id, category_id, search_key, rating FROM ${kind.itemsTable}',
    );
    return [
      for (final r in rows)
        SearchEntry(
          id: r['id'] as int,
          categoryId: r['category_id'] as String,
          rawKey: r['search_key'] as String,
          rating: (r['rating'] as num?)?.toDouble() ?? 0,
        ),
    ];
  }

  /// O mesmo índice em listas simples (para enviar ao isolate de busca).
  Future<({List<int> ids, List<String> cats, List<String> keys, List<double> ratings})>
      searchIndexRaw(CatalogKind kind) async {
    final rows = await _db.rawQuery(
      'SELECT id, category_id, search_key, rating FROM ${kind.itemsTable}',
    );
    return (
      ids: [for (final r in rows) r['id'] as int],
      cats: [for (final r in rows) r['category_id'] as String],
      keys: [for (final r in rows) r['search_key'] as String],
      ratings: [for (final r in rows) (r['rating'] as num?)?.toDouble() ?? 0.0],
    );
  }

  /// Títulos pelos ids, na mesma ordem da lista recebida.
  Future<List<CatalogTitle>> titlesByIds(CatalogKind kind, List<int> ids) async {
    if (ids.isEmpty) return const [];
    final out = <int, CatalogTitle>{};
    for (var i = 0; i < ids.length; i += 400) {
      final part = ids.sublist(i, i + 400 > ids.length ? ids.length : i + 400);
      final marks = List.filled(part.length, '?').join(',');
      final rows = await _db.rawQuery(
        'SELECT * FROM ${kind.itemsTable} WHERE id IN ($marks)',
        part,
      );
      for (final r in rows) {
        final t = _title(kind, r);
        out[t.id] = t;
      }
    }
    return [
      for (final id in ids)
        if (out[id] != null) out[id]!,
    ];
  }

  // ---- imagens horizontais em cache ------------------------------------------

  /// Chaves `<tipo>:<id>` -> endereço da imagem horizontal já descoberta.
  Future<Map<String, String>> backdropCache() async {
    final rows = await _db.rawQuery('SELECT kind, item_id, url FROM backdrop_cache');
    return {
      for (final r in rows) '${r['kind']}:${r['item_id']}': r['url'] as String,
    };
  }

  Future<void> putBackdrop(CatalogKind kind, int id, String url) async {
    await _db.insert(
      'backdrop_cache',
      {'kind': kind.key, 'item_id': id, 'url': url},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---- favoritos -----------------------------------------------------------

  /// Chaves `<tipo>:<id>` de todos os favoritos.
  Future<Set<String>> favoriteKeys() async {
    final rows = await _db.rawQuery('SELECT kind, item_id FROM favorite_titles');
    return {for (final r in rows) '${r['kind']}:${r['item_id']}'};
  }

  Future<void> setFavorite(CatalogKind kind, int id, bool on) async {
    if (on) {
      await _db.insert(
        'favorite_titles',
        {
          'kind': kind.key,
          'item_id': id,
          'added_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await _db.delete(
        'favorite_titles',
        where: 'kind = ? AND item_id = ?',
        whereArgs: [kind.key, id],
      );
    }
  }

  /// Favoritos de um tipo, do mais recente para o mais antigo. Títulos que
  /// sumiram do catálogo (o provedor removeu) não aparecem.
  Future<List<CatalogTitle>> favoriteTitles(CatalogKind kind) async {
    final rows = await _db.rawQuery(
      'SELECT item_id FROM favorite_titles WHERE kind = ? ORDER BY added_at DESC',
      [kind.key],
    );
    return titlesByIds(kind, [for (final r in rows) r['item_id'] as int]);
  }

  // ---- progresso -----------------------------------------------------------

  Future<WatchProgress?> progress(String progressKind, int itemId) async {
    final rows = await _db.query(
      'watch_progress',
      where: 'kind = ? AND item_id = ?',
      whereArgs: [progressKind, itemId],
    );
    if (rows.isEmpty) return null;
    return _progress(rows.first);
  }

  WatchProgress _progress(Map<String, Object?> r) => WatchProgress(
        positionMs: (r['position_ms'] as int?) ?? 0,
        durationMs: (r['duration_ms'] as int?) ?? 0,
        watched: ((r['watched'] as int?) ?? 0) == 1,
      );

  /// Progresso de todos os episódios de uma série (id do episódio → progresso).
  Future<Map<int, WatchProgress>> episodeProgress(int seriesId) async {
    final rows = await _db.query(
      'watch_progress',
      where: "kind = 'episode' AND series_id = ?",
      whereArgs: [seriesId],
    );
    return {for (final r in rows) r['item_id'] as int: _progress(r)};
  }

  Future<void> saveProgress(
    PlayItem item, {
    required int positionMs,
    required int durationMs,
    required bool watched,
  }) async {
    await _db.insert(
      'watch_progress',
      {
        'kind': item.kind.progressKind,
        'item_id': item.id,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'watched': watched ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'title': item.title,
        'subtitle': item.subtitle,
        'image': item.image,
        'series_id': item.seriesId,
        'season': item.season,
        'episode': item.episode,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Marca/desmarca como assistido sem perder a posição já salva.
  Future<void> setWatched(PlayItem item, bool watched) async {
    final existing = await progress(item.kind.progressKind, item.id);
    await saveProgress(
      item,
      positionMs: existing?.positionMs ?? 0, // mantém onde parou
      durationMs: existing?.durationMs ?? 0,
      watched: watched,
    );
  }

  /// "Continuar assistindo" dos filmes: começados e não terminados.
  Future<List<CatalogTitle>> continueMovies({int limit = 30}) async {
    final rows = await _db.query(
      'watch_progress',
      // item_id > 0: arquivos importados pelo usuário (id negativo) ficam só
      // na Minha biblioteca, fora do "Continuar assistindo".
      where: "kind = 'vod' AND item_id > 0 AND watched = 0 AND position_ms > 5000",
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return [
      for (final r in rows)
        CatalogTitle(
          kind: CatalogKind.movies,
          id: r['item_id'] as int,
          name: (r['title'] as String?) ?? 'Filme',
          categoryId: '',
          image: r['image'] as String?,
          positionMs: r['position_ms'] as int?,
          durationMs: r['duration_ms'] as int?,
          updatedAt: r['updated_at'] as int?,
        ),
    ];
  }

  /// Para cada série, o episódio mexido por último (assistido até o fim ou em
  /// andamento), da mais recente para a mais antiga. Episódios apenas abertos
  /// (até 5 s) não contam.
  Future<List<SeriesActivity>> seriesActivity({int limit = 30}) async {
    final rows = await _db.rawQuery(
      "SELECT *, MAX(updated_at) AS last FROM watch_progress "
      "WHERE kind = 'episode' AND series_id IS NOT NULL "
      'AND (watched = 1 OR position_ms > 5000) GROUP BY series_id '
      'ORDER BY last DESC LIMIT $limit',
    );
    return [
      for (final r in rows)
        SeriesActivity(
          seriesId: r['series_id'] as int,
          episodeId: r['item_id'] as int,
          season: r['season'] as int?,
          episode: r['episode'] as int?,
          watched: ((r['watched'] as int?) ?? 0) == 1,
          positionMs: (r['position_ms'] as int?) ?? 0,
          durationMs: (r['duration_ms'] as int?) ?? 0,
          updatedAt: (r['last'] as int?) ?? 0,
          title: (r['title'] as String?) ?? 'Série',
          subtitle: r['subtitle'] as String?,
          image: r['image'] as String?,
        ),
    ];
  }

  /// Temporada do último episódio assistido (ou começado) da série.
  Future<int?> lastEpisodeSeason(int seriesId) async {
    final rows = await _db.query(
      'watch_progress',
      columns: ['season'],
      where: "kind = 'episode' AND series_id = ? AND season IS NOT NULL "
          'AND (watched = 1 OR position_ms > 0)',
      whereArgs: [seriesId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['season'] as int?;
  }

  Future<void> clearProgress() => _db.delete('watch_progress');

  // ---- histórico ---------------------------------------------------------------

  /// Tudo que já foi assistido ou começado (filmes e episódios do catálogo),
  /// do mais recente para o mais antigo. Arquivos importados (id negativo) ficam
  /// de fora: eles têm o próprio cartão em "Minha biblioteca".
  Future<List<HistoryRow>> history({int limit = 1000}) async {
    final rows = await _db.query(
      'watch_progress',
      where: "kind IN ('vod', 'episode') AND item_id > 0 "
          'AND (watched = 1 OR position_ms > 0)',
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return [
      for (final r in rows)
        HistoryRow(
          progressKind: r['kind'] as String,
          itemId: r['item_id'] as int,
          positionMs: (r['position_ms'] as int?) ?? 0,
          durationMs: (r['duration_ms'] as int?) ?? 0,
          watched: ((r['watched'] as int?) ?? 0) == 1,
          updatedAt: (r['updated_at'] as int?) ?? 0,
          title: (r['title'] as String?) ?? 'Sem título',
          subtitle: r['subtitle'] as String?,
          image: r['image'] as String?,
          seriesId: r['series_id'] as int?,
        ),
    ];
  }

  /// Marca como assistido ou não assistido; a posição já salva é mantida.
  /// Não muda a data.
  Future<void> setHistoryWatched(HistoryRow row, bool watched) {
    return _db.update(
      'watch_progress',
      {'watched': watched ? 1 : 0},
      where: 'kind = ? AND item_id = ?',
      whereArgs: [row.progressKind, row.itemId],
    );
  }

  Future<void> removeHistory(HistoryRow row) {
    return _db.delete(
      'watch_progress',
      where: 'kind = ? AND item_id = ?',
      whereArgs: [row.progressKind, row.itemId],
    );
  }

  /// Apaga o histórico do catálogo (filmes e episódios); progresso de arquivos
  /// importados não é tocado.
  Future<int> clearHistory() => _db.delete(
        'watch_progress',
        where: "kind IN ('vod', 'episode') AND item_id > 0",
      );
}
