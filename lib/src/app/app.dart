import 'dart:async';

import 'package:flutter/material.dart';

import '../core/navigation/app_router.dart';
import '../core/theme/app_theme.dart';
import '../features/shared/controllers/auth_controller.dart';
import '../features/shared/services/driver_repository.dart';
import '../features/shared/services/push_notification_service.dart';
import 'app_bootstrap.dart';
import 'app_scope.dart';

class HmuDriverBootstrapApp extends StatelessWidget {
  const HmuDriverBootstrapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: FutureBuilder<AppBootstrapData>(
        future: AppBootstrap.initialize(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _BootstrapScreen();
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return _BootstrapErrorScreen(
              error: snapshot.error,
            );
          }

          final data = snapshot.data!;
          return HmuDriverApp(
            repository: data.repository,
            authController: data.authController,
            pushNotificationService: data.pushNotificationService,
          );
        },
      ),
    );
  }
}

class HmuDriverApp extends StatefulWidget {
  const HmuDriverApp({
    super.key,
    required this.repository,
    required this.authController,
    required this.pushNotificationService,
  });

  final DriverRepository repository;
  final AuthController authController;
  final PushNotificationService pushNotificationService;

  @override
  State<HmuDriverApp> createState() => _HmuDriverAppState();
}

class _HmuDriverAppState extends State<HmuDriverApp> {
  late final AppRouter _router;

  @override
  void initState() {
    super.initState();
    _router = AppRouter(widget.authController);
    unawaited(widget.pushNotificationService.initialize());
  }

  @override
  void dispose() {
    unawaited(widget.pushNotificationService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      repository: widget.repository,
      authController: widget.authController,
      pushNotificationService: widget.pushNotificationService,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'HMU-Driver',
        theme: AppTheme.light(),
        routerConfig: _router.config,
      ),
    );
  }
}

class _BootstrapScreen extends StatelessWidget {
  const _BootstrapScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The app could not finish starting.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '$error',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
