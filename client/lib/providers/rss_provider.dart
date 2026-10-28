import 'package:flutter/material.dart';
import '../models/rss_model.dart';
import '../services/api_service.dart';

class RssProvider extends ChangeNotifier {
  final ApiService _apiService;

  RssProvider({ApiService? apiService}) : _apiService = apiService ?? ApiService.instance;

  List<RssSubscriptionModel> _subscriptions = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<RssSubscriptionModel> get subscriptions => _subscriptions;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// 加载所有 RSS 订阅
  Future<void> loadSubscriptions() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _subscriptions = await _apiService.getRssSubscriptions();
    } catch (e) {
      _errorMessage = '获取 RSS 订阅列表失败: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 在线预览并测试过滤规则
  Future<RssPreviewResponse?> previewFeed({
    required String feedUrl,
    List<RssFilterRule>? filterRules,
    Map<String, dynamic>? urlExtractRule,
  }) async {
    try {
      return await _apiService.previewRssFeed(
        feedUrl: feedUrl,
        filterRules: filterRules,
        urlExtractRule: urlExtractRule,
      );
    } catch (e) {
      _errorMessage = '解析 RSS 失败: $e';
      notifyListeners();
      return null;
    }
  }

  /// 创建 RSS 订阅
  Future<RssSubscriptionModel?> createSubscription({
    required String feedUrl,
    required String saveDir,
    String? title,
    List<RssFilterRule>? filterRules,
    Map<String, dynamic>? urlExtractRule,
    int checkIntervalMinutes = 15,
    String downloadEngine = 'auto',
    List<String>? selectedGuids,
    bool downloadExisting = true,
    String? agentTaskId,
  }) async {
    try {
      final sub = await _apiService.createRssSubscription(
        feedUrl: feedUrl,
        saveDir: saveDir,
        title: title,
        filterRules: filterRules,
        urlExtractRule: urlExtractRule,
        checkIntervalMinutes: checkIntervalMinutes,
        downloadEngine: downloadEngine,
        selectedGuids: selectedGuids,
        downloadExisting: downloadExisting,
        agentTaskId: agentTaskId,
      );
      _subscriptions.insert(0, sub);
      notifyListeners();
      return sub;
    } catch (e) {
      _errorMessage = '创建 RSS 订阅失败: $e';
      notifyListeners();
      return null;
    }
  }

  /// 获取单个 RSS 订阅最新详情
  Future<RssSubscriptionModel?> getDetail(String rssId) async {
    try {
      final sub = await _apiService.getRssSubscriptionDetail(rssId);
      final idx = _subscriptions.indexWhere((s) => s.rssId == rssId);
      if (idx != -1) {
        _subscriptions[idx] = sub;
        notifyListeners();
      }
      return sub;
    } catch (e) {
      _errorMessage = '获取 RSS 详情失败: $e';
      notifyListeners();
      return null;
    }
  }

  /// 立即强制刷新检查
  Future<bool> refreshSubscription(String rssId) async {
    try {
      await _apiService.refreshRssSubscription(rssId);
      await getDetail(rssId);
      return true;
    } catch (e) {
      _errorMessage = '刷新 RSS 任务失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 切换启用/暂停
  Future<bool> toggleSubscription(String rssId) async {
    try {
      final enabled = await _apiService.toggleRssSubscription(rssId);
      final idx = _subscriptions.indexWhere((s) => s.rssId == rssId);
      if (idx != -1) {
        final old = _subscriptions[idx];
        _subscriptions[idx] = RssSubscriptionModel(
          rssId: old.rssId,
          title: old.title,
          feedUrl: old.feedUrl,
          saveDir: old.saveDir,
          filterRules: old.filterRules,
          urlExtractRule: old.urlExtractRule,
          checkIntervalMinutes: old.checkIntervalMinutes,
          downloadEngine: old.downloadEngine,
          enabled: enabled,
          lastCheckedAt: old.lastCheckedAt,
          lastError: old.lastError,
          totalDownloadedCount: old.totalDownloadedCount,
          downloadedGuids: old.downloadedGuids,
          downloadHistory: old.downloadHistory,
          agentTaskId: old.agentTaskId,
          subtitleLanguage: old.subtitleLanguage,
          createdAt: old.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch / 1000.0,
        );
        notifyListeners();
      }
      return enabled;
    } catch (e) {
      _errorMessage = '切换状态失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 更新 RSS 订阅配置（包括下载目录、标题、规则、轮询周期等）
  Future<RssSubscriptionModel?> updateSubscription({
    required String rssId,
    String? title,
    String? saveDir,
    List<RssFilterRule>? filterRules,
    int? checkIntervalMinutes,
    String? downloadEngine,
    bool? enabled,
    String? subtitleLanguage,
  }) async {
    try {
      final updated = await _apiService.updateRssSubscription(
        rssId: rssId,
        title: title,
        saveDir: saveDir,
        filterRules: filterRules,
        checkIntervalMinutes: checkIntervalMinutes,
        downloadEngine: downloadEngine,
        enabled: enabled,
        subtitleLanguage: subtitleLanguage,
      );
      final idx = _subscriptions.indexWhere((s) => s.rssId == rssId);
      if (idx != -1) {
        _subscriptions[idx] = updated;
        notifyListeners();
      }
      return updated;
    } catch (e) {
      _errorMessage = '更新 RSS 订阅失败: $e';
      notifyListeners();
      return null;
    }
  }

  /// 删除 RSS 订阅
  Future<bool> deleteSubscription(String rssId) async {
    try {
      final ok = await _apiService.deleteRssSubscription(rssId);
      if (ok) {
        _subscriptions.removeWhere((s) => s.rssId == rssId);
        notifyListeners();
      }
      return ok;
    } catch (e) {
      _errorMessage = '删除 RSS 订阅失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 获取指定 RSS 订阅当前远端的全部资源列表
  Future<RssSubscriptionItemsResponse?> fetchSubscriptionItems(String rssId) async {
    try {
      return await _apiService.getRssSubscriptionItems(rssId);
    } catch (e) {
      _errorMessage = '获取 RSS 资源列表失败: $e';
      notifyListeners();
      return null;
    }
  }

  /// 选摘下载指定的 RSS 资源条目，并刷新订阅统计
  Future<RssBatchDownloadResult?> downloadSubscriptionItems({
    required String rssId,
    required List<RssItemPreview> items,
  }) async {
    try {
      final result = await _apiService.downloadRssSubscriptionItems(
        rssId: rssId,
        items: items,
      );
      // 成功派发后刷新订阅详情以同步最新的下载计数与历史
      await getDetail(rssId);
      return result;
    } catch (e) {
      _errorMessage = '派发下载失败: $e';
      notifyListeners();
      return null;
    }
  }
}
