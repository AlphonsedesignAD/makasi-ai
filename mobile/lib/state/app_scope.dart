import 'package:flutter/widgets.dart';

import 'app_controller.dart';

/// Rend le contrôleur accessible partout, avec reconstruction automatique.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope introuvable dans le contexte.');
    return scope!.notifier!;
  }

  /// Accès sans écouter les changements (actions, callbacks).
  static AppController read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<AppScope>();
    final scope = element?.widget as AppScope?;
    assert(scope != null, 'AppScope introuvable dans le contexte.');
    return scope!.notifier!;
  }
}
