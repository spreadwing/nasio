class ToolCallTraceItem {
  final String toolName;
  final Map<String, dynamic> arguments;
  final String resultPreview;
  final String status;
  final int durationMs;

  ToolCallTraceItem({
    required this.toolName,
    required this.arguments,
    required this.resultPreview,
    required this.status,
    required this.durationMs,
  });

  factory ToolCallTraceItem.fromJson(Map<String, dynamic> json) {
    return ToolCallTraceItem(
      toolName: json['tool_name']?.toString() ?? '',
      arguments: (json['arguments'] as Map<String, dynamic>?) ?? {},
      resultPreview: json['result_preview']?.toString() ?? '',
      status: json['status']?.toString() ?? 'SUCCESS',
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatMessageItem {
  final String id;
  final String role;
  final String content;
  final List<ToolCallTraceItem> toolCalls;
  final String mode;
  final double createdAt;

  ChatMessageItem({
    required this.id,
    required this.role,
    required this.content,
    this.toolCalls = const [],
    this.mode = 'llm',
    required this.createdAt,
  });

  factory ChatMessageItem.fromJson(Map<String, dynamic> json) {
    final rawCalls = json['tool_calls'] as List<dynamic>? ?? [];
    return ChatMessageItem(
      id: json['id']?.toString() ?? '',
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      toolCalls: rawCalls
          .map((e) => ToolCallTraceItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      mode: json['mode']?.toString() ?? 'llm',
      createdAt: (json['created_at'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ChatSessionSummary {
  final String sessionId;
  final String title;
  final int messageCount;
  final String lastMessage;
  final double createdAt;
  final double updatedAt;

  ChatSessionSummary({
    required this.sessionId,
    required this.title,
    required this.messageCount,
    required this.lastMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatSessionSummary.fromJson(Map<String, dynamic> json) {
    return ChatSessionSummary(
      sessionId: json['session_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '新对话',
      messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
      lastMessage: json['last_message']?.toString() ?? '',
      createdAt: (json['created_at'] as num?)?.toDouble() ?? 0.0,
      updatedAt: (json['updated_at'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ApprovalItem {
  final String approvalId;
  final String title;
  final String description;
  final String diffPreview;
  final String? agentTaskId;
  final String status;
  final String decisionComment;
  final double createdAt;
  final double? decidedAt;

  ApprovalItem({
    required this.approvalId,
    required this.title,
    required this.description,
    required this.diffPreview,
    this.agentTaskId,
    required this.status,
    required this.decisionComment,
    required this.createdAt,
    this.decidedAt,
  });

  factory ApprovalItem.fromJson(Map<String, dynamic> json) {
    return ApprovalItem(
      approvalId: json['approval_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      diffPreview: json['diff_preview']?.toString() ?? '',
      agentTaskId: json['agent_task_id']?.toString(),
      status: json['status']?.toString() ?? 'PENDING',
      decisionComment: json['decision_comment']?.toString() ?? '',
      createdAt: (json['created_at'] as num?)?.toDouble() ?? 0.0,
      decidedAt: (json['decided_at'] as num?)?.toDouble(),
    );
  }
}

class ActionTransactionItem {
  final String transactionId;
  final String operationType;
  final String summary;
  final String? agentTaskId;
  final String status;
  final int movementsCount;
  final int trashCount;
  final double createdAt;
  final double? rolledBackAt;

  ActionTransactionItem({
    required this.transactionId,
    required this.operationType,
    required this.summary,
    this.agentTaskId,
    required this.status,
    required this.movementsCount,
    required this.trashCount,
    required this.createdAt,
    this.rolledBackAt,
  });

  factory ActionTransactionItem.fromJson(Map<String, dynamic> json) {
    return ActionTransactionItem(
      transactionId: json['transaction_id']?.toString() ?? '',
      operationType: json['operation_type']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      agentTaskId: json['agent_task_id']?.toString(),
      status: json['status']?.toString() ?? 'APPLIED',
      movementsCount: (json['movements_count'] as num?)?.toInt() ?? 0,
      trashCount: (json['trash_count'] as num?)?.toInt() ?? 0,
      createdAt: (json['created_at'] as num?)?.toDouble() ?? 0.0,
      rolledBackAt: (json['rolled_back_at'] as num?)?.toDouble(),
    );
  }
}
