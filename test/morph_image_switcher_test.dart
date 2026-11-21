import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/widgets/morph_image_switcher.dart';

/// PNG 1x1 de uma cor, gerado aqui mesmo (sem arquivos de imagem no teste).
Future<MemoryImage> _png(Color cor) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = cor);
  final img = await rec.endRecording().toImage(1, 1);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return MemoryImage(Uint8List.view(data!.buffer));
}

Widget _app(ImageProvider? image, {bool semAnimacao = false, Widget? ph}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: semAnimacao),
      child: Scaffold(
        body: SizedBox(
          width: 320,
          height: 180,
          child: MorphImageSwitcher(
            image: image,
            duration: const Duration(milliseconds: 400),
            placeholder: ph,
          ),
        ),
      ),
    ),
  );
}

/// Deixa o carregamento (assíncrono de verdade) das imagens e do shader andar.
Future<void> _carregar(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  await t.pump();
}

/// Carrega o shader fora do relógio falso do teste (o carregamento é real) e
/// diz se ele compilou.
Future<bool> _shader() => MorphImageSwitcher.debugReloadProgram();

void main() {
  tearDown(() => MorphImageSwitcher.debugForceFallback = false);

  testWidgets('sem imagem mostra o placeholder', (t) async {
    await t.runAsync(_shader);
    await t.pumpWidget(_app(null, ph: const Text('vazio')));
    expect(find.text('vazio'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('fallback: trocar a imagem faz cross-fade e termina na nova',
      (t) async {
    MorphImageSwitcher.debugForceFallback = true;
    late MemoryImage a, b;
    await t.runAsync(() async {
      await _shader();
      a = await _png(const Color(0xFFFF0000));
      b = await _png(const Color(0xFF0000FF));
    });

    await t.pumpWidget(_app(a));
    await _carregar(t);
    expect(find.byType(Image), findsOneWidget);
    expect(t.widget<Image>(find.byType(Image)).image, a);

    await t.pumpWidget(_app(b));
    await _carregar(t);
    await t.pump(const Duration(milliseconds: 200));
    expect(t.takeException(), isNull);
    // No meio da troca as duas imagens coexistem.
    expect(find.byType(Image), findsNWidgets(2));

    await t.pump(const Duration(milliseconds: 500));
    expect(t.takeException(), isNull);
    expect(find.byType(Image), findsOneWidget);
    expect(t.widget<Image>(find.byType(Image)).image, b);
  });

  testWidgets('sem animações: troca direta, sem cross-fade', (t) async {
    late MemoryImage a, b;
    await t.runAsync(() async {
      await _shader();
      a = await _png(const Color(0xFF00FF00));
      b = await _png(const Color(0xFFFFFF00));
    });

    await t.pumpWidget(_app(a, semAnimacao: true));
    await _carregar(t);
    await t.pumpWidget(_app(b, semAnimacao: true));
    await _carregar(t);
    await t.pump();

    expect(t.takeException(), isNull);
    expect(find.byType(Image), findsOneWidget);
    expect(t.widget<Image>(find.byType(Image)).image, b);
  });

  testWidgets('com o shader: a troca não lança erro e termina na nova',
      (t) async {
    late MemoryImage a, b, c;
    late bool shaderOk;
    await t.runAsync(() async {
      shaderOk = await _shader();
      a = await _png(const Color(0xFFFF0000));
      b = await _png(const Color(0xFF0000FF));
      c = await _png(const Color(0xFF00FF00));
    });

    await t.pumpWidget(_app(a));
    await _carregar(t);
    await t.pumpWidget(_app(b));
    await _carregar(t);
    await t.pump(const Duration(milliseconds: 200));
    // Troca no meio de uma transição: a anterior é fechada sem erro.
    await t.pumpWidget(_app(c));
    await _carregar(t);
    await t.pump(const Duration(milliseconds: 200));
    await t.pump(const Duration(milliseconds: 600));
    expect(t.takeException(), isNull);

    // O shader compila no flutter test: a imagem é desenhada pelo CustomPaint
    // (sem widget Image, que só existe no cross-fade de fallback).
    expect(shaderOk, isTrue);
    expect(find.byType(Image), findsNothing);
    expect(
      find.descendant(
        of: find.byType(MorphImageSwitcher),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );

    // Voltar a "sem imagem" libera tudo e mostra o placeholder.
    await t.pumpWidget(_app(null, ph: const Text('vazio')));
    expect(find.text('vazio'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}

