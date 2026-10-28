enum UserRole {
  admin('ADMIN', '管理员'),
  user('USER', '普通用户');

  final String value;
  final String label;
  const UserRole(this.value, this.label);

  static UserRole fromString(String? val) {
    if (val == null) return UserRole.user;
    if (val.toUpperCase() == 'ADMIN') return UserRole.admin;
    return UserRole.user;
  }
}

class UserModel {
  final String id;
  final String username;
  final UserRole role;
  final String? token;
  final bool isMaster;
  final String createdAt;
  final String updatedAt;

  UserModel({
    required this.id,
    required this.username,
    required this.role,
    this.token,
    this.isMaster = false,
    this.createdAt = '',
    this.updatedAt = '',
  });

  bool get isAdmin => role == UserRole.admin || isMaster;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      role: UserRole.fromString(json['role']?.toString()),
      token: json['token']?.toString(),
      isMaster: json['is_master'] == true,
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'role': role.value,
      'token': token,
      'is_master': isMaster,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  UserModel copyWith({
    String? id,
    String? username,
    UserRole? role,
    String? token,
    bool? isMaster,
    String? createdAt,
    String? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      role: role ?? this.role,
      token: token ?? this.token,
      isMaster: isMaster ?? this.isMaster,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class LoginResult {
  final String token;
  final UserModel user;

  LoginResult({
    required this.token,
    required this.user,
  });

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    return LoginResult(
      token: json['token']?.toString() ?? '',
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
    );
  }
}
