import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/catalog_models.dart';
import '../state/app_scope.dart';
import 'catalog/title_details_panel.dart';
import 'catalog/title_widgets.dart';
import 'home/continue_strip.dart';
import 'home/hero_carousel.dart';

/// Início estilo Netflix: banner, "continuar assistindo", adicionados recentemente
/// e, no fim, resumos de TV ao vivo e conta. Só mostra dados que o app tem.
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.onOpenCatalog,
  });

  final VoidCallback onOpenCatalog;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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

    // Column dentro de rolagem simples (poucas fileiras): sem alturas estimadas,
    // então não "pula" ao subir.
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasCatalog)
          HeroCarousel(
            key: ValueKey(
              'hero:${catalog.progressRevision}:${catalog.bannersRevision}'
              ':${catalog.section(CatalogKind.movies).total}'
              ':${catalog.section(CatalogKind.series).total}',
            ),
            future: catalog.heroSlides(),
            onOpenCatalog: widget.onOpenCatalog,
          )
        else
          _EmptyHero(
            syncing: syncing,
            error: catalog.section(CatalogKind.movies).error ??
                catalog.section(CatalogKind.series).error,
            onRetry: _load,
          ),
        const SizedBox(height: 28),
        ContinueStrip(
          key: ValueKey('home:continue:${catalog.progressRevision}'),
          future: catalog.continueAll(),
        ),
        TitleRow(
          key: const ValueKey('home:movies:recent'),
          label: 'Filmes adicionados recentemente',
          future: catalog.recentTitles(CatalogKind.movies),
          onOpen: open,
          onSeeAll: widget.onOpenCatalog,
        ),
        TitleRow(
          key: const ValueKey('home:series:recent'),
          label: 'Séries adicionadas recentemente',
          future: catalog.recentTitles(CatalogKind.series),
          onOpen: open,
          onSeeAll: widget.onOpenCatalog,
        ),
      ],
      ),
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
    return Container(
      height: 220,
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            syncing ? 'Baixando filmes e séries…' : 'Filmes e séries',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            error ??
                (syncing
                    ? 'Isso pode levar um tempo na primeira vez.'
                    : 'O catálogo ainda não foi baixado ou o provedor não tem filmes/séries.'),
            style: TextStyle(
              color: error != null ? AppColors.danger : AppColors.textMuted,
            ),
          ),
          if (syncing)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
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
