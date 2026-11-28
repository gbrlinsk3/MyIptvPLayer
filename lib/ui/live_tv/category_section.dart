import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../widgets/glass.dart';
import '../widgets/split_text.dart';

/// Posição, dentro do bloco, onde a categoria arrastada vai cair. [extents] são
/// as alturas das categorias do bloco, [from] a posição da arrastada (fechada)
/// e [delta] quanto ela andou. Uma vizinha é passada quando a borda da frente
/// da arrastada cruza o meio dela.
int dragTargetIndex(List<double> extents, int from, double delta) {
  final start = extents.take(from).fold(0.0, (a, b) => a + b);
  final draggedTop = start + delta;
  final draggedBottom = draggedTop + extents[from];
  var to = 0;
  var top = 0.0;
  for (var i = 0; i < extents.length; i++) {
    final center = top + extents[i] / 2;
    top += extents[i];
    // Quem fica antes da arrastada no resultado conta uma posição.
    if (i < from && draggedTop >= center) to++;
    if (i > from && draggedBottom > center) to++;
  }
  return to;
}

/// Quanto a categoria [i] sai do lugar para abrir espaço à arrastada, que tem
/// [extent] de altura e vai de [from] para [to].
double dragShift(int i, int from, int to, double extent) {
  if (i > from && i <= to) return -extent;
  if (i < from && i >= to) return extent;
  return 0;
}

/// Título de uma categoria da TV ao vivo: clicar abre ou fecha a fileira, o
/// coração favorita e, com ela fechada, segurar e arrastar muda a ordem.
class CategoryHeader extends StatefulWidget {
  const CategoryHeader({
    super.key,
    required this.title,
    required this.count,
    required this.open,
    required this.favorite,
    required this.onToggle,
    required this.onToggleFavorite,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final String title;

  /// Texto da quantidade ("24 canais").
  final String count;
  final bool open;
  final bool favorite;

  /// Nulo quando não dá para fechar (durante a busca).
  final VoidCallback? onToggle;
  final VoidCallback onToggleFavorite;

  /// Nulos quando a categoria não pode ser arrastada (aberta ou na busca).
  final GestureLongPressStartCallback? onDragStart;
  final GestureLongPressMoveUpdateCallback? onDragUpdate;

  /// Soltou ([drop] verdadeiro) ou o gesto foi cancelado.
  final void Function(bool drop)? onDragEnd;

  static const double height = 44;

  /// Tempo segurando até a categoria sair do lugar.
  static const Duration holdDelay = Duration(milliseconds: 300);

  @override
  State<CategoryHeader> createState() => _CategoryHeaderState();
}

class _CategoryHeaderState extends State<CategoryHeader> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final draggable = widget.onDragStart != null;
    final reduce = MediaQuery.disableAnimationsOf(context);

    Widget header = InkWell(
      onTap: widget.onToggle,
      onHover: (v) => setState(() => _hover = v),
      borderRadius: AppShape.control,
      hoverColor: AppColors.text.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            AnimatedRotation(
              turns: widget.open ? 0.25 : 0,
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: SplitText(
                      text: widget.title,
                      revealId: ('titulo-categoria-tv', widget.title),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                      delayPerChar: const Duration(milliseconds: 22),
                      charDuration: const Duration(milliseconds: 360),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.count,
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: widget.favorite
                        ? 'Desfavoritar categoria'
                        : 'Favoritar categoria',
                    onPressed: widget.onToggleFavorite,
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                    icon: Icon(
                      widget.favorite ? Icons.favorite : Icons.favorite_border,
                      color: widget.favorite
                          ? AppColors.accentInk
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            // Só com o mouse em cima: avisa que dá para arrastar.
            if (draggable && _hover) ...[
              Text(
                'Segure para arrastar',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(width: 4),
              Icon(Icons.drag_indicator, size: 18, color: AppColors.textMuted),
              const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );

    header = Semantics(expanded: widget.open, child: header);

    // O reconhecedor fica sempre na árvore (sem gestos quando não há arraste):
    // trocar a árvore ao abrir ou fechar reiniciaria a seta e o título.
    return SizedBox(
      height: CategoryHeader.height,
      child: RawGestureDetector(
        gestures: {
          if (draggable)
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(
                  () => LongPressGestureRecognizer(
                    debugOwner: this,
                    duration: CategoryHeader.holdDelay,
                  ),
                  (r) => r
                    ..onLongPressStart = widget.onDragStart
                    ..onLongPressMoveUpdate = widget.onDragUpdate
                    ..onLongPressEnd = ((_) => widget.onDragEnd?.call(true))
                    ..onLongPressCancel = () => widget.onDragEnd?.call(false),
                ),
        },
        child: header,
      ),
    );
  }
}

/// A categoria enquanto é arrastada: o título numa peça de vidro que segue o
/// mouse. Sem desfoque ao vivo, para não pesar durante o movimento.
class CategoryDragGhost extends StatelessWidget {
  const CategoryDragGhost({
    super.key,
    required this.title,
    required this.count,
  });

  final String title;
  final String count;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: GlassSurface(
        liveBlur: false,
        radius: AppShape.control,
        fill: AppColors.surface,
        edge: AppColors.accent,
        shadow: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(Icons.drag_indicator, size: 20, color: AppColors.accentInk),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                count,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// O conteúdo de uma categoria desce ao abrir e recolhe ao fechar. Fechado, não
/// existe na árvore. Só a altura muda por quadro: [builder] não é refeito.
class CategoryReveal extends StatefulWidget {
  const CategoryReveal({super.key, required this.open, required this.builder});

  final bool open;
  final WidgetBuilder builder;

  static const Duration duration = Duration(milliseconds: 200);

  @override
  State<CategoryReveal> createState() => _CategoryRevealState();
}

class _CategoryRevealState extends State<CategoryReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: CategoryReveal.duration,
    value: widget.open ? 1 : 0,
  );
  late final Animation<double> _height = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void didUpdateWidget(CategoryReveal old) {
    super.didUpdateWidget(old);
    if (old.open == widget.open) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = widget.open ? 1 : 0;
    } else if (widget.open) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        if (_c.isDismissed && !widget.open) return const SizedBox.shrink();
        return ClipRect(
          // Parada e aberta, nada é cortado (sombra dos cartões).
          clipBehavior: _c.isCompleted ? Clip.none : Clip.hardEdge,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: _height.value,
            child: child,
          ),
        );
      },
      child: widget.open || !_c.isDismissed
          ? Builder(builder: widget.builder)
          : null,
    );
  }
}
