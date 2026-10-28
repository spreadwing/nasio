import 'package:flutter/material.dart';
import '../models/home_layout_model.dart';
import '../services/storage_service.dart';

class HomeLayoutProvider extends ChangeNotifier {
  List<HomeFeatureItem> _features = List.of(HomeLayoutDefaults.defaultFeatures);
  List<HomeNavItem> _navItems = List.of(HomeLayoutDefaults.defaultNavItems);
  List<HomeCardItem> _cards = List.of(HomeLayoutDefaults.defaultCards);

  List<HomeFeatureItem> get features => _features;
  List<HomeNavItem> get navItems => _navItems;
  List<HomeCardItem> get cards => _cards;

  List<HomeFeatureItem> get activeFeatures => _features.where((f) => f.enabled).toList();
  List<HomeNavItem> get activeNavItems => _navItems.where((n) => n.enabled).toList();
  List<HomeCardItem> get activeCards => _cards.where((c) => c.enabled).toList();

  HomeLayoutProvider() {
    loadLayout();
  }

  /// 从本地持久化存储加载主页布局配置
  void loadLayout() {
    final raw = StorageService.getHomeLayoutRaw();
    if (raw != null && raw.isNotEmpty) {
      final config = HomeLayoutConfig.fromJsonString(raw);
      _features = List.of(config.features);
      _navItems = List.of(config.navItems);
      _cards = List.of(config.cards);
    } else {
      _features = List.of(HomeLayoutDefaults.defaultFeatures);
      _navItems = List.of(HomeLayoutDefaults.defaultNavItems);
      _cards = List.of(HomeLayoutDefaults.defaultCards);
    }
    notifyListeners();
  }

  /// 保存当前布局到本地
  Future<void> saveLayout() async {
    final config = HomeLayoutConfig(features: _features, navItems: _navItems, cards: _cards);
    await StorageService.saveHomeLayoutRaw(config.toJsonString());
  }

  /// 切换功能入口显示状态
  void toggleFeature(String id, bool enabled) {
    final index = _features.indexWhere((f) => f.id == id);
    if (index != -1) {
      _features[index] = _features[index].copyWith(enabled: enabled);
      notifyListeners();
      saveLayout();
    }
  }

  /// 切换侧边栏/底部导航栏显隐（必须保留至少 2 项启用以满足 Navigation 规范）
  bool toggleNavItem(String id, bool enabled) {
    final index = _navItems.indexWhere((n) => n.id == id);
    if (index != -1) {
      if (_navItems[index].isFixed) {
        return false;
      }
      if (!enabled && activeNavItems.length <= 2) {
        return false;
      }
      _navItems[index] = _navItems[index].copyWith(enabled: enabled);
      notifyListeners();
      saveLayout();
      return true;
    }
    return false;
  }

  /// 切换资源看板卡片显示状态
  void toggleCard(String id, bool enabled) {
    final index = _cards.indexWhere((c) => c.id == id);
    if (index != -1) {
      _cards[index] = _cards[index].copyWith(enabled: enabled);
      notifyListeners();
      saveLayout();
    }
  }

  /// 调整功能入口排序
  void reorderFeatures(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _features.removeAt(oldIndex);
    _features.insert(newIndex, item);
    notifyListeners();
    saveLayout();
  }

  /// 调整导航项排序（主页始终锁定首位）
  void reorderNavItems(int oldIndex, int newIndex) {
    if (oldIndex == 0) return;
    if (newIndex == 0) newIndex = 1;
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (newIndex == 0) newIndex = 1;
    final item = _navItems.removeAt(oldIndex);
    _navItems.insert(newIndex, item);
    notifyListeners();
    saveLayout();
  }

  /// 调整看板卡片排序
  void reorderCards(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _cards.removeAt(oldIndex);
    _cards.insert(newIndex, item);
    notifyListeners();
    saveLayout();
  }

  /// 一键恢复默认布局与排序
  Future<void> resetToDefault() async {
    _features = List.of(HomeLayoutDefaults.defaultFeatures);
    _navItems = List.of(HomeLayoutDefaults.defaultNavItems);
    _cards = List.of(HomeLayoutDefaults.defaultCards);
    await StorageService.resetHomeLayout();
    notifyListeners();
  }
}
