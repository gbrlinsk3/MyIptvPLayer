import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/app_log.dart';
import '../../core/theme.dart';

/// De onde veio a imagem de fundo em uso.
enum BackdropOrigin {
  /// Imagem do PC escolhida em Personalização.
  chosen,

  /// Imagem que acompanha o app (padrão).
  bundled,
}

/// Níveis de desfoque da imagem escolhida pelo usuário. A padrão fica sempre no
/// [standard], que é o desfoque calibrado de cada tema.
class BackdropBlur {
  BackdropBlur._();

  static const labels = ['Nenhum', 'Leve', 'Médio', 'Forte', 'Intenso'];
  static const standard = 2;

  /// Quanto cada nível multiplica o desfoque do tema.
  static const _factors = [0.0, 0.5, 1.0, 2.0, 3.5];

  static int normalize(int? level) =>
      level == null || level < 0 || level >= labels.length ? standard : level;

  static double factor(int level) => _factors[normalize(level)];
}

/// Imagem de fundo em uso. [chosenFailed] = havia uma imagem escolhida, mas o
/// arquivo não abriu (apagado, movido ou formato não aceito).
class BackdropInfo {
  const BackdropInfo(this.origin, {this.chosenFailed = false});

  final BackdropOrigin origin;
  final bool chosenFailed;

  @override
  bool operator ==(Object other) =>
      other is BackdropInfo &&
      other.origin == origin &&
      other.chosenFailed == chosenFailed;

  @override
  int get hashCode => Object.hash(origin, chosenFailed);
}

/// Um candidato a imagem de fundo. [key] muda quando o arquivo muda.
class BackdropCandidate {
  const BackdropCandidate(this.origin, this.key, this.read);

  final BackdropOrigin origin;
  final String key;
  final Future<Uint8List> Function() read;
}

/// Prepara a imagem de fundo (ajuste de tons, desfoque, saturação e véu) uma
/// única vez por imagem e tema: na tela ela é só uma foto parada, sem desfoque
/// a cada quadro.
class BackdropRender {
  BackdropRender._();

  static const bundledAsset = 'assets/backgrounds/padrao.jpg';

  /// Largura de trabalho: de sobra para uma imagem desfocada.
  static const workWidth = 1280;

  /// O que está em uso agora (para o texto em Personalização).
  static final ValueNotifier<BackdropInfo?> info = ValueNotifier(null);

  /// Os dois últimos prontos (os dois temas da mesma imagem): trocar de tema
  /// não deixa a tela sem fundo.
  static final Map<String, ui.Image> _cache = {};

  /// Na ordem de preferência: a escolhida e a do app.
  static List<BackdropCandidate> candidates(String chosen) {
    BackdropCandidate? file(String path) {
      if (path.isEmpty) return null;
      try {
        final f = File(path);
        final stat = f.statSync();
        if (stat.type != FileSystemEntityType.file) return null;
        return BackdropCandidate(
          BackdropOrigin.chosen,
          '$path|${stat.size}|${stat.modified.millisecondsSinceEpoch}',
          f.readAsBytes,
        );
      } catch (_) {
        return null;
      }
    }

    return [
      ?file(chosen),
      BackdropCandidate(BackdropOrigin.bundled, bundledAsset, () async {
        final data = await rootBundle.load(bundledAsset);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }),
    ];
  }

  /// true se o arquivo abre como imagem (usado antes de salvar a escolha).
  static Future<bool> canOpen(String path) async {
    try {
      (await _decode(await File(path).readAsBytes())).dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Imagem pronta para a tela (uma cópia: quem recebe deve descartá-la). Nulo
  /// se nenhum candidato abrir; a tela fica com a cor lisa do tema.
  static Future<ui.Image?> load(
    List<BackdropCandidate> list, {
    required bool dark,
    required bool chose,
    int blur = BackdropBlur.standard,
  }) async {
    for (final c in list) {
      // O nível do usuário não alcança a imagem padrão.
      final level =
          c.origin == BackdropOrigin.chosen ? blur : BackdropBlur.standard;
      final key = '${c.key}|$dark|$level';
      try {
        var image = _cache.remove(key);
        image ??= await bake(await c.read(), dark: dark, blur: level);
        _cache[key] = image;
        while (_cache.length > 2) {
          _cache.remove(_cache.keys.first)!.dispose();
        }
        info.value = BackdropInfo(
          c.origin,
          chosenFailed: chose && c.origin != BackdropOrigin.chosen,
        );
        return image.clone();
      } catch (e) {
        AppLog.warn('fundo.${c.origin.name}', e);
      }
    }
    return null;
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) => ui.TargetImageSize(
        width: width > workWidth ? workWidth : width,
      ),
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  static final Uint8List _lift = Uint8List.fromList([
    for (var v = 0; v < 256; v++) AppBackdropStyle.lift(v),
  ]);

  static final Uint8List _tame = Uint8List.fromList([
    for (var v = 0; v < 256; v++) AppBackdropStyle.tame(v),
  ]);

  /// Claro: abre as sombras (preto vira cinza). Escuro: contém as partes
  /// claras pelo brilho do ponto, sem mudar o tom da cor.
  static Future<ui.Image> _toned(ui.Image source, {required bool dark}) async {
    final data =
        await source.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final pixels = data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final lift = _lift, tame = _tame;
    for (var i = 0; i + 3 < pixels.length; i += 4) {
      var r = pixels[i], g = pixels[i + 1], b = pixels[i + 2];
      if (dark) {
        final y = (54 * r + 183 * g + 19 * b) >> 8;
        final kept = tame[y];
        if (kept < y) {
          r = r * kept ~/ y;
          g = g * kept ~/ y;
          b = b * kept ~/ y;
        }
      } else {
        r = lift[r];
        g = lift[g];
        b = lift[b];
      }
      pixels[i] = r;
      pixels[i + 1] = g;
      pixels[i + 2] = b;
      pixels[i + 3] = 255;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      source.width,
      source.height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  static Future<ui.Image> bake(
    Uint8List bytes, {
    required bool dark,
    int blur = BackdropBlur.standard,
  }) async {
    final decoded = await _decode(bytes);
    final source = await _toned(decoded, dark: dark);
    decoded.dispose();
    final w = source.width, h = source.height;
    final style = AppBackdropStyle.of(dark);
    final sigma = style.blurFraction * w * BackdropBlur.factor(blur);
    final area = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, area);
    // Cor do tema por baixo: imagens com transparência não ficam vazadas.
    canvas.drawRect(area, Paint()..color = style.base);
    canvas.saveLayer(
      area,
      Paint()..colorFilter = saturationFilter(style.saturation),
    );
    final paint = Paint();
    if (sigma > 0) {
      paint.imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.clamp,
      );
    }
    canvas.drawImage(source, Offset.zero, paint);
    canvas.restore();
    canvas.drawRect(area, Paint()..color = style.veil);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(w, h);
    } finally {
      picture.dispose();
      source.dispose();
    }
  }
}

/// Fundo das telas principais: a imagem escolhida ou a imagem do app. Confere
/// de novo quando a janela volta ao foco (o arquivo escolhido pode ter mudado).
class AppBackdrop extends StatefulWidget {
  const AppBackdrop({
    super.key,
    required this.chosen,
    this.blur = BackdropBlur.standard,
    this.enabled = true,
  });

  /// `false` = fundo liso, na cor do tema (Minimalista sem imagem).
  final bool enabled;

  /// Caminho escolhido em Personalização (vazio = padrão).
  final String chosen;

  /// Nível de desfoque da imagem escolhida (ver [BackdropBlur]).
  final int blur;

  @override
  State<AppBackdrop> createState() => _AppBackdropState();
}

class _AppBackdropState extends State<AppBackdrop> with WindowListener {
  ui.Image? _image;
  String? _shown;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _load();
  }

  @override
  void didUpdateWidget(AppBackdrop old) {
    super.didUpdateWidget(old);
    _load();
  }

  @override
  void onWindowFocus() => _load();

  Future<void> _load() async {
    if (!widget.enabled) {
      _drop();
      return;
    }
    final dark = AppColors.isDark;
    final list = BackdropRender.candidates(widget.chosen);
    // Nada mudou (mesmos arquivos, tema e desfoque): não refaz.
    final wanted = '${list.map((c) => c.key).join('|')}|$dark|${widget.blur}';
    if (wanted == _shown) return;
    _shown = wanted;
    final request = ++_request;
    final image = await BackdropRender.load(
      list,
      dark: dark,
      chose: widget.chosen.isNotEmpty,
      blur: widget.blur,
    );
    if (!mounted || request != _request) {
      image?.dispose();
      return;
    }
    final old = _image;
    setState(() => _image = image);
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  /// Solta a imagem (fundo liso). Quem chama já vai redesenhar.
  void _drop() {
    _request++;
    _shown = null;
    final old = _image;
    if (old == null) return;
    _image = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return ColoredBox(
      color: AppColors.bg,
      child: image == null
          ? const SizedBox.expand()
          : RawImage(
              image: image,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
    );
  }
}

/// Matriz de saturação (a mesma do `saturate()` do CSS usado na prévia).
ColorFilter saturationFilter(double s) {
  const r = 0.213, g = 0.715, b = 0.072;
  return ColorFilter.matrix([
    r + (1 - r) * s, g - g * s, b - b * s, 0, 0, //
    r - r * s, g + (1 - g) * s, b - b * s, 0, 0, //
    r - r * s, g - g * s, b + (1 - b) * s, 0, 0, //
    0, 0, 0, 1, 0,
  ]);
}
