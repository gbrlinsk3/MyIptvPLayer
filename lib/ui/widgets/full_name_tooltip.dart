import 'package:flutter/material.dart';

/// Dica com o nome completo ao parar o mouse sobre [child]. Só aparece quando a
/// tela não mostra o nome inteiro: cortado por falta de espaço ou encurtado
/// ([shownName] diferente de [fullName]).
class FullNameTooltip extends StatelessWidget {
  const FullNameTooltip({
    super.key,
    required this.fullName,
    required this.style,
    required this.maxLines,
    required this.child,
    this.shownName,
    this.textWidth,
    this.verticalOffset,
  });

  final String fullName;

  /// Texto que está na tela; sem ele, é o próprio [fullName].
  final String? shownName;

  /// Estilo e linhas do texto na tela, para saber se ele foi cortado.
  final TextStyle style;
  final int maxLines;

  /// Largura do texto; sem ela, usa a largura disponível para [child].
  final double? textWidth;

  /// Distância do centro de [child] até a dica (padrão: a do tema).
  final double? verticalOffset;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = textWidth;
    if (width != null) return _tooltip(context, width, verticalOffset);
    return LayoutBuilder(
      builder: (context, box) => _tooltip(
        context,
        box.maxWidth,
        verticalOffset ??
            (box.maxHeight.isFinite ? box.maxHeight / 2 + 4 : null),
      ),
    );
  }

  Widget _tooltip(BuildContext context, double width, double? offset) {
    final shown = shownName ?? fullName;
    var hidden = shown != fullName;
    if (!hidden) {
      final painter = TextPainter(
        text: TextSpan(
          text: shown,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        maxLines: maxLines,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: width);
      hidden = painter.didExceedMaxLines;
      painter.dispose();
    }
    // A árvore não muda quando a dica liga ou desliga (as animações do filho
    // não reiniciam). O TooltipVisibility de dentro devolve ao filho o valor de
    // fora: sem ele, as dicas dos botões do cartão sumiriam junto.
    final ambient = TooltipVisibility.of(context);
    return TooltipVisibility(
      visible: hidden,
      child: Tooltip(
        message: fullName,
        verticalOffset: offset,
        waitDuration: const Duration(milliseconds: 600),
        excludeFromSemantics: true,
        child: TooltipVisibility(visible: ambient, child: child),
      ),
    );
  }
}
