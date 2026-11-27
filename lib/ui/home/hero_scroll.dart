import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/layout_metrics.dart';
import '../../core/theme.dart';
import '../widgets/smooth_scroll.dart';

/// Banner do Início guiado pela rolagem: no topo da página ele ocupa a janela
/// inteira; conforme a página rola ele encolhe até o lugar de sempre e os
/// banners menores entram pela direita. Tudo é função da posição da rolagem,
/// então o caminho de volta é o mesmo.

/// Medidas das duas pontas da transição.
@immutable
class HeroStage {
  const HeroStage({
    required this.size,
    required this.margins,
    required this.height,
  });

  /// Área visível da página: a janela inteira.
  final Size size;

  /// Onde fica o conteúdo no layout normal (barra lateral, barra do topo e,
  /// com largura fixa, as sobras dos lados).
  final EdgeInsets margins;

  /// Altura do banner no layout normal.
  final double height;

  /// Quanto é preciso rolar para ir da tela cheia ao layout normal. É a
  /// distância que a borda de baixo percorre, então ela acompanha o conteúdo
  /// que vem embaixo pixel a pixel. Zero em janela baixa demais.
  double get distance => math.max(0, size.height - margins.top - height);

  /// Altura reservada para o banner no começo da página.
  double get extent => distance + margins.top + height;

  double get normalWidth => math.max(0, size.width - margins.horizontal);

  /// 0 = janela inteira; 1 = layout normal.
  double progress(double offset) =>
      distance <= 0 ? 1 : (offset / distance).clamp(0.0, 1.0).toDouble();

  /// Retângulo do banner dentro do espaço reservado (que rola com a página).
  /// Durante a transição o topo é "segurado" na tela.
  Rect rect(double offset) {
    final p = progress(offset);
    final pin = offset.clamp(0.0, distance).toDouble();
    return Rect.fromLTRB(
      margins.left * p,
      pin + margins.top * p,
      size.width - margins.right * p,
      extent,
    );
  }

  /// Folga para o texto e os botões não ficarem atrás das barras enquanto o
  /// banner passa por baixo delas.
  EdgeInsets safeArea(double p) => EdgeInsets.fromLTRB(
        margins.left * (1 - p),
        margins.top * (1 - p),
        margins.right * (1 - p),
        0,
      );

  @override
  bool operator ==(Object other) =>
      other is HeroStage &&
      other.size == size &&
      other.margins == margins &&
      other.height == height;

  @override
  int get hashCode => Object.hash(size, margins, height);
}

/// Posição da rolagem (0 antes de a página existir).
double scrollOffsetOf(ScrollController c) =>
    c.positions.length == 1 && c.position.hasPixels ? c.position.pixels : 0;

/// Quanto da transição basta andar para ela se completar no mesmo sentido.
/// Baixo de propósito: um único toque da roda já passa disso.
const double heroSnapCommit = 0.15;

/// Em janela muito alta o percurso é longo e 15 % passariam de um toque da
/// roda (100 px); aí vale este limite em pixels.
const double heroSnapCommitPixels = 80;

/// Para onde completar quando a rolagem para no meio da transição; `null` se
/// já está numa das pontas ou fora dela. [direction] > 0 = descendo.
double? heroSnapTarget(double pixels, double zone, double direction) {
  if (zone <= 0 || pixels <= 0.5 || pixels >= zone - 0.5) return null;
  final commit = math.min(heroSnapCommit * zone, heroSnapCommitPixels);
  if (direction >= 0) return pixels >= commit ? zone : 0;
  return pixels <= zone - commit ? 0 : zone;
}

/// Rapidez da mola quando o toque da roda já completa a transição: o percurso é
/// bem maior que um dente da roda, então vai um pouco mais devagar.
const double heroSnapOmega = 14;

/// Rolagem do Início: a mesma roda suave das outras páginas
/// ([SmoothScrollController]) e, no trecho da transição (0 até [zone]), parar no
/// meio completa o movimento.
class HeroScrollController extends SmoothScrollController {
  HeroScrollController({super.holding}) : super(keepScrollOffset: false);

  double zone = 0;

  /// "Reduzir animações": sem suavização, a transição troca de uma vez.
  bool reduceMotion = false;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) =>
      _HeroScrollPosition(
        owner: this,
        physics: physics,
        context: context,
        oldPosition: oldPosition,
      );
}

class _HeroScrollPosition extends SmoothScrollPosition {
  _HeroScrollPosition({
    required this.owner,
    required super.physics,
    required super.context,
    super.oldPosition,
  }) : super(keepScrollOffset: false, holding: owner.holding) {
    isScrollingNotifier.addListener(_onActivity);
    owner.holding?.addListener(_onActivity);
    addListener(_trackDirection);
  }

  /// Espera depois de a rolagem parar antes de completar a transição.
  static const Duration _settleDelay = Duration(milliseconds: 60);

  final HeroScrollController owner;

  /// Até onde a roda pediu para ir no movimento em curso, antes de o encaixe
  /// mudar o destino: os giros seguintes somam a isto.
  double? _asked;
  double _direction = 1;
  double? _last;
  Timer? _settle;

  void _trackDirection() {
    if (!hasPixels) return;
    final last = _last;
    if (last != null && pixels != last) _direction = pixels - last;
    _last = pixels;
  }

  @override
  void pointerScroll(double delta) {
    final zone = owner.zone;
    if (delta == 0 || zone <= 0) {
      super.pointerScroll(delta);
      return;
    }
    final from = glideTarget == null ? pixels : (_asked ?? glideTarget!);
    var to =
        (from + delta).clamp(minScrollExtent, maxScrollExtent).toDouble();
    _asked = to;
    final inZone = pixels < zone || to < zone;
    if (owner.reduceMotion) {
      if (inZone) {
        jumpTo(delta > 0 ? math.max(zone, to) : (to >= zone ? to : 0));
      } else {
        jumpTo(to);
      }
      return;
    }
    // Para o encaixe, o que vale é o sentido do pedido.
    _direction = delta;
    if (directScroll) {
      super.pointerScroll(delta);
      return;
    }
    // Se este giro vai terminar em encaixe, já mira a ponta: um movimento só,
    // sem parar no meio para depois continuar.
    var omega = wheelScrollOmega;
    if (inZone) {
      final end = heroSnapTarget(to, zone, delta);
      if (end != null && end <= maxScrollExtent && (end - pixels) * delta > 0) {
        to = end;
        omega = heroSnapOmega;
      }
    }
    glideTo(to, omega: omega);
  }

  void _onActivity() {
    _settle?.cancel();
    if (isScrollingNotifier.value) return;
    if (owner.holding?.value ?? false) return;
    _settle = Timer(_settleDelay, _snap);
  }

  void _snap() {
    if (!hasPixels || isScrollingNotifier.value) return;
    final end = heroSnapTarget(pixels, owner.zone, _direction);
    if (end == null || end > maxScrollExtent) return;
    if (owner.reduceMotion) {
      jumpTo(end);
      return;
    }
    glideTo(end, omega: heroSnapOmega);
  }

  @override
  void dispose() {
    _settle?.cancel();
    owner.holding?.removeListener(_onActivity);
    isScrollingNotifier.removeListener(_onActivity);
    super.dispose();
  }
}

/// Recorte da página: na tela cheia nada é cortado; no layout normal o
/// conteúdo fica na mesma área de sempre (não passa por trás das barras).
class HeroViewportClipper extends CustomClipper<Rect> {
  HeroViewportClipper(this.stage, this.scroll) : super(reclip: scroll);

  final HeroStage stage;
  final ScrollController scroll;

  @override
  Rect getClip(Size size) {
    final p = stage.progress(scrollOffsetOf(scroll));
    return Rect.fromLTRB(
      stage.margins.left * p,
      stage.margins.top * p,
      size.width - stage.margins.right * p,
      size.height,
    );
  }

  @override
  bool shouldReclip(HeroViewportClipper old) =>
      old.stage != stage || old.scroll != scroll;
}

/// Põe o banner grande e os dois menores no lugar a cada quadro da rolagem.
/// Só posição, tamanho e opacidade mudam: [main], [sideTop] e [sideBottom] são
/// as mesmas instâncias, então não são reconstruídas durante o movimento.
class HeroStageLayout extends StatelessWidget {
  const HeroStageLayout({
    super.key,
    required this.stage,
    required this.scroll,
    required this.framed,
    required this.main,
    this.sideTop,
    this.sideBottom,
  });

  final HeroStage stage;
  final ScrollController scroll;

  /// Coluna de largura fixa: no layout normal os cantos externos arredondam.
  final bool framed;
  final Widget main;

  /// Nulos quando não há banners menores.
  final Widget? sideTop;
  final Widget? sideBottom;

  static const double gap = 12;

  /// Coreografia: o banner grande conduz; os menores entram empurrados pela
  /// borda dele, o de cima antes do de baixo.
  static const _topReveal = Interval(0.04, 0.65, curve: Curves.easeOut);
  static const _bottomReveal = Interval(0.2, 0.9, curve: Curves.easeOut);

  static Widget _reveal(double t, Widget child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(32 * (1 - t), 0),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final top = sideTop;
    final bottom = sideBottom;
    final side = top != null && bottom != null && stage.normalWidth >= 900;
    final sideWidth = (stage.normalWidth * 0.30)
        .clamp(240.0, HeroMetrics.sideMax(stage.height))
        .toDouble();

    return SizedBox(
      height: stage.extent,
      child: AnimatedBuilder(
        animation: scroll,
        builder: (context, _) {
          final offset = scrollOffsetOf(scroll);
          final p = stage.progress(offset);
          final rect = stage.rect(offset);
          final mainWidth =
              side ? rect.width - p * (sideWidth + gap) : rect.width;
          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    framed ? AppShape.r(22) * p : 0,
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: mainWidth,
                        child: ClipRRect(
                          borderRadius: BorderRadius.only(
                            bottomRight: Radius.circular(AppShape.r(28) * p),
                            bottomLeft: Radius.circular(
                              side ? 0 : AppShape.r(28) * p,
                            ),
                          ),
                          child: main,
                        ),
                      ),
                      if (side)
                        Positioned(
                          left: mainWidth + gap,
                          top: 0,
                          bottom: 0,
                          width: sideWidth,
                          child: Column(
                            children: [
                              Expanded(
                                child: _reveal(_topReveal.transform(p), top),
                              ),
                              const SizedBox(height: gap),
                              Expanded(
                                child: _reveal(
                                  _bottomReveal.transform(p),
                                  bottom,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Afasta o texto e os controles das barras enquanto o banner está por baixo
/// delas.
class HeroSafeArea extends StatelessWidget {
  const HeroSafeArea({
    super.key,
    required this.stage,
    required this.scroll,
    required this.child,
  });

  final HeroStage stage;
  final ScrollController scroll;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scroll,
      child: child,
      builder: (context, child) => Padding(
        padding: stage.safeArea(stage.progress(scrollOffsetOf(scroll))),
        child: child,
      ),
    );
  }
}
