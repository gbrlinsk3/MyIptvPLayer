import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/layout_metrics.dart';
import '../../core/theme.dart';
import '../widgets/cubos_logo.dart';
import 'preview_data.dart';
import 'preview_look.dart';
import 'preview_parts.dart';

/// As abas que a prévia grande mostra.
enum PreviewTab {
  home('Início', 0),
  live('TV ao vivo', 1),
  catalog('Filmes e séries', 2),
  library('Biblioteca', 4);

  const PreviewTab(this.label, this.sidebarIndex);

  final String label;
  final int sidebarIndex;
}

/// Uma aba do app em tamanho de janela ([size], em pixels lógicos), para ser
/// reduzida por quem a mostra. É um desenho parado, com as medidas das telas de
/// verdade: nada rola, toca ou responde.
class PreviewScreen extends StatelessWidget {
  const PreviewScreen({
    super.key,
    required this.tab,
    required this.look,
    required this.data,
    required this.size,
    this.backdrop,
  });

  final PreviewTab tab;
  final PreviewLook look;
  final PreviewData data;
  final Size size;
  final ui.Image? backdrop;

  static const double _rail = 68;
  static const double _top = 64;

  /// Largura da coluna de conteúdo e a sobra de cada lado.
  static ({double width, double margin}) column(Size size, int catalogWidth) {
    final free = math.max(0.0, size.width - _rail);
    if (catalogWidth == CatalogWidth.fill || free <= catalogWidth) {
      return (width: free, margin: 0);
    }
    return (
      width: catalogWidth.toDouble(),
      margin: (free - catalogWidth) / 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final parts = PreviewParts(look);
    final frame = column(size, look.catalogWidth);
    final width = frame.width;
    return SizedBox.fromSize(
      size: size,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 13,
          color: parts.p.text,
          decoration: TextDecoration.none,
        ),
        child: Stack(
          children: [
            Positioned.fill(child: parts.ground(backdrop)),
            Positioned(
              left: _rail + frame.margin,
              top: _top,
              width: width,
              bottom: 0,
              // Lista parada: recorta o que passa da tela sem estourar.
              child: ListView(
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: switch (tab) {
                  PreviewTab.home => _home(parts, width),
                  PreviewTab.live => _live(parts),
                  PreviewTab.catalog => _catalog(parts, width),
                  PreviewTab.library => _library(parts),
                },
              ),
            ),
            Positioned(
              left: _rail,
              right: 0,
              top: 0,
              height: _top,
              child: _topBar(parts),
            ),
            Positioned(
              left: 6,
              top: 8,
              bottom: 8,
              width: 56,
              child: _sidebar(parts),
            ),
          ],
        ),
      ),
    );
  }

  // ---- moldura -------------------------------------------------------------

  Widget _sidebar(PreviewParts parts) {
    const icons = [
      (Icons.home_outlined, Icons.home_rounded),
      (Icons.live_tv_outlined, Icons.live_tv_rounded),
      (Icons.local_movies_outlined, Icons.local_movies_rounded),
      (Icons.favorite_border_rounded, Icons.favorite_rounded),
      (Icons.folder_special_outlined, Icons.folder_special_rounded),
    ];
    final p = parts.p;
    Widget item(IconData icon, bool selected) => Container(
          height: 42,
          margin: const EdgeInsets.only(bottom: 4),
          alignment: Alignment.center,
          decoration: selected
              ? BoxDecoration(
                  color: p.selected,
                  borderRadius: look.control,
                  border: Border.all(color: p.selectedEdge),
                )
              : null,
          child: Icon(icon, size: 20, color: selected ? p.accentInk : p.muted),
        );
    final divider = Container(
      height: 1,
      margin: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      color: p.line,
    );
    return parts.panel(
      radius: look.panel,
      fill: p.barFill,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: CubosLogo(size: 30, color: p.accent)),
          divider,
          for (var i = 0; i < icons.length; i++)
            item(
              i == tab.sidebarIndex ? icons[i].$2 : icons[i].$1,
              i == tab.sidebarIndex,
            ),
          divider,
          item(Icons.settings_outlined, false),
          const Spacer(),
          Icon(Icons.chevron_right, size: 20, color: p.muted),
        ],
      ),
    );
  }

  Widget _topBar(PreviewParts parts) {
    final p = parts.p;
    return Row(
      children: [
        const SizedBox(width: 12),
        SizedBox(
          width: 360,
          height: 40,
          child: parts.panel(
            radius: look.control,
            fill: p.barFill,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.search, size: 18, color: p.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: parts.text(
                    'Buscar filmes, séries e canais...',
                    color: p.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: p.accent, borderRadius: look.control),
          child: Icon(Icons.person, size: 20, color: p.onAccent),
        ),
        const SizedBox(width: 20),
        for (final icon in const [Icons.remove, Icons.crop_square, Icons.close])
          SizedBox(width: 40, child: Icon(icon, size: 16, color: p.muted)),
      ],
    );
  }

  Widget _heading(PreviewParts parts, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(RowMetrics.pad, 0, 0, 12),
        child: parts.text(label, size: 18, weight: FontWeight.w700),
      );

  /// Quantos itens uma fileira desenha: os que existem, até [fit]; sem
  /// nenhum, blocos no lugar de todos.
  static int _shown(List<PreviewItem> list, int fit) =>
      list.isEmpty ? fit : math.min(list.length, fit);

  /// Fileira de itens que segue para fora da tela.
  Widget _strip({
    required double height,
    required double gap,
    required int count,
    required Widget Function(int i) item,
    double left = RowMetrics.pad,
  }) =>
      SizedBox(
        height: height,
        child: ListView.separated(
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.only(left: left),
          itemCount: count,
          separatorBuilder: (_, _) => SizedBox(width: gap),
          itemBuilder: (_, i) => item(i),
        ),
      );

  Widget _posters(PreviewParts parts, double width, List<PreviewItem> list) {
    final count = RowMetrics.portraitCount(look.scalePercent);
    final w = RowMetrics.portraitWidth(width, count);
    return _strip(
      height: w * 1.5,
      gap: RowMetrics.gap,
      count: _shown(list, count + 1),
      item: (i) => SizedBox(
        width: w,
        child: parts.image(itemAt(list, i).image, radius: look.card),
      ),
    );
  }

  // ---- Início ----------------------------------------------------------------

  List<Widget> _home(PreviewParts parts, double width) {
    final height = HeroMetrics.height(size.height - _top, width: width);
    final slides = data.banners;
    ({String name, List<PreviewItem> titles}) slide(int i) => i < slides.length
        ? slides[i]
        : (name: '', titles: const <PreviewItem>[]);
    final sides = width > 900;
    final landscape = RowMetrics.landscapeSizes(
      width,
      RowMetrics.landscapeCount(look.scalePercent),
    );
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          RowMetrics.pad,
          8,
          RowMetrics.pad,
          28,
        ),
        child: SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _hero(parts, slide(0))),
              if (sides) ...[
                const SizedBox(width: RowMetrics.gap),
                SizedBox(
                  width: math.min(HeroMetrics.sideMax(height), width * 0.27),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _sideBanner(parts, slide(1))),
                      const SizedBox(height: RowMetrics.gap),
                      Expanded(child: _sideBanner(parts, slide(2))),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      _heading(parts, 'Continuar assistindo'),
      _strip(
        height: landscape.height,
        gap: RowMetrics.landscapeGap,
        count: _shown(
          data.continuing,
          RowMetrics.landscapeCount(look.scalePercent) + 1,
        ),
        item: (i) {
          final item = itemAt(data.continuing, i);
          return SizedBox(
            width: i == 0 ? landscape.expanded : landscape.collapsed,
            child: ClipRRect(
              borderRadius: look.card,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  parts.image(item.image, radius: BorderRadius.zero),
                  const DecoratedBox(decoration: PreviewParts.shadeBottom),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (i == 0) ...[
                          parts.text(
                            item.name,
                            color: Colors.white,
                            weight: FontWeight.w600,
                          ),
                          const SizedBox(height: 6),
                        ],
                        parts.progress(
                          0.3 + (i % 4) * 0.15,
                          track: const Color(0x55FFFFFF),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 24),
      _heading(parts, 'Filmes adicionados recentemente'),
      _posters(parts, width, data.movies),
      const SizedBox(height: 24),
      _heading(parts, 'Séries adicionadas recentemente'),
      _posters(parts, width, data.series),
    ];
  }

  Widget _hero(
    PreviewParts parts,
    ({String name, List<PreviewItem> titles}) slide,
  ) {
    final first = itemAt(slide.titles, 0);
    return ClipRRect(
      borderRadius: look.panel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          parts.image(
            first.image,
            radius: BorderRadius.zero,
            cacheWidth: 640,
            ground: const Color(0xFF2A2825),
          ),
          const DecoratedBox(decoration: PreviewParts.shadeLeft),
          Positioned(
            left: 40,
            right: 40,
            bottom: 32,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      parts.text(
                        slide.name,
                        size: 14,
                        color: parts.p.onMedia,
                        weight: FontWeight.w700,
                      ),
                      const SizedBox(height: 8),
                      parts.title(first.name, 44, color: Colors.white),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          parts.button(
                            'Assistir',
                            icon: Icons.play_arrow,
                            filled: true,
                          ),
                          parts.mediaButton(
                            'Detalhes',
                            icon: Icons.info_outline,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < math.min(3, slide.titles.length); i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Container(
                      width: 64,
                      height: 96,
                      foregroundDecoration: BoxDecoration(
                        borderRadius: look.radius(8),
                        border: Border.all(
                          color: i == 0
                              ? parts.p.onMedia
                              : const Color(0x55FFFFFF),
                          width: 2,
                        ),
                      ),
                      child: parts.image(
                        slide.titles[i].image,
                        radius: look.radius(8),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideBanner(
    PreviewParts parts,
    ({String name, List<PreviewItem> titles}) slide,
  ) =>
      ClipRRect(
        borderRadius: look.panel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            parts.image(
              itemAt(slide.titles, 0).image,
              radius: BorderRadius.zero,
              cacheWidth: 420,
              ground: const Color(0xFF2A2825),
            ),
            const DecoratedBox(decoration: PreviewParts.shadeBottom),
            Positioned(
              left: 18,
              right: 18,
              bottom: 14,
              child: parts.text(
                slide.name,
                size: 15,
                color: Colors.white,
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );

  // ---- TV ao vivo ------------------------------------------------------------

  List<Widget> _live(PreviewParts parts) {
    const side = EdgeInsets.symmetric(horizontal: 28);
    Widget head(String label) => Padding(
          padding: side.copyWith(bottom: 10, top: 6),
          child: parts.text(label, size: 16, weight: FontWeight.w700),
        );
    return [
      Padding(
        padding: side,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              Expanded(child: parts.title('TV AO VIVO', 30)),
              parts.button('Categorias', icon: Icons.tune),
            ],
          ),
        ),
      ),
      Padding(
        padding: side.copyWith(bottom: 16),
        child: SizedBox(height: 280, child: highlightTiles(parts)),
      ),
      head('Recentes e favoritos'),
      _strip(
        height: 144,
        gap: 12,
        left: 28,
        count: _shown(data.recentChannels, 16),
        item: (i) {
          final item = itemAt(data.recentChannels, i);
          return SizedBox(
            width: i == 0 ? 256 : 112,
            child: parts.panel(
              radius: look.card,
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Expanded(
                    child: parts.image(
                      item.image,
                      radius: look.radius(8),
                      fit: BoxFit.contain,
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                  if (i == 0) ...[
                    const SizedBox(height: 8),
                    parts.text(item.name, weight: FontWeight.w600),
                  ],
                ],
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 16),
      for (var r = 0; r < math.max(2, data.channelRows.length); r++) ...[
        head(r < data.channelRows.length ? data.channelRows[r].name : ''),
        _strip(
          height: 224,
          gap: 12,
          left: 28,
          count: _shown(_channels(r), 12),
          item: (i) => _channelCard(parts, itemAt(_channels(r), i), i),
        ),
        const SizedBox(height: 16),
      ],
    ];
  }

  List<PreviewItem> _channels(int row) =>
      row < data.channelRows.length ? data.channelRows[row].channels : const [];

  /// O banner de destaques da TV ao vivo.
  Widget highlightTiles(PreviewParts parts) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              flex: i == 0 ? 2 : 1,
              child: Builder(
                builder: (context) {
                  final group = i < data.highlights.length
                      ? data.highlights[i]
                      : (name: '', channels: const <PreviewItem>[]);
                  final channel = itemAt(group.channels, 0);
                  return parts.panel(
                    radius: look.panel,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        parts.text(
                          group.name,
                          size: 14,
                          color: parts.p.accentInk,
                          weight: FontWeight.w700,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: parts.image(
                              channel.image,
                              radius: look.card,
                              fit: BoxFit.contain,
                              padding: const EdgeInsets.all(18),
                            ),
                          ),
                        ),
                        parts.text(
                          channel.name,
                          size: 15,
                          weight: FontWeight.w600,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      );

  Widget _channelCard(PreviewParts parts, PreviewItem item, int i) => SizedBox(
        width: 240,
        child: parts.panel(
          radius: look.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 120,
                child: parts.image(
                  item.image,
                  radius: look.radius(13),
                  fit: BoxFit.contain,
                  padding: const EdgeInsets.all(24),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      parts.text(item.name, weight: FontWeight.w700),
                      const SizedBox(height: 10),
                      parts.bar(150),
                      const Spacer(),
                      parts.progress(0.2 + (i % 5) * 0.15),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  // ---- Filmes e séries -------------------------------------------------------

  List<Widget> _catalog(PreviewParts parts, double width) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
          child: Row(
            children: [
              Expanded(child: parts.title('FILMES E SÉRIES', 34)),
              parts.button('Categorias', icon: Icons.tune),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: parts.tabs(const ['Filmes', 'Séries']),
          ),
        ),
        _heading(parts, 'Filmes adicionados recentemente'),
        _posters(parts, width, data.movies),
        const SizedBox(height: 24),
        _heading(parts, 'Séries adicionadas recentemente'),
        _posters(parts, width, data.series),
        const SizedBox(height: 24),
        _heading(parts, 'Continuar assistindo'),
        _posters(parts, width, data.continuing),
      ];

  // ---- Minha biblioteca ------------------------------------------------------

  List<Widget> _library(PreviewParts parts) {
    Widget row(String label, List<PreviewItem> list) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(parts, label),
            _strip(
              height: 153 + 40,
              gap: 16,
              count: _shown(list, 10),
              item: (i) {
                final item = itemAt(list, i);
                return SizedBox(
                  width: 272,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 272,
                        height: 153,
                        child: parts.image(
                          item.image,
                          radius: look.card,
                          cacheWidth: 360,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (item.name.isEmpty)
                        parts.bar(160)
                      else
                        parts.text(item.name, weight: FontWeight.w600),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        );
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
        child: Row(
          children: [
            Expanded(child: parts.title('MINHA BIBLIOTECA', 30)),
            parts.button('Adicionar arquivo', icon: Icons.add, filled: true),
            const SizedBox(width: 8),
            parts.button('Abrir pasta', icon: Icons.folder_open_outlined),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Align(
          alignment: Alignment.centerLeft,
          child: parts.tabs(const ['Arquivos', 'Histórico']),
        ),
      ),
      row('Filmes', data.downloads),
      row('Meus arquivos', data.imports),
      row('Gravações', data.recordings),
    ];
  }
}
