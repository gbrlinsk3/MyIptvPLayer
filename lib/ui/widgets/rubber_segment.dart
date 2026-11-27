import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import 'glass.dart';

/// Seletor segmentado com a mesma aparência do `SlidingTabs` (fundo da
/// superfície, borda, pílula `accentSoft`, texto de destaque no item ativo),
/// mas a pílula se move como uma borracha: ao trocar de item a borda dianteira
/// sai na frente e estica a pílula sobre origem e destino; a traseira a alcança
/// logo depois e, ao chegar, a pílula dá um leve achatamento vertical (~6%) e
/// volta ao normal.
///
/// Teclado: setas esquerda/direita mudam a seleção; o foco por teclado desenha
/// um contorno. Cada item é anunciado como botão (selecionado ou não).
///
/// Inspirado no RubberSegment do React Bits. Com `disableAnimations`, a pílula
/// vai direto ao destino.
class RubberSegment<T> extends StatefulWidget {
  const RubberSegment({
    super.key,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    this.iconOf,
  });

  final List<T> values;
  final String Function(T value) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Ícone opcional à esquerda do rótulo.
  final IconData? Function(T value)? iconOf;

  static const double _altura = 36;
  static const double _margem = 4;
  static const double _espaco = 4;
  static const double _iconeLado = 16;
  static const double _iconeFolga = 6;
  static const _estilo = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600);

  /// Quanto a pílula é achatada no fim do movimento (0,06 = 6%).
  static const double squash = 0.06;

  @override
  State<RubberSegment<T>> createState() => _RubberSegmentState<T>();
}

class _RubberSegmentState<T> extends State<RubberSegment<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1, // em repouso: a pílula já está sob o item escolhido
  );
  final FocusNode _focus = FocusNode(debugLabel: 'RubberSegment');

  // Extremidades da pílula (coordenadas do conteúdo): de onde saiu e para onde vai.
  double _fromL = 0, _fromR = 0, _toL = 0, _toR = 0;
  bool _rightward = true;
  bool _focused = false;

  /// O foco veio de um clique: o contorno de foco só aparece para o teclado.
  bool _byPointer = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) _byPointer = false;
    if (_focused != _focus.hasFocus) setState(() => _focused = _focus.hasFocus);
  }

  int _indexOf(T value) {
    final i = widget.values.indexOf(value);
    return i < 0 ? 0 : i;
  }

  // ---- medidas ----------------------------------------------------------

  List<double> _widths(RubberSegment<T> w) {
    final scaler = MediaQuery.textScalerOf(context);
    return [
      for (final v in w.values)
        _textWidth(w.labelOf(v), scaler) +
            (w.iconOf?.call(v) != null
                ? RubberSegment._iconeLado + RubberSegment._iconeFolga
                : 0) +
            32,
    ];
  }

  (double, double) _edgesOf(List<double> widths, int i) {
    var x = 0.0;
    for (var j = 0; j < i; j++) {
      x += widths[j] + RubberSegment._espaco;
    }
    return (x, x + widths[i]);
  }

  // ---- animação ---------------------------------------------------------

  /// Extremidades e achatamento da pílula agora.
  (double, double, double) _pose() {
    if (!_anim.isAnimating && _anim.value >= 1) {
      return (_toL, _toR, 1);
    }
    final t = _anim.value;
    // A borda dianteira anda primeiro; a traseira começa um pouco depois.
    final lead = Interval(0, 0.62, curve: Curves.easeOutCubic).transform(t);
    final trail = Interval(0.14, 1, curve: Curves.easeOutCubic).transform(t);
    final double l, r;
    if (_rightward) {
      r = _fromR + (_toR - _fromR) * lead;
      l = _fromL + (_toL - _fromL) * trail;
    } else {
      l = _fromL + (_toL - _fromL) * lead;
      r = _fromR + (_toR - _fromR) * trail;
    }
    // Achatamento no fim: a traseira alcançou, a pílula "assenta".
    final k = Interval(0.58, 1).transform(t);
    final sy = 1 - RubberSegment.squash * math.sin(math.pi * k);
    return (l, r, sy);
  }

  @override
  void didUpdateWidget(RubberSegment<T> old) {
    super.didUpdateWidget(old);
    final de = _indexOf(old.selected);
    final para = _indexOf(widget.selected);
    final widths = _widths(widget);
    final alvo = _edgesOf(widths, para.clamp(0, widths.length - 1));
    if (de == para && old.values.length == widget.values.length) {
      // Sem troca (rótulos podem ter mudado de largura): só acompanha.
      _toL = alvo.$1;
      _toR = alvo.$2;
      if (!_anim.isAnimating) {
        _fromL = _toL;
        _fromR = _toR;
      }
      return;
    }
    final (l, r, _) = _pose();
    _fromL = l;
    _fromR = r;
    _toL = alvo.$1;
    _toR = alvo.$2;
    _rightward = (_toL + _toR) >= (l + r);
    if (MediaQuery.disableAnimationsOf(context)) {
      _anim.value = 1;
    } else {
      _anim.forward(from: 0);
    }
  }

  // ---- interação --------------------------------------------------------

  void _select(int i) {
    if (i < 0 || i >= widget.values.length) return;
    if (i == _indexOf(widget.selected)) return;
    widget.onChanged(widget.values[i]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (_byPointer) setState(() => _byPointer = false);
    final atual = _indexOf(widget.selected);
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _select(atual - 1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      _select(atual + 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- construção -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final values = widget.values;
    if (values.isEmpty) return const SizedBox.shrink();

    final widths = _widths(widget);
    final indice = _indexOf(widget.selected).clamp(0, values.length - 1);
    final alvo = _edgesOf(widths, indice);
    if (!_anim.isAnimating) {
      // Em repouso a pílula está exatamente sob o item escolhido.
      _toL = alvo.$1;
      _toR = alvo.$2;
      _fromL = _toL;
      _fromR = _toR;
    } else {
      _toL = alvo.$1;
      _toR = alvo.$2;
    }

    final contorno = _focused &&
        !_byPointer &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: GlassSurface(
          radius: AppShape.control,
          edge: contorno ? AppColors.accent : null,
          edgeWidth: contorno ? 2 : 1,
          child: Padding(
            // + 1: o espaço da borda.
            padding: const EdgeInsets.all(RubberSegment._margem + 1),
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _anim,
                    builder: (context, _) {
                      final (l, r, sy) = _pose();
                      return Stack(
                        children: [
                          Positioned(
                            left: l,
                            width: math.max(0, r - l),
                            top: 0,
                            bottom: 0,
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.diagonal3Values(1, sy, 1),
                              child: DecoratedBox(
                                key: const ValueKey('rubber-pill'),
                                decoration: BoxDecoration(
                                  color: AppColors.accentSoft,
                                  borderRadius: AppShape.control,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < values.length; i++) ...[
                      if (i > 0) const SizedBox(width: RubberSegment._espaco),
                      _Item(
                        key: ValueKey('rubber-item-$i'),
                        label: widget.labelOf(values[i]),
                        icon: widget.iconOf?.call(values[i]),
                        width: widths[i],
                        active: i == indice,
                        onTap: () {
                          _byPointer = true;
                          _focus.requestFocus();
                          _select(i);
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ),
        ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    super.key,
    required this.label,
    required this.icon,
    required this.width,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final double width;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cor = active ? AppColors.accentInk : AppColors.textMuted;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: width,
            height: RubberSegment._altura,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: RubberSegment._iconeLado, color: cor),
                    const SizedBox(width: RubberSegment._iconeFolga),
                  ],
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: RubberSegment._estilo.copyWith(
                      fontFamily: AppFonts.body,
                      color: cor,
                    ),
                    child: Text(label),
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

/// Largura do texto com o estilo do segmento (sem o espaçamento interno).
double _textWidth(String texto, TextScaler escala) {
  final tp = TextPainter(
    text: TextSpan(
      text: texto,
      style: RubberSegment._estilo.copyWith(fontFamily: AppFonts.body),
    ),
    textDirection: TextDirection.ltr,
    textScaler: escala,
    maxLines: 1,
  )..layout();
  final largura = tp.width;
  tp.dispose();
  return largura;
}
