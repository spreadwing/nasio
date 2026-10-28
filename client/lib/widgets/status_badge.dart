import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../models/task_model.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  factory StatusBadge.fromTask(TaskItem task) {
    if (task.isSeeding) {
      return const StatusBadge(
        label: '做种中',
        color: AppColors.successGreen,
        icon: Icons.arrow_upward_rounded,
      );
    }
    if (task.isSeedingStopped) {
      return const StatusBadge(
        label: '已停止做种',
        color: Colors.grey,
        icon: Icons.pause_circle_outline_rounded,
      );
    }
    return StatusBadge.fromTaskStatus(task.status);
  }

  factory StatusBadge.fromTaskStatus(TaskStatus status) {
    Color c;
    IconData ic;
    switch (status) {
      case TaskStatus.running:
        c = AppColors.infoBlue;
        ic = Icons.sync_rounded;
        break;
      case TaskStatus.paused:
        c = AppColors.warningOrange;
        ic = Icons.pause_circle_outline_rounded;
        break;
      case TaskStatus.completed:
        c = AppColors.successGreen;
        ic = Icons.check_circle_outline_rounded;
        break;
      case TaskStatus.failed:
        c = AppColors.errorRed;
        ic = Icons.error_outline_rounded;
        break;
      case TaskStatus.cancelled:
        c = Colors.grey;
        ic = Icons.cancel_outlined;
        break;
      case TaskStatus.pending:
        c = AppColors.warningOrange;
        ic = Icons.hourglass_top_rounded;
        break;
    }
    return StatusBadge(label: status.label, color: c, icon: ic);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
