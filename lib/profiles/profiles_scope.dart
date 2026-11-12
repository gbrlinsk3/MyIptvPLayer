import 'package:flutter/widgets.dart';

import 'profiles_controller.dart';

/// Disponibiliza o [ProfilesController] na árvore de widgets.
class ProfilesScope extends InheritedNotifier<ProfilesController> {
  const ProfilesScope({
    super.key,
    required ProfilesController controller,
    required super.child,
  }) : super(notifier: controller);

  static ProfilesController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ProfilesScope>();
    assert(scope != null, 'ProfilesScope não encontrado na árvore de widgets.');
    return scope!.notifier!;
  }

  static ProfilesController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ProfilesScope>();
    assert(scope != null, 'ProfilesScope não encontrado na árvore de widgets.');
    return scope!.notifier!;
  }
}
