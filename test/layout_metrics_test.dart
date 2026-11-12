import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/layout_metrics.dart';

void main() {
  const rail = 68.0; // trilho lateral
  const screenWidth = 2560.0; // monitor de referência (1440p, Windows a 100 %)

  /// Largura lógica da área de conteúdo para o tamanho de interface [percent].
  double contentWidth(int percent) => screenWidth / (percent / 100) - rail;

  test('verticais por linha no monitor de referência: 12 / 11 / 11 / 9', () {
    const expected = {100: 12, 115: 11, 130: 11, 150: 9};
    for (final e in expected.entries) {
      final w = contentWidth(e.key);
      final poster = RowMetrics.portraitWidth(w, e.value);
      final slot = poster + RowMetrics.gap;
      // Cabem exatamente `count` pôsteres e o seguinte começa fora da fileira.
      expect(RowMetrics.pad + slot * e.value, closeTo(w, 0.001),
          reason: '${e.key} %');
      expect(RowMetrics.pad + slot * (e.value + 1), greaterThan(w));
    }
  });

  test('a quantidade por linha vale para qualquer janela (até o mínimo)', () {
    // 1080p a 100 %: janela de 1920 px.
    final w = 1920 - rail;
    final poster = RowMetrics.portraitWidth(w, RowMetrics.portraitCount(100));
    expect(poster, greaterThan(RowMetrics.minPortrait));
    expect(RowMetrics.pad + (poster + RowMetrics.gap) * 12, closeTo(w, 0.001));
    // Janela muito estreita: respeita o mínimo (a fileira passa a rolar).
    expect(RowMetrics.portraitWidth(600, 12), RowMetrics.minPortrait);
  });

  test('horizontais por linha: 6 / 6 / 5 / 4, com 1 expandido', () {
    const expected = {100: 6, 115: 6, 130: 5, 150: 4};
    for (final e in expected.entries) {
      // Largura sem o teto: a fileira inteira é usada (6/6/5/4 cabem).
      final w = RowMetrics.pad + RowMetrics.landscapeGap * e.value + 180 * (e.value - 1 + RowMetrics.expandedRatio);
      final s = RowMetrics.landscapeSizes(w, e.value);
      // margem + (n-1) recolhidos + 1 expandido + n espaços = fileira inteira.
      final total = RowMetrics.pad +
          (e.value - 1) * s.collapsed +
          s.expanded +
          e.value * RowMetrics.landscapeGap;
      expect(s.collapsed, lessThan(RowMetrics.maxCollapsed));
      expect(total, closeTo(w, 0.001), reason: '${e.key} %');
      // Janela larga ("Preenchido"): o cartão não passa do teto.
      final wide = RowMetrics.landscapeSizes(contentWidth(e.key), e.value);
      expect(wide.collapsed, RowMetrics.maxCollapsed);
      // Proporções de antes: 150×200 recolhido, 340×200 expandido.
      expect(s.expanded / s.collapsed, closeTo(340 / 150, 1e-9));
      expect(s.height / s.collapsed, closeTo(200 / 150, 1e-9));
    }
  });

  test('colunas da grade: no máximo a quantidade, no mínimo 1', () {
    expect(RowMetrics.gridColumns(2400, 12), 12);
    expect(RowMetrics.gridColumns(700, 12), lessThan(12));
    expect(RowMetrics.gridColumns(50, 12), 1);
  });

  test('banner: telas baixas ficam como antes, 1440p cresce', () {
    expect(HeroMetrics.height(976), HeroMetrics.baseHeight); // 1080p
    expect(HeroMetrics.sideMax(HeroMetrics.baseHeight), HeroMetrics.baseSideMax);
    final tall = HeroMetrics.height(1328); // 1440p a 100 %
    expect(tall, greaterThan(500));
    expect(tall, lessThanOrEqualTo(HeroMetrics.maxHeight));
    expect(HeroMetrics.sideMax(tall), greaterThan(HeroMetrics.baseSideMax));
    // Largura fixa (1600) não muda; "Preenchido" largo fica mais alto.
    expect(HeroMetrics.height(1328, width: 1600), tall);
    expect(HeroMetrics.height(1328, width: 2160), greaterThan(tall));
  });

  test('valores inválidos salvos voltam ao padrão', () {
    expect(UiSizes.normalize(null), 115);
    expect(UiSizes.normalize(120), 115);
    expect(UiSizes.normalize(150), 150);
    expect(CatalogWidth.normalize(999), CatalogWidth.fill);
    expect(CatalogWidth.normalize(1440), 1440);
  });
}
