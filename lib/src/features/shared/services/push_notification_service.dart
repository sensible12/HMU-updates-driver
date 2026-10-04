import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../controllers/auth_controller.dart';
import 'driver_repository.dart';

const AndroidNotificationChannel _ordersChannel = AndroidNotificationChannel(
  'accepted_orders',
  'Accepted Orders',
  description: 'Push notifications for newly accepted delivery orders.',
  importance: Importance.high,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
}

class PushNotificationService {
  PushNotificationService({
    required DriverRepository repository,
    required AuthController authController,
  })  : _repository = repository,
        _authController = authController;

  final DriverRepository _repository;
  final AuthController _authController;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<String>? _tokenRefreshSubscription;
  VoidCallback? _authListener;
  String? _activeToken;
  bool _initialized = false;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  Future<PushDiagnostics> inspectSetup() async {
    var firebaseReady = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (error) {
      firebaseReady = false;
      debugPrint('Push diagnostics Firebase init failed: $error');
    }

    AuthorizationStatus? permissionStatus;
    String? token;
    String? errorMessage;

    if (firebaseReady) {
      try {
        final settings = await _messaging.getNotificationSettings();
        permissionStatus = settings.authorizationStatus;
        token = await _messaging.getToken();
      } catch (error) {
        errorMessage = error.toString();
        debugPrint('Push diagnostics lookup failed: $error');
      }
    }

    return PushDiagnostics(
      firebaseReady: firebaseReady,
      isAuthenticated: _authController.isAuthenticated,
      permissionStatus: permissionStatus,
      token: token,
      errorMessage: errorMessage,
    );
  }

  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (_) {
      debugPrint('Push initialization skipped because Firebase failed to initialize.');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _initializeLocalNotifications();

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint(
      'Push permission status: ${settings.authorizationStatus.name}',
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('Push notifications are denied on this device.');
      return;
    }

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) async {
      final previousToken = _activeToken;
      _activeToken = token;
      if (previousToken != null && previousToken != token) {
        await _repository.unregisterPushToken(previousToken);
      }
      await _syncTokenIfPossible(token);
    });

    _authListener = () {
      final token = _activeToken;
      if (token == null || token.isEmpty) {
        return;
      }

      if (_authController.isAuthenticated) {
        unawaited(_repository.registerPushToken(token));
      } else {
        unawaited(_repository.unregisterPushToken(token));
      }
    };
    _authController.addListener(_authListener!);

    _activeToken = await _messaging.getToken();
    debugPrint('Initial FCM token loaded: ${_activeToken != null}');
    if (_activeToken != null) {
      await _syncTokenIfPossible(_activeToken!);
    }

    _initialized = true;
  }

  Future<void> ensureCurrentPushToken() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final settings = await _messaging.getNotificationSettings();
      debugPrint(
        'Explicit push sync permission status: ${settings.authorizationStatus.name}',
      );
      final token = await _messaging.getToken();
      if (token == null || token.trim().isEmpty) {
        debugPrint('FCM token is null or empty during explicit sync.');
        return;
      }

      _activeToken = token;
      debugPrint('Explicit push sync got FCM token.');
      await _syncTokenIfPossible(token);
    } catch (error) {
      debugPrint('Explicit push token sync failed: $error');
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    if (_authListener != null) {
      _authController.removeListener(_authListener!);
    }
  }

  Future<void> _syncTokenIfPossible(String token) async {
    if (!_authController.isAuthenticated) {
      debugPrint('Skipping push token sync because user is not authenticated.');
      return;
    }
    debugPrint('Registering FCM token for authenticated driver.');
    await _repository.registerPushToken(token);
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    await _localNotifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_ordersChannel);
    await androidPlugin?.requestNotificationsPermission();
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) {
      return;
    }

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _ordersChannel.id,
          _ordersChannel.name,
          channelDescription: _ordersChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}

class PushDiagnostics {
  const PushDiagnostics({
    required this.firebaseReady,
    required this.isAuthenticated,
    required this.permissionStatus,
    required this.token,
    required this.errorMessage,
  });

  final bool firebaseReady;
  final bool isAuthenticated;
  final AuthorizationStatus? permissionStatus;
  final String? token;
  final String? errorMessage;

  bool get hasToken => (token ?? '').trim().isNotEmpty;

  String get permissionLabel => permissionStatus?.name ?? 'unknown';
}
