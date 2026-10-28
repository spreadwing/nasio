class AgentTaskStep {
  final int stepIndex;
  final String stepName;
  final String status; // PENDING, RUNNING, COMPLETED, FAILED
  final double progress;
  final String logMessage;
  final double timestamp;

  AgentTaskStep({
    required this.stepIndex,
    required this.stepName,
    required this.status,
    required this.progress,
    required this.logMessage,
    required this.timestamp,
  });

  factory AgentTaskStep.fromJson(Map<String, dynamic> json) {
    return AgentTaskStep(
      stepIndex: (json['step_index'] as num?)?.toInt() ?? 1,
      stepName: json['step_name'] ?? '',
      status: json['status'] ?? 'COMPLETED',
      progress: (json['progress'] as num?)?.toDouble() ?? 100.0,
      logMessage: json['log_message'] ?? '',
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AgentSubAction {
  final String actionType; // DOWNLOAD, FILE_ORGANIZE, DUPLICATE_SCAN, TRASH_DELETE, CUSTOM
  final String actionId;
  final String summary;
  final String status;
  final double timestamp;

  AgentSubAction({
    required this.actionType,
    required this.actionId,
    required this.summary,
    required this.status,
    required this.timestamp,
  });

  factory AgentSubAction.fromJson(Map<String, dynamic> json) {
    return AgentSubAction(
      actionType: json['action_type'] ?? 'CUSTOM',
      actionId: json['action_id'] ?? '',
      summary: json['summary'] ?? '',
      status: json['status'] ?? 'COMPLETED',
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AgentTaskModel {
  final String agentTaskId;
  final String title;
  final String description;
  final String status; // RUNNING, COMPLETED, FAILED, CANCELLED
  final double progress;
  final int totalSteps;
  final int currentStep;
  final List<AgentTaskStep> steps;
  final List<AgentSubAction> subActions;
  final dynamic result;
  final String? error;
  final String? promptTemplate;
  final double createdAt;
  final double updatedAt;

  AgentTaskModel({
    required this.agentTaskId,
    required this.title,
    required this.description,
    required this.status,
    required this.progress,
    required this.totalSteps,
    required this.currentStep,
    required this.steps,
    required this.subActions,
    this.result,
    this.error,
    this.promptTemplate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AgentTaskModel.fromJson(Map<String, dynamic> json) {
    final rawTotal = (json['total_steps'] as num?)?.toInt() ?? 1;
    final current = (json['current_step'] as num?)?.toInt() ?? 1;
    final stepsList = (json['steps'] as List<dynamic>?)
            ?.map((e) => AgentTaskStep.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    var total = rawTotal < current ? current : rawTotal;
    if (total < stepsList.length) total = stepsList.length;
    if (total < 1) total = 1;

    return AgentTaskModel(
      agentTaskId: json['agent_task_id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      status: json['status'] ?? 'RUNNING',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      totalSteps: total,
      currentStep: current,
      steps: stepsList,
      subActions: (json['sub_actions'] as List<dynamic>?)
              ?.map((e) => AgentSubAction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      result: json['result'],
      error: json['error']?.toString(),
      promptTemplate: json['prompt_template']?.toString(),
      createdAt: (json['created_at'] as num?)?.toDouble() ?? 0.0,
      updatedAt: (json['updated_at'] as num?)?.toDouble() ?? 0.0,
    );
  }

  bool get isRunning => status == 'RUNNING';
  bool get isCompleted => status == 'COMPLETED';
  bool get isFailed => status == 'FAILED';
  bool get isCancelled => status == 'CANCELLED';
}
