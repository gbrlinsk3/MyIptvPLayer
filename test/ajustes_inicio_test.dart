import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_controller.dart';
import 'package:iptv_player/core/layout_metrics.dart';
import 'package:iptv_player/data/catalog_models.dart';
import 'package:iptv_player/state/app_controller.dart';
import 'package:iptv_player/state/app_scope.dart';
import 'package:iptv_player/ui/catalog/endless_titles.dart';
import 'package:iptv_player/ui/catalog/title_widgets.dart';
import 'package:iptv_player/ui/shell.dart';
import 'package:iptv_player/ui/widgets/edge_scroll_marks.dart';

class _CatalogoFalso extends ChangeNotifier implements CatalogController {
  final favoritos = <int>{};

  @override
  final ValueNotifier<int> favoritesRevision = ValueNotifier(0);

  @override
  bool isFavorite(CatalogKind kind, int id) => favoritos.contains(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AppFalso extends ChangeNotifier implements AppController {
  @override
  final _CatalogoFalso catalog = _CatalogoFalso();

  @override
  int get portraitPerRow => 6;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CatalogTitle _titulo(int id) => CatalogTitle(
      kind: CatalogKind.movies,
      id: id,
      name: 'Filme $id',
      categoryId: '1',
      rating: 7.5,
    );

List<CatalogTitle> _bloco(int de, int quantos) =>
    [for (var i = de; i < de + quantos; i++) _titulo(i)];

void main() {
  test('onda da barra: maior no meio do trecho, menor nas pontas', () {
    final meio = comprimentoDoTraco(0.5, 0.4, 0.6);
    final perto = comprimentoDoTraco(0.43, 0.4, 0.6);
    expect(meio, 14);
    expect(perto, inExclusiveRange(8, 14));
    expect(comprimentoDoTraco(0.57, 0.4, 0.6), closeTo(perto, 0.001));
    expect(comprimentoDoTraco(0.4, 0.4, 0.6), 8);
    expect(comprimentoDoTraco(0.9, 0.4, 0.6), 8);
  });

  test('dica da barra lateral fica ao lado, centrada no botão', () {
    final pos = dicaAoLado(
      const TooltipPositionContext(
        target: Offset(28, 200),
        targetSize: Size(40, 42),
        tooltipSize: Size(90, 30),
        verticalOffset: 22,
        overlaySize: Size(1200, 800),
      ),
    );
    expect(pos, const Offset(56, 185));
  });

  test('três pôsteres do banner crescem com a altura dele', () {
    expect(HeroMetrics.thumbScale(440), 1);
    expect(HeroMetrics.thumbShift(440), 0);
    expect(HeroMetrics.thumbScale(640), closeTo(1.45, 0.001));
    expect(HeroMetrics.thumbShift(640), 48);
  });

  test('fileira sem fim: junta os blocos e depois recomeça', () async {
    final primeiro = _bloco(0, recentPageSize);
    final pedidos = <int>[];
    final fileira = EndlessTitles();
    Future<TitlePage> buscar(int offset) async {
      pedidos.add(offset);
      final n = offset == recentPageSize ? recentPageSize : 3;
      return (titles: _bloco(offset, n), lidos: n);
    }

    // Pedido repetido enquanto o primeiro não volta é ignorado.
    final a = fileira.more(buscar);
    expect(await fileira.more(buscar), isFalse);
    expect(await a, isTrue);
    expect(fileira.ended, isFalse);
    expect(await fileira.more(buscar), isTrue);
    expect(fileira.ended, isTrue);
    expect(await fileira.more(buscar), isFalse);
    expect(pedidos, [40, 80]);

    final total = fileira.loaded(primeiro);
    expect(total, 83);
    expect(fileira.at(primeiro, total - 1).id, 82);
    expect(fileira.at(primeiro, total).id, 0);
    expect(fileira.at(primeiro, total * 2 + 5).id, 5);
  });

  test('fileira sem fim: bloco filtrado menor não encerra a busca', () async {
    final fileira = EndlessTitles();
    await fileira.more(
      (o) async => (titles: _bloco(o, 5), lidos: recentPageSize),
    );
    expect(fileira.ended, isFalse);
  });

  Future<_AppFalso> montar(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = _AppFalso();
    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    return app;
  }

  testWidgets('carrossel: pôsteres entre as setas e volta ao mais novo',
      (tester) async {
    final primeiro = _bloco(0, recentPageSize);
    await montar(
      tester,
      TitleRow(
        label: 'Recentes',
        future: Future.value(primeiro),
        onOpen: (_) {},
        loadMore: (o) async => (titles: _bloco(o, 4), lidos: 4),
      ),
    );

    final lista = find.byType(ListView);
    expect(tester.getRect(lista).left, TitleRow.arrowColumn);
    expect(tester.getRect(lista).right, 1200 - TitleRow.arrowColumn);
    // Sem máscara na fileira: ela pesava na rolagem da página.
    expect(
      find.ancestor(of: lista, matching: find.byType(ShaderMask)),
      findsNothing,
    );

    final posicao = tester
        .state<ScrollableState>(
          find.descendant(of: lista, matching: find.byType(Scrollable)),
        )
        .position;
    final item = tester.getSize(find.byType(PosterCard).first).width +
        TitleRow.gap;
    // Até perto do fim do primeiro bloco: busca o resto (4 títulos).
    posicao.jumpTo(item * 34);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // Passa do fim (44 títulos): o mais novo aparece de novo.
    posicao.jumpTo(item * 44);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    Finder cartao(int id) => find.byWidgetPredicate(
          (w) => w is PosterCard && w.title.id == id,
        );
    expect(cartao(0), findsOneWidget);
    // O último do catálogo ainda aparece na ponta, antes do mais novo.
    expect(
      tester.getTopLeft(cartao(43)).dx,
      lessThan(tester.getTopLeft(cartao(0)).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pôster: nota só com o mouse; favorito sempre visível',
      (tester) async {
    final app = await montar(
      tester,
      Center(
        child: SizedBox(
          width: 150,
          height: 290,
          child: PosterCard(title: _titulo(1), onTap: () {}),
        ),
      ),
    );
    double nota() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.text('★ 7.5'),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    expect(nota(), 0);
    expect(find.byIcon(Icons.favorite_border), findsNothing);

    app.catalog.favoritos.add(1);
    app.catalog.favoritesRevision.value++;
    await tester.pump();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(nota(), 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(PosterCard)));
    await tester.pump(const Duration(seconds: 1));
    expect(nota(), 1);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('barra lateral de rolagem: rolar não deixa timer pendurado',
      (tester) async {
    final posicao = ValueNotifier<PosicaoRolagem?>(
      const PosicaoRolagem(
        pixels: 0,
        maxScrollExtent: 2000,
        viewportDimension: 800,
      ),
    );
    addTearDown(posicao.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: EdgeScrollMarks(posicao: posicao, aoRolar: (_) {}),
          ),
        ),
      ),
    );
    double aberta() => (tester
            .widget<CustomPaint>(
              find
                  .descendant(
                    of: find.byType(EdgeScrollMarks),
                    matching: find.byType(CustomPaint),
                  )
                  .last,
            )
            .painter! as dynamic)
        .aberta as double;

    expect(aberta(), 0);
    posicao.value = const PosicaoRolagem(
      pixels: 300,
      maxScrollExtent: 2000,
      viewportDimension: 800,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(aberta(), 1);
    // Parou de rolar: recolhe.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(aberta(), 0);
  });
}
