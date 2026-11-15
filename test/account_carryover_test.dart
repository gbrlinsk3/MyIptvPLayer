import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/title_matcher.dart';
import 'package:iptv_player/data/carryover_store.dart';
import 'package:iptv_player/data/catalog_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  for (final t in ['vod', 'series']) {
    await db.execute(
      'CREATE TABLE ${t}_items (id INTEGER PRIMARY KEY, name TEXT NOT NULL, '
      'year TEXT, category_id TEXT)',
    );
    await db.execute(
      'CREATE TABLE ${t}_categories (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
    );
  }
  await db.execute(
    'CREATE TABLE live_channels (stream_id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE live_categories (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
  );
  await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  await db.execute(
    'CREATE TABLE hidden_categories (kind TEXT NOT NULL, category_id TEXT NOT NULL, '
    'PRIMARY KEY (kind, category_id))',
  );
  await db.execute(
    'CREATE TABLE favorite_titles (kind TEXT NOT NULL, item_id INTEGER NOT NULL, '
    'added_at INTEGER NOT NULL, PRIMARY KEY (kind, item_id))',
  );
  await db.execute(
    'CREATE TABLE watch_progress (kind TEXT NOT NULL, item_id INTEGER NOT NULL, '
    'position_ms INTEGER NOT NULL, duration_ms INTEGER NOT NULL, '
    'watched INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL, '
    'title TEXT, subtitle TEXT, image TEXT, series_id INTEGER, '
    'season INTEGER, episode INTEGER, PRIMARY KEY (kind, item_id))',
  );
  return db;
}

TitleDetails _series(Map<int, List<Episode>> seasons) => TitleDetails(seasons: seasons);

Episode _ep(int id, int season, int number) =>
    Episode(id: id, season: season, number: number, title: 'E$number', ext: 'mp4');

void main() {
  group('TitleMatcher', () {
    final m = TitleMatcher<int>([
      MatchCandidate(10, 'Vingadores: Ultimato', '2019'),
      MatchCandidate(11, 'Duna', '1984'),
      MatchCandidate(12, 'Duna', '2021'),
      MatchCandidate(13, 'Coringa [LEG]', '2019'),
      MatchCandidate(14, 'Coringa [DUB]', '2019'),
      MatchCandidate(15, 'Ação Total 4K'),
      MatchCandidate(16, '1917', '2019'),
    ]);

    test('mesmo nome, sem diferença de acento/pontuação', () {
      expect(m.find('vingadores ultimato', year: '2019'), 10);
      expect(m.find('Acao Total 4K'), 15);
    });

    test('ano separa títulos de mesmo nome', () {
      expect(m.find('Duna', year: '2021'), 12);
      expect(m.find('Duna (1984)'), 11);
      expect(m.find('Duna'), isNull, reason: 'sem ano e com dois anos: ambíguo');
      expect(m.find('Duna', year: '2000'), isNull);
    });

    test('sem marcações só casa se for único', () {
      expect(m.find('Ação Total FHD'), 15);
      expect(m.find('Coringa', year: '2019'), isNull, reason: 'LEG e DUB: ambíguo');
      expect(m.find('Coringa', year: '2019', previousId: 14), 14);
    });

    test('título que é só um ano', () {
      expect(looseKey('1917'), '1917');
      expect(m.find('1917', year: '2019'), 16);
    });

    test('id antigo tem preferência quando é candidato', () {
      final dup = TitleMatcher<int>([
        MatchCandidate(1, 'Globo SP HD'),
        MatchCandidate(2, 'Globo SP HD'),
      ]);
      expect(dup.find('Globo SP HD', previousId: 2), 2);
      expect(dup.find('Globo SP HD'), 1);
    });
  });

  group('CarryoverStore', () {
    test('guarda pelo nome e religa aos ids novos', () async {
      final db = await _openDb();
      addTearDown(db.close);
      final store = CarryoverStore(db);

      // Conta antiga.
      await db.insert('vod_items', {'id': 1, 'name': 'Duna', 'year': '2021'});
      await db.insert('series_items', {'id': 5, 'name': 'Dark', 'year': '2017'});
      await db.insert('vod_categories', {'id': 'c1', 'name': 'Terror'});
      await db.insert('live_categories', {'id': 'l1', 'name': 'Adultos'});
      await db.insert('live_channels', {'stream_id': 100, 'name': 'Globo SP HD'});
      await db.insert('settings', {'key': 'favorite_channels', 'value': '100'});
      await db.insert('hidden_categories', {'kind': 'vod', 'category_id': 'c1'});
      await db.insert('hidden_categories', {'kind': 'live', 'category_id': 'l1'});
      await db.insert('favorite_titles', {'kind': 'vod', 'item_id': 1, 'added_at': 7});
      await db.insert('watch_progress', {
        'kind': 'vod', 'item_id': 1, 'position_ms': 1000, 'duration_ms': 5000,
        'updated_at': 9, 'title': 'Duna',
      });
      await db.insert('watch_progress', {
        'kind': 'episode', 'item_id': 50, 'position_ms': 2000, 'duration_ms': 3000,
        'updated_at': 8, 'title': 'Dark', 'series_id': 5, 'season': 1, 'episode': 2,
      });
      await db.insert('watch_progress', {
        'kind': 'vod', 'item_id': 2, 'position_ms': 1, 'duration_ms': 2,
        'updated_at': 1, 'title': 'Filme que sumiu',
      });

      await store.snapshot();

      // Troca: tudo apagado e catálogo novo com outros ids.
      for (final t in [
        'vod_items', 'series_items', 'vod_categories', 'live_categories',
        'live_channels', 'hidden_categories', 'favorite_titles', 'watch_progress',
      ]) {
        await db.delete(t);
      }
      await db.insert('settings', {'key': 'favorite_channels', 'value': ''},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('vod_items', {'id': 901, 'name': 'DUNA', 'year': '2021'});
      await db.insert('series_items', {'id': 905, 'name': 'Dark', 'year': '2017'});
      await db.insert('vod_categories', {'id': 'n1', 'name': 'TERROR'});
      await db.insert('live_categories', {'id': 'nl1', 'name': 'Adultos'});
      await db.insert('live_channels', {'stream_id': 777, 'name': 'Globo SP FHD'});

      expect(await store.applyLive(), isTrue);
      expect(await store.applyKind(CatalogKind.movies), isTrue);
      expect(
        await store.applyKind(
          CatalogKind.series,
          seriesInfo: (id) async {
            expect(id, 905);
            return _series({1: [_ep(9501, 1, 1), _ep(9502, 1, 2)]});
          },
        ),
        isTrue,
      );

      final fav = await db.query('settings', where: "key = 'favorite_channels'");
      expect(fav.first['value'], '777');
      final hidden = await db.query('hidden_categories', orderBy: 'kind');
      expect([for (final h in hidden) '${h['kind']}:${h['category_id']}'],
          ['live:nl1', 'vod:n1']);
      final favs = await db.query('favorite_titles');
      expect(favs.single['item_id'], 901);
      expect(favs.single['added_at'], 7);
      final prog = await db.query('watch_progress', orderBy: 'kind');
      expect(prog.length, 2);
      expect(prog[0]['item_id'], 9502);
      expect(prog[0]['series_id'], 905);
      expect(prog[1]['item_id'], 901);
      expect(prog[1]['position_ms'], 1000);

      // Só o filme que não existe mais continua guardado.
      final left = await store.load();
      expect(left!.total, 1);
      expect(left.progress.single['name'], 'Filme que sumiu');

      // Religar à mão (tela "Dados anteriores"): grava e tira da lista.
      await db.insert('vod_items', {'id': 950, 'name': 'Filme renomeado'});
      await store.relinkProgress(left.progress.single, itemId: 950);
      final relinked = await db.query('watch_progress', where: 'item_id = 950');
      expect(relinked.single['position_ms'], 1);
      expect(await store.load(), isNull, reason: 'sem itens, a chave some');
    });

    test('religar não sobrescreve progresso mais novo; descartar remove', () async {
      final db = await _openDb();
      addTearDown(db.close);
      final store = CarryoverStore(db);
      await db.insert('vod_items', {'id': 1, 'name': 'A'});
      await db.insert('vod_items', {'id': 2, 'name': 'B'});
      for (final id in [1, 2]) {
        await db.insert('watch_progress', {
          'kind': 'vod', 'item_id': id, 'position_ms': 10, 'duration_ms': 100,
          'updated_at': 5, 'title': 'x',
        });
      }
      await store.snapshot();
      await db.delete('watch_progress');
      await db.delete('vod_items');
      // Assistido depois da troca (mais novo que o guardado).
      await db.insert('watch_progress', {
        'kind': 'vod', 'item_id': 70, 'position_ms': 99, 'duration_ms': 100,
        'updated_at': 50, 'title': 'A',
      });
      final c = (await store.load())!;
      expect(c.progress.length, 2);
      final a = c.progress.firstWhere((p) => p['name'] == 'A');
      final b = c.progress.firstWhere((p) => p['name'] == 'B');
      await store.relinkProgress(a, itemId: 70);
      final row = await db.query('watch_progress', where: 'item_id = 70');
      expect(row.single['position_ms'], 99, reason: 'o mais novo fica');
      await store.remove(CarryGroup.progress, b);
      expect(await store.load(), isNull);
    });
  });
}
