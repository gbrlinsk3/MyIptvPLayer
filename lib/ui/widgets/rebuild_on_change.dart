import 'package:flutter/widgets.dart';

/// Quando [value] muda, manda reconstruir tudo o que está abaixo, inclusive
/// widgets `const` e o que lê valores estáticos (como o `AppShape`). Ninguém é
/// recriado: aba, rolagem, campos e diálogos abertos continuam como estavam.
class RebuildOnChange extends StatefulWidget {
  const RebuildOnChange({super.key, required this.value, required this.child});

  final Object value;
  final Widget child;

  @override
  State<RebuildOnChange> createState() => _RebuildOnChangeState();
}

class _RebuildOnChangeState extends State<RebuildOnChange> {
  @override
  void didUpdateWidget(RebuildOnChange old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value) return;
    // Depois do quadro: durante a construção não se percorre a árvore.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) (context as Element).visitChildren(_marcar);
    });
  }

  static void _marcar(Element element) {
    element.markNeedsBuild();
    element.visitChildren(_marcar);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
