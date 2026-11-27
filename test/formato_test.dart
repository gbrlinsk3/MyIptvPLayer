import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/theme.dart';
import 'package:iptv_player/ui/widgets/app_popup_menu.dart';
import 'package:iptv_player/ui/widgets/app_switch.dart';
import 'package:iptv_player/ui/widgets/glass.dart';
import 'package:iptv_player/ui/widgets/rebuild_on_change.dart';
import 'package:iptv_player/ui/widgets/shimmer.dart';

/// Lê o AppShape sem depender de nada herdado: sem o RebuildOnChange, um
/// `const` destes nunca seria reconstruído.
class _Sonda extends StatefulWidget {
  const _Sonda();

  @override
  State<_Sonda> createState() => _SondaState();
}

class _SondaState extends State<_Sonda> {
  int toques = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => toques++),
        child: Text('${AppShape.rounded ? 'redondo' : 'quadrado'} $toques'),
      );
}

BorderRadius _canto(WidgetTester t, Finder f) {
  final box = t.widget<Container>(
    find.descendant(of: f, matching: find.byType(Container)).first,
  );
  return (box.decoration! as BoxDecoration).borderRadius! as BorderRadius;
}

void main() {
  tearDown(() => AppShape.rounded = true);

  test('o padrão é arredondado e o quadrado zera tudo', () {
    expect(AppShape.rounded, isTrue);
    expect(AppShape.controlRadius, 999);
    expect(AppShape.cardRadius, 14);
    expect(AppShape.panelRadius, 22);
    expect(AppShape.r(28), 28);

    AppShape.rounded = false;
    expect(AppShape.control, BorderRadius.zero);
    expect(AppShape.card, BorderRadius.zero);
    expect(AppShape.panel, BorderRadius.zero);
    expect(AppShape.r(28), 0);
  });

  test('o tema aplica o formato aos componentes do Material', () {
    for (final rounded in [true, false]) {
      AppShape.rounded = rounded;
      final tema = buildTheme();
      final controle = AppShape.button;
      expect(tema.filledButtonTheme.style!.shape!.resolve({}), controle);
      expect(tema.iconButtonTheme.style!.shape!.resolve({}), controle);
      expect(tema.chipTheme.shape, controle);
      expect(tema.checkboxTheme.shape, controle);
      expect(tema.dialogTheme.shape, AppShape.panelBorder);
      expect(tema.popupMenuTheme.shape, AppShape.cardBorder);
      expect(
        (tema.snackBarTheme.shape! as RoundedRectangleBorder).borderRadius,
        AppShape.card,
      );
      expect(tema.progressIndicatorTheme.borderRadius, AppShape.control);
      expect(
        tema.sliderTheme.trackShape,
        rounded
            ? isA<RoundedRectSliderTrackShape>()
            : isA<RectangularSliderTrackShape>(),
      );
    }
  });

  testWidgets('a troca redesenha widgets const sem perder o estado', (t) async {
    Widget app() => MaterialApp(
          builder: (context, child) =>
              RebuildOnChange(value: AppShape.rounded, child: child!),
          home: const Center(child: _Sonda()),
        );

    await t.pumpWidget(app());
    await t.tap(find.text('redondo 0'));
    await t.pump();
    expect(find.text('redondo 1'), findsOneWidget);

    AppShape.rounded = false;
    await t.pumpWidget(app());
    await t.pump();
    expect(find.text('quadrado 1'), findsOneWidget);
  });

  testWidgets('interruptor: clique, teclado e formato', (t) async {
    var ligado = false;
    Widget app() => MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) => AppSwitch(
                  value: ligado,
                  onChanged: (v) => setState(() => ligado = v),
                ),
              ),
            ),
          ),
        );

    final bolinha = find.byKey(const ValueKey('app-switch-thumb'));
    await t.pumpWidget(app());
    expect(t.getSize(find.byType(AppSwitch)), const Size(52, 32));
    expect(t.getSize(bolinha), const Size(16, 16));

    await t.tap(find.byType(AppSwitch));
    await t.pumpAndSettle();
    expect(ligado, isTrue);
    expect(t.getSize(bolinha), const Size(24, 24));

    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(ligado, isFalse);

    BoxDecoration pintura() =>
        t.widget<DecoratedBox>(
          find.descendant(of: bolinha, matching: find.byType(DecoratedBox)),
        ).decoration as BoxDecoration;
    expect(pintura().borderRadius, BorderRadius.circular(999));

    AppShape.rounded = false;
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(app());
    expect(pintura().borderRadius, BorderRadius.zero);
  });

  testWidgets('linha com interruptor: clicar nela troca; desativada não', (
    t,
  ) async {
    final trocas = <bool>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppSwitchTile(
                value: false,
                onChanged: trocas.add,
                title: const Text('Ativa'),
              ),
              const AppSwitchTile(
                value: false,
                onChanged: null,
                title: Text('Desativada'),
              ),
            ],
          ),
        ),
      ),
    );

    await t.tap(find.text('Ativa'));
    await t.tap(find.text('Desativada'));
    // Quem recebe o clique em cima do interruptor é a linha.
    await t.tap(find.byType(AppSwitch).first, warnIfMissed: false);
    await t.pump();
    expect(trocas, [true, true]);
    expect(t.takeException(), isNull);
  });

  testWidgets('campo com rótulo desenha nos dois formatos', (t) async {
    for (final rounded in [true, false]) {
      AppShape.rounded = rounded;
      await t.pumpWidget(
        MaterialApp(
          key: ValueKey(rounded),
          theme: buildTheme(),
          home: Scaffold(
            body: Column(
              children: [
                TextField(decoration: fieldDecoration(label: 'Servidor')),
                TextField(
                  maxLines: 5,
                  decoration: fieldDecoration(label: 'Lista', multiline: true),
                ),
              ],
            ),
          ),
        ),
      );
      await t.tap(find.byType(TextField).first);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('esqueleto: baixo é linha, alto é cartão', (t) async {
    await t.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            SkeletonBox(key: ValueKey('linha'), width: 100, height: 12),
            SkeletonBox(key: ValueKey('poster'), width: 100, height: 150),
          ],
        ),
      ),
    );
    expect(
      _canto(t, find.byKey(const ValueKey('linha'))),
      BorderRadius.circular(999),
    );
    expect(
      _canto(t, find.byKey(const ValueKey('poster'))),
      BorderRadius.circular(14),
    );
  });

  testWidgets('item de menu: pílula com folga, reto de ponta a ponta', (
    t,
  ) async {
    for (final rounded in [true, false]) {
      AppShape.rounded = rounded;
      await t.pumpWidget(
        MaterialApp(
          key: ValueKey(rounded),
          home: Scaffold(
            body: Center(
              child: GlassMenuPanel(
                width: 200,
                children: [GlassMenuItem(label: 'Um', onPressed: () {})],
              ),
            ),
          ),
        ),
      );
      expect(
        t.getSize(find.byType(MenuItemButton)).width,
        rounded ? 184 : 200,
      );
    }
  });

  test('miniatura e recorte interno acompanham o formato', () {
    expect(AppShape.thumb, BorderRadius.circular(8));
    expect(AppShape.inset(2), BorderRadius.circular(12));
    AppShape.rounded = false;
    expect(AppShape.thumb, BorderRadius.zero);
    expect(AppShape.inset(2), BorderRadius.zero);
  });

  testWidgets('menu de "Opções": destaque em pílula ou reto, texto no lugar', (
    t,
  ) async {
    final textos = <double>[];
    for (final rounded in [true, false]) {
      AppShape.rounded = rounded;
      String? escolhido;
      await t.pumpWidget(
        MaterialApp(
          key: ValueKey(rounded),
          home: Scaffold(
            body: Center(
              child: PopupMenuButton<String>(
                tooltip: 'Opções',
                onSelected: (v) => escolhido = v,
                itemBuilder: (_) => [
                  AppPopupMenuItem(value: 'um', child: const Text('Um')),
                ],
              ),
            ),
          ),
        ),
      );
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      final item = find.byType(AppPopupMenuItem<String>);
      final destaque = find.descendant(of: item, matching: find.byType(InkWell));
      expect(
        t.getSize(destaque).width,
        t.getSize(item).width - (rounded ? 16 : 0),
      );
      final forma = t
          .widget<Material>(
            find.ancestor(of: destaque, matching: find.byType(Material)).first,
          )
          .shape;
      expect(forma, AppShape.button);
      textos.add(
        t.getTopLeft(find.text('Um')).dx - t.getTopLeft(item).dx,
      );
      await t.tap(find.text('Um'));
      await t.pumpAndSettle();
      expect(escolhido, 'um');
    }
    expect(textos.first, textos.last);
  });
}
