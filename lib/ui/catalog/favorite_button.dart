import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../state/app_scope.dart';
import '../home/hero_buttons.dart';
import '../widgets/click_spark.dart';
import '../widgets/press_scale.dart';

/// Coração sobre os cartões de pôster/busca: aparece ao passar o mouse e fica
/// visível (preenchido, na cor do perfil) quando o título já é favorito.
/// Só o coração é reconstruído quando os favoritos mudam.
class FavoriteOverlay extends StatelessWidget {
  const FavoriteOverlay({
    super.key,
    required this.title,
    required this.hover,
    this.onPoster = false,
  });

  final CatalogTitle title;
  final bool hover;

  /// Sobre o pôster: coração sem fundo, no canto de cima à esquerda de uma
  /// faixa com degradê (ocupa a largura toda do pôster).
  final bool onPoster;

  @override
  Widget build(BuildContext context) {
    final catalog = AppScope.read(context).catalog;
    return ValueListenableBuilder<int>(
      valueListenable: catalog.favoritesRevision,
      builder: (context, _, _) {
        final fav = catalog.isFavorite(title.kind, title.id);
        if (!hover && !fav) return const SizedBox.shrink();
        final heart = PressShield(
          child: Tooltip(
            message: fav ? 'Remover dos favoritos' : 'Adicionar aos favoritos',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (!fav) ClickSpark.noClique(context, shape: SparkShape.stars);
                catalog.toggleFavorite(title);
              },
              child: Container(
                width: 30,
                height: 30,
                decoration: onPoster
                    ? null
                    : BoxDecoration(
                        color: const Color(0xB3000000),
                        borderRadius: AppShape.control,
                      ),
                child: Icon(
                  fav ? Icons.favorite : Icons.favorite_border,
                  size: onPoster ? 20 : 18,
                  color: fav ? AppColors.accentOnMedia : Colors.white,
                  shadows: onPoster
                      ? const [Shadow(color: Color(0x99000000), blurRadius: 6)]
                      : null,
                ),
              ),
            ),
          ),
        );
        if (!onPoster) return heart;
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xB3000000), Color(0x00000000)],
            ),
          ),
          child: SizedBox(
            height: 64,
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(padding: const EdgeInsets.all(4), child: heart),
            ),
          ),
        );
      },
    );
  }
}

/// Botão só com ícone para o painel lateral de detalhes (mesmo estilo dos vizinhos).
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
          onPressed: () {
            if (!fav) ClickSpark.noClique(context, shape: SparkShape.stars);
            catalog.toggleFavorite(title);
          },
          style: IconButton.styleFrom(
            backgroundColor: const Color(0x99000000),
            foregroundColor: fav ? AppColors.accentOnMedia : Colors.white,
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
          onTap: () {
            if (!fav) ClickSpark.noClique(context, shape: SparkShape.stars);
            catalog.toggleFavorite(title);
          },
        );
      },
    );
  }
}
