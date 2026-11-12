import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/app_log.dart';
import '../data/db.dart';

/// Arquivo de vídeo que o usuário adicionou por conta própria à biblioteca
/// (fora do catálogo do provedor). Fica só em "Minha biblioteca"; título,
/// sinopse, pôster e banner são editáveis por ele.
class LibraryImport {
  LibraryImport({
    this.id,
    required this.filePath,
    required this.title,
    this.year,
    this.plot,
    this.image,
    this.backdrop,
    this.kind = 'file',
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  int? id;
  String filePath;
  String title;
  String? year;
  String? plot;

  /// Pôster e banner: endereço http(s) ou caminho de arquivo no computador.
  String? image;
  String? backdrop;

  /// 'file' (adicionado pelo usuário) ou 'recording' (gravação de TV ao vivo).
  String kind;
  bool get isRecording => kind == 'recording';
  final int createdAt;

  Map<String, Object?> toRow() => {
        'file_path': filePath,
        'title': title,
        'year': year,
        'plot': plot,
        'image': image,
        'backdrop': backdrop,
        'kind': kind,
        'created_at': createdAt,
      };

  static LibraryImport fromRow(Map<String, Object?> r) => LibraryImport(
        id: r['id'] as int,
        filePath: r['file_path'] as String,
        title: r['title'] as String,
        year: r['year'] as String?,
        plot: r['plot'] as String?,
        image: r['image'] as String?,
        backdrop: r['backdrop'] as String?,
        kind: (r['kind'] as String?) ?? 'file',
        createdAt: r['created_at'] as int,
      );
}

/// Tabela `library_imports` do banco do perfil.
class ImportStore {
  ImportStore(this._db);

  final Database _db;

  Future<List<LibraryImport>> all() async {
    final rows = await _db.query('library_imports', orderBy: 'created_at ASC');
    return [for (final r in rows) LibraryImport.fromRow(r)];
  }

  Future<int> insert(LibraryImport i) => _db.insert('library_imports', i.toRow());

  Future<void> update(LibraryImport i) => _db.update(
        'library_imports',
        i.toRow(),
        where: 'id = ?',
        whereArgs: [i.id],
      );

  Future<void> delete(int id) =>
      _db.delete('library_imports', where: 'id = ?', whereArgs: [id]);
}

/// Lista de arquivos importados do perfil ativo.
class ImportsController extends ChangeNotifier {
  ImportsController(this._db);

  final AppDatabase _db;
  List<LibraryImport> items = const [];
  bool _disposed = false;

  Future<void> load() async {
    try {
      items = await _db.imports.all();
    } catch (e, st) {
      AppLog.error('biblioteca.importados', e, st);
    }
    _notify();
  }

  /// Insere (id nulo) ou atualiza.
  Future<void> save(LibraryImport i) async {
    if (i.id == null) {
      i.id = await _db.imports.insert(i);
    } else {
      await _db.imports.update(i);
    }
    await load();
  }

  /// Tira da biblioteca. O arquivo no computador **não** é apagado.
  Future<void> remove(LibraryImport i) async {
    if (i.id == null) return;
    await _db.imports.delete(i.id!);
    await load();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
