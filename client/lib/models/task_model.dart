enum TaskStatus {
  pending,
  running,
  paused,
  completed,
  failed,
  cancelled;

  static TaskStatus fromString(String? val) {
    if (val == null) return TaskStatus.pending;
    switch (val.toUpperCase()) {
      case 'RUNNING':
        return TaskStatus.running;
      case 'PAUSED':
        return TaskStatus.paused;
      case 'COMPLETED':
        return TaskStatus.completed;
      case 'FAILED':
        return TaskStatus.failed;
      case 'CANCELLED':
        return TaskStatus.cancelled;
      default:
        return TaskStatus.pending;
    }
  }

  String get label {
    switch (this) {
      case TaskStatus.pending:
        return '等待中';
      case TaskStatus.running:
        return '下载中';
      case TaskStatus.paused:
        return '已暂停';
      case TaskStatus.completed:
        return '已完成';
      case TaskStatus.failed:
        return '失败';
      case TaskStatus.cancelled:
        return '已取消';
    }
  }
}

class TaskItem {
  final String taskId;
  final String taskType;
  TaskStatus status;
  double progress;
  final double createdAt;
  double updatedAt;
  Map<String, dynamic> detail;
  String? error;
  dynamic result;

  TaskItem({
    required this.taskId,
    required this.taskType,
    required this.status,
    required this.progress,
    required this.createdAt,
    required this.updatedAt,
    required this.detail,
    this.error,
    this.result,
  });

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    return TaskItem(
      taskId: json['task_id'] ?? '',
      taskType: json['task_type'] ?? 'CUSTOM',
      status: TaskStatus.fromString(json['status']?.toString()),
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      createdAt: (json['created_at'] as num?)?.toDouble() ?? 0.0,
      updatedAt: (json['updated_at'] as num?)?.toDouble() ?? 0.0,
      detail: json['detail'] as Map<String, dynamic>? ?? {},
      error: json['error']?.toString(),
      result: json['result'],
    );
  }

  /// 通过 WebSocket 推送更新进度与速率详情
  void updateFromWs(Map<String, dynamic> wsData) {
    if (wsData['status'] != null) {
      status = TaskStatus.fromString(wsData['status']?.toString());
    }
    if (wsData['progress'] != null) {
      progress = (wsData['progress'] as num).toDouble();
    }
    // 合并 detail
    detail = Map<String, dynamic>.from(detail)..addAll(wsData);
    updatedAt = DateTime.now().millisecondsSinceEpoch / 1000.0;
  }

  String get speed => detail['speed']?.toString() ?? '0 B/s';
  int get downloadedBytes => (detail['downloaded_bytes'] as num?)?.toInt() ?? 0;
  int get totalBytes => (detail['total_bytes'] as num?)?.toInt() ?? 0;
  int get etaSeconds => (detail['eta_seconds'] as num?)?.toInt() ?? 0;
  String get title => detail['name']?.toString() ?? detail['url']?.toString() ?? taskId;

  bool get isQb => taskId.startsWith('qb_');
  String get qbState => (detail['state'] as String? ?? '').toLowerCase();
  bool get isSeeding =>
      isQb &&
      const [
        'uploading',
        'stalledup',
        'forcedup',
        'forceup',
        'queuedup',
        'checkingup'
      ].contains(qbState);
  bool get isSeedingStopped =>
      isQb &&
      const [
        'pausedup',
        'stoppedup',
        'completed'
      ].contains(qbState);
}
