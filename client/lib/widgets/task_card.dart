import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../models/task_model.dart';
import 'status_badge.dart';

class TaskCard extends StatelessWidget {
  final TaskItem task;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isWideScreen;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onRecheck;
  final VoidCallback? onCancel;
  final void Function(bool deleteFiles)? onDelete;

  const TaskCard({
    super.key,
    required this.task,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isWideScreen = true,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.onPause,
    this.onResume,
    this.onRecheck,
    this.onCancel,
    this.onDelete,
  });

  void _showDeleteDialog(BuildContext context) {
    bool deleteFiles = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.delete_forever_rounded, color: AppColors.errorRed, size: 22),
                SizedBox(width: 8),
                Text('删除下载任务', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '确定要删除任务 "${task.title}" 吗？',
                  style: TextStyle(color: context.subtextColor, fontSize: 14),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.isDark ? Colors.white12 : AppColors.lightBorder),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: deleteFiles,
                        activeColor: AppColors.errorRed,
                        onChanged: (val) {
                          setState(() {
                            deleteFiles = val ?? false;
                          });
                        },
                      ),
                      const Expanded(
                        child: Text(
                          '同时从磁盘彻底删除已下载的文件',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.errorRed),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  onDelete?.call(deleteFiles);
                },
                child: const Text('删除'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = task.status == TaskStatus.running;
    final isPaused = task.status == TaskStatus.paused;
    final isPending = task.status == TaskStatus.pending;
    final isDownload = task.taskType == 'DOWNLOAD';
    final isQb = task.taskId.startsWith('qb_');
    final isSeeding = task.isSeeding;
    final isSeedingStopped = task.isSeedingStopped;
    final canPause = (isQb && (isRunning || isPending)) || isSeeding;
    final canResume = (isQb && isPaused) || isSeedingStopped;

    IconData typeIcon;
    switch (task.taskType) {
      case 'DOWNLOAD':
        typeIcon = Icons.download_rounded;
        break;
      case 'DUPLICATE_SCAN':
        typeIcon = Icons.fingerprint_rounded;
        break;
      case 'ARCHIVE_EXTRACT':
        typeIcon = Icons.unarchive_rounded;
        break;
      case 'BATCH_ORGANIZE':
        typeIcon = Icons.auto_fix_high_rounded;
        break;
      default:
        typeIcon = Icons.task_alt_rounded;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isSelected
            ? const BorderSide(color: AppColors.primaryBlue, width: 2)
            : BorderSide(color: context.customBorderColor, width: 1),
      ),
      color: isSelected
          ? AppColors.primaryBlue.withOpacity(context.isDark ? 0.12 : 0.08)
          : Theme.of(context).cardTheme.color,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTapDown: onSecondaryTapDown,
        splashColor: AppColors.primaryBlue.withOpacity(0.1),
        highlightColor: AppColors.primaryBlue.withOpacity(0.05),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isSelectionMode) ...[
                    Checkbox(
                      value: isSelected,
                      activeColor: AppColors.primaryBlue,
                      onChanged: (_) => onTap?.call(),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(typeIcon, color: AppColors.primaryBlue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ID: ${task.taskId} • ${task.taskType}${task.detail['engine'] != null ? ' (${task.detail['engine']})' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: context.subtextColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge.fromTask(task),
                  // 宽屏下如果处于做种或停止做种状态，直接展示显式控制按钮
                  if (isWideScreen && !isSelectionMode) ...[
                    if (isSeeding) ...[
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          backgroundColor: AppColors.warningOrange.withOpacity(0.15),
                          foregroundColor: AppColors.warningOrange,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: onPause,
                        icon: const Icon(Icons.pause_circle_outline_rounded, size: 15),
                        label: const Text('停止做种', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ] else if (isSeedingStopped) ...[
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          backgroundColor: AppColors.successGreen.withOpacity(0.15),
                          foregroundColor: AppColors.successGreen,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: onResume,
                        icon: const Icon(Icons.play_circle_outline_rounded, size: 15),
                        label: const Text('继续做种', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                  // 小屏且非多选模式下，显示右上角快捷三点菜单
                  if (!isWideScreen && !isSelectionMode) ...[
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded, size: 20, color: context.subtextColor),
                      elevation: 8,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onSelected: (val) {
                        switch (val) {
                          case 'pause':
                            onPause?.call();
                            break;
                          case 'resume':
                            onResume?.call();
                            break;
                          case 'recheck':
                            onRecheck?.call();
                            break;
                          case 'delete':
                            _showDeleteDialog(context);
                            break;
                          case 'cancel':
                            onCancel?.call();
                            break;
                        }
                      },
                      itemBuilder: (ctx) => [
                        if (canPause)
                          PopupMenuItem(
                            value: 'pause',
                            child: Row(
                              children: [
                                const Icon(Icons.pause_circle_outline_rounded,
                                    size: 18, color: AppColors.warningOrange),
                                const SizedBox(width: 10),
                                Text(isSeeding ? '停止做种' : '暂停下载', style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        if (canResume)
                          PopupMenuItem(
                            value: 'resume',
                            child: Row(
                              children: [
                                const Icon(Icons.play_circle_outline_rounded,
                                    size: 18, color: AppColors.successGreen),
                                const SizedBox(width: 10),
                                Text(isSeedingStopped ? '继续做种' : '恢复下载', style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        if (isQb && onRecheck != null)
                          PopupMenuItem(
                            value: 'recheck',
                            child: Row(
                              children: [
                                Icon(Icons.refresh_rounded,
                                    size: 18,
                                    color: context.isDark
                                        ? AppColors.accentCyan
                                        : AppColors.primaryBlue),
                                const SizedBox(width: 10),
                                const Text('重新校验', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        if (onDelete != null)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded,
                                    size: 18, color: AppColors.errorRed),
                                SizedBox(width: 10),
                                Text('删除任务',
                                    style: TextStyle(fontSize: 13, color: AppColors.errorRed)),
                              ],
                            ),
                          ),
                        if (!isQb && isRunning && onCancel != null)
                          const PopupMenuItem(
                            value: 'cancel',
                            child: Row(
                              children: [
                                Icon(Icons.close_rounded, size: 18, color: AppColors.errorRed),
                                SizedBox(width: 10),
                                Text('取消任务',
                                    style: TextStyle(fontSize: 13, color: AppColors.errorRed)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (task.progress / 100.0).clamp(0.0, 1.0),
                  backgroundColor: context.isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isPaused
                        ? AppColors.warningOrange
                        : (isRunning
                            ? (context.isDark ? AppColors.accentCyan : AppColors.primaryBlue)
                            : AppColors.primaryBlue),
                  ),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    '${task.progress.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (isDownload && isRunning)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.speed_rounded,
                            size: 14,
                            color: context.isDark ? AppColors.accentCyan : AppColors.primaryBlueDark),
                        const SizedBox(width: 4),
                        Text(
                          task.speed,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.isDark ? AppColors.accentCyan : AppColors.primaryBlueDark,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  if (task.totalBytes > 0)
                    Text(
                      '${Formatters.formatBytes(task.downloadedBytes)} / ${Formatters.formatBytes(task.totalBytes)}',
                      style: TextStyle(fontSize: 12, color: context.subtextColor),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Divider(color: Theme.of(context).dividerColor, height: 1),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (task.etaSeconds > 0 && isRunning)
                    Text(
                      '预计剩余: ${Formatters.formatDuration(task.etaSeconds)}',
                      style: TextStyle(fontSize: 11, color: context.tertiaryTextColor),
                    )
                  else if (task.detail['save_path'] != null)
                    Expanded(
                      child: Text(
                        '目录: ${task.detail['save_path']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: context.tertiaryTextColor),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
              if (task.error != null) ...[
                const SizedBox(height: 6),
                Text(
                  '错误: ${task.error}',
                  style: const TextStyle(fontSize: 11, color: AppColors.errorRed),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
