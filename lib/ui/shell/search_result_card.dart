import 'dart:async';

import 'package:flutter/material.dart';

import '../../catalog/catalog_controller.dart' show CatalogController;
import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../state/app_scope.dart';
import '../catalog/favorite_button.dart';
import '../catalog/poster_image.dart';

/// Cartão de resultado da busca: imagem horizontal 16:9 com título, tipo,
/// ano e nota embaixo. A lista do servidor só traz o pôster; a imagem
/// horizontal vem dos detalhes (pedidos limitados a 3 ao mesmo tempo). O
/// endereço dela fica guardado no banco ([CatalogController.cachedBackdrop]):
/// quem já foi visto aparece na hora, sem pedido ao provedor. Enquanto ela não
/// chega o cartão mostra só um fundo liso; se o título não tiver imagem
/// horizontal, o pôster aparece centralizado no fim.
class SearchResultCard extends StatefulWidget {
  const SearchResultCard({super.key, required this.title, required this.onTap});

  final CatalogTitle title;
  final VoidCallback onTap;

  /// Altura do texto embaixo da imagem.
  static const double textHeight = 66;

  @override
  State<SearchResultCard> createState() => _SearchResultCardState();
}

class _SearchResultCardState extends State<SearchResultCard> {
  Future<TitleDetails?>? _details;
  Timer? _delay;
  bool _hover = false;
  bool _failed = false;
  String? _cached;
  bool _requested = false;
  CatalogController? _catalog;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Só pede a imagem horizontal se o cartão ficar na tela por um instante:
    // ao rolar rápido, os que passam voando não geram pedidos ao provedor.
    if (_details == null && _delay == null) {
      final catalog = _catalog = AppScope.read(context).catalog;
      final t = widget.title;
      // Já conhecida de outra vez: usa direto, sem pedir os detalhes.
      _cached = catalog.cachedBackdrop(t.kind, t.id);
      if (_cached != null) return;
      _delay = Timer(const Duration(milliseconds: 150), () {
        if (mounted) {
          _requested = true;
          setState(() => _details = catalog.requestBackdrop(t.kind, t.id));
        }
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    // Saiu da tela antes de o pedido começar: cancela (não gasta internet).
    if (_requested) {
      final t = widget.title;
      _catalog?.releaseBackdrop(t.kind, t.id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.title;
    final meta = [
      t.kind == CatalogKind.movies ? 'Filme' : 'Série',
      if (t.year != null && t.year!.isNotEmpty) t.year!,
    ].join(' · ');
    final rating = t.rating;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hover ? AppColors.accent : AppColors.border,
                    width: _hover ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: FutureBuilder<TitleDetails?>(
                  future: _details,
                  builder: (context, snap) {
                    final done = snap.connectionState == ConnectionState.done;
                    final bd = _cached ?? snap.data?.backdrop;
                    final hasBackdrop = bd != null && bd.isNotEmpty && !_failed;
                    final poster = t.image ?? snap.data?.poster;
                    // O pôster só aparece no fim, se o título realmente não tem imagem horizontal.
                    final showPoster =
                        poster != null && (done || _cached != null) && !hasBackdrop;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // Sem pôster de fundo enquanto a imagem horizontal carrega
                        // (era pesado e dava impressão de lentidão): só um fundo liso.
                        const ColoredBox(color: Color(0xFF1B1A19)),
                        if (hasBackdrop)
                          ChainImage(
                            key: ValueKey(bd),
                            urls: [
                              if (tmdbSize(bd, 'w780') != bd) tmdbSize(bd, 'w780')!,
                              bd,
                            ],
                            cacheWidth: 640,
                            onExhausted: () {
                              if (mounted) setState(() => _failed = true);
                            },
                          ),
                        if (showPoster)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: PosterImage(
                              url: poster,
                              name: t.name,
                              fit: BoxFit.contain,
                              cacheWidth: 300,
                            ),
                          ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: FavoriteOverlay(title: t, hover: _hover),
                        ),
                        if (rating != null && rating > 0)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: _Badge(
                              icon: Icons.star_rounded,
                              text: rating.toStringAsFixed(1),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            SizedBox(
              height: SearchResultCard.textHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: _hover ? AppColors.accent : AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFFFFC857)),
            const SizedBox(width: 2),
            Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
