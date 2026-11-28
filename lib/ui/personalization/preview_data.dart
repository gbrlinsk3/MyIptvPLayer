import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/catalog_models.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../catalog/poster_image.dart' show isLocalImagePath;
import '../widgets/app_backdrop.dart';
import 'preview_look.dart';

/// Um item desenhado nas prévias: nome e, se houver, a imagem.
typedef PreviewItem = ({String name, String? image});

/// O conteúdo do próprio usuário mostrado nas prévias. Só lê o que o app já
/// tem; o que faltar vira um bloco liso.
class PreviewData {
  const PreviewData({
    this.banners = const [],
    this.continuing = const [],
    this.movies = const [],
    this.series = const [],
    this.recentChannels = const [],
    this.channelRows = const [],
    this.highlights = const [],
    this.downloads = const [],
    this.imports = const [],
    this.recordings = const [],
  });

  /// Banners do Início, na ordem: nome do banner e os títulos dele.
  final List<({String name, List<PreviewItem> titles})> banners;
  final List<PreviewItem> continuing;
  final List<PreviewItem> movies;
  final List<PreviewItem> series;
  final List<PreviewItem> recentChannels;
  final List<({String name, List<PreviewItem> channels})> channelRows;

  /// Destaques da TV ao vivo: a palavra-chave e canais que ela encontrou.
  final List<({String name, List<PreviewItem> channels})> highlights;

  /// Minha biblioteca: filmes baixados, "Meus arquivos" e "Gravações".
  final List<PreviewItem> downloads;
  final List<PreviewItem> imports;
  final List<PreviewItem> recordings;

  static const int _perRow = 14;

  static Future<PreviewData> load(AppController c) async {
    PreviewItem title(CatalogTitle t) => (name: t.name, image: t.image);
    PreviewItem channel(LiveChannel l) => (name: l.name, image: l.icon);

    /// Uma fonte que falhe deixa só a sua parte em blocos.
    Future<List<T>> safe<T>(Future<List<T>> Function() read) async {
      try {
        return await read();
      } catch (_) {
        return <T>[];
      }
    }

    final catalog = c.catalog;
    final slides = await safe(() => catalog.heroSlides());
    final continuing = await safe(() => catalog.continueAll());
    final movies = await safe(() => catalog.recentTitles(CatalogKind.movies));
    final series = await safe(() => catalog.recentTitles(CatalogKind.series));

    final channels = c.allChannels;
    final byId = {for (final l in channels) l.streamId: l};
    final recent = [
      for (final id in c.recentChannels) ?byId[id],
    ];
    final rows = <({String name, List<PreviewItem> channels})>[];
    for (final category in c.categories) {
      if (rows.length == 3) break;
      final inside = [
        for (final l in channels)
          if (l.categoryId == category.id) l,
      ].take(_perRow).toList();
      if (inside.isEmpty) continue;
      rows.add((
        name: category.name,
        channels: [for (final l in inside) channel(l)],
      ));
    }

    return PreviewData(
      banners: [
        for (final s in slides)
          (name: s.kicker, titles: [for (final t in s.titles) title(t)]),
      ],
      continuing: [for (final t in continuing.take(_perRow)) title(t)],
      movies: [for (final t in movies.take(_perRow)) title(t)],
      series: [for (final t in series.take(_perRow)) title(t)],
      recentChannels: [
        for (final l in (recent.isEmpty ? channels : recent).take(_perRow))
          channel(l),
      ],
      channelRows: rows,
      highlights: [
        for (final h in c.highlights.take(3))
          (
            name: h.keyword,
            channels: [for (final l in h.channels.take(4)) channel(l)],
          ),
      ],
      downloads: [
        for (final e in c.downloads.finished.where((e) => e.isMovie).take(_perRow))
          (name: e.title, image: e.backdrop ?? e.image),
      ],
      imports: [
        for (final i in c.imports.items
            .where((i) => !i.isRecording)
            .take(_perRow))
          (name: i.title, image: i.backdrop ?? i.image),
      ],
      recordings: [
        for (final i in c.imports.items
            .where((i) => i.isRecording)
            .take(_perRow))
          (name: i.title, image: i.backdrop ?? i.image),
      ],
    );
  }
}

/// Imagem que a prévia só mostra se já estiver no PC: do cache de imagens do
/// app ou um arquivo local. **Não baixa nada**; sem ela, fica o [fallback].
class PreviewImage extends StatefulWidget {
  const PreviewImage({
    super.key,
    required this.url,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.cacheWidth = 240,
  });

  final String? url;
  final Widget fallback;
  final BoxFit fit;
  final int cacheWidth;

  /// Caminhos já descobertos: trocar de aba ou de opção não faz piscar.
  static final Map<String, String> _paths = {};

  @override
  State<PreviewImage> createState() => _PreviewImageState();
}

class _PreviewImageState extends State<PreviewImage> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _find();
  }

  @override
  void didUpdateWidget(PreviewImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _find();
  }

  Future<void> _find() async {
    final url = widget.url;
    _path = null;
    if (url == null || url.isEmpty) return;
    if (isLocalImagePath(url)) {
      _path = url;
      return;
    }
    final known = PreviewImage._paths[url];
    if (known != null) {
      _path = known;
      return;
    }
    if (!url.startsWith('http')) return;
    try {
      final info = await CachedNetworkImageProvider.defaultCacheManager
          .getFileFromCache(url);
      if (info == null) return;
      final path = PreviewImage._paths[url] = info.file.path;
      if (mounted && widget.url == url) setState(() => _path = path);
    } catch (_) {
      // Sem cache legível: fica o bloco.
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    if (path == null) return widget.fallback;
    return Image.file(
      File(path),
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) => widget.fallback,
    );
  }
}

/// Os fundos prontos que as prévias usam, um por tema, imagem e desfoque. Quem
/// cria é dono: descartar ao sair de Personalização.
class PreviewBackdrops extends ChangeNotifier {
  final Map<String, ui.Image> _ready = {};
  final Set<String> _loading = {};
  bool _disposed = false;

  /// A imagem de fundo de [look], ou nulo enquanto é preparada (ou se o tema
  /// não mostra imagem). [currentBlur] é o desfoque em uso no app: com ele a
  /// prévia aproveita o fundo que o app já preparou.
  ui.Image? of(PreviewLook look, {required int currentBlur}) {
    if (!look.showImage) return null;
    final key = '${look.background}|${look.dark}|${look.blur}';
    final image = _ready[key];
    if (image == null && _loading.add(key)) {
      // Depois da construção: preparar pode notificar na mesma hora.
      Future.microtask(() => _load(key, look, shared: look.blur == currentBlur));
    }
    return image;
  }

  Future<void> _load(String key, PreviewLook look, {required bool shared}) async {
    final candidates = BackdropRender.candidates(look.background);
    ui.Image? image;
    if (shared) {
      image = await BackdropRender.load(
        candidates,
        dark: look.dark,
        chose: look.background.isNotEmpty,
        blur: look.blur,
        report: false,
      );
    } else {
      // Outro desfoque (opção sob o mouse): fora do cache do app, que guarda
      // só os dois temas em uso.
      for (final candidate in candidates) {
        try {
          image = await BackdropRender.bake(
            await candidate.read(),
            dark: look.dark,
            blur: candidate.origin == BackdropOrigin.chosen
                ? look.blur
                : BackdropBlur.standard,
          );
          break;
        } catch (_) {
          // Tenta o próximo (a imagem do app).
        }
      }
    }
    if (image == null) return;
    if (_disposed) {
      image.dispose();
      return;
    }
    _ready[key] = image;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _ready.values) {
      image.dispose();
    }
    _ready.clear();
    super.dispose();
  }
}
