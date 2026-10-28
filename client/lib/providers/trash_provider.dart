import 'package:flutter/material.dart';
import '../models/trash_model.dart';
import '../services/api_service.dart';

class TrashProvider extends ChangeNotifier {
  List<TrashItem> _items = [];
  int _total = 0;
  int _page = 1;
  int _limit = 20;
  String _keyword = '';

  bool _isLoading = false;
  String? _errorMessage;

  List<TrashItem> get items => _items;
  int get total => _total;
  int get page => _page;
  int get limit => _limit;
  String get keyword => _keyword;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get totalPages => (_total / _limit).ceil().clamp(1, 9999);

  /// 加载回收站条目
  Future<void> loadTrash({int? page, String? keyword}) async {
    if (page != null) _page = page;
    if (keyword != null) _keyword = keyword;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.instance.getTrashList(
        keyword: _keyword,
        page: _page,
        limit: _limit,
      );
      _items = res.items;
      _total = res.total;
      _page = res.page;
      _limit = res.limit;
    } catch (e) {
      _errorMessage = '获取回收站列表失败: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 一键原路恢复文件
  Future<bool> restoreFile(String fileId, [String? customDir]) async {
    try {
      final success = await ApiService.instance.restoreTrashFile(fileId, customDir);
      if (success) {
        _items.removeWhere((item) => item.fileId == fileId);
        _total = (_total - 1).clamp(0, 999999);
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = '恢复文件失败: $e';
      notifyListeners();
    }
    return false;
  }

  /// 彻底删除文件
  Future<bool> deleteFile(String fileId) async {
    try {
      final success = await ApiService.instance.deleteTrashFile(fileId);
      if (success) {
        _items.removeWhere((item) => item.fileId == fileId);
        _total = (_total - 1).clamp(0, 999999);
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = '彻底删除文件失败: $e';
      notifyListeners();
    }
    return false;
  }

  /// 清空回收站
  Future<bool> emptyTrash() async {
    try {
      await ApiService.instance.emptyTrash();
      _items.clear();
      _total = 0;
      _page = 1;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '清空回收站失败: $e';
      notifyListeners();
      return false;
    }
  }
}
