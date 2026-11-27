import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/theme.dart';
import 'package:iptv_player/ui/widgets/app_backdrop.dart';

Future<List<int>> _solidPng(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 64, 36),
    Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(64, 36);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<List<int>> _centerPixel(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final i = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
  return [for (var k = 0; k < 3; k++) data!.getUint8(i + k)];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fundo'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final file = File('${dir.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  List<BackdropOrigin> origins(String chosen) =>
      [for (final c in BackdropRender.candidates(chosen)) c.origin];

  test('ordem: imagem escolhida e imagem do app', () {
    final a = write('a.png', [1]);
    expect(origins(a), [BackdropOrigin.chosen, BackdropOrigin.bundled]);
    expect(origins(''), [BackdropOrigin.bundled]);
    // Arquivo que sumiu: pula.
    expect(origins('${dir.path}/nao_existe.png'), [BackdropOrigin.bundled]);
  });

  test('desfoque: o nível do meio é o do tema; fora da faixa volta a ele', () {
    expect(BackdropBlur.factor(BackdropBlur.standard), 1);
    expect(BackdropBlur.factor(0), 0);
    for (var i = 1; i < BackdropBlur.labels.length; i++) {
      expect(BackdropBlur.factor(i), greaterThan(BackdropBlur.factor(i - 1)));
    }
    for (final bad in [null, -1, 99]) {
      expect(BackdropBlur.normalize(bad), BackdropBlur.standard);
    }
  });

  testWidgets('o nível muda a imagem escolhida, não a padrão', (t) async {
    await t.runAsync(() async {
      // Metade preta, metade branca: o desfoque muda a borda entre elas.
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..drawRect(const Rect.fromLTWH(0, 0, 640, 360), Paint())
        ..drawRect(
          const Rect.fromLTWH(320, 0, 320, 360),
          Paint()..color = Colors.white,
        );
      final split = await recorder.endRecording().toImage(640, 360);
      final png = await split.toByteData(format: ui.ImageByteFormat.png);
      split.dispose();
      final path = write('meio.png', png!.buffer.asUint8List());

      Future<List<int>> rgba(String chosen, int blur) async {
        final image = await BackdropRender.load(
          BackdropRender.candidates(chosen),
          dark: false,
          chose: chosen.isNotEmpty,
          blur: blur,
        );
        final data =
            await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      }

      expect(await rgba(path, 0), isNot(equals(await rgba(path, 4))));
      expect(await rgba('', 0), equals(await rgba('', 4)));
    });
  });

  testWidgets('sem imagem escolhida: usa a imagem do app', (t) async {
    await t.runAsync(() async {
      final image = await BackdropRender.load(
        BackdropRender.candidates(''),
        dark: true,
        chose: false,
      );
      expect(image, isNotNull);
      expect(BackdropRender.info.value!.origin, BackdropOrigin.bundled);
      expect(BackdropRender.info.value!.chosenFailed, isFalse);
      expect(image!.width, BackdropRender.workWidth);
      image.dispose();
    });
  });

  testWidgets('imagem escolhida quebrada: cai para o padrão e avisa',
      (t) async {
    await t.runAsync(() async {
      final broken = write('quebrada.png', [0, 1, 2, 3]);
      final good = write('boa.png', await _solidPng(Colors.blue));
      expect(await BackdropRender.canOpen(broken), isFalse);
      expect(await BackdropRender.canOpen(good), isTrue);
      final image = await BackdropRender.load(
        BackdropRender.candidates(broken),
        dark: false,
        chose: true,
      );
      expect(BackdropRender.info.value!.origin, BackdropOrigin.bundled);
      expect(BackdropRender.info.value!.chosenFailed, isTrue);
      image!.dispose();
    });
  });

  testWidgets('claro levanta as sombras; escuro contém as partes claras',
      (t) async {
    expect(AppBackdropStyle.lift(0), 80);
    expect(AppBackdropStyle.lift(255), 255);
    expect(AppBackdropStyle.tame(60), 60);
    expect(AppBackdropStyle.tame(255), lessThan(120));
    await t.runAsync(() async {
      final black = await _solidPng(Colors.black);
      final white = await _solidPng(Colors.white);
      Uint8List bytes(List<int> v) => Uint8List.fromList(v);

      // Preto no claro: sombra 80 com véu claro de 30 % fica perto de 130.
      final light = await BackdropRender.bake(bytes(black), dark: false);
      final l = await _centerPixel(light);
      expect(l[0], inInclusiveRange(124, 136));
      light.dispose();

      // Branco no escuro (o pior caso) fica escuro o bastante para o texto
      // cinza ter 4,5:1.
      final darkImage = await BackdropRender.bake(bytes(white), dark: true);
      final d = await _centerPixel(darkImage);
      expect(d[0], inInclusiveRange(50, 60));
      darkImage.dispose();
      AppColors.applyBrightness(true);
      final muted = AppColors.textMuted.computeLuminance();
      final ground =
          Color.fromARGB(255, d[0], d[1], d[2]).computeLuminance();
      expect((muted + 0.05) / (ground + 0.05), greaterThanOrEqualTo(4.4));
      AppColors.applyBrightness(false);
    });
  });
}
