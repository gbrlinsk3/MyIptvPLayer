import 'dart:async';
import 'dart:isolate';

import 'smart_search.dart';

/// Faz a busca num isolate separado: normalizar milhares de nomes e comparar
/// cada letra digitada com todos eles não trava mais a interface.
///
/// O índice (id, categoria, nome, nota) é enviado uma vez por tipo; depois cada
/// busca manda só o texto e recebe ids e pontuações.
class SearchWorker {
  SearchWorker._(this._isolate, this._port);

  final Isolate _isolate;
  final SendPort _port;

  static Future<SearchWorker> start() async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_main, ready.sendPort);
    final port = await ready.first as SendPort;
    ready.close();
    return SearchWorker._(isolate, port);
  }

  Future<Object?> _call(List<Object?> message) async {
    final reply = ReceivePort();
    _port.send([...message, reply.sendPort]);
    final result = await reply.first;
    reply.close();
    if (result is List && result.isNotEmpty && result[0] == 'error') {
      throw StateError('${result[1]}');
    }
    return result;
  }

  /// Envia (ou troca) o índice de um tipo ("vod" ou "series").
  Future<void> load(
    String kind, {
    required List<int> ids,
    required List<String> categories,
    required List<String> keys,
    required List<double> ratings,
  }) async {
    await _call(['load', kind, ids, categories, keys, ratings]);
  }

  Future<SearchHits> query(
    String kind,
    String text,
    Set<String> hidden, {
    int bestLimit = 300,
    int relatedLimit = 60,
  }) async {
    final r = await _call(
      ['query', kind, text, hidden.toList(), bestLimit, relatedLimit],
    ) as List;
    final scoreIds = (r[2] as List).cast<int>();
    final scoreVals = (r[3] as List).cast<double>();
    return SearchHits(
      best: (r[0] as List).cast<int>(),
      related: (r[1] as List).cast<int>(),
      scores: {
        for (var i = 0; i < scoreIds.length; i++) scoreIds[i]: scoreVals[i],
      },
    );
  }

  void dispose() => _isolate.kill(priority: Isolate.immediate);

  // ---- lado do isolate ----------------------------------------------------------

  static void _main(SendPort toMain) {
    final port = ReceivePort();
    toMain.send(port.sendPort);
    final index = <String, List<SearchEntry>>{};
    port.listen((dynamic raw) {
      final m = raw as List;
      final reply = m.last as SendPort;
      try {
        switch (m[0]) {
          case 'load':
            final ids = (m[2] as List).cast<int>();
            final cats = (m[3] as List).cast<String>();
            final keys = (m[4] as List).cast<String>();
            final ratings = (m[5] as List).cast<double>();
            index[m[1] as String] = [
              for (var i = 0; i < ids.length; i++)
                SearchEntry(
                  id: ids[i],
                  categoryId: cats[i],
                  rawKey: keys[i],
                  rating: ratings[i],
                ),
            ];
            reply.send(['ok']);
          case 'query':
            final hits = SmartSearch.runBilingual(
              index[m[1] as String] ?? const [],
              m[2] as String,
              hidden: (m[3] as List).cast<String>().toSet(),
              bestLimit: m[4] as int,
              relatedLimit: m[5] as int,
            );
            reply.send([
              hits.best,
              hits.related,
              hits.scores.keys.toList(),
              hits.scores.values.toList(),
            ]);
          default:
            reply.send(['error', 'mensagem desconhecida: ${m[0]}']);
        }
      } catch (e) {
        reply.send(['error', '$e']);
      }
    });
  }
}
