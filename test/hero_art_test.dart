import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/home/hero_art.dart';

Future<List<int>> _png() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 40, 20),
    Paint()..color = const Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(40, 20);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('hero_art'));
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('a imagem do banner carrega uma vez e continua na memória',
      (tester) async {
    await tester.runAsync(() async {
      final file = File('${dir.path}/a.png')..writeAsBytesSync(await _png());
      final urls = [file.path];

      expect(HeroArt.ready(urls, HeroArt.thumb), isNull);
      final first = await HeroArt.load(urls, HeroArt.thumb);
      expect(first, isNotNull);

      // Sem o arquivo e com o cache comum vazio, carregar de novo falharia.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      file.deleteSync();
      PaintingBinding.instance.imageCache.clear();

      expect(HeroArt.ready(urls, HeroArt.thumb), same(first));
      var immediate = false;
      final stream = first!.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener(
        (info, synchronous) {
          immediate = synchronous;
          info.dispose();
        },
      );
      stream.addListener(listener);
      expect(immediate, isTrue);
      stream.removeListener(listener);
    });
  });

  testWidgets('ao hibernar as imagens são soltas e dá para ler de novo',
      (tester) async {
    await tester.runAsync(() async {
      final file = File('${dir.path}/c.png')..writeAsBytesSync(await _png());
      final urls = [file.path];
      expect(await HeroArt.load(urls, HeroArt.thumb), isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      HeroArt.release();
      expect(HeroArt.ready(urls, HeroArt.thumb), isNull);

      expect(await HeroArt.load(urls, HeroArt.thumb), isNotNull);
      expect(HeroArt.ready(urls, HeroArt.thumb), isNotNull);
      HeroArt.release();
    });
  });

  testWidgets('endereço que falha passa ao próximo e pode ser tentado de novo',
      (tester) async {
    await tester.runAsync(() async {
      final missing = '${dir.path}/faltando.png';
      final good = File('${dir.path}/b.png')..writeAsBytesSync(await _png());

      expect(await HeroArt.load([missing, good.path], HeroArt.thumb), isNotNull);
      expect(HeroArt.ready([missing], HeroArt.thumb), isNull);

      File(missing).writeAsBytesSync(await _png());
      expect(await HeroArt.load([missing], HeroArt.thumb), isNotNull);
    });
    // O erro esperado do arquivo ausente não pode reprovar o teste.
    tester.takeException();
  });
}
