import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/shell/lazy_pages.dart';

/// Opacidade efetiva acima do texto [texto] (produto dos Opacity/Fade).
double _opacidade(WidgetTester tester, String texto) {
  var o = 1.0;
  for (final w in tester.widgetList<Opacity>(
      find.ancestor(of: find.text(texto), matching: find.byType(Opacity)))) {
    o *= w.opacity;
  }
  for (final w in tester.widgetList<FadeTransition>(find.ancestor(
      of: find.text(texto), matching: find.byType(FadeTransition)))) {
    o *= w.opacity.value;
  }
  return o;
}

Widget _app(int index) => MaterialApp(
      home: LazyPages(
        index: index,
        // O descarte compara com o relógio real; zero descarta no próximo ciclo.
        keepFor: Duration.zero,
        revealFirstOpen: const {1},
        builders: [
          (_) => const Text('zero'),
          (_) => const Text('um'),
        ],
      ),
    );

void main() {
  testWidgets('entrada especial só na primeira abertura da página',
      (tester) async {
    await tester.pumpWidget(_app(0));
    await tester.pumpAndSettle();

    // Primeira abertura da página 1: começa transparente e termina visível.
    await tester.pumpWidget(_app(1));
    await tester.pump(const Duration(milliseconds: 60));
    expect(_opacidade(tester, 'um'), lessThan(0.5));
    await tester.pumpAndSettle();
    expect(_opacidade(tester, 'um'), closeTo(1, 0.001));

    // Sai, deixa descartar e volta: já nasce visível (sem a entrada longa).
    await tester.pumpWidget(_app(0));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('um', skipOffstage: false), findsNothing);
    await tester.pumpWidget(_app(1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_opacidade(tester, 'um'), closeTo(1, 0.001));
  });
}
