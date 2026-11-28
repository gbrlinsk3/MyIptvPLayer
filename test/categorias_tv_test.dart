import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/category_order.dart';
import 'package:iptv_player/ui/live_tv/category_section.dart';
import 'package:iptv_player/ui/live_tv/channel_group_card.dart';

import 'apoio/categorias_tv.dart';

void main() {
  group('ordem', () {
    const provedor = ['a', 'b', 'c', 'd'];

    test('sem ordem salva vale a do provedor', () {
      expect(orderCategoryIds(provedor, const []), provedor);
    });

    test('categoria nova fica depois da vizinha dela no provedor', () {
      expect(orderCategoryIds(['a', 'x', 'b', 'c'], ['c', 'a', 'b']), [
        'c',
        'a',
        'x',
        'b',
      ]);
      expect(orderCategoryIds(['y', 'a', 'b'], ['b', 'a']), ['y', 'b', 'a']);
    });

    test('categoria que sumiu sai da ordem', () {
      expect(orderCategoryIds(['a', 'c'], ['c', 'b', 'a']), ['c', 'a']);
    });

    test('mover leva ao lugar do alvo nos dois sentidos', () {
      expect(moveCategoryId(provedor, 'a', 'c'), ['b', 'c', 'a', 'd']);
      expect(moveCategoryId(provedor, 'd', 'b'), ['a', 'd', 'b', 'c']);
      expect(moveCategoryId(provedor, 'a', 'a'), provedor);
    });

    test('a vizinha troca quando a borda da arrastada cruza o meio dela', () {
      const alturas = [48.0, 48.0, 292.0, 48.0];
      expect(dragTargetIndex(alturas, 0, 0), 0);
      expect(dragTargetIndex(alturas, 0, 20), 0);
      expect(dragTargetIndex(alturas, 0, 30), 1);
      // A aberta é alta: precisa chegar ao meio dela.
      expect(dragTargetIndex(alturas, 0, 180), 1);
      expect(dragTargetIndex(alturas, 0, 200), 2);
      expect(dragTargetIndex(alturas, 0, 5000), 3);
      expect(dragTargetIndex(alturas, 3, -100), 3);
      expect(dragTargetIndex(alturas, 3, -150), 2);
      expect(dragTargetIndex(alturas, 3, -5000), 0);
      const iguais = [48.0, 48.0, 48.0, 48.0];
      expect(dragTargetIndex(iguais, 0, 96), 2, reason: 'duas posições');
      expect(dragTargetIndex(iguais, 3, -96), 1);
    });

    test('só quem está no caminho abre espaço', () {
      expect(
        [for (var i = 0; i < 4; i++) dragShift(i, 0, 2, 48)],
        [0, -48, -48, 0],
      );
      expect(
        [for (var i = 0; i < 4; i++) dragShift(i, 3, 1, 48)],
        [0, 48, 48, 0],
      );
    });
  });

  group('gaveta', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    prepararPasta();

    testWidgets('começam fechadas; o título abre e fecha a fileira', (
      tester,
    ) async {
      final (_, app) = await abrir(tester);
      await montar(tester, app);
      expect(titulos(tester), nomesPadrao);
      expect(find.byType(ChannelGroupCard), findsNothing);

      await clicar(tester, 'Esportes');
      expect(find.byType(ChannelGroupCard), findsNWidgets(2));
      expect(
        tester.getTopLeft(titulo('Filmes')).dy -
            tester.getTopLeft(titulo('Esportes')).dy,
        greaterThan(ChannelGroupCard.height),
      );

      // A abertura vale enquanto o app estiver aberto, mesmo saindo da página.
      await montar(tester, app);
      expect(find.byType(ChannelGroupCard), findsNWidgets(2));

      await clicar(tester, 'Esportes');
      expect(find.byType(ChannelGroupCard), findsNothing);
      await fechar(tester, app);
    });

    testWidgets('favoritas sobem, abrem e voltam abertas ao recarregar', (
      tester,
    ) async {
      var (_, app) = await abrir(tester);
      await montar(tester, app);

      await favoritar(tester, 'Filmes');
      await favoritar(tester, 'Notícias');
      expect(titulos(tester), ['Filmes', 'Notícias', 'Abertos', 'Esportes']);
      expect(find.byType(ChannelGroupCard), findsNWidgets(4));

      // Fechar uma favorita e abrir uma comum não é salvo.
      await clicar(tester, 'Filmes');
      await clicar(tester, 'Abertos');
      await fechar(tester, app);

      (_, app) = await abrir(tester);
      await montar(tester, app);
      expect(app.favoriteCategories, {'3', '4'});
      expect(app.isCategoryOpen('3'), isTrue);
      expect(app.isCategoryOpen('4'), isTrue);
      expect(app.isCategoryOpen('1'), isFalse);

      await favoritar(tester, 'Filmes');
      expect(titulos(tester), ['Notícias', 'Abertos', 'Esportes', 'Filmes']);
      expect(app.isCategoryOpen('3'), isTrue, reason: 'continua como estava');
      await fechar(tester, app);
    });

    // Janela mínima do app, a de abertura e as maiores, em cada Tamanho da
    // interface das pontas.
    testWidgets('o fim da lista é exato com fileiras abertas e fechadas', (
      tester,
    ) async {
      final (_, app) = await abrir(tester, nomes: muitasCategorias);
      // Quatro abertas no alto: pela média, o fim sairia errado.
      for (var i = 1; i <= 4; i++) {
        await tester.runAsync(() => app.toggleFavoriteCategory('$i'));
      }
      await montar(tester, app);
      final posicao = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final noAlto = posicao.maxScrollExtent;
      posicao.jumpTo(noAlto);
      await tester.pumpAndSettle();
      expect(posicao.maxScrollExtent, closeTo(noAlto, 1));
      expect(posicao.pixels, closeTo(noAlto, 1));
      // Desfaz para não passar ao próximo teste (o banco é o mesmo arquivo).
      await fechar(tester, app);
    });

    testWidgets('o arraste não sai do bloco; aberta não é arrastada', (
      tester,
    ) async {
      final (_, app) = await abrir(tester);
      await montar(tester, app);
      await favoritar(tester, 'Filmes');
      await clicar(tester, 'Filmes');

      // Uma comum arrastada até o topo para no começo das comuns.
      await arrastar(tester, 'Notícias', -600);
      expect(titulos(tester), ['Filmes', 'Notícias', 'Abertos', 'Esportes']);

      // E a favorita sozinha no bloco não sai do lugar.
      await arrastar(tester, 'Filmes', 600);
      expect(titulos(tester), ['Filmes', 'Notícias', 'Abertos', 'Esportes']);

      await clicar(tester, 'Filmes');
      final area = tester.getRect(titulo('Filmes'));
      final gesto = await tester.startGesture(
        Offset(area.left + 120, area.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CategoryDragGhost), findsNothing);
      await gesto.up();
      await tester.pumpAndSettle();
      await fechar(tester, app);
    });

    testWidgets('na busca, as categorias com resultado ficam abertas', (
      tester,
    ) async {
      final (_, app) = await abrir(tester);
      await montar(tester, app, sobreVideo: true);
      await tester.enterText(find.byType(TextField), 'Esportes');
      await tester.pumpAndSettle();
      expect(titulos(tester), ['Esportes']);
      expect(find.byType(ChannelGroupCard), findsNWidgets(2));
      expect(app.isCategoryOpen('2'), isFalse, reason: 'só durante a busca');
      await fechar(tester, app);
    });
  });
}
