import 'package:flutter/material.dart';
import '../models/config_model.dart';
import '../services/api_service.dart';

class StorageProvider extends ChangeNotifier {
  SystemConfig? _config;
  List<StoragePoolInfo> _storagePools = [];
  List<String> _allowedPaths = [];
  String _trashDir = '/volume1/.trash';
  int _trashRetentionDays = 30;

  bool _isLoading = false;
  String? _errorMessage;

  SystemConfig? get config => _config;
  List<StoragePoolInfo> get storagePools => _storagePools;
  List<String> get allowedPaths => _allowedPaths;
  String get trashDir => _trashDir;
  int get trashRetentionDays => _trashRetentionDays;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// 加载存储配置与存储池容量
  Future<void> loadConfig() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.instance.getConfig();
      _config = res.config;
      _storagePools = res.storagePools;
      _allowedPaths = res.config.allowedPaths;
      _trashDir = res.config.trashDir;
      _trashRetentionDays = res.config.trashRetentionDays;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = '获取存储信息失败: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 添加白名单路径
  Future<bool> addWhitelist(String path) async {
    if (path.trim().isEmpty) return false;
    try {
      final success = await ApiService.instance.addWhitelistPath(path.trim());
      if (success) {
        if (!_allowedPaths.contains(path.trim())) {
          _allowedPaths.add(path.trim());
        }
        await loadConfig(); // 重新刷新容量状态
        return true;
      }
    } catch (e) {
      _errorMessage = '添加白名单失败: $e';
      notifyListeners();
    }
    return false;
  }

  /// 移除白名单路径
  Future<bool> removeWhitelist(String path) async {
    try {
      final success = await ApiService.instance.removeWhitelistPath(path);
      if (success) {
        _allowedPaths.remove(path);
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = '移除白名单失败: $e';
      notifyListeners();
    }
    return false;
  }
}
