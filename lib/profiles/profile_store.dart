import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db.dart';
import 'profile.dart';
import '../core/app_log.dart';

class _CorruptIndex implements Exception {}

/// Índice de perfis (`profiles.db`) e caminhos dos bancos de cada perfil
/// (`profile_<id>.db`). O índice só guarda nome, avatar e cor.
class ProfileStore {
  ProfileStore._(this._db, this._dir, {required this.recovered});

  final Database _db;
  final Directory _dir;

  /// true quando o índice estava ilegível e foi recriado (os bancos dos perfis
  /// que existiam em disco foram religados como "Perfil N").
  final bool recovered;

  static const _indexName = 'profiles.db';

  static Future<ProfileStore> open() async {
    final dir = await AppDatabase.supportDirectory();
    final path = p.join(dir.path, _indexName);
    try {
      final db = await _openAt(path);
      final store = ProfileStore._(db, dir, recovered: false);
      await store._migrateLegacy();
      return store;
    } catch (e) {
      if (e is! DatabaseException && e is! _CorruptIndex) rethrow;
      final file = File(path);
      if (await file.exists()) {
        await file.rename('$path.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      }
      final db = await _openAt(path);
      final store = ProfileStore._(db, dir, recovered: true);
      await store._adoptOrphans();
      await store._migrateLegacy();
      return store;
    }
  }

  static Future<Database> _openAt(String path) async {
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE profiles ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, '
          'avatar TEXT NOT NULL, accent INTEGER NOT NULL, '
          'created_at INTEGER NOT NULL)',
        ),
      ),
    );
    final check = await db.rawQuery('PRAGMA quick_check');
    if (check.isEmpty || check.first.values.first != 'ok') {
      await db.close();
      throw _CorruptIndex();
    }
    return db;
  }

  String pathFor(int id) => p.join(_dir.path, 'profile_$id.db');

  // ---- migração -----------------------------------------------------------

  /// Se existe o banco da versão sem perfis e ainda não há perfis, ele vira o
  /// primeiro perfil (o arquivo é renomeado, nada é apagado).
  Future<void> _migrateLegacy() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS n FROM profiles');
    final count = rows.isEmpty ? 0 : (rows.first['n'] as int? ?? 0);
    if (count > 0) return;
    final legacy = File(p.join(_dir.path, AppDatabase.legacyFileName));
    if (!await legacy.exists()) return;

    var name = 'Perfil 1';
    try {
      final old = await AppDatabase.open(legacy.path);
      final account = await old.loadAccount();
      await old.close();
      if (account != null && account.username.trim().isNotEmpty) {
        name = account.username.trim();
      }
    } catch (e) {
      AppLog.warn('perfis.migracao', e);
      // Mantém o nome padrão; o arquivo é migrado mesmo assim.
    }
    final id = await _insert(name, avatarKeys.first, profileAccents.first);
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('${legacy.path}$suffix');
      if (await f.exists()) await f.rename('${pathFor(id)}$suffix');
    }
  }

  /// Depois de um índice corrompido: cria entradas para `profile_<id>.db` soltos.
  Future<void> _adoptOrphans() async {
    final re = RegExp(r'^profile_(\d+)\.db$');
    final ids = <int>[];
    await for (final e in _dir.list()) {
      if (e is! File) continue;
      final m = re.firstMatch(p.basename(e.path));
      if (m != null) ids.add(int.parse(m.group(1)!));
    }
    ids.sort();
    for (var i = 0; i < ids.length; i++) {
      await _db.insert('profiles', {
        'id': ids[i],
        'name': 'Perfil ${i + 1}',
        'avatar': avatarKeys[i % avatarKeys.length],
        'accent': profileAccents.first,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  // ---- perfis --------------------------------------------------------------

  Future<List<Profile>> list() async {
    final rows = await _db.query('profiles', orderBy: 'id');
    return [
      for (final r in rows)
        Profile(
          id: r['id'] as int,
          name: r['name'] as String,
          avatar: r['avatar'] as String,
          accent: r['accent'] as int,
        ),
    ];
  }

  Future<int> _insert(String name, String avatar, int accent) {
    return _db.insert('profiles', {
      'name': name,
      'avatar': avatar,
      'accent': accent,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<Profile> create(String name, String avatar, int accent) async {
    final id = await _insert(name, avatar, accent);
    return Profile(id: id, name: name, avatar: avatar, accent: accent);
  }

  Future<void> update(Profile profile) async {
    await _db.update(
      'profiles',
      {'name': profile.name, 'avatar': profile.avatar, 'accent': profile.accent},
      where: 'id = ?',
      whereArgs: [profile.id],
    );
  }

  /// Remove o perfil e o banco dele (conta, catálogo, ajustes e EPG daquele perfil).
  Future<void> delete(int id) async {
    await _db.delete('profiles', where: 'id = ?', whereArgs: [id]);
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('${pathFor(id)}$suffix');
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (e) {
          AppLog.warn('perfis.apagarArquivo', e);
          // Arquivo em uso: fica órfão, sem aparecer na lista.
        }
      }
    }
  }
}
