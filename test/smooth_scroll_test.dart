import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/widgets/edge_scroll_marks.dart';
import 'package:iptv_player/ui/widgets/smooth_scroll.dart';

void main() {
  late ScrollController scroll;
  var toques = 0;

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => EdgeScrollMarks.segurando.value = false);
    toques = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SmoothScroll(
          builder: (_, controller) {
            scroll = controller;
            return ListView.builder(
              controller: controller,
              itemExtent: 100,
              itemCount: 20, // 2000 px: dá para rolar 1400
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => toques++,
                child: ColoredBox(color: Colors.black, child: Text('$i')),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> roda(WidgetTester tester, double dy) => tester.sendEventToBinding(
        PointerScrollEvent(
          position: const Offset(400, 300),
          scrollDelta: Offset(0, dy),
        ),
      );

  Future<void> assentar(WidgetTester tester) =>
      tester.pumpAndSettle(const Duration(milliseconds: 16));

  testWidgets('o giro da roda anda aos poucos, sem passar do ponto', (
    tester,
  ) async {
    await montar(tester);
    await roda(tester, 100);
    var anterior = 0.0;
    var quadros = 0;
    while (tester.binding.hasScheduledFrame) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(scroll.offset, inInclusiveRange(anterior, 100));
      expect(scroll.offset - anterior, lessThan(35), reason: 'sem saltos');
      anterior = scroll.offset;
      quadros++;
    }
    expect(scroll.offset, 100);
    expect(quadros, inInclusiveRange(10, 40));
  });

  testWidgets('giros seguidos somam e mudar de sentido volta', (tester) async {
    await montar(tester);
    for (var i = 0; i < 3; i++) {
      await roda(tester, 100);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await assentar(tester);
    expect(scroll.offset, 300);
    await roda(tester, 100);
    await tester.pump(const Duration(milliseconds: 40));
    await roda(tester, -100);
    await assentar(tester);
    expect(scroll.offset, 300);
  });

  testWidgets('para nas pontas da lista', (tester) async {
    await montar(tester);
    await roda(tester, 5000);
    await assentar(tester);
    expect(scroll.offset, 1400);
    await roda(tester, -9000);
    await assentar(tester);
    expect(scroll.offset, 0);
  });

  testWidgets('arrastando a barra de rolagem a página vai direto', (
    tester,
  ) async {
    await montar(tester);
    EdgeScrollMarks.segurando.value = true;
    await roda(tester, 250);
    await tester.pump();
    expect(scroll.offset, 250);
  });

  testWidgets('clicar durante o movimento funciona', (tester) async {
    await montar(tester);
    await roda(tester, 300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 48));
    expect(scroll.position.isScrollingNotifier.value, isTrue);
    await tester.tapAt(const Offset(400, 300));
    expect(toques, 1);
    await assentar(tester);
  });

  testWidgets('sair da tela no meio do movimento não dá erro', (tester) async {
    await montar(tester);
    await roda(tester, 300);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });
}
