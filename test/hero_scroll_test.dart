import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/home/hero_scroll.dart';

const _stage = HeroStage(
  size: Size(1600, 900),
  margins: EdgeInsets.only(left: 68, top: 64),
  height: 440,
);

/// Conta quantas vezes o conteúdo do banner é construído.
class _Conta extends StatelessWidget {
  const _Conta(this.nome, this.contagem);

  final String nome;
  final Map<String, int> contagem;

  @override
  Widget build(BuildContext context) {
    contagem[nome] = (contagem[nome] ?? 0) + 1;
    return SizedBox.expand(key: ValueKey(nome));
  }
}

void main() {
  group('medidas', () {
    test('no começo o banner é a janela inteira', () {
      expect(_stage.distance, 900 - 64 - 440);
      expect(_stage.extent, 900);
      expect(_stage.rect(0), const Rect.fromLTRB(0, 0, 1600, 900));
    });

    test('no fim é o banner de sempre, ao lado e abaixo das barras', () {
      final d = _stage.distance;
      // Em coordenadas da tela (o espaço reservado subiu junto com a página).
      expect(
        _stage.rect(d).shift(Offset(0, -d)),
        const Rect.fromLTRB(68, 64, 1600, 504),
      );
    });

    test('a borda de baixo acompanha o conteúdo pixel a pixel', () {
      for (final offset in [0.0, 100.0, 250.0, _stage.distance]) {
        expect(_stage.rect(offset).bottom - offset, 900 - offset);
      }
    });

    test('depois da transição o banner rola com a página', () {
      final d = _stage.distance;
      expect(_stage.rect(d + 200), _stage.rect(d));
    });

    test('janela baixa demais não tem transição', () {
      const baixa = HeroStage(
        size: Size(1000, 480),
        margins: EdgeInsets.only(left: 68, top: 64),
        height: 440,
      );
      expect(baixa.distance, 0);
      expect(baixa.progress(0), 1);
      expect(baixa.rect(0), const Rect.fromLTRB(68, 64, 1000, 504));
    });
  });

  group('encaixe', () {
    test('um toque da roda completa no sentido da rolagem', () {
      expect(heroSnapTarget(100, 400, 1), 400);
      expect(heroSnapTarget(300, 400, -1), 0);
    });

    test('movimento mínimo volta para onde estava', () {
      expect(heroSnapTarget(40, 400, 1), 0);
      expect(heroSnapTarget(360, 400, -1), 400);
    });

    test('em janela muito alta um toque da roda continua bastando', () {
      expect(heroSnapTarget(100, 900, 1), 900);
      expect(heroSnapTarget(800, 900, -1), 0);
    });

    test('nas pontas e fora da transição não mexe', () {
      expect(heroSnapTarget(0, 400, 1), isNull);
      expect(heroSnapTarget(400, 400, -1), isNull);
      expect(heroSnapTarget(700, 400, 1), isNull);
      expect(heroSnapTarget(100, 0, 1), isNull);
    });
  });

  group('rolagem', () {
    late HeroScrollController scroll;
    late ValueNotifier<bool> segurando;

    Future<void> montar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      segurando = ValueNotifier(false);
      scroll = HeroScrollController(holding: segurando)..zone = 400;
      addTearDown(() {
        scroll.dispose();
        segurando.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            controller: scroll,
            child: const SizedBox(height: 3000, width: 1600),
          ),
        ),
      );
    }

    /// Deixa a rolagem parar, o encaixe começar (é por temporizador, que o
    /// `pumpAndSettle` sozinho não espera) e terminar.
    Future<void> assentar(WidgetTester tester) async {
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
    }

    Future<void> roda(WidgetTester tester, double dy) =>
        tester.sendEventToBinding(
          PointerScrollEvent(
            position: const Offset(800, 450),
            scrollDelta: Offset(0, dy),
          ),
        );

    testWidgets('suaviza o toque da roda e completa a transição', (
      tester,
    ) async {
      await montar(tester);
      await roda(tester, 100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(scroll.offset, greaterThan(0));
      expect(scroll.offset, lessThan(400), reason: 'não salta');
      await assentar(tester);
      expect(scroll.offset, 400);
    });

    testWidgets('para cima volta à tela cheia', (tester) async {
      await montar(tester);
      scroll.jumpTo(400);
      await tester.pumpAndSettle();
      await roda(tester, -100);
      await assentar(tester);
      expect(scroll.offset, 0);
    });

    testWidgets('toques seguidos somam', (tester) async {
      await montar(tester);
      scroll.jumpTo(400);
      await tester.pumpAndSettle();
      // Dentro da página (depois da transição) a roda também é suave.
      await roda(tester, 100);
      await tester.pump();
      expect(scroll.offset, lessThan(500));
      await roda(tester, 100);
      await assentar(tester);
      expect(scroll.offset, 600);

      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        await roda(tester, 100);
        await tester.pump(const Duration(milliseconds: 30));
      }
      await assentar(tester);
      expect(scroll.offset, 600, reason: 'passa da transição sem perder toques');
    });

    testWidgets('segurando a barra de rolagem só encaixa ao soltar', (
      tester,
    ) async {
      await montar(tester);
      segurando.value = true;
      await roda(tester, 200);
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.offset, 200);
      segurando.value = false;
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(scroll.offset, 400);
    });

    testWidgets('reduzir animações troca de uma vez', (tester) async {
      await montar(tester);
      scroll.reduceMotion = true;
      await roda(tester, 100);
      await tester.pump();
      expect(scroll.offset, 400);
      await roda(tester, -100);
      await tester.pump();
      expect(scroll.offset, 0);
    });
  });

  group('roda fora do recorte', () {
    // Largura em px: o conteúdo fica no meio, com sobra dos dois lados.
    const estreito = HeroStage(
      size: Size(1600, 900),
      margins: EdgeInsets.only(left: 268, top: 64, right: 200),
      height: 440,
    );

    Future<ScrollController> montar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: HeroWheelArea(
            scroll: scroll,
            child: ClipRect(
              clipper: HeroViewportClipper(estreito, scroll),
              child: SingleChildScrollView(
                controller: scroll,
                child: const SizedBox(height: 3000, width: 1600),
              ),
            ),
          ),
        ),
      );
      scroll.jumpTo(estreito.distance + 100);
      await tester.pump();
      return scroll;
    }

    for (final (onde, x) in [('à esquerda', 150.0), ('à direita', 1500.0)]) {
      testWidgets('na sobra $onde a página rola', (tester) async {
        final scroll = await montar(tester);
        final antes = scroll.offset;
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: Offset(x, 450),
            scrollDelta: const Offset(0, 100),
          ),
        );
        await tester.pumpAndSettle();
        expect(scroll.offset, antes + 100);
      });
    }

    testWidgets('sobre o conteúdo a roda não conta duas vezes', (tester) async {
      final scroll = await montar(tester);
      final antes = scroll.offset;
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(800, 450),
          scrollDelta: Offset(0, 100),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, antes + 100);
    });
  });

  group('palco', () {
    testWidgets(
        'menores escondidos na tela cheia, revelados ao rolar, sem reconstruir',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final contagem = <String, int>{};

      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                HeroStageLayout(
                  stage: _stage,
                  scroll: scroll,
                  framed: false,
                  main: _Conta('grande', contagem),
                  sideTop: _Conta('cima', contagem),
                  sideBottom: _Conta('baixo', contagem),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );

      Rect area(String nome) => tester.getRect(find.byKey(ValueKey(nome)));
      double opacidade(String nome) => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byKey(ValueKey(nome)),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;

      expect(area('grande'), const Rect.fromLTRB(0, 0, 1600, 900));
      expect(area('cima').left, greaterThanOrEqualTo(1600));
      expect(opacidade('cima'), 0);
      expect(opacidade('baixo'), 0);
      final antes = Map.of(contagem);

      scroll.jumpTo(_stage.distance * 0.5);
      await tester.pump();
      expect(opacidade('cima'), greaterThan(opacidade('baixo')));

      scroll.jumpTo(_stage.distance);
      await tester.pump();
      expect(opacidade('cima'), 1);
      expect(opacidade('baixo'), 1);
      expect(area('grande').topLeft, const Offset(68, 64));
      expect(area('grande').bottom, 504);
      expect(area('cima').right, 1600);
      expect(area('cima').left, area('grande').right + HeroStageLayout.gap);
      expect(area('baixo').bottom, 504);
      expect(contagem, antes, reason: 'a rolagem só reposiciona');
    });
  });
}
