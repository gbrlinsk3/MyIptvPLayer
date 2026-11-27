import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Posição da página atual: pixels rolados, extensão máxima e altura da janela
/// visível. Vem das notificações de rolagem vertical da página.
class PosicaoRolagem {
  const PosicaoRolagem({
    required this.pixels,
    required this.maxScrollExtent,
    required this.viewportDimension,
  });

  final double pixels;
  final double maxScrollExtent;
  final double viewportDimension;

  /// Há o que rolar. Sem isso a faixa de traços fica oculta.
  bool get rolavel => maxScrollExtent > 0;

  @override
  bool operator ==(Object other) =>
      other is PosicaoRolagem &&
      other.pixels == pixels &&
      other.maxScrollExtent == maxScrollExtent &&
      other.viewportDimension == viewportDimension;

  @override
  int get hashCode => Object.hash(pixels, maxScrollExtent, viewportDimension);
}

/// Enviada pela página ativa com a posição da sua rolagem vertical principal.
/// `posicao` é `null` quando a página não tem rolagem vertical medida.
class PaginaRolagemNotification extends Notification {
  const PaginaRolagemNotification(this.posicao);

  final PosicaoRolagem? posicao;
}

/// Comprimento de um traço da faixa aberta: no trecho visível da página (entre
/// [ini] e [fim], frações de 0 a 1) ele forma uma onda, maior no meio e menor
/// nas duas pontas. [centro] é a posição do traço na mesma escala.
@visibleForTesting
double comprimentoDoTraco(double centro, double ini, double fim) {
  const base = EdgeScrollMarks._traco;
  if (centro <= ini || centro >= fim) return base;
  final onda = math.sin(math.pi * (centro - ini) / (fim - ini));
  return lerpDouble(base, EdgeScrollMarks._tracoNaJanela, onda)!;
}

/// Faixa de traços na borda direita da janela. Mostra a posição da página
/// (os traços da janela visível ficam maiores e em destaque) e permite rolar
/// clicando ou arrastando. Em repouso é compacta, uma coluna de pontos; com o
/// mouse em cima, arrastando ou enquanto a página rola, os pontos viram os
/// traços e o trecho em destaque desliza até a nova posição.
/// Quando a página não tem o que rolar, a faixa some com fade e desliza para fora da borda, sem bloquear cliques.
class EdgeScrollMarks extends StatefulWidget {
  const EdgeScrollMarks({
    super.key,
    required this.posicao,
    required this.aoRolar,
  });

  static const double largura = 14;
  static const double _margemV = 8;
  static const double _espaco = 10;
  static const double _altura = 2;
  static const double _traco = 8;
  static const double _tracoNaJanela = 14;
  static const double _ponto = 3;
  static const double _pontoNaJanela = 4;
  static const double _recuoPonto = 2;
  static const Duration _expansao = Duration(milliseconds: 180);
  static const Duration _duracao = Duration(milliseconds: 220);

  /// Quanto a faixa fica aberta depois que a rolagem para.
  static const Duration _repouso = Duration(milliseconds: 900);
  static const Curve _curva = Curves.easeOutCubic;
  static const Offset _deslocamentoOculto = Offset(0.6, 0);

  /// Posição da página, atualizada pela tela de conteúdo.
  final ValueListenable<PosicaoRolagem?> posicao;

  /// Pede rolagem da página em pixels (positivo desce).
  final ValueChanged<double> aoRolar;

  @override
  State<EdgeScrollMarks> createState() => _EdgeScrollMarksState();
}

class _EdgeScrollMarksState extends State<EdgeScrollMarks> {
  /// Última posição rolável. Os traços continuam desenhados com ela enquanto
  /// a faixa some, para o fade-out não mostrar uma faixa vazia.
  PosicaoRolagem? _ultima;

  bool _mouse = false;
  bool _arrastando = false;
  bool _rolando = false;
  Timer? _recolher;

  @override
  void initState() {
    super.initState();
    _ultima = _rolavelOuNulo(widget.posicao.value);
    widget.posicao.addListener(_aoMudar);
  }

  @override
  void didUpdateWidget(EdgeScrollMarks antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.posicao != widget.posicao) {
      antigo.posicao.removeListener(_aoMudar);
      widget.posicao.addListener(_aoMudar);
      _ultima = _rolavelOuNulo(widget.posicao.value);
    }
  }

  @override
  void dispose() {
    widget.posicao.removeListener(_aoMudar);
    _recolher?.cancel();
    super.dispose();
  }

  static PosicaoRolagem? _rolavelOuNulo(PosicaoRolagem? p) =>
      p != null && p.rolavel ? p : null;

  void _aoMudar() {
    final p = _rolavelOuNulo(widget.posicao.value);
    if (p == null) return;
    final antes = _ultima;
    _ultima = p;
    // Só a rolagem abre a faixa (roda, teclado, arraste); conteúdo que chega
    // ou janela redimensionada não.
    if (antes == null ||
        antes.viewportDimension != p.viewportDimension ||
        antes.pixels == p.pixels) {
      return;
    }
    _recolher?.cancel();
    _recolher = Timer(EdgeScrollMarks._repouso, () {
      if (mounted) setState(() => _rolando = false);
    });
    if (!_rolando) setState(() => _rolando = true);
  }

  static double _fracaoInicial(PosicaoRolagem? p) => p == null
      ? 0
      : p.pixels / (p.maxScrollExtent + p.viewportDimension);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PosicaoRolagem?>(
      valueListenable: widget.posicao,
      builder: (context, p, _) {
        final visivel = p != null && p.rolavel;
        final duracao = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : EdgeScrollMarks._duracao;
        final cinza = AppColors.textMuted.withAlpha(89);
        final destaque = AppColors.accent;
        return AnimatedSlide(
          duration: duracao,
          curve: EdgeScrollMarks._curva,
          offset: visivel ? Offset.zero : EdgeScrollMarks._deslocamentoOculto,
          child: AnimatedOpacity(
            duration: duracao,
            curve: EdgeScrollMarks._curva,
            opacity: visivel ? 1 : 0,
            child: IgnorePointer(
              ignoring: !visivel,
              child: ExcludeSemantics(
                excluding: !visivel,
                child: Semantics(
                  label: 'Posição de rolagem da página',
                  container: true,
                  child: Tooltip(
                    message: 'Rolar a página',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => setState(() => _mouse = true),
                      onExit: (_) => setState(() => _mouse = false),
                      child: SizedBox(
                        width: EdgeScrollMarks.largura,
                        height: double.infinity,
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final trilho =
                                box.maxHeight - 2 * EdgeScrollMarks._margemV;
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (d) {
                                final atual = widget.posicao.value;
                                if (atual == null || trilho <= 0) return;
                                final total = atual.maxScrollExtent +
                                    atual.viewportDimension;
                                final frac = ((d.localPosition.dy -
                                            EdgeScrollMarks._margemV) /
                                        trilho)
                                    .clamp(0.0, 1.0)
                                    .toDouble();
                                final alvo = (frac * total -
                                        atual.viewportDimension / 2)
                                    .clamp(0.0, atual.maxScrollExtent)
                                    .toDouble();
                                final delta = alvo - atual.pixels;
                                if (delta != 0) widget.aoRolar(delta);
                              },
                              onVerticalDragStart: (_) =>
                                  setState(() => _arrastando = true),
                              onVerticalDragEnd: (_) =>
                                  setState(() => _arrastando = false),
                              onVerticalDragCancel: () {
                                if (_arrastando) {
                                  setState(() => _arrastando = false);
                                }
                              },
                              onVerticalDragUpdate: (d) {
                                final atual = widget.posicao.value;
                                if (atual == null || trilho <= 0) return;
                                final total = atual.maxScrollExtent +
                                    atual.viewportDimension;
                                widget.aoRolar(d.delta.dy * total / trilho);
                              },
                              child: TweenAnimationBuilder<double>(
                                tween: Tween<double>(
                                  end: _mouse || _arrastando || _rolando
                                      ? 1
                                      : 0,
                                ),
                                duration: duracao == Duration.zero
                                    ? Duration.zero
                                    : EdgeScrollMarks._expansao,
                                curve: EdgeScrollMarks._curva,
                                builder: (context, aberta, _) =>
                                    TweenAnimationBuilder<double>(
                                  // Início do trecho visível: a roda salta, o
                                  // destaque desliza até lá.
                                  tween: Tween<double>(
                                    end: _fracaoInicial(_ultima),
                                  ),
                                  duration: duracao,
                                  curve: EdgeScrollMarks._curva,
                                  builder: (context, inicio, _) => CustomPaint(
                                    size: Size(
                                      EdgeScrollMarks.largura,
                                      box.maxHeight,
                                    ),
                                    painter: _TracosPainter(
                                      posicao: _ultima,
                                      inicio: inicio,
                                      cinza: cinza,
                                      destaque: destaque,
                                      aberta: aberta,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Desenha a coluna de traços a partir da última posição rolável. Refaz o
/// desenho só quando a posição ou as cores mudam.
class _TracosPainter extends CustomPainter {
  _TracosPainter({
    required this.posicao,
    required this.inicio,
    required this.cinza,
    required this.destaque,
    required this.aberta,
  }) : rounded = AppShape.rounded;

  final bool rounded;

  final PosicaoRolagem? posicao;

  /// Início do destaque, em fração do conteúdo (animado).
  final double inicio;
  final Color cinza;
  final Color destaque;

  /// 0 = pontos (compacta), 1 = traços.
  final double aberta;

  @override
  void paint(Canvas canvas, Size size) {
    final p = posicao;
    if (p == null || !p.rolavel) return;
    final trilho = size.height - 2 * EdgeScrollMarks._margemV;
    if (trilho < EdgeScrollMarks._altura) return;
    // Quantidade de traços acompanha a altura disponível.
    final n = ((trilho - EdgeScrollMarks._altura) / EdgeScrollMarks._espaco)
            .floor() +
        1;
    final total = p.maxScrollExtent + p.viewportDimension;
    final janelaFim = inicio + p.viewportDimension / total;
    final pCinza = Paint()..color = cinza;
    final pDestaque = Paint()..color = destaque;
    for (var i = 0; i < n; i++) {
      // Cada traço representa a fatia i/n do conteúdo da página.
      final naJanela = i / n < janelaFim && (i + 1) / n > inicio;
      final ponto = naJanela
          ? EdgeScrollMarks._pontoNaJanela
          : EdgeScrollMarks._ponto;
      final traco = comprimentoDoTraco((i + 0.5) / n, inicio, janelaFim);
      final largura = lerpDouble(ponto, traco, aberta)!;
      final altura = lerpDouble(ponto, EdgeScrollMarks._altura, aberta)!;
      final recuo = lerpDouble(EdgeScrollMarks._recuoPonto, 0, aberta)!;
      // Centro na mesma linha nas duas formas.
      final y =
          EdgeScrollMarks._margemV +
          i * EdgeScrollMarks._espaco +
          (EdgeScrollMarks._altura - altura) / 2;
      final rect = Rect.fromLTWH(
        size.width - recuo - largura,
        y,
        largura,
        altura,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(AppShape.r(altura / 2))),
        naJanela ? pDestaque : pCinza,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TracosPainter old) =>
      old.posicao != posicao ||
      old.inicio != inicio ||
      old.cinza != cinza ||
      old.destaque != destaque ||
      old.aberta != aberta ||
      old.rounded != rounded;
}
