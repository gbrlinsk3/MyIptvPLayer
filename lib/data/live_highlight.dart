import 'models.dart';

/// Um destaque da TV ao vivo: uma palavra-chave e os canais das categorias
/// cujo nome contém essa palavra.
class LiveHighlight {
  const LiveHighlight({
    required this.keyword,
    required this.categories,
    required this.channels,
  });

  /// Como o usuário escreveu a palavra (a tela mostra em maiúsculas).
  final String keyword;
  final List<LiveCategory> categories;
  final List<LiveChannel> channels;
}

/// Palavras-chave iniciais (o usuário pode trocar em Conta e ajustes).
const defaultHighlightKeywords = <String>[
  'Eventos',
  'Destaque',
  'Esportes',
  'Notícias',
  'Filmes',
  'Séries',
  'Infantil',
  'Documentários',
];

const maxHighlights = 4;
const maxChannelsPerHighlight = 60;

/// Para cada palavra-chave, na ordem, junta as categorias visíveis cujo nome
/// (sem acentos, minúsculo) contém a palavra e os canais delas. Uma categoria
/// só entra no primeiro destaque que a encontrar; destaque sem canal não
/// aparece; no máximo [maxHighlights].
List<LiveHighlight> computeHighlights({
  required List<String> keywords,
  required List<LiveCategory> categories,
  required List<LiveChannel> channels,
}) {
  if (keywords.isEmpty || categories.isEmpty || channels.isEmpty) return const [];
  final byCategory = <String, List<LiveChannel>>{};
  for (final ch in channels) {
    (byCategory[ch.categoryId] ??= []).add(ch);
  }
  final used = <String>{};
  final out = <LiveHighlight>[];
  for (final raw in keywords) {
    final word = foldText(raw.trim());
    if (word.isEmpty) continue;
    final cats = [
      for (final c in categories)
        if (!used.contains(c.id) &&
            (byCategory[c.id]?.isNotEmpty ?? false) &&
            foldText(c.name).contains(word))
          c,
    ];
    if (cats.isEmpty) continue;
    used.addAll(cats.map((c) => c.id));
    final list = <LiveChannel>[
      for (final c in cats) ...byCategory[c.id]!,
    ];
    out.add(LiveHighlight(
      keyword: raw.trim(),
      categories: cats,
      channels: list.take(maxChannelsPerHighlight).toList(growable: false),
    ));
    if (out.length >= maxHighlights) break;
  }
  return out;
}

// ---- mini banners (fileira abaixo do banner principal) --------------------

/// Mini banners por aba do banner principal.
const miniSlotsPerSlide = 4;

/// Abas (slides) que têm fileira de mini banners.
const miniSlides = maxHighlights;

/// Cada espaço guarda um "token": `kw:<palavra>` (categorias cujo nome contém
/// a palavra), `cat:<id>` (uma categoria escolhida pelo usuário) ou vazio.
/// A aba 1 já vem com palavras-chave; as demais vêm vazias.
const defaultMiniBannerKeywords = <String>['HBO', 'Premiere', 'SporTV', 'Telecine'];

List<List<String>> defaultMiniBanners() => [
      [for (final w in defaultMiniBannerKeywords) 'kw:$w'],
      for (var i = 1; i < miniSlides; i++) List<String>.filled(miniSlotsPerSlide, ''),
    ];

/// Um mini banner já resolvido (com categorias e canais).
class MiniBanner {
  const MiniBanner({
    required this.label,
    required this.categories,
    required this.channels,
  });

  final String label;
  final List<LiveCategory> categories;
  final List<LiveChannel> channels;
}

/// Resolve um token em categorias/canais; nulo se vazio ou sem canais.
MiniBanner? resolveMiniBanner(
  String token, {
  required List<LiveCategory> categories,
  required Map<String, List<LiveChannel>> channelsByCategory,
}) {
  if (token.startsWith('kw:')) {
    final raw = token.substring(3).trim();
    final word = foldText(raw);
    if (word.isEmpty) return null;
    final cats = [
      for (final c in categories)
        if ((channelsByCategory[c.id]?.isNotEmpty ?? false) &&
            foldText(c.name).contains(word))
          c,
    ];
    if (cats.isEmpty) return null;
    return MiniBanner(
      label: raw,
      categories: cats,
      channels: [for (final c in cats) ...channelsByCategory[c.id]!],
    );
  }
  if (token.startsWith('cat:')) {
    final id = token.substring(4);
    for (final c in categories) {
      final list = channelsByCategory[c.id];
      if (c.id == id && list != null && list.isNotEmpty) {
        return MiniBanner(label: c.name, categories: [c], channels: list);
      }
    }
  }
  return null;
}
