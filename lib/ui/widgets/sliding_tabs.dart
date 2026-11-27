import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'glass.dart';

/// Abas com um indicador que desliza até a aba escolhida. Visual e animação do
/// protótipo aprovado (test/_previews/motion_preview_test.dart), com os cantos
/// dos controles ([AppShape.control]).
///
/// As larguras são medidas pelo texto, então um rótulo que muda (ex.: contador
/// "Filmes · 12" para "Filmes · 13") é tratado sem ajuste extra. Se a largura
/// não couber, a faixa rola na horizontal em vez de estourar.
class SlidingTabs extends StatelessWidget {
  const SlidingTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.spacing = 4,
  });

  final List<String> labels;

  /// Índice da aba ativa.
  final int selected;

  final ValueChanged<int> onChanged;

  /// Espaço entre uma aba e a seguinte.
  final double spacing;

  static const double _altura = 36;
  static const double _margem = 4;
  static const _estilo = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();

    final escala = MediaQuery.textScalerOf(context);
    final larguras = [for (final l in labels) _larguraDoTexto(l, escala) + 32];
    final indice = selected.clamp(0, labels.length - 1).toInt();

    double esquerdaDe(int i) {
      var x = 0.0;
      for (var j = 0; j < i; j++) {
        x += larguras[j] + spacing;
      }
      return x;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: GlassSurface(
        radius: AppShape.control,
        child: Padding(
          // + 1: o espaço da borda.
          padding: const EdgeInsets.all(_margem + 1),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: esquerdaDe(indice),
                top: 0,
                bottom: 0,
                width: larguras[indice],
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: AppShape.control,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < labels.length; i++) ...[
                    if (i > 0) SizedBox(width: spacing),
                    _Aba(
                      label: labels[i],
                      largura: larguras[i],
                      ativa: i == indice,
                      onTap: () => onChanged(i),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Aba extends StatelessWidget {
  const _Aba({
    required this.label,
    required this.largura,
    required this.ativa,
    required this.onTap,
  });

  final String label;
  final double largura;
  final bool ativa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: ativa,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: largura,
            height: SlidingTabs._altura,
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: SlidingTabs._estilo.copyWith(
                  fontFamily: AppFonts.body,
                  color: ativa ? AppColors.accentInk : AppColors.textMuted,
                ),
                child: Text(label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Largura do texto de [texto] com o estilo das abas (sem o espaçamento interno).
double _larguraDoTexto(String texto, TextScaler escala) {
  final tp = TextPainter(
    text: TextSpan(
      text: texto,
      style: SlidingTabs._estilo.copyWith(fontFamily: AppFonts.body),
    ),
    textDirection: TextDirection.ltr,
    textScaler: escala,
    maxLines: 1,
  )..layout();
  final largura = tp.width;
  tp.dispose();
  return largura;
}
