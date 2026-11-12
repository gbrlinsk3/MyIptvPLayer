import 'package:flutter/material.dart';

import '../../core/layout_metrics.dart';
import '../../state/app_scope.dart';

/// "Largura do catálogo": com uma largura fixa (1200/1440/1600 px lógicos) o
/// conteúdo das telas fica numa coluna centralizada; em "preenchido" usa a
/// largura toda. Aplicado uma vez em volta da área de páginas do `Shell`.
class ContentFrame extends StatelessWidget {
  const ContentFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fixed = AppScope.of(context).catalogWidth;
    return LayoutBuilder(
      builder: (context, box) {
        final framed = fixed != CatalogWidth.fill && fixed < box.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: framed ? fixed.toDouble() : box.maxWidth,
            height: box.maxHeight,
            child: ContentFrameScope(framed: framed, child: child),
          ),
        );
      },
    );
  }
}

/// Diz às telas se o conteúdo está numa coluna estreita (e não de borda a
/// borda): o banner do Início arredonda os cantos externos nesse caso.
class ContentFrameScope extends InheritedWidget {
  const ContentFrameScope({
    super.key,
    required this.framed,
    required super.child,
  });

  final bool framed;

  static bool framedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentFrameScope>()?.framed ??
      false;

  @override
  bool updateShouldNotify(ContentFrameScope old) => framed != old.framed;
}
