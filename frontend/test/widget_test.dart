import 'package:flutter_test/flutter_test.dart';
import 'package:smart_office_queue/models/token.dart';
import 'package:smart_office_queue/utils/formatters.dart';
import 'package:smart_office_queue/utils/validators.dart';

void main() {
  test('TokenModel parses the backend JSON', () {
    final t = TokenModel.fromJson(<String, dynamic>{
      'id': 'a',
      'token_number': 'IT-004',
      'department_id': 'd',
      'department_name': 'IT Support',
      'department_code': 'IT',
      'department_paused': false,
      'priority': 'PRIORITY',
      'status': 'WAITING',
      'no_show_count': 0,
      'queue_position': 1,
      'people_ahead': 0,
      'estimated_wait_minutes': 0,
      'created_at': '2026-01-01T09:00:00Z',
    });
    expect(t.isPriority, isTrue);
    expect(t.isWaiting, isTrue);
    expect(t.queuePosition, 1);
    expect(t.events, isEmpty);
  });

  test('formatEstimate', () {
    expect(formatEstimate(0), 'No wait');
    expect(formatEstimate(15), '~15 min');
    expect(formatEstimate(null), '—');
  });

  test('email / password validators', () {
    expect(Validators.email(''), isNotNull);
    expect(Validators.email('nope'), isNotNull);
    expect(Validators.email('a@b.co'), isNull);
    expect(Validators.password('123'), isNotNull);
    expect(Validators.password('123456'), isNull);
  });
}
