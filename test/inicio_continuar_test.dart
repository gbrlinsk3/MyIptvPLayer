import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/format.dart';
import 'package:iptv_player/data/catalog_models.dart';
import 'package:iptv_player/ui/widgets/timed_switcher.dart';

CatalogTitle _title({String? subtitle, int? position, int? duration}) =>
    CatalogTitle(
      kind: CatalogKind.series,
      id: 1,
      name: 'Série',
      categoryId: '',
      subtitle: subtitle,
      positionMs: position,
      durationMs: duration,
    );

void main() {
  group('tempo restante', () {
    const min = 60000;

    test('minutos, com singular e arredondamento para cima', () {
      expect(formatRemaining(10 * min, 22 * min), 'faltam 12 min');
      expect(formatRemaining(10 * min, 10 * min + 1), 'falta 1 min');
    });

    test('uma hora ou mais', () {
      expect(formatRemaining(min, 61 * min), 'falta 1 h');
      expect(formatRemaining(min, 66 * min), 'falta 1 h 05 min');
      expect(formatRemaining(min, 133 * min), 'faltam 2 h 12 min');
    });

    test('sem duração ou sem nada começado não mostra', () {
      expect(formatRemaining(null, 10 * min), isNull);
      expect(formatRemaining(min, 0), isNull);
      expect(formatRemaining(0, 10 * min), isNull);
      expect(formatRemaining(10 * min, 10 * min), isNull);
    });

    test('linha do cartão: série, filme e próximo episódio', () {
      expect(
        _title(
          subtitle: 'T6 · E9',
          position: 10 * min,
          duration: 22 * min,
        ).continueLabel,
        'T6 · E9 · faltam 12 min',
      );
      expect(
        _title(position: 10 * min, duration: 58 * min).continueLabel,
        'faltam 48 min',
      );
      expect(
        _title(subtitle: 'T1 · E8 · Próximo episódio').continueLabel,
        'T1 · E8 · Próximo episódio',
      );
      expect(_title().continueLabel, isNull);
    });
  });

  group('TimedSwitcher', () {
    Widget host(String text, int ms) => Directionality(
      textDirection: TextDirection.ltr,
      child: TimedSwitcher(
        duration: Duration(milliseconds: ms),
        child: Text(text, key: ValueKey(text)),
      ),
    );

    testWidgets('quem sai usa a duração nova, não a de quando entrou', (
      tester,
    ) async {
      await tester.pumpWidget(host('a', 1000));
      await tester.pumpWidget(host('b', 350));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('a'), findsNothing);

      // "b" entrou em 350 ms; a saída automática leva o tempo lento.
      await tester.pumpWidget(host('c', 1000));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('b'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('b'), findsNothing);
    });

    testWidgets('trocas seguidas não deixam restos', (tester) async {
      await tester.pumpWidget(host('a', 350));
      await tester.pumpWidget(host('b', 350));
      await tester.pumpWidget(host('c', 350));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(host('d', 350));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.byType(Text), findsOneWidget);
      expect(find.text('d'), findsOneWidget);
    });
  });
}
