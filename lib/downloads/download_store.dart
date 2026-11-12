import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'download_models.dart';

/// Tabela `downloads` do banco do perfil.
class DownloadStore {
  DownloadStore(this._db);

  final Database _db;

  Future<List<DownloadEntry>> all() async {
    final rows = await _db.query('downloads', orderBy: 'created_at ASC');
    return [for (final r in rows) DownloadEntry.fromRow(r)];
  }

  /// Insere e devolve o id.
  Future<int> insert(DownloadEntry e) => _db.insert('downloads', e.toRow());

  Future<void> update(DownloadEntry e) async {
    if (e.id == null) return;
    await _db.update('downloads', e.toRow(), where: 'id = ?', whereArgs: [e.id]);
  }

  Future<void> delete(int id) =>
      _db.delete('downloads', where: 'id = ?', whereArgs: [id]);
}
