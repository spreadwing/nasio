import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../models/config_model.dart';

class StoragePoolCard extends StatelessWidget {
  final StoragePoolInfo pool;

  const StoragePoolCard({super.key, required this.pool});

  @override
  Widget build(BuildContext context) {
    Color progressColor;
    if (pool.usagePercent >= 90) {
      progressColor = AppColors.errorRed;
    } else if (pool.usagePercent >= 75) {
      progressColor = AppColors.warningOrange;
    } else {
      progressColor = AppColors.primaryBlue;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_shared_rounded,
                        color: pool.exists
                            ? (context.isDark ? AppColors.accentCyan : AppColors.primaryBlue)
                            : Colors.grey,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          pool.path,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: pool.exists
                        ? AppColors.successGreen.withOpacity(0.15)
                        : AppColors.errorRed.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    pool.exists ? '正常挂载' : '未挂载',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: pool.exists ? AppColors.successGreen : AppColors.errorRed,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (pool.usagePercent / 100).clamp(0.0, 1.0),
                backgroundColor: context.isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  '使用率: ${pool.usagePercent.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: progressColor,
                  ),
                ),
                Text(
                  '已用: ${Formatters.formatBytes(pool.usedBytes)} / 总量: ${Formatters.formatBytes(pool.totalBytes)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.isDark ? Colors.white70 : AppColors.lightTitle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '剩余可用: ${Formatters.formatBytes(pool.freeBytes)}',
              style: TextStyle(
                fontSize: 12,
                color: context.subtextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
