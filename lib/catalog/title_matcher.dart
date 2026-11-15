import '../data/models.dart' show foldText;

/// Encontra no catálogo novo o mesmo título/canal/categoria do catálogo
/// antigo, pelo nome (e pelo ano, quando houver). Usado ao trocar o Xtream do
/// mesmo provedor, quando os ids podem ter mudado.
///
/// Só aceita casamentos seguros: na dúvida (vários candidatos diferentes)
/// devolve null e o item fica para o usuário revisar.
class TitleMatcher<T> {
  TitleMatcher(Iterable<MatchCandidate<T>> items) {
    for (final c in items) {
      (_strict[strictKey(c.name)] ??= []).add(c);
      final loose = looseKey(c.name);
      if (loose.isNotEmpty) (_loose[loose] ??= []).add(c);
    }
  }

  final Map<String, List<MatchCandidate<T>>> _strict = {};
  final Map<String, List<MatchCandidate<T>>> _loose = {};

  /// Id do item que corresponde a [name]/[year]; [previousId] (o id antigo)
  /// tem preferência quando está entre os candidatos.
  T? find(String name, {String? year, T? previousId}) {
    final y = yearOf(year, name);
    // 1º: mesmo nome (ignorando maiúsculas, acentos e pontuação). Nomes e anos
    // idênticos em categorias diferentes são o mesmo título: aceita o primeiro.
    final strict = _pick(_strict[strictKey(name)], y, previousId, sameName: true);
    if (strict != null) return strict;
    // 2º: nome sem marcações (4K, FHD, LEG, DUB, [..], ano) — só se for único.
    final loose = looseKey(name);
    if (loose.isEmpty) return null;
    return _pick(_loose[loose], y, previousId, sameName: false);
  }

  T? _pick(
    List<MatchCandidate<T>>? list,
    String? year,
    T? previousId, {
    required bool sameName,
  }) {
    if (list == null || list.isEmpty) return null;
    var pool = list;
    if (year != null) {
      final sameYear = [for (final c in list) if (c.year == year) c];
      final noYear = [for (final c in list) if (c.year == null) c];
      // Ano diferente = outro título (remake, nova temporada...).
      pool = sameYear.isNotEmpty ? sameYear : noYear;
      if (pool.isEmpty) return null;
    }
    if (previousId != null) {
      for (final c in pool) {
        if (c.id == previousId) return c.id;
      }
    }
    if (pool.length == 1) return pool.first.id;
    // Vários com o mesmo nome: é o mesmo título repetido em categorias só se
    // nenhum ano os diferenciar (senão é remake/outro filme: ambíguo).
    final years = {for (final c in pool) c.year};
    return sameName && years.length == 1 ? pool.first.id : null;
  }
}

class MatchCandidate<T> {
  MatchCandidate(this.id, this.name, [String? year]) : year = yearOf(year, name);

  final T id;
  final String name;
  final String? year;
}

final _separators = RegExp(r'[\s\p{P}\p{S}]+', unicode: true);
final _brackets = RegExp(r'[\[\(\{][^\]\)\}]*[\]\)\}]');
final _yearInText = RegExp(r'(?:^|\D)((?:19|20)\d{2})(?:\D|$)');
final _isYear = RegExp(r'^(?:19|20)\d{2}$');

/// Marcações de qualidade/idioma que os provedores colam no nome.
const _noise = {
  '4k', 'uhd', 'fhd', 'hd', 'sd', 'hdr', 'h264', 'h265', 'hevc', '720p', '1080p',
  '2160p', 'leg', 'legendado', 'dub', 'dublado', 'dual', 'audio', 'nacional',
  'l', 'd', 'cam', 'ts',
};

/// Nome sem diferença de maiúsculas, acentos e pontuação.
String strictKey(String name) =>
    foldText(name).split(_separators).where((w) => w.isNotEmpty).join(' ');

/// Nome sem marcações, partes entre colchetes/parênteses e ano. Se não sobrar
/// nada (um filme chamado "1917"), devolve o nome estrito.
String looseKey(String name) {
  final words = foldText(name)
      .replaceAll(_brackets, ' ')
      .split(_separators)
      .where((w) => w.isNotEmpty && !_noise.contains(w) && !_isYear.hasMatch(w))
      .toList();
  return words.isEmpty ? strictKey(name) : words.join(' ');
}

/// Ano de 4 dígitos do campo [year] ou, sem ele, do próprio nome.
String? yearOf(String? year, String name) {
  if (year != null) {
    final m = _yearInText.firstMatch(year);
    if (m != null) return m.group(1);
  }
  final m = _yearInText.firstMatch(name);
  return m?.group(1);
}
