class StoragePoolInfo {
  final String path;
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final double usagePercent;
  final bool exists;

  StoragePoolInfo({
    required this.path,
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.usagePercent,
    required this.exists,
  });

  factory StoragePoolInfo.fromJson(Map<String, dynamic> json) {
    int parseBytes(dynamic bytesVal, dynamic gbVal) {
      if (bytesVal != null) {
        final numVal = bytesVal is num ? bytesVal : num.tryParse('$bytesVal') ?? 0;
        return numVal.toInt();
      }
      if (gbVal != null) {
        final numGb = gbVal is num ? gbVal : num.tryParse('$gbVal') ?? 0;
        return (numGb * 1024 * 1024 * 1024).toInt();
      }
      return 0;
    }

    final totalBytes = parseBytes(json['total_bytes'] ?? json['total'], json['total_gb']);
    final usedBytes = parseBytes(json['used_bytes'] ?? json['used'], json['used_gb']);
    final freeBytes = parseBytes(json['free_bytes'] ?? json['free'], json['free_gb']);

    double percent = 0.0;
    if (json['used_percent'] != null) {
      percent = (json['used_percent'] as num).toDouble();
    } else if (json['usage_percent'] != null) {
      percent = (json['usage_percent'] as num).toDouble();
    } else if (totalBytes > 0) {
      percent = (usedBytes / totalBytes) * 100;
    }

    return StoragePoolInfo(
      path: json['path'] ?? '',
      totalBytes: totalBytes,
      usedBytes: usedBytes,
      freeBytes: freeBytes,
      usagePercent: percent,
      exists: json['exists'] ?? true,
    );
  }
}

class SystemConfig {
  final List<String> allowedPaths;
  final String trashDir;
  final int trashRetentionDays;
  final Map<String, dynamic> downloaders;
  final Map<String, dynamic> llm;
  final Map<String, dynamic> webhook;

  SystemConfig({
    required this.allowedPaths,
    required this.trashDir,
    required this.trashRetentionDays,
    required this.downloaders,
    this.llm = const {},
    this.webhook = const {},
  });

  factory SystemConfig.fromJson(Map<String, dynamic> json) {
    final storage = json['storage'] as Map<String, dynamic>? ?? {};
    final trash = json['trash'] as Map<String, dynamic>? ?? {};
    final downloaders = json['downloaders'] as Map<String, dynamic>? ?? {};
    final llm = json['llm'] as Map<String, dynamic>? ?? {};
    final webhook = json['webhook'] as Map<String, dynamic>? ?? {};

    final allowed = (storage['allowed_paths'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return SystemConfig(
      allowedPaths: allowed,
      trashDir: trash['trash_dir']?.toString() ?? '/volume1/.trash',
      trashRetentionDays: trash['retention_days'] is num
          ? (trash['retention_days'] as num).toInt()
          : 30,
      downloaders: downloaders,
      llm: llm,
      webhook: webhook,
    );
  }
}

class ConfigResponse {
  final SystemConfig config;
  final List<StoragePoolInfo> storagePools;

  ConfigResponse({
    required this.config,
    required this.storagePools,
  });

  factory ConfigResponse.fromJson(Map<String, dynamic> json) {
    final cfgJson = json['config'] as Map<String, dynamic>? ?? {};
    final poolsJson = json['storage_pools'] as List<dynamic>? ?? [];

    return ConfigResponse(
      config: SystemConfig.fromJson(cfgJson),
      storagePools: poolsJson
          .map((e) => StoragePoolInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
