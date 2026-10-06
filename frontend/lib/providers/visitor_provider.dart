import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';
import '../models/department.dart';
import '../models/token.dart';
import '../repositories/queue_repository.dart';
import '../services/api_client.dart';
import '../utils/poller.dart';
import 'load_state.dart';

/// State for the visitor flow: department list + the visitor's own token.
/// All queue numbers (position, ETA) come from the backend on every refresh.
class VisitorProvider extends ChangeNotifier {
  VisitorProvider(this._repo, this._prefs) {
    departmentPoller = Poller(AppConfig.pollInterval, () => loadDepartments(silent: true));
    tokenPoller = Poller(AppConfig.pollInterval, () => refreshToken(silent: true));
  }

  static const _tokenIdKey = 'visitor_token_id';

  final QueueRepository _repo;
  final SharedPreferences _prefs;
  late final Poller departmentPoller;
  late final Poller tokenPoller;

  List<Department> departments = const [];
  LoadState departmentState = LoadState.idle;
  String? departmentError;

  TokenModel? token;
  LoadState tokenState = LoadState.idle;
  String? tokenError;
  bool busy = false;

  bool get hasActiveToken => token != null && token!.isActive;

  Future<void> loadDepartments({bool silent = false}) async {
    if (!silent || departments.isEmpty) {
      departmentState = LoadState.loading;
      departmentError = null;
      notifyListeners();
    }
    try {
      departments = await _repo.departments();
      departmentState = LoadState.loaded;
      departmentError = null;
    } on ApiException catch (e) {
      if (departments.isEmpty || !silent) {
        departmentState = LoadState.error;
        departmentError = e.message;
      }
    }
    notifyListeners();
  }

  /// Creates a token. Throws [ApiException] (e.g. department_paused).
  Future<TokenModel> generateToken(Department department, {required bool priority}) async {
    busy = true;
    notifyListeners();
    try {
      final created = await _repo.createToken(department.id, priority: priority);
      token = created;
      tokenState = LoadState.loaded;
      tokenError = null;
      await _prefs.setString(_tokenIdKey, created.id);
      return created;
    } on ApiException catch (e) {
      if (e.code == 'department_paused') {
        loadDepartments(silent: true); // show the paused state immediately
      }
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Re-opens the token saved on this device (if any).
  Future<void> restoreToken() async {
    final id = _prefs.getString(_tokenIdKey);
    if (id == null || token != null) return;
    await _loadToken(id, silent: false, forgetOnNotFound: true);
  }

  Future<void> refreshToken({bool silent = false}) async {
    final current = token;
    if (current == null) return;
    await _loadToken(current.id, silent: silent);
  }

  Future<void> _loadToken(String id, {required bool silent, bool forgetOnNotFound = false}) async {
    if (!silent) {
      tokenState = LoadState.loading;
      tokenError = null;
      notifyListeners();
    }
    try {
      token = await _repo.getToken(id);
      tokenState = LoadState.loaded;
      tokenError = null;
    } on ApiException catch (e) {
      if (forgetOnNotFound && e.statusCode == 404) {
        await clearToken();
        return;
      }
      if (!silent || token == null) {
        tokenState = LoadState.error;
        tokenError = e.message;
      }
    }
    notifyListeners();
  }

  /// Cancels the visitor's waiting token. Throws [ApiException] on failure.
  Future<bool> cancelToken() async {
    final current = token;
    if (current == null) return false;
    busy = true;
    notifyListeners();
    try {
      token = await _repo.cancelToken(current.id);
      return true;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// After a staff transfer: follow the visitor to their new token.
  Future<void> followTransfer() async {
    final newId = token?.transferredToTokenId;
    if (newId == null) return;
    await _prefs.setString(_tokenIdKey, newId);
    await _loadToken(newId, silent: false);
  }

  Future<void> clearToken() async {
    token = null;
    tokenState = LoadState.idle;
    tokenError = null;
    await _prefs.remove(_tokenIdKey);
    notifyListeners();
  }

  @override
  void dispose() {
    departmentPoller.dispose();
    tokenPoller.dispose();
    super.dispose();
  }
}
