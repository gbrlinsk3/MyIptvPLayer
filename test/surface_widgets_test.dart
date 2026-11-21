import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/widgets/rubber_segment.dart';
import 'package:iptv_player/ui/widgets/spotlight.dart';
import 'package:iptv_player/ui/widgets/swipe_toast.dart';

/// Mouse virtual (para hover) já posicionado fora de tudo.
Future<TestGesture> _mouse(WidgetTester tester) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: const Offset(1, 1));
  addTearDown(g.removePointer);
  return g;
}

void main() {
  group('SpotlightCard', () {
    const rect = Rect.fromLTWH(0, 0, 100, 100);

    test('intensidade: 1 dentro, cai linear fora e some na proximidade', () {
      double k(Offset p) => SpotlightCard.intensityFor(
            rect: rect,
            pointer: p,
            proximity: 160,
          );
      expect(k(const Offset(50, 50)), 1);
      expect(k(const Offset(100, 100)), 1); // exatamente na borda
      // 100 px à direita da borda: 1 - 100/160.
      expect(k(const Offset(200, 50)), closeTo(0.375, 1e-9));
      expect(k(const Offset(200, 50)), greaterThan(0));
      // 200 px fora: além da proximidade.
      expect(k(const Offset(300, 50)), 0);
      // Em diagonal a distância é euclidiana.
      expect(k(const Offset(160, 160)), closeTo(1 - 84.85 / 160, 1e-3));
    });

    Widget host(List<Widget> cards, {bool group = true}) {
      final col = Column(
        mainAxisSize: MainAxisSize.min,
        children: cards,
      );
      return MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: group ? SpotlightGroup(child: col) : col,
          ),
        ),
      );
    }

    Widget card(Key key, {void Function()? onBuild}) => SpotlightCard(
          borderRadius: BorderRadius.circular(8),
          child: Builder(
            builder: (_) {
              onBuild?.call();
              return SizedBox(key: key, width: 200, height: 100);
            },
          ),
        );

    testWidgets('repinta com o hover, sem reconstruir o filho', (tester) async {
      var builds = 0;
      await tester.pumpWidget(
        host([card(const ValueKey('a'), onBuild: () => builds++)]),
      );
      final paint = find.byKey(const ValueKey('spotlight-paint'));
      expect(tester.renderObject(paint), isNot(paints..rrect()));
      final antes = builds;

      final mouse = await _mouse(tester);
      await mouse.moveTo(const Offset(100, 50));
      await tester.pump();
      expect(tester.renderObject(paint), paints..rrect());
      expect(builds, antes, reason: 'só repinta, não reconstrói');

      // Longe da proximidade (160 px) o facho some.
      await mouse.moveTo(const Offset(700, 500));
      await tester.pump();
      expect(tester.renderObject(paint), isNot(paints..rrect()));
    });

    testWidgets('no grupo, o vizinho acende de leve e o distante não',
        (tester) async {
      await tester.pumpWidget(
        host([
          card(const ValueKey('a')),
          const SizedBox(height: 300),
          card(const ValueKey('b')),
        ]),
      );
      final paints0 = find.byKey(const ValueKey('spotlight-paint'));
      expect(paints0, findsNWidgets(2));

      final mouse = await _mouse(tester);
      // Dentro do primeiro cartão (0..100); o segundo começa em y=400.
      await mouse.moveTo(const Offset(100, 90));
      await tester.pump();
      expect(tester.renderObject(paints0.at(0)), paints..rrect());
      expect(tester.renderObject(paints0.at(1)), isNot(paints..rrect()));

      // A ~100 px acima do segundo (y=300): ele já acende de leve.
      await mouse.moveTo(const Offset(100, 300));
      await tester.pump();
      expect(tester.renderObject(paints0.at(1)), paints..rrect());
      expect(tester.renderObject(paints0.at(0)), isNot(paints..rrect()));
    });

    testWidgets('sem grupo usa o próprio MouseRegion', (tester) async {
      await tester.pumpWidget(host([card(const ValueKey('a'))], group: false));
      final paint = find.byKey(const ValueKey('spotlight-paint'));
      final mouse = await _mouse(tester);
      await mouse.moveTo(const Offset(50, 50));
      await tester.pump();
      expect(tester.renderObject(paint), paints..rrect());
    });
  });

  group('SwipeToast', () {
    Widget host({
      required VoidCallback onDismiss,
      Duration? lifetime,
      VoidCallback? onTimeout,
      bool paused = false,
      Object? restartKey,
      ValueListenable<double>? progress,
      bool dismissible = true,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: 300,
              child: SwipeToast(
                onDismiss: onDismiss,
                lifetime: lifetime,
                onTimeout: onTimeout,
                paused: paused,
                restartKey: restartKey,
                progress: progress,
                dismissible: dismissible,
                child: const SizedBox(height: 100, child: Text('aviso')),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('dismissible falso ignora o arrasto', (tester) async {
      var dispensou = 0;
      await tester.pumpWidget(host(onDismiss: () => dispensou++, dismissible: false));
      await tester.drag(find.text('aviso'), const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(dispensou, 0);
      expect(find.text('aviso'), findsOneWidget);
    });

    testWidgets('arrastar 60% da altura para baixo dispensa', (tester) async {
      var dispensou = 0;
      await tester.pumpWidget(host(onDismiss: () => dispensou++));
      await tester.drag(find.text('aviso'), const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(dispensou, 1);
    });

    testWidgets('arrastar 10% volta ao lugar sem dispensar', (tester) async {
      var dispensou = 0;
      await tester.pumpWidget(host(onDismiss: () => dispensou++));
      final antes = tester.getTopLeft(find.text('aviso'));
      await tester.drag(find.text('aviso'), const Offset(0, 10));
      await tester.pumpAndSettle();
      expect(dispensou, 0);
      expect(tester.getTopLeft(find.text('aviso')).dy, closeTo(antes.dy, 0.5));
    });

    testWidgets('gesto rápido dispensa mesmo com pouco arrasto', (tester) async {
      var dispensou = 0;
      await tester.pumpWidget(host(onDismiss: () => dispensou++));
      final inicio = tester.getCenter(find.text('aviso'));
      final g = await tester.startGesture(inicio);
      var t = Duration.zero;
      for (var i = 1; i <= 4; i++) {
        t += const Duration(milliseconds: 8);
        await g.moveTo(inicio + Offset(0, 10.0 * i), timeStamp: t);
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(dispensou, 1);
    });

    testWidgets('arrastar para cima só cede um pouco e não dispensa',
        (tester) async {
      var dispensou = 0;
      await tester.pumpWidget(host(onDismiss: () => dispensou++));
      final antes = tester.getTopLeft(find.text('aviso'));
      final g = await tester.startGesture(tester.getCenter(find.text('aviso')));
      await g.moveBy(const Offset(0, -25)); // passa da folga do toque
      await g.moveBy(const Offset(0, -200));
      await tester.pump();
      final subiu = antes.dy - tester.getTopLeft(find.text('aviso')).dy;
      expect(subiu, greaterThan(0));
      expect(subiu, lessThanOrEqualTo(14));
      await g.up();
      await tester.pumpAndSettle();
      expect(dispensou, 0);
    });

    testWidgets('lifetime curto chama onTimeout', (tester) async {
      var dispensou = 0, acabou = 0;
      await tester.pumpWidget(
        host(
          onDismiss: () => dispensou++,
          onTimeout: () => acabou++,
          lifetime: const Duration(milliseconds: 300),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(acabou, 0);
      await tester.pump(const Duration(milliseconds: 250));
      expect(acabou, 1);
      expect(dispensou, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(acabou, 1, reason: 'chama uma vez só');
    });

    testWidgets('sem onTimeout, o fim do tempo chama onDismiss', (tester) async {
      var dispensou = 0;
      await tester.pumpWidget(
        host(
          onDismiss: () => dispensou++,
          lifetime: const Duration(milliseconds: 200),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(dispensou, 1);
    });

    testWidgets('o pavio encolhe com o tempo', (tester) async {
      await tester.pumpWidget(
        host(
          onDismiss: () {},
          lifetime: const Duration(seconds: 2),
        ),
      );
      double fator() => tester
          .widget<FractionallySizedBox>(
            find.byKey(const ValueKey('swipe-toast-fuse')),
          )
          .widthFactor!;
      await tester.pump();
      expect(fator(), 1);
      await tester.pump(const Duration(seconds: 1));
      expect(fator(), closeTo(0.5, 0.05));
    });

    testWidgets('mouse em cima pausa o tempo; ao sair, continua',
        (tester) async {
      var acabou = 0;
      await tester.pumpWidget(
        host(
          onDismiss: () {},
          onTimeout: () => acabou++,
          lifetime: const Duration(milliseconds: 300),
        ),
      );
      final mouse = await _mouse(tester);
      await mouse.moveTo(tester.getCenter(find.text('aviso')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(acabou, 0, reason: 'pausado pelo mouse');

      await mouse.moveTo(const Offset(700, 100));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(acabou, 1);
    });

    testWidgets('paused=true congela o tempo', (tester) async {
      var acabou = 0;
      await tester.pumpWidget(
        host(
          onDismiss: () {},
          onTimeout: () => acabou++,
          lifetime: const Duration(milliseconds: 300),
          paused: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(acabou, 0);

      await tester.pumpWidget(
        host(
          onDismiss: () {},
          onTimeout: () => acabou++,
          lifetime: const Duration(milliseconds: 300),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(acabou, 1);
    });

    testWidgets('restartKey reinicia o tempo', (tester) async {
      var acabou = 0;
      Widget montar(Object chave) => host(
            onDismiss: () {},
            onTimeout: () => acabou++,
            lifetime: const Duration(milliseconds: 500),
            restartKey: chave,
          );
      await tester.pumpWidget(montar('a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(montar('b'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(acabou, 0, reason: 'recomeçou do zero');
      await tester.pump(const Duration(milliseconds: 200));
      expect(acabou, 1);
    });

    testWidgets('progress substitui o tempo interno', (tester) async {
      final progresso = ValueNotifier<double>(1);
      addTearDown(progresso.dispose);
      var acabou = 0;
      await tester.pumpWidget(
        host(
          onDismiss: () {},
          onTimeout: () => acabou++,
          lifetime: const Duration(milliseconds: 100),
          progress: progresso,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(acabou, 0);
      progresso.value = 0.25;
      await tester.pump();
      expect(
        tester
            .widget<FractionallySizedBox>(
              find.byKey(const ValueKey('swipe-toast-fuse')),
            )
            .widthFactor,
        0.25,
      );
    });
  });

  group('RubberSegment', () {
    Widget host({
      required List<String> chamadas,
      String inicial = 'Um',
      bool semAnimacao = false,
    }) {
      var atual = inicial;
      return MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: semAnimacao),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, setState) => RubberSegment<String>(
                values: const ['Um', 'Dois', 'Três', 'Quatro'],
                labelOf: (v) => v,
                selected: atual,
                onChanged: (v) {
                  chamadas.add(v);
                  setState(() => atual = v);
                },
              ),
            ),
          ),
        ),
      );
    }

    final pilula = find.byKey(const ValueKey('rubber-pill'));
    Finder item(int i) => find.byKey(ValueKey('rubber-item-$i'));

    testWidgets('começa com a pílula sob o item escolhido', (tester) async {
      await tester.pumpWidget(host(chamadas: []));
      expect(tester.getRect(pilula).left, closeTo(tester.getRect(item(0)).left, 0.5));
      expect(tester.getRect(pilula).width, closeTo(tester.getRect(item(0)).width, 0.5));
    });

    testWidgets('tocar no 3º chama onChanged e a pílula termina sob ele',
        (tester) async {
      final chamadas = <String>[];
      await tester.pumpWidget(host(chamadas: chamadas));
      await tester.tap(item(2));
      expect(chamadas, ['Três']);
      await tester.pumpAndSettle();
      final p = tester.getRect(pilula);
      final alvo = tester.getRect(item(2));
      expect(p.left, closeTo(alvo.left, 0.5));
      expect(p.right, closeTo(alvo.right, 0.5));
      expect(p.height, closeTo(alvo.height, 0.5), reason: 'sem achatamento no fim');
    });

    testWidgets('no meio do caminho a pílula está esticada e achata no fim',
        (tester) async {
      await tester.pumpWidget(host(chamadas: []));
      final larguraItem = tester.getRect(item(0)).width;
      final altura = tester.getRect(pilula).height;
      await tester.tap(item(3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(pilula).width, greaterThan(larguraItem * 1.5));

      var achatou = false;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        if (tester.getRect(pilula).height < altura - 0.2) achatou = true;
      }
      expect(achatou, isTrue);
      await tester.pumpAndSettle();
      expect(tester.getRect(pilula).height, closeTo(altura, 0.01));
    });

    testWidgets('toque no item já selecionado não chama onChanged',
        (tester) async {
      final chamadas = <String>[];
      await tester.pumpWidget(host(chamadas: chamadas));
      await tester.tap(item(0));
      await tester.pumpAndSettle();
      expect(chamadas, isEmpty);
    });

    testWidgets('setas mudam a seleção', (tester) async {
      final chamadas = <String>[];
      await tester.pumpWidget(host(chamadas: chamadas));
      await tester.tap(item(0)); // dá o foco (sem mudar a seleção)
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(chamadas, ['Dois', 'Três', 'Dois']);
      expect(
        tester.getRect(pilula).left,
        closeTo(tester.getRect(item(1)).left, 0.5),
      );
    });

    testWidgets('setas nas pontas não saem da lista', (tester) async {
      final chamadas = <String>[];
      await tester.pumpWidget(host(chamadas: chamadas));
      await tester.tap(item(0));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(chamadas, isEmpty);
    });

    testWidgets('anuncia botões, com o escolhido selecionado', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(chamadas: [], inicial: 'Dois'));
      expect(
        tester.getSemantics(item(1)),
        matchesSemantics(
          label: 'Dois',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          hasEnabledState: false,
          isFocusable: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('com animações desligadas vai direto ao destino',
        (tester) async {
      final chamadas = <String>[];
      await tester.pumpWidget(host(chamadas: chamadas, semAnimacao: true));
      await tester.tap(item(2));
      await tester.pump();
      expect(
        tester.getRect(pilula).left,
        closeTo(tester.getRect(item(2)).left, 0.5),
      );
    });
  });
}
