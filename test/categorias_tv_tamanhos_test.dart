// Arraste das categorias em vários tamanhos de janela e de interface. Fica à
// parte de categorias_tv_test.dart: o flutter_tester cai sozinho de vez em
// quando, e quanto maior o arquivo, menos rodadas chegam ao fim.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/live_tv/category_section.dart';

import 'apoio/categorias_tv.dart';

void main() {
  group('gaveta em vários tamanhos', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    prepararPasta();

    const medidas = [
      (Size(1000, 620), 1.0),
      (Size(1000, 620), 1.5),
      (Size(1280, 800), 1.3),
      (Size(1400, 900), 1.0),
      (Size(1400, 900), 1.15),
      (Size(2560, 1440), 1.15),
      (Size(2560, 1440), 1.5),
    ];
    for (final (janela, escala) in medidas) {
      final caso = '${janela.width.toInt()}x${janela.height.toInt()}, $escala';
      testWidgets('arrastar muda a ordem e a peça segue o mouse ($caso)', (
        tester,
      ) async {
        var (_, app) = await abrir(tester);
        await montar(tester, app, escala: escala, janela: janela);
        final passo =
            tester.getTopLeft(titulo('Esportes')).dy -
            tester.getTopLeft(titulo('Abertos')).dy;

        final andou = await arrastar(tester, 'Abertos', passo * 2);
        expect(andou, closeTo(passo * 2, 1));
        expect(titulos(tester), ['Esportes', 'Filmes', 'Abertos', 'Notícias']);

        await fechar(tester, app);
        (_, app) = await abrir(tester);
        await montar(tester, app, escala: escala, janela: janela);
        expect(titulos(tester), [
          'Esportes',
          'Filmes',
          'Abertos',
          'Notícias',
        ], reason: 'a ordem é salva');
        await fechar(tester, app);
      });
    }

    for (final (janela, escala) in const [
      (Size(1000, 620), 1.5),
      (Size(1400, 900), 1.15),
      (Size(2560, 1440), 1.0),
    ]) {
      final caso = '${janela.width.toInt()}x${janela.height.toInt()}, $escala';
      testWidgets('perto da borda a lista rola sozinha sem soltar ($caso)', (
        tester,
      ) async {
        final (_, app) = await abrir(tester, nomes: muitasCategorias);
        await montar(tester, app, escala: escala, janela: janela);
        final area = tester.getRect(titulo('Categoria 1'));
        final inicio = Offset(area.left + 120, area.center.dy);
        final gesto = await tester.startGesture(
          inicio,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(
          CategoryHeader.holdDelay + const Duration(milliseconds: 50),
        );
        await gesto.moveTo(Offset(inicio.dx, janela.height - 4));
        // Passos longos: o flutter_tester cai mais quanto mais quadros desenha.
        for (var i = 0; i < 90; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        final posicao = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        // Passou da área que a lista mantém montada fora da tela; na janela
        // grande o fim chega antes.
        expect(
          posicao.pixels,
          greaterThan(math.min(600.0, posicao.maxScrollExtent - 1)),
        );
        expect(posicao.pixels, greaterThan(0));
        expect(find.byType(CategoryDragGhost), findsOneWidget);
        await gesto.up();
        await tester.pumpAndSettle();
        expect(find.byType(CategoryDragGhost), findsNothing);
        final ordem = app.drawerCategories.map((c) => c.name).toList();
        expect(ordem.indexOf('Categoria 1'), greaterThan(12));
        expect(ordem.first, 'Categoria 0');
        await fechar(tester, app);
      });
    }
  });
}
