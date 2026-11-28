import 'package:flutter/widgets.dart';

import 'preview_look.dart';
import 'preview_screen.dart';

/// O que a comparação "Agora × Com esta opção" desenha.
enum CompareKind {
  /// Close das peças que a aparência muda (barra, botões, abas, pôsteres).
  pieces,

  /// Uma aba inteira (tamanho da interface e largura do catálogo).
  screen,

  /// Como um título baixado abre.
  openMode,

  /// Os banners do Início (sem opção para comparar).
  banners,

  /// Os destaques da TV ao vivo (sem opção para comparar).
  highlights,
}

/// A opção sob o mouse. Duas com o mesmo [id] são a mesma.
@immutable
class CompareSpec {
  const CompareSpec(
    this.id,
    this.title, {
    this.kind = CompareKind.pieces,
    this.change,
    this.openMode,
    this.tab = PreviewTab.catalog,
  });

  final String id;
  final String title;
  final CompareKind kind;

  /// A aparência com a opção aplicada, a partir da atual.
  final PreviewLook Function(PreviewLook now)? change;

  /// Para [CompareKind.openMode]: 'panel', 'expanded' ou 'player'.
  final String? openMode;

  /// Para [CompareKind.screen].
  final PreviewTab tab;

  @override
  bool operator ==(Object other) => other is CompareSpec && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Leva a opção sob o mouse dos ajustes até a prévia. Sem ele (janela
/// estreita, testes), os marcadores abaixo não fazem nada.
class PreviewHover extends InheritedWidget {
  const PreviewHover({super.key, required this.notifier, required super.child});

  final ValueNotifier<CompareSpec?> notifier;

  static ValueNotifier<CompareSpec?>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PreviewHover>()?.notifier;

  @override
  bool updateShouldNotify(PreviewHover old) => old.notifier != notifier;
}

/// Mouse sobre [child]: a prévia compara [spec]. Ao sair, a última comparação
/// continua à vista.
class HoverCompare extends StatelessWidget {
  const HoverCompare({super.key, required this.spec, required this.child});

  final CompareSpec spec;
  final Widget child;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => PreviewHover.maybeOf(context)?.value = spec,
        child: child,
      );
}

/// Um controle com várias opções lado a lado, de larguras iguais (o
/// `SegmentedButton`) ou contínuas (um `Slider`): [specAt] recebe a posição do
/// mouse, de 0 a 1, já descontadas as margens de [inset] em cada ponta.
class HoverRange extends StatelessWidget {
  const HoverRange({
    super.key,
    required this.specAt,
    required this.child,
    this.inset = 0,
  });

  /// Uma opção por segmento.
  HoverRange.segments({
    super.key,
    required List<CompareSpec> specs,
    required this.child,
  })  : inset = 0,
        specAt = ((f) =>
            specs[(f * specs.length).floor().clamp(0, specs.length - 1)]);

  final CompareSpec Function(double fraction) specAt;
  final double inset;
  final Widget child;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onHover: (event) {
          final hover = PreviewHover.maybeOf(context);
          final box = context.findRenderObject();
          if (hover == null || box is! RenderBox) return;
          final span = box.size.width - 2 * inset;
          if (span <= 0) return;
          hover.value =
              specAt(((event.localPosition.dx - inset) / span).clamp(0.0, 1.0));
        },
        child: child,
      );
}
