import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user_session.dart';
import '../models/driver_order.dart';
import '../models/driver_profile.dart';
import 'driver_repository.dart';

class DemoDriverRepository implements DriverRepository {
  DemoDriverRepository(this._preferences);

  final SharedPreferences _preferences;
  final StreamController<AppUserSession?> _authController =
      StreamController<AppUserSession?>.broadcast();

  static const _sessionKey = 'demo_driver_session';
  static const _profileKey = 'demo_driver_profile';

  final List<DriverOrder> _orders = [
    DriverOrder(
      id: '1001',
      status: 'accepted',
      alert: false,
      orderNumber: '227',
      restaurantId: 'r-1',
      restaurantName: 'Sunset Grill',
      customerId: 'c-1',
      customerName: 'Lebo Nkosi',
      customerPhone: '+26650000001',
      deliveryAddress: 'Maseru West, Main South 1 Road',
      deliveryLat: -29.3151,
      deliveryLng: 27.4869,
      allergyNote: 'No peanuts',
      createdAt: '2026-04-01T12:00:00Z',
      items: const [
        OrderItem(name: 'Chicken Wrap', qty: 2, notes: 'Extra sauce'),
        OrderItem(name: 'Still Water', qty: 1),
      ],
    ),
    DriverOrder(
      id: '1002',
      status: 'accepted',
      alert: false,
      orderNumber: '228',
      restaurantId: 'r-2',
      restaurantName: 'City Bowl',
      customerId: 'c-2',
      customerName: 'Mpho Khaketla',
      customerPhone: '+26650000002',
      deliveryAddress: 'Kingsway Avenue, Maseru Central',
      createdAt: '2026-04-01T12:20:00Z',
      items: const [
        OrderItem(name: 'Beef Rice Bowl', qty: 1, orderType: 'Large'),
        OrderItem(name: 'Fresh Juice', qty: 2),
      ],
    ),
  ];

  AppUserSession? _currentUser;

  @override
  AppUserSession? get currentUser {
    if (_currentUser != null) {
      return _currentUser;
    }

    final raw = _preferences.getString(_sessionKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final json = jsonDecode(raw) as Map<String, dynamic>;
    _currentUser = AppUserSession(
      id: json['id'] as String,
      email: json['email'] as String,
    );
    return _currentUser;
  }

  @override
  Stream<AppUserSession?> get authStateChanges => _authController.stream;

  @override
  bool get isDemoMode => true;

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));

    if (email.trim().isEmpty || password.isEmpty) {
      throw Exception('Please enter your email and password.');
    }

    if (email.trim().toLowerCase() == 'invalid@example.com' || password == 'wrong') {
      throw Exception('Invalid email or password. Please check your credentials and try again.');
    }

    _currentUser = AppUserSession(
      id: 'demo-driver',
      email: email.trim().toLowerCase(),
    );

    await _preferences.setString(
      _sessionKey,
      jsonEncode({'id': _currentUser!.id, 'email': _currentUser!.email}),
    );
    _authController.add(_currentUser);
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final trimmed = email.trim();
    if (trimmed.isEmpty || !trimmed.contains('@')) {
      throw Exception('Please enter a valid email address.');
    }
  }

  @override
  Future<void> register({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    if (name.trim().isEmpty || email.trim().isEmpty || password.isEmpty) {
      throw Exception('Please complete all required fields.');
    }

    if (password.length < 6) {
      throw Exception('Password must be at least 6 characters.');
    }

    await _preferences.setString(
      _profileKey,
      jsonEncode(
        DriverProfile(
          name: name.trim(),
          email: email.trim().toLowerCase(),
          phone: phone.trim().isEmpty ? null : phone.trim(),
        ).toJson(),
      ),
    );

    await signIn(email: email, password: password);
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    await _preferences.remove(_sessionKey);
    _authController.add(null);
  }

  @override
  Future<List<DriverOrder>> fetchAcceptedOrders() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return _orders
        .where((order) => order.status != 'delivered')
        .toList(growable: false);
  }

  @override
  Future<List<DriverOrder>> getCachedAcceptedOrders() async {
    return fetchAcceptedOrders();
  }

  @override
  Stream<void> watchAcceptedOrderChanges() {
    return const Stream<void>.empty();
  }

  @override
  Stream<bool> watchOrderAlert(String orderId) async* {
    final order = _orders.firstWhere(
      (entry) => entry.id == orderId,
      orElse: () => throw Exception('Order not found.'),
    );
    yield order.alert;
  }

  @override
  Future<DriverOrder> fetchOrderById(String orderId) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return _orders.firstWhere(
      (order) => order.id == orderId,
      orElse: () => throw Exception('Order not found.'),
    );
  }

  @override
  Future<DriverProfile> fetchProfile() async {
    final raw = _preferences.getString(_profileKey);
    if (raw != null && raw.isNotEmpty) {
      return DriverProfile.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    }

    final session = currentUser;
    return DriverProfile(
      id: session?.id ?? 'demo-driver-001',
      name: 'Demo Driver',
      email: session?.email ?? 'driver@example.com',
      phone: '+266 5000 0000',
      role: 'driver',
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
    );
  }

  @override
  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
  }) async {
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index == -1) {
      throw Exception('Order not found.');
    }

    _orders[index] = _orders[index].copyWith(
      status: status,
      driverId: currentUser?.id,
    );
  }

  @override
  Future<void> updateOrderAlert({
    required String orderId,
    required bool alert,
  }) async {
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index == -1) {
      throw Exception('Order not found.');
    }

    _orders[index] = _orders[index].copyWith(alert: alert);
  }

  @override
  Future<void> registerPushToken(String token) async {}

  @override
  Future<void> unregisterPushToken(String token) async {}
}
