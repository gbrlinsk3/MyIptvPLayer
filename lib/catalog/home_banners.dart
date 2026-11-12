import 'dart:convert';

import '../data/catalog_models.dart';

/// De onde vêm os títulos de um banner do Início.
enum BannerSource {
  newMovies('Filmes novos', 'Sorteia 3 entre os 100 filmes mais recentes'),
  newSeries('Séries novas', 'Sorteia 3 entre as 100 séries mais recentes'),
  newMix('Novos (filmes e séries)', 'Os mais recentes, alternando filmes e séries'),
  continueMore('Continue assistindo', 'Outros títulos em andamento (do 2º em diante)'),
  categories('Categorias', 'Sorteia 3 títulos das categorias escolhidas'),
  titles('Títulos escolhidos', 'Filmes e séries que você escolher (até 6)');

  const BannerSource(this.label, this.hint);
  final String label;
  final String hint;
}

/// Referência a um título escolhido à mão (o nome é guardado só para exibir).
class BannerTitleRef {
  const BannerTitleRef(this.kind, this.id, this.name);

  final CatalogKind kind;
  final int id;
  final String name;

  Map<String, Object> toJson() => {'k': kind.key, 'i': id, 'n': name};

  static BannerTitleRef? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['i'];
    if (id is! int) return null;
    final kind = CatalogKind.values.where((k) => k.key == j['k']).firstOrNull;
    if (kind == null) return null;
    return BannerTitleRef(kind, id, '${j['n'] ?? ''}');
  }
}

/// Um banner do Início configurável (o 1º, "Continue de onde parou", é fixo e
/// não aparece aqui). No máximo [maxExtra] configuráveis (total 5 com o fixo).
class BannerConfig {
  BannerConfig({
    required this.name,
    required this.source,
    Set<String>? categories,
    List<BannerTitleRef>? titles,
  })  : categories = categories ?? {},
        titles = titles ?? [];

  static const maxExtra = 4;
  static const maxTitles = 6;

  String name;
  BannerSource source;

  /// `m:<id>` (filmes) ou `s:<id>` (séries).
  Set<String> categories;
  List<BannerTitleRef> titles;

  BannerConfig copy() => BannerConfig(
        name: name,
        source: source,
        categories: {...categories},
        titles: [...titles],
      );

  Map<String, Object> toJson() => {
        'name': name,
        'source': source.name,
        'categories': categories.toList(),
        'titles': [for (final t in titles) t.toJson()],
      };

  static BannerConfig? fromJson(Object? j) {
    if (j is! Map) return null;
    final source =
        BannerSource.values.where((s) => s.name == j['source']).firstOrNull;
    if (source == null) return null;
    final name = '${j['name'] ?? ''}'.trim();
    return BannerConfig(
      name: name.isEmpty ? source.label : name,
      source: source,
      categories: {
        for (final c in (j['categories'] as List? ?? const []))
          if (c is String && c.length > 2) c,
      },
      titles: [
        for (final t in (j['titles'] as List? ?? const []))
          ?BannerTitleRef.fromJson(t),
      ],
    );
  }

  static String encode(List<BannerConfig> list) =>
      jsonEncode([for (final b in list) b.toJson()]);

  /// Lista vazia se o texto for inválido (o chamador usa o padrão).
  static List<BannerConfig> decode(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is! List) return const [];
      return [
        for (final j in data)
          ?fromJson(j),
      ].take(maxExtra).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Os banners de antes: Filmes novos, Séries novas, Adicionados
  /// recentemente e (se havia categorias marcadas) Animações.
  static List<BannerConfig> defaults(Set<String> animationCategories) => [
        BannerConfig(name: 'Filmes novos', source: BannerSource.newMovies),
        BannerConfig(name: 'Séries novas', source: BannerSource.newSeries),
        BannerConfig(
          name: 'Adicionados recentemente',
          source: BannerSource.newMix,
        ),
        if (animationCategories.isNotEmpty)
          BannerConfig(
            name: 'Animações',
            source: BannerSource.categories,
            categories: {...animationCategories},
          ),
      ];
}
