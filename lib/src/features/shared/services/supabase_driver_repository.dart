import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_session.dart';
import '../models/driver_order.dart';
import '../models/driver_profile.dart';
import 'driver_repository.dart';

class SupabaseDriverRepository implements DriverRepository {
  SupabaseDriverRepository({
    required SupabaseClient client,
    required SharedPreferences preferences,
  }) : _client = client,
       _preferences = preferences;

  final SupabaseClient _client;
  final SharedPreferences _preferences;

  static const _profileCachePrefix = 'driver_profile:';
  static const _acceptedOrdersCachePrefix = 'accepted_orders:';

  @override
  AppUserSession? get currentUser {
    final user = _client.auth.currentUser;
    if (user == null) {
      return null;
    }

    return AppUserSession(id: user.id, email: user.email ?? '');
  }

  @override
  Stream<AppUserSession?> get authStateChanges {
    return _client.auth.onAuthStateChange.map((data) {
      final user = data.session?.user;
      if (user == null) {
        return null;
      }
      return AppUserSession(id: user.id, email: user.email ?? '');
    });
  }

  @override
  bool get isDemoMode => false;

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      if (response.user == null) {
        throw Exception(
          'Invalid email or password. Please check your credentials and try again.',
        );
      }

      await _syncCurrentDevicePushTokenIfAvailable();
    } on AuthException catch (authError) {
      final message = authError.message.toLowerCase();
      if (message.contains('invalid login credentials') ||
          message.contains('invalid credential') ||
          message.contains('invalid grant')) {
        throw Exception(
          'Invalid email or password. Please check your credentials and try again.',
        );
      } else if (message.contains('email not confirmed')) {
        throw Exception(
          'Your email has not been confirmed yet. Please check your inbox for the confirmation link.',
        );
      } else if (message.contains('user not found')) {
        throw Exception(
          'No account found with this email address. Please check your email or create an account.',
        );
      } else if (message.contains('rate limit') ||
          message.contains('too many requests')) {
        throw Exception(
          'Too many login attempts. Please wait a moment before trying again.',
        );
      }
      throw Exception(authError.message);
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception(
        'An unexpected error occurred during sign in. Please try again.',
      );
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty || !trimmed.contains('@')) {
      throw Exception('Please enter a valid email address.');
    }

    try {
      await _client.auth.resetPasswordForEmail(trimmed);
    } on AuthException catch (authError) {
      final message = authError.message.toLowerCase();
      if (message.contains('user not found')) {
        throw Exception('No account found with this email address.');
      } else if (message.contains('rate limit') ||
          message.contains('too many requests')) {
        throw Exception(
          'Too many reset requests. Please wait a moment before trying again.',
        );
      }
      throw Exception(authError.message);
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Failed to send password reset email. Please try again.');
    }
  }

  @override
  Future<void> register({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    final trimmedName = name.trim();
    final trimmedEmail = email.trim().toLowerCase();
    final trimmedPhone = phone.trim();

    final response = await _client.auth.signUp(
      email: trimmedEmail,
      password: password,
    );

    final userId = response.user?.id;
    if (userId == null) {
      throw Exception('Check your email to activate your account.');
    }

    await _client.from('users').upsert({
      'id': userId,
      'email': trimmedEmail,
      'name': trimmedName,
      'phone': trimmedPhone.isEmpty ? null : trimmedPhone,
      'role': 'driver',
    });

    await _syncCurrentDevicePushTokenIfAvailable();
  }

  @override
  Future<void> signOut() async {
    final user = _client.auth.currentUser;
    if (user != null) {
      final currentToken = await FirebaseMessaging.instance.getToken();
      final existingTokens = await _fetchPushTokens(user);
      final nextTokens = currentToken == null
          ? existingTokens
          : existingTokens.where((token) => token != currentToken).toList();
      await _persistPushTokens(user, nextTokens);
    }
    await _client.auth.signOut();
  }

  @override
  Future<List<DriverOrder>> fetchAcceptedOrders() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('No active session found.');
    }
    final driverRowId = await _resolveDriverRowId(user);

    final rows = await _client
        .from('orders')
        .select(
          'id, order_numbers, customer_id, restaurant_id, driver_id, status, alert, allergy_note, delivery_address, delivery_lat, delivery_lng, items_json, created_at, subtotal_cents, delivery_fee_cents, total_cents, payment_intent_id, mpesa_transaction_id',
        )
        .not('delivery_address', 'is', null)
        .or(
          'and(status.eq.accepted,driver_id.is.null),and(driver_id.eq.$driverRowId,status.in.(accepted,picked_up))',
        )
        .order('created_at', ascending: false);

    final orders = (rows as List<dynamic>)
        .map((row) => _orderFromRow(row as Map<String, dynamic>))
        .toList();
    final hydratedOrders = await Future.wait(orders.map(_attachNames));
    await _cacheAcceptedOrders(hydratedOrders);
    return hydratedOrders;
  }

  @override
  Future<List<DriverOrder>> getCachedAcceptedOrders() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const [];
    }

    final raw = _preferences.getString('$_acceptedOrdersCachePrefix${user.id}');
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (entry) =>
                DriverOrder.fromJson(Map<String, dynamic>.from(entry as Map)),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Stream<void> watchAcceptedOrderChanges() {
    late final RealtimeChannel channel;
    late final StreamController<void> controller;

    controller = StreamController<void>.broadcast(
      onListen: () {
        channel = _client
            .channel('driver-orders-feed')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'orders',
              callback: (_) {
                if (!controller.isClosed) {
                  controller.add(null);
                }
              },
            );

        channel.subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );

    return controller.stream;
  }

  @override
  Stream<bool> watchOrderAlert(String orderId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map((rows) {
          if (rows.isEmpty) {
            return false;
          }

          final row = rows.first;
          return _toBool(row['alert']);
        });
  }

  @override
  Future<DriverOrder> fetchOrderById(String orderId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('No active session found.');
    }
    final driverRowId = await _resolveDriverRowId(user);

    final row = await _client
        .from('orders')
        .select(
          'id, order_numbers, customer_id, restaurant_id, driver_id, status, alert, allergy_note, delivery_address, delivery_lat, delivery_lng, items_json, created_at, subtotal_cents, delivery_fee_cents, total_cents, payment_intent_id, mpesa_transaction_id',
        )
        .eq('id', orderId)
        .single();

    final order = _orderFromRow(row);
    final isClaimedByAnotherDriver =
        (order.driverId ?? '').isNotEmpty &&
        order.driverId != driverRowId &&
        order.status != 'accepted';
    if (isClaimedByAnotherDriver) {
      throw Exception(
        'This order has already been assigned to another driver.',
      );
    }
    return _attachNames(order);
  }

  @override
  Future<DriverProfile> fetchProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('No active session found.');
    }

    final authEmail = user.email;
    final authPhone =
        user.phone ??
        (user.userMetadata?['phone']?.toString()) ??
        (user.userMetadata?['mobile']?.toString()) ??
        (user.userMetadata?['phone_number']?.toString());
    final authName =
        (user.userMetadata?['name']?.toString()) ??
        (user.userMetadata?['full_name']?.toString()) ??
        (user.userMetadata?['display_name']?.toString()) ??
        (user.userMetadata?['username']?.toString());
    final authCreatedAt = DateTime.tryParse(user.createdAt);

    final cacheKey = '$_profileCachePrefix${user.id}';
    final cached = _preferences.getString(cacheKey);

    try {
      Map<String, dynamic>? row;
      try {
        row = await _client
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();
      } catch (err) {
        debugPrint('Error querying users by id: $err');
      }

      if (row == null && authEmail != null && authEmail.isNotEmpty) {
        try {
          row = await _client
              .from('users')
              .select()
              .eq('email', authEmail)
              .maybeSingle();
        } catch (err) {
          debugPrint('Error querying users by email: $err');
        }
      }

      if (row != null) {
        if (row['role'] != 'driver' && row['id'] != null) {
          unawaited(
            _client
                .from('users')
                .update({'role': 'driver'})
                .eq('id', row['id']),
          );
        }

        final profile = DriverProfile.fromJson(
          {
            ...row,
            'role': 'driver',
            if (authCreatedAt != null)
              'created_at': authCreatedAt.toIso8601String(),
          },
          fallbackEmail: authEmail,
          fallbackName: authName,
          fallbackPhone: authPhone,
        );

        // If row was missing name or phone in database, backfill it
        final updates = <String, dynamic>{
          if ((row['name'] == null || row['name'].toString().trim().isEmpty) &&
              profile.name.isNotEmpty &&
              profile.name != 'Driver')
            'name': profile.name,
          if ((row['email'] == null ||
                  row['email'].toString().trim().isEmpty) &&
              authEmail != null)
            'email': authEmail,
          if ((row['phone'] == null ||
                  row['phone'].toString().trim().isEmpty) &&
              authPhone != null &&
              authPhone.isNotEmpty)
            'phone': authPhone,
        };

        if (updates.isNotEmpty && row['id'] != null) {
          unawaited(_client.from('users').update(updates).eq('id', row['id']));
        }

        await _preferences.setString(cacheKey, jsonEncode(profile.toJson()));
        return profile;
      }

      final fallbackProfile = DriverProfile.fromJson(
        {
          'id': user.id,
          'role': 'driver',
          if (authCreatedAt != null)
            'created_at': authCreatedAt.toIso8601String(),
        },
        fallbackEmail: authEmail,
        fallbackName: authName,
        fallbackPhone: authPhone,
      );

      try {
        await _client.from('users').upsert({
          'id': user.id,
          'email': authEmail,
          'name': fallbackProfile.name,
          if (authPhone != null && authPhone.isNotEmpty) 'phone': authPhone,
          'role': 'driver',
        });
      } catch (err) {
        debugPrint('Could not upsert user row: $err');
      }

      await _preferences.setString(
        cacheKey,
        jsonEncode(fallbackProfile.toJson()),
      );
      return fallbackProfile;
    } catch (_) {
      if (cached != null && cached.isNotEmpty) {
        try {
          final decoded = jsonDecode(cached) as Map<String, dynamic>;
          final cachedProfile = DriverProfile.fromJson(
            decoded,
            fallbackEmail: authEmail,
            fallbackName: authName,
            fallbackPhone: authPhone,
          );
          if (cachedProfile.email.isNotEmpty) {
            return cachedProfile;
          }
        } catch (_) {}
      }

      return DriverProfile.fromJson(
        {
          'id': user.id,
          'role': 'driver',
          if (authCreatedAt != null)
            'created_at': authCreatedAt.toIso8601String(),
        },
        fallbackEmail: authEmail,
        fallbackName: authName,
        fallbackPhone: authPhone,
      );
    }
  }

  @override
  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('No active session found.');
    }
    final driverRowId = await _resolveDriverRowId(user);

    final response = status == 'picked_up'
        ? await _client
              .from('orders')
              .update({'status': status, 'driver_id': driverRowId})
              .eq('id', orderId)
              .eq('status', 'accepted')
              .isFilter('driver_id', null)
              .select('id')
        : await _client
              .from('orders')
              .update({'status': status})
              .eq('id', orderId)
              .eq('driver_id', driverRowId)
              .inFilter('status', ['accepted', 'picked_up'])
              .select('id');

    if ((response as List<dynamic>).isEmpty) {
      throw Exception(
        status == 'picked_up'
            ? 'This order was already picked up by another driver.'
            : 'Failed to update order.',
      );
    }
  }

  @override
  Future<void> updateOrderAlert({
    required String orderId,
    required bool alert,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('No active session found.');
    }
    final driverRowId = await _resolveDriverRowId(user);

    final response = await _client
        .from('orders')
        .update({'alert': alert})
        .eq('id', orderId)
        .eq('driver_id', driverRowId)
        .neq('status', 'delivered')
        .select('id');

    if ((response as List<dynamic>).isEmpty) {
      throw Exception('Failed to update customer alert for this order.');
    }
  }

  @override
  Future<void> registerPushToken(String token) async {
    final user = _client.auth.currentUser;
    final normalizedToken = token.trim();
    if (user == null || normalizedToken.isEmpty) {
      return;
    }

    final existingTokens = await _fetchPushTokens(user);
    final nextTokens = {...existingTokens, normalizedToken}.toList();

    await _persistPushTokens(user, nextTokens);
  }

  @override
  Future<void> unregisterPushToken(String token) async {
    final user = _client.auth.currentUser;
    final normalizedToken = token.trim();
    if (user == null || normalizedToken.isEmpty) {
      return;
    }

    final existingTokens = await _fetchPushTokens(user);
    final nextTokens = existingTokens
        .where((entry) => entry != normalizedToken)
        .toList();

    await _persistPushTokens(user, nextTokens);
  }

  DriverOrder _orderFromRow(Map<String, dynamic> row) {
    return DriverOrder(
      id: row['id'].toString(),
      status: row['status'] as String? ?? 'pending',
      alert: _toBool(row['alert']),
      orderNumber: row['order_numbers']?.toString(),
      allergyNote: row['allergy_note'] as String?,
      deliveryAddress: row['delivery_address'] as String?,
      driverId: row['driver_id'] as String?,
      deliveryLat: _toDouble(row['delivery_lat']),
      deliveryLng: _toDouble(row['delivery_lng']),
      customerId: row['customer_id']?.toString(),
      restaurantId: row['restaurant_id']?.toString(),
      items: _parseItems(row['items_json']),
      subtotalCents: row['subtotal_cents'] as int?,
      deliveryFeeCents: row['delivery_fee_cents'] as int?,
      totalCents: row['total_cents'] as int?,
      paymentIntentId: row['payment_intent_id'] as String?,
      createdAt: row['created_at'] as String?,
      mpesaTransactionId: row['mpesa_transaction_id'] as String?,
    );
  }

  Future<DriverOrder> _attachNames(DriverOrder order) async {
    String? restaurantName = order.restaurantName;
    String? customerName = order.customerName;
    String? customerPhone = order.customerPhone;
    var restaurantOrderDelayMinutes = order.restaurantOrderDelayMinutes;

    if (order.restaurantId != null) {
      try {
        final row = await _client
            .from('restaurants')
            .select('name, driver_order_delay_minutes')
            .eq('id', order.restaurantId!)
            .single();
        restaurantName = row['name'] as String? ?? restaurantName;
        final delayMinutes = (row['driver_order_delay_minutes'] as num?)
            ?.toInt();
        restaurantOrderDelayMinutes = delayMinutes ?? 10;
      } catch (_) {}
    }

    if (order.customerId != null) {
      try {
        final row = await _client
            .from('users')
            .select()
            .eq('id', order.customerId!)
            .maybeSingle();
        if (row != null) {
          customerName = _resolveCustomerName(row, fallback: customerName);
          customerPhone =
              row['phone']?.toString() ??
              row['mobile']?.toString() ??
              row['mobile_number']?.toString() ??
              customerPhone;
        }
      } catch (_) {}
    }

    return order.copyWith(
      restaurantName: restaurantName,
      restaurantOrderDelayMinutes: restaurantOrderDelayMinutes,
      customerName: customerName,
      customerPhone: customerPhone,
    );
  }

  String? _resolveCustomerName(Map<String, dynamic> row, {String? fallback}) {
    final firstName = row['first_name']?.toString().trim();
    final lastName = row['last_name']?.toString().trim();
    final composedName = [
      if (firstName != null && firstName.isNotEmpty) firstName,
      if (lastName != null && lastName.isNotEmpty) lastName,
    ].join(' ');

    final directName = _firstNonEmpty([
      row['name']?.toString(),
      row['full_name']?.toString(),
      composedName,
      row['display_name']?.toString(),
      row['username']?.toString(),
    ]);
    if (directName != null) {
      return directName;
    }

    final email = row['email']?.toString().trim();
    if (email != null && email.isNotEmpty && email.contains('@')) {
      return email.split('@').first;
    }

    final knownPlace = row['known_place']?.toString().trim();
    if (knownPlace != null && knownPlace.isNotEmpty) {
      return knownPlace;
    }

    return fallback;
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  List<OrderItem> _parseItems(dynamic raw) {
    final list = switch (raw) {
      final List<dynamic> value => value,
      final String value when value.isNotEmpty =>
        jsonDecode(value) as List<dynamic>,
      _ => <dynamic>[],
    };

    return list.map((entry) {
      final item = Map<String, dynamic>.from(entry as Map);
      return OrderItem(
        name: item['name'] as String? ?? item['title'] as String? ?? 'Item',
        qty:
            (item['qty'] as num?)?.toInt() ??
            (item['quantity'] as num?)?.toInt() ??
            1,
        notes: item['notes'] as String? ?? item['note'] as String?,
        price: _toDouble(item['price']),
        orderType: item['orderType'] as String? ?? item['type'] as String?,
      );
    }).toList();
  }

  double? _toDouble(dynamic value) {
    return switch (value) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text),
      _ => null,
    };
  }

  bool _toBool(dynamic value) {
    return switch (value) {
      final bool boolValue => boolValue,
      final num number => number != 0,
      final String text =>
        text.trim().toLowerCase() == 'true' || text.trim() == '1',
      _ => false,
    };
  }

  Future<List<String>> _fetchPushTokens(User user) async {
    final row = await _findUserRow(user);

    if (row == null) {
      return const [];
    }

    final raw = row['push_tokens'];
    return _normalizePushTokens(raw);
  }

  List<String> _normalizePushTokens(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<String>()
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList();
    }

    if (raw is String && raw.trim().isNotEmpty) {
      return [raw.trim()];
    }

    return const [];
  }

  Future<void> _syncCurrentDevicePushTokenIfAvailable() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) {
        return;
      }

      await registerPushToken(token);
    } catch (error) {
      debugPrint('Failed to sync push token: $error');
    }
  }

  Future<void> _persistPushTokens(User user, List<String> tokens) async {
    final normalizedTokens = tokens
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toSet()
        .toList();

    final existingRow = await _findUserRow(user);
    Map<String, dynamic>? response;

    if (existingRow != null) {
      final query = _client.from('users').update({
        'role': 'driver',
        'push_tokens': normalizedTokens,
      });

      response =
          await (existingRow['id'] != null
                  ? query.eq('id', existingRow['id'])
                  : query.eq('email', user.email as Object))
              .select('id, push_tokens')
              .maybeSingle();
    } else {
      response = await _client
          .from('users')
          .insert({
            'id': user.id,
            'email': user.email,
            'role': 'driver',
            'push_tokens': normalizedTokens,
          })
          .select('id, push_tokens')
          .maybeSingle();
    }

    if (response == null) {
      throw Exception('Failed to persist push token for ${user.id}.');
    }

    final savedTokens = _normalizePushTokens(response['push_tokens']);
    final expectedTokens = normalizedTokens.toSet();
    if (savedTokens.toSet().length != expectedTokens.length ||
        !savedTokens.toSet().containsAll(expectedTokens)) {
      throw Exception('Push token persistence did not update the users row.');
    }
  }

  Future<Map<String, dynamic>?> _findUserRow(User user) async {
    final byId = await _client
        .from('users')
        .select('id, email, push_tokens')
        .eq('id', user.id)
        .maybeSingle();
    if (byId != null) {
      return byId;
    }

    final email = user.email;
    if (email == null || email.isEmpty) {
      return null;
    }

    return _client
        .from('users')
        .select('id, email, push_tokens')
        .eq('email', email)
        .maybeSingle();
  }

  Future<String> _resolveDriverRowId(User user) async {
    final row = await _findUserRow(user);
    final driverRowId = row?['id']?.toString();
    if (driverRowId == null || driverRowId.isEmpty) {
      throw Exception(
        'Your driver profile could not be found in the users table.',
      );
    }
    return driverRowId;
  }

  Future<void> _cacheAcceptedOrders(List<DriverOrder> orders) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return;
    }

    await _preferences.setString(
      '$_acceptedOrdersCachePrefix${user.id}',
      jsonEncode(orders.map((order) => order.toJson()).toList()),
    );
  }
}
