import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/theme.dart';
import 'package:iptv_player/ui/widgets/appearance_fade.dart';
import 'package:iptv_player/ui/widgets/rebuild_on_change.dart';

/// Guarda um valor próprio: se a árvore for recriada, ele volta a zero.
class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => taps++),
        child: LayoutBuilder(
          // Lê a paleta estática dentro de um LayoutBuilder, como várias telas.
          builder: (context, _) => ColoredBox(
            key: const ValueKey('fundo'),
            color: AppColors.bg,
            child: Text('toques: $taps', textDirection: TextDirection.ltr),
          ),
        ),
      );
}

Widget _app(
  bool dark, {
  Object? owner = 'perfil',
  bool skip = false,
  bool reduce = false,
}) {
  AppColors.applyBrightness(dark);
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: AppearanceFade(
      owner: owner,
      look: dark,
      skip: () => skip,
      child: RebuildOnChange(value: dark, child: const _Counter()),
    ),
  );
}

Color _ground(WidgetTester tester) =>
    tester.widget<ColoredBox>(find.byKey(const ValueKey('fundo'))).color;

void main() {
  tearDown(() => AppColors.applyBrightness(false));

  testWidgets('troca a paleta sem recriar a tela e esmaece a anterior',
      (tester) async {
    await tester.pumpWidget(_app(false));
    await tester.tap(find.byType(_Counter));
    await tester.pump();
    final light = _ground(tester);

    await tester.pumpWidget(_app(true));
    // A foto da tela de antes está por cima.
    expect(find.byType(RawImage), findsOneWidget);
    await tester.pump();
    await tester.pump();

    expect(find.text('toques: 1'), findsOneWidget);
    expect(_ground(tester), AppColors.bg);
    expect(_ground(tester), isNot(light));

    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets('trocar de novo no meio do fade mantém uma só foto',
      (tester) async {
    await tester.pumpWidget(_app(false));
    await tester.pumpWidget(_app(true));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(_app(false));
    expect(find.byType(RawImage), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets('sem perfil, com troca de perfil, vídeo ou sem animações a '
      'troca é direta', (tester) async {
    await tester.pumpWidget(_app(false, owner: null));
    await tester.pumpWidget(_app(true, owner: null));
    expect(find.byType(RawImage), findsNothing);

    await tester.pumpWidget(_app(true));
    await tester.pumpWidget(_app(false, owner: 'outro'));
    expect(find.byType(RawImage), findsNothing);

    await tester.pumpWidget(_app(true, owner: 'outro', skip: true));
    expect(find.byType(RawImage), findsNothing);

    await tester.pumpWidget(_app(false, owner: 'outro', reduce: true));
    expect(find.byType(RawImage), findsNothing);
  });
}
