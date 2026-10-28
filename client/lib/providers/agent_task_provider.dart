import 'package:flutter/material.dart';
import '../models/agent_task_model.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

class AgentTaskProvider extends ChangeNotifier {
  List<AgentTaskModel> _tasks = [];
  AgentTaskModel? _selectedTask;
  String _statusFilter = 'ALL';
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;

  AgentTaskProvider() {
    WebSocketService.instance.addListener(_handleWsEvent);
  }

  @override
  void dispose() {
    WebSocketService.instance.removeListener(_handleWsEvent);
    super.dispose();
  }

  List<AgentTaskModel> get tasks {
    if (_statusFilter == 'ALL' || _statusFilter.isEmpty) {
      return _tasks;
    }
    return _tasks.where((t) => t.status.toUpperCase() == _statusFilter.toUpperCase()).toList();
  }

  AgentTaskModel? get selectedTask => _selectedTask;
  String get statusFilter => _statusFilter;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;

  void reset() {
    _tasks = [];
    _selectedTask = null;
    _statusFilter = 'ALL';
    _isLoading = false;
    _hasLoaded = false;
    _errorMessage = null;
    notifyListeners();
  }

  void setStatusFilter(String filter) {
    _statusFilter = filter;
    // 若当前选中的任务被过滤掉，自动指向符合条件的第一个任务
    if (_selectedTask != null && _statusFilter != 'ALL' && _statusFilter.isNotEmpty) {
      if (_selectedTask!.status.toUpperCase() != _statusFilter.toUpperCase()) {
        final filtered = tasks;
        _selectedTask = filtered.isNotEmpty ? filtered.first : null;
      }
    }
    notifyListeners();
  }

  void selectTask(AgentTaskModel? task) {
    _selectedTask = task;
    notifyListeners();
  }

  Future<void> loadTasks() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 客户端获取全量任务列表，由前端本地实现毫秒级瞬时筛选
      _tasks = await ApiService.instance.getAgentTasks(limit: 100);
      _hasLoaded = true;
      if (_selectedTask != null) {
        final found = _tasks.where((t) => t.agentTaskId == _selectedTask!.agentTaskId);
        if (found.isNotEmpty) {
          _selectedTask = found.first;
        } else {
          _selectedTask = null;
        }
      }
    } catch (e) {
      _errorMessage = '获取智能体任务失败: $e';
      _hasLoaded = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> cancelTask(String id) async {
    try {
      final success = await ApiService.instance.cancelAgentTask(id);
      if (success) {
        await loadTasks();
        return true;
      }
    } catch (e) {
      _errorMessage = '取消任务失败: $e';
      notifyListeners();
    }
    return false;
  }

  /// 删除单条任务记录
  Future<bool> deleteTask(String id) async {
    try {
      final success = await ApiService.instance.deleteAgentTask(id);
      if (success) {
        _tasks.removeWhere((t) => t.agentTaskId == id);
        if (_selectedTask?.agentTaskId == id) {
          final filtered = tasks;
          _selectedTask = filtered.isNotEmpty ? filtered.first : null;
        }
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = '删除任务失败: $e';
      notifyListeners();
    }
    return false;
  }

  /// 批量清空已结束的任务记录
  Future<int> clearFinishedTasks() async {
    try {
      final count = await ApiService.instance.clearFinishedAgentTasks();
      if (count > 0) {
        await loadTasks();
      }
      return count;
    } catch (e) {
      _errorMessage = '清空已结束任务失败: $e';
      notifyListeners();
      return 0;
    }
  }

  void _handleWsEvent(Map<String, dynamic> event) {
    final eventName = event['event'];
    final data = event['data'] as Map<String, dynamic>?;
    if (eventName == 'AGENT_TASK_UPDATE' && data != null) {
      try {
        final updated = AgentTaskModel.fromJson(data);
        final index = _tasks.indexWhere((t) => t.agentTaskId == updated.agentTaskId);
        if (index >= 0) {
          _tasks[index] = updated;
        } else {
          _tasks.insert(0, updated);
        }
        if (_selectedTask?.agentTaskId == updated.agentTaskId) {
          _selectedTask = updated;
        }
        notifyListeners();
      } catch (e) {
        debugPrint('Error updating agent task from ws: $e');
      }
    } else if (eventName == 'AGENT_TASK_DELETED' && data != null) {
      final id = data['agent_task_id'] as String?;
      if (id != null) {
        _tasks.removeWhere((t) => t.agentTaskId == id);
        if (_selectedTask?.agentTaskId == id) {
          final filtered = tasks;
          _selectedTask = filtered.isNotEmpty ? filtered.first : null;
        }
        notifyListeners();
      }
    } else if (eventName == 'AGENT_TASKS_CLEARED') {
      loadTasks();
    }
  }
}
