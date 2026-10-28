import 'package:flutter/material.dart';
import '../models/task_model.dart';
import '../models/downloader_config_model.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

class TaskProvider extends ChangeNotifier {
  final Map<String, TaskItem> _tasksMap = {};
  bool _isLoading = false;
  String? _errorMessage;

  Map<String, dynamic>? _downloaderStatus;
  bool _isTestingDownloader = false;

  DownloaderConfigModel? _downloaderConfig;
  bool _isLoadingConfig = false;

  TaskProvider() {
    // 监听 WebSocket 实时任务更新
    WebSocketService.instance.addListener(_handleWsEvent);
  }

  @override
  void dispose() {
    WebSocketService.instance.removeListener(_handleWsEvent);
    super.dispose();
  }

  List<TaskItem> get allTasks {
    final list = _tasksMap.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<TaskItem> get activeTasks {
    return allTasks
        .where((t) =>
            t.status == TaskStatus.running ||
            t.status == TaskStatus.pending ||
            t.status == TaskStatus.paused)
        .toList();
  }

  List<TaskItem> get completedTasks {
    return allTasks
        .where((t) =>
            t.status == TaskStatus.completed ||
            t.status == TaskStatus.failed ||
            t.status == TaskStatus.cancelled)
        .toList();
  }

  List<TaskItem> get failedTasks {
    return allTasks.where((t) => t.status == TaskStatus.failed).toList();
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get downloaderStatus => _downloaderStatus;
  bool get isTestingDownloader => _isTestingDownloader;
  DownloaderConfigModel? get downloaderConfig => _downloaderConfig;
  bool get isLoadingConfig => _isLoadingConfig;

  /// 根据任务 ID 获取任务实例
  TaskItem? getTaskById(String taskId) => _tasksMap[taskId];


  final Map<String, DateTime> _optimisticLocks = {};

  /// 加载所有长任务
  Future<void> loadTasks({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final items = await ApiService.instance.getTasks();
      final now = DateTime.now();
      _optimisticLocks.removeWhere((_, expire) => now.isAfter(expire));

      final newIds = items.map((e) => e.taskId).toSet();
      _tasksMap.removeWhere((id, _) => !newIds.contains(id));

      for (final item in items) {
        if (_optimisticLocks.containsKey(item.taskId) &&
            now.isBefore(_optimisticLocks[item.taskId]!)) {
          final existing = _tasksMap[item.taskId];
          if (existing != null) {
            item.status = existing.status;
            item.detail['state'] = existing.detail['state'];
            if (existing.status == TaskStatus.paused) {
              item.detail['speed'] = '0 B/s';
            }
          }
        }
        _tasksMap[item.taskId] = item;
      }
    } catch (e) {
      if (!silent) {
        _errorMessage = '获取任务列表失败: $e';
      }
    } finally {
      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  /// 处理 WebSocket 推送的 TASK_UPDATE / TASK_PROGRESS 事件
  void _handleWsEvent(Map<String, dynamic> event) {
    final eventName = event['event'];
    final data = event['data'] as Map<String, dynamic>?;
    if ((eventName == 'TASK_UPDATE' || eventName == 'TASK_PROGRESS') && data != null) {
      final taskId = data['task_id']?.toString();
      if (taskId != null) {
        final now = DateTime.now();
        if (_optimisticLocks.containsKey(taskId) && now.isBefore(_optimisticLocks[taskId]!)) {
          // 乐观锁定中，保留乐观状态，仅合入进度与其它字段
          if (_tasksMap.containsKey(taskId)) {
            final currentStatus = _tasksMap[taskId]!.status;
            final currentState = _tasksMap[taskId]!.detail['state'];
            _tasksMap[taskId]!.updateFromWs(data);
            _tasksMap[taskId]!.status = currentStatus;
            _tasksMap[taskId]!.detail['state'] = currentState;
            if (currentStatus == TaskStatus.paused) {
              _tasksMap[taskId]!.detail['speed'] = '0 B/s';
            }
            notifyListeners();
            return;
          }
        }
        if (_tasksMap.containsKey(taskId)) {
          _tasksMap[taskId]!.updateFromWs(data);
        } else {
          // 动态注册新任务
          _tasksMap[taskId] = TaskItem.fromJson(data);
        }
        notifyListeners();
      }
    }
  }

  /// 创建下载任务
  Future<bool> createTask({
    required String url,
    required String saveDir,
    String? filename,
  }) async {
    try {
      await ApiService.instance.createTask(
        url: url,
        saveDir: saveDir,
        filename: filename,
      );
      await loadTasks();
      return true;
    } catch (e) {
      _errorMessage = '创建任务失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 取消/删除任务
  Future<bool> cancelTask(String taskId, {bool deleteFiles = false}) async {
    try {
      final success = await ApiService.instance.cancelTask(taskId, deleteFiles: deleteFiles);
      if (success) {
        if (deleteFiles) {
          _tasksMap.remove(taskId);
        } else if (_tasksMap.containsKey(taskId)) {
          _tasksMap[taskId] = TaskItem(
            taskId: taskId,
            taskType: _tasksMap[taskId]!.taskType,
            status: TaskStatus.cancelled,
            progress: _tasksMap[taskId]!.progress,
            createdAt: _tasksMap[taskId]!.createdAt,
            updatedAt: DateTime.now().millisecondsSinceEpoch / 1000.0,
            detail: _tasksMap[taskId]!.detail,
          );
        }
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = '取消任务失败: $e';
      notifyListeners();
    }
    return false;
  }

  /// 暂停任务
  Future<bool> pauseTask(String taskId) async {
    // 1. 立即乐观更新 (0ms 界面响应)
    _optimisticLocks[taskId] = DateTime.now().add(const Duration(milliseconds: 3000));
    if (_tasksMap.containsKey(taskId)) {
      final t = _tasksMap[taskId]!;
      t.status = TaskStatus.paused;
      t.detail['state'] = 'stoppedDL';
      t.detail['speed'] = '0 B/s';
      notifyListeners();
    }

    try {
      final success = await ApiService.instance.pauseTask(taskId);
      if (!success) {
        _optimisticLocks.remove(taskId);
        await loadTasks(silent: true);
        return false;
      }
      Future.delayed(const Duration(milliseconds: 2000), () => loadTasks(silent: true));
      return true;
    } catch (e) {
      _optimisticLocks.remove(taskId);
      _errorMessage = '暂停任务失败: $e';
      await loadTasks(silent: true);
      notifyListeners();
    }
    return false;
  }

  /// 恢复任务
  Future<bool> resumeTask(String taskId) async {
    // 1. 立即乐观更新 (0ms 界面响应)
    _optimisticLocks[taskId] = DateTime.now().add(const Duration(milliseconds: 3000));
    if (_tasksMap.containsKey(taskId)) {
      final t = _tasksMap[taskId]!;
      t.status = TaskStatus.running;
      t.detail['state'] = 'downloading';
      notifyListeners();
    }

    try {
      final success = await ApiService.instance.resumeTask(taskId);
      if (!success) {
        _optimisticLocks.remove(taskId);
        await loadTasks(silent: true);
        return false;
      }
      Future.delayed(const Duration(milliseconds: 2000), () => loadTasks(silent: true));
      return true;
    } catch (e) {
      _optimisticLocks.remove(taskId);
      _errorMessage = '恢复任务失败: $e';
      await loadTasks(silent: true);
      notifyListeners();
    }
    return false;
  }

  /// 重新校验种子
  Future<bool> recheckTask(String taskId) async {
    try {
      final success = await ApiService.instance.recheckTask(taskId);
      if (success) {
        await loadTasks();
        return true;
      }
    } catch (e) {
      _errorMessage = '重新校验失败: $e';
      notifyListeners();
    }
    return false;
  }

  /// 删除任务
  Future<bool> deleteTask(String taskId, {bool deleteFiles = false}) async {
    try {
      final success = await ApiService.instance.deleteTask(taskId, deleteFiles: deleteFiles);
      if (success) {
        _tasksMap.remove(taskId);
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = '删除任务失败: $e';
      notifyListeners();
    }
    return false;
  }

  /// 一键清空所有失败任务
  Future<int> clearFailedTasks({bool deleteFiles = false}) async {
    try {
      int count = await ApiService.instance.clearFailedTasks(deleteFiles: deleteFiles);
      if (count <= 0) {
        // 服务端端点返回 0 或未部署时，降级采用并发逐个删除失败任务
        final failedList = failedTasks;
        if (failedList.isNotEmpty) {
          final results = await Future.wait(
            failedList.map((t) => ApiService.instance.deleteTask(t.taskId, deleteFiles: deleteFiles)),
          );
          count = results.where((r) => r).length;
        }
      }
      _tasksMap.removeWhere((_, item) => item.status == TaskStatus.failed);
      notifyListeners();
      return count;
    } catch (e) {
      _errorMessage = '清空失败任务失败: $e';
      notifyListeners();
      return 0;
    }
  }

  /// 批量暂停任务
  Future<bool> batchPauseTasks(List<String> taskIds) async {
    if (taskIds.isEmpty) return true;
    final lockUntil = DateTime.now().add(const Duration(milliseconds: 3000));
    for (final tid in taskIds) {
      _optimisticLocks[tid] = lockUntil;
      if (_tasksMap.containsKey(tid)) {
        final t = _tasksMap[tid]!;
        t.status = TaskStatus.paused;
        t.detail['state'] = 'stoppedDL';
        t.detail['speed'] = '0 B/s';
      }
    }
    notifyListeners();

    try {
      final success = await ApiService.instance.batchPauseTasks(taskIds);
      if (!success) {
        for (final tid in taskIds) {
          _optimisticLocks.remove(tid);
        }
        await loadTasks(silent: true);
        return false;
      }
      Future.delayed(const Duration(milliseconds: 2000), () => loadTasks(silent: true));
      return true;
    } catch (e) {
      for (final tid in taskIds) {
        _optimisticLocks.remove(tid);
      }
      _errorMessage = '批量暂停失败: $e';
      await loadTasks(silent: true);
      notifyListeners();
    }
    return false;
  }

  /// 批量恢复任务
  Future<bool> batchResumeTasks(List<String> taskIds) async {
    if (taskIds.isEmpty) return true;
    final lockUntil = DateTime.now().add(const Duration(milliseconds: 3000));
    for (final tid in taskIds) {
      _optimisticLocks[tid] = lockUntil;
      if (_tasksMap.containsKey(tid)) {
        final t = _tasksMap[tid]!;
        t.status = TaskStatus.running;
        t.detail['state'] = 'downloading';
      }
    }
    notifyListeners();

    try {
      final success = await ApiService.instance.batchResumeTasks(taskIds);
      if (!success) {
        for (final tid in taskIds) {
          _optimisticLocks.remove(tid);
        }
        await loadTasks(silent: true);
        return false;
      }
      Future.delayed(const Duration(milliseconds: 2000), () => loadTasks(silent: true));
      return true;
    } catch (e) {
      for (final tid in taskIds) {
        _optimisticLocks.remove(tid);
      }
      _errorMessage = '批量恢复失败: $e';
      await loadTasks(silent: true);
      notifyListeners();
    }
    return false;
  }

  /// 批量删除任务
  Future<bool> batchDeleteTasks(List<String> taskIds, {bool deleteFiles = false}) async {
    try {
      final success = await ApiService.instance.batchDeleteTasks(taskIds, deleteFiles: deleteFiles);
      if (success) {
        for (final tid in taskIds) {
          _tasksMap.remove(tid);
        }
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = '批量删除失败: $e';
      notifyListeners();
    }
    return false;
  }

  /// 获取下载器配置
  Future<void> loadDownloaderConfig() async {
    _isLoadingConfig = true;
    notifyListeners();
    try {
      _downloaderConfig = await ApiService.instance.getDownloaderConfig();
    } catch (e) {
      _errorMessage = '获取下载器配置失败: $e';
    } finally {
      _isLoadingConfig = false;
      notifyListeners();
    }
  }

  /// 设置下载器限速、并发与全局路径
  Future<bool> updateDownloaderConfig({
    int? downloadLimitKb,
    int? uploadLimitKb,
    String? defaultSavePath,
    int? maxActiveDownloads,
    int? maxActiveTorrents,
    String? defaultCategory,
    bool? queueingEnabled,
    bool? autoStopSeeding,
  }) async {
    try {
      final success = await ApiService.instance.setDownloaderConfig(
        downloadLimitKb: downloadLimitKb,
        uploadLimitKb: uploadLimitKb,
        defaultSavePath: defaultSavePath,
        maxActiveDownloads: maxActiveDownloads,
        maxActiveTorrents: maxActiveTorrents,
        defaultCategory: defaultCategory,
        queueingEnabled: queueingEnabled,
        autoStopSeeding: autoStopSeeding,
      );
      if (success) {
        await loadDownloaderConfig();
        return true;
      }
    } catch (e) {
      _errorMessage = '更新下载配置失败: $e';
      notifyListeners();
    }
    return false;
  }

  /// 测试外部下载器连通性
  Future<void> testDownloader([String type = 'qbittorrent']) async {
    _isTestingDownloader = true;
    notifyListeners();

    try {
      _downloaderStatus = await ApiService.instance.testDownloaderConnection(type);
    } catch (e) {
      _downloaderStatus = {'status': 'error', 'error': '$e'};
    } finally {
      _isTestingDownloader = false;
      notifyListeners();
    }
  }
}

