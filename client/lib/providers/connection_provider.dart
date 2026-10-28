import 'package:flutter/material.dart';
import '../core/utils/formatters.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/websocket_service.dart';

class ConnectionProvider extends ChangeNotifier {
  String _host = '';
  int _port = 8000;
  String _token = '';
  bool _isHttps = false;
  AuthType _authType = AuthType.token;
  String _username = '';
  String _password = '';

  UserModel? _currentUser;
  bool _isChecking = false;
  bool _isConnected = false;
  bool _wasConnected = false;
  String? _errorMessage;

  ConnectionProvider() {
    _loadFromStorage();
  }

  String get host => _host;
  int get port => _port;
  String get token => _token;
  bool get isHttps => _isHttps;
  AuthType get authType => _authType;
  String get username => _username;
  String get password => _password;
  UserModel? get currentUser => _currentUser;

  /// 是否具备管理员操作权限：
  /// 1. 当前获取到的用户对象具有 admin 权限或 master 标识
  /// 2. 使用安全令牌 (Token) 接入时默认具备最高超级管理员权限
  bool get isAdmin {
    if (_currentUser != null) {
      return _currentUser!.isAdmin;
    }
    return authType == AuthType.token && token.isNotEmpty;
  }

  bool get isChecking => _isChecking;
  bool get isConnected => _isConnected;
  bool get wasConnected => _wasConnected;
  String? get errorMessage => _errorMessage;

  void clearErrorMessage() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  void _loadFromStorage() {
    _host = StorageService.getHost();
    _port = StorageService.getPort();
    _token = StorageService.getToken();
    _isHttps = StorageService.getIsHttps();
    _authType = StorageService.getAuthType();
    _username = StorageService.getUsername();
    _password = StorageService.getPassword();
    _wasConnected = StorageService.getWasConnected();
    _isConnected = _wasConnected;

    if (_isConnected) {
      final savedRole = UserRole.fromString(StorageService.getUserRole());
      _currentUser = UserModel(
        id: savedRole == UserRole.admin ? 'admin' : 'user',
        username: _username.isNotEmpty
            ? _username
            : (savedRole == UserRole.admin ? 'Master 管理员' : '当前用户'),
        role: savedRole,
        isMaster: _authType == AuthType.token && savedRole == UserRole.admin,
      );
      _fetchCurrentIdentity();
    }
  }

  Future<void> _fetchCurrentIdentity() async {
    try {
      final user = await ApiService.instance.getMe();
      if (_isConnected) {
        _currentUser = user;
        await StorageService.updateUserRole(user.role.value);
        notifyListeners();
      }
    } catch (e) {
      if (_isChecking) return;
      _isConnected = false;
      _wasConnected = false;
      _currentUser = null;
      await StorageService.setWasConnected(false);
      _errorMessage = Formatters.formatErrorMessage(e, '登录凭证已失效，请重新连接');
      notifyListeners();
    }
  }

  /// 测试与连接 NAS 服务端 (支持 Token 模式与用户名密码双模式)
  Future<bool> connect({
    required String host,
    required int port,
    String token = '',
    bool isHttps = false,
    AuthType authType = AuthType.token,
    String username = '',
    String password = '',
  }) async {
    _isChecking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      String effectiveToken = token.trim();
      UserModel? resolvedUser;

      // 1. 如果采用账号密码认证方式，先请求 /auth/login 获取用户 Token 与身份
      if (authType == AuthType.credentials) {
        if (username.trim().isNotEmpty && password.trim().isNotEmpty) {
          // 临时保存 host/port/https 供 baseUrl 生效（保留当前 effectiveToken 避免并发请求丢失鉴权）
          await StorageService.saveConnectionConfig(
            host: host,
            port: port,
            token: effectiveToken,
            isHttps: isHttps,
            authType: authType,
            username: username,
            password: password,
          );

          final loginRes = await ApiService.instance.login(username, password);
          effectiveToken = loginRes.token;
          resolvedUser = loginRes.user;
        } else if (effectiveToken.isEmpty) {
          throw Exception('用户名和密码不能为空');
        }
      }

      // 2. 保存完整连接配置供全局使用
      await StorageService.saveConnectionConfig(
        host: host,
        port: port,
        token: effectiveToken,
        isHttps: isHttps,
        authType: authType,
        username: username,
        password: password,
        userRole: resolvedUser?.role.value ?? StorageService.getUserRole(),
      );

      _host = host;
      _port = port;
      _token = effectiveToken;
      _isHttps = isHttps;
      _authType = authType;
      _username = username;
      _password = password;
      if (resolvedUser != null) {
        _currentUser = resolvedUser;
      }

      // 3. 服务健康检查
      final healthy = await ApiService.instance.checkHealth();
      if (!healthy) {
        _isConnected = false;
        _wasConnected = false;
        await StorageService.setWasConnected(false);
        _errorMessage = '无法连接到 NAS 服务端，请检查 IP 与端口是否可访问';
        return false;
      }

      // 4. 强校验身份与安全凭据
      // 若提供了 Token（且尚未通过 login 拿到 resolvedUser），必须通过 /api/v1/auth/me 校验
      if (effectiveToken.isNotEmpty && resolvedUser == null) {
        try {
          _currentUser = await ApiService.instance.getMe();
          if (_currentUser != null) {
            await StorageService.updateUserRole(_currentUser!.role.value);
          }
        } catch (e) {
          _isConnected = false;
          _wasConnected = false;
          _currentUser = null;
          await StorageService.setWasConnected(false);
          _errorMessage = Formatters.formatErrorMessage(e, '安全令牌 (Token) 无效或凭据已过期');
          return false;
        }
      } else if (authType == AuthType.token && effectiveToken.isEmpty) {
        // 内网免密信任模式下尝试获取 Master 身份
        try {
          _currentUser = await ApiService.instance.getMe();
        } catch (_) {
          _currentUser = UserModel(
            id: 'master',
            username: 'Master 管理员',
            role: UserRole.admin,
            isMaster: true,
          );
        }
      }

      _isConnected = true;
      _wasConnected = true;
      _errorMessage = null;
      await StorageService.setWasConnected(true);

      // 保存到历史预设
      await StorageService.saveConnectionPreset(ConnectionPreset(
        host: host,
        port: port,
        token: effectiveToken,
        isHttps: isHttps,
        authType: authType,
        username: username,
        password: password,
      ));

      // 自动连接 WebSocket
      WebSocketService.instance.connect();
    } catch (e) {
      _isConnected = false;
      _wasConnected = false;
      await StorageService.setWasConnected(false);
      _errorMessage = Formatters.formatErrorMessage(e);
    } finally {
      _isChecking = false;
      notifyListeners();
    }
    return _isConnected;
  }

  /// 重新生成 Master Token 并自动使用新 Token 重连
  Future<bool> regenerateTokenAndReconnect() async {
    _isChecking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newToken = await ApiService.instance.regenerateMasterToken();
      if (newToken.isEmpty) {
        _errorMessage = '重新生成 Token 失败: 返回的 Token 为空';
        return false;
      }

      _token = newToken;
      await StorageService.updateToken(newToken);
      await StorageService.saveConnectionConfig(
        host: _host,
        port: _port,
        token: newToken,
        isHttps: _isHttps,
        authType: AuthType.token,
        username: _username,
        password: _password,
        userRole: 'ADMIN',
      );

      // 保存到历史预设
      await StorageService.saveConnectionPreset(ConnectionPreset(
        host: _host,
        port: _port,
        token: newToken,
        isHttps: _isHttps,
        authType: AuthType.token,
        username: _username,
        password: _password,
      ));

      // 验证连接与新 Token
      final healthy = await ApiService.instance.checkHealth();
      if (!healthy) {
        _isConnected = false;
        _wasConnected = false;
        await StorageService.setWasConnected(false);
        _errorMessage = '新 Token 已生成，但重新连接 NAS 服务端通信失败';
        return false;
      }

      try {
        _currentUser = await ApiService.instance.getMe();
      } catch (e) {
        _isConnected = false;
        _wasConnected = false;
        _currentUser = null;
        await StorageService.setWasConnected(false);
        _errorMessage = Formatters.formatErrorMessage(e, '新 Token 验证失败');
        return false;
      }

      _isConnected = true;
      _wasConnected = true;
      _errorMessage = null;
      await StorageService.setWasConnected(true);
      WebSocketService.instance.connect();
      return true;
    } catch (e) {
      _errorMessage = Formatters.formatErrorMessage(e, '重新生成 Token 失败');
      return false;
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  /// 静默刷新健康状态与当前身份
  Future<void> refreshHealth() async {
    try {
      final healthy = await ApiService.instance.checkHealth();
      if (!healthy) {
        _isConnected = false;
        _wasConnected = false;
        await StorageService.setWasConnected(false);
        _errorMessage = 'NAS 服务通信断开，无法连通目标服务';
        notifyListeners();
        return;
      }

      // 若当前为已连接状态，持续校验身份与凭证有效性
      if (_token.isNotEmpty || _authType == AuthType.credentials) {
        try {
          _currentUser = await ApiService.instance.getMe();
          _isConnected = true;
          _wasConnected = true;
          _errorMessage = null;
          await StorageService.setWasConnected(true);
        } catch (e) {
          _isConnected = false;
          _wasConnected = false;
          _currentUser = null;
          await StorageService.setWasConnected(false);
          _errorMessage = '认证凭据已失效或已变更，请重新连接';
          notifyListeners();
          return;
        }
      } else {
        _isConnected = true;
        _wasConnected = true;
        _errorMessage = null;
        await StorageService.setWasConnected(true);
      }
    } catch (e) {
      _isConnected = false;
      _wasConnected = false;
      await StorageService.setWasConnected(false);
      _errorMessage = Formatters.formatErrorMessage(e);
    }
    notifyListeners();
  }

  void disconnect() {
    _isConnected = false;
    _wasConnected = false;
    _currentUser = null;
    StorageService.setWasConnected(false);
    WebSocketService.instance.disconnect();
    notifyListeners();
  }
}
