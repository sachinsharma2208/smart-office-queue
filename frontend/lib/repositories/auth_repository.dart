import '../models/auth_user.dart';
import '../services/api_client.dart';

class LoginResult {
  const LoginResult({required this.token, required this.user});
  final String token;
  final AuthUser user;
}

class AuthRepository {
  AuthRepository(this._api);
  final ApiClient _api;

  Future<LoginResult> login(String email, String password) async {
    final json = await _api.post('/api/auth/login', body: <String, dynamic>{
      'email': email,
      'password': password,
    }) as Map<String, dynamic>;
    return LoginResult(
      token: json['token'] as String,
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}
