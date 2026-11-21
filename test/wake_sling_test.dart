import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/widgets/sling_arrow.dart';
import 'package:iptv_player/ui/widgets/wake_slider.dart';

void main() {
  group('WakeSlider', () {
    late List<double> mudancas;
    late List<double> fins;

    Widget host({double inicial = 50, bool semAnimacao = false}) {
      var valor = inicial;
      return MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: semAnimacao),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, setState) => WakeSlider(
                value: valor,
                onChanged: (v) {
                  mudancas.add(v);
                  setState(() => valor = v);
                },
                onChangeEnd: fins.add,
              ),
            ),
          ),
        ),
      );
    }

    setUp(() {
      mudancas = [];
      fins = [];
    });

    final slider = find.byType(WakeSlider);

    testWidgets('arrastar muda o valor e chama onChangeEnd ao soltar',
        (tester) async {
      await tester.pumpWidget(host(inicial: 0));
      final r = tester.getRect(slider);
      final g = await tester.startGesture(Offset(r.left + 6, r.center.dy));
      expect(mudancas.last, 5); // 6/120 = 5%
      await g.moveTo(Offset(r.left + 60, r.center.dy));
      expect(mudancas.last, 50);
      await g.moveTo(Offset(r.left + 300, r.center.dy)); // além da ponta
      expect(mudancas.last, 100);
      expect(fins, isEmpty, reason: 'só ao soltar');
      await g.up();
      expect(fins, [100]);
      await tester.pumpAndSettle();
    });

    testWidgets('arrastar também funciona com o mouse', (tester) async {
      await tester.pumpWidget(host(inicial: 10));
      final r = tester.getRect(slider);
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.down(Offset(r.left + 90, r.center.dy));
      await g.moveTo(Offset(r.left + 30, r.center.dy));
      await g.up();
      expect(mudancas.last, 25);
      expect(fins, [25]);
      await tester.pumpAndSettle();
    });

    for (final restaurar in [false, true]) {
      testWidgets(
          'restoreFocusOnRelease=$restaurar: depois do clique o foco ${restaurar ? 'volta a quem tinha' : 'fica no controle'}',
          (tester) async {
        final antes = FocusNode(debugLabel: 'pagina');
        addTearDown(antes.dispose);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Focus(focusNode: antes, child: const SizedBox(width: 10, height: 10)),
                WakeSlider(
                  value: 50,
                  onChanged: (_) {},
                  restoreFocusOnRelease: restaurar,
                ),
              ],
            ),
          ),
        ));
        antes.requestFocus();
        await tester.pump();
        expect(antes.hasPrimaryFocus, isTrue);
        final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await g.down(tester.getCenter(slider));
        await tester.pump();
        expect(antes.hasPrimaryFocus, isFalse, reason: 'durante o clique o foco é do controle');
        await g.up();
        await tester.pumpAndSettle();
        expect(antes.hasPrimaryFocus, restaurar);
      });
    }

    testWidgets('clicar pula ao ponto tocado', (tester) async {
      await tester.pumpWidget(host(inicial: 0));
      final r = tester.getRect(slider);
      await tester.tapAt(Offset(r.left + 90, r.center.dy));
      expect(mudancas, [75]);
      expect(fins, [75]);
      await tester.pumpAndSettle();
    });

    testWidgets('roda do mouse muda ±5', (tester) async {
      await tester.pumpWidget(host());
      final centro = tester.getCenter(slider);
      await tester.sendEventToBinding(
        PointerScrollEvent(position: centro, scrollDelta: const Offset(0, -20)),
      );
      expect(mudancas, [55]);
      expect(fins, [55]);
      await tester.sendEventToBinding(
        PointerScrollEvent(position: centro, scrollDelta: const Offset(0, 20)),
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(position: centro, scrollDelta: const Offset(0, 20)),
      );
      expect(mudancas, [55, 50, 45]);
      expect(fins, [55, 50, 45]);
      await tester.pumpAndSettle();
    });

    testWidgets('teclado: setas ±5, Home e End', (tester) async {
      await tester.pumpWidget(host());
      // Tocar no meio (50) dá o foco sem mudar o valor.
      await tester.tapAt(tester.getCenter(slider));
      expect(mudancas, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(mudancas, [55, 60, 55, 50]);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      expect(mudancas.sublist(4), [0, 100]);
      expect(fins.length, 7); // 1 do toque + 6 do teclado
      await tester.pumpAndSettle();
    });

    testWidgets('não passa dos limites e não repete valores iguais',
        (tester) async {
      await tester.pumpWidget(host(inicial: 100));
      await tester.tapAt(
        tester.getTopRight(slider) + const Offset(-0.1, 14),
      );
      await tester.pump();
      mudancas.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(mudancas, isEmpty, reason: 'já está em 100');
      await tester.pumpAndSettle();
    });

    testWidgets('anuncia controle deslizante com o valor em %', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(inicial: 40));
      final s = tester.getSemantics(slider);
      expect(s.label, 'Volume');
      expect(s.value, '40%');
      expect(s.flagsCollection.isSlider, isTrue);
      handle.dispose();
    });

    testWidgets('com animações desligadas não deixa quadros pendentes',
        (tester) async {
      await tester.pumpWidget(host(inicial: 0, semAnimacao: true));
      await tester.tapAt(tester.getCenter(slider));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(mudancas, [50]);
    });
  });

  group('SlingArrowButton', () {
    late int disparos;

    Widget host({bool left = false, bool enabled = true}) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SlingArrowButton(
                left: left,
                enabled: enabled,
                onFire: () => disparos++,
              ),
            ),
          ),
        );

    setUp(() => disparos = 0);

    final botao = find.byType(SlingArrowButton);

    /// Segura no botão, puxa [dx] pixels e solta.
    Future<void> puxar(WidgetTester tester, double dx) async {
      final g = await tester.startGesture(tester.getCenter(botao));
      await g.moveBy(Offset(dx / 2, 0));
      await g.moveBy(Offset(dx / 2, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await g.up();
      await tester.pumpAndSettle();
    }

    testWidgets('clique chama onFire uma vez', (tester) async {
      await tester.pumpWidget(host());
      await tester.tap(botao);
      await tester.pumpAndSettle();
      expect(disparos, 1);
    });

    testWidgets('movimento mínimo ainda conta como clique', (tester) async {
      await tester.pumpWidget(host());
      await puxar(tester, -4);
      expect(disparos, 1);
    });

    testWidgets('arrasto curto não dispara', (tester) async {
      await tester.pumpWidget(host()); // seta para a direita: trás = esquerda
      await puxar(tester, -12);
      expect(disparos, 0);
    });

    testWidgets('puxar além de armAt dispara uma vez', (tester) async {
      await tester.pumpWidget(host());
      await puxar(tester, -30);
      expect(disparos, 1);
    });

    testWidgets('seta para a esquerda puxa para a direita', (tester) async {
      await tester.pumpWidget(host(left: true));
      await puxar(tester, 12);
      expect(disparos, 0);
      await puxar(tester, 30);
      expect(disparos, 1);
    });

    testWidgets('puxar para qualquer lado dispara ao passar de armAt',
        (tester) async {
      await tester.pumpWidget(host());
      await puxar(tester, 40); // para a frente da seta da direita
      expect(disparos, 1);

      // Para cima, para baixo e na diagonal.
      for (final delta in const [
        Offset(0, -40),
        Offset(0, 40),
        Offset(28, 28),
        Offset(-28, -28),
      ]) {
        final g = await tester.startGesture(tester.getCenter(botao));
        await g.moveBy(delta / 2);
        await g.moveBy(delta / 2);
        await tester.pump(const Duration(milliseconds: 50));
        await g.up();
        await tester.pumpAndSettle();
      }
      expect(disparos, 5);
    });

    testWidgets('puxão curto em qualquer direção não dispara', (tester) async {
      await tester.pumpWidget(host());
      for (final delta in const [Offset(0, -12), Offset(0, 12), Offset(9, 9)]) {
        final g = await tester.startGesture(tester.getCenter(botao));
        await g.moveBy(delta);
        await tester.pump(const Duration(milliseconds: 50));
        await g.up();
        await tester.pumpAndSettle();
      }
      expect(disparos, 0);
    });

    testWidgets('o botão segue o puxão na vertical e volta ao soltar',
        (tester) async {
      await tester.pumpWidget(host());
      final antes = tester.getCenter(find.byIcon(Icons.chevron_right));
      final g = await tester.startGesture(tester.getCenter(botao));
      await g.moveBy(const Offset(0, 20));
      await g.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
      final esticado = tester.getCenter(find.byIcon(Icons.chevron_right));
      expect(esticado.dy, greaterThan(antes.dy + 10));
      expect(esticado.dx, closeTo(antes.dx, 0.5));
      await g.up();
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byIcon(Icons.chevron_right)).dy,
        closeTo(antes.dy, 0.1),
      );
    });

    testWidgets('o botão se afasta ao esticar e volta ao soltar',
        (tester) async {
      await tester.pumpWidget(host());
      final antes = tester.getCenter(find.byIcon(Icons.chevron_right));
      final g = await tester.startGesture(tester.getCenter(botao));
      await g.moveBy(const Offset(-20, 0));
      await g.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
      final esticado = tester.getCenter(find.byIcon(Icons.chevron_right));
      expect(esticado.dx, lessThan(antes.dx - 10));
      expect(esticado.dx, greaterThan(antes.dx - 36 - 0.01),
          reason: 'limitado por maxPull');
      await g.up();
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byIcon(Icons.chevron_right)).dx,
        closeTo(antes.dx, 0.1),
      );
    });

    testWidgets('enabled=false não dispara por toque nem teclado',
        (tester) async {
      await tester.pumpWidget(host(enabled: false));
      await tester.tap(botao);
      await tester.pumpAndSettle();
      await puxar(tester, -30);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(disparos, 0);
    });

    testWidgets('Enter e Espaço disparam', (tester) async {
      await tester.pumpWidget(host());
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(disparos, 2);
    });

    testWidgets('tooltip e semântica conforme o lado', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(left: true));
      expect(find.byTooltip('Anterior'), findsOneWidget);
      final sem = tester.getSemantics(find.bySemanticsLabel('Anterior').first);
      expect(sem.flagsCollection.isButton, isTrue);
      await tester.pumpWidget(host());
      expect(find.byTooltip('Próximo'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('com animações desligadas dispara sem animar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: SlingArrowButton(
                left: false,
                enabled: true,
                onFire: () => disparos++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(botao);
      await tester.pump();
      expect(disparos, 1);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
