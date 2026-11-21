import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/widgets/animated_content.dart';
import 'package:iptv_player/ui/widgets/click_spark.dart';
import 'package:iptv_player/ui/widgets/magnet.dart';

Widget _app(Widget child, {bool semAnimacao = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: semAnimacao),
        child: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
      ),
    );

const _alvoKey = ValueKey('alvo');

double _opacidade(WidgetTester t) => t
    .widget<Opacity>(find.descendant(of: find.byType(AnimatedContent), matching: find.byType(Opacity)))
    .opacity;

void main() {
  group('AnimatedContent', () {
    testWidgets('começa deslocado e transparente e termina visível na posição final', (t) async {
      await t.pumpWidget(_app(const AnimatedContent(
        child: SizedBox(key: _alvoKey, width: 100, height: 40),
      )));
      // Primeiro quadro: já deslocado para baixo e invisível (layout intacto).
      await t.pump(const Duration(milliseconds: 1));
      final inicio = t.getTopLeft(find.byKey(_alvoKey));
      expect(inicio.dy, greaterThan(t.getTopLeft(find.byType(AnimatedContent)).dy + 30));
      expect(_opacidade(t), lessThan(0.1));
      expect(t.getSize(find.byKey(_alvoKey)), const Size(100, 40));
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.byKey(_alvoKey)), t.getTopLeft(find.byType(AnimatedContent)));
      expect(_opacidade(t), 1);
    });

    testWidgets('delay segura o início e a direção horizontal desloca em x', (t) async {
      await t.pumpWidget(_app(const AnimatedContent(
        direction: Axis.horizontal,
        reverse: true,
        distance: 50,
        delay: Duration(milliseconds: 300),
        child: SizedBox(key: _alvoKey, width: 100, height: 40),
      )));
      final inicial = t.getTopLeft(find.byKey(_alvoKey));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.getTopLeft(find.byKey(_alvoKey)), inicial); // ainda no delay
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.byKey(_alvoKey)).dx, inicial.dx + 50); // inicial estava 50 à esquerda
      expect(t.getTopLeft(find.byKey(_alvoKey)).dy, inicial.dy);
    });

    testWidgets('com blur termina sem filtro', (t) async {
      await t.pumpWidget(_app(const AnimatedContent(
        blur: 8,
        child: SizedBox(key: _alvoKey, width: 100, height: 40),
      )));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled, isTrue);
      await t.pumpAndSettle();
      expect(t.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled, isFalse);
    });

    testWidgets('com RevealScope não reanima o mesmo id ao remontar', (t) async {
      Widget build({required bool mostrar, Object id = 'a'}) => _app(RevealScope(
            child: mostrar
                ? AnimatedContent(revealId: id, child: const SizedBox(key: _alvoKey, width: 100, height: 40))
                : const SizedBox(),
          ));

      await t.pumpWidget(build(mostrar: true));
      await t.pump(const Duration(milliseconds: 1));
      expect(t.hasRunningAnimations, isTrue);
      await t.pumpAndSettle();

      // Some e volta com o mesmo id: nasce no estado final, sem animação.
      await t.pumpWidget(build(mostrar: false));
      await t.pumpWidget(build(mostrar: true));
      expect(t.hasRunningAnimations, isFalse);
      expect(_opacidade(t), 1);

      // Outro id no mesmo escopo anima.
      await t.pumpWidget(build(mostrar: false));
      await t.pumpWidget(build(mostrar: true, id: 'b'));
      await t.pump(const Duration(milliseconds: 1));
      expect(t.hasRunningAnimations, isTrue);
      await t.pumpAndSettle();
    });

    testWidgets('sem revealId (ou sem escopo) anima a cada montagem', (t) async {
      Widget build(bool mostrar) => _app(RevealScope(
            child: mostrar
                ? const AnimatedContent(child: SizedBox(width: 10, height: 10))
                : const SizedBox(),
          ));
      await t.pumpWidget(build(true));
      await t.pumpAndSettle();
      await t.pumpWidget(build(false));
      await t.pumpWidget(build(true));
      await t.pump(const Duration(milliseconds: 1));
      expect(t.hasRunningAnimations, isTrue);
      await t.pumpAndSettle();
    });

    testWidgets('disableAnimations nasce no estado final', (t) async {
      await t.pumpWidget(_app(
        const AnimatedContent(child: SizedBox(key: _alvoKey, width: 100, height: 40)),
        semAnimacao: true,
      ));
      expect(t.hasRunningAnimations, isFalse);
      expect(_opacidade(t), 1);
    });
  });

  group('Magnet', () {
    testWidgets('desloca com o ponteiro por perto e volta ao sair', (t) async {
      await t.pumpWidget(_app(Padding(
        padding: const EdgeInsets.all(200),
        child: Magnet(
          padding: 60,
          strength: 4,
          child: Container(key: _alvoKey, width: 100, height: 100, color: Colors.red),
        ),
      )));
      final origem = t.getTopLeft(find.byKey(_alvoKey)); // (200,200)
      final centro = t.getCenter(find.byKey(_alvoKey));

      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(5, 5));
      addTearDown(mouse.removePointer);

      // 30 px à direita da borda (dentro do padding): atrai.
      await mouse.moveTo(centro + const Offset(80, 0));
      await t.pumpAndSettle();
      final atraido = t.getTopLeft(find.byKey(_alvoKey));
      expect(atraido.dx, closeTo(origem.dx + 80 / 4, 0.01));
      expect(atraido.dy, closeTo(origem.dy, 0.01));

      // Fora da área expandida: volta ao lugar.
      await mouse.moveTo(centro + const Offset(200, 0));
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.byKey(_alvoKey)), origem);
    });

    testWidgets('não atrai além do padding nem quando enabled é falso', (t) async {
      Widget build(bool ativo) => _app(Padding(
            padding: const EdgeInsets.all(200),
            child: Magnet(
              padding: 20,
              enabled: ativo,
              child: Container(key: _alvoKey, width: 100, height: 100, color: Colors.red),
            ),
          ));
      await t.pumpWidget(build(true));
      final origem = t.getTopLeft(find.byKey(_alvoKey));
      final centro = t.getCenter(find.byKey(_alvoKey));
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(5, 5));
      addTearDown(mouse.removePointer);

      await mouse.moveTo(centro + const Offset(100, 0)); // 50 px da borda > 20
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.byKey(_alvoKey)), origem);

      await t.pumpWidget(build(false));
      await mouse.moveTo(centro + const Offset(30, 0));
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.byKey(_alvoKey)), origem);
    });

    testWidgets('não rouba cliques do filho', (t) async {
      var cliques = 0;
      await t.pumpWidget(_app(Padding(
        padding: const EdgeInsets.all(100),
        child: Magnet(
          child: GestureDetector(
            onTap: () => cliques++,
            child: Container(key: _alvoKey, width: 100, height: 100, color: Colors.red),
          ),
        ),
      )));
      await t.tap(find.byKey(_alvoKey));
      expect(cliques, 1);
      // Clique na faixa de padding (fora do filho) não chega ao filho.
      await t.tapAt(t.getTopLeft(find.byKey(_alvoKey)) - const Offset(20, 0));
      expect(cliques, 1);
    });
  });

  group('ClickSpark', () {
    for (final forma in SparkShape.values) {
      testWidgets('burst ${forma.name} insere e remove o OverlayEntry', (t) async {
        late BuildContext ctx;
        await t.pumpWidget(_app(Builder(builder: (c) {
          ctx = c;
          return const SizedBox(width: 50, height: 50);
        })));
        expect(ClickSpark.ativas, 0);
        ClickSpark.burst(ctx, globalPosition: const Offset(100, 100), shape: forma);
        await t.pump();
        expect(ClickSpark.ativas, 1);
        expect(find.byType(CustomPaint), findsWidgets);
        await t.pump(const Duration(milliseconds: 200));
        // Em andamento: desenha sem estourar.
        expect(t.takeException(), isNull);
        expect(ClickSpark.ativas, 1);
        await t.pump(const Duration(milliseconds: 300));
        await t.pump();
        expect(ClickSpark.ativas, 0);
      });
    }

    testWidgets('fromContext usa o centro do widget e termina', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(_app(Padding(
        padding: const EdgeInsets.all(100),
        child: Builder(builder: (c) {
          ctx = c;
          return const SizedBox(width: 50, height: 50);
        }),
      )));
      ClickSpark.fromContext(ctx, shape: SparkShape.stars, color: Colors.amber, count: 6);
      await t.pump();
      expect(ClickSpark.ativas, 1);
      await t.pump(const Duration(milliseconds: 500));
      await t.pump();
      expect(ClickSpark.ativas, 0);
    });

    testWidgets('não bloqueia cliques enquanto a explosão está na tela', (t) async {
      var cliques = 0;
      late BuildContext ctx;
      await t.pumpWidget(_app(Builder(builder: (c) {
        ctx = c;
        return GestureDetector(
          onTap: () => cliques++,
          child: Container(key: _alvoKey, width: 200, height: 200, color: Colors.blueGrey),
        );
      })));
      ClickSpark.burst(ctx, globalPosition: const Offset(100, 100));
      await t.pump(const Duration(milliseconds: 100));
      await t.tapAt(const Offset(100, 100));
      expect(cliques, 1);
      await t.pump(const Duration(milliseconds: 500));
      await t.pump();
      expect(ClickSpark.ativas, 0);
    });

    testWidgets('disableAnimations não desenha', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(_app(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
        semAnimacao: true,
      ));
      ClickSpark.burst(ctx, globalPosition: const Offset(10, 10));
      expect(ClickSpark.ativas, 0);
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
    });
  });
}
