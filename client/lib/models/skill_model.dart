class SkillModel {
  final String name;
  final String description;
  final List<String> tags;
  final String version;
  final String updatedAt;
  final int fileSize;
  final String? content;
  final String? body;

  SkillModel({
    required this.name,
    required this.description,
    this.tags = const [],
    this.version = '1.0.0',
    required this.updatedAt,
    this.fileSize = 0,
    this.content,
    this.body,
  });

  factory SkillModel.fromJson(Map<String, dynamic> json) {
    return SkillModel(
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      version: json['version'] ?? '1.0.0',
      updatedAt: json['updated_at'] ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      content: json['content'] as String?,
      body: json['body'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'tags': tags,
      'version': version,
      'updated_at': updatedAt,
      'file_size': fileSize,
      if (content != null) 'content': content,
      if (body != null) 'body': body,
    };
  }
}
