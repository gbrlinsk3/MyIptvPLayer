import 'models.dart';

/// Resultado de [parseChannelName]: o nome do canal sem as marcas de versão
/// (FHD, HD, ALT...) e as marcas que foram retiradas.
class ChannelNameParts {
  const ChannelNameParts({
    required this.base,
    required this.tags,
    required this.key,
    required this.label,
    required this.alt,
    required this.rank,
  });

  /// Nome sem as marcas, com as maiúsculas/minúsculas originais.
  final String base;

  /// Marcas retiradas, em maiúsculas, na ordem em que aparecem no nome.
  final List<String> tags;

  /// [base] em maiúsculas e com espaços colapsados: chave de agrupamento.
  final String key;

  /// Texto curto da versão: marcas (sem ALT) separadas por espaço, ou
  /// 'Padrão'; com ALT acrescenta ' [ALT]' no fim.
  final String label;

  final bool alt;

  /// Ordem de preferência (menor = melhor): FHD 0, HD 1, sem marca 2, 4K 3,
  /// SD 4; +10 para versões [ALT].
  final int rank;
}

const String _seps = r'\s\-|:·_/';

final RegExp _bracketed = RegExp(r'[\[\(]\s*([^\]\)]*?)\s*[\]\)]');

// Marcas escritas como palavra, precisam de separador antes.
final RegExp _trailingWord = RegExp(
  '[$_seps]+('
  r'FULL\s*HD|FHD|UHD|4K|HD|SD|ALT|HEVC|H\.?265|1080P|720P|60FPS'
  r')$',
  caseSensitive: false,
);

// ² e ³ podem vir colados ao nome.
final RegExp _trailingSup = RegExp('[$_seps]*([²³])\$');

final RegExp _trailingSeps = RegExp('[$_seps]+\$');
final RegExp _spaces = RegExp(r'\s+');

/// Devolve a forma canônica (maiúsculas) de [raw] se for uma marca de versão;
/// senão null.
String? _canonicalTag(String raw) {
  final t = raw.trim().toUpperCase().replaceAll(_spaces, ' ');
  switch (t) {
    case 'ALT':
    case 'FHD':
    case 'FULLHD':
    case 'FULL HD':
    case 'UHD':
    case '4K':
    case 'HD':
    case 'SD':
    case 'HEVC':
    case 'H265':
    case 'H.265':
    case '1080P':
    case '720P':
    case '60FPS':
    case '²':
    case '³':
      return t;
  }
  return null;
}

int _rankOf(List<String> tags) {
  bool has(Set<String> set) => tags.any(set.contains);
  var rank = 2;
  if (has(const {'FHD', 'FULLHD', 'FULL HD', '1080P'})) {
    rank = 0;
  } else if (has(const {'HD', '720P'})) {
    rank = 1;
  } else if (has(const {'4K', 'UHD'})) {
    rank = 3;
  } else if (has(const {'SD'})) {
    rank = 4;
  }
  return tags.contains('ALT') ? rank + 10 : rank;
}

/// Separa o nome base das marcas de versão. Só saem marcas no fim do nome
/// (em sequência) e marcas entre colchetes/parênteses em qualquer posição.
ChannelNameParts parseChannelName(String name) {
  var s = name;
  final found = <MapEntry<int, String>>[];

  // 1) [ALT], (FHD)... em qualquer posição. A troca por espaços mantém as
  // posições, que dão a ordem original das marcas.
  s = s.replaceAllMapped(_bracketed, (m) {
    final tag = _canonicalTag(m[1] ?? '');
    if (tag == null) return m[0]!;
    found.add(MapEntry(m.start, tag));
    return ' ' * m[0]!.length;
  });

  // 2) Marcas soltas no fim do nome, uma a uma, de trás para frente.
  while (true) {
    s = s.trimRight();
    final word = _trailingWord.firstMatch(s);
    final sup = word == null ? _trailingSup.firstMatch(s) : null;
    final m = word ?? sup;
    if (m == null) break;
    final tag = _canonicalTag(m[1]!)!;
    found.add(MapEntry(m.end - m[1]!.length, tag));
    s = s.substring(0, m.start);
  }

  found.sort((a, b) => a.key.compareTo(b.key));
  final tags = [for (final e in found) e.value];

  var base = s.replaceAll(_spaces, ' ').trim().replaceAll(_trailingSeps, '').trim();
  if (base.isEmpty) base = name.trim();
  final key = base.toUpperCase().replaceAll(_spaces, ' ');

  final alt = tags.contains('ALT');
  final plain = [
    for (final t in tags)
      if (t != 'ALT') t,
  ];
  final label = '${plain.isEmpty ? 'Padrão' : plain.join(' ')}${alt ? ' [ALT]' : ''}';

  return ChannelNameParts(
    base: base,
    tags: tags,
    key: key,
    label: label,
    alt: alt,
    rank: _rankOf(tags),
  );
}

/// Versões do mesmo canal (mesmo nome base), da melhor para a pior.
class ChannelGroup {
  ChannelGroup({
    required this.key,
    required this.displayName,
    required this.versions,
  });

  final String key;
  final String displayName;

  /// Ordenadas por qualidade; empate mantém a ordem original.
  final List<LiveChannel> versions;

  late final Map<int, String> _labels = {
    for (final v in versions) v.streamId: parseChannelName(v.name).label,
  };

  LiveChannel get primary => versions.first;

  /// Primeiro logo não vazio entre as versões.
  String? get icon {
    for (final v in versions) {
      final i = v.icon;
      if (i != null && i.isNotEmpty) return i;
    }
    return null;
  }

  bool contains(int streamId) => versions.any((v) => v.streamId == streamId);

  String labelOf(LiveChannel ch) =>
      _labels[ch.streamId] ?? parseChannelName(ch.name).label;

  /// A versão preferida se estiver no grupo; senão a principal.
  LiveChannel pick(int? preferredStreamId) {
    if (preferredStreamId != null) {
      for (final v in versions) {
        if (v.streamId == preferredStreamId) return v;
      }
    }
    return primary;
  }
}

class _Entry {
  _Entry(this.channel, this.rank, this.order);

  final LiveChannel channel;
  final int rank;
  final int order;
}

/// Agrupa [channels] pelo nome base. Grupos na ordem da primeira aparição;
/// streamId repetido é ignorado.
List<ChannelGroup> groupChannels(Iterable<LiveChannel> channels) {
  final seen = <int>{};
  final names = <String, String>{}; // chave -> nome de exibição (ordem de inserção)
  final entries = <String, List<_Entry>>{};
  var order = 0;
  for (final ch in channels) {
    if (!seen.add(ch.streamId)) continue;
    final parts = parseChannelName(ch.name);
    names.putIfAbsent(parts.key, () => parts.base);
    (entries[parts.key] ??= []).add(_Entry(ch, parts.rank, order++));
  }
  return [
    for (final e in names.entries)
      ChannelGroup(
        key: e.key,
        displayName: e.value,
        // List.sort não é estável: a ordem original desempata.
        versions: (entries[e.key]!
              ..sort((a, b) =>
                  a.rank != b.rank ? a.rank - b.rank : a.order - b.order))
            .map((x) => x.channel)
            .toList(growable: false),
      ),
  ];
}
