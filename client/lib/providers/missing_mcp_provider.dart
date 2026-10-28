import 'package:flutter/foundation.dart';
import '../models/missing_mcp_model.dart';
import '../services/api_service.dart';

class MissingMcpProvider extends ChangeNotifier {
  List<MissingMcpToolModel> _items = [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;

  List<MissingMcpToolModel> get items => _items;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;

  void reset() {
    _items = [];
    _isLoading = false;
    _hasLoaded = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> loadItems() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _items = await ApiService.instance.getMissingMcpTools(limit: 100);
      _hasLoaded = true;
    } catch (e) {
      _errorMessage = '获取缺失接口记录失败: $e';
      _hasLoaded = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteItem(String id) async {
    try {
      final success = await ApiService.instance.deleteMissingMcpTool(id);
      if (success) {
        _items.removeWhere((item) => item.id == id);
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = '删除记录失败: $e';
      notifyListeners();
    }
    return false;
  }

  Future<int> clearAll() async {
    try {
      final count = await ApiService.instance.clearMissingMcpTools();
      if (count > 0) {
        _items.clear();
        notifyListeners();
      }
      return count;
    } catch (e) {
      _errorMessage = '清空记录失败: $e';
      notifyListeners();
      return 0;
    }
  }
}
