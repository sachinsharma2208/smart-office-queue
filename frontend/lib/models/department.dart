class Department {
  const Department({
    required this.id,
    required this.name,
    required this.code,
    required this.isPaused,
    required this.waitingCount,
    required this.servingToken,
    required this.avgServiceMinutes,
    required this.estimatedWaitMinutes,
  });

  final String id;
  final String name;
  final String code;
  final bool isPaused;
  final int waitingCount;
  final String? servingToken;
  final double avgServiceMinutes;
  final int estimatedWaitMinutes;

  factory Department.fromJson(Map<String, dynamic> j) => Department(
        id: j['id'] as String,
        name: j['name'] as String,
        code: j['code'] as String,
        isPaused: j['is_paused'] as bool? ?? false,
        waitingCount: (j['waiting_count'] as num?)?.toInt() ?? 0,
        servingToken: j['serving_token'] as String?,
        avgServiceMinutes: (j['avg_service_minutes'] as num?)?.toDouble() ?? 0,
        estimatedWaitMinutes: (j['estimated_wait_minutes'] as num?)?.toInt() ?? 0,
      );
}
