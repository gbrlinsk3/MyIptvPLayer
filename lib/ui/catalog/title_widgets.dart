import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog_models.dart';
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
    return MouseRegion(
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
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
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
    );
  }
}

/// Fileira horizontal com título, "Ver tudo" e setas que aparecem com o mouse.
/// Os dados vêm de um Future em cache do controller (não consulta o banco de
/// novo a cada reconstrução). Fileira vazia não ocupa espaço.
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

  static const double posterWidth = 148;
  static const double gap = 14;

  @override
  State<TitleRow> createState() => _TitleRowState();
}

class _TitleRowState extends State<TitleRow> {
  final ScrollController _scroll = ScrollController();
  bool _hover = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollBy(double delta) {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final target = (_scroll.offset + delta).clamp(0.0, max).toDouble();
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
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
        final itemWidth = TitleRow.posterWidth + TitleRow.gap;
        // Altura: pôster 2:3 + espaço do texto.
        final rowHeight = TitleRow.posterWidth * 1.5 + 56 + 24;
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.title(22, spacing: 1.2),
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
                  child: Stack(
                    children: [
                      if (list == null)
                        _skeleton(itemWidth)
                      else
                        ListView.builder(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          itemExtent: itemWidth,
                          // Folga em cima e embaixo: o cartão cresce ao passar
                          // o mouse e a borda não pode ser cortada.
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
                      if (_hover && list != null && list.length > 5) ...[
                        _Arrow(
                          left: true,
                          onTap: () => _scrollBy(-itemWidth * 4),
                        ),
                        _Arrow(
                          left: false,
                          onTap: () => _scrollBy(itemWidth * 4),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _skeleton(double itemWidth) {
    return ListView.builder(
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
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.left, required this.onTap});

  final bool left;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      bottom: 56,
      left: left ? 4 : null,
      right: left ? null : 4,
      child: Center(
        child: Material(
          color: const Color(0xCC1F1E1D),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                left ? Icons.chevron_left : Icons.chevron_right,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ),
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

  static const _delegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 176,
    crossAxisSpacing: 16,
    mainAxisSpacing: 16,
    childAspectRatio: 0.54,
  );

  /// Só a grade (com margens), para usar dentro de um CustomScrollView maior.
  static Widget sliver({
    required List<CatalogTitle> titles,
    required ValueChanged<CatalogTitle> onOpen,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      sliver: SliverGrid(
        gridDelegate: _delegate,
        delegate: SliverChildBuilderDelegate(
          (context, i) => PosterCard(
            title: titles[i],
            onTap: () => onOpen(titles[i]),
          ),
          childCount: titles.length,
        ),
      ),
    );
  }

  SliverGrid _grid(List<CatalogTitle> list) => SliverGrid(
        gridDelegate: _delegate,
        delegate: SliverChildBuilderDelegate(
          (context, i) => PosterCard(
            title: list[i],
            onTap: () => onOpen(list[i]),
          ),
          childCount: list.length,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          sliver: _grid(titles),
        ),
        if (extra.isNotEmpty) ...[
          SliverToBoxAdapter(child: SearchDivider(label: extraLabel)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            sliver: _grid(extra),
          ),
        ] else
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}
