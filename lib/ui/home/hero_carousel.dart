import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../catalog/catalog_controller.dart';
import '../../core/layout_metrics.dart';
import '../../core/theme.dart';
import '../../data/catalog_models.dart';
import '../../state/app_scope.dart';
import '../catalog/play_actions.dart';
import '../catalog/poster_image.dart';
import '../catalog/title_details_panel.dart';
import '../widgets/more_button.dart';
import '../widgets/content_frame.dart';
import '../widgets/glass.dart';
import '../widgets/magnet.dart';
import '../widgets/morph_image_switcher.dart';
import '../widgets/shimmer.dart';
import '../widgets/shiny_text.dart';
import '../widgets/sling_arrow.dart';
import '../widgets/timed_switcher.dart';
import '../window/title_bar.dart';
import 'hero_art.dart';
import 'hero_buttons.dart';
import 'hero_scroll.dart';
import '../../core/format.dart';

/// Carrossel do Início, de borda a borda: banner grande à esquerda (até 5
/// slides; a cada 8 s passa ao próximo título do banner e, depois do último,
/// ao próximo banner) e, à direita, dois banners menores (clique para ir até
/// eles). Setas (só com mais de um banner) e pílulas também trocam de slide.
///
/// No topo da página o banner grande ocupa a janela inteira e os menores ficam
/// escondidos; a rolagem leva ao layout normal (ver [HeroStage]). No layout
/// normal a troca automática pausa com o mouse em cima; na tela cheia, onde o
/// mouse está quase sempre sobre o banner, pausa só enquanto ele se mexe.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({
    super.key,
    required this.future,
    required this.onOpenCatalog,
    required this.stage,
    required this.scroll,
    this.onScreen = true,
    this.onUnavailable,
  });

  final Future<List<HeroSlide>> future;
  final ValueChanged<CatalogKind> onOpenCatalog;

  /// Medidas e rolagem da transição entre a tela cheia e o layout normal.
  final HeroStage stage;
  final ScrollController scroll;

  /// O Início está à vista (aba aberta, sem busca nem outra tela por cima):
  /// só então a barra do topo é avisada de que está sobre o banner.
  final bool onScreen;

  /// Não há nenhum banner para mostrar.
  final VoidCallback? onUnavailable;

  /// Altura do banner: 440 como sempre; em telas altas (1440p) cresce
  /// (40 % da altura útil, até 640) e os banners da direita acompanham.
  static double heightFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Largura útil: janela menos o trilho, ou a largura fixa escolhida.
    var width = size.width - 68;
    final fixed = AppScope.read(context).catalogWidth;
    if (fixed != CatalogWidth.fill && fixed < width) width = fixed.toDouble();
    return HeroMetrics.height(size.height - _topBar, width: width);
  }

  /// Altura da barra do topo (ver `Shell`).
  static const double _topBar = 64;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel>
    with SingleTickerProviderStateMixin {
  static const _interval = Duration(seconds: 8);

  /// Trocas pedidas pelo usuário respondem rápido; a automática é lenta.
  static const _quick = Duration(milliseconds: 350);

  late final AnimationController _timer =
      AnimationController(
        vsync: this,
        duration: _interval,
        // Sem isto, "reduzir animações" encurtaria o intervalo para 5 %.
        animationBehavior: AnimationBehavior.preserve,
      )
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _advance();
        });

  int _slide = 0;
  final Map<int, int> _picked = {}; // slide -> título mostrado no banner grande
  int _count = 0;
  int _titleCount = 1; // títulos do slide atual
  bool _hover = false;
  Timer? _pointerRest; // tela cheia: o mouse se mexeu há pouco
  static const _pointerRestTime = Duration(seconds: 3);
  Timer? _scrollRest; // a página está rolando
  static const _scrollRestTime = Duration(milliseconds: 600);
  bool _expandedBefore = true;
  bool _hasSlides = false;
  List<HeroSlide>? _prefetched; // banners cujas imagens já foram pedidas
  bool _clicked = false; // a última troca veio de um clique

  /// Mouse sobre o banner grande (o título só brilha enquanto isso).
  final ValueNotifier<bool> _bigHover = ValueNotifier(false);

  /// Mais perto da tela cheia do que do layout normal.
  bool get _expanded =>
      widget.stage.progress(scrollOffsetOf(widget.scroll)) < 0.5;

  /// Rolando, nada troca: uma troca junto com a transição engasga.
  bool get _paused =>
      (_scrollRest?.isActive ?? false) ||
      (_expanded ? (_pointerRest?.isActive ?? false) : _hover);

  void _syncTimer() {
    if (_paused) {
      _timer.stop();
    } else if (!_timer.isAnimating && _count > 0) {
      _timer.forward();
    }
  }

  void _onPointerMove() {
    _pointerRest?.cancel();
    _pointerRest = Timer(_pointerRestTime, () {
      if (mounted) _syncTimer();
    });
    if (_expanded) _timer.stop();
  }

  void _onScroll() {
    _scrollRest?.cancel();
    _scrollRest = Timer(_scrollRestTime, () {
      if (mounted) _syncTimer();
    });
    _timer.stop();
    final expanded = _expanded;
    if (expanded == _expandedBefore) return;
    _expandedBefore = expanded;
    _syncTimer();
    _publishOverMedia();
  }

  /// Avisa a barra do topo se ela está sobre a imagem (texto claro). Fora do
  /// build: quem ouve são outros widgets.
  void _publishOverMedia() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WindowChrome.overMedia.value = widget.onScreen &&
          _hasSlides &&
          widget.stage.distance > 0 &&
          _expanded;
    });
  }

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(HeroCarousel old) {
    super.didUpdateWidget(old);
    if (old.scroll != widget.scroll) {
      old.scroll.removeListener(_onScroll);
      widget.scroll.addListener(_onScroll);
    }
    if (old.onScreen != widget.onScreen || old.stage != widget.stage) {
      _publishOverMedia();
    }
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_onScroll);
    _pointerRest?.cancel();
    _scrollRest?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WindowChrome.overMedia.value = false;
    });
    _bigHover.dispose();
    _timer.dispose();
    super.dispose();
  }

  /// Vai para o slide [i] (começando pelo primeiro título dele).
  void _go(int i, {bool clicked = true}) {
    if (_count == 0) return;
    final target = ((i % _count) + _count) % _count;
    setState(() {
      _clicked = clicked;
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
      setState(() {
        _clicked = false;
        _picked[_slide] = pick + 1;
      });
      _timer.forward(from: 0);
    } else {
      _go(_slide + 1, clicked: false);
    }
  }

  /// Pede de uma vez tudo o que o carrossel vai mostrar. Cada imagem carrega
  /// uma única vez (ver [HeroArt]); depois disso, a troca automática e a
  /// rolagem não carregam nada.
  void _prefetch(List<HeroSlide> slides) {
    if (identical(_prefetched, slides)) return;
    _prefetched = slides;
    unawaited(_loadArt(slides));
  }

  Future<void> _loadArt(List<HeroSlide> slides) async {
    final catalog = AppScope.read(context).catalog;
    // Primeiro o título de capa de cada banner, depois os demais.
    final shown = [
      for (final s in slides) (slide: s, title: s.titles.first),
      for (final s in slides)
        for (final t in s.titles.skip(1)) (slide: s, title: t),
    ];
    // O controller limita a 3 pedidos de detalhes simultâneos, nesta ordem.
    for (final e in shown) {
      unawaited(catalog.detailsOrNull(e.title.kind, e.title.id));
    }
    for (final e in shown) {
      final d = await catalog.detailsOrNull(e.title.kind, e.title.id);
      if (!mounted || !identical(_prefetched, slides)) return;
      await HeroArt.loadTitle(e.title, d);
    }
    // Por último, os que só aparecem no banner menor de baixo.
    if (slides.length < 2) return;
    for (final e in shown) {
      final other = await _bottomTitle(catalog, e.title, e.slide.resume);
      if (!mounted || !identical(_prefetched, slides)) return;
      if (other == null) continue;
      final d = await catalog.detailsOrNull(other.kind, other.id);
      if (!mounted || !identical(_prefetched, slides)) return;
      await HeroArt.loadTitle(other, d, full: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HeroSlide>>(
      future: widget.future,
      builder: (context, snap) {
        final slides = snap.data;
        final stage = widget.stage;
        final scroll = widget.scroll;
        if (slides == null && snap.connectionState != ConnectionState.done) {
          return HeroSkeleton(
            height: stage.height,
            stage: stage,
            scroll: scroll,
          );
        }
        if (slides == null || slides.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onUnavailable?.call();
          });
          return SizedBox(height: stage.extent);
        }
        _prefetch(slides);
        _count = slides.length;
        if (_slide >= _count) _slide = 0;
        if (!_timer.isAnimating && !_paused) _timer.forward();
        if (!_hasSlides) {
          _hasSlides = true;
          _expandedBefore = _expanded;
          _publishOverMedia();
        }

        final slide = slides[_slide];
        _titleCount = slide.titles.length;
        final pick = (_picked[_slide] ?? 0).clamp(0, slide.titles.length - 1);
        final title = slide.titles[pick];
        final quick = _clicked ? _quick : null;
        final hasSide = slides.length > 1;
        // Banner menor de cima: o slide atual + 2 (com só 2 slides, o outro).
        // O "próximo" é alcançado pela seta do banner grande.
        final topSlide = slides.length >= 3
            ? slides[(_slide + 2) % slides.length]
            : slides[(_slide + 1) % slides.length];
        final topIndex = slides.indexOf(topSlide);

        final big = MouseRegion(
          onEnter: (_) => _bigHover.value = true,
          onExit: (_) => _bigHover.value = false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // O fundo troca por conta própria ("derretendo" de uma imagem
              // para a outra); o texto só aparece e some.
              _HeroBackground(title: title, quick: quick),
              const _HeroShade(),
              HeroSafeArea(
                stage: stage,
                scroll: scroll,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TimedSwitcher(
                      duration: quick ?? const Duration(milliseconds: 750),
                      switchInCurve: Curves.easeInOutCubic,
                      switchOutCurve: Curves.easeInOutCubic,
                      transitionBuilder: (child, anim) =>
                          _SlideFade(opacity: anim, child: child),
                      child: _SlideView(
                        hover: _bigHover,
                        key: ValueKey('$_slide:${title.kind.key}:${title.id}'),
                        slide: slide,
                        title: title,
                        pick: pick,
                        bannerHeight: stage.height,
                        quick: quick,
                        onPick: (i) {
                          setState(() {
                            _clicked = true;
                            _picked[_slide] = i;
                          });
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
                          child: SlingArrowButton(
                            glassGroup: GlassGroups.bannerArrows,
                            left: true,
                            enabled: true,
                            onFire: () => _go(_slide - 1),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 16,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: SlingArrowButton(
                            glassGroup: GlassGroups.bannerArrows,
                            left: false,
                            enabled: true,
                            onFire: () => _go(_slide + 1),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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
        );

        return MouseRegion(
          onEnter: (_) {
            _hover = true;
            _syncTimer();
          },
          onHover: (_) => _onPointerMove(),
          onExit: (_) {
            _hover = false;
            _pointerRest?.cancel();
            _syncTimer();
          },
          child: HeroStageLayout(
            stage: stage,
            scroll: scroll,
            framed: ContentFrameScope.framedOf(context),
            main: big,
            sideTop: hasSide
                ? _SideBanner(
                    slide: topSlide,
                    slot: 0,
                    quick: quick,
                    onTap: () => _go(topIndex),
                  )
                : null,
            // De baixo: um título relacionado ao do banner grande; clicar abre
            // o card expandido dele.
            sideBottom: hasSide
                ? _RelatedSide(
                    title: title,
                    resume: slide.resume,
                    quick: quick,
                  )
                : null,
          ),
        );
      },
    );
  }
}

/// Esqueleto do Início enquanto os banners carregam: mesma altura e mesma
/// divisão do [HeroCarousel] (banner grande à esquerda e, em janela larga, dois
/// banners menores à direita), com barras de título, texto e botão no grande.
/// Com [stage], segue a mesma transição da tela cheia para o layout normal.
/// Também usado pelo Início enquanto o catálogo ainda está baixando.
class HeroSkeleton extends StatelessWidget {
  const HeroSkeleton({
    super.key,
    required this.height,
    this.stage,
    this.scroll,
  });

  final double height;
  final HeroStage? stage;
  final ScrollController? scroll;

  static const _bars = Padding(
    padding: EdgeInsets.fromLTRB(84, 28, 84, 56),
    child: Align(
      alignment: Alignment.bottomLeft,
      child: _SkeletonBars(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final framed = ContentFrameScope.framedOf(context);
    final stage = this.stage;
    final scroll = this.scroll;
    if (stage != null && scroll != null) {
      return Shimmer(
        child: HeroStageLayout(
          stage: stage,
          scroll: scroll,
          framed: framed,
          main: Stack(
            fit: StackFit.expand,
            children: [
              const SkeletonBox(radius: 0),
              HeroSafeArea(stage: stage, scroll: scroll, child: _bars),
            ],
          ),
          sideTop: const SkeletonBox(),
          sideBottom: const SkeletonBox(),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: Shimmer(
        child: LayoutBuilder(
          builder: (context, box) {
            final side = box.maxWidth >= 900;
            final sideWidth =
                (box.maxWidth * 0.30).clamp(240.0, HeroMetrics.sideMax(height));
            return ClipRRect(
              borderRadius: BorderRadius.circular(framed ? AppShape.r(22) : 0),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.only(
                        bottomRight: Radius.circular(AppShape.r(28)),
                        bottomLeft: Radius.circular(side ? 0 : AppShape.r(28)),
                      ),
                      child: const Stack(
                        fit: StackFit.expand,
                        children: [SkeletonBox(radius: 0), _bars],
                      ),
                    ),
                  ),
                  if (side) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: sideWidth,
                      child: const Column(
                        children: [
                          Expanded(child: SkeletonBox()),
                          SizedBox(height: 12),
                          Expanded(child: SkeletonBox()),
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
  }
}

class _SkeletonBars extends StatelessWidget {
  const _SkeletonBars();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FractionallySizedBox(
            widthFactor: 0.7,
            child: SkeletonBox(height: 40),
          ),
          const SizedBox(height: 14),
          FractionallySizedBox(
            widthFactor: 0.9,
            child: SkeletonBox(height: 12),
          ),
          const SizedBox(height: 8),
          FractionallySizedBox(
            widthFactor: 0.75,
            child: SkeletonBox(height: 12),
          ),
          const SizedBox(height: 22),
          SkeletonBox(width: 160, height: 40),
        ],
      ),
    );
  }
}

/// Seta de troca de slide (quadrado claro arredondado, como na referência).
/// Camadas escuras fixas sobre o fundo do banner grande (nos dois temas: o texto
/// branco precisa de contraste). Ficam fora da troca de slide para não piscar.
class _HeroShade extends StatelessWidget {
  const _HeroShade();

  static const _layers = [
    LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xE6000000), Color(0x99000000), Color(0x10000000)],
      stops: [0, 0.45, 1],
    ),
    LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x00000000), Color(0xAA000000)],
      stops: [0.5, 1],
    ),
    // No alto: segura a categoria e o "Ver catálogo" em imagem clara.
    LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x99000000), Color(0x00000000)],
      stops: [0, 0.24],
    ),
  ];

  @override
  Widget build(BuildContext context) => const BakedShade(_layers);
}

// Banners menores: escuro no alto (a categoria não tem fundo próprio) e
// embaixo, um pouco mais forte com o mouse em cima.
const _sideShade = [
  LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x8C000000), Color(0x33000000), Color(0xB0000000)],
    stops: [0, 0.32, 1],
  ),
];
const _sideShadeHover = [
  LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x8C000000), Color(0x33000000), Color(0xCC000000)],
    stops: [0, 0.32, 1],
  ),
];

/// Fundo do banner grande. A imagem horizontal do título troca com a transição
/// "derretendo" do [MorphImageSwitcher]: a nova imagem é baixada em segundo
/// plano (tenta a versão grande do TMDB e cai para o endereço original) e só
/// então entra; até lá a anterior continua. Título sem imagem horizontal usa o
/// [_Backdrop] de antes (pôster nítido sobre o pôster borrado). Mantém o zoom
/// lento; ao trocar de título o zoom volta ao início suavemente.
class _HeroBackground extends StatefulWidget {
  const _HeroBackground({required this.title, this.quick});

  final CatalogTitle title;

  /// Duração da troca feita por clique; nula na troca automática.
  final Duration? quick;

  @override
  State<_HeroBackground> createState() => _HeroBackgroundState();
}

class _HeroBackgroundState extends State<_HeroBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _zoom =
      AnimationController(vsync: this, duration: const Duration(seconds: 16));

  ImageProvider? _image;
  bool _semImagem = false; // o título atual não tem imagem horizontal
  // A imagem horizontal do título atual já carregou e pode aparecer. Enquanto
  // for falso, só o pôster desfocado do próprio título fica visível (nunca o
  // fundo de outro banner).
  bool _mostrar = false;

  /// A imagem horizontal já cobre tudo: a base desfocada deixa de ser
  /// desenhada (por baixo dela, só pesaria nas trocas).
  bool _coberto = false;
  int _carga = 0;
  int _voltaZoom = 0;

  @override
  void initState() {
    super.initState();
    _zoom.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  @override
  void didUpdateWidget(_HeroBackground old) {
    super.didUpdateWidget(old);
    if (old.title.kind != widget.title.kind || old.title.id != widget.title.id) {
      _carregar();
      final volta = ++_voltaZoom;
      _zoom
          .animateTo(
            0,
            duration: widget.quick ?? const Duration(milliseconds: 900),
            curve: Curves.easeInOut,
          )
          .whenComplete(() {
        if (mounted && volta == _voltaZoom) _zoom.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    final titulo = widget.title;
    final carga = ++_carga;
    final catalogo = AppScope.read(context).catalog;
    // Imagem já na memória: troca direto de uma para a outra. Se ainda não
    // chegou até o próximo quadro, a do título anterior sai da tela.
    var resolvido = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!resolvido && carga == _carga) _esconder();
    });

    final d = await catalogo.detailsOrNull(titulo.kind, titulo.id);
    if (!mounted || carga != _carga) return;
    final bd = d?.backdrop;
    ImageProvider? provider;
    if (bd != null && bd.isNotEmpty) {
      final urls = HeroArt.backdropUrls(bd);
      provider = HeroArt.ready(urls, HeroArt.backdrop);
      if (provider == null) {
        _esconder();
        provider = await HeroArt.load(urls, HeroArt.backdrop);
        if (!mounted || carga != _carga) return;
      }
    }
    resolvido = true;
    setState(() {
      if (provider == null) {
        _semImagem = true;
        _mostrar = false;
        _coberto = false;
      } else {
        _semImagem = false;
        _image = provider;
        _mostrar = true;
      }
    });
  }

  /// Tira da tela a imagem do título anterior, deixando o pôster do atual.
  void _esconder() {
    if (!mounted || !(_semImagem || _mostrar || _coberto)) return;
    setState(() {
      _semImagem = false;
      _mostrar = false;
      _coberto = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduzir = MediaQuery.disableAnimationsOf(context);
    final poster = widget.title.image;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _zoom,
        builder: (context, filho) => Transform.scale(
          scale: reduzir ? 1 : 1 + 0.08 * _zoom.value,
          child: filho,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF141312)),
            // Base: pôster desfocado do título atual (dissolve ao trocar).
            if (_coberto)
              const SizedBox.shrink()
            else
              TimedSwitcher(
                duration: reduzir
                    ? Duration.zero
                    : widget.quick ?? const Duration(milliseconds: 600),
                child: Stack(
                  key: ValueKey('${widget.title.kind.key}:${widget.title.id}'),
                  fit: StackFit.expand,
                  children: [
                    if (poster != null) HeroBlur(url: poster),
                    const ColoredBox(color: Color(0x55000000)),
                  ],
                ),
              ),
            // Imagem horizontal: só aparece quando a do título atual carregou.
            AnimatedOpacity(
              opacity: _mostrar ? 1 : 0,
              duration: reduzir
                  ? Duration.zero
                  : widget.quick ?? const Duration(milliseconds: 600),
              onEnd: () {
                if (_mostrar && !_coberto) setState(() => _coberto = true);
              },
              child: MorphImageSwitcher(
                image: _image,
                duration: widget.quick ?? const Duration(milliseconds: 1100),
              ),
            ),
            TimedSwitcher(
              duration: widget.quick ?? const Duration(milliseconds: 600),
              child: _semImagem
                  ? _Backdrop(
                      key: ValueKey('${widget.title.kind.key}:${widget.title.id}'),
                      title: widget.title,
                    )
                  : const SizedBox.expand(key: ValueKey('sem-fallback')),
            ),
          ],
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
  const _Backdrop({
    super.key,
    required this.title,
    this.full = true,
    this.posterAside,
  });

  final CatalogTitle title;

  /// Banners menores: o pôster da frente vai para a borda direita, e este
  /// aviso diz se ele está na tela (para o texto não passar por cima).
  final ValueNotifier<bool>? posterAside;

  static const double asideMargin = 14;
  static const double posterHeightFactor = 0.7;

  /// Título que passa no banner grande: usa a mesma imagem dele.
  final bool full;

  @override
  State<_Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<_Backdrop> {
  bool _failed = false;

  /// Imagem horizontal: se a versão do banner grande já está na memória, vale
  /// ela, sem carregar outra.
  Widget _wide(String url) {
    final big = HeroArt.backdropUrls(url);
    final full = widget.full || HeroArt.ready(big, HeroArt.backdrop) != null;
    return HeroImage(
      key: ValueKey(url),
      urls: full ? big : HeroArt.backdropUrls(url, full: false),
      width: full ? HeroArt.backdrop : HeroArt.small,
      onFailed: () {
        if (mounted) setState(() => _failed = true);
      },
    );
  }

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
        final aside = widget.posterAside;
        if (aside != null && aside.value != showPoster) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) aside.value = showPoster;
          });
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF141312)),
            if (poster != null)
              HeroBlur(
                url: poster,
                sigma: widget.full ? HeroArt.bigBlur : HeroArt.sideBlur,
              ),
            const ColoredBox(color: Color(0x55000000)),
            if (hasBackdrop) _wide(bd),
            if (poster != null)
              AnimatedOpacity(
                opacity: showPoster ? 1 : 0,
                duration: const Duration(milliseconds: 600),
                child: Padding(
                padding: EdgeInsets.only(
                  right: aside == null ? 0 : _Backdrop.asideMargin,
                ),
                child: Align(
                alignment: aside == null
                    ? const Alignment(0.55, -0.15)
                    : Alignment.centerRight,
                child: FractionallySizedBox(
                  heightFactor: _Backdrop.posterHeightFactor,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: AppShape.card,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x88000000),
                            blurRadius: 30,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: AppShape.card,
                        child: HeroImage(
                          urls: [tmdbSize(poster, 'w780')!],
                          width: HeroArt.front,
                          placeholder: ColoredBox(color: AppColors.hover),
                          fallback: PosterImage(url: null, name: title.name),
                        ),
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
    required this.hover,
    required this.slide,
    required this.title,
    required this.pick,
    required this.bannerHeight,
    required this.onPick,
    required this.onOpenCatalog,
    this.quick,
  });

  /// Altura do banner grande: define o tamanho dos três pôsteres.
  final double bannerHeight;

  /// Duração da entrada do texto quando a troca veio de um clique.
  final Duration? quick;

  /// Mouse sobre o banner grande (o título brilha enquanto isso).
  final ValueListenable<bool> hover;
  final HeroSlide slide;
  final CatalogTitle title;
  final int pick;
  final ValueChanged<int> onPick;
  final ValueChanged<CatalogKind> onOpenCatalog;

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
          ?formatRuntime(d?.durationLabel),
          if ((d?.rating ?? title.rating) != null)
            '★ ${(d?.rating ?? title.rating)!.toStringAsFixed(1)}',
        ].join('   ·   ');
        final plot = (d?.plot ?? title.plot)?.trim();
        final progress = slide.resume ? title.progress : null;

        return Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              // Em cima fica a faixa da categoria e do "Ver catálogo".
              padding: const EdgeInsets.fromLTRB(84, 64, 84, 56),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        // Texto entra subindo e aparecendo, um instante depois da imagem.
                        child: _SlideFade.part(context, TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration:
                              quick ?? const Duration(milliseconds: 1000),
                          curve: Interval(
                            quick == null ? 0.3 : 0.15,
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
                                  hover: hover,
                                  slide: slide,
                                  title: title,
                                  meta: meta,
                                  plot: plot,
                                  progress: progress,
                                ),
                              ),
                            ),
                          ),
                        )),
                      ),
                    ),
                  ),
                  if (slide.titles.length > 1)
                    Padding(
                      padding: EdgeInsets.only(
                        right: HeroMetrics.thumbShift(bannerHeight),
                      ),
                      child: _SlideFade.part(
                        context,
                        _Thumbs(
                          titles: slide.titles,
                          selected: pick,
                          scale: HeroMetrics.thumbScale(bannerHeight),
                          onPick: onPick,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              left: 84,
              // Reserva o lado direito para o "Ver catálogo".
              right: 200,
              top: 24,
              child: _SlideFade.part(context, _Kicker(slide.kicker)),
            ),
            if (slide.opensCatalog)
              Positioned(
                right: 20,
                top: 14,
                child: _SlideFade.part(
                  context,
                  MoreButton(
                    label: 'Ver catálogo',
                    icon: Icons.grid_view_rounded,
                    color: Colors.white,
                    onPressed: () => onOpenCatalog(title.kind),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Esmaecimento da troca de texto. Vale por parte (categoria, texto,
/// pôsteres, botão), e não na área inteira: cada esmaecimento é desenhado à
/// parte, e um do tamanho da janela pesa na placa de vídeo.
class _SlideFade extends InheritedWidget {
  const _SlideFade({required this.opacity, required super.child});

  final Animation<double> opacity;

  static Widget part(BuildContext context, Widget child) {
    final fade = context.dependOnInheritedWidgetOfExactType<_SlideFade>();
    return fade == null
        ? child
        : FadeTransition(opacity: fade.opacity, child: child);
  }

  @override
  bool updateShouldNotify(_SlideFade old) => old.opacity != opacity;
}

/// Categoria do banner grande, no alto à esquerda.
class _Kicker extends StatelessWidget {
  const _Kicker(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 28, height: 2, color: AppColors.accentOnMedia),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
              color: Color.lerp(AppColors.accentOnMedia, Colors.white, 0.35),
              shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 6)],
            ),
          ),
        ),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({
    required this.hover,
    required this.slide,
    required this.title,
    required this.meta,
    required this.plot,
    required this.progress,
  });

  final ValueListenable<bool> hover;
  final HeroSlide slide;
  final CatalogTitle title;
  final String meta;
  final String? plot;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final hasPlot = plot != null && plot!.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // O brilho passa só com o mouse sobre o banner.
        ValueListenableBuilder<bool>(
          valueListenable: hover,
          builder: (context, sobre, _) => ShinyText(
            text: title.name.toUpperCase(),
            active: sobre,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            shineColor: Color.lerp(AppColors.accent, Colors.white, 0.45),
            style: AppFonts.title(54, color: Colors.white, spacing: 1),
          ),
        ),
        const SizedBox(height: 10),
        if (hasPlot) ...[
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
          const SizedBox(height: 32),
        ],
        Text(
          meta,
          style: const TextStyle(fontSize: 12.5, color: Color(0xCCFFFFFF)),
        ),
        if (slide.resume && title.continueLabel != null) ...[
          const SizedBox(height: 6),
          Text(
            title.continueLabel!,
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
              color: AppColors.accentOnMedia,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            HeroPrimaryButton(
              label: slide.resume ? 'Continuar' : 'Assistir',
              onTap: () => watchTitle(context, title),
            ),
            TextButton.icon(
              onPressed: () => showTitleDetails(context, title),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: AppShape.button,
                textStyle: AppFonts.title(15, spacing: 2),
              ),
              icon: const Icon(Icons.info_outline, size: 18),
              label: const Text('MAIS INFORMAÇÕES'),
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
  const _RelatedSide({
    required this.title,
    required this.resume,
    this.quick,
  });

  final CatalogTitle title;
  final Duration? quick;

  /// O banner grande é um "Continue de onde parou": o de baixo mostra **outro**
  /// título em andamento (diferente do grande) e clicar retoma a reprodução.
  final bool resume;

  @override
  Widget build(BuildContext context) {
    final catalog = AppScope.of(context).catalog;
    return FutureBuilder<CatalogTitle?>(
      future: _bottomTitle(catalog, title, resume),
      builder: (context, snap) {
        final rel = snap.data;
        if (rel == null) return const SizedBox.shrink();
        return _SideBanner(
          slide: HeroSlide(
            kicker: resume ? 'Continue de onde parou' : 'Relacionado',
            titles: [rel],
          ),
          slot: 1,
          full: false,
          quick: quick,
          hint: resume ? 'Clique aqui para assistir' : null,
          onTap: () => resume
              ? watchTitle(context, rel)
              : showTitleDetails(context, rel),
        );
      },
    );
  }
}

/// Título do banner menor de baixo: com [resume], outro em andamento; senão,
/// um relacionado ao do banner grande.
Future<CatalogTitle?> _bottomTitle(
  CatalogController catalog,
  CatalogTitle title,
  bool resume,
) =>
    resume
        ? catalog.continueAll().then<CatalogTitle?>((all) {
            for (final t in all) {
              if (t.kind != title.kind || t.id != title.id) return t;
            }
            return null;
          })
        : catalog.relatedTo(title);

/// Banner menor à direita: mostra um dos próximos slides; clicar vai até ele.
/// Quando o slide muda, o conteúdo desliza e some/aparece.
class _SideBanner extends StatefulWidget {
  const _SideBanner({
    required this.slide,
    required this.slot,
    required this.onTap,
    this.full = true,
    this.hint,
    this.quick,
  });

  final HeroSlide slide;
  final int slot;
  final VoidCallback onTap;

  /// Mostra um título que também passa no banner grande.
  final bool full;

  /// Duração da troca feita por clique; nula na troca automática.
  final Duration? quick;

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
        child: TimedSwitcher(
          duration: widget.quick ?? const Duration(milliseconds: 650),
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
          child: _SideContent(
            key: ValueKey('${slide.kicker}:${t.kind.key}:${t.id}'),
            slide: slide,
            hover: _hover,
            hint: widget.hint,
            full: widget.full,
          ),
        ),
      ),
    );
  }
}

/// Conteúdo de um banner menor. Cada um guarda se o próprio pôster está na
/// frente, porque na troca o que sai e o que entra aparecem juntos.
class _SideContent extends StatefulWidget {
  const _SideContent({
    super.key,
    required this.slide,
    required this.hover,
    this.hint,
    this.full = true,
  });

  final HeroSlide slide;
  final bool hover;
  final String? hint;
  final bool full;

  @override
  State<_SideContent> createState() => _SideContentState();
}

class _SideContentState extends State<_SideContent> {
  final ValueNotifier<bool> _posterAside = ValueNotifier(false);

  @override
  void dispose() {
    _posterAside.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slide;
    final t = slide.titles.first;
    final hover = widget.hover;
    return ClipRRect(
      borderRadius: BorderRadius.horizontal(
        left: Radius.circular(AppShape.r(22)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final posterWidth =
              box.maxHeight * _Backdrop.posterHeightFactor * 2 / 3;
          return Stack(
            fit: StackFit.expand,
            children: [
              AnimatedScale(
                scale: hover ? 1.06 : 1,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                child: _Backdrop(
                  title: t,
                  full: widget.full,
                  posterAside: _posterAside,
                ),
              ),
              BakedShade(hover ? _sideShadeHover : _sideShade),
              ValueListenableBuilder<bool>(
                valueListenable: _posterAside,
                builder: (context, aside, _) {
                  // Com o pôster à direita, o texto fica à esquerda dele.
                  final right = aside
                      ? posterWidth + _Backdrop.asideMargin + 12
                      : 16.0;
                  return Stack(
                    children: [
                      Positioned(
                        top: 14,
                        left: 16,
                        right: right,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            slide.kicker.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                              shadows: [
                                Shadow(color: Color(0xE6000000), blurRadius: 6),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: right,
                        bottom: 14,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShinyText(
                              text: t.name.toUpperCase(),
                              active: hover,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              shineColor: Color.lerp(
                                AppColors.accent,
                                Colors.white,
                                0.45,
                              ),
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
                                  slide.titles
                                      .skip(1)
                                      .map((e) => e.name)
                                      .join('  ·  '),
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
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Miniaturas dos títulos do banner (canto inferior direito).
class _Thumbs extends StatelessWidget {
  const _Thumbs({
    required this.titles,
    required this.selected,
    required this.scale,
    required this.onPick,
  });

  final List<CatalogTitle> titles;
  final int selected;
  final double scale;
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
            // Os pôsteres são levemente atraídos pelo ponteiro.
            child: Magnet(
              padding: 40,
              strength: 5,
              child: _Thumb(
                title: titles[i],
                selected: i == selected,
                scale: scale,
                onTap: () => onPick(i),
              ),
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
    required this.scale,
    required this.onTap,
  });

  final CatalogTitle title;
  final bool selected;
  final double scale;
  final VoidCallback onTap;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  bool _hover = false;

  Widget _art() {
    final url = widget.title.image;
    final named = PosterImage(url: null, name: widget.title.name);
    if (url == null || !url.startsWith('http')) return named;
    return HeroImage(
      urls: [url],
      width: HeroArt.thumb,
      placeholder: ColoredBox(color: AppColors.hover),
      fallback: named,
    );
  }

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
            borderRadius: AppShape.card,
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.4),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          textStyle: TextStyle(
            color: AppColors.onAccent,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: (sel ? 84 : 66) * widget.scale,
            height: (sel ? 124 : 98) * widget.scale,
            decoration: BoxDecoration(
              borderRadius: AppShape.card,
              border: Border.all(
                color: sel
                    ? AppColors.accentOnMedia
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
              borderRadius: AppShape.inset(2),
              child: _art(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Indicadores do carrossel: o atual é uma pílula que vai enchendo enquanto o
/// banner passa pelos seus títulos ([step] de [steps], 8 s cada).
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
                    borderRadius: AppShape.control,
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.centerLeft,
                  child: i == index
                      ? AnimatedBuilder(
                          animation: progress,
                          builder: (context, _) => FractionallySizedBox(
                            widthFactor:
                                ((step + progress.value) / steps).clamp(0.0, 1.0),
                            child: ColoredBox(color: AppColors.accentOnMedia),
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
