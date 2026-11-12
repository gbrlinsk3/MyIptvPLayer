import '../data/models.dart' show foldText;
import 'title_dictionary.dart';

/// Uma linha do índice de busca: só o necessário para comparar nomes.
class SearchEntry {
  SearchEntry({
    required this.id,
    required this.categoryId,
    required String rawKey,
    required this.rating,
  }) : key = SmartSearch.normalize(rawKey);

  final int id;
  final String categoryId;

  /// Nome sem acentos, sem pontuação, palavras separadas por um espaço
  /// ("Homem-Aranha" vira "homem aranha").
  final String key;

  /// Mesmo texto sem espaços ("homemaranha"), para casar "spiderman"/"spider man".
  /// Calculado só quando usado (a normalização já foi feita uma vez em [key]).
  late final String joined = key.replaceAll(' ', '');
  final double rating;
}

class SearchHits {
  const SearchHits({
    this.best = const [],
    this.related = const [],
    this.scores = const {},
  });

  /// Pontuação de cada id devolvido (maior = mais parecido).
  final Map<int, double> scores;

  /// Ids dos que melhor combinam com tudo o que foi digitado, do melhor ao pior.
  final List<int> best;

  /// Ids que combinam só com parte da busca (ou de forma menos exata).
  final List<int> related;

  bool get isEmpty => best.isEmpty && related.isEmpty;
}

/// Busca tolerante: ignora acentos, hífen e pontuação; aceita as palavras em
/// qualquer ordem; aceita prefixos ("homem ara"), erros leves de digitação
/// ("homen aranha") e nomes juntos/separados ("spiderman" = "spider man").
/// Os pesos abaixo são escolhas minhas, não medidas no seu catálogo.
class SmartSearch {
  static final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  static const _stop = {
    'de', 'da', 'do', 'das', 'dos', 'e', 'o', 'a', 'os', 'as', 'em', 'no',
    'na', 'the', 'of', 'and', 'to', 'in',
  };

  static String normalize(String s) =>
      foldText(s).replaceAll(_nonWord, ' ').trim();

  // Pontuação de uma palavra digitada contra as palavras do nome.
  static const _exact = 1.0;
  static const _prefix = 0.85;
  static const _inside = 0.6;
  static const _typo = 0.5;

  /// Busca o que foi digitado **e** a tradução palavra por palavra
  /// (português ↔ inglês, ver [TitleDictionary]). Une os dois resultados
  /// mantendo a maior pontuação de cada título; resultados vindos só da
  /// tradução valem um pouco menos (x0,97), para o que combina literalmente
  /// ficar na frente.
  static SearchHits runBilingual(
    List<SearchEntry> index,
    String query, {
    Set<String> hidden = const {},
    int bestLimit = 300,
    int relatedLimit = 60,
  }) {
    final direct = run(index, query,
        hidden: hidden, bestLimit: bestLimit, relatedLimit: relatedLimit);
    final other = TitleDictionary.translate(query);
    if (other == null) return direct;
    final translated = run(index, other,
        hidden: hidden, bestLimit: bestLimit, relatedLimit: relatedLimit);
    if (translated.isEmpty) return direct;

    const penalty = 0.97;
    final scores = <int, double>{...direct.scores};
    final best = <int>{...direct.best};
    for (final id in translated.best) {
      final sc = (translated.scores[id] ?? 0) * penalty;
      if ((scores[id] ?? -1) < sc) scores[id] = sc;
      best.add(id);
    }
    final related = <int>{
      for (final id in [...direct.related, ...translated.related])
        if (!best.contains(id)) id,
    };
    for (final id in translated.related) {
      final sc = (translated.scores[id] ?? 0) * penalty;
      if ((scores[id] ?? -1) < sc) scores[id] = sc;
    }
    int byScore(int x, int y) => (scores[y] ?? 0).compareTo(scores[x] ?? 0);
    final bestOut = (best.toList()..sort(byScore)).take(bestLimit).toList();
    final relatedOut = (related.toList()..sort(byScore)).take(relatedLimit).toList();
    return SearchHits(best: bestOut, related: relatedOut, scores: scores);
  }

  static SearchHits run(
    List<SearchEntry> index,
    String query, {
    Set<String> hidden = const {},
    int bestLimit = 300,
    int relatedLimit = 60,
  }) {
    final nq = normalize(query);
    if (nq.isEmpty) return const SearchHits();
    final all = nq.split(' ');
    var needed = [for (final t in all) if (!_stop.contains(t)) t];
    if (needed.isEmpty) needed = all;
    final joinedQuery = nq.replaceAll(' ', '');

    final strong = <_Scored>[];
    final weak = <_Scored>[];
    final partial = <_Scored>[];

    for (final e in index) {
      if (hidden.contains(e.categoryId)) continue;
      final words = e.key.split(' ');
      var sum = 0.0;
      var matched = 0;
      var allStrong = true;
      for (final q in needed) {
        final s = _wordScore(q, words);
        if (s > 0) {
          matched++;
          sum += s;
          if (s < _inside) allStrong = false;
        } else {
          allStrong = false;
        }
      }

      var full = matched == needed.length;
      var score = sum / needed.length;
      var isStrong = full && allStrong;
      // "spiderman" x "spider man": o texto inteiro aparece sem espaços.
      if (!full && joinedQuery.length >= 4 && e.joined.contains(joinedQuery)) {
        full = true;
        isStrong = true;
        score = 0.95;
      }

      if (full) {
        if (e.key == nq) score += 1.0;
        if (e.key.startsWith(nq)) score += 0.5;
        if (e.key.contains(nq)) score += 0.3;
        score += (e.rating.clamp(0, 10)) / 10 * 0.05;
        score -= words.length * 0.002; // nomes mais curtos primeiro
        (isStrong ? strong : weak).add(_Scored(e.id, score));
      } else if (matched > 0 && sum >= _inside) {
        partial.add(_Scored(e.id, score + e.rating.clamp(0, 10) / 10 * 0.05));
      }
    }

    int byScore(_Scored a, _Scored b) => b.score.compareTo(a.score);
    strong.sort(byScore);
    weak.sort(byScore);
    partial.sort(byScore);

    // Com acertos exatos, os "quase" (erros de digitação) vão para os extras;
    // sem nenhum exato, eles são o resultado principal.
    final best = strong.isNotEmpty ? strong : weak;
    final extra = [
      if (strong.isNotEmpty) ...weak,
      ...partial,
    ];
    final bestOut = best.take(bestLimit).toList();
    final relatedOut = extra.take(relatedLimit).toList();
    return SearchHits(
      best: [for (final s in bestOut) s.id],
      related: [for (final s in relatedOut) s.id],
      scores: {
        for (final s in [...bestOut, ...relatedOut]) s.id: s.score,
      },
    );
  }

  static double _wordScore(String q, List<String> words) {
    var best = 0.0;
    for (final w in words) {
      if (w == q) return _exact;
      if (best < _prefix && q.length >= 2 && w.startsWith(q)) {
        best = _prefix;
      } else if (best < _inside && q.length >= 3 && w.contains(q)) {
        best = _inside;
      } else if (best < _typo && q.length >= 4) {
        final diff = w.length - q.length;
        if (diff.abs() <= 2) {
          final max = q.length <= 5 ? 1 : 2;
          if (_within(q, w, max)) best = _typo;
        }
      } else if (best < _typo &&
          q.length >= 2 &&
          q.length < 4 &&
          w.length <= q.length + 1 &&
          w.length >= q.length &&
          w.codeUnitAt(0) == q.codeUnitAt(0) &&
          _within(q, w, 1)) {
        // Palavras curtas ("te" por "the"): 1 letra de diferença, mesma inicial.
        best = _typo;
      }
    }
    return best;
  }

  /// Distância de edição (Levenshtein) limitada a [max]: para cedo se passar.
  static bool _within(String a, String b, int max) {
    if ((a.length - b.length).abs() > max) return false;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = prev[j - 1] + cost;
        if (prev[j] + 1 < v) v = prev[j] + 1;
        if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > max) return false;
      prev = cur;
    }
    return prev[b.length] <= max;
  }
}

class _Scored {
  const _Scored(this.id, this.score);

  final int id;
  final double score;
}
