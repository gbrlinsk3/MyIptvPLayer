import 'package:flutter/material.dart';

import '../../core/layout_metrics.dart';
import '../../core/theme.dart';
import '../../state/app_scope.dart';
import '../../data/catalog_models.dart';
import '../widgets/shimmer.dart';
import '../widgets/split_text.dart';
import '../widgets/carousel_arrows.dart';
import '../widgets/content_frame.dart';
import '../widgets/full_name_tooltip.dart';
import '../widgets/press_scale.dart';
import 'favorite_button.dart';
import 'poster_image.dart';

/// Pôster com título embaixo. Cresce de leve ao passar o mouse.
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.onTap,
    this.showProgress = false,
  });

  final CatalogTitle title;
  final VoidCallback onTap;

  /// Barra de progresso sobre o pôster (fileira "Continuar assistindo").
  final bool showProgress;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.title;
    final progress = widget.showProgress ? t.progress : null;
    return FullNameTooltip(
      fullName: t.name,
      style: _nameStyle,
      maxLines: 2,
      child: PressScale(
        child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: AnimatedScale(
                  scale: _hover ? 1.04 : 1,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _hover ? AppColors.accent : AppColors.border,
                        width: _hover ? 2 : 1,
                      ),
                      boxShadow: _hover
                          ? const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 14,
                                offset: Offset(0, 6),
                              ),
                            ]
                          : const [],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          PosterImage(url: t.image, name: t.name),
                          Positioned(
                            top: 6,
                            left: 6,
                            child: FavoriteOverlay(title: t, hover: _hover),
                          ),
                          if (t.rating != null)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xB3000000),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '★ ${t.rating!.toStringAsFixed(1)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          if (progress != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 4,
                                backgroundColor: const Color(0x99000000),
                                color: AppColors.accent,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _nameStyle,
              ),
              if (t.subtitle != null)
                Text(
                  t.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  static const _nameStyle = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
  );
}

/// Largura de cada coluna lateral de setas (fileira enquadrada). A seta (36 px)
/// fica centralizada nela.
const double _colunaSetas = 44;

/// Fileira horizontal com título, "Ver tudo" e setas fixas. Os pôsteres podem
/// ser arrastados com o mouse. Com largura fixa (enquadrado) as setas ficam em
/// colunas laterais, fora dos pôsteres; em "preenchido" ficam sobre as bordas
/// da lista. Os dados vêm de um Future em cache do controller (não consulta o
/// banco de novo a cada reconstrução). Fileira vazia não ocupa espaço.
class TitleRow extends StatefulWidget {
  const TitleRow({
    super.key,
    required this.label,
    required this.future,
    required this.onOpen,
    this.onSeeAll,
    this.showProgress = false,
  });

  final String label;
  final Future<List<CatalogTitle>> future;
  final ValueChanged<CatalogTitle> onOpen;
  final VoidCallback? onSeeAll;
  final bool showProgress;

  static const double gap = RowMetrics.gap;

  @override
  State<TitleRow> createState() => _TitleRowState();
}

class _TitleRowState extends State<TitleRow> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CatalogTitle>>(
      future: widget.future,
      builder: (context, snap) {
        final list = snap.data;
        if (snap.connectionState == ConnectionState.done &&
            (list == null || list.isEmpty)) {
          return const SizedBox.shrink();
        }
        // O pôster se ajusta à largura útil da lista para caber a quantidade por
        // linha do tamanho de interface escolhido (12/11/11/9).
        final perRow = AppScope.of(context).portraitPerRow;
        final framed = ContentFrameScope.framedOf(context);
        return LayoutBuilder(builder: (context, box) {
          // Enquadrado: as colunas laterais de setas tiram largura da lista.
          final recuo = framed ? _colunaSetas : 0.0;
          final larguraLista = box.maxWidth - 2 * recuo;
          final posterWidth = RowMetrics.portraitWidth(larguraLista, perRow);
          final itemWidth = posterWidth + TitleRow.gap;
          // Altura: pôster 2:3 + espaço do texto.
          final rowHeight = posterWidth * 1.5 + 56 + 24;
          // Centro vertical dos pôsteres (a lista tem folga de 12 em cima): é
          // onde as setas ficam.
          final yCentro = 12 + posterWidth * 0.75;
          // Sem rolagem quando a lista cabe inteira: as setas somem.
          final visiveis =
              ((larguraLista - RowMetrics.pad * 2 + TitleRow.gap) / itemWidth)
                  .floor();
          final comSetas = list != null && list.length > visiveis;
          final passo = itemWidth * 4;
          final miolo = list == null
              ? _skeleton(itemWidth)
              : CarouselDragArea(
                  child: ListView.builder(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    itemExtent: itemWidth,
                    // Folga em cima e embaixo: o cartão cresce ao passar o mouse
                    // e a borda não pode ser cortada.
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(right: TitleRow.gap),
                      child: PosterCard(
                        title: list[i],
                        showProgress: widget.showProgress,
                        onTap: () => widget.onOpen(list[i]),
                      ),
                    ),
                  ),
                );
          final setaEsq = comSetas
              ? CarouselArrow(controller: _scroll, left: true, passo: passo)
              : null;
          final setaDir = comSetas
              ? CarouselArrow(controller: _scroll, left: false, passo: passo)
              : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(24 + recuo, 0, 24 + recuo, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: SplitText(
                          text: widget.label.toUpperCase(),
                          revealId: ('titulo-fileira', widget.label),
                          maxLines: 1,
                          style: AppFonts.title(22, spacing: 1.2),
                          delayPerChar: const Duration(milliseconds: 22),
                          charDuration: const Duration(milliseconds: 360),
                        ),
                      ),
                      if (widget.onSeeAll != null)
                        TextButton(
                          onPressed: widget.onSeeAll,
                          child: const Text('Ver tudo'),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: rowHeight,
                  child: framed
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _colunaDeSetas(setaEsq, yCentro),
                            Expanded(child: miolo),
                            _colunaDeSetas(setaDir, yCentro),
                          ],
                        )
                      : Stack(
                          children: [
                            miolo,
                            if (setaEsq != null)
                              Positioned(
                                left: 4,
                                top: yCentro - CarouselArrowButton.size / 2,
                                child: setaEsq,
                              ),
                            if (setaDir != null)
                              Positioned(
                                right: 4,
                                top: yCentro - CarouselArrowButton.size / 2,
                                child: setaDir,
                              ),
                          ],
                        ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  /// Coluna lateral de [_colunaSetas] px: a seta (se houver) fica na altura
  /// dos pôsteres.
  Widget _colunaDeSetas(Widget? seta, double yCentro) {
    return SizedBox(
      width: _colunaSetas,
      child: Column(
        children: [
          SizedBox(height: yCentro - CarouselArrowButton.size / 2),
          ?seta,
        ],
      ),
    );
  }

  Widget _skeleton(double itemWidth) {
    return Shimmer(
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemExtent: itemWidth,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        itemCount: 10,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(right: TitleRow.gap),
          child: Align(
            alignment: Alignment.topCenter,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.hover,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Esqueleto com brilho da grade de pôsteres: mesma forma e mesmas medidas de
/// [TitleGrid] (colunas e altura), enquanto a lista ainda não chegou. Só as
/// linhas visíveis são construídas (grade preguiçosa).
class TitleGridSkeleton extends StatelessWidget {
  const TitleGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final perRow = AppScope.of(context).portraitPerRow;
                final cols =
                    RowMetrics.gridColumns(constraints.crossAxisExtent, perRow);
                final w = (constraints.crossAxisExtent -
                        RowMetrics.gridGap * (cols - 1)) /
                    cols;
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: RowMetrics.gridGap,
                    mainAxisSpacing: RowMetrics.gridGap,
                    mainAxisExtent: w * 1.5 + TitleGrid._textHeight,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => const _PosterSkeleton(),
                    childCount: cols * 6,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterSkeleton extends StatelessWidget {
  const _PosterSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: SkeletonBox(radius: 10),
        ),
        const SizedBox(height: 8),
        FractionallySizedBox(
          widthFactor: 0.7,
          child: SkeletonBox(height: 10, radius: 4),
        ),
      ],
    );
  }
}

/// Divisor entre o resultado principal da busca e os extras.
class SearchDivider extends StatelessWidget {
  const SearchDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: AppFonts.title(16, color: AppColors.textMuted, spacing: 1.4),
          ),
          const SizedBox(width: 14),
          Expanded(child: Divider(color: AppColors.border)),
        ],
      ),
    );
  }
}

/// Grade de pôsteres (busca e "Ver tudo"). [extra] aparece depois de um
/// divisor ([extraLabel]); é usado pelos resultados "relacionados" da busca.
class TitleGrid extends StatelessWidget {
  const TitleGrid({
    super.key,
    required this.titles,
    required this.onOpen,
    this.extra = const [],
    this.extraLabel = 'Também pode interessar',
  });

  final List<CatalogTitle> titles;
  final ValueChanged<CatalogTitle> onOpen;
  final List<CatalogTitle> extra;
  final String extraLabel;

  /// Altura do nome/subtítulo embaixo do pôster na grade.
  static const double _textHeight = 62;

  /// Só a grade (com margens), para usar dentro de um CustomScrollView maior.
  static Widget sliver({
    required List<CatalogTitle> titles,
    required ValueChanged<CatalogTitle> onOpen,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      sliver: _grid(titles, onOpen),
    );
  }

  /// Grade com a mesma quantidade de pôsteres por linha das fileiras (12/11/11/9
  /// conforme o tamanho da interface), reduzida só se a janela for estreita.
  static Widget _grid(List<CatalogTitle> list, ValueChanged<CatalogTitle> onOpen) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final perRow = AppScope.of(context).portraitPerRow;
        final cols = RowMetrics.gridColumns(constraints.crossAxisExtent, perRow);
        final w = (constraints.crossAxisExtent -
                RowMetrics.gridGap * (cols - 1)) /
            cols;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: RowMetrics.gridGap,
            mainAxisSpacing: RowMetrics.gridGap,
            mainAxisExtent: w * 1.5 + _textHeight,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => PosterCard(
              title: list[i],
              onTap: () => onOpen(list[i]),
            ),
            childCount: list.length,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          sliver: _grid(titles, onOpen),
        ),
        if (extra.isNotEmpty) ...[
          SliverToBoxAdapter(child: SearchDivider(label: extraLabel)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            sliver: _grid(extra, onOpen),
          ),
        ] else
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}
