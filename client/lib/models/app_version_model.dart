import '../core/utils/formatters.dart';

enum AppPlatformType {
  android,
  windows,
  web,
  other,
}

/// Gitea 软件包中单个文件资源定义
class PackageFileModel {
  final int id;
  final String name;
  final int size;
  final String downloadUrl;
  final String? md5;
  final String? sha256;

  const PackageFileModel({
    required this.id,
    required this.name,
    required this.size,
    required this.downloadUrl,
    this.md5,
    this.sha256,
  });

  factory PackageFileModel.fromJson(
    Map<String, dynamic> json, {
    required String giteaBaseUrl,
    required String owner,
    required String packageName,
    required String version,
  }) {
    final fileName = json['name'] as String? ?? '';
    // Gitea Generic Package 直链格式：/api/packages/{owner}/generic/{name}/{version}/{filename}
    final rawBase = giteaBaseUrl.endsWith('/')
        ? giteaBaseUrl.substring(0, giteaBaseUrl.length - 1)
        : giteaBaseUrl;
    final directUrl = '$rawBase/api/packages/$owner/generic/$packageName/$version/$fileName';

    return PackageFileModel(
      id: json['id'] as int? ?? 0,
      name: fileName,
      size: json['size'] as int? ?? 0,
      downloadUrl: directUrl,
      md5: json['md5'] as String?,
      sha256: json['sha256'] as String?,
    );
  }

  String get formattedSize => Formatters.formatBytes(size);

  AppPlatformType get platformType {
    final lower = name.toLowerCase();
    if (lower.endsWith('.apk')) {
      return AppPlatformType.android;
    }
    if (lower.endsWith('.exe') ||
        (lower.contains('windows') && lower.endsWith('.zip')) ||
        (lower.contains('win') && lower.endsWith('.zip'))) {
      return AppPlatformType.windows;
    }
    return AppPlatformType.other;
  }
}

/// 客户端版本与多端包元数据模型
class AppVersionModel {
  final int id;
  final String name;
  final String version;
  final String htmlUrl;
  final DateTime createdAt;
  final List<PackageFileModel> files;

  const AppVersionModel({
    required this.id,
    required this.name,
    required this.version,
    required this.htmlUrl,
    required this.createdAt,
    this.files = const [],
  });

  factory AppVersionModel.fromJson(Map<String, dynamic> json) {
    return AppVersionModel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? 'nasio-client',
      version: json['version'] as String? ?? '1.0.0',
      htmlUrl: json['html_url'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
      files: const [],
    );
  }

  /// 兼容解析 Gitea Releases API 返回的数据
  factory AppVersionModel.fromGiteaRelease(Map<String, dynamic> json) {
    final rawTag = (json['tag_name'] as String? ?? json['name'] as String? ?? '1.0.0').trim();
    final cleanVersion = rawTag.startsWith('v') || rawTag.startsWith('V')
        ? rawTag.substring(1)
        : rawTag;

    final assets = json['assets'] as List? ?? [];
    final files = assets.whereType<Map<String, dynamic>>().map((a) {
      return PackageFileModel(
        id: a['id'] as int? ?? 0,
        name: a['name'] as String? ?? '',
        size: a['size'] as int? ?? 0,
        downloadUrl: a['browser_download_url'] as String? ?? '',
      );
    }).toList();

    return AppVersionModel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? 'nasio-client',
      version: cleanVersion,
      htmlUrl: json['html_url'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
      files: files,
    );
  }

  AppVersionModel copyWith({List<PackageFileModel>? files}) {
    return AppVersionModel(
      id: id,
      name: name,
      version: version,
      htmlUrl: htmlUrl,
      createdAt: createdAt,
      files: files ?? this.files,
    );
  }

  /// 获取 Android APK 文件
  PackageFileModel? get apkFile {
    try {
      return files.firstWhere((f) => f.platformType == AppPlatformType.android);
    } catch (_) {
      return null;
    }
  }

  /// 获取 Windows 下载包文件 (zip 或 exe)
  PackageFileModel? get windowsFile {
    try {
      return files.firstWhere((f) => f.platformType == AppPlatformType.windows);
    } catch (_) {
      return null;
    }
  }

  /// 比较远端版本与本地当前版本，判断是否有更新
  /// 支持标准语义化版本号对比，例如 1.0.21 对比 1.0.0+1 或 1.0.20
  bool isNewerThan(String currentVersionStr) {
    return compareVersion(version, currentVersionStr) > 0;
  }

  /// 解析版本号字符串为整型数组，兼容 1.0.0+24、1.0.0.24、v1.0.21 等格式
  static List<int> _parseVersionParts(String raw) {
    var clean = raw.trim();
    if (clean.startsWith('v') || clean.startsWith('V')) {
      clean = clean.substring(1).trim();
    }

    int? plusBuild;
    if (clean.contains('+')) {
      final splitPlus = clean.split('+');
      clean = splitPlus.first.trim();
      plusBuild = int.tryParse(splitPlus.last.trim());
    }

    final parts = clean.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    // 若主版本号为 3 段 (如 1.0.0) 且带有 +build (如 +24)，将 +build 映射为第 4 段构建号
    if (parts.length == 3 && plusBuild != null) {
      parts.add(plusBuild);
    }
    return parts;
  }

  /// 版本对比静态算法：v1 > v2 返回 1，v1 < v2 返回 -1，相等返回 0
  static int compareVersion(String v1, String v2) {
    final parts1 = _parseVersionParts(v1);
    final parts2 = _parseVersionParts(v2);

    int major1 = parts1.isNotEmpty ? parts1[0] : 0;
    int minor1 = parts1.length > 1 ? parts1[1] : 0;
    int patch1 = parts1.length > 2 ? parts1[2] : 0;
    int build1 = parts1.length > 3 ? parts1[3] : 0;

    int major2 = parts2.isNotEmpty ? parts2[0] : 0;
    int minor2 = parts2.length > 1 ? parts2[1] : 0;
    int patch2 = parts2.length > 2 ? parts2[2] : 0;
    int build2 = parts2.length > 3 ? parts2[3] : 0;

    if (major1 != major2) return major1.compareTo(major2);
    if (minor1 != minor2) return minor1.compareTo(minor2);

    // 兼容 1.0.0.X 与 1.0.Y 跨格式对比
    if (parts1.length >= 4 && parts2.length == 3 && patch1 == 0 && patch2 > 0 && build2 == 0) {
      return build1.compareTo(patch2);
    }
    if (parts2.length >= 4 && parts1.length == 3 && patch2 == 0 && patch1 > 0 && build1 == 0) {
      return patch1.compareTo(build2);
    }

    if (patch1 != patch2) return patch1.compareTo(patch2);
    if (build1 != build2) return build1.compareTo(build2);

    return 0;
  }
}
