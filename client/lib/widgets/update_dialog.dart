import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../models/app_version_model.dart';
import '../providers/update_provider.dart';

class UpdateDialogHelper {
  /// 展示发现新版本对话框
  static void showUpdateInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const _UpdateInfoDialogContent(),
    );
  }

  /// 展示下载中进度对话框
  static void showDownloadDialog(BuildContext context, PackageFileModel file) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DownloadProgressDialog(file: file),
    );
  }
}

class _UpdateInfoDialogContent extends StatelessWidget {
  const _UpdateInfoDialogContent();

  @override
  Widget build(BuildContext context) {
    final updateProv = context.watch<UpdateProvider>();
    final release = updateProv.latestRelease;
    final isDark = context.isDark;

    if (release == null) {
      return AlertDialog(
        title: const Text('暂无新版本'),
        content: const Text('未检测到可用的更新版本'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      );
    }

    final formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(release.createdAt);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 头部图标与版本标题
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primaryBlue, AppColors.accentCyan],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.system_update_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              '发现新版本',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
                              ),
                              child: Text(
                                'v${release.version}',
                                style: const TextStyle(
                                  color: AppColors.primaryBlue,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '发布时间: $formattedDate',
                          style: TextStyle(color: context.tertiaryTextColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 针对当前运行平台的专属操作
              _buildPlatformActionSection(context, updateProv, release),

              const SizedBox(height: 20),

              // 底部关闭与详情按钮
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (release.htmlUrl.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        updateProv.openExternalUrl(release.htmlUrl);
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('查看 Gitea 软件包'),
                    )
                  else
                    const SizedBox.shrink(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('稍后再说'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlatformActionSection(
    BuildContext context,
    UpdateProvider updateProv,
    AppVersionModel release,
  ) {
    if (kIsWeb) {
      // -------------------------------------------------------------
      // Web 平台：提供一键刷新与多端下载按钮
      // -------------------------------------------------------------
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warningOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warningOrange.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppColors.warningOrange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '当前为 Web 网页版，点击下方按钮刷新即可加载部署的最新前端。',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                launchUrl(Uri.base, webOnlyWindowName: '_self');
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('立即刷新页面加载新版'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '或下载跨平台独立客户端：',
            style: TextStyle(color: context.subtextColor, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (release.apkFile != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      updateProv.openExternalUrl(release.apkFile!.downloadUrl);
                    },
                    icon: const Icon(Icons.android_rounded, color: AppColors.successGreen),
                    label: Text('Android APK (${release.apkFile!.formattedSize})'),
                  ),
                ),
              if (release.apkFile != null && release.windowsFile != null)
                const SizedBox(width: 8),
              if (release.windowsFile != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      updateProv.openExternalUrl(release.windowsFile!.downloadUrl);
                    },
                    icon: const Icon(Icons.window_rounded, color: AppColors.primaryBlue),
                    label: Text('Windows (${release.windowsFile!.formattedSize})'),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    // -------------------------------------------------------------
    // Android 移动端：下载并拉起系统安装器
    // -------------------------------------------------------------
    if (Platform.isAndroid) {
      final apk = release.apkFile;
      if (apk == null) {
        return const Text('此版本尚未包含 Android APK 安装文件。');
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.android_rounded, color: AppColors.successGreen, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      apk.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '安装包大小: ${apk.formattedSize}',
                      style: TextStyle(fontSize: 12, color: context.subtextColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                UpdateDialogHelper.showDownloadDialog(context, apk);
              },
              icon: const Icon(Icons.download_rounded),
              label: Text('立即下载并安装更新 (${apk.formattedSize})'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      );
    }

    // -------------------------------------------------------------
    // Windows 桌面端：下载安装包并自动打开运行
    // -------------------------------------------------------------
    if (Platform.isWindows) {
      final winFile = release.windowsFile;
      if (winFile == null) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warningOrange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.warningOrange.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.warningOrange, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '此版本云端仅发布了移动端 APK 与 Web 端，未附带独立 Windows 安装包。',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.window_rounded, color: AppColors.primaryBlue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '软件包: ${winFile.name} (${winFile.formattedSize})',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                UpdateDialogHelper.showDownloadDialog(context, winFile);
              },
              icon: const Icon(Icons.download_rounded),
              label: Text('立即下载 Windows 客户端 (${winFile.formattedSize})'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  final PackageFileModel file;

  const _DownloadProgressDialog({required this.file});

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final updateProv = context.read<UpdateProvider>();
      updateProv.downloadAndInstall(
        file: widget.file,
        onSuccess: (savePath) {
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('下载完成！正在调起安装程序: $savePath'),
                backgroundColor: AppColors.successGreen,
              ),
            );
          }
        },
        onError: (err) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(err),
                backgroundColor: AppColors.errorRed,
              ),
            );
          }
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final updateProv = context.watch<UpdateProvider>();
    final isDark = context.isDark;
    final progress = updateProv.downloadProgress.clamp(0.0, 1.0);
    final percent = (progress * 100).toStringAsFixed(1);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '正在下载 ${widget.file.name}...',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                minHeight: 10,
                backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${updateProv.receivedBytes > 0 ? (updateProv.receivedBytes / 1024 / 1024).toStringAsFixed(1) : "0"} MB / ${(widget.file.size / 1024 / 1024).toStringAsFixed(1)} MB',
                  style: TextStyle(color: context.subtextColor, fontSize: 12),
                ),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (updateProv.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                updateProv.errorMessage!,
                style: const TextStyle(color: AppColors.errorRed, fontSize: 12),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    updateProv.cancelDownload();
                    Navigator.of(context).pop();
                  },
                  child: const Text('取消下载'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
