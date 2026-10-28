import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';

class UserProvider extends ChangeNotifier {
  List<UserModel> _users = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<UserModel> get users => _users;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get adminCount => _users.where((u) => u.isAdmin).length;
  int get normalUserCount => _users.where((u) => !u.isAdmin).length;

  Future<void> loadUsers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _users = await ApiService.instance.getUsers();
    } catch (e) {
      _errorMessage = '获取用户列表失败: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createUser({
    required String username,
    required String password,
    required String role,
  }) async {
    try {
      final newUser = await ApiService.instance.createUser(
        username: username,
        password: password,
        role: role,
      );
      _users.insert(0, newUser);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '创建用户失败: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateUser(
    String userId, {
    String? password,
    String? role,
  }) async {
    try {
      final updated = await ApiService.instance.updateUser(
        userId,
        password: password,
        role: role,
      );
      final idx = _users.indexWhere((u) => u.id == userId);
      if (idx != -1) {
        _users[idx] = updated;
        notifyListeners();
      }
      return true;
    } catch (e) {
      _errorMessage = '更新用户失败: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteUser(String userId) async {
    try {
      final success = await ApiService.instance.deleteUser(userId);
      if (success) {
        _users.removeWhere((u) => u.id == userId);
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = '删除用户失败: $e';
      notifyListeners();
    }
    return false;
  }

  Future<String?> regenerateUserToken(String userId) async {
    try {
      final newToken = await ApiService.instance.regenerateUserToken(userId);
      final idx = _users.indexWhere((u) => u.id == userId);
      if (idx != -1) {
        _users[idx] = _users[idx].copyWith(token: newToken);
        notifyListeners();
      }
      return newToken;
    } catch (e) {
      _errorMessage = '重新生成 Token 失败: $e';
      notifyListeners();
      return null;
    }
  }
}
