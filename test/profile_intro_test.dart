import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/widgets/profile_intro.dart';

void main() {
  testWidgets('a animação dura 2,5 s, cobre a tela e chama onDone no fim',
      (t) async {
    t.view.physicalSize = const Size(1200, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var done = 0;
    var taps = 0;
    await t.pumpWidget(MaterialApp(
      home: Stack(children: [
        Positioned.fill(
          child: GestureDetector(onTap: () => taps++, child: const ColoredBox(color: Colors.red)),
        ),
        Positioned.fill(child: ProfileIntro(onDone: () => done++)),
      ]),
    ));
    await t.pump(const Duration(milliseconds: 2400));
    await t.tapAt(const Offset(600, 350));
    expect(taps, 0, reason: 'não deixa clicar por baixo');
    expect(done, 0);
    await t.pump(const Duration(milliseconds: 200));
    expect(done, 1);
  });
}
