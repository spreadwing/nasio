class RssFilterRule {
  final String tag;
  final String? attribute;
  final String pattern;
  final String mode; // INCLUDE or EXCLUDE

  RssFilterRule({
    required this.tag,
    this.attribute,
    required this.pattern,
    this.mode = 'INCLUDE',
  });

  factory RssFilterRule.fromJson(Map<String, dynamic> json) {
    return RssFilterRule(
      tag: json['tag'] ?? 'title',
      attribute: json['attribute'],
      pattern: json['pattern'] ?? '',
      mode: json['mode'] ?? 'INCLUDE',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tag': tag,
      if (attribute != null && attribute!.isNotEmpty) 'attribute': attribute,
      'pattern': pattern,
      'mode': mode,
    };
  }
}

class RssItemPreview {
  final String guid;
  final String title;
  final String link;
  final String downloadUrl;
  final String pubDate;
  final bool matched;
  final bool isDownloaded;
  final Map<String, dynamic> tagValues;

  RssItemPreview({
    required this.guid,
    required this.title,
    required this.link,
    required this.downloadUrl,
    this.pubDate = '',
    this.matched = true,
    this.isDownloaded = false,
    this.tagValues = const {},
  });

  factory RssItemPreview.fromJson(Map<String, dynamic> json) {
    return RssItemPreview(
      guid: json['guid'] ?? '',
      title: json['title'] ?? '',
      link: json['link'] ?? '',
      downloadUrl: json['download_url'] ?? '',
      pubDate: json['pub_date'] ?? '',
      matched: json['matched'] ?? true,
      isDownloaded: json['is_downloaded'] ?? false,
      tagValues: json['tag_values'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toDownloadJson() {
    return {
      'guid': guid,
      'title': title,
      'download_url': downloadUrl,
      'link': link,
      'pub_date': pubDate,
    };
  }
}

class RssPreviewResponse {
  final String feedUrl;
  final String channelTitle;
  final int totalItems;
  final int matchedCount;
  final List<RssItemPreview> items;

  RssPreviewResponse({
    required this.feedUrl,
    required this.channelTitle,
    required this.totalItems,
    required this.matchedCount,
    required this.items,
  });

  factory RssPreviewResponse.fromJson(Map<String, dynamic> json) {
    return RssPreviewResponse(
      feedUrl: json['feed_url'] ?? '',
      channelTitle: json['channel_title'] ?? '',
      totalItems: (json['total_items'] as num?)?.toInt() ?? 0,
      matchedCount: (json['matched_count'] as num?)?.toInt() ?? 0,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => RssItemPreview.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class RssDownloadRecord {
  final String guid;
  final String title;
  final String downloadUrl;
  final double downloadTime;
  final String? taskId;
  final String engine;
  final String status;

  RssDownloadRecord({
    required this.guid,
    required this.title,
    required this.downloadUrl,
    required this.downloadTime,
    this.taskId,
    this.engine = 'auto',
    this.status = 'DISPATCHED',
  });

  factory RssDownloadRecord.fromJson(Map<String, dynamic> json) {
    return RssDownloadRecord(
      guid: json['guid'] ?? '',
      title: json['title'] ?? '',
      downloadUrl: json['download_url'] ?? '',
      downloadTime: (json['download_time'] as num?)?.toDouble() ?? 0.0,
      taskId: json['task_id'],
      engine: json['engine'] ?? 'auto',
      status: json['status'] ?? 'DISPATCHED',
    );
  }
}

class RssSubscriptionModel {
  final String rssId;
  final String title;
  final String feedUrl;
  final String saveDir;
  final List<RssFilterRule> filterRules;
  final Map<String, dynamic>? urlExtractRule;
  final int checkIntervalMinutes;
  final String downloadEngine;
  final bool enabled;
  final double lastCheckedAt;
  final String? lastError;
  final int totalDownloadedCount;
  final List<String> downloadedGuids;
  final List<RssDownloadRecord> downloadHistory;
  final String? agentTaskId;
  final String? subtitleLanguage;
  final double createdAt;
  final double updatedAt;

  RssSubscriptionModel({
    required this.rssId,
    required this.title,
    required this.feedUrl,
    required this.saveDir,
    required this.filterRules,
    this.urlExtractRule,
    required this.checkIntervalMinutes,
    required this.downloadEngine,
    required this.enabled,
    required this.lastCheckedAt,
    this.lastError,
    required this.totalDownloadedCount,
    required this.downloadedGuids,
    required this.downloadHistory,
    this.agentTaskId,
    this.subtitleLanguage,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RssSubscriptionModel.fromJson(Map<String, dynamic> json) {
    return RssSubscriptionModel(
      rssId: json['rss_id'] ?? '',
      title: json['title'] ?? '',
      feedUrl: json['feed_url'] ?? '',
      saveDir: json['save_dir'] ?? '',
      filterRules: (json['filter_rules'] as List<dynamic>?)
              ?.map((e) => RssFilterRule.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      urlExtractRule: json['url_extract_rule'] as Map<String, dynamic>?,
      checkIntervalMinutes: (json['check_interval_minutes'] as num?)?.toInt() ?? 15,
      downloadEngine: json['download_engine'] ?? 'auto',
      enabled: json['enabled'] ?? true,
      lastCheckedAt: (json['last_checked_at'] as num?)?.toDouble() ?? 0.0,
      lastError: json['last_error'],
      totalDownloadedCount: (json['total_downloaded_count'] as num?)?.toInt() ?? 0,
      downloadedGuids: (json['downloaded_guids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      downloadHistory: (json['download_history'] as List<dynamic>?)
              ?.map((e) => RssDownloadRecord.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      agentTaskId: json['agent_task_id'],
      subtitleLanguage: json['subtitle_language'],
      createdAt: (json['created_at'] as num?)?.toDouble() ?? 0.0,
      updatedAt: (json['updated_at'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class RssSubscriptionItemsResponse {
  final String rssId;
  final String title;
  final String feedUrl;
  final String saveDir;
  final String downloadEngine;
  final int totalItems;
  final int matchedCount;
  final int downloadedCount;
  final List<RssItemPreview> items;

  RssSubscriptionItemsResponse({
    required this.rssId,
    required this.title,
    required this.feedUrl,
    required this.saveDir,
    required this.downloadEngine,
    required this.totalItems,
    required this.matchedCount,
    required this.downloadedCount,
    required this.items,
  });

  factory RssSubscriptionItemsResponse.fromJson(Map<String, dynamic> json) {
    return RssSubscriptionItemsResponse(
      rssId: json['rss_id'] ?? '',
      title: json['title'] ?? '',
      feedUrl: json['feed_url'] ?? '',
      saveDir: json['save_dir'] ?? '',
      downloadEngine: json['download_engine'] ?? 'auto',
      totalItems: (json['total_items'] as num?)?.toInt() ?? 0,
      matchedCount: (json['matched_count'] as num?)?.toInt() ?? 0,
      downloadedCount: (json['downloaded_count'] as num?)?.toInt() ?? 0,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => RssItemPreview.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class RssBatchDownloadResult {
  final String rssId;
  final int totalRequested;
  final int dispatchedCount;
  final int failedCount;
  final int totalDownloadedCount;

  RssBatchDownloadResult({
    required this.rssId,
    required this.totalRequested,
    required this.dispatchedCount,
    required this.failedCount,
    required this.totalDownloadedCount,
  });

  factory RssBatchDownloadResult.fromJson(Map<String, dynamic> json) {
    return RssBatchDownloadResult(
      rssId: json['rss_id'] ?? '',
      totalRequested: (json['total_requested'] as num?)?.toInt() ?? 0,
      dispatchedCount: (json['dispatched_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
      totalDownloadedCount: (json['total_downloaded_count'] as num?)?.toInt() ?? 0,
    );
  }
}
