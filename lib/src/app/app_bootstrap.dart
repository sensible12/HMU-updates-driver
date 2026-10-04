import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_environment.dart';
import '../features/shared/controllers/auth_controller.dart';
import '../features/shared/services/demo_driver_repository.dart';
import '../features/shared/services/driver_repository.dart';
import '../features/shared/services/push_notification_service.dart';
import '../features/shared/services/supabase_driver_repository.dart';

class AppBootstrap {
  static Future<AppBootstrapData> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (_) {}

    final repository = await buildRepository();
    final authController = AuthController(repository);
    await authController.initialize();
    final pushNotificationService = PushNotificationService(
      repository: repository,
      authController: authController,
    );

    return AppBootstrapData(
      repository: repository,
      authController: authController,
      pushNotificationService: pushNotificationService,
    );
  }

  static Future<DriverRepository> buildRepository() async {
    final preferences = await SharedPreferences.getInstance();

    if (AppEnvironment.supabaseConfigured) {
      await Supabase.initialize(
        url: AppEnvironment.supabaseUrl,
        anonKey: AppEnvironment.supabaseAnonKey,
      );

      return SupabaseDriverRepository(
        client: Supabase.instance.client,
        preferences: preferences,
      );
    }

    return DemoDriverRepository(preferences);
  }
}

class AppBootstrapData {
  const AppBootstrapData({
    required this.repository,
    required this.authController,
    required this.pushNotificationService,
  });

  final DriverRepository repository;
  final AuthController authController;
  final PushNotificationService pushNotificationService;
}
