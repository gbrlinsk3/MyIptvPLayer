import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/widgets/common.dart';
import 'package:iptv_player/ui/widgets/glass.dart';

void main() {
  testWidgets('menu de vidro: marca a opção em uso e troca', (t) async {
    var temporada = 2;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Align(
              alignment: Alignment.topLeft,
              child: GlassMenuButton<int>(
                tooltip: 'Temporada',
                options: [for (var i = 1; i <= 30; i++) i],
                labelOf: (s) => 'Temporada $s',
                selected: temporada,
                onSelected: (s) => setState(() => temporada = s),
                child: Text('Atual: $temporada'),
              ),
            ),
          ),
        ),
      ),
    );

    await t.tap(find.text('Atual: 2'));
    await t.pumpAndSettle();
    final marcada = t.widget<GlassMenuItem>(
      find.widgetWithText(GlassMenuItem, 'Temporada 2'),
    );
    expect(marcada.selected, isTrue);
    // Lista longa rola dentro do painel, sem passar da altura máxima.
    expect(t.getSize(find.byType(GlassMenuPanel)).height, lessThan(380));
    expect(t.takeException(), isNull);

    await t.tap(find.text('Temporada 3'));
    await t.pumpAndSettle();
    expect(find.text('Atual: 3'), findsOneWidget);
    expect(find.byType(GlassMenuPanel), findsNothing);

    // Esc fecha sem trocar.
    await t.tap(find.text('Atual: 3'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(GlassMenuPanel), findsNothing);
    expect(temporada, 3);
  });

  testWidgets('diálogo de vidro: confirma, cancela e fecha fora', (t) async {
    bool? resposta;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                resposta = await confirmDialog(
                  context,
                  title: 'Apagar?',
                  message: 'Não dá para desfazer.',
                  action: 'Apagar',
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    expect(find.byType(GlassAlertDialog), findsOneWidget);
    // O cartão acompanha o conteúdo: não ocupa a tela inteira.
    expect(t.getSize(find.byType(GlassPane)).width, inInclusiveRange(280, 600));
    expect(t.getSize(find.byType(GlassPane)).height, lessThan(320));
    await t.tap(find.text('Apagar'));
    await t.pumpAndSettle();
    expect(resposta, isTrue);

    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(find.byType(GlassAlertDialog), findsNothing);
    expect(resposta, isFalse);
  });

  testWidgets('diálogo de vidro sem botões', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: GlassAlertDialog(
          title: Text('Movendo arquivos…'),
          content: LinearProgressIndicator(value: 0.5),
        ),
      ),
    );
    expect(find.byType(OverflowBar), findsNothing);
    expect(t.takeException(), isNull);
  });
}
