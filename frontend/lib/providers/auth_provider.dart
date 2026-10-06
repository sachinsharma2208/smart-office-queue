import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_user.dart';
import '../repositories/auth_repository.dart';
import '../services/api_client.dart';

/// Holds the logged-in staff/admin session (visitors never log in).
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._repo, this._api, this._prefs) {
    _api.onUnauthorized = _handleExpired;
  }

  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  final AuthRepository _repo;
  final ApiClient _api;
  final SharedPreferences _prefs;

  AuthUser? user;
  bool loading = false;
  String? error;
  bool sessionExpired = false;

  bool get isLoggedIn => user != null;

  /// Restores a saved session on app start.
  Future<void> restore() async {
    final token = _prefs.getString(_tokenKey);
    final saved = _prefs.getString(_userKey);
    if (token != null && saved != null) {
      try {
        user = AuthUser.fromJson(jsonDecode(saved) as Map<String, dynamic>);
        _api.authToken = token;
      } catch (_) {
        await _clear();
      }
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    loading = true;
    error = null;
    sessionExpired = false;
    notifyListeners();
    try {
      final result = await _repo.login(email.trim(), password);
      _api.authToken = result.token;
      user = result.user;
      await _prefs.setString(_tokenKey, result.token);
      await _prefs.setString(_userKey, jsonEncode(result.user.toJson()));
      return true;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } catch (_) {
      error = 'Unexpected error. Please try again.';
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _clear();
    notifyListeners();
  }

  void _handleExpired() {
    if (user == null) return;
    sessionExpired = true;
    _clear().then((_) => notifyListeners());
  }

  Future<void> _clear() async {
    _api.authToken = null;
    user = null;
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_userKey);
  }
}
