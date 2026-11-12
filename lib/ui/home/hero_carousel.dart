import 'package:flutter/material.dart';

import '../../catalog/catalog_controller.dart';
import '../../core/layout_metrics.dart';
import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../state/app_scope.dart';
import '../catalog/play_actions.dart';
import '../catalog/poster_image.dart';
import '../catalog/title_details_panel.dart';
import '../widgets/content_frame.dart';
import 'hero_buttons.dart';

/// Carrossel do Início, de borda a borda: banner grande à esquerda (até 5
/// slides; a cada 12 s passa ao próximo título do banner e, depois do último,
/// ao próximo banner; pausa com o mouse) e, à direita, dois banners menores
/// (clique para ir até eles). Setas (só com mais de um banner) e pílulas
/// também trocam de slide.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({
    super.key,
    required this.future,
    required this.onOpenCatalog,
  });

  final Future<List<HeroSlide>> future;
  final VoidCallback onOpenCatalog;

  /// Altura do banner: 440 como sempre; em telas altas (1440p) cresce
  /// (40 % da altura útil, até 640) e os banners da direita acompanham.
  static double heightFor(BuildContext context) =>
      HeroMetrics.height(MediaQuery.sizeOf(context).height - _topBar);

  /// Altura da barra do topo (ver `Shell`).
  static const double _topBar = 64;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel>
    with SingleTickerProviderStateMixin {
  static const _interval = Duration(seconds: 12);

  late final AnimationController _timer =
      AnimationController(vsync: this, duration: _interval)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _advance();
        });

  int _slide = 0;
  final Map<int, int> _picked = {}; // slide -> título mostrado no banner grande
  int _count = 0;
  int _titleCount = 1; // títulos do slide atual
  bool _hover = false;
  bool _prefetched = false;

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  /// Vai para o slide [i] (começando pelo primeiro título dele).
  void _go(int i) {
    if (_count == 0) return;
    final target = ((i % _count) + _count) % _count;
    setState(() {
      _slide = target;
      _picked.remove(target);
    });
    _timer.forward(from: 0);
  }

  /// Passo automático: próximo título do banner e, depois do último, o
  /// próximo banner.
  void _advance() {
    if (_count == 0) return;
    final pick = _picked[_slide] ?? 0;
    if (pick + 1 < _titleCount) {
      setState(() => _picked[_slide] = pick + 1);
      _timer.forward(from: 0);
    } else {
      _go(_slide + 1);
    }
  }

  /// Busca os detalhes (imagem de fundo) de todos os slides de uma vez, para a
  /// troca já encontrar a imagem pronta e a transição ficar suave.
  void _prefetch(List<HeroSlide> slides) {
    if (_prefetched) return;
    _prefetched = true;
    final catalog = AppScope.read(context).catalog;
    // O controller limita a 3 pedidos simultâneos; primeiro o título de capa de
    // cada slide, depois os demais títulos (a troca automática passa por todos).
    for (final s in slides) {
      catalog.detailsOrNull(s.titles.first.kind, s.titles.first.id);
    }
    for (final s in slides) {
      for (final t in s.titles.skip(1)) {
        catalog.detailsOrNull(t.kind, t.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HeroSlide>>(
      future: widget.future,
      builder: (context, snap) {
        final slides = snap.data;
        final height = HeroCarousel.heightFor(context);
        if (slides == null || slides.isEmpty) {
          return SizedBox(height: height);
        }
        _prefetch(slides);
        _count = slides.length;
        if (_slide >= _count) _slide = 0;
        if (!_timer.isAnimating && !_hover) _timer.forward();

        final slide = slides[_slide];
        _titleCount = slide.titles.length;
        final pick = (_picked[_slide] ?? 0).clamp(0, slide.titles.length - 1);
        final title = slide.titles[pick];

        return MouseRegion(
          onEnter: (_) {
            _hover = true;
            _timer.stop();
          },
          onExit: (_) {
            _hover = false;
            _timer.forward();
          },
          child: SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (context, box) {
                final side = slides.length > 1 && box.maxWidth >= 900;
                final sideWidth =
                    (box.maxWidth * 0.30).clamp(240.0, HeroMetrics.sideMax(height));
                // Banner menor de cima: o slide atual + 2 (com só 2 slides, o
                // outro). O "próximo" é alcançado pela seta do banner grande.
                final topSlide = slides.length >= 3
                    ? slides[(_slide + 2) % slides.length]
                    : slides[(_slide + 1) % slides.length];
                final topIndex = slides.indexOf(topSlide);
                // Com largura fixa (coluna centralizada) os cantos externos do
                // banner também arredondam; de borda a borda ficam retos.
                final framed = ContentFrameScope.framedOf(context);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(framed ? 22 : 0),
                  child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.only(
                          bottomRight: const Radius.circular(28),
                          bottomLeft: Radius.circular(side ? 0 : 28),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 750),
                              switchInCurve: Curves.easeInOutCubic,
                              switchOutCurve: Curves.easeInOutCubic,
                              transitionBuilder: (child, anim) => FadeTransition(
                                opacity: anim,
                                child: ScaleTransition(
                                  scale: Tween<double>(begin: 1.03, end: 1)
                                      .animate(anim),
                                  child: child,
                                ),
                              ),
                              child: _SlideView(
                                key: ValueKey(
                                  '$_slide:${title.kind.key}:${title.id}',
                                ),
                                slide: slide,
                                title: title,
                                pick: pick,
                                onPick: (i) {
                                  setState(() => _picked[_slide] = i);
                                  _timer.forward(from: 0);
                                },
                                onOpenCatalog: widget.onOpenCatalog,
                              ),
                            ),
                            if (slides.length > 1) ...[
                              Positioned(
                                left: 16,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: _Arrow(
                                    icon: Icons.chevron_left_rounded,
                                    onTap: () => _go(_slide - 1),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 16,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: _Arrow(
                                    icon: Icons.chevron_right_rounded,
                                    onTap: () => _go(_slide + 1),
                                  ),
                                ),
                              ),
                            ],
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 18,
                              child: Center(
                                child: _Dots(
                                  count: slides.length,
                                  index: _slide,
                                  step: pick,
                                  steps: slide.titles.length,
                                  progress: _timer,
                                  onTap: _go,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (side) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                        width: sideWidth,
                        child: Column(
                          children: [
                            Expanded(
                              child: _SideBanner(
                                slide: topSlide,
                                slot: 0,
                                onTap: () => _go(topIndex),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // De baixo: um título relacionado ao do banner
                            // grande; clicar abre o card expandido dele.
                            Expanded(child: _RelatedSide(title: title, resume: slide.resume)),
                          ],
                        ),
                      ),
                    ],
                  ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Seta de troca de slide (quadrado claro arredondado, como na referência).
class _Arrow extends StatefulWidget {
  const _Arrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_Arrow> createState() => _ArrowState();
}

class _ArrowState extends State<_Arrow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover ? 1.1 : 1,
          duration: const Duration(milliseconds: 140),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _hover ? 0.95 : 0.78),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(widget.icon, size: 28, color: const Color(0xFF1B1A19)),
          ),
        ),
      ),
    );
  }
}

/// Fundo do banner. Camadas: pôster borrado (aparece na hora, já temos o
/// pôster), imagem horizontal do servidor em alta resolução por cima (entra em
/// fade quando carrega; tenta a versão grande do TMDB e cai para o endereço
/// original) e, se não houver imagem horizontal, o pôster nítido na frente.
class _Backdrop extends StatefulWidget {
  const _Backdrop({required this.title, this.size = 'w1280', this.cache = 1920});

  final CatalogTitle title;
  final String size;
  final int cache;

  @override
  State<_Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<_Backdrop> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final catalog = AppScope.of(context).catalog;
    return FutureBuilder<TitleDetails?>(
      future: catalog.detailsOrNull(title.kind, title.id),
      builder: (context, snap) {
        final done = snap.connectionState == ConnectionState.done;
        final bd = snap.data?.backdrop;
        final hasBackdrop = bd != null && bd.isNotEmpty;
        final poster = title.image ?? snap.data?.poster;
        // Pôster nítido na frente até a imagem horizontal chegar (ou se não houver).
        final showPoster = poster != null && (!done || !hasBackdrop || _failed);
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF141312)),
            if (poster != null)
              SoftBlurBackdrop(url: poster),
            const ColoredBox(color: Color(0x55000000)),
            if (hasBackdrop)
              ChainImage(
                key: ValueKey(bd),
                urls: [
                  if (tmdbSize(bd, widget.size) != bd) tmdbSize(bd, widget.size)!,
                  bd,
                ],
                cacheWidth: widget.cache,
                onExhausted: () {
                  if (mounted) setState(() => _failed = true);
                },
              ),
            if (poster != null)
              AnimatedOpacity(
                opacity: showPoster ? 1 : 0,
                duration: const Duration(milliseconds: 600),
                child: Align(
                alignment: const Alignment(0.55, -0.15),
                child: FractionallySizedBox(
                  heightFactor: 0.7,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x88000000),
                            blurRadius: 30,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: PosterImage(
                          url: tmdbSize(poster, 'w780'),
                          name: title.name,
                          cacheWidth: 700,
                        ),
                      ),
                    ),
                  ),
                ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({
    super.key,
    required this.slide,
    required this.title,
    required this.pick,
    required this.onPick,
    required this.onOpenCatalog,
  });

  final HeroSlide slide;
  final CatalogTitle title;
  final int pick;
  final ValueChanged<int> onPick;
  final VoidCallback onOpenCatalog;

  @override
  Widget build(BuildContext context) {
    final catalog = AppScope.of(context).catalog;
    return FutureBuilder<TitleDetails?>(
      future: catalog.detailsOrNull(title.kind, title.id),
      builder: (context, snap) {
        final d = snap.data;
        final year = d?.year ?? title.year;
        final genre = d?.genre;
        final meta = [
          title.kind == CatalogKind.movies ? 'Filme' : 'Série',
          if (year != null && year.isNotEmpty) year,
          if (genre != null && genre.isNotEmpty) genre,
          if (d?.durationLabel != null && d!.durationLabel!.isNotEmpty)
            d.durationLabel!,
          if ((d?.rating ?? title.rating) != null)
            '★ ${(d?.rating ?? title.rating)!.toStringAsFixed(1)}',
        ].join('   ·   ');
        final plot = (d?.plot ?? title.plot)?.trim();
        final progress = slide.resume ? title.progress : null;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Zoom lento na imagem enquanto o slide está na tela.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 1.0, end: 1.08),
              duration: const Duration(seconds: 16),
              curve: Curves.linear,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              // RepaintBoundary: o zoom lento só move a imagem já pintada
              // (sem refazer o desfoque do pôster a cada quadro).
              child: RepaintBoundary(child: _Backdrop(title: title)),
            ),
            // Sempre escuro por cima da imagem, nos dois temas: texto branco legível.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xE6000000),
                    Color(0x99000000),
                    Color(0x10000000),
                  ],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xAA000000)],
                  stops: [0.5, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(84, 28, 84, 56),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        // Texto entra subindo e aparecendo, um instante depois da imagem.
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 1000),
                          curve: const Interval(
                            0.3,
                            1,
                            curve: Curves.easeOutCubic,
                          ),
                          builder: (context, t, child) => Opacity(
                            opacity: t,
                            child: Transform.translate(
                              offset: Offset(0, (1 - t) * 22),
                              child: child,
                            ),
                          ),
                          // Se o texto for mais alto que o banner (janela baixa,
                          // botões em duas linhas), reduz em vez de estourar.
                          child: LayoutBuilder(
                            builder: (context, box) => FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.bottomLeft,
                              child: SizedBox(
                                width: box.maxWidth,
                                child: _Info(
                                  slide: slide,
                                  title: title,
                                  meta: meta,
                                  plot: plot,
                                  progress: progress,
                                  onOpenCatalog: onOpenCatalog,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (slide.titles.length > 1)
                    _Thumbs(titles: slide.titles, selected: pick, onPick: onPick),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({
    required this.slide,
    required this.title,
    required this.meta,
    required this.plot,
    required this.progress,
    required this.onOpenCatalog,
  });

  final HeroSlide slide;
  final CatalogTitle title;
  final String meta;
  final String? plot;
  final double? progress;
  final VoidCallback onOpenCatalog;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 28, height: 2, color: AppColors.accent),
            const SizedBox(width: 10),
            Text(
              slide.kicker.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                color: Color.lerp(AppColors.accent, Colors.white, 0.35),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          title.name.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppFonts.title(54, color: Colors.white, spacing: 1),
        ),
        const SizedBox(height: 10),
        Text(
          meta,
          style: const TextStyle(fontSize: 12.5, color: Color(0xCCFFFFFF)),
        ),
        if (slide.resume && title.subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            title.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
        if (progress != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: 260,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: const Color(0x55FFFFFF),
              color: AppColors.accent,
            ),
          ),
        ],
        if (plot != null && plot!.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            plot!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Color(0xE6FFFFFF),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            HeroPrimaryButton(
              label: slide.resume ? 'Continuar' : 'Assistir',
              onTap: () => watchTitle(context, title),
            ),
            HeroGhostButton(
              label: 'Mais informações',
              icon: Icons.info_outline,
              onTap: () => showTitleDetails(context, title),
            ),
            if (slide.opensCatalog)
              HeroGhostButton(
                label: 'Ver catálogo',
                icon: Icons.grid_view_rounded,
                onTap: onOpenCatalog,
              ),
          ],
        ),
      ],
    );
  }
}

/// Banner menor de baixo: título da mesma categoria do que está no banner
/// grande. Sem relacionado disponível, fica vazio.
class _RelatedSide extends StatelessWidget {
  const _RelatedSide({required this.title, required this.resume});

  final CatalogTitle title;

  /// O banner grande é um "Continue de onde parou": o de baixo mostra **outro**
  /// título em andamento (diferente do grande) e clicar retoma a reprodução.
  final bool resume;

  @override
  Widget build(BuildContext context) {
    final catalog = AppScope.of(context).catalog;
    final Future<CatalogTitle?> future = resume
        ? catalog.continueAll().then<CatalogTitle?>((all) {
            for (final t in all) {
              if (t.kind != title.kind || t.id != title.id) return t;
            }
            return null;
          })
        : catalog.relatedTo(title);
    return FutureBuilder<CatalogTitle?>(
      future: future,
      builder: (context, snap) {
        final rel = snap.data;
        if (rel == null) return const SizedBox.shrink();
        return _SideBanner(
          slide: HeroSlide(
            kicker: resume ? 'Continue de onde parou' : 'Relacionado',
            titles: [rel],
          ),
          slot: 1,
          hint: resume ? 'Clique aqui para assistir' : null,
          onTap: () => resume
              ? watchTitle(context, rel)
              : showTitleDetails(context, rel),
        );
      },
    );
  }
}

/// Banner menor à direita: mostra um dos próximos slides; clicar vai até ele.
/// Quando o slide muda, o conteúdo desliza e some/aparece.
class _SideBanner extends StatefulWidget {
  const _SideBanner({
    required this.slide,
    required this.slot,
    required this.onTap,
    this.hint,
  });

  final HeroSlide slide;
  final int slot;
  final VoidCallback onTap;

  /// Texto pequeno embaixo do nome (no lugar dos nomes dos outros títulos).
  final String? hint;

  @override
  State<_SideBanner> createState() => _SideBannerState();
}

class _SideBannerState extends State<_SideBanner> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final slide = widget.slide;
    final t = slide.titles.first;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 650),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.12, 0),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey('${slide.kicker}:${t.kind.key}:${t.id}'),
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(22),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedScale(
                    scale: _hover ? 1.06 : 1,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    child: _Backdrop(title: t, size: 'w780', cache: 900),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0x33000000),
                          Color(_hover ? 0xCC000000 : 0xB0000000),
                        ],
                        stops: const [0.2, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        slide.kicker.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.title(
                            24,
                            color: Colors.white,
                            spacing: 0.8,
                          ),
                        ),
                        if (widget.hint != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              widget.hint!,
                              style: const TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 11,
                              ),
                            ),
                          )
                        else if (slide.titles.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              slide.titles.skip(1).map((e) => e.name).join('  ·  '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Miniaturas dos títulos do banner (canto inferior direito).
class _Thumbs extends StatelessWidget {
  const _Thumbs({
    required this.titles,
    required this.selected,
    required this.onPick,
  });

  final List<CatalogTitle> titles;
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < titles.length; i++)
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: _Thumb(
              title: titles[i],
              selected: i == selected,
              onTap: () => onPick(i),
            ),
          ),
      ],
    );
  }
}

class _Thumb extends StatefulWidget {
  const _Thumb({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final CatalogTitle title;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.title.name,
          preferBelow: false,
          verticalOffset: 14,
          waitDuration: const Duration(milliseconds: 250),
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.4),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          textStyle: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: sel ? 84 : 66,
            height: sel ? 124 : 98,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: sel
                    ? AppColors.accent
                    : Colors.white.withValues(alpha: _hover ? 0.8 : 0.3),
                width: sel ? 2.5 : 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: PosterImage(
                url: widget.title.image,
                name: widget.title.name,
                cacheWidth: 240,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Indicadores do carrossel: o atual é uma pílula que vai enchendo enquanto o
/// banner passa pelos seus títulos ([step] de [steps], 12 s cada).
class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.index,
    required this.step,
    required this.steps,
    required this.progress,
    required this.onTap,
  });

  final int count;
  final int index;
  final int step;
  final int steps;
  final Animation<double> progress;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  width: i == index ? 36 : 10,
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0x66FFFFFF),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.centerLeft,
                  child: i == index
                      ? AnimatedBuilder(
                          animation: progress,
                          builder: (context, _) => FractionallySizedBox(
                            widthFactor:
                                ((step + progress.value) / steps).clamp(0.0, 1.0),
                            child: ColoredBox(color: AppColors.accent),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
