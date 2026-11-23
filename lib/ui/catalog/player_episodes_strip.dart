import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../widgets/carousel_arrows.dart';
import 'poster_image.dart';

/// Faixa de episódios sobre o vídeo, logo acima dos controles (mesmo
/// comportamento de "Continuar assistindo"/"Recentes e favoritos"): cartões
/// horizontais com a imagem do episódio. Só um fica expandido: o que está sob o
/// mouse e, sem mouse na faixa, o que está tocando; os outros ficam compactos.
/// Rola com as setas ou segurando e arrastando.
class PlayerEpisodesStrip extends StatefulWidget {
  const PlayerEpisodesStrip({
    super.key,
    required this.items,
    required this.current,
    required this.onSelect,
    required this.onClose,
  });

  final List<PlayItem> items;
  final int current;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  @override
  State<PlayerEpisodesStrip> createState() => _PlayerEpisodesStripState();
}

class _PlayerEpisodesStripState extends State<PlayerEpisodesStrip> {
  static const double collapsedWidth = 112;
  static const double expandedWidth = 256;
  static const double _cardHeight = 144;
  static const double _gap = 12;
  static const double _rowHeight = _cardHeight + 8;

  /// Cartão sob o mouse; nulo = abre o do episódio tocando.
  int? _hover;

  late final ScrollController _scroll = ScrollController(
    // Começa com o episódio atual à vista (o anterior aparece à esquerda).
    initialScrollOffset: ((widget.current - 1) * (collapsedWidth + _gap)).clamp(
      0.0,
      double.infinity,
    ),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// "T1 · E5 — Nome" vira ("T1 · E5", "Nome"); sem o formato, usa o número.
  (String, String) _labels(PlayItem it, int i) {
    final sub = it.subtitle ?? it.title;
    final cut = sub.indexOf(' — ');
    if (cut > 0) return (sub.substring(0, cut), sub.substring(cut + 3));
    return ('Ep. ${i + 1}', sub);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.items.isEmpty ? '' : widget.items.first.title;
    final open = _hover ?? widget.current;
    const itemWidth = collapsedWidth + _gap;
    const extra = expandedWidth - collapsedWidth;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Episódios · $title',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color.fromRGBO(255, 255, 255, 0.75),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Fechar episódios',
              visualDensity: VisualDensity.compact,
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
            ),
          ],
        ),
        SizedBox(
          height: _rowHeight,
          child: LayoutBuilder(
            builder: (context, box) {
              final comSetas =
                  widget.items.length * itemWidth + extra > box.maxWidth;
              const top = (_rowHeight - CarouselArrowButton.size) / 2;
              const passo = itemWidth * 3;
              return Stack(
                children: [
                  MouseRegion(
                    onExit: (_) {
                      if (_hover != null) setState(() => _hover = null);
                    },
                    child: CarouselDragArea(
                      child: ListView.builder(
                        controller: _scroll,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: widget.items.length,
                        itemBuilder: (context, i) {
                          final it = widget.items[i];
                          final (label, name) = _labels(it, i);
                          return Padding(
                            padding: const EdgeInsets.only(right: _gap),
                            child: _EpisodeCard(
                              key: ValueKey(it.id),
                              thumb: it.thumb ?? it.image,
                              label: label,
                              name: name,
                              now: i == widget.current,
                              expanded: i == open,
                              onEnter: () {
                                if (_hover != i) setState(() => _hover = i);
                              },
                              onTap: i == widget.current
                                  ? null
                                  : () => widget.onSelect(i),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (comSetas)
                    Positioned(
                      left: 4,
                      top: top,
                      child: CarouselArrow(
                        controller: _scroll,
                        left: true,
                        passo: passo,
                      ),
                    ),
                  if (comSetas)
                    Positioned(
                      right: 4,
                      top: top,
                      child: CarouselArrow(
                        controller: _scroll,
                        left: false,
                        passo: passo,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    super.key,
    required this.thumb,
    required this.label,
    required this.name,
    required this.now,
    required this.expanded,
    required this.onEnter,
    required this.onTap,
  });

  final String? thumb;
  final String label;
  final String name;
  final bool now;
  final bool expanded;
  final VoidCallback onEnter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dur = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
    return Semantics(
      button: true,
      selected: now,
      label: '$label, $name',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        onEnter: (_) => onEnter(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: dur,
            curve: Curves.easeOutCubic,
            width: expanded
                ? _PlayerEpisodesStripState.expandedWidth
                : _PlayerEpisodesStripState.collapsedWidth,
            height: _PlayerEpisodesStripState._cardHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: now || expanded ? AppColors.accent : Colors.white24,
                width: now || expanded ? 2 : 1,
              ),
              boxShadow: expanded
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(
                    child: PosterImage(
                      url: thumb,
                      name: label,
                      cacheWidth: 520,
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xCC000000)],
                        stops: [0.3, 1],
                      ),
                    ),
                  ),
                  // Os textos usam a largura disponível com reticências: não
                  // estouram em nenhum quadro da animação de largura.
                  Positioned(
                    left: expanded ? 14 : 8,
                    right: expanded ? 14 : 8,
                    bottom: 12,
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: expanded ? 16 : 13,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (expanded)
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xE6FFFFFF),
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (now)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: Color(0x99000000),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.equalizer,
                          size: 16,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
