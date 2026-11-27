import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/window/hibernator.dart';

void main() {
  const quase = Duration(minutes: 1, seconds: 59);
  const segundo = Duration(seconds: 1);

  /// [corpo] roda com um hibernador ligado e a janela volta ao fim.
  Future<void> com(
    WidgetTester tester,
    Future<void> Function(Hibernator h) corpo, {
    bool Function()? ocupado,
  }) async {
    await tester.pumpWidget(const SizedBox());
    final h = Hibernator(busy: ocupado ?? () => false)..attach();
    try {
      await corpo(h);
    } finally {
      h.restored();
      await tester.pump();
      h.dispose();
      Hibernator.holds.clear();
    }
  }

  testWidgets('hiberna com 2 minutos minimizado e acorda ao voltar', (
    tester,
  ) async {
    await com(tester, (h) async {
      h.minimized();
      await tester.pump(quase);
      expect(Hibernator.asleep.value, isFalse);
      await tester.pump(segundo);
      expect(Hibernator.asleep.value, isTrue);
      h.restored();
      expect(Hibernator.asleep.value, isFalse);
    });
  });

  testWidgets('voltando antes dos 2 minutos não hiberna', (tester) async {
    await com(tester, (h) async {
      h.minimized();
      await tester.pump(quase);
      h.restored();
      await tester.pump(const Duration(minutes: 5));
      expect(Hibernator.asleep.value, isFalse);
    });
  });

  testWidgets('com TV tocando ou gravando espera parar', (tester) async {
    var tocando = true;
    await com(tester, ocupado: () => tocando, (h) async {
      h.minimized();
      await tester.pump(const Duration(minutes: 10));
      expect(Hibernator.asleep.value, isFalse);
      tocando = false;
      await tester.pump(h.retry);
      expect(Hibernator.asleep.value, isTrue);
    });
  });

  testWidgets('filme tocando em outro player também segura', (tester) async {
    var tocando = true;
    await com(tester, (h) async {
      Hibernator.holds.add(() => tocando);
      h.minimized();
      await tester.pump(const Duration(minutes: 3));
      expect(Hibernator.asleep.value, isFalse);
      tocando = false;
      await tester.pump(h.retry);
      expect(Hibernator.asleep.value, isTrue);
    });
  });

  testWidgets('minimizado o desenho fica desligado, mesmo perdendo o foco', (
    tester,
  ) async {
    await com(tester, (h) async {
      final app = SchedulerBinding.instance;
      h.minimized();
      await tester.pump();
      expect(app.lifecycleState, AppLifecycleState.hidden);
      expect(app.framesEnabled, isFalse);

      // O Windows avisa a perda de foco depois.
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.lifecycle.name,
        const StringCodec().encodeMessage('AppLifecycleState.inactive'),
        (_) {},
      );
      await tester.pump();
      expect(app.framesEnabled, isFalse);

      h.restored();
      await tester.pump();
      expect(app.lifecycleState, AppLifecycleState.resumed);
      expect(app.framesEnabled, isTrue);
    });
  });
}
