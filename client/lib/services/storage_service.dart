import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/api_constants.dart';

enum AuthType {
  token('token', '安全令牌'),
  credentials('credentials', '账号密码');

  final String value;
  final String label;
  const AuthType(this.value, this.label);

  static AuthType fromString(String? val) {
    if (val == 'credentials') return AuthType.credentials;
    return AuthType.token;
  }
}

class ConnectionPreset {
  final String host;
  final int port;
  final String token;
  final bool isHttps;
  final AuthType authType;
  final String? username;
  final String? password;
  final String? label;
  final int updatedAt;

  ConnectionPreset({
    required this.host,
    required this.port,
    required this.token,
    this.isHttps = false,
    this.authType = AuthType.token,
    this.username,
    this.password,
    this.label,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  String get displayTitle {
    if (label != null && label!.isNotEmpty) return label!;
    if (authType == AuthType.credentials && username != null && username!.isNotEmpty) {
      return '$username@$host:$port';
    }
    return '$host:$port';
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'token': token,
        'is_https': isHttps,
        'auth_type': authType.value,
        'username': username,
        'password': password,
        'label': label,
        'updated_at': updatedAt,
      };

  factory ConnectionPreset.fromJson(Map<String, dynamic> json) => ConnectionPreset(
        host: json['host']?.toString() ?? '',
        port: (json['port'] as num?)?.toInt() ?? 8000,
        token: json['token']?.toString() ?? '',
        isHttps: json['is_https'] == true,
        authType: AuthType.fromString(json['auth_type']?.toString()),
        username: json['username']?.toString(),
        password: json['password']?.toString(),
        label: json['label']?.toString(),
        updatedAt: (json['updated_at'] as num?)?.toInt(),
      );
}

class StorageService {
  static const String _keyHost = 'nasio_host';
  static const String _keyPort = 'nasio_port';
  static const String _keyToken = 'nasio_token';
  static const String _keyIsHttps = 'nasio_https';
  static const String _keyAuthType = 'nasio_auth_type';
  static const String _keyUsername = 'nasio_username';
  static const String _keyPassword = 'nasio_password';
  static const String _keyUserRole = 'nasio_user_role';
  static const String _keyWasConnected = 'nasio_was_connected';
  static const String _keyConnectionHistory = 'nasio_connection_history';
  static const String _keyThemeMode = 'nasio_theme_mode';
  static const String _keyGiteaUrl = 'nasio_gitea_url';
  static const String _keyHomeLayout = 'nasio_home_layout';
  static const String defaultGiteaUrl = '';

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    final history = getConnectionHistory();
    if (history.isEmpty) {
      final savedHost = _prefs?.getString(_keyHost);
      final savedPort = _prefs?.getInt(_keyPort);
      if (savedHost != null && savedHost.isNotEmpty) {
        saveConnectionPreset(ConnectionPreset(
          host: savedHost,
          port: savedPort ?? 8000,
          token: getToken(),
          isHttps: getIsHttps(),
          authType: getAuthType(),
          username: getUsername(),
          password: getPassword(),
        ));
      }
    }
  }

  static String getHost() {
    final saved = _prefs?.getString(_keyHost);
    if (saved != null && saved.isNotEmpty) return saved;
    if (kIsWeb && Uri.base.host.isNotEmpty && Uri.base.host != 'localhost') {
      return Uri.base.host;
    }
    return ApiConstants.defaultHost;
  }

  static int getPort() {
    final saved = _prefs?.getInt(_keyPort);
    if (saved != null) return saved;
    if (kIsWeb && Uri.base.hasPort && Uri.base.port != 0) {
      return Uri.base.port;
    }
    return ApiConstants.defaultPort;
  }

  static String getToken() {
    return _prefs?.getString(_keyToken) ?? ApiConstants.defaultToken;
  }

  static bool getIsHttps() {
    final saved = _prefs?.getBool(_keyIsHttps);
    if (saved != null) return saved;
    if (kIsWeb && Uri.base.scheme == 'https') return true;
    return false;
  }

  static AuthType getAuthType() {
    final saved = _prefs?.getString(_keyAuthType);
    return AuthType.fromString(saved);
  }

  static String getUsername() {
    return _prefs?.getString(_keyUsername) ?? '';
  }

  static String getPassword() {
    return _prefs?.getString(_keyPassword) ?? '';
  }

  static String getUserRole() {
    return _prefs?.getString(_keyUserRole) ?? 'ADMIN';
  }

  static bool getWasConnected() {
    if (_prefs?.containsKey(_keyWasConnected) == true) {
      return _prefs!.getBool(_keyWasConnected) ?? false;
    }
    final savedHost = _prefs?.getString(_keyHost);
    return savedHost != null && savedHost.isNotEmpty;
  }

  static Future<void> setWasConnected(bool value) async {
    await _prefs?.setBool(_keyWasConnected, value);
  }

  static Future<void> saveConnectionConfig({
    required String host,
    required int port,
    required String token,
    bool isHttps = false,
    AuthType authType = AuthType.token,
    String username = '',
    String password = '',
    String userRole = 'ADMIN',
  }) async {
    await _prefs?.setString(_keyHost, host.trim());
    await _prefs?.setInt(_keyPort, port);
    await _prefs?.setString(_keyToken, token.trim());
    await _prefs?.setBool(_keyIsHttps, isHttps);
    await _prefs?.setString(_keyAuthType, authType.value);
    await _prefs?.setString(_keyUsername, username.trim());
    await _prefs?.setString(_keyPassword, password.trim());
    await _prefs?.setString(_keyUserRole, userRole.trim());
  }

  static Future<void> updateToken(String token) async {
    await _prefs?.setString(_keyToken, token.trim());
  }

  static Future<void> updateUserRole(String role) async {
    await _prefs?.setString(_keyUserRole, role.trim());
  }

  static List<ConnectionPreset> getConnectionHistory() {
    final raw = _prefs?.getString(_keyConnectionHistory);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>?;
      if (list == null) return [];
      return list
          .map((e) => ConnectionPreset.fromJson(e as Map<String, dynamic>))
          .where((e) => e.host.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveConnectionPreset(ConnectionPreset preset) async {
    if (preset.host.trim().isEmpty) return;
    final history = getConnectionHistory();
    history.removeWhere((e) => e.host == preset.host.trim() && e.port == preset.port);
    history.insert(0, preset);
    if (history.length > 20) {
      history.removeRange(20, history.length);
    }
    final raw = jsonEncode(history.map((e) => e.toJson()).toList());
    await _prefs?.setString(_keyConnectionHistory, raw);
  }

  static Future<void> removeConnectionPreset(String host, int port) async {
    final history = getConnectionHistory();
    history.removeWhere((e) => e.host == host && e.port == port);
    final raw = jsonEncode(history.map((e) => e.toJson()).toList());
    await _prefs?.setString(_keyConnectionHistory, raw);
  }

  static String getBaseUrl() {
    final scheme = getIsHttps() ? 'https' : 'http';
    return '$scheme://${getHost()}:${getPort()}';
  }

  static String getWsUrl() {
    final scheme = getIsHttps() ? 'wss' : 'ws';
    final token = getToken();
    final tokenParam = token.isNotEmpty ? '?token=$token' : '';
    return '$scheme://${getHost()}:${getPort()}${ApiConstants.wsTasksPath}$tokenParam';
  }

  static ThemeMode getThemeMode() {
    final saved = _prefs?.getString(_keyThemeMode);
    switch (saved) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    String val;
    switch (mode) {
      case ThemeMode.light:
        val = 'light';
        break;
      case ThemeMode.dark:
        val = 'dark';
        break;
      case ThemeMode.system:
        val = 'system';
        break;
    }
    await _prefs?.setString(_keyThemeMode, val);
  }

  static String getGiteaUrl() {
    final saved = _prefs?.getString(_keyGiteaUrl);
    if (saved != null && saved.trim().isNotEmpty) return saved.trim();
    return defaultGiteaUrl;
  }

  static Future<void> setGiteaUrl(String url) async {
    await _prefs?.setString(_keyGiteaUrl, url.trim());
  }

  static String? getHomeLayoutRaw() {
    return _prefs?.getString(_keyHomeLayout);
  }

  static Future<void> saveHomeLayoutRaw(String rawJson) async {
    await _prefs?.setString(_keyHomeLayout, rawJson);
  }

  static Future<void> resetHomeLayout() async {
    await _prefs?.remove(_keyHomeLayout);
  }
}
