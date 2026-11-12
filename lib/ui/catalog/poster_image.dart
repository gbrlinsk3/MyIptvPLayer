import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Imagem da internet com cache em disco (pacote cached_network_image).
/// Sem endereço ou com falha, mostra um quadro neutro com o nome do título.
/// Caminho de arquivo no computador (e não endereço da web).
bool isLocalImagePath(String u) =>
    !(u.startsWith('http://') || u.startsWith('https://')) &&
    (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(u) || u.startsWith(r'\\') || u.startsWith('/'));

class PosterImage extends StatelessWidget {
  const PosterImage({
    super.key,
    required this.url,
    required this.name,
    this.fit = BoxFit.cover,
    this.cacheWidth = 360,
    this.filterQuality = FilterQuality.low,
  });

  final String? url;
  final String name;
  final BoxFit fit;

  /// Largura máxima (px) em que a imagem é decodificada na memória.
  final int cacheWidth;
  final FilterQuality filterQuality;

  Widget _fallback() {
    return ColoredBox(
      color: AppColors.hover,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            name,
            maxLines: 4,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u != null && isLocalImagePath(u)) {
      // Imagem escolhida pelo usuário no próprio computador (biblioteca).
      return Image.file(
        File(u),
        fit: fit,
        cacheWidth: cacheWidth,
        filterQuality: filterQuality,
        errorBuilder: (context, error, stack) => _fallback(),
      );
    }
    if (u == null || u.isEmpty || !(u.startsWith('http://') || u.startsWith('https://'))) {
      return _fallback();
    }
    return CachedNetworkImage(
      imageUrl: u,
      fit: fit,
      memCacheWidth: cacheWidth,
      filterQuality: filterQuality,
      fadeInDuration: const Duration(milliseconds: 160),
      placeholder: (context, url) => ColoredBox(color: AppColors.hover),
      errorWidget: (context, url, error) => _fallback(),
    );
  }
}

/// Pede ao TMDB (se a imagem vier de lá) uma versão maior da mesma arte.
/// Provedores costumam entregar `w300`/`w500`, que fica borrado em banners.
/// Qualquer outro endereço volta sem mudança.
String? tmdbSize(String? url, String size) {
  if (url == null) return null;
  return url.replaceFirstMapped(
    RegExp(r'(image\.tmdb\.org/t/p/)(?:w\d+(?:_and_h\d+_[a-z0-9]+)?|original)/'),
    (m) => '${m[1]}$size/',
  );
}

/// Tenta uma lista de endereços, na ordem, até um carregar (ex.: versão
/// grande do TMDB, depois o endereço original do servidor). Enquanto carrega
/// ou se todos falharem, fica transparente; [onExhausted] avisa a falha total.
class ChainImage extends StatefulWidget {
  const ChainImage({
    super.key,
    required this.urls,
    this.cacheWidth = 1280,
    this.onExhausted,
  });

  final List<String> urls;
  final int cacheWidth;
  final VoidCallback? onExhausted;

  @override
  State<ChainImage> createState() => _ChainImageState();
}

class _ChainImageState extends State<ChainImage> {
  int _i = 0;
  bool _told = false;

  void _next(int failed) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _i != failed) return;
      setState(() => _i++);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_i >= widget.urls.length) {
      if (!_told) {
        _told = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onExhausted?.call();
        });
      }
      return const SizedBox.shrink();
    }
    final index = _i;
    if (isLocalImagePath(widget.urls[index])) {
      return Image.file(
        File(widget.urls[index]),
        key: ValueKey(widget.urls[index]),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: widget.cacheWidth,
        errorBuilder: (context, error, stack) {
          _next(index);
          return const SizedBox.shrink();
        },
      );
    }
    return CachedNetworkImage(
      key: ValueKey(widget.urls[index]),
      imageUrl: widget.urls[index],
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: widget.cacheWidth,
      fadeInDuration: const Duration(milliseconds: 450),
      placeholder: (context, url) => const SizedBox.shrink(),
      errorWidget: (context, url, error) {
        _next(index);
        return const SizedBox.shrink();
      },
    );
  }
}

/// Fundo desfocado a partir do pôster: imagem pequena ampliada com filtro
/// suave (`FilterQuality.high`) e um desfoque real, dentro de um
/// `RepaintBoundary` (o desfoque é desenhado uma vez e reaproveitado).
/// Antes era só uma miniatura de 40 px esticada, que aparecia em "pixels".
/// [sigma] 0 desliga o desfoque (volta ao esticado, sem filtro).
class SoftBlurBackdrop extends StatelessWidget {
  const SoftBlurBackdrop({super.key, required this.url, this.sigma = 14});

  final String? url;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    final image = PosterImage(
      url: url,
      name: '',
      cacheWidth: 96,
      filterQuality: FilterQuality.high,
    );
    if (sigma <= 0) return image;
    return RepaintBoundary(
      child: ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
          child: image,
        ),
      ),
    );
  }
}
