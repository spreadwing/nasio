class MissingMcpToolModel {
  final String id;
  final String toolName;
  final String description;
  final String? suggestedParameters;
  final String? scenario;
  final String? agentTaskId;
  final double createdAt;

  MissingMcpToolModel({
    required this.id,
    required this.toolName,
    required this.description,
    this.suggestedParameters,
    this.scenario,
    this.agentTaskId,
    required this.createdAt,
  });

  factory MissingMcpToolModel.fromJson(Map<String, dynamic> json) {
    return MissingMcpToolModel(
      id: json['id'] ?? '',
      toolName: json['tool_name'] ?? '',
      description: json['description'] ?? '',
      suggestedParameters: json['suggested_parameters']?.toString(),
      scenario: json['scenario']?.toString(),
      agentTaskId: json['agent_task_id']?.toString(),
      createdAt: (json['created_at'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tool_name': toolName,
      'description': description,
      'suggested_parameters': suggestedParameters,
      'scenario': scenario,
      'agent_task_id': agentTaskId,
      'created_at': createdAt,
    };
  }
}
