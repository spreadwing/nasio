class TrashItem {
  final String fileId;
  final String name;
  final String originalPath;
  final String deletedAt;
  final int sizeBytes;
  final bool isDir;
  final String? reason;

  TrashItem({
    required this.fileId,
    required this.name,
    required this.originalPath,
    required this.deletedAt,
    required this.sizeBytes,
    required this.isDir,
    this.reason,
  });

  factory TrashItem.fromJson(Map<String, dynamic> json) {
    return TrashItem(
      fileId: json['file_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      originalPath: json['original_path']?.toString() ?? '',
      deletedAt: json['deleted_at']?.toString() ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      isDir: json['is_dir'] ?? false,
      reason: json['reason']?.toString(),
    );
  }
}

class TrashResponse {
  final List<TrashItem> items;
  final int total;
  final int page;
  final int limit;

  TrashResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory TrashResponse.fromJson(Map<String, dynamic> json) {
    final list = json['items'] as List<dynamic>? ?? [];
    return TrashResponse(
      items: list.map((e) => TrashItem.fromJson(e as Map<String, dynamic>)).toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 20,
    );
  }
}
