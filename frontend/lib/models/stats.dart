import 'department.dart';
import 'token.dart';

class DeptStats {
  const DeptStats({
    required this.departmentId,
    required this.name,
    required this.code,
    required this.isPaused,
    required this.waiting,
    required this.serving,
    required this.completed,
    required this.cancelled,
    required this.noShows,
    required this.avgWaitingMinutes,
    required this.avgServiceMinutes,
  });

  final String departmentId;
  final String name;
  final String code;
  final bool isPaused;
  final int waiting;
  final int serving;
  final int completed;
  final int cancelled;
  final int noShows;
  final double avgWaitingMinutes;
  final double avgServiceMinutes;

  factory DeptStats.fromJson(Map<String, dynamic> j) => DeptStats(
        departmentId: j['department_id'] as String,
        name: j['department_name'] as String,
        code: j['department_code'] as String,
        isPaused: j['is_paused'] as bool? ?? false,
        waiting: (j['waiting'] as num?)?.toInt() ?? 0,
        serving: (j['serving'] as num?)?.toInt() ?? 0,
        completed: (j['completed'] as num?)?.toInt() ?? 0,
        cancelled: (j['cancelled'] as num?)?.toInt() ?? 0,
        noShows: (j['no_shows'] as num?)?.toInt() ?? 0,
        avgWaitingMinutes: (j['avg_waiting_minutes'] as num?)?.toDouble() ?? 0,
        avgServiceMinutes: (j['avg_service_minutes'] as num?)?.toDouble() ?? 0,
      );
}

class DashboardTotals {
  const DashboardTotals({
    required this.waiting,
    required this.serving,
    required this.completed,
    required this.cancelled,
    required this.noShows,
    required this.avgWaitingMinutes,
    required this.pausedDepartments,
    required this.totalDepartments,
  });

  final int waiting;
  final int serving;
  final int completed;
  final int cancelled;
  final int noShows;
  final double avgWaitingMinutes;
  final int pausedDepartments;
  final int totalDepartments;

  factory DashboardTotals.fromJson(Map<String, dynamic> j) => DashboardTotals(
        waiting: (j['waiting'] as num?)?.toInt() ?? 0,
        serving: (j['serving'] as num?)?.toInt() ?? 0,
        completed: (j['completed'] as num?)?.toInt() ?? 0,
        cancelled: (j['cancelled'] as num?)?.toInt() ?? 0,
        noShows: (j['no_shows'] as num?)?.toInt() ?? 0,
        avgWaitingMinutes: (j['avg_waiting_minutes'] as num?)?.toDouble() ?? 0,
        pausedDepartments: (j['paused_departments'] as num?)?.toInt() ?? 0,
        totalDepartments: (j['total_departments'] as num?)?.toInt() ?? 0,
      );
}

class Dashboard {
  const Dashboard({required this.totals, required this.departments});

  final DashboardTotals totals;
  final List<DeptStats> departments;

  factory Dashboard.fromJson(Map<String, dynamic> j) => Dashboard(
        totals: DashboardTotals.fromJson(j['totals'] as Map<String, dynamic>),
        departments: (j['departments'] as List)
            .map((e) => DeptStats.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// The live queue of one department (GET /api/queues/:id).
class QueueData {
  const QueueData({
    required this.department,
    required this.serving,
    required this.waiting,
    required this.stats,
  });

  final Department department;
  final TokenModel? serving;
  final List<TokenModel> waiting;
  final DeptStats stats;

  factory QueueData.fromJson(Map<String, dynamic> j) => QueueData(
        department: Department.fromJson(j['department'] as Map<String, dynamic>),
        serving: j['serving'] == null
            ? null
            : TokenModel.fromJson(j['serving'] as Map<String, dynamic>),
        waiting: ((j['waiting'] as List?) ?? const <dynamic>[])
            .map((e) => TokenModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        stats: DeptStats.fromJson(j['stats'] as Map<String, dynamic>),
      );
}
