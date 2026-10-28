class DownloaderConfigModel {
  final String defaultEngine;
  final List<String> allowedPaths;
  final QbittorrentConfig qbittorrent;

  DownloaderConfigModel({
    required this.defaultEngine,
    required this.allowedPaths,
    required this.qbittorrent,
  });

  factory DownloaderConfigModel.fromJson(Map<String, dynamic> json) {
    return DownloaderConfigModel(
      defaultEngine: json['default_engine'] ?? 'auto',
      allowedPaths: (json['allowed_paths'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      qbittorrent: QbittorrentConfig.fromJson(
          json['qbittorrent'] as Map<String, dynamic>? ?? {}),
    );
  }
}

class QbittorrentConfig {
  final bool enabled;
  final String url;
  final String defaultCategory;
  final int downloadLimitKb;
  final int uploadLimitKb;
  final String defaultSavePath;
  final int maxActiveDownloads;
  final int maxActiveTorrents;
  final bool queueingEnabled;
  final bool autoStopSeeding;

  QbittorrentConfig({
    required this.enabled,
    required this.url,
    required this.defaultCategory,
    required this.downloadLimitKb,
    required this.uploadLimitKb,
    required this.defaultSavePath,
    required this.maxActiveDownloads,
    required this.maxActiveTorrents,
    required this.queueingEnabled,
    this.autoStopSeeding = false,
  });

  factory QbittorrentConfig.fromJson(Map<String, dynamic> json) {
    return QbittorrentConfig(
      enabled: json['enabled'] ?? false,
      url: json['url'] ?? '',
      defaultCategory: json['default_category'] ?? '',
      downloadLimitKb: (json['download_limit_kb'] as num?)?.toInt() ?? 0,
      uploadLimitKb: (json['upload_limit_kb'] as num?)?.toInt() ?? 0,
      defaultSavePath: json['default_save_path'] ?? '/volume1/Download',
      maxActiveDownloads: (json['max_active_downloads'] as num?)?.toInt() ?? 5,
      maxActiveTorrents: (json['max_active_torrents'] as num?)?.toInt() ?? 10,
      queueingEnabled: json['queueing_enabled'] ?? true,
      autoStopSeeding: json['auto_stop_seeding'] ?? false,
    );
  }
}
