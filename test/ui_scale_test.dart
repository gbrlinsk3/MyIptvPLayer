import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/widgets/ui_scale.dart';

/// Valida a ideia do plano 7B: ampliar a interface inteira sem quebrar toque,
/// hover, campo de texto, tamanho lógico e diálogos.
Size? lastSize;

void main() {
  const scale = 1.5;

  void setWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget app({
    required VoidCallback onTap,
    required void Function(bool) onHover,
    TextEditingController? text,
    FocusNode? focus,
    double s = scale,
  }) {
    return MaterialApp(
      builder: (context, child) => UiScale(scale: s, child: child!),
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand, // sem isto a Stack teria tamanho 0 e nada receberia toque
          children: [
            Builder(builder: (context) {
              // O que o filho enxerga como tamanho da janela.
              lastSize = MediaQuery.sizeOf(context);
              return const SizedBox.shrink();
            }),
            Positioned(
              left: 400,
              top: 200,
              width: 100,
              height: 50,
              child: MouseRegion(
                onEnter: (_) => onHover(true),
                onExit: (_) => onHover(false),
                child: GestureDetector(
                  key: const Key('alvo'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: const ColoredBox(color: Colors.red),
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: 330,
              width: 200,
              child: TextField(key: const Key('campo'), controller: text, focusNode: focus),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('tamanho lógico = janela / escala e o alvo aparece ampliado',
      (tester) async {
    setWindow(tester);
    await tester.pumpWidget(app(onTap: () {}, onHover: (_) {}));
    expect(lastSize, const Size(600, 400));
    // Lógico (400,200)-(500,250) → na tela (600,300)-(750,375).
    expect(tester.getRect(find.byKey(const Key('alvo'))),
        const Rect.fromLTWH(600, 300, 150, 75));
  });

  testWidgets('toque acerta na posição ampliada e erra na posição sem escala',
      (tester) async {
    setWindow(tester);
    var taps = 0;
    await tester.pumpWidget(app(onTap: () => taps++, onHover: (_) {}));

    await tester.tapAt(const Offset(450, 225)); // seria o centro sem escala
    expect(taps, 0);
    await tester.tapAt(const Offset(675, 337)); // centro ampliado
    expect(taps, 1);
    // Perto do canto oposto da janela também responde (não só o 1/escala do
    // canto superior esquerdo).
    await tester.tapAt(const Offset(745, 370));
    expect(taps, 2);
  });

  testWidgets('hover (MouseRegion) acompanha a posição ampliada', (tester) async {
    setWindow(tester);
    final events = <bool>[];
    await tester.pumpWidget(app(onTap: () {}, onHover: events.add));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(const Offset(675, 337));
    await tester.pump();
    expect(events, [true]);
    await mouse.moveTo(const Offset(450, 225));
    await tester.pump();
    expect(events, [true, false]);
  });

  testWidgets('campo de texto ampliado recebe foco e texto', (tester) async {
    setWindow(tester);
    final text = TextEditingController();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      app(onTap: () {}, onHover: (_) {}, text: text, focus: focus),
    );
    // Lógico x 10..210 → tela 15..315; y 330.. → 495..
    expect(focus.hasFocus, isFalse);
    await tester.tapAt(const Offset(100, 520));
    await tester.pump();
    expect(focus.hasFocus, isTrue); // o toque ampliado chegou ao campo
    await tester.enterText(find.byKey(const Key('campo')), 'olá');
    expect(text.text, 'olá');
    final field = tester.getRect(find.byKey(const Key('campo')));
    expect(field.left, closeTo(15, 0.01));
    expect(field.width, closeTo(300, 0.01));
  });

  testWidgets('diálogos também são ampliados (ficam dentro do Navigator)',
      (tester) async {
    setWindow(tester);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => UiScale(scale: scale, child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(
                content: SizedBox(width: 200, height: 100, child: Text('oi')),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(AlertDialog));
    // Centrado na janela física e 1,5× maior que o tamanho lógico.
    expect(box.center.dx, closeTo(450, 1));
    expect(box.center.dy, closeTo(300, 1));
    expect(box.width, greaterThan(300)); // ≥ (200 + margens) × 1,5
  });

  testWidgets('trocar a escala não recria o app (estado preservado)',
      (tester) async {
    setWindow(tester);
    final text = TextEditingController(text: 'x');
    await tester.pumpWidget(app(onTap: () {}, onHover: (_) {}, text: text, s: 1.0));
    final stateBefore = tester.state(find.byType(TextField));
    await tester.pumpWidget(app(onTap: () {}, onHover: (_) {}, text: text, s: 1.5));
    expect(tester.state(find.byType(TextField)), same(stateBefore));
    expect(lastSize, const Size(600, 400));
  });
}
