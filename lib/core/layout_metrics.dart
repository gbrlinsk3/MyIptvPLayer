import 'dart:math' as math;

/// Ajustes de tamanho da interface (todos os valores em pixels **lógicos**, ou
/// seja, já dentro da escala aplicada por `UiScale`).

/// "Tamanho da interface": 100/115/130/150 %. 100 % é o tamanho de antes.
class UiSizes {
  static const percents = [100, 115, 130, 150];
  static const defaultPercent = 115;

  static int normalize(int? percent) =>
      percents.contains(percent) ? percent! : defaultPercent;
}

/// "Largura do catálogo": 0 = preenchido (toda a largura); senão a largura
/// máxima da coluna, em pixels lógicos, centralizada.
class CatalogWidth {
  static const fill = 0;
  static const options = [1200, 1440, 1600, fill];

  static int normalize(int? px) => options.contains(px) ? px! : fill;
}

/// Quantos pôsteres aparecem por linha e quais os tamanhos que isso resulta.
///
/// Os números vêm do usuário (monitor 2560×1440, Windows a 100 %, largura
/// "preenchido") e valem para **qualquer** janela: o pôster se ajusta à largura
/// disponível para manter a quantidade. [minPortrait] / [minCollapsed] evitam
/// pôsteres minúsculos em janelas estreitas (aí a fileira rola).
class RowMetrics {
  /// Pôsteres verticais (2:3) por linha.
  static int portraitCount(int percent) => switch (percent) {
        100 => 12,
        115 => 11,
        130 => 11,
        150 => 9,
        _ => 11,
      };

  /// Cartões horizontais ("Continuar assistindo") por linha, contando o
  /// expandido.
  static int landscapeCount(int percent) => switch (percent) {
        100 => 6,
        115 => 6,
        130 => 5,
        150 => 4,
        _ => 6,
      };

  /// Margem esquerda das fileiras e espaço entre pôsteres.
  static const double pad = 24;
  static const double gap = 14;
  static const double minPortrait = 110;

  /// Largura do pôster vertical para caber [count] numa fileira de [width]:
  /// a margem esquerda e [count] pôsteres com o espaço entre eles ocupam a
  /// fileira inteira (o seguinte começa fora da tela, sem "fatia" aparecendo).
  static double portraitWidth(double width, int count) =>
      math.max(minPortrait, (width - pad) / count - gap);

  // ---- "Continuar assistindo" ----------------------------------------------

  static const double landscapeGap = 12;
  static const double minCollapsed = 150;

  /// Teto do cartão recolhido: em "Preenchido" (janela larga) os cartões não
  /// passam daqui; sobra espaço à direita em vez de cartões enormes.
  static const double maxCollapsed = 200;

  /// Proporções de antes: recolhido 150×200 e expandido 340×200.
  static const double expandedRatio = 340 / 150;
  static const double heightRatio = 200 / 150;

  /// Cartões do "Continuar assistindo" para [count] por linha: 1 expandido e
  /// os demais recolhidos, mantendo as proporções de antes.
  static ({double collapsed, double expanded, double height}) landscapeSizes(
    double width,
    int count,
  ) {
    final c = (width - pad - landscapeGap * count) / (count - 1 + expandedRatio);
    final capped = math.max(minCollapsed, math.min(maxCollapsed, c)).toDouble();
    return (
      collapsed: capped,
      expanded: capped * expandedRatio,
      height: capped * heightRatio,
    );
  }

  // ---- grade ("Ver tudo", favoritos) ----------------------------------------

  static const double gridGap = 16;

  /// Colunas da grade de pôsteres para a largura útil [inner] (já sem margens).
  static int gridColumns(double inner, int count) {
    final fit = ((inner + gridGap) / (minPortrait + gridGap)).floor();
    return math.max(1, math.min(count, fit));
  }
}

/// Banner do Início: cresce em telas altas (1440p) e o banner da direita
/// acompanha.
class HeroMetrics {
  static const double baseHeight = 440;
  static const double maxHeight = 640;
  static const double baseSideMax = 420;

  /// Altura do banner grande para a altura útil [contentHeight] (janela menos
  /// a barra do topo). Em telas baixas continua 440, como antes.
  /// Com [width] (largura útil), telas muito largas ("Preenchido") também
  /// ganham altura: 28 % da largura, para o banner não ficar achatado.
  static double height(double contentHeight, {double width = 0}) =>
      math.max(contentHeight * 0.40, width * 0.28)
          .clamp(baseHeight, maxHeight)
          .toDouble();

  /// Largura máxima dos banners menores da direita para um banner de [height].
  static double sideMax(double height) =>
      baseSideMax + (height - baseHeight) * 1.6;
}
