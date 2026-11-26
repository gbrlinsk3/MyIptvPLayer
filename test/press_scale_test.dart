import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/widgets/press_scale.dart';

void main() {
  double escala(WidgetTester tester, Key key) => tester
      .widget<AnimatedScale>(
        find
            .descendant(
              of: find.byKey(key),
              matching: find.byType(AnimatedScale),
            )
            .first,
      )
      .scale;

  const fora = Key('fora');
  const dentro = Key('dentro');
  const protegido = Key('protegido');

  Future<void> monta(WidgetTester tester, VoidCallback onTap) {
    return tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PressScale(
            key: fora,
            child: Container(
              width: 300,
              height: 200,
              color: Colors.black,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  PressScale(
                    key: dentro,
                    child: GestureDetector(
                      onTap: onTap,
                      child: const SizedBox(
                        width: 60,
                        height: 60,
                        child: Text('a'),
                      ),
                    ),
                  ),
                  const PressShield(
                    child: SizedBox(
                      key: protegido,
                      width: 60,
                      height: 60,
                      child: ColoredBox(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('encolhe ao apertar, volta ao soltar e não rouba o toque', (
    tester,
  ) async {
    var taps = 0;
    await monta(tester, () => taps++);
    final g = await tester.startGesture(
      tester.getTopLeft(find.byKey(fora)) + const Offset(10, 10),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(escala(tester, fora), PressScale.pressedScale);
    await g.up();
    await tester.pumpAndSettle();
    expect(escala(tester, fora), 1);
    await tester.tap(find.text('a'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('botão interno não encolhe o cartão', (tester) async {
    await monta(tester, () {});
    var g = await tester.startGesture(
      tester.getCenter(find.byKey(dentro)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(escala(tester, dentro), PressScale.pressedScale);
    expect(escala(tester, fora), 1);
    await g.up();
    await tester.pumpAndSettle();

    g = await tester.startGesture(
      tester.getCenter(find.byKey(protegido)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(escala(tester, fora), 1);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('arrastar solta o efeito; botão direito não aciona', (
    tester,
  ) async {
    await monta(tester, () {});
    final canto = tester.getTopLeft(find.byKey(fora)) + const Offset(10, 10);
    var g = await tester.startGesture(canto, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await g.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(escala(tester, fora), 1);
    await g.up();

    g = await tester.startGesture(
      canto,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    expect(escala(tester, fora), 1);
    await g.up();
  });
}
