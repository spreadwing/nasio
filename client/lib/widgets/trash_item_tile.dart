import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../models/trash_model.dart';

class TrashItemTile extends StatelessWidget {
  final TrashItem item;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const TrashItemTile({
    super.key,
    required this.item,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: item.isDir
                ? AppColors.warningOrange.withOpacity(0.15)
                : AppColors.primaryBlue.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            item.isDir ? Icons.folder_delete_rounded : Icons.insert_drive_file_rounded,
            color: item.isDir ? AppColors.warningOrange : AppColors.primaryBlue,
            size: 24,
          ),
        ),
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '原路径: ${item.originalPath}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: context.subtextColor),
            ),
            const SizedBox(height: 2),
            Text(
              '大小: ${Formatters.formatBytes(item.sizeBytes)} • 删除于: ${item.deletedAt}',
              style: TextStyle(fontSize: 11, color: context.tertiaryTextColor),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.restore_rounded, color: AppColors.successGreen),
              tooltip: '原路还原',
              onPressed: onRestore,
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever_rounded, color: AppColors.errorRed),
              tooltip: '永久删除',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
