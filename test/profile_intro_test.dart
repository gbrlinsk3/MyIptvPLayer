import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/widgets/profile_intro.dart';

void main() {
  testWidgets('a animação dura 3 s, cobre a tela e chama onDone no fim',
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
        Positioned.fill(child: ProfileIntro(duration: const Duration(milliseconds: 3000), onDone: () => done++)),
      ]),
    ));
    await t.pump(const Duration(milliseconds: 2900));
    await t.tapAt(const Offset(600, 350));
    expect(taps, 0, reason: 'não deixa clicar por baixo');
    expect(done, 0);
    await t.pump(const Duration(milliseconds: 200));
    expect(done, 1);
  });

  // Quantas vezes a cena terminou, 1 s de cena, com o som dado.
  Future<int Function()> pumpWithSound(
    WidgetTester t,
    Future<void> Function() sound,
  ) async {
    var done = 0;
    await t.pumpWidget(MaterialApp(
      home: ProfileIntro(
        duration: const Duration(seconds: 1),
        startSound: sound,
        onDone: () => done++,
      ),
    ));
    return () => done;
  }

  testWidgets('a cena só parte quando o som começa', (t) async {
    final sound = Completer<void>();
    final done = await pumpWithSound(t, () => sound.future);
    await t.pump(const Duration(milliseconds: 500));
    expect(done(), 0);
    sound.complete();
    await t.pump();
    await t.pump(); // primeiro quadro da animação: o relógio dela começa aqui
    await t.pump(const Duration(milliseconds: 900));
    expect(done(), 0);
    await t.pump(const Duration(milliseconds: 200));
    expect(done(), 1);
  });

  testWidgets('som travado: a cena parte depois da espera máxima', (t) async {
    final done = await pumpWithSound(t, () => Completer<void>().future);
    await t.pump(ProfileIntro.soundTimeout);
    await t.pump();
    await t.pump(const Duration(milliseconds: 1100));
    expect(done(), 1);
  });

  testWidgets('som com erro: a cena toca assim mesmo', (t) async {
    final done = await pumpWithSound(t, () async => throw StateError('x'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 1100));
    expect(done(), 1);
  });
}
