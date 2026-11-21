import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Logo/pôster de canal da TV ao vivo com cache em disco: na segunda abertura
/// do app as imagens vêm do disco, sem baixar de novo (o `Image.network` só
/// guarda na memória). [memCacheWidth]/[memCacheHeight] limitam o tamanho em
/// que a imagem é decodificada.
class LiveLogo extends StatelessWidget {
  const LiveLogo({
    super.key,
    required this.url,
    required this.fallback,
    this.fit = BoxFit.contain,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  final String url;
  final Widget fallback;
  final BoxFit fit;
  final int? memCacheWidth;
  final int? memCacheHeight;

  @override
  Widget build(BuildContext context) {
    if (!(url.startsWith('http://') || url.startsWith('https://'))) {
      return fallback;
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: Duration.zero,
      placeholder: (context, _) => const SizedBox.shrink(),
      errorWidget: (context, _, error) => fallback,
    );
  }
}
