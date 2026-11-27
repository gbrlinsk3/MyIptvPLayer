import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../catalog/poster_image.dart';

/// Imagens dos banners do Início. Cada uma é baixada e decodificada **uma
/// vez** e fica na memória até o app fechar: um ouvinte que nunca sai a mantém
/// viva, mesmo além do limite do cache de imagens do Flutter. Ao reabrir o app,
/// os banners sorteados carregam de novo.
abstract final class HeroArt {
  /// Larguras de decodificação, uma por uso.
  static const int backdrop = 1920; // fundo de título que passa no grande
  static const int small = 900; // fundo que só aparece no banner menor
  static const int front = 700; // pôster nítido (título sem imagem horizontal)
  static const int thumb = 360;
  static const int _blurSource = 96;

  /// Desfoque, em pixels da imagem de [_blurWidth] de largura. Equivalem ao
  /// antigo sigma 14 na tela: o grande é largo, o menor estica bem menos.
  static const double bigBlur = 1.6;
  static const double sideBlur = 6;
  static const int _blurWidth = 192;

  static final Map<String, _Kept> _kept = {};
  static final Map<String, ui.Image> _blurred = {};
  static final Map<String, Future<ui.Image?>> _blurring = {};

  static List<String> backdropUrls(String url, {bool full = true}) {
    final sized = tmdbSize(url, full ? 'w1280' : 'w780')!;
    return [if (sized != url) sized, url];
  }

  static _Kept _hold(String url, int width) {
    final key = '$width|$url';
    final existing = _kept[key];
    if (existing != null) return existing;

    final ImageProvider source = isLocalImagePath(url)
        ? FileImage(File(url))
        : CachedNetworkImageProvider(url);
    final kept = _Kept(ResizeImage(source, width: width));
    _kept[key] = kept;

    final stream = kept.provider.resolve(ImageConfiguration.empty);
    kept.stream = stream;
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (kept.done.isCompleted) {
          info.dispose(); // GIF: só o primeiro quadro interessa
          return;
        }
        kept.info = info;
        kept.done.complete(info.image);
        // Quem a mantém é o ouvinte: sai do cache comum para não ocupar o
        // limite dele à toa (os pôsteres das outras telas ficam).
        scheduleMicrotask(() async {
          final cacheKey =
              await kept.provider.obtainKey(ImageConfiguration.empty);
          PaintingBinding.instance.imageCache
              .evict(cacheKey, includeLive: false);
        });
      },
      onError: (error, stack) {
        if (kept.done.isCompleted) return;
        _kept.remove(key); // pode tentar de novo (ex.: voltou a internet)
        stream.removeListener(listener);
        kept.provider.evict();
        kept.done.complete(null);
      },
    );
    kept.listener = listener;
    stream.addListener(listener);
    return kept;
  }

  /// Solta todas as imagens guardadas (hibernação). Só pode ser chamado com o
  /// Início fora da tela; ao voltar, elas são lidas de novo do cache em disco.
  static void release() {
    for (final kept in _kept.values.toList()) {
      final listener = kept.listener;
      if (listener != null) kept.stream?.removeListener(listener);
      kept.info?.dispose();
      kept.info = null;
      kept.provider.evict();
      if (!kept.done.isCompleted) kept.done.complete(null);
    }
    _kept.clear();
    for (final image in _blurred.values) {
      image.dispose();
    }
    _blurred.clear();
    _blurring.clear();
  }

  /// O primeiro endereço da lista já carregado, sem esperar.
  static ImageProvider? ready(List<String> urls, int width) {
    for (final url in urls) {
      final kept = _kept['$width|$url'];
      if (kept?.info != null) return kept!.provider;
    }
    return null;
  }

  /// Carrega o primeiro endereço que funcionar; `null` se nenhum funcionar.
  static Future<ImageProvider?> load(List<String> urls, int width) async {
    for (final url in urls) {
      final kept = _hold(url, width);
      if (await kept.done.future != null) return kept.provider;
    }
    return null;
  }

  static String _blurKey(String url, double sigma) => '$sigma|$url';

  /// Pôster desfocado, desenhado uma vez numa imagem pequena. Esticá-la custa
  /// quase nada; desfocar ao vivo a janela inteira, com o zoom andando, custava
  /// mais de 100 ms por quadro.
  static Future<ui.Image?> blurred(String url, double sigma) {
    final key = _blurKey(url, sigma);
    return _blurring[key] ??= () async {
      final source = await _hold(url, _blurSource).done.future;
      if (source == null) {
        _blurring.remove(key);
        return null;
      }
      final height =
          (_blurWidth * source.height / source.width).round().clamp(1, 600);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        source,
        Offset.zero &
            Size(source.width.toDouble(), source.height.toDouble()),
        Offset.zero & Size(_blurWidth.toDouble(), height.toDouble()),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(_blurWidth, height);
      picture.dispose();
      return _blurred[key] = image;
    }();
  }

  /// Tudo o que o título usa no carrossel. [full]: passa no banner grande
  /// (senão, aparece só no banner menor).
  static Future<void> loadTitle(
    CatalogTitle title,
    TitleDetails? details, {
    bool full = true,
  }) async {
    final bd = details?.backdrop;
    var hasBackdrop = false;
    if (bd != null && bd.isNotEmpty) {
      final already = ready(backdropUrls(bd), backdrop);
      hasBackdrop = already != null ||
          await load(backdropUrls(bd, full: full), full ? backdrop : small) !=
              null;
    }
    final poster = title.image ?? details?.poster;
    if (poster == null || !poster.startsWith('http')) return;
    await blurred(poster, full ? bigBlur : sideBlur);
    if (full) await load([poster], thumb);
    if (!hasBackdrop) await load([tmdbSize(poster, 'w780')!], front);
  }
}

class _Kept {
  _Kept(this.provider);

  final ImageProvider provider;
  final Completer<ui.Image?> done = Completer();

  /// Guardada para a imagem não ser liberada.
  ImageInfo? info;

  ImageStream? stream;
  ImageStreamListener? listener;
}

/// Imagem do carrossel vinda do [HeroArt]. Já carregada, aparece na hora; senão
/// entra num fade curto. Enquanto isso mostra [placeholder]; se nenhum endereço
/// abrir, [fallback] (ou o [placeholder]) e avisa [onFailed].
class HeroImage extends StatefulWidget {
  const HeroImage({
    super.key,
    required this.urls,
    required this.width,
    this.placeholder = const SizedBox.shrink(),
    this.fallback,
    this.onFailed,
  });

  final List<String> urls;
  final int width;
  final Widget placeholder;
  final Widget? fallback;
  final VoidCallback? onFailed;

  @override
  State<HeroImage> createState() => _HeroImageState();
}

class _HeroImageState extends State<HeroImage> {
  ImageProvider? _provider;
  bool _failed = false;
  bool _fade = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(HeroImage old) {
    super.didUpdateWidget(old);
    if (old.width != widget.width ||
        old.urls.join('\n') != widget.urls.join('\n')) {
      _load();
    }
  }

  void _load() {
    final request = ++_request;
    _failed = false;
    _provider = HeroArt.ready(widget.urls, widget.width);
    _fade = _provider == null;
    if (_provider != null) return;
    HeroArt.load(widget.urls, widget.width).then((provider) {
      if (!mounted || request != _request) return;
      setState(() {
        _provider = provider;
        _failed = provider == null;
      });
      if (provider == null) widget.onFailed?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null) {
      return _failed
          ? widget.fallback ?? widget.placeholder
          : widget.placeholder;
    }
    final image = Image(
      image: provider,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
    );
    if (!_fade || MediaQuery.disableAnimationsOf(context)) return image;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      child: image,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
    );
  }
}

/// Pôster desfocado de fundo, a partir da imagem pronta do [HeroArt.blurred].
class HeroBlur extends StatefulWidget {
  const HeroBlur({super.key, required this.url, this.sigma = HeroArt.bigBlur});

  final String url;
  final double sigma;

  @override
  State<HeroBlur> createState() => _HeroBlurState();
}

class _HeroBlurState extends State<HeroBlur> {
  // Pedida só ao criar ou trocar de imagem: o banner reconstrói a cada quadro
  // da rolagem, e uma imagem com erro seria baixada de novo a cada um.
  late Future<ui.Image?> _future = _request();

  Future<ui.Image?> _request() => HeroArt.blurred(widget.url, widget.sigma);

  @override
  void didUpdateWidget(HeroBlur old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.sigma != widget.sigma) _future = _request();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image?>(
      future: _future,
      initialData:
          HeroArt._blurred[HeroArt._blurKey(widget.url, widget.sigma)],
      builder: (context, snap) {
        final image = snap.data;
        if (image == null) return ColoredBox(color: AppColors.hover);
        return RawImage(
          image: image,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          filterQuality: FilterQuality.medium,
        );
      },
    );
  }
}

/// Degradês do banner, desenhados uma vez numa imagem e depois só esticados.
/// Desenhados ao vivo, mudando de tamanho a cada quadro da rolagem, custavam
/// cerca de 170 ms por quadro. Vale para degradês horizontais e verticais, que
/// esticados continuam iguais. [layers] precisa ser uma lista `const`.
class BakedShade extends StatelessWidget {
  const BakedShade(this.layers, {super.key});

  final List<LinearGradient> layers;

  static const int _side = 512;
  static final Map<List<LinearGradient>, ui.Image> _images = {};

  static ui.Image _bake(List<LinearGradient> layers) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Offset.zero & Size.square(_side.toDouble());
    for (final layer in layers) {
      canvas.drawRect(rect, Paint()..shader = layer.createShader(rect));
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(_side, _side);
    picture.dispose();
    return image;
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.infinite,
        painter: _ShadePainter(_images[layers] ??= _bake(layers)),
      );
}

class _ShadePainter extends CustomPainter {
  const _ShadePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_ShadePainter old) => old.image != image;
}
