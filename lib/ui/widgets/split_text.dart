import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'animated_content.dart';

/// Texto cujos caracteres entram um a um, com fade e subida, em ease-out
/// (inspirado no SplitText do React Bits).
///
/// O layout é o de um [Text] normal com o mesmo estilo: um [Text] invisível
/// reserva o espaço e, durante a animação, cada caractere é desenhado por cima
/// na posição que ele terá no texto final. Ao terminar, o [Text] real aparece e
/// nada mais é desenhado, então a largura e a altura nunca mudam.
///
/// Toca uma vez ao montar; se [playKey] mudar, toca de novo. Com
/// `MediaQuery.disableAnimations` ligado (ou [animate] falso) mostra o texto
/// final direto. A escada entre caracteres é limitada para que o efeito inteiro
/// não passe de ~1 s em textos longos.
///
/// Se o texto não cabe ([maxLines] excedido, com reticências), a entrada vira um
/// fade com subida do texto inteiro, para nunca desenhar caracteres cortados.
class SplitText extends StatefulWidget {
  const SplitText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
    this.delayPerChar = const Duration(milliseconds: 30),
    this.charDuration = const Duration(milliseconds: 450),
    this.rise = 0.4,
    this.animate = true,
    this.playKey,
    this.revealId,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;

  /// Atraso entre o início de um caractere e o do seguinte.
  final Duration delayPerChar;

  /// Duração da entrada de cada caractere.
  final Duration charDuration;

  /// Altura da subida, em múltiplos do tamanho da fonte.
  final double rise;

  final bool animate;

  /// Quando muda (comparado com `==`), a animação toca de novo.
  final Object? playKey;

  /// Dentro de um [RevealScope], a entrada toca só na primeira vez que este id
  /// aparece no escopo (títulos em listas que remontam ao rolar ou trocar de
  /// aba); depois o texto nasce pronto.
  final Object? revealId;

  /// Tempo máximo da "escada" entre o primeiro e o último caractere.
  static const _escadaMaxima = Duration(milliseconds: 900);

  @override
  State<SplitText> createState() => _SplitTextState();
}

class _SplitTextState extends State<SplitText> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this);
  final _cache = _LayoutCache();
  bool _semAnimacao = false;
  bool _inicializado = false;

  int get _n => widget.text.characters.length;

  Duration get _atraso {
    final n = _n;
    if (n <= 1) return Duration.zero;
    final maxPorChar = SplitText._escadaMaxima.inMicroseconds ~/ (n - 1);
    return Duration(microseconds: math.min(widget.delayPerChar.inMicroseconds, maxPorChar));
  }

  Duration get _total {
    final n = _n;
    return widget.charDuration + _atraso * math.max(0, n - 1);
  }

  void _tocar() {
    _ctl.stop();
    if (_semAnimacao || !widget.animate || widget.text.isEmpty) {
      _ctl.value = 1;
      return;
    }
    _ctl.duration = _total;
    _ctl.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sem = MediaQuery.disableAnimationsOf(context);
    if (!_inicializado) {
      _inicializado = true;
      _semAnimacao = sem;
      final escopo = RevealScope.maybeOf(context);
      final id = widget.revealId;
      final jaRevelado = escopo != null && id != null && escopo.jaRevelado(id);
      // Montado escondido (página pré-carregada): a entrada ainda não foi vista.
      if (escopo != null && id != null && TickerMode.valuesOf(context).enabled) {
        escopo.marcarRevelado(id);
      }
      if (jaRevelado) {
        _ctl.value = 1;
      } else {
        _tocar();
      }
    } else if (sem != _semAnimacao) {
      _semAnimacao = sem;
      if (sem) {
        _ctl.stop();
        _ctl.value = 1;
      }
    }
  }

  @override
  void didUpdateWidget(SplitText old) {
    super.didUpdateWidget(old);
    if (widget.playKey != old.playKey) {
      _tocar();
    } else if (widget.text != old.text && _ctl.isAnimating) {
      // Texto trocado no meio da entrada: reajusta a duração sem recomeçar.
      _ctl.duration = _total;
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final efetivo = base.merge(widget.style);
    final texto = Text(
      widget.text,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _ctl,
        builder: (context, _) {
          final pronto = _ctl.value >= 1;
          if (pronto) return texto;
          return Stack(
            children: [
              Opacity(opacity: 0, child: texto),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SplitPainter(
                      cache: _cache,
                      text: widget.text,
                      style: efetivo,
                      maxLines: widget.maxLines,
                      overflow: widget.overflow,
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                      locale: Localizations.maybeLocaleOf(context),
                      rise: widget.rise,
                      atrasoUs: _atraso.inMicroseconds,
                      charUs: math.max(1, widget.charDuration.inMicroseconds),
                      totalUs: math.max(1, _total.inMicroseconds),
                      value: _ctl.value,
                    ),
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

class _Glifo {
  _Glifo(this.painter, this.offset);
  final TextPainter? painter;
  final Offset offset;
}

/// Layout guardado entre quadros: só é refeito quando texto, estilo ou largura mudam.
class _LayoutCache {
  Object? _chave;
  TextPainter? inteiro;
  List<_Glifo> glifos = const [];
  bool estourou = false;

  void garantir({
    required String text,
    required TextStyle style,
    required int? maxLines,
    required TextOverflow overflow,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Locale? locale,
    required double largura,
  }) {
    final chave = Object.hash(text, style, maxLines, overflow, textDirection, textScaler, locale, largura);
    if (chave == _chave && inteiro != null) return;
    _chave = chave;
    inteiro?.dispose();
    for (final g in glifos) {
      g.painter?.dispose();
    }

    TextPainter novo(String t, {int? linhas, String? reticencias}) => TextPainter(
          text: TextSpan(text: t, style: style),
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
          maxLines: linhas,
          ellipsis: reticencias,
        );

    final limitado = novo(
      text,
      linhas: maxLines,
      reticencias: overflow == TextOverflow.ellipsis ? '…' : null,
    )..layout(maxWidth: largura);
    inteiro = limitado;

    final livre = novo(text)..layout(maxWidth: largura);
    estourou = limitado.didExceedMaxLines ||
        livre.computeLineMetrics().length > limitado.computeLineMetrics().length;
    livre.dispose();

    if (estourou) {
      glifos = const [];
      return;
    }

    final lista = <_Glifo>[];
    var i = 0;
    for (final c in text.characters) {
      final fim = i + c.length;
      if (c.trim().isNotEmpty) {
        final caixas = limitado.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: fim));
        if (caixas.isNotEmpty) {
          final p = novo(c)..layout();
          lista.add(_Glifo(p, Offset(caixas.first.left, caixas.first.top)));
        } else {
          lista.add(_Glifo(null, Offset.zero));
        }
      } else {
        lista.add(_Glifo(null, Offset.zero));
      }
      i = fim;
    }
    glifos = lista;
  }

  void dispose() {
    inteiro?.dispose();
    inteiro = null;
    for (final g in glifos) {
      g.painter?.dispose();
    }
    glifos = const [];
    _chave = null;
  }
}

class _SplitPainter extends CustomPainter {
  _SplitPainter({
    required this.cache,
    required this.text,
    required this.style,
    required this.maxLines,
    required this.overflow,
    required this.textDirection,
    required this.textScaler,
    required this.locale,
    required this.rise,
    required this.atrasoUs,
    required this.charUs,
    required this.totalUs,
    required this.value,
  });

  final _LayoutCache cache;
  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow overflow;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;
  final double rise;
  final int atrasoUs;
  final int charUs;
  final int totalUs;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    cache.garantir(
      text: text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      largura: size.width,
    );
    final subida = rise * (style.fontSize ?? 14);
    final decorrido = value * totalUs;

    if (cache.estourou) {
      final t = Curves.easeOutCubic.transform((decorrido / charUs).clamp(0.0, 1.0));
      _desenhar(canvas, cache.inteiro!, Offset(0, subida * (1 - t)), t, size);
      return;
    }

    for (var i = 0; i < cache.glifos.length; i++) {
      final g = cache.glifos[i];
      final painter = g.painter;
      if (painter == null) continue;
      final t = Curves.easeOutCubic.transform(((decorrido - i * atrasoUs) / charUs).clamp(0.0, 1.0));
      if (t <= 0) continue;
      _desenhar(canvas, painter, g.offset + Offset(0, subida * (1 - t)), t, size);
    }
  }

  void _desenhar(Canvas canvas, TextPainter p, Offset pos, double alfa, Size size) {
    if (alfa >= 1) {
      p.paint(canvas, pos);
      return;
    }
    canvas.saveLayer(
      (pos & Size(p.width + 2, p.height + 2)).inflate(2),
      Paint()..color = Color.fromRGBO(0, 0, 0, alfa),
    );
    p.paint(canvas, pos);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SplitPainter old) =>
      old.value != value ||
      old.text != text ||
      old.style != style ||
      old.rise != rise ||
      old.atrasoUs != atrasoUs ||
      old.charUs != charUs ||
      old.totalUs != totalUs;
}
