import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/catalog_models.dart';
import '../data/db.dart';
import 'download_models.dart';
import '../core/app_info.dart';
import '../core/app_log.dart';
import '../core/disk_space.dart';
import '../core/format.dart';

/// Resultado de [DownloadsController.moveToCurrentFolder].
class MoveResult {
  const MoveResult({
    required this.moved,
    required this.skipped,
    required this.failed,
    this.busy = false,
  });

  final int moved;

  /// Já havia arquivo no destino, ou o original não existe mais.
  final int skipped;
  final int failed;

  /// Não rodou porque há downloads em andamento.
  final bool busy;
}

class _Stopped implements Exception {
  _Stopped(this.cancel);

  /// true = cancelar e apagar; false = só pausar.
  final bool cancel;
}

/// Baixa filmes e episódios **no formato original** (o mesmo arquivo que o
/// provedor entrega, sem recomprimir), um por vez, com pausa e retomada
/// (cabeçalho Range, se o servidor aceitar). Cada perfil tem a sua lista.
class DownloadsController extends ChangeNotifier {
  DownloadsController(
    this._db, {
    required this.urlFor,
    required this.headers,
  });

  final AppDatabase _db;

  /// Endereço de download do item (nulo se não houver conta).
  final String? Function(CatalogKind kind, int itemId, String ext) urlFor;
  final Map<String, String>? Function() headers;

  static const _maxParallel = 1;

  /// Tentativas automáticas depois de uma queda de conexão (retomando de onde
  /// parou) e a espera antes de cada uma, em segundos.
  static const _retryDelays = [5, 15, 45, 90];
  static const _incomplete =
      'Download incompleto (a conexão foi encerrada). Toque em retomar.';

  /// Pausa o download enquanto algo está sendo assistido (filme/série pela
  /// internet ou TV ao vivo): evita estourar o limite de conexões da conta.
  bool pauseOnPlayback = true;
  int _suspended = 0;
  final Set<int> _pausedByPlayback = {};

  final Map<int, int> _retries = {};
  final Map<int, DateTime> _notBefore = {};
  final Map<int, Timer> _retryTimers = {};

  List<DownloadEntry> entries = const [];
  String? customFolder;
  String defaultFolder = '';
  bool loaded = false;

  /// Ao procurar arquivos baixados que sumiram, olhar também as subpastas da
  /// pasta de downloads (por padrão, só a própria pasta).
  bool scanSubfolders = false;

  // ids de downloads concluídos cujo arquivo não foi achado ao abrir.
  final Set<int> _missing = {};

  final Map<int, http.Client> _clients = {};
  final Map<int, StreamSubscription<List<int>>> _subs = {};
  final Map<int, Completer<void>> _waiters = {};
  final Map<int, _Stopped> _stopping = {};
  int _active = 0;
  bool _disposed = false;

  String get folder => (customFolder != null && customFolder!.isNotEmpty)
      ? customFolder!
      : defaultFolder;

  // ---- consulta -----------------------------------------------------------------

  DownloadEntry? entryFor(CatalogKind kind, int itemId) {
    final key = '${kind.progressKind}:$itemId';
    for (final e in entries) {
      if (e.key == key) return e;
    }
    return null;
  }

  /// Caminho do arquivo baixado e completo, se existir de verdade.
  String? localPath(CatalogKind kind, int itemId) {
    final e = entryFor(kind, itemId);
    if (e == null || !e.isDone) return null;
    return File(e.filePath).existsSync() ? e.filePath : null;
  }

  List<DownloadEntry> get unfinished =>
      [for (final e in entries) if (!e.isDone) e];
  List<DownloadEntry> get finished =>
      [for (final e in entries) if (e.isDone) e];

  int get usedBytes => finished.fold(0, (a, e) => a + e.doneBytes);
  bool get hasActive => entries.any(
        (e) =>
            e.status == DownloadStatus.downloading ||
            e.status == DownloadStatus.queued,
      );

  // ---- carregar -------------------------------------------------------------------

  Future<void> load() async {
    try {
      final base = await getDownloadsDirectory() ??
          await AppDatabase.supportDirectory();
      defaultFolder = p.join(base.path, AppInfo.downloadsFolder);
    } catch (e) {
      AppLog.warn('downloads.pasta', e);
      defaultFolder = p.join((await AppDatabase.supportDirectory()).path, 'downloads');
    }
    customFolder = await _db.getSetting('download_dir');
    scanSubfolders = await _db.getSetting('download_scan_subfolders') == '1';
    pauseOnPlayback = await _db.getSetting('download_pause_on_play') != '0';
    final list = await _db.downloads.all();
    for (final e in list) {
      if (e.status == DownloadStatus.downloading ||
          e.status == DownloadStatus.queued) {
        // O app foi fechado no meio: volta como pausado (retoma de onde parou).
        e.status = DownloadStatus.paused;
      }
      if (e.isDone) {
        if (!File(e.filePath).existsSync()) {
          e.status = DownloadStatus.error;
          e.error = 'Arquivo não encontrado (foi apagado ou movido).';
          e.doneBytes = 0;
          if (e.id != null) _missing.add(e.id!);
        }
      } else {
        final part = File('${e.filePath}.part');
        e.doneBytes = part.existsSync() ? part.lengthSync() : 0;
      }
    }
    entries = list;
    loaded = true;
    await reconcile();
    _notify();
  }

  /// Parte do caminho a partir da pasta `Filmes`/`Séries` (desenho de pastas
  /// do app), ou só o nome do arquivo se o caminho não seguir esse desenho.
  static List<String> _layoutParts(String filePath) {
    final parts = p.split(filePath);
    final at = parts.indexWhere((s) => s == 'Filmes' || s == 'Séries');
    return at >= 0 ? parts.sublist(at) : [p.basename(filePath)];
  }

  /// Concluídos cujo arquivo está fora da pasta de downloads atual
  /// (por exemplo, ficaram na pasta anterior depois de uma troca).
  List<DownloadEntry> get outsideCurrentFolder {
    final base = p.normalize(folder);
    return [
      for (final e in entries)
        if (e.isDone && !p.isWithin(base, p.normalize(e.filePath))) e,
    ];
  }

  bool _moving = false;
  bool get moving => _moving;

  /// Move para a pasta atual os downloads concluídos que estão fora dela,
  /// mantendo o desenho `Filmes/`, `Séries/<série>/Temporada NN/`. Nunca
  /// sobrescreve: se já existe um arquivo no destino, o item é pulado.
  /// Tenta renomear (rápido, mesmo disco) e, se falhar (outro disco), copia e
  /// apaga a origem só depois da cópia terminar. Não roda com downloads ativos.
  Future<MoveResult> moveToCurrentFolder({
    void Function(int done, int total)? onProgress,
  }) async {
    if (_moving) return const MoveResult(moved: 0, skipped: 0, failed: 0);
    if (hasActive) {
      return const MoveResult(moved: 0, skipped: 0, failed: 0, busy: true);
    }
    _moving = true;
    _notify();
    final list = outsideCurrentFolder;
    var moved = 0, skipped = 0, failed = 0, done = 0;
    try {
      await Directory(folder).create(recursive: true);
      for (final e in list) {
        onProgress?.call(done, list.length);
        final source = File(e.filePath);
        final target = File(p.joinAll([folder, ..._layoutParts(e.filePath)]));
        try {
          if (!source.existsSync()) {
            skipped++;
          } else if (target.existsSync()) {
            skipped++;
          } else {
            await target.parent.create(recursive: true);
            try {
              await source.rename(target.path);
            } on FileSystemException {
              // Outro disco: copia e só então apaga a origem.
              await source.copy(target.path);
              if (target.lengthSync() != source.lengthSync()) {
                await target.delete();
                throw const FileSystemException('Cópia incompleta');
              }
              await source.delete();
            }
            final old = e.filePath;
            e.filePath = target.path;
            await _db.downloads.update(e);
            await _pruneAppFolders(old);
            moved++;
          }
        } catch (err, st) {
          failed++;
          AppLog.error('downloads.mover ${e.title}', err, st);
        }
        done++;
      }
      onProgress?.call(done, list.length);
    } finally {
      _moving = false;
      _notify();
    }
    return MoveResult(moved: moved, skipped: skipped, failed: failed);
  }

  /// Apaga pastas vazias do desenho do app (`Séries/<série>/Temporada NN`,
  /// `Filmes`...) deixadas para trás, até a própria pasta `Filmes`/`Séries`.
  Future<void> _pruneAppFolders(String oldFilePath) async {
    try {
      final parts = p.split(oldFilePath);
      final at = parts.indexWhere((s) => s == 'Filmes' || s == 'Séries');
      if (at < 0) return;
      for (var i = parts.length - 2; i >= at; i--) {
        final dir = Directory(p.joinAll(parts.sublist(0, i + 1)));
        if (!dir.existsSync() || dir.listSync().isNotEmpty) break;
        await dir.delete();
      }
    } catch (err) {
      AppLog.warn('downloads.limparPastas', err);
    }
  }

  Future<void> setScanSubfolders(bool value) async {
    scanSubfolders = value;
    await _db.setSetting('download_scan_subfolders', value ? '1' : '0');
    _notify();
    if (value) await reconcile();
  }

  /// Reconhece de novo downloads concluídos cujo arquivo não está mais no
  /// caminho gravado (por exemplo, depois de mudar de pasta e mover os arquivos).
  /// Procura primeiro no mesmo desenho de pastas do app (`Filmes/`, `Séries/...`)
  /// dentro da pasta atual e, depois, pelo nome do arquivo: só na própria pasta,
  /// ou também nas subpastas se [scanSubfolders] estiver ligado.
  /// Devolve quantos foram reconhecidos.
  Future<int> reconcile() async {
    if (_missing.isEmpty) return 0;
    final root = Directory(folder);
    if (!await root.exists()) return 0;

    Map<String, String>? byName;
    Future<Map<String, String>> index() async {
      final map = <String, String>{};
      try {
        await for (final ent in root.list(recursive: scanSubfolders, followLinks: false)) {
          if (ent is File && !ent.path.endsWith('.part')) {
            map.putIfAbsent(p.basename(ent.path).toLowerCase(), () => ent.path);
          }
        }
      } catch (err) {
        AppLog.warn('downloads.varredura', err);
      }
      return map;
    }

    var found = 0;
    for (final e in entries) {
      if (e.id == null || !_missing.contains(e.id)) continue;
      String? hit;
      // 1) mesmo desenho de pastas do app, dentro da pasta atual.
      final parts = p.split(e.filePath);
      final at = parts.indexWhere((s) => s == 'Filmes' || s == 'Séries');
      if (at >= 0) {
        final candidate = p.joinAll([root.path, ...parts.sublist(at)]);
        if (File(candidate).existsSync()) hit = candidate;
      }
      // 2) pelo nome do arquivo.
      if (hit == null) {
        byName ??= await index();
        hit = byName[p.basename(e.filePath).toLowerCase()];
      }
      if (hit == null) continue;
      e.filePath = hit;
      e.status = DownloadStatus.done;
      e.error = null;
      e.doneBytes = File(hit).lengthSync();
      await _db.downloads.update(e);
      _missing.remove(e.id);
      found++;
    }
    if (found > 0) _notify();
    return found;
  }

  Future<void> setFolder(String? value) async {
    final v = value?.trim();
    if (v == null || v.isEmpty) {
      customFolder = null;
      await _db.deleteSetting('download_dir');
    } else {
      await Directory(v).create(recursive: true); // falha = erro mostrado na tela
      customFolder = v;
      await _db.setSetting('download_dir', v);
    }
    _notify();
    await reconcile();
  }

  // ---- ações ----------------------------------------------------------------------

  /// Põe na fila (ou retoma, se já existir pausado/com erro).
  Future<void> enqueue(DownloadRequest r) async {
    final existing = entryFor(r.kind, r.itemId);
    if (existing != null) {
      if (existing.isDone &&
          File(existing.filePath).existsSync()) {
        return;
      }
      await resume(existing);
      return;
    }
    final path = _targetPath(r);
    final e = DownloadEntry(
      kind: r.kind,
      itemId: r.itemId,
      title: r.title,
      subtitle: r.subtitle,
      image: r.image,
      backdrop: r.backdrop,
      ext: r.ext,
      seriesId: r.seriesId,
      season: r.season,
      episode: r.episode,
      filePath: path,
      status: DownloadStatus.queued,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    e.id = await _db.downloads.insert(e);
    entries = [...entries, e];
    _notify();
    _pump();
  }

  Future<void> enqueueAll(List<DownloadRequest> list) async {
    for (final r in list) {
      await enqueue(r);
    }
  }

  Future<void> pause(DownloadEntry e) async {
    if (e.status == DownloadStatus.queued) {
      e.status = DownloadStatus.paused;
      e.error = null;
      if (e.id != null) {
        _retries.remove(e.id);
        _notBefore.remove(e.id);
      }
      await _db.downloads.update(e);
      _notify();
      return;
    }
    if (e.status != DownloadStatus.downloading) return;
    _stop(e, cancel: false);
  }

  Future<void> resume(DownloadEntry e) async {
    if (e.status == DownloadStatus.downloading ||
        e.status == DownloadStatus.queued ||
        (e.isDone && File(e.filePath).existsSync())) {
      return;
    }
    e.status = DownloadStatus.queued;
    e.error = null;
    if (e.id != null) {
      _retries.remove(e.id);
      _notBefore.remove(e.id);
    }
    if (e.isDone) e.doneBytes = 0;
    await _db.downloads.update(e);
    _notify();
    _pump();
  }

  /// Cancela um download não concluído e apaga o que já foi baixado.
  Future<void> cancel(DownloadEntry e) async {
    if (e.status == DownloadStatus.downloading) {
      _stop(e, cancel: true);
      return; // _run termina e remove a entrada
    }
    await _remove(e, deleteFile: true);
  }

  /// Apaga o arquivo baixado e tira o item da biblioteca.
  Future<void> deleteDownload(DownloadEntry e) async {
    if (e.status == DownloadStatus.downloading) {
      _stop(e, cancel: true);
      return;
    }
    await _remove(e, deleteFile: true);
  }

  /// Apaga vários de uma vez (ex.: uma série inteira).
  Future<void> deleteMany(Iterable<DownloadEntry> list) async {
    for (final e in list.toList()) {
      await deleteDownload(e);
    }
  }

  Future<void> openFolder([DownloadEntry? e]) async {
    try {
      if (e != null && File(e.filePath).existsSync()) {
        await Process.run('explorer.exe', ['/select,', e.filePath]);
      } else {
        await Directory(folder).create(recursive: true);
        await Process.run('explorer.exe', [folder]);
      }
    } catch (e) {
      AppLog.warn('downloads.abrirPasta', e);
    }
  }

  // ---- fila -----------------------------------------------------------------------

  void _stop(DownloadEntry e, {required bool cancel}) {
    final id = e.id;
    if (id == null) return;
    _stopping[id] = _Stopped(cancel);
    _subs[id]?.cancel();
    _clients[id]?.close();
    final w = _waiters[id];
    if (w != null && !w.isCompleted) w.completeError(_stopping[id]!);
  }

  Future<void> setPauseOnPlayback(bool value) async {
    pauseOnPlayback = value;
    await _db.setSetting('download_pause_on_play', value ? '1' : '0');
    _notify();
    if (!value) _pump();
  }

  /// Chamado quando um player vai abrir. Pausa o download ativo (se a opção
  /// estiver ligada) e segura a fila até [resumeAfterPlayback].
  void suspendForPlayback() {
    _suspended++;
    if (!pauseOnPlayback) return;
    for (final e in entries) {
      if (e.status == DownloadStatus.downloading && e.id != null) {
        _pausedByPlayback.add(e.id!);
        _stop(e, cancel: false);
      }
    }
  }

  /// Chamado quando o player fecha: retoma o que foi pausado por ele.
  Future<void> resumeAfterPlayback() async {
    if (_suspended > 0) _suspended--;
    if (_suspended > 0 || _disposed) return;
    final ids = {..._pausedByPlayback};
    _pausedByPlayback.clear();
    for (final e in entries.toList()) {
      if (e.id == null || !ids.contains(e.id)) continue;
      // O download pausado pode ainda estar terminando de parar.
      for (var i = 0; i < 15 && e.status == DownloadStatus.downloading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (e.status == DownloadStatus.paused) await resume(e);
    }
    _pump();
  }

  void _pump() {
    if (_disposed || (_suspended > 0 && pauseOnPlayback)) return;
    while (_active < _maxParallel) {
      DownloadEntry? next;
      final now = DateTime.now();
      for (final e in entries) {
        if (e.status != DownloadStatus.queued) continue;
        final wait = e.id == null ? null : _notBefore[e.id];
        if (wait != null && wait.isAfter(now)) {
          // Em espera para a nova tentativa: volta a olhar quando passar.
          _retryTimers[e.id!] ??= Timer(
            wait.difference(now) + const Duration(milliseconds: 100),
            () {
              _retryTimers.remove(e.id);
              _pump();
            },
          );
          continue;
        }
        next = e;
        break;
      }
      if (next == null) return;
      _active++;
      next.status = DownloadStatus.downloading;
      unawaited(_run(next));
    }
  }

  Future<void> _run(DownloadEntry e) async {
    final id = e.id!;
    final part = File('${e.filePath}.part');
    final startBytes = e.doneBytes;
    _notBefore.remove(id);
    e.error = null;
    IOSink? sink;
    final client = http.Client();
    _clients[id] = client;
    _notify();
    try {
      final url = urlFor(e.kind, e.itemId, e.ext);
      if (url == null) throw 'Sem conta Xtream neste perfil.';
      await part.parent.create(recursive: true);
      var have = part.existsSync() ? part.lengthSync() : 0;

      final uri = Uri.parse(url);
      Future<http.StreamedResponse> open(int from) {
        final req = http.Request('GET', uri);
        final h = headers();
        if (h != null) req.headers.addAll(h);
        if (from > 0) req.headers['Range'] = 'bytes=$from-';
        return client.send(req).timeout(const Duration(seconds: 30));
      }

      var resp = await open(have);
      if (resp.statusCode == 416 && have > 0) {
        // "Faixa inválida": o arquivo já está completo OU o .part é maior que o
        // arquivo real. Confere o tamanho de verdade antes de decidir.
        final fromHeader = _rangeTotal(resp);
        await resp.stream.drain<void>().catchError((Object _) {});
        final total = fromHeader ?? await _probeTotal(client, uri);
        if (total == null) {
          AppLog.warn('downloads.tamanho ${e.title}',
              'Servidor não informou o tamanho; considerando completo.');
          await _finish(e, part);
          return;
        }
        if (total == have) {
          await _finish(e, part);
          return;
        }
        AppLog.warn('downloads.parcialInconsistente ${e.title}',
            '.part com $have bytes, arquivo real com $total; recomeçando.');
        await part.delete();
        have = 0;
        e.doneBytes = 0;
        resp = await open(0);
      }
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw 'O servidor respondeu ${resp.statusCode}.';
      }
      final append = resp.statusCode == 206 && have > 0;
      if (!append) have = 0;
      final len = resp.contentLength;
      // Tamanho total: do Content-Range (se vier) ou do Content-Length.
      e.totalBytes = _rangeTotal(resp) ?? (len == null ? 0 : have + len);
      e.doneBytes = have;

      // Espaço livre: só dá erro se a medição funcionou e não cabe.
      if (e.totalBytes > 0) {
        final need = e.totalBytes - have;
        final free = await DiskSpace.freeBytes(p.dirname(e.filePath));
        if (free != null && free < need + _spareBytes) {
          throw 'Espaço insuficiente no disco: faltam '
              '${formatBytes(need + _spareBytes - free)} '
              '(livre: ${formatBytes(free)}, necessário: ${formatBytes(need)}).';
        }
      }
      sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);

      final finished = Completer<void>();
      _waiters[id] = finished;
      var lastNotify = DateTime.now();
      var lastSave = DateTime.now();
      var lastBytes = e.doneBytes;
      final sub = resp.stream.timeout(const Duration(seconds: 60)).listen(
        (chunk) {
          sink!.add(chunk);
          e.doneBytes += chunk.length;
          final now = DateTime.now();
          final ms = now.difference(lastNotify).inMilliseconds;
          if (ms >= 500) {
            final inst = (e.doneBytes - lastBytes) * 1000 / ms;
            e.speed = e.speed == 0 ? inst : e.speed * 0.6 + inst * 0.4;
            lastBytes = e.doneBytes;
            lastNotify = now;
            _notify();
            if (now.difference(lastSave).inSeconds >= 5) {
              lastSave = now;
              unawaited(_db.downloads.update(e));
            }
          }
        },
        onError: (Object err, StackTrace st) {
          if (!finished.isCompleted) finished.completeError(err);
        },
        onDone: () {
          if (!finished.isCompleted) finished.complete();
        },
        cancelOnError: true,
      );
      _subs[id] = sub;
      await finished.future;
      await sink.flush();
      await sink.close();
      sink = null;
      if (e.totalBytes > 0 && e.doneBytes < e.totalBytes) {
        throw _incomplete;
      }
      if (e.totalBytes == 0) {
        // O servidor não informou o tamanho: pergunta de novo para ter certeza
        // de que a conexão não caiu no meio.
        final t = await _probeTotal(client, uri);
        if (t == null) {
          AppLog.warn('downloads.tamanho ${e.title}',
              'Sem como conferir se o arquivo veio completo.');
        } else if (e.doneBytes < t) {
          throw _incomplete;
        } else if (e.doneBytes > t) {
          await part.delete();
          e.doneBytes = 0;
          throw _incomplete;
        }
      }
      await _finish(e, part);
    } catch (err) {
      if (_disposed) return; // perfil fechado: volta pausado na próxima abertura
      try {
        await sink?.close();
      } catch (e) {
        AppLog.warn('downloads.fechar', e);
      }
      final stop = _stopping[id] ?? (err is _Stopped ? err : null);
      if (stop != null) {
        if (stop.cancel) {
          await _remove(e, deleteFile: true);
        } else {
          e.status = DownloadStatus.paused;
          e.speed = 0;
          await _db.downloads.update(e);
        }
      } else {
        final tries = _retries[id] ?? 0;
        // Se esta tentativa baixou algo, a contagem recomeça.
        final used = e.doneBytes > startBytes ? 0 : tries;
        if (_isNetworkError(err) && used < _retryDelays.length) {
          final delay = _retryDelays[used];
          _retries[id] = used + 1;
          _notBefore[id] = DateTime.now().add(Duration(seconds: delay));
          AppLog.warn(
            'downloads.novaTentativa ${e.title}',
            '${_message(err)} (tentativa ${used + 1}/${_retryDelays.length} em ${delay}s)',
          );
          e.status = DownloadStatus.queued;
          e.speed = 0;
          e.error = 'Conexão interrompida. Nova tentativa em ${delay}s '
              '(${used + 1}/${_retryDelays.length})…';
          await _db.downloads.update(e);
        } else {
          AppLog.error('downloads.falha ${e.title}', err);
          e.status = DownloadStatus.error;
          e.speed = 0;
          e.error = _message(err);
          await _db.downloads.update(e);
        }
      }
    } finally {
      if (e.status != DownloadStatus.queued) {
        _retries.remove(id);
        _notBefore.remove(id);
      }
      _clients.remove(id)?.close();
      _subs.remove(id);
      _waiters.remove(id);
      _stopping.remove(id);
      _active--;
      _notify();
      _pump();
    }
  }

  /// Falhas de rede que valem uma nova tentativa automática (o servidor
  /// recusar com 403/404 etc. não entra: repetir não resolve).
  static bool _isNetworkError(Object err) =>
      err is TimeoutException ||
      err is SocketException ||
      err is http.ClientException ||
      err is HttpException ||
      err is TlsException ||
      err == _incomplete;

  /// Margem de espaço livre exigida além do tamanho do arquivo (50 MB).
  static const _spareBytes = 50 * 1024 * 1024;

  /// Tamanho total a partir de `Content-Range: bytes a-b/TOTAL` (ou `*/TOTAL`).
  static int? _rangeTotal(http.BaseResponse resp) {
    final v = resp.headers['content-range'];
    if (v == null) return null;
    final m = RegExp(r'/(\d+)\s*$').firstMatch(v);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Pergunta o tamanho real do arquivo pedindo só o primeiro byte. Nulo se o
  /// servidor não informar (ou falhar).
  Future<int?> _probeTotal(http.Client client, Uri uri) async {
    try {
      final req = http.Request('GET', uri);
      final h = headers();
      if (h != null) req.headers.addAll(h);
      req.headers['Range'] = 'bytes=0-0';
      final resp = await client.send(req).timeout(const Duration(seconds: 30));
      final fromRange = _rangeTotal(resp);
      final len = resp.statusCode == 200 ? resp.contentLength : null;
      unawaited(resp.stream.listen((_) {}).cancel()); // fecha sem baixar o corpo
      return fromRange ?? len;
    } catch (err) {
      AppLog.warn('downloads.sondar', err);
      return null;
    }
  }

  String _message(Object err) {
    if (err is TimeoutException) return 'O servidor não respondeu a tempo.';
    if (err is SocketException) return 'Sem conexão com o servidor.';
    if (err is http.ClientException ||
        err is HttpException ||
        err is TlsException) {
      return 'A conexão com o servidor foi interrompida.';
    }
    if (err is FileSystemException) {
      final why = err.osError?.message ?? err.message;
      return 'Não foi possível gravar o arquivo (disco cheio ou sem permissão?): $why';
    }
    return '$err';
  }

  Future<void> _finish(DownloadEntry e, File part) async {
    final target = File(e.filePath);
    if (target.existsSync()) await target.delete();
    await part.rename(e.filePath);
    e.status = DownloadStatus.done;
    e.error = null;
    e.speed = 0;
    e.doneBytes = await target.length();
    e.totalBytes = e.doneBytes;
    e.completedAt = DateTime.now().millisecondsSinceEpoch;
    await _db.downloads.update(e);
  }

  Future<void> _remove(DownloadEntry e, {required bool deleteFile}) async {
    if (deleteFile) {
      for (final path in [e.filePath, '${e.filePath}.part']) {
        try {
          final f = File(path);
          if (f.existsSync()) await f.delete();
        } catch (err) {
          AppLog.warn('downloads.apagar', err);
        }
      }
      await _pruneEmptyFolders(e.filePath);
    }
    if (e.id != null) await _db.downloads.delete(e.id!);
    entries = [for (final x in entries) if (!identical(x, e)) x];
    _notify();
  }

  /// Remove pastas vazias deixadas por séries/temporadas apagadas (até a pasta base).
  Future<void> _pruneEmptyFolders(String filePath) async {
    try {
      var dir = Directory(p.dirname(filePath));
      final base = p.normalize(folder);
      while (p.isWithin(base, dir.path)) {
        if (dir.listSync().isNotEmpty) break;
        await dir.delete();
        dir = dir.parent;
      }
    } catch (err) {
      AppLog.warn('downloads.limparPastas', err);
    }
  }

  // ---- nomes de arquivo -----------------------------------------------------------

  static String _clean(String name) {
    var s = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'[. ]+$'), '');
    if (s.length > 100) s = s.substring(0, 100).trim();
    return s.isEmpty ? 'Sem nome' : s;
  }

  String _targetPath(DownloadRequest r) {
    final String rel;
    if (r.kind == CatalogKind.movies) {
      rel = p.join('Filmes', '${_clean(r.title)}.${r.ext}');
    } else {
      final series = _clean(r.title);
      final s = r.season ?? 0;
      final ep = r.episode ?? 0;
      final code = 'S${s.toString().padLeft(2, '0')}E${ep.toString().padLeft(2, '0')}';
      final sub = r.subtitle == null
          ? ''
          : ' - ${_clean(r.subtitle!.replaceFirst(RegExp(r'^T\d+ · E\d+\s*—\s*'), ''))}';
      rel = p.join(
        'Séries',
        series,
        'Temporada ${s.toString().padLeft(2, '0')}',
        '$series - $code$sub.${r.ext}',
      );
    }
    var path = p.join(folder, rel);
    // Dois itens com o mesmo nome (ex.: filmes repetidos): acrescenta o id.
    final taken = entries.any((e) => e.filePath.toLowerCase() == path.toLowerCase());
    if (taken || File(path).existsSync()) {
      final ext = p.extension(path);
      path = '${p.withoutExtension(path)} (${r.itemId})$ext';
    }
    return path;
  }

  // ---- ciclo de vida --------------------------------------------------------------

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in _retryTimers.values) {
      t.cancel();
    }
    // Fecha as conexões; o que estava baixando volta "pausado" na próxima abertura.
    for (final s in _subs.values) {
      s.cancel();
    }
    for (final c in _clients.values) {
      c.close();
    }
    super.dispose();
  }
}
