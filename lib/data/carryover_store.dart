import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../catalog/title_matcher.dart';
import 'catalog_models.dart';

/// Dados do perfil que sobrevivem à troca do Xtream do **mesmo provedor**:
/// histórico ("Continuar assistindo"), favoritos de filmes/séries, canais
/// favoritos e categorias ocultas.
///
/// Antes de apagar o catálogo antigo, [snapshot] guarda esses dados pelo nome
/// (e ano), não pelo id. Quando cada catálogo novo chega ([applyLive] e
/// [applyKind]), o que casar com segurança é religado aos ids novos; o resto
/// continua guardado (chave `account_carryover` em `settings`) para revisão.
class CarryoverStore {
  CarryoverStore(this._db);

  final Database _db;

  static const _key = 'account_carryover';

  Future<Carryover?> load() async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: [_key]);
    if (rows.isEmpty) return null;
    try {
      return Carryover.fromJson(
        jsonDecode(rows.first['value'] as String) as Map<String, dynamic>,
      );
    } catch (_) {
      return null; // conteúdo ilegível: trata como se não houvesse
    }
  }

  Future<void> _save(Carryover c) async {
    if (c.isEmpty) {
      await clear();
      return;
    }
    await _db.insert(
      'settings',
      {'key': _key, 'value': jsonEncode(c.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clear() =>
      _db.delete('settings', where: 'key = ?', whereArgs: [_key]);

  /// Tira um item guardado (descartado ou religado à mão).
  Future<void> remove(CarryGroup group, Map<String, dynamic> entry) async {
    final c = await load();
    if (c == null) return;
    final key = jsonEncode(entry);
    c.listOf(group).removeWhere((e) => jsonEncode(e) == key);
    await _save(c);
  }

  /// Grava à mão o progresso guardado em [itemId] (episódio: [seriesId] é a
  /// série nova). Se já houver progresso mais novo desse item, ele fica.
  Future<void> relinkProgress(
    Map<String, dynamic> entry, {
    required int itemId,
    int? seriesId,
  }) async {
    final cur = await _db.query(
      'watch_progress',
      columns: ['updated_at'],
      where: 'kind = ? AND item_id = ?',
      whereArgs: [entry['kind'], itemId],
    );
    final newer = cur.isNotEmpty &&
        ((cur.first['updated_at'] as int?) ?? 0) >= ((entry['updated_at'] as int?) ?? 0);
    if (!newer) {
      await _db.delete(
        'watch_progress',
        where: 'kind = ? AND item_id = ?',
        whereArgs: [entry['kind'], itemId],
      );
      await _insertProgress(entry, itemId: itemId, seriesId: seriesId);
    }
    await remove(CarryGroup.progress, entry);
  }

  /// Guarda os dados ligados à conta atual (somados ao que ainda estava
  /// pendente de uma troca anterior). Chamar **antes** de apagar o catálogo.
  Future<void> snapshot() async {
    final c = await load() ?? Carryover();

    final progress = await _db.rawQuery(
      'SELECT p.*, v.name AS v_name, v.year AS v_year, '
      's.name AS s_name, s.year AS s_year FROM watch_progress p '
      "LEFT JOIN vod_items v ON p.kind = 'vod' AND v.id = p.item_id "
      "LEFT JOIN series_items s ON p.kind = 'episode' AND s.id = p.series_id",
    );
    for (final r in progress) {
      final isMovie = r['kind'] == 'vod';
      final name = (isMovie ? r['v_name'] : r['s_name']) as String? ??
          r['title'] as String?;
      if (name == null || name.isEmpty) continue;
      if (!isMovie && (r['season'] == null || r['episode'] == null)) continue;
      c.progress.add({
        'kind': r['kind'],
        'name': name,
        'year': isMovie ? r['v_year'] : r['s_year'],
        'old_id': isMovie ? r['item_id'] : r['series_id'],
        'season': r['season'],
        'episode': r['episode'],
        'position_ms': r['position_ms'],
        'duration_ms': r['duration_ms'],
        'watched': r['watched'],
        'updated_at': r['updated_at'],
        'title': r['title'],
        'subtitle': r['subtitle'],
        'image': r['image'],
      });
    }

    for (final kind in CatalogKind.values) {
      final favs = await _db.rawQuery(
        'SELECT f.item_id, f.added_at, i.name, i.year FROM favorite_titles f '
        'JOIN ${kind.itemsTable} i ON i.id = f.item_id WHERE f.kind = ?',
        [kind.key],
      );
      for (final r in favs) {
        c.favorites.add({
          'kind': kind.key,
          'name': r['name'],
          'year': r['year'],
          'old_id': r['item_id'],
          'added_at': r['added_at'],
        });
      }
    }

    const catTables = {
      'live': 'live_categories',
      'vod': 'vod_categories',
      'series': 'series_categories',
    };
    for (final e in catTables.entries) {
      final rows = await _db.rawQuery(
        'SELECT h.category_id, c.name FROM hidden_categories h '
        'JOIN ${e.value} c ON c.id = h.category_id WHERE h.kind = ?',
        [e.key],
      );
      for (final r in rows) {
        c.hidden.add({'kind': e.key, 'name': r['name'], 'old_id': r['category_id']});
      }
    }

    final favChannels = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['favorite_channels'],
    );
    final ids = favChannels.isEmpty
        ? const <int>[]
        : [
            for (final p in (favChannels.first['value'] as String).split(','))
              if (int.tryParse(p) != null) int.parse(p),
          ];
    if (ids.isNotEmpty) {
      final rows = await _db.rawQuery(
        'SELECT stream_id, name FROM live_channels '
        'WHERE stream_id IN (${List.filled(ids.length, '?').join(',')})',
        ids,
      );
      for (final r in rows) {
        c.channels.add({'name': r['name'], 'old_id': r['stream_id']});
      }
    }

    await _save(c);
  }

  /// Religa canais favoritos e categorias ocultas da TV ao vivo ao catálogo
  /// recém-baixado. Devolve true se algo mudou.
  Future<bool> applyLive() async {
    final c = await load();
    if (c == null) return false;
    var changed = false;

    final hiddenLive = [for (final h in c.hidden) if (h['kind'] == 'live') h];
    if (hiddenLive.isNotEmpty) {
      final m = await _categoryMatcher('live_categories');
      for (final h in hiddenLive) {
        final id = m.find(h['name'] as String, previousId: h['old_id'] as String?);
        if (id == null) continue;
        await _db.insert(
          'hidden_categories',
          {'kind': 'live', 'category_id': id},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        c.hidden.remove(h);
        changed = true;
      }
    }

    if (c.channels.isNotEmpty) {
      final rows = await _db.query('live_channels', columns: ['stream_id', 'name']);
      final m = TitleMatcher<int>([
        for (final r in rows) MatchCandidate(r['stream_id'] as int, r['name'] as String),
      ]);
      final found = <int>{};
      for (final ch in [...c.channels]) {
        final id = m.find(ch['name'] as String, previousId: ch['old_id'] as int?);
        if (id == null) continue;
        found.add(id);
        c.channels.remove(ch);
      }
      if (found.isNotEmpty) {
        final cur = await _db.query(
          'settings',
          where: 'key = ?',
          whereArgs: ['favorite_channels'],
        );
        final now = cur.isEmpty
            ? <int>{}
            : {
                for (final p in (cur.first['value'] as String).split(','))
                  if (int.tryParse(p) != null) int.parse(p),
              };
        await _db.insert(
          'settings',
          {'key': 'favorite_channels', 'value': {...now, ...found}.join(',')},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        changed = true;
      }
    }

    if (changed) await _save(c);
    return changed;
  }

  /// Religa histórico, favoritos e categorias ocultas de filmes ou séries ao
  /// catálogo recém-baixado. Para episódios, [seriesInfo] traz os episódios da
  /// série nova (o episódio é achado por temporada e número). Devolve true se
  /// algo mudou.
  Future<bool> applyKind(
    CatalogKind kind, {
    Future<TitleDetails> Function(int seriesId)? seriesInfo,
  }) async {
    final c = await load();
    if (c == null) return false;
    final hidden = [for (final h in c.hidden) if (h['kind'] == kind.key) h];
    final favs = [for (final f in c.favorites) if (f['kind'] == kind.key) f];
    final prog = [
      for (final p in c.progress)
        if (p['kind'] == kind.progressKind) p,
    ];
    if (hidden.isEmpty && favs.isEmpty && prog.isEmpty) return false;
    var changed = false;

    if (hidden.isNotEmpty) {
      final m = await _categoryMatcher(kind.categoriesTable);
      for (final h in hidden) {
        final id = m.find(h['name'] as String, previousId: h['old_id'] as String?);
        if (id == null) continue;
        await _db.insert(
          'hidden_categories',
          {'kind': kind.key, 'category_id': id},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        c.hidden.remove(h);
        changed = true;
      }
    }

    final rows = await _db.query(kind.itemsTable, columns: ['id', 'name', 'year']);
    final m = TitleMatcher<int>([
      for (final r in rows)
        MatchCandidate(r['id'] as int, r['name'] as String, r['year'] as String?),
    ]);
    int? match(Map<String, dynamic> e) => m.find(
          e['name'] as String,
          year: e['year'] as String?,
          previousId: e['old_id'] as int?,
        );

    for (final f in favs) {
      final id = match(f);
      if (id == null) continue;
      await _db.insert(
        'favorite_titles',
        {'kind': kind.key, 'item_id': id, 'added_at': f['added_at']},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      c.favorites.remove(f);
      changed = true;
    }

    if (kind == CatalogKind.movies) {
      for (final p in prog) {
        final id = match(p);
        if (id == null) continue;
        await _insertProgress(p, itemId: id);
        c.progress.remove(p);
        changed = true;
      }
    } else if (seriesInfo != null) {
      // Uma consulta por série (não por episódio).
      final bySeries = <int, List<Map<String, dynamic>>>{};
      for (final p in prog) {
        final id = match(p);
        if (id != null) (bySeries[id] ??= []).add(p);
      }
      for (final e in bySeries.entries) {
        TitleDetails d;
        try {
          d = await seriesInfo(e.key);
        } catch (_) {
          continue; // fica para a próxima atualização de séries
        }
        final episodes = {
          for (final list in d.seasons.values)
            for (final ep in list) '${ep.season}:${ep.number}': ep.id,
        };
        for (final p in e.value) {
          final epId = episodes['${p['season']}:${p['episode']}'];
          if (epId == null) continue;
          await _insertProgress(p, itemId: epId, seriesId: e.key);
          c.progress.remove(p);
          changed = true;
        }
      }
    }

    if (changed) await _save(c);
    return changed;
  }

  Future<TitleMatcher<String>> _categoryMatcher(String table) async {
    final rows = await _db.query(table, columns: ['id', 'name']);
    return TitleMatcher<String>([
      for (final r in rows) MatchCandidate(r['id'] as String, r['name'] as String),
    ]);
  }

  /// Grava o progresso guardado com o id novo. Se já houver progresso desse
  /// item (assistido depois da troca), o mais novo fica.
  Future<void> _insertProgress(
    Map<String, dynamic> p, {
    required int itemId,
    int? seriesId,
  }) {
    return _db.insert(
      'watch_progress',
      {
        'kind': p['kind'],
        'item_id': itemId,
        'position_ms': p['position_ms'] ?? 0,
        'duration_ms': p['duration_ms'] ?? 0,
        'watched': p['watched'] ?? 0,
        'updated_at': p['updated_at'] ?? 0,
        'title': p['title'],
        'subtitle': p['subtitle'],
        'image': p['image'],
        'series_id': seriesId,
        'season': p['season'],
        'episode': p['episode'],
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

/// Grupos de dados guardados (as abas da tela "Dados anteriores").
enum CarryGroup { progress, favorites, channels, hidden }

/// Dados guardados pelo nome, à espera do catálogo novo.
class Carryover {
  Carryover({
    List<Map<String, dynamic>>? progress,
    List<Map<String, dynamic>>? favorites,
    List<Map<String, dynamic>>? hidden,
    List<Map<String, dynamic>>? channels,
  })  : progress = progress ?? [],
        favorites = favorites ?? [],
        hidden = hidden ?? [],
        channels = channels ?? [];

  final List<Map<String, dynamic>> progress;
  final List<Map<String, dynamic>> favorites;
  final List<Map<String, dynamic>> hidden;
  final List<Map<String, dynamic>> channels;

  bool get isEmpty =>
      progress.isEmpty && favorites.isEmpty && hidden.isEmpty && channels.isEmpty;

  int get total => progress.length + favorites.length + hidden.length + channels.length;

  List<Map<String, dynamic>> listOf(CarryGroup g) => switch (g) {
        CarryGroup.progress => progress,
        CarryGroup.favorites => favorites,
        CarryGroup.channels => channels,
        CarryGroup.hidden => hidden,
      };

  Map<String, dynamic> toJson() => {
        'progress': progress,
        'favorites': favorites,
        'hidden': hidden,
        'channels': channels,
      };

  static List<Map<String, dynamic>> _list(Object? v) => [
        if (v is List)
          for (final e in v)
            if (e is Map) Map<String, dynamic>.from(e),
      ];

  factory Carryover.fromJson(Map<String, dynamic> j) => Carryover(
        progress: _list(j['progress']),
        favorites: _list(j['favorites']),
        hidden: _list(j['hidden']),
        channels: _list(j['channels']),
      );
}
