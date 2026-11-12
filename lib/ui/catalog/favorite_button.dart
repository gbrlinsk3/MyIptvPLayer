import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../state/app_scope.dart';
import '../home/hero_buttons.dart';

/// Coração sobre os cartões de pôster/busca: aparece ao passar o mouse e fica
/// visível (preenchido, na cor do perfil) quando o título já é favorito.
/// Só o coração é reconstruído quando os favoritos mudam.
class FavoriteOverlay extends StatelessWidget {
  const FavoriteOverlay({super.key, required this.title, required this.hover});

  final CatalogTitle title;
  final bool hover;

  @override
  Widget build(BuildContext context) {
    final catalog = AppScope.read(context).catalog;
    return ValueListenableBuilder<int>(
      valueListenable: catalog.favoritesRevision,
      builder: (context, _, _) {
        final fav = catalog.isFavorite(title.kind, title.id);
        if (!hover && !fav) return const SizedBox.shrink();
        return Tooltip(
          message: fav ? 'Remover dos favoritos' : 'Adicionar aos favoritos',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => catalog.toggleFavorite(title),
            child: Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: Color(0xB3000000),
                shape: BoxShape.circle,
              ),
              child: Icon(
                fav ? Icons.favorite : Icons.favorite_border,
                size: 18,
                color: fav ? AppColors.accent : Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Botão redondo para o painel lateral de detalhes (mesmo estilo dos vizinhos).
class FavoritePanelButton extends StatelessWidget {
  const FavoritePanelButton({super.key, required this.title});

  final CatalogTitle title;

  @override
  Widget build(BuildContext context) {
    final catalog = AppScope.read(context).catalog;
    return ValueListenableBuilder<int>(
      valueListenable: catalog.favoritesRevision,
      builder: (context, _, _) {
        final fav = catalog.isFavorite(title.kind, title.id);
        return IconButton.filled(
          tooltip: fav ? 'Remover dos favoritos' : 'Adicionar aos favoritos',
          onPressed: () => catalog.toggleFavorite(title),
          style: IconButton.styleFrom(
            backgroundColor: const Color(0x99000000),
            foregroundColor: fav ? AppColors.accent : Colors.white,
          ),
          icon: Icon(fav ? Icons.favorite : Icons.favorite_border, size: 18),
        );
      },
    );
  }
}

/// Botão com texto para a tela expandida.
class FavoriteHeroButton extends StatelessWidget {
  const FavoriteHeroButton({super.key, required this.title});

  final CatalogTitle title;

  @override
  Widget build(BuildContext context) {
    final catalog = AppScope.read(context).catalog;
    return ValueListenableBuilder<int>(
      valueListenable: catalog.favoritesRevision,
      builder: (context, _, _) {
        final fav = catalog.isFavorite(title.kind, title.id);
        return HeroGhostButton(
          icon: fav ? Icons.favorite : Icons.favorite_border,
          label: fav ? 'Nos favoritos' : 'Favoritar',
          onTap: () => catalog.toggleFavorite(title),
        );
      },
    );
  }
}
