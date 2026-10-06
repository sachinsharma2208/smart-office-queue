DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

class QueueEvent {
  const QueueEvent({required this.eventType, required this.metadata, required this.createdAt});

  final String eventType;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  factory QueueEvent.fromJson(Map<String, dynamic> j) => QueueEvent(
        eventType: j['event_type'] as String,
        metadata: (j['metadata'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

class TokenModel {
  const TokenModel({
    required this.id,
    required this.tokenNumber,
    required this.departmentId,
    required this.departmentName,
    required this.departmentCode,
    required this.departmentPaused,
    required this.priority,
    required this.status,
    required this.noShowCount,
    required this.queuePosition,
    required this.peopleAhead,
    required this.estimatedWaitMinutes,
    required this.createdAt,
    required this.calledAt,
    required this.completedAt,
    required this.cancelledAt,
    required this.transferredFromTokenId,
    required this.transferredToTokenId,
    required this.transferredToTokenNumber,
    required this.events,
  });

  final String id;
  final String tokenNumber;
  final String departmentId;
  final String departmentName;
  final String departmentCode;
  final bool departmentPaused;
  final String priority; // NORMAL | PRIORITY
  final String status; // WAITING | SERVING | COMPLETED | CANCELLED | TRANSFERRED
  final int noShowCount;
  final int? queuePosition;
  final int? peopleAhead;
  final int? estimatedWaitMinutes;
  final DateTime createdAt;
  final DateTime? calledAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? transferredFromTokenId;
  final String? transferredToTokenId;
  final String? transferredToTokenNumber;
  final List<QueueEvent> events;

  bool get isPriority => priority == 'PRIORITY';
  bool get isWaiting => status == 'WAITING';
  bool get isServing => status == 'SERVING';
  bool get isActive => isWaiting || isServing;

  factory TokenModel.fromJson(Map<String, dynamic> j) => TokenModel(
        id: j['id'] as String,
        tokenNumber: j['token_number'] as String,
        departmentId: j['department_id'] as String,
        departmentName: j['department_name'] as String,
        departmentCode: j['department_code'] as String,
        departmentPaused: j['department_paused'] as bool? ?? false,
        priority: j['priority'] as String,
        status: j['status'] as String,
        noShowCount: (j['no_show_count'] as num?)?.toInt() ?? 0,
        queuePosition: (j['queue_position'] as num?)?.toInt(),
        peopleAhead: (j['people_ahead'] as num?)?.toInt(),
        estimatedWaitMinutes: (j['estimated_wait_minutes'] as num?)?.toInt(),
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        calledAt: _dt(j['called_at']),
        completedAt: _dt(j['completed_at']),
        cancelledAt: _dt(j['cancelled_at']),
        transferredFromTokenId: j['transferred_from_token_id'] as String?,
        transferredToTokenId: j['transferred_to_token_id'] as String?,
        transferredToTokenNumber: j['transferred_to_token_number'] as String?,
        events: ((j['events'] as List?) ?? const <dynamic>[])
            .map((e) => QueueEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
