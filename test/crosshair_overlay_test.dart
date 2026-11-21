import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/widgets/crosshair_overlay.dart';

const _botaoKey = ValueKey('botao');

/// App com um alvo clicável (MouseRegion com cursor de clique) e uma área comum.
Widget _app({
  required CrosshairController controller,
  bool enabled = true,
  VoidCallback? aoClicar,
  bool semAnimacao = false,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: semAnimacao),
      child: CrosshairOverlay(enabled: enabled, controller: controller, child: child!),
    ),
    home: Scaffold(
      body: Stack(
        children: [
          Positioned(
            left: 100,
            top: 100,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: aoClicar,
                child: Container(key: _botaoKey, width: 140, height: 48, color: Colors.blueGrey),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<TestGesture> _mouse(WidgetTester t) async {
  final g = await t.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: const Offset(700, 500));
  addTearDown(g.removePointer);
  return g;
}

void main() {
  testWidgets('mover o ponteiro atualiza a posição e desenha as linhas', (t) async {
    final c = CrosshairController();
    addTearDown(c.dispose);
    await t.pumpWidget(_app(controller: c));
    expect(c.value.position, isNull);

    final g = await _mouse(t);
    await g.moveTo(const Offset(400, 300));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(c.value.position, const Offset(400, 300));
    expect(c.value.lockedRect, isNull);

    final pintura = t.renderObject<RenderBox>(find.byKey(CrosshairOverlay.paintKey));
    expect(pintura, paints..line()..line()..rrect());

    await g.moveTo(const Offset(410, 320));
    await t.pump();
    expect(c.value.position, const Offset(410, 320));
  });

  testWidgets('sobre um alvo com cursor de clique o retângulo bate com o do botão', (t) async {
    final c = CrosshairController();
    addTearDown(c.dispose);
    await t.pumpWidget(_app(controller: c));
    final g = await _mouse(t);

    await g.moveTo(const Offset(150, 120));
    await t.pump(); // quadro do movimento: agenda o hit test
    await t.pump(const Duration(milliseconds: 200)); // anima a trava
    expect(c.value.lockedRect, t.getRect(find.byKey(_botaoKey)));
    expect(c.value.position, const Offset(150, 120));

    // Com a trava completa: cantoneiras em volta do alvo e rótulo "L × A".
    await t.pump(const Duration(milliseconds: 300));
    final pintura = t.renderObject<RenderBox>(find.byKey(CrosshairOverlay.paintKey));
    expect(pintura, paints..line()..line()..path()..rrect());

    // Sai do alvo: destrava.
    await g.moveTo(const Offset(600, 450));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(c.value.lockedRect, isNull);
    expect(c.value.position, const Offset(600, 450));
  });

  testWidgets('cliques chegam ao botão', (t) async {
    final c = CrosshairController();
    addTearDown(c.dispose);
    var cliques = 0;
    await t.pumpWidget(_app(controller: c, aoClicar: () => cliques++));
    await t.tap(find.byKey(_botaoKey));
    await t.pump();
    expect(cliques, 1);

    // Também com a mira travada no botão.
    final g = await _mouse(t);
    await g.moveTo(t.getCenter(find.byKey(_botaoKey)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(c.value.lockedRect, isNotNull);
    await g.down(t.getCenter(find.byKey(_botaoKey)));
    await g.up();
    await t.pump();
    expect(cliques, 2);
  });

  testWidgets('ponteiro que sai da janela some', (t) async {
    final c = CrosshairController();
    addTearDown(c.dispose);
    await t.pumpWidget(_app(controller: c));
    final g = await t.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(300, 300));
    await g.moveTo(const Offset(310, 300));
    await t.pump();
    expect(c.value.position, isNotNull);
    await g.removePointer();
    await t.pump();
    expect(c.value.position, isNull);
    expect(c.value.lockedRect, isNull);
  });

  testWidgets('enabled=false não rastreia nem pinta', (t) async {
    final c = CrosshairController();
    addTearDown(c.dispose);
    await t.pumpWidget(_app(controller: c, enabled: false));
    final g = await _mouse(t);
    await g.moveTo(const Offset(150, 120));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(c.value, const CrosshairState());
    expect(find.byKey(CrosshairOverlay.paintKey), findsNothing);
  });

  testWidgets('ligar e desligar não remonta o conteúdo', (t) async {
    final c = CrosshairController();
    addTearDown(c.dispose);
    await t.pumpWidget(_app(controller: c, enabled: false));
    final antes = t.element(find.byKey(_botaoKey));
    await t.pumpWidget(_app(controller: c));
    expect(t.element(find.byKey(_botaoKey)), same(antes));
    expect(find.byKey(CrosshairOverlay.paintKey), findsOneWidget);

    final g = await _mouse(t);
    await g.moveTo(const Offset(150, 120));
    await t.pump();
    expect(c.value.position, isNotNull);

    await t.pumpWidget(_app(controller: c, enabled: false));
    expect(t.element(find.byKey(_botaoKey)), same(antes));
    expect(c.value, const CrosshairState());
    expect(find.byKey(CrosshairOverlay.paintKey), findsNothing);
  });

  testWidgets('disableAnimations trava sem animação', (t) async {
    final c = CrosshairController();
    addTearDown(c.dispose);
    await t.pumpWidget(_app(controller: c, semAnimacao: true));
    final g = await _mouse(t);
    await g.moveTo(const Offset(150, 120));
    await t.pump(); // agenda e avalia no pós-quadro
    expect(c.value.lockedRect, t.getRect(find.byKey(_botaoKey)));
    await t.pump();
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('quadro acompanha o alvo que cresce sob o ponteiro parado', (t) async {
    final c = CrosshairController();
    addTearDown(c.dispose);
    final largura = ValueNotifier<double>(140);
    addTearDown(largura.dispose);
    await t.pumpWidget(MaterialApp(
      builder: (context, child) => CrosshairOverlay(enabled: true, controller: c, child: child!),
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              left: 100,
              top: 100,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: ValueListenableBuilder<double>(
                  valueListenable: largura,
                  builder: (_, w, _) => SizedBox(width: w, height: 48),
                ),
              ),
            ),
          ],
        ),
      ),
    ));
    final g = await _mouse(t);
    await g.moveTo(const Offset(150, 120));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(c.value.lockedRect, const Rect.fromLTWH(100, 100, 140, 48));

    // O alvo cresce (como o cartão do Continuar assistindo) sem mexer o mouse.
    largura.value = 300;
    await t.pump();
    await t.pump();
    expect(c.value.lockedRect, const Rect.fromLTWH(100, 100, 300, 48));
  });

  testWidgets('com a interface ampliada o quadro usa o tamanho na janela', (t) async {
    final c = CrosshairController();
    addTearDown(c.dispose);
    await t.pumpWidget(MaterialApp(
      // Como o UiScale: mira fora da ampliação, conteúdo ampliado 2x.
      builder: (context, child) => CrosshairOverlay(
        enabled: true,
        controller: c,
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox(width: 400, height: 300, child: child),
        ),
      ),
      home: Stack(
        children: [
          Positioned(
            left: 50,
            top: 50,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: const SizedBox(width: 100, height: 40),
            ),
          ),
        ],
      ),
    ));
    final g = await _mouse(t);
    await g.moveTo(const Offset(150, 130));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(c.value.lockedRect, const Rect.fromLTWH(100, 100, 200, 80));
  });
}
