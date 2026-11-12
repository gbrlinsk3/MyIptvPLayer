import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/app_log.dart';
import '../core/secret_store.dart';
import 'catalog_models.dart';
import '../downloads/download_store.dart';
import '../library/library_import.dart';
import 'catalog_store.dart';
import 'epg_parsing.dart' show XmltvRow;
import 'models.dart';

class _CorruptDatabase implements Exception {}

/// Resultado de [AppDatabase.repairHistory].
class RepairReport {
  const RepairReport({
    required this.backupPath,
    required this.integrityOk,
    required this.fixed,
    required this.removedInvalid,
    required this.removedOrphans,
  });

  /// Cópia de segurança feita antes de mexer (nula se não foi possível).
  final String? backupPath;
  final bool integrityOk;

  /// Linhas corrigidas (valores impossíveis ajustados).
  final int fixed;

  /// Linhas removidas por serem inutilizáveis (tipo desconhecido, episódio sem série).
  final int removedInvalid;

  /// Linhas removidas por apontar para títulos que não existem mais no catálogo.
  final int removedOrphans;

  bool get changedAnything => fixed + removedInvalid + removedOrphans > 0;
}

class DbDiagnostics {
  const DbDiagnostics({
    required this.path,
    required this.sizeBytes,
    required this.schemaVersion,
    required this.quickCheckOk,
    required this.counts,
  });

  final String path;
  final int sizeBytes;
  final int schemaVersion;
  final bool quickCheckOk;
  final Map<String, int> counts;
}

/// Banco SQLite local: conta, ajustes, cache do catálogo, EPG e categorias ocultas.
///
/// Versões do esquema:
///  1 = conta, ajustes, catálogo de TV ao vivo.
///  2 = + epg_channel_id nos canais, tabelas de EPG, categorias ocultas.
///  3 = + filmes, séries e progresso de reprodução.
class AppDatabase {
  AppDatabase._(this._db, {required this.recoveredFromCorruption});

  final Database _db;

  /// true quando o arquivo antigo estava ilegível e foi movido para um
  /// arquivo `.corrupt-<timestamp>` ao lado do original (um banco novo foi criado).
  final bool recoveredFromCorruption;

  /// Filmes, séries e progresso (esquema versão 3).
  late final CatalogStore catalog = CatalogStore(_db);

  /// Downloads (esquema versão 4).
  late final DownloadStore downloads = DownloadStore(_db);
  late final ImportStore imports = ImportStore(_db);

  /// Pasta onde ficam todos os bancos do app (índice de perfis e um banco por perfil).
  static Future<Directory> supportDirectory() async {
    sqfliteFfiInit();
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return dir;
  }

  /// Nome do banco da versão anterior (antes dos perfis), usado na migração.
  static const legacyFileName = 'iptv_player.db';

  Future<void> close() => _db.close();

  /// Repara o histórico de reprodução (`watch_progress`). Faz antes uma cópia de
  /// segurança do banco (`<arquivo>.backup-<data>`, guarda as 3 mais recentes) e
  /// depois, numa transação: ajusta valores impossíveis (posição negativa ou
  /// maior que a duração) e remove linhas inutilizáveis. Com [removeOrphans],
  /// remove também o progresso de títulos que sumiram do catálogo (só se o
  /// catálogo correspondente não estiver vazio, para nunca apagar tudo por
  /// engano). Arquivos importados (id negativo) nunca são considerados órfãos.
  Future<RepairReport> repairHistory({bool removeOrphans = false}) async {
    String? backup;
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      backup = '${_db.path}.backup-$stamp';
      await _db.execute("VACUUM INTO '${backup.replaceAll("'", "''")}'");
      await _pruneBackups();
    } catch (e, st) {
      AppLog.error('historico.backup', e, st);
      backup = null;
    }

    final check = await _db.rawQuery('PRAGMA integrity_check');
    final integrityOk = check.isNotEmpty && check.first.values.first == 'ok';

    var fixed = 0, invalid = 0, orphans = 0;
    await _db.transaction((txn) async {
      fixed += await txn.rawUpdate(
        'UPDATE watch_progress SET position_ms = 0 WHERE position_ms < 0',
      );
      fixed += await txn.rawUpdate(
        'UPDATE watch_progress SET duration_ms = 0 WHERE duration_ms < 0',
      );
      fixed += await txn.rawUpdate(
        'UPDATE watch_progress SET position_ms = duration_ms, watched = 1 '
        'WHERE duration_ms > 0 AND position_ms > duration_ms',
      );
      invalid += await txn.rawDelete(
        "DELETE FROM watch_progress WHERE kind NOT IN ('vod', 'episode')",
      );
      invalid += await txn.rawDelete(
        "DELETE FROM watch_progress WHERE kind = 'episode' AND series_id IS NULL",
      );
      if (removeOrphans) {
        Future<int> count(String table) async {
          final r = await txn.rawQuery('SELECT COUNT(*) FROM $table');
          final v = r.isEmpty ? 0 : r.first.values.first;
          return v is int ? v : 0;
        }

        if (await count('vod_items') > 0) {
          orphans += await txn.rawDelete(
            "DELETE FROM watch_progress WHERE kind = 'vod' AND item_id > 0 "
            'AND item_id NOT IN (SELECT id FROM vod_items)',
          );
        }
        if (await count('series_items') > 0) {
          orphans += await txn.rawDelete(
            "DELETE FROM watch_progress WHERE kind = 'episode' "
            'AND series_id NOT IN (SELECT id FROM series_items)',
          );
        }
      }
    });
    AppLog.info(
      'historico.reparo',
      'corrigidos=$fixed inválidos=$invalid órfãos=$orphans integridade=$integrityOk',
    );
    return RepairReport(
      backupPath: backup,
      integrityOk: integrityOk,
      fixed: fixed,
      removedInvalid: invalid,
      removedOrphans: orphans,
    );
  }

  /// Mantém só as 3 cópias de segurança mais recentes ao lado do banco.
  Future<void> _pruneBackups() async {
    final file = File(_db.path);
    final prefix = '${file.uri.pathSegments.last}.backup-';
    final backups = [
      for (final f in file.parent.listSync())
        if (f is File && f.uri.pathSegments.last.startsWith(prefix)) f,
    ]..sort((a, b) => b.path.compareTo(a.path));
    for (final old in backups.skip(3)) {
      try {
        await old.delete();
      } catch (e) {
        AppLog.warn('historico.limparBackup', e);
      }
    }
  }

  /// Dados para a tela de diagnóstico (nada aqui altera o banco).
  Future<DbDiagnostics> diagnostics() async {
    Future<int> one(String sql) async {
      final rows = await _db.rawQuery(sql);
      final v = rows.isEmpty ? null : rows.first.values.first;
      return v is int ? v : 0;
    }

    final version = await one('PRAGMA user_version');
    final check = await _db.rawQuery('PRAGMA quick_check');
    final checkOk = check.isNotEmpty && check.first.values.first == 'ok';
    final counts = <String, int>{};
    for (final table in const [
      'live_channels',
      'vod_items',
      'series_items',
      'watch_progress',
      'downloads',
      'library_imports',
    ]) {
      try {
        counts[table] = await one('SELECT COUNT(*) FROM $table');
      } catch (_) {
        // Tabela inexistente neste esquema: simplesmente não aparece.
      }
    }
    var size = 0;
    try {
      size = await File(_db.path).length();
    } catch (_) {}
    return DbDiagnostics(
      path: _db.path,
      sizeBytes: size,
      schemaVersion: version,
      quickCheckOk: checkOk,
      counts: counts,
    );
  }

  /// Abre (ou cria) o banco em [path]. Cada perfil tem o seu próprio arquivo.
  static Future<AppDatabase> open(String path) async {
    sqfliteFfiInit();

    try {
      return AppDatabase._(await _openAt(path), recoveredFromCorruption: false);
    } catch (e) {
      // Só trata como corrupção erros do SQLite; qualquer outro (por exemplo,
      // biblioteca nativa ausente) sobe como erro, sem mexer no arquivo.
      if (e is! DatabaseException && e is! _CorruptDatabase) rethrow;
      final file = File(path);
      if (await file.exists()) {
        await file.rename(
          '$path.corrupt-${DateTime.now().millisecondsSinceEpoch}',
        );
      }
      return AppDatabase._(await _openAt(path), recoveredFromCorruption: true);
    }
  }

  static Future<Database> _openAt(String path) async {
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 9,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    final check = await db.rawQuery('PRAGMA quick_check');
    final ok = check.isNotEmpty && check.first.values.first == 'ok';
    if (!ok) {
      await db.close();
      throw _CorruptDatabase();
    }
    return db;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute(
      'CREATE TABLE account ('
      'id INTEGER PRIMARY KEY CHECK (id = 1), '
      'server TEXT NOT NULL, username TEXT NOT NULL, password TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE live_categories ('
      'id TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE live_channels ('
      'stream_id INTEGER PRIMARY KEY, name TEXT NOT NULL, icon TEXT, '
      'category_id TEXT NOT NULL, position INTEGER NOT NULL, '
      'epg_channel_id TEXT)',
    );
    await _createV2Tables(db);
    await _createV3Tables(db);
    await _createV4Tables(db);
    await _addDownloadBackdrop(db);
    await _createV6Tables(db);
    await _createV7Tables(db);
    await _createV8Tables(db);
    await _createV9Tables(db);
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE live_channels ADD COLUMN epg_channel_id TEXT');
      await _createV2Tables(db);
      // O catálogo antigo não tem os códigos de EPG: é descartado para ser
      // baixado de novo na próxima abertura (a conta e os ajustes continuam).
      await db.delete('live_channels');
      await db.delete('live_categories');
      await db.delete('settings', where: 'key = ?', whereArgs: ['catalog_updated_at']);
    }
    if (oldVersion < 3) {
      // Só acrescenta tabelas novas: nada do que já existe é alterado.
      await _createV3Tables(db);
    }
    if (oldVersion < 4) {
      await _createV4Tables(db);
    }
    if (oldVersion < 5) {
      await _addDownloadBackdrop(db);
    }
    if (oldVersion < 6) {
      await _createV6Tables(db);
    }
    if (oldVersion < 7) {
      await _createV7Tables(db);
    }
    if (oldVersion < 8) {
      await _createV8Tables(db);
    }
    if (oldVersion < 9) {
      await _createV9Tables(db);
    }
  }

  /// v8: endereço da imagem horizontal de cada título (aprendido ao pedir os
  /// detalhes ao servidor), para a busca mostrá-la na hora nas próximas vezes.
  /// v9: `library_imports.kind` ('file' = arquivo do usuário, 'recording' =
  /// gravação de TV ao vivo), para separar as gravações na biblioteca.
  static Future<void> _createV9Tables(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(library_imports)');
    if (cols.any((c) => c['name'] == 'kind')) return;
    await db.execute(
      "ALTER TABLE library_imports ADD COLUMN kind TEXT NOT NULL DEFAULT 'file'",
    );
  }

  static Future<void> _createV8Tables(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS backdrop_cache ('
      'kind TEXT NOT NULL, item_id INTEGER NOT NULL, url TEXT NOT NULL, '
      'PRIMARY KEY (kind, item_id))',
    );
  }

  /// v7: filmes e séries favoritos (só guarda o tipo e o id do título; os dados
  /// vêm do catálogo).
  static Future<void> _createV7Tables(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS favorite_titles ('
      'kind TEXT NOT NULL, item_id INTEGER NOT NULL, added_at INTEGER NOT NULL, '
      'PRIMARY KEY (kind, item_id))',
    );
  }

  /// v6: arquivos que o usuário importou para "Minha biblioteca".
  static Future<void> _createV6Tables(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS library_imports ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, file_path TEXT NOT NULL, '
      'title TEXT NOT NULL, year TEXT, plot TEXT, image TEXT, backdrop TEXT, '
      'created_at INTEGER NOT NULL)',
    );
  }

  /// v5: imagem horizontal dos downloads (para a biblioteca em cartões deitados).
  static Future<void> _addDownloadBackdrop(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(downloads)');
    if (cols.any((c) => c['name'] == 'backdrop')) return;
    await db.execute('ALTER TABLE downloads ADD COLUMN backdrop TEXT');
  }

  /// v4: downloads (filmes e episódios baixados no formato original).
  static Future<void> _createV4Tables(Database db) async {
    await db.execute(
      'CREATE TABLE downloads ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, '
      'item_id INTEGER NOT NULL, series_id INTEGER, season INTEGER, '
      'episode INTEGER, title TEXT NOT NULL, subtitle TEXT, image TEXT, '
      'ext TEXT NOT NULL, file_path TEXT NOT NULL, '
      'total_bytes INTEGER NOT NULL DEFAULT 0, '
      'done_bytes INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL, '
      'error TEXT, created_at INTEGER NOT NULL, completed_at INTEGER, '
      'UNIQUE (kind, item_id))',
    );
  }

  static Future<void> _createV3Tables(Database db) async {
    for (final kind in CatalogKind.values) {
      await db.execute(
        'CREATE TABLE ${kind.categoriesTable} ('
        'id TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE ${kind.itemsTable} ('
        'id INTEGER PRIMARY KEY, name TEXT NOT NULL, image TEXT, '
        'category_id TEXT NOT NULL, rating REAL, added INTEGER, ext TEXT, '
        'year TEXT, plot TEXT, position INTEGER NOT NULL, search_key TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE INDEX idx_${kind.itemsTable}_cat '
        'ON ${kind.itemsTable} (category_id, position)',
      );
    }
    await db.execute(
      'CREATE TABLE watch_progress ('
      'kind TEXT NOT NULL, item_id INTEGER NOT NULL, '
      'position_ms INTEGER NOT NULL, duration_ms INTEGER NOT NULL, '
      'watched INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL, '
      'title TEXT, subtitle TEXT, image TEXT, series_id INTEGER, '
      'season INTEGER, episode INTEGER, PRIMARY KEY (kind, item_id))',
    );
    await db.execute(
      'CREATE INDEX idx_progress_updated ON watch_progress (kind, updated_at)',
    );
  }

  static Future<void> _createV2Tables(Database db) async {
    await db.execute(
      'CREATE TABLE epg_sources ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT NOT NULL UNIQUE, '
      'updated_at INTEGER, program_count INTEGER NOT NULL DEFAULT 0, error TEXT)',
    );
    await db.execute(
      'CREATE TABLE epg_programs ('
      'source TEXT NOT NULL, channel_key TEXT NOT NULL, '
      'start INTEGER NOT NULL, stop INTEGER NOT NULL, '
      'title TEXT NOT NULL, descr TEXT)',
    );
    await db.execute(
      'CREATE INDEX idx_epg_lookup ON epg_programs (source, channel_key, start)',
    );
    await db.execute(
      'CREATE TABLE epg_fetch ('
      'source TEXT NOT NULL, key TEXT NOT NULL, fetched_at INTEGER NOT NULL, '
      'PRIMARY KEY (source, key))',
    );
    await db.execute(
      'CREATE TABLE hidden_categories ('
      'kind TEXT NOT NULL, category_id TEXT NOT NULL, '
      'PRIMARY KEY (kind, category_id))',
    );
  }

  // ---- conta -------------------------------------------------------------

  Future<SavedAccount?> loadAccount() async {
    final rows = await _db.query('account', where: 'id = 1');
    if (rows.isEmpty) return null;
    final r = rows.first;
    final stored = r['password'] as String;
    final account = SavedAccount(
      server: r['server'] as String,
      username: r['username'] as String,
      password: SecretStore.reveal(stored),
    );
    // Senha antiga em texto simples: protege agora (se a DPAPI funcionar).
    if (!SecretStore.isProtected(stored) && stored.isNotEmpty) {
      final p = SecretStore.protect(stored);
      if (SecretStore.isProtected(p)) {
        await _db.update('account', {'password': p}, where: 'id = 1');
        AppLog.info('seguranca', 'Senha Xtream migrada para armazenamento protegido');
      }
    }
    return account;
  }

  Future<void> saveAccount(SavedAccount account) async {
    await _db.insert(
      'account',
      {
        'id': 1,
        'server': account.server,
        'username': account.username,
        'password': SecretStore.protect(account.password),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Remove conta, catálogo, EPG do provedor e categorias ocultas (que são
  /// específicos da conta). Ajustes e fontes EPG por URL são mantidos.
  Future<void> deleteAccountAndCatalog() async {
    await _db.transaction((txn) async {
      await txn.delete('account');
      await txn.delete('live_channels');
      await txn.delete('live_categories');
      await txn.delete('hidden_categories');
      for (final kind in CatalogKind.values) {
        await txn.delete(kind.itemsTable);
        await txn.delete(kind.categoriesTable);
        await txn.delete('settings', where: 'key = ?', whereArgs: ['${kind.key}_updated_at']);
      }
      await txn.delete('watch_progress');
      await txn.delete('epg_programs', where: 'source = ?', whereArgs: ['provider']);
      await txn.delete('epg_fetch', where: 'source = ?', whereArgs: ['provider']);
      await txn.delete('settings', where: 'key = ?', whereArgs: ['catalog_updated_at']);
    });
  }

  // ---- ajustes -----------------------------------------------------------

  Future<String?> getSetting(String key) async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    await _db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSetting(String key) async {
    await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  /// Apaga filmes, séries e progresso (usado ao entrar com outra conta).
  Future<void> clearVodAndProgress() async {
    await _db.transaction((txn) async {
      for (final kind in CatalogKind.values) {
        await txn.delete(kind.itemsTable);
        await txn.delete(kind.categoriesTable);
        await txn.delete('settings', where: 'key = ?', whereArgs: ['${kind.key}_updated_at']);
      }
      await txn.delete('watch_progress');
    });
  }

  // ---- catálogo ----------------------------------------------------------

  Future<List<LiveCategory>> loadCategories() async {
    final rows = await _db.query('live_categories', orderBy: 'position ASC');
    return [
      for (final r in rows)
        LiveCategory(id: r['id'] as String, name: r['name'] as String),
    ];
  }

  Future<List<LiveChannel>> loadChannels() async {
    final rows = await _db.query('live_channels', orderBy: 'position ASC');
    return [
      for (final r in rows)
        LiveChannel(
          streamId: r['stream_id'] as int,
          name: r['name'] as String,
          categoryId: r['category_id'] as String,
          icon: r['icon'] as String?,
          epgId: r['epg_channel_id'] as String?,
        ),
    ];
  }

  /// Troca o catálogo inteiro numa única transação: se algo falhar no meio,
  /// o catálogo anterior continua intacto.
  Future<void> replaceCatalog(
    List<LiveCategory> categories,
    List<LiveChannel> channels,
  ) async {
    await _db.transaction((txn) async {
      await txn.delete('live_channels');
      await txn.delete('live_categories');
      final batch = txn.batch();
      for (var i = 0; i < categories.length; i++) {
        batch.insert(
          'live_categories',
          {'id': categories[i].id, 'name': categories[i].name, 'position': i},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (var i = 0; i < channels.length; i++) {
        final c = channels[i];
        batch.insert(
          'live_channels',
          {
            'stream_id': c.streamId,
            'name': c.name,
            'icon': c.icon,
            'category_id': c.categoryId,
            'position': i,
            'epg_channel_id': c.epgId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Limpa o catálogo e o cache de EPG do provedor. Não mexe na conta, nos
  /// ajustes, nas fontes EPG por URL nem nas categorias ocultas.
  Future<void> clearCatalog() async {
    await _db.transaction((txn) async {
      await txn.delete('live_channels');
      await txn.delete('live_categories');
      await txn.delete('epg_programs', where: 'source = ?', whereArgs: ['provider']);
      await txn.delete('epg_fetch', where: 'source = ?', whereArgs: ['provider']);
      await txn.delete('settings', where: 'key = ?', whereArgs: ['catalog_updated_at']);
    });
  }

  // ---- categorias ocultas -----------------------------------------------

  Future<Set<String>> loadHiddenCategories(String kind) async {
    final rows = await _db.query(
      'hidden_categories',
      where: 'kind = ?',
      whereArgs: [kind],
    );
    return {for (final r in rows) r['category_id'] as String};
  }

  Future<void> setCategoriesHidden(
    String kind,
    Iterable<String> ids, {
    required bool hidden,
  }) async {
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final id in ids) {
        if (hidden) {
          batch.insert(
            'hidden_categories',
            {'kind': kind, 'category_id': id},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        } else {
          batch.delete(
            'hidden_categories',
            where: 'kind = ? AND category_id = ?',
            whereArgs: [kind, id],
          );
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> clearHiddenCategories() async {
    await _db.delete('hidden_categories');
  }

  // ---- EPG: fontes por URL ----------------------------------------------

  Future<List<EpgSource>> loadEpgSources() async {
    final rows = await _db.query('epg_sources', orderBy: 'id ASC');
    return [
      for (final r in rows)
        EpgSource(
          id: r['id'] as int,
          url: r['url'] as String,
          updatedAt: r['updated_at'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (r['updated_at'] as int) * 1000,
                ),
          programCount: (r['program_count'] as int?) ?? 0,
          error: r['error'] as String?,
        ),
    ];
  }

  Future<int> insertEpgSource(String url) {
    return _db.insert('epg_sources', {'url': url});
  }

  Future<void> updateEpgSourceStatus(int id, Map<String, Object?> values) async {
    await _db.update('epg_sources', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteEpgSource(int id) async {
    await _db.transaction((txn) async {
      await txn.delete('epg_sources', where: 'id = ?', whereArgs: [id]);
      await txn.delete('epg_programs', where: 'source = ?', whereArgs: ['url:$id']);
    });
  }

  // ---- EPG: programas ----------------------------------------------------

  Future<List<EpgProgram>> epgPrograms(
    String source,
    String key, {
    required int fromEpoch,
  }) async {
    final rows = await _db.query(
      'epg_programs',
      where: 'source = ? AND channel_key = ? AND stop >= ?',
      whereArgs: [source, key, fromEpoch],
      orderBy: 'start ASC',
    );
    return [
      for (final r in rows)
        EpgProgram(
          start: r['start'] as int,
          stop: r['stop'] as int,
          title: r['title'] as String,
          description: r['descr'] as String?,
        ),
    ];
  }

  Future<int?> epgFetchedAt(String source, String key) async {
    final rows = await _db.query(
      'epg_fetch',
      where: 'source = ? AND key = ?',
      whereArgs: [source, key],
    );
    if (rows.isEmpty) return null;
    return rows.first['fetched_at'] as int;
  }

  /// Troca os programas de um canal (EPG do provedor) e registra quando foram buscados.
  Future<void> replaceChannelPrograms(
    String source,
    String key,
    List<EpgProgram> programs,
    int fetchedAt,
  ) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'epg_programs',
        where: 'source = ? AND channel_key = ?',
        whereArgs: [source, key],
      );
      final batch = txn.batch();
      for (final prog in programs) {
        batch.insert('epg_programs', {
          'source': source,
          'channel_key': key,
          'start': prog.start,
          'stop': prog.stop,
          'title': prog.title,
          'descr': prog.description,
        });
      }
      batch.insert(
        'epg_fetch',
        {'source': source, 'key': key, 'fetched_at': fetchedAt},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await batch.commit(noResult: true);
    });
  }

  /// Troca todos os programas de uma fonte XMLTV numa única transação.
  Future<void> replaceSourcePrograms(String source, List<XmltvRow> rows) async {
    await _db.transaction((txn) async {
      await txn.delete('epg_programs', where: 'source = ?', whereArgs: [source]);
      final batch = txn.batch();
      for (final r in rows) {
        batch.insert('epg_programs', {
          'source': source,
          'channel_key': r.channel,
          'start': r.start,
          'stop': r.stop,
          'title': r.title,
          'descr': r.description,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  /// Apaga programas que já terminaram antes de [beforeEpoch].
  Future<void> pruneEpg(int beforeEpoch) async {
    await _db.delete('epg_programs', where: 'stop < ?', whereArgs: [beforeEpoch]);
    await _db.delete('epg_fetch', where: 'fetched_at < ?', whereArgs: [beforeEpoch]);
  }
}
