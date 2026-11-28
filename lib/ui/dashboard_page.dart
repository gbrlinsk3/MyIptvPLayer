import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/catalog_models.dart';
import '../state/app_scope.dart';
import 'catalog/title_details_panel.dart';
import 'catalog/title_widgets.dart';
import 'home/continue_strip.dart';
import 'home/hero_carousel.dart';
import 'home/hero_scroll.dart';
import 'widgets/content_frame.dart';
import 'widgets/edge_scroll_marks.dart';

/// Início estilo Netflix: banner, "continuar assistindo", adicionados recentemente
/// e, no fim, resumos de TV ao vivo e conta. Só mostra dados que o app tem.
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.onOpenCatalog,
    this.active = true,
    this.covered = false,
  });

  final ValueChanged<CatalogKind> onOpenCatalog;

  /// O Início é a aba aberta. Ao sair dela a página volta ao topo, para
  /// reabrir com o banner em tela cheia.
  final bool active;

  /// A busca está aberta por cima.
  final bool covered;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final HeroScrollController _scroll =
      HeroScrollController(holding: EdgeScrollMarks.segurando);

  /// Medida da transição no último layout.
  double? _zone;

  /// Chave dos banners que vieram vazios (sem banner não há tela cheia).
  Key? _emptyHeroKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(DashboardPage old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active) {
      // Depois do quadro (a rolagem avisa outros widgets), já fora da tela.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.active && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Janela redimensionada: quem já tinha passado da transição continua
  /// vendo o mesmo trecho da página.
  void _applyZone(double zone) {
    final before = _zone;
    _zone = zone;
    _scroll.zone = zone;
    if (before == null || before == zone) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final past = position.pixels - before;
      if (before <= 0 || past < -0.5) return;
      _scroll.jumpTo(
        (zone + past).clamp(0.0, position.maxScrollExtent).toDouble(),
      );
    });
  }

  /// Baixa filmes e séries (um de cada vez) se nunca foram baixados ou estão velhos.
  Future<void> _load() async {
    if (!mounted) return;
    final catalog = AppScope.read(context).catalog;
    await catalog.ensureFresh(CatalogKind.movies);
    if (!mounted) return;
    await catalog.ensureFresh(CatalogKind.series);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final catalog = c.catalog;
    final syncing = catalog.section(CatalogKind.movies).syncing ||
        catalog.section(CatalogKind.series).syncing;
    final hasCatalog = catalog.section(CatalogKind.movies).total > 0 ||
        catalog.section(CatalogKind.series).total > 0;

    void open(CatalogTitle t) => showTitleDetails(context, t);

    final heroKey = ValueKey(
      'hero:${catalog.progressRevision}:${catalog.bannersRevision}'
      ':${catalog.section(CatalogKind.movies).total}'
      ':${catalog.section(CatalogKind.series).total}',
    );
    final showHero = hasCatalog && _emptyHeroKey != heroKey;

    // A página ocupa a janela inteira; as margens são onde o conteúdo fica no
    // layout normal.
    final margins = ContentFrameScope.margensOf(context);
    final sides = EdgeInsets.only(left: margins.left, right: margins.right);
    final heroHeight = HeroCarousel.heightFor(context);
    // Com um diálogo ou outra tela por cima, a barra volta às cores normais.
    final onScreen = widget.active &&
        !widget.covered &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _scroll.reduceMotion = MediaQuery.disableAnimationsOf(context);

    return LayoutBuilder(
      builder: (context, box) {
        final stage = HeroStage(
          size: box.biggest,
          margins: margins,
          // Sem banner, a "altura" cobre a janela: não há transição.
          height: showHero
              ? heroHeight
              : (box.maxHeight - margins.top).clamp(0.0, double.infinity),
        );
        _applyZone(stage.distance);

        // Column dentro de rolagem simples (poucas fileiras): sem alturas
        // estimadas, então não "pula" ao subir.
        return HeroWheelArea(
          scroll: _scroll,
          child: ClipRect(
            clipper: HeroViewportClipper(stage, _scroll),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 24),
              child: ConstrainedBox(
                // Mesmo antes de as fileiras chegarem dá para rolar a transição.
                constraints: BoxConstraints(
                  minHeight: box.maxHeight + stage.distance,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showHero)
                      HeroCarousel(
                        key: heroKey,
                        future: catalog.heroSlides(),
                        onOpenCatalog: widget.onOpenCatalog,
                        stage: stage,
                        scroll: _scroll,
                        onScreen: onScreen,
                        onUnavailable: () =>
                            setState(() => _emptyHeroKey = heroKey),
                      )
                    else
                      Padding(
                        padding: sides.copyWith(top: margins.top),
                        child: hasCatalog
                            ? const SizedBox.shrink()
                            : _EmptyHero(
                                syncing: syncing,
                                error: catalog
                                        .section(CatalogKind.movies)
                                        .error ??
                                    catalog.section(CatalogKind.series).error,
                                onRetry: _load,
                              ),
                      ),
                    Padding(
                      padding: sides,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 28),
                          ContinueStrip(
                            key: ValueKey(
                              'home:continue:${catalog.progressRevision}',
                            ),
                            future: catalog.continueAll(),
                          ),
                          TitleRow(
                            key: const ValueKey('home:movies:recent'),
                            label: 'Filmes adicionados recentemente',
                            future: catalog.recentTitles(CatalogKind.movies),
                            loadMore: (offset) =>
                                catalog.recentPage(CatalogKind.movies, offset),
                            onOpen: open,
                            onSeeAll: () =>
                                widget.onOpenCatalog(CatalogKind.movies),
                          ),
                          TitleRow(
                            key: const ValueKey('home:series:recent'),
                            label: 'Séries adicionadas recentemente',
                            future: catalog.recentTitles(CatalogKind.series),
                            loadMore: (offset) =>
                                catalog.recentPage(CatalogKind.series, offset),
                            onOpen: open,
                            onSeeAll: () =>
                                widget.onOpenCatalog(CatalogKind.series),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Banner enquanto o catálogo de filmes/séries ainda não foi baixado.
class _EmptyHero extends StatelessWidget {
  const _EmptyHero({
    required this.syncing,
    required this.error,
    required this.onRetry,
  });

  final bool syncing;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // Baixando: esqueleto da forma do banner, na altura que ele terá ao chegar.
    if (syncing) return HeroSkeleton(height: HeroCarousel.heightFor(context));
    return Container(
      height: 220,
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.panel,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filmes e séries',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            error ??
                'O catálogo ainda não foi baixado ou o provedor não tem filmes/séries.',
            style: TextStyle(
              color: error != null ? AppColors.danger : AppColors.textMuted,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: OutlinedButton(
              onPressed: onRetry,
              child: const Text('Tentar de novo'),
            ),
          ),
        ],
      ),
    );
  }
}
