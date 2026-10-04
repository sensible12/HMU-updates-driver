import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_user_session.dart';
import '../services/driver_repository.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._repository);

  final DriverRepository _repository;

  StreamSubscription<AppUserSession?>? _subscription;
  AppUserSession? currentUser;
  bool loading = true;

  bool get isAuthenticated => currentUser != null;

  Future<void> initialize() async {
    currentUser = _repository.currentUser;
    _subscription = _repository.authStateChanges.listen((session) {
      currentUser = session;
      loading = false;
      notifyListeners();
    });
    loading = false;
    notifyListeners();
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) {
    return _repository.signIn(email: email, password: password);
  }

  Future<void> register({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) {
    return _repository.register(
      name: name,
      phone: phone,
      email: email,
      password: password,
    );
  }

  Future<void> signOut() {
    return _repository.signOut();
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _repository.sendPasswordResetEmail(email);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
