import '../models/department.dart';
import '../models/stats.dart';
import '../models/token.dart';
import '../services/api_client.dart';

/// Maps every backend endpoint to a typed Dart method.
class QueueRepository {
  QueueRepository(this._api);
  final ApiClient _api;

  Map<String, dynamic> _obj(dynamic json) => json as Map<String, dynamic>;

  // ---- departments
  Future<List<Department>> departments() async {
    final list = await _api.get('/api/departments') as List;
    return list.map((e) => Department.fromJson(_obj(e))).toList();
  }

  Future<Department> setPaused(String departmentId, {required bool paused}) async {
    final action = paused ? 'pause' : 'resume';
    return Department.fromJson(_obj(await _api.post('/api/departments/$departmentId/$action')));
  }

  // ---- tokens
  Future<TokenModel> createToken(String departmentId, {required bool priority}) async {
    final json = await _api.post('/api/tokens', body: <String, dynamic>{
      'department_id': departmentId,
      'priority': priority ? 'PRIORITY' : 'NORMAL',
    });
    return TokenModel.fromJson(_obj(json));
  }

  Future<TokenModel> getToken(String id) async =>
      TokenModel.fromJson(_obj(await _api.get('/api/tokens/$id')));

  Future<TokenModel> cancelToken(String id) async =>
      TokenModel.fromJson(_obj(await _api.post('/api/tokens/$id/cancel')));

  Future<TokenModel> complete(String id) async =>
      TokenModel.fromJson(_obj(await _api.post('/api/tokens/$id/complete')));

  Future<TokenModel> noShow(String id) async =>
      TokenModel.fromJson(_obj(await _api.post('/api/tokens/$id/no-show')));

  /// Returns the NEW token created in the target department.
  Future<TokenModel> transfer(String id, String targetDepartmentId) async {
    final json = _obj(await _api.post('/api/tokens/$id/transfer', body: <String, dynamic>{
      'target_department_id': targetDepartmentId,
    }));
    return TokenModel.fromJson(_obj(json['new_token']));
  }

  // ---- queues
  Future<QueueData> queue(String departmentId) async =>
      QueueData.fromJson(_obj(await _api.get('/api/queues/$departmentId')));

  Future<TokenModel> callNext(String departmentId) async =>
      TokenModel.fromJson(_obj(await _api.post('/api/queues/$departmentId/call-next')));

  // ---- dashboard
  Future<Dashboard> dashboard() async =>
      Dashboard.fromJson(_obj(await _api.get('/api/dashboard')));
}
