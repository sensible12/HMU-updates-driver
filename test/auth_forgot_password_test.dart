import 'package:flutter_test/flutter_test.dart';
import 'package:hmu_driver/src/features/shared/controllers/auth_controller.dart';
import 'package:hmu_driver/src/features/shared/models/app_user_session.dart';
import 'package:hmu_driver/src/features/shared/models/driver_order.dart';
import 'package:hmu_driver/src/features/shared/models/driver_profile.dart';
import 'package:hmu_driver/src/features/shared/services/driver_repository.dart';

class MockDriverRepository implements DriverRepository {
  bool resetEmailCalled = false;
  String? lastResetEmail;
  bool shouldFailReset = false;
  bool shouldFailSignIn = false;

  @override
  AppUserSession? get currentUser => null;

  @override
  Stream<AppUserSession?> get authStateChanges => const Stream.empty();

  @override
  bool get isDemoMode => false;

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (shouldFailSignIn) {
      throw Exception(
        'Invalid email or password. Please check your credentials and try again.',
      );
    }
  }

  @override
  Future<void> register({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    if (shouldFailReset) {
      throw Exception('No account found with this email address.');
    }
    resetEmailCalled = true;
    lastResetEmail = email;
  }

  @override
  Future<List<DriverOrder>> fetchAcceptedOrders() async => [];

  @override
  Future<List<DriverOrder>> getCachedAcceptedOrders() async => [];

  @override
  Stream<void> watchAcceptedOrderChanges() => const Stream.empty();

  @override
  Stream<bool> watchOrderAlert(String orderId) => const Stream.empty();

  @override
  Future<DriverOrder> fetchOrderById(String orderId) async {
    throw UnimplementedError();
  }

  @override
  Future<DriverProfile> fetchProfile() async {
    throw UnimplementedError();
  }

  @override
  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
  }) async {}

  @override
  Future<void> updateOrderAlert({
    required String orderId,
    required bool alert,
  }) async {}

  @override
  Future<void> registerPushToken(String token) async {}

  @override
  Future<void> unregisterPushToken(String token) async {}
}

void main() {
  group('Auth and Forgot Password tests', () {
    late MockDriverRepository mockRepository;
    late AuthController authController;

    setUp(() {
      mockRepository = MockDriverRepository();
      authController = AuthController(mockRepository);
    });

    test('sendPasswordResetEmail forwards to repository', () async {
      await authController.sendPasswordResetEmail('driver@example.com');

      expect(mockRepository.resetEmailCalled, isTrue);
      expect(mockRepository.lastResetEmail, 'driver@example.com');
    });

    test('sendPasswordResetEmail propagates error message', () async {
      mockRepository.shouldFailReset = true;

      expect(
        () => authController.sendPasswordResetEmail('missing@example.com'),
        throwsA(
          predicate(
            (e) =>
                e is Exception &&
                e.toString().contains('No account found with this email address.'),
          ),
        ),
      );
    });

    test('signIn propagates friendly invalid credentials error', () async {
      mockRepository.shouldFailSignIn = true;

      expect(
        () => authController.signIn(
          email: 'driver@example.com',
          password: 'wrongpassword',
        ),
        throwsA(
          predicate(
            (e) =>
                e is Exception &&
                e.toString().contains(
                  'Invalid email or password. Please check your credentials and try again.',
                ),
          ),
        ),
      );
    });
  });
}
