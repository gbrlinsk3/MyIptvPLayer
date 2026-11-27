import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/playback/playback_controller.dart';
import 'package:iptv_player/ui/live_tv/player_controls.dart';

/// Só o que o selo REC e a linha de controles usam.
class _Play extends ChangeNotifier implements PlaybackController {
  @override
  RecState get recState => RecState.idle;
  @override
  double volume = 100;
  @override
  bool get muted => false;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  testWidgets('a camada do selo REC não tira o mouse do que está atrás', (
    tester,
  ) async {
    var hovers = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          fit: StackFit.expand,
          children: [
            MouseRegion(onHover: (_) => hovers++),
            PlayerControls(
              playback: _Play(),
              fullscreen: false,
              visible: true,
              part: PlayerControlsPart.recBadge,
              onToggleFullscreen: () {},
            ),
          ],
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 100));
    addTearDown(mouse.removePointer);

    // A tela de teste tem 800×600; a faixa antiga bloqueava os ~92 px de baixo.
    for (final y in [300.0, 450.0, 520.0, 560.0, 599.0]) {
      final before = hovers;
      await mouse.moveTo(Offset(100, y));
      await tester.pump();
      expect(hovers, greaterThan(before), reason: 'mouse em y=$y');
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('linha: volume à esquerda, tela cheia à direita e sem fundo', (
    tester,
  ) async {
    var fullscreen = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: 700,
              child: PlayerControls(
                playback: _Play(),
                fullscreen: false,
                visible: false,
                part: PlayerControlsPart.row,
                onToggleFullscreen: () => fullscreen++,
              ),
            ),
          ),
        ),
      ),
    );
    final row = find.byType(PlayerControls);
    final volume = find.byTooltip('Silenciar');
    final full = find.byTooltip('Tela cheia');
    expect(
      tester.getTopLeft(volume).dx,
      moreOrLessEquals(tester.getTopLeft(row).dx, epsilon: 8),
    );
    expect(
      tester.getTopRight(full).dx,
      moreOrLessEquals(tester.getTopRight(row).dx, epsilon: 8),
    );
    expect(
      tester.getCenter(full).dy,
      moreOrLessEquals(tester.getCenter(volume).dy, epsilon: 4),
    );
    expect(
      find.descendant(of: row, matching: find.byType(DecoratedBox)).evaluate()
          .map((e) => (e.widget as DecoratedBox).decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.gradient is LinearGradient),
      isEmpty,
    );
    await tester.tap(full);
    expect(fullscreen, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
