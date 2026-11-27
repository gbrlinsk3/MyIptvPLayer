import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// [PopupMenuItem] cujo destaque (mouse, foco e clique) segue o formato da
/// interface: o do Flutter é sempre um retângulo de ponta a ponta. Em pílula o
/// item não encosta nas bordas; o texto fica no mesmo lugar nos dois formatos.
class AppPopupMenuItem<T> extends PopupMenuItem<T> {
  AppPopupMenuItem({
    super.key,
    super.value,
    super.enabled,
    super.height,
    required super.child,
  }) : super(
          padding: EdgeInsets.symmetric(horizontal: 16 - _margin),
        );

  static double get _margin => AppShape.rounded ? 8 : 0;

  @override
  PopupMenuItemState<T, PopupMenuItem<T>> createState() =>
      _AppPopupMenuItemState<T>();
}

class _AppPopupMenuItemState<T>
    extends PopupMenuItemState<T, PopupMenuItem<T>> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppPopupMenuItem._margin),
      // O destaque do clique é pintado neste Material, recortado na forma.
      child: Material(
        type: MaterialType.transparency,
        shape: AppShape.button,
        clipBehavior: Clip.antiAlias,
        child: super.build(context),
      ),
    );
  }
}
