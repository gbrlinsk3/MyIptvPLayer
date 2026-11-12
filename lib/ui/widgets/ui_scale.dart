import 'package:flutter/material.dart';

/// Ajuste "Tamanho da interface": monta o filho com `tamanho da janela / scale`
/// e amplia o resultado para ocupar a janela inteira.
///
/// Usa [FittedBox] (e não `Transform.scale` solto) porque o `RenderFittedBox`
/// ocupa a janela toda e converte as coordenadas no teste de acerto: toque,
/// hover, rolagem e campos de texto funcionam em toda a área. O [MediaQuery]
/// do filho informa o tamanho **lógico** (reduzido), então `LayoutBuilder` e
/// afins enxergam a janela como ela "é" depois de ampliada.
///
/// A estrutura da árvore não muda com [scale] (nem em 1.0): trocar o tamanho
/// em tempo de execução não recria o `Navigator` nem perde o estado das telas.
class UiScale extends StatelessWidget {
  const UiScale({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (!box.hasBoundedWidth || !box.hasBoundedHeight || scale <= 0) {
          return child;
        }
        final size = Size(box.maxWidth / scale, box.maxHeight / scale);
        return FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: size),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
