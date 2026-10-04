import '../models/app_user_session.dart';
import '../models/driver_order.dart';
import '../models/driver_profile.dart';
import 'dart:async';

abstract class DriverRepository {
  AppUserSession? get currentUser;

  Stream<AppUserSession?> get authStateChanges;

  bool get isDemoMode;

  Future<void> signIn({
    required String email,
    required String password,
  });

  Future<void> register({
    required String name,
    required String phone,
    required String email,
    required String password,
  });

  Future<void> signOut();

  Future<void> sendPasswordResetEmail(String email);

  Future<List<DriverOrder>> fetchAcceptedOrders();

  Future<List<DriverOrder>> getCachedAcceptedOrders();

  Stream<void> watchAcceptedOrderChanges();

  Stream<bool> watchOrderAlert(String orderId);

  Future<DriverOrder> fetchOrderById(String orderId);

  Future<DriverProfile> fetchProfile();

  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
  });

  Future<void> updateOrderAlert({
    required String orderId,
    required bool alert,
  });

  Future<void> registerPushToken(String token);

  Future<void> unregisterPushToken(String token);
}
