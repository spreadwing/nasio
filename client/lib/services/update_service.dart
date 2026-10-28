import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_version_model.dart';

class UpdateService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
      },
    ),
  );

  /// 将 version 与 buildNumber 规范化为统一展示版本字符串 (如 1.0.0.25)
  static String formatVersionAndBuild(String version, String buildNumber) {
    final cleanVer = version.trim();
    final cleanBuild = buildNumber.trim();
    if (cleanVer.isEmpty) return '1.0.0';
    if (cleanBuild.isEmpty || cleanBuild == '0') return cleanVer;

    final parts = cleanVer.split('.');
    // 若 version 已包含第 4 段且与 buildNumber 相同（如 1.0.0.25 与 25），直接返回
    if (parts.length >= 4 && parts.last == cleanBuild) {
      return cleanVer;
    }
    // 将标准 3 段版本号 + 构建号（如 1.0.0 与 25）统一拼接为点分 4 段格式 1.0.0.25，与 Gitea 软件包保持一致
    if (parts.length == 3) {
      return '$cleanVer.$cleanBuild';
    }
    return '$cleanVer+$cleanBuild';
  }

  /// 获取当前客户端版本信息
  Future<String> getCurrentVersion() async {
    const envBuildName = String.fromEnvironment('FLUTTER_BUILD_NAME');
    const envBuildNumber = String.fromEnvironment('FLUTTER_BUILD_NUMBER');
    final envVersion = envBuildName.isNotEmpty
        ? formatVersionAndBuild(envBuildName, envBuildNumber)
        : '';

    try {
      final info = await PackageInfo.fromPlatform();
      final pkgVersion = formatVersionAndBuild(
        info.version.isNotEmpty ? info.version : '1.0.0',
        info.buildNumber,
      );
      // Windows 端 CMake 增量编译时 Runner.rc 资源可能未重新编译，优先取编译宏与平台资源中较新的版本
      if (envVersion.isNotEmpty &&
          AppVersionModel.compareVersion(envVersion, pkgVersion) > 0) {
        return envVersion;
      }
      return pkgVersion;
    } catch (e) {
      debugPrint('获取本地版本失败: $e');
      return envVersion.isNotEmpty ? envVersion : '1.0.0';
    }
  }

  /// Gitea 软件包只读 Token (用于公开读取 generic package 资产元数据)
  // Read token can be provided via settings if required

  /// 从 Gitea 软件包仓库获取最新发布的客户端版本与多端文件
  Future<AppVersionModel?> fetchLatestRelease({
    required String giteaUrl,
    String owner = 'spreadwing',
    String packageName = 'nasio-client',
    String? token,
  }) async {
    final baseUrl = giteaUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final packagesApi = '$baseUrl/api/v1/packages/$owner?type=generic';

    final authToken = token;
    final headers = <String, dynamic>{
      'Accept': 'application/json',
      if (authToken != null && authToken.isNotEmpty) 'Authorization': 'token $authToken',
    };

    try {
      final resp = await _dio.get(
        packagesApi,
        options: Options(headers: headers),
      );

      if (resp.statusCode == 200 && resp.data is List) {
        final list = resp.data as List;
        // 过滤出客户端包 (兼容 nasio-client 与历史 nas-copilot-client)
        final clientPackages = list.where((item) {
          if (item is! Map<String, dynamic>) return false;
          final name = item['name'] as String? ?? '';
          return name == packageName || name == 'nasio-client' || name == 'nas-copilot-client';
        }).toList();

        if (clientPackages.isNotEmpty) {
          // 优先按发布创建时间与语义化版本综合排序，确保最新构建始终排在首位
          clientPackages.sort((a, b) {
            final tA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
            final tB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
            // 若创建时间有明确差距（超过1分钟），以最新的发布时间为准
            if (tB.difference(tA).inSeconds.abs() > 60) {
              return tB.compareTo(tA);
            }
            final vA = a['version'] as String? ?? '0.0.0';
            final vB = b['version'] as String? ?? '0.0.0';
            final cmp = AppVersionModel.compareVersion(vB, vA);
            if (cmp != 0) return cmp;
            return tB.compareTo(tA);
          });

          final latestRaw = clientPackages.first as Map<String, dynamic>;
          final latestModel = AppVersionModel.fromJson(latestRaw);
          final actualPackageName =
              latestModel.name.isNotEmpty ? latestModel.name : packageName;

          // 查询该版本下的具体文件清单 (如 APK、Windows ZIP/EXE)
          final filesApi =
              '$baseUrl/api/v1/packages/$owner/generic/$actualPackageName/${latestModel.version}/files';
          final filesResp = await _dio.get(
            filesApi,
            options: Options(headers: headers),
          );

          List<PackageFileModel> files = [];
          if (filesResp.statusCode == 200 && filesResp.data is List) {
            final rawFiles = filesResp.data as List;
            files = rawFiles
                .whereType<Map<String, dynamic>>()
                .map((fJson) => PackageFileModel.fromJson(
                      fJson,
                      giteaBaseUrl: baseUrl,
                      owner: owner,
                      packageName: actualPackageName,
                      version: latestModel.version,
                    ))
                .toList();
          }

          return latestModel.copyWith(files: files);
        }
      }
    } catch (e) {
      debugPrint('通过 Gitea Packages API 查询遇到异常，尝试备用 Releases 接口: $e');
    }

    // 备用兜底策略：调用公开仓库的 Releases API
    try {
      final releasesApi = '$baseUrl/api/v1/repos/$owner/$packageName/releases';
      final relResp = await _dio.get(releasesApi);
      if (relResp.statusCode == 200 && relResp.data is List) {
        final relList = relResp.data as List;
        if (relList.isNotEmpty) {
          return AppVersionModel.fromGiteaRelease(relList.first as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('备用 Releases 接口查询失败: $e');
    }

    return null;
  }

  /// 下载指定平台安装包，并回调实时进度
  Future<String> downloadPackage({
    required PackageFileModel file,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    if (kIsWeb) {
      // Web 端直接拉起浏览器新标签下载
      await openDownloadUrl(file.downloadUrl);
      return file.downloadUrl;
    }

    Directory tempDir;
    if (Platform.isWindows) {
      tempDir = (await getDownloadsDirectory()) ?? await getTemporaryDirectory();
    } else {
      tempDir = await getTemporaryDirectory();
    }

    final savePath = '${tempDir.path}${Platform.pathSeparator}${file.name}';
    final saveFile = File(savePath);
    if (await saveFile.exists()) {
      try {
        await saveFile.delete();
      } catch (_) {}
    }

    await _dio.download(
      file.downloadUrl,
      savePath,
      onReceiveProgress: onProgress,
      cancelToken: cancelToken,
    );

    return savePath;
  }

  /// 打开安装包文件或拉起系统安装意图
  Future<OpenResult?> installOrOpenFile(String filePath) async {
    if (kIsWeb) return null;

    try {
      if (Platform.isAndroid) {
        return await OpenFilex.open(
          filePath,
          type: 'application/vnd.android.package-archive',
        );
      } else {
        return await OpenFilex.open(filePath);
      }
    } catch (e) {
      debugPrint('拉起安装文件失败: $e');
      return null;
    }
  }

  /// 外部浏览器打开链接 (Web 或备用下载)
  Future<bool> openDownloadUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
