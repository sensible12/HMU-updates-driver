import 'package:flutter/widgets.dart';

import '../features/shared/controllers/auth_controller.dart';
import '../features/shared/services/driver_repository.dart';
import '../features/shared/services/push_notification_service.dart';

class AppScope extends InheritedNotifier<AuthController> {
  const AppScope({
    super.key,
    required this.repository,
    required this.authController,
    required this.pushNotificationService,
    required super.child,
  }) : super(notifier: authController);

  final DriverRepository repository;
  final AuthController authController;
  final PushNotificationService pushNotificationService;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in widget tree.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    return repository != oldWidget.repository ||
        authController != oldWidget.authController ||
        pushNotificationService != oldWidget.pushNotificationService;
  }
}
