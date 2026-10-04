import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/orders/presentation/order_details_screen.dart';
import '../../features/orders/presentation/orders_home_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/shared/controllers/auth_controller.dart';
import '../../features/shared/presentation/splash_screen.dart';

class AppRouter {
  AppRouter(this.authController);

  final AuthController authController;

  late final GoRouter config = GoRouter(
    initialLocation: '/splash',
    refreshListenable: authController,
    redirect: (context, state) {
      final path = state.uri.path;
      final isAuthRoute =
          path == '/login' || path == '/register' || path == '/forgot-password';
      final isSplash = path == '/splash';

      if (authController.loading) {
        return isSplash ? null : '/splash';
      }

      if (!authController.isAuthenticated) {
        return isAuthRoute ? null : '/login';
      }

      if (isSplash || isAuthRoute) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const OrdersHomeScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/order/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return OrderDetailsScreen(orderId: id);
        },
      ),
    ],
  );
}
