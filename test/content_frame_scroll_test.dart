import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/state/app_controller.dart';
import 'package:iptv_player/state/app_scope.dart';
import 'package:iptv_player/ui/shell/lazy_pages.dart';
import 'package:iptv_player/ui/widgets/content_frame.dart';
import 'package:iptv_player/ui/widgets/edge_scroll_marks.dart';

/// Controller mínimo: `ContentFrame` só lê a largura do catálogo e a aba aberta.
class _AppFalso extends ChangeNotifier implements AppController {
  _AppFalso({required this.catalogWidth, required this.shellIndex});

  @override
  int catalogWidth;

  @override
  int shellIndex;

  @override
  bool liveFullBleed = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Roda do mouse com coluna de largura fixa: fora da coluna a página rola
/// mesmo assim, e dentro dela a rolagem acontece uma única vez.
void main() {
  Future<ScrollController> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContentFrameLayout(
            largura: 1000,
            framed: true,
            pagina: 0,
            child: ListView.builder(
              controller: controller,
              itemCount: 100,
              itemBuilder: (_, i) => SizedBox(
                height: 100,
                child: Text('item $i'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  /// Duas páginas dentro do `LazyPages` como no Shell: a 0 é longa e a 1 não
  /// tem nada para rolar.
  Widget comPaginas({required int pagina, required ScrollController longa}) {
    return MaterialApp(
      home: Scaffold(
        body: ContentFrameLayout(
          largura: 1000,
          framed: true,
          pagina: pagina,
          child: LazyPages(
            index: pagina,
            builders: [
              (_) => ListView.builder(
                    controller: longa,
                    itemCount: 100,
                    itemBuilder: (_, i) => SizedBox(
                      height: 100,
                      child: Text('item $i'),
                    ),
                  ),
              (_) => const Center(child: Text('sem rolagem')),
            ],
          ),
        ),
      ),
    );
  }

  /// Opacidade atual da faixa (0 a 1), lida da animação de fade.
  double opacidadeDaFaixa(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find.descendant(
          of: find.byType(EdgeScrollMarks),
          matching: find.byType(FadeTransition),
        ),
      )
      .opacity
      .value;

  /// Com a faixa oculta ela não recebe toques (IgnorePointer ligado).
  bool ignorandoToques(WidgetTester tester) => tester
      .widget<IgnorePointer>(
        find
            .descendant(
              of: find.byType(EdgeScrollMarks),
              matching: find.byType(IgnorePointer),
            )
            .first,
      )
      .ignoring;

  /// Colhe a opacidade durante a animação de entrada/saída.
  Future<List<double>> colherOpacidades(WidgetTester tester) async {
    final valores = <double>[];
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      valores.add(opacidadeDaFaixa(tester));
    }
    return valores;
  }

  // Deixa as animações e os retornos atrasados (350 ms) terminarem.
  Future<void> assentar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('roda fora da coluna rola a página', (tester) async {
    final controller = await montar(tester);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: const Offset(50, 450),
        scrollDelta: const Offset(0, 100),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, 100);
  });

  testWidgets('roda dentro da coluna rola uma vez só', (tester) async {
    final controller = await montar(tester);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: const Offset(800, 450),
        scrollDelta: const Offset(0, 100),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, 100);
  });

  testWidgets('faixa de traços aparece quando a página tem rolagem',
      (tester) async {
    await montar(tester);
    await assentar(tester);
    expect(opacidadeDaFaixa(tester), 1);
    expect(ignorandoToques(tester), isFalse);
  });

  testWidgets('página sem rolagem oculta a faixa, mesmo com outra longa antes',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final longa = ScrollController();
    addTearDown(longa.dispose);

    await tester.pumpWidget(comPaginas(pagina: 0, longa: longa));
    await assentar(tester);
    expect(opacidadeDaFaixa(tester), 1);

    await tester.pumpWidget(comPaginas(pagina: 1, longa: longa));
    await assentar(tester);
    expect(opacidadeDaFaixa(tester), 0);
    expect(ignorandoToques(tester), isTrue);
  });

  testWidgets('página inativa que rola não altera a faixa da página aberta',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final longa = ScrollController();
    addTearDown(longa.dispose);

    await tester.pumpWidget(comPaginas(pagina: 0, longa: longa));
    await assentar(tester);
    await tester.pumpWidget(comPaginas(pagina: 1, longa: longa));
    await assentar(tester);
    expect(opacidadeDaFaixa(tester), 0);

    // A página 0 continua viva (inativa) e rola: não pode acender a faixa.
    longa.jumpTo(300);
    await tester.pump();
    await assentar(tester);
    expect(opacidadeDaFaixa(tester), 0);
  });

  testWidgets('faixa faz fade ao sair de página rolável e ao voltar',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final longa = ScrollController();
    addTearDown(longa.dispose);

    await tester.pumpWidget(comPaginas(pagina: 0, longa: longa));
    await assentar(tester);
    expect(opacidadeDaFaixa(tester), 1);

    await tester.pumpWidget(comPaginas(pagina: 1, longa: longa));
    final saida = await colherOpacidades(tester);
    expect(saida.any((v) => v > 0 && v < 1), isTrue);
    expect(saida.last, 0);

    await tester.pumpWidget(comPaginas(pagina: 0, longa: longa));
    final entrada = await colherOpacidades(tester);
    expect(entrada.any((v) => v > 0 && v < 1), isTrue);
    expect(entrada.last, 1);
    expect(ignorandoToques(tester), isFalse);
  });

  testWidgets('largura fixa vale também na TV ao vivo (aba 1)', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<(double, bool)> medir(int largura, int aba) async {
      final app = _AppFalso(catalogWidth: largura, shellIndex: aba);
      addTearDown(app.dispose);
      double? recebida;
      bool? emoldurado;
      await tester.pumpWidget(
        AppScope(
          controller: app,
          child: MaterialApp(
            home: Scaffold(
              body: ContentFrame(
                child: Builder(
                  builder: (context) {
                    emoldurado = ContentFrameScope.framedOf(context);
                    return LayoutBuilder(
                      builder: (_, box) {
                        recebida = box.maxWidth;
                        return const SizedBox.expand();
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (recebida!, emoldurado!);
    }

    expect(await medir(1200, 1), (1200.0, true));
    expect(await medir(1440, 1), (1440.0, true));
    expect(await medir(0, 1), (1600.0, false));
    // As outras abas continuam iguais.
    expect(await medir(1200, 0), (1200.0, true));
  });
}
