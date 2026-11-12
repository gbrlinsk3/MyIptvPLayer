import 'package:flutter/widgets.dart';

import 'app_controller.dart';

/// Disponibiliza o [AppController] na árvore de widgets, sem pacotes externos.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Lê o controller e reconstrói o widget quando ele notificar mudanças.
  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope não encontrado na árvore de widgets.');
    return scope!.notifier!;
  }

  /// Lê o controller sem reconstruir (para callbacks e initState).
  static AppController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope não encontrado na árvore de widgets.');
    return scope!.notifier!;
  }
}
