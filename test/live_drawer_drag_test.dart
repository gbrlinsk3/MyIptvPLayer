import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/live_tv/live_tv_page.dart';

void main() {
  const snaps = [284.0, 600.0, 900.0];
  final pick = LiveTvPage.pickSnap;

  test('soltar perto do médio volta ao médio', () {
    expect(pick(590, 0, snaps), 600);
  });

  test('arrastar para cima rápido vai ao próximo acima', () {
    expect(pick(610, -1500, snaps), 900);
    expect(pick(300, -1500, snaps), 600);
  });

  test('arrastar para baixo rápido vai ao próximo abaixo', () {
    expect(pick(590, 1500, snaps), 284);
  });

  test('abaixo de metade do baixo fecha', () {
    expect(pick(100, 0, snaps), isNull);
  });
}
