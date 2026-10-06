class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.departmentId,
    required this.departmentName,
  });

  final String id;
  final String name;
  final String email;
  final String role; // STAFF | ADMIN
  final String? departmentId;
  final String? departmentName;

  bool get isAdmin => role == 'ADMIN';

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String,
        role: j['role'] as String,
        departmentId: j['department_id'] as String?,
        departmentName: j['department_name'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'email': email,
        'role': role,
        'department_id': departmentId,
        'department_name': departmentName,
      };
}
