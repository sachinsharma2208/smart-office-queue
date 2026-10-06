import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../models/auth_user.dart';
import '../models/department.dart';
import '../models/stats.dart';
import '../models/token.dart';
import '../repositories/queue_repository.dart';
import '../services/api_client.dart';
import '../utils/poller.dart';
import 'load_state.dart';

/// State for staff/admin screens: selected department, its live queue,
/// department list (management) and the admin dashboard.
/// Every action calls the backend; the UI just re-renders what comes back.
class StaffProvider extends ChangeNotifier {
  StaffProvider(this._repo) {
    queuePoller = Poller(AppConfig.pollInterval, () => refreshQueue(silent: true));
    departmentPoller = Poller(AppConfig.pollInterval, () => loadDepartments(silent: true));
    dashboardPoller = Poller(AppConfig.pollInterval, () => loadDashboard(silent: true));
  }

  final QueueRepository _repo;
  late final Poller queuePoller;
  late final Poller departmentPoller;
  late final Poller dashboardPoller;

  List<Department> departments = const [];
  String? selectedDepartmentId;

  QueueData? queue;
  LoadState queueState = LoadState.idle;
  String? queueError;

  Dashboard? dashboard;
  LoadState dashboardState = LoadState.idle;
  String? dashboardError;

  bool busy = false;

  Department? get selectedDepartment {
    for (final d in departments) {
      if (d.id == selectedDepartmentId) return d;
    }
    return null;
  }

  /// Called when a staff/admin screen opens: loads departments and selects
  /// the user's own department (admins start with the first one).
  Future<void> init(AuthUser user) async {
    await loadDepartments();
    if (selectedDepartmentId == null || (!user.isAdmin && selectedDepartmentId != user.departmentId)) {
      selectedDepartmentId =
          user.departmentId ?? (departments.isNotEmpty ? departments.first.id : null);
    }
    await refreshQueue();
  }

  void selectDepartment(String id) {
    if (id == selectedDepartmentId) return;
    selectedDepartmentId = id;
    queue = null;
    queueState = LoadState.loading;
    notifyListeners();
    refreshQueue();
  }

  void reset() {
    departments = const [];
    selectedDepartmentId = null;
    queue = null;
    queueState = LoadState.idle;
    dashboard = null;
    dashboardState = LoadState.idle;
    notifyListeners();
  }

  Future<void> loadDepartments({bool silent = false}) async {
    try {
      departments = await _repo.departments();
    } on ApiException catch (e) {
      if (!silent) queueError = e.message;
    }
    notifyListeners();
  }

  Future<void> refreshQueue({bool silent = false}) async {
    final id = selectedDepartmentId;
    if (id == null) return;
    if (!silent) {
      queueState = LoadState.loading;
      queueError = null;
      notifyListeners();
    }
    try {
      final data = await _repo.queue(id);
      if (id != selectedDepartmentId) return; // user switched department meanwhile
      queue = data;
      queueState = LoadState.loaded;
      queueError = null;
    } on ApiException catch (e) {
      if (!silent || queue == null) {
        queueState = LoadState.error;
        queueError = e.message;
      }
    }
    notifyListeners();
  }

  Future<void> loadDashboard({bool silent = false}) async {
    if (!silent || dashboard == null) {
      dashboardState = LoadState.loading;
      dashboardError = null;
      notifyListeners();
    }
    try {
      dashboard = await _repo.dashboard();
      dashboardState = LoadState.loaded;
      dashboardError = null;
    } on ApiException catch (e) {
      if (!silent || dashboard == null) {
        dashboardState = LoadState.error;
        dashboardError = e.message;
      }
    }
    notifyListeners();
  }

  Future<TokenModel> fetchToken(String id) => _repo.getToken(id);

  // ---- queue actions (all throw ApiException on failure)

  Future<T> _run<T>(Future<T> Function() action) async {
    busy = true;
    notifyListeners();
    try {
      final result = await action();
      await Future.wait<void>([refreshQueue(silent: true), loadDepartments(silent: true)]);
      return result;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<TokenModel> callNext() => _run(() => _repo.callNext(selectedDepartmentId!));

  Future<TokenModel> complete(String tokenId) => _run(() => _repo.complete(tokenId));

  Future<TokenModel> noShow(String tokenId) => _run(() => _repo.noShow(tokenId));

  Future<TokenModel> transfer(String tokenId, String targetDepartmentId) =>
      _run(() => _repo.transfer(tokenId, targetDepartmentId));

  Future<Department> setPaused(String departmentId, {required bool paused}) async {
    busy = true;
    notifyListeners();
    try {
      final updated = await _repo.setPaused(departmentId, paused: paused);
      await Future.wait<void>([
        loadDepartments(silent: true),
        loadDashboard(silent: true),
        if (departmentId == selectedDepartmentId) refreshQueue(silent: true),
      ]);
      return updated;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    queuePoller.dispose();
    departmentPoller.dispose();
    dashboardPoller.dispose();
    super.dispose();
  }
}
