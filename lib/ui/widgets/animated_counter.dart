import 'package:flutter/material.dart';

/// Número cujos dígitos rolam na vertical quando o valor muda: o dígito antigo
/// sai para cima e o novo entra por baixo. Visual do protótipo aprovado
/// (test/_previews/counter_preview_test.dart).
///
/// Não anima na primeira exibição, só quando [value] muda. Com
/// `MediaQuery.disableAnimations` ligado, troca o número sem animação. Os
/// dígitos usam números tabulares para não mudar de largura.
class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    required this.style,
    this.prefix = '',
    this.suffix = '',
    this.maxShown,
    this.semanticsLabel,
  });

  final int value;
  final TextStyle style;
  final String prefix;
  final String suffix;

  /// Acima deste valor mostra `maxShown+` (ex.: 99 vira "99+"). O "+" é fixo e não anima.
  final int? maxShown;

  /// Texto para leitores de tela (ex.: '5 de 12 assistidos'). Sem ele, usa
  /// prefixo, número e sufixo juntos.
  final String? semanticsLabel;

  static const _rolagem = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final limite = maxShown;
    final acima = limite != null && value > limite;
    final digitos = acima ? '$limite' : '$value';
    final animar = !MediaQuery.disableAnimationsOf(context);
    final estiloDigitos = style.copyWith(
      fontFeatures: [...?style.fontFeatures, const FontFeature.tabularFigures()],
    );

    return Semantics(
      label: semanticsLabel ?? '$prefix${acima ? '$limite+' : '$value'}$suffix',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prefix.isNotEmpty) Text(prefix, style: style),
          for (var i = 0; i < digitos.length; i++)
            _DigitoRolante(char: digitos[i], style: estiloDigitos, animar: animar),
          if (acima) Text('+', style: style),
          if (suffix.isNotEmpty) Text(suffix, style: style),
        ],
      ),
    );
  }
}

class _DigitoRolante extends StatelessWidget {
  const _DigitoRolante({
    required this.char,
    required this.style,
    required this.animar,
  });

  final String char;
  final TextStyle style;
  final bool animar;

  @override
  Widget build(BuildContext context) {
    if (!animar) return Text(char, style: style);

    // ClipRect por dígito: o corte acontece na caixa do próprio dígito.
    return ClipRect(
      child: AnimatedSwitcher(
        duration: AnimatedCounter._rolagem,
        switchInCurve: Curves.easeOutCubic,
        // AnimatedSwitcher inverte a curva de saída: easeInCubic faz o antigo
        // subir na mesma cadência com que o novo entra (easeOutCubic).
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          // Quem está entrando é o dígito atual; o que sai é o anterior.
          final entrando = child.key == ValueKey<String>(char);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, entrando ? 0.6 : -0.6),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: Text(char, key: ValueKey<String>(char), style: style),
      ),
    );
  }
}
