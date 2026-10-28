import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/downloader_config_model.dart';
import '../../models/task_model.dart';
import '../../providers/connection_provider.dart';
import '../../providers/task_provider.dart';
import '../../services/websocket_service.dart';
import '../../widgets/task_card.dart';
import '../home_scaffold.dart';

enum TaskSortField {
  name, // 任务名称
  status, // 状态优先级 (下载中 > 等待中 > 已暂停 ...)
  progress, // 下载进度
  speed, // 实时速度
  createdAt, // 添加时间
}

class TabSortState {
  TaskSortField field;
  bool isAscending;

  TabSortState({required this.field, required this.isAscending});
}

class TasksView extends StatefulWidget {
  const TasksView({super.key});

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _selectedTaskIds = {};
  bool _isSelectionMode = false;
  int? _lastFocusedIndex;

  // 各 Tab 独立记忆排序状态：0: 进行中, 1: 全部任务, 2: 已完成
  final List<TabSortState> _tabSortStates = [
    TabSortState(field: TaskSortField.status, isAscending: true), // 进行中: 状态优先(下载中排最前)
    TabSortState(field: TaskSortField.createdAt, isAscending: false), // 全部任务: 添加时间倒序
    TabSortState(field: TaskSortField.createdAt, isAscending: false), // 已完成: 添加时间倒序
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging || mounted) {
        setState(() {
          _selectedTaskIds.clear();
          _isSelectionMode = false;
          _lastFocusedIndex = null;
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final conn = context.read<ConnectionProvider>();
      if (conn.isConnected) {
        final prov = context.read<TaskProvider>();
        prov.loadTasks();
        prov.loadDownloaderConfig();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showClearFailedDialog() {
    final taskProv = context.read<TaskProvider>();
    final failedCount = taskProv.failedTasks.length;
    if (failedCount == 0) return;

    bool deleteFiles = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.delete_sweep_rounded, color: AppColors.errorRed, size: 22),
                SizedBox(width: 8),
                Text('清空失败任务确认', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '确定要清空已完成列表中的全部失败任务吗？\n当前失败任务数量：$failedCount 项。',
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
                          setModalState(() {
                            deleteFiles = val ?? false;
                          });
                        },
                      ),
                      const Expanded(
                        child: Text(
                          '同时清理磁盘残留临时文件',
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
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.of(ctx).pop();
                  final count = await taskProv.clearFailedTasks(deleteFiles: deleteFiles);
                  await taskProv.loadTasks();
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('已清空 $count 个失败任务'),
                        backgroundColor: AppColors.successGreen,
                      ),
                    );
                  }
                },
                child: const Text('确认清空'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showBatchDeleteDialog(List<String> taskIds) {
    if (taskIds.isEmpty) return;
    final taskProv = context.read<TaskProvider>();
    bool deleteFiles = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.delete_forever_rounded, color: AppColors.errorRed, size: 22),
                const SizedBox(width: 8),
                Text('批量删除任务 (${taskIds.length} 项)',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '确定要删除选中的 ${taskIds.length} 个任务吗？该操作不可撤销。',
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
                          setModalState(() {
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
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.of(ctx).pop();
                  final ok = await taskProv.batchDeleteTasks(taskIds, deleteFiles: deleteFiles);
                  await taskProv.loadTasks();
                  if (mounted) {
                    setState(() {
                      _selectedTaskIds.removeAll(taskIds);
                    });
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(ok ? '已成功批量删除任务' : '部分任务删除失败'),
                        backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
                      ),
                    );
                  }
                },
                child: const Text('确认删除'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showContextMenu({
    required BuildContext context,
    required Offset position,
    required List<TaskItem> currentList,
    required TaskProvider taskProv,
  }) async {
    final selectedTasks = currentList.where((t) => _selectedTaskIds.contains(t.taskId)).toList();
    if (selectedTasks.isEmpty) return;

    final isSingle = selectedTasks.length == 1;
    final singleTask = isSingle ? selectedTasks.first : null;
    final isCompletedTab = _tabController.index == 2;

    final canStopSeedingTasks = selectedTasks
        .where((t) => t.isSeeding)
        .map((t) => t.taskId)
        .toList();
    final canResumeSeedingTasks = selectedTasks
        .where((t) => t.isSeedingStopped)
        .map((t) => t.taskId)
        .toList();

    final canPauseTasks = isCompletedTab
        ? canStopSeedingTasks
        : selectedTasks
            .where((t) =>
                t.taskId.startsWith('qb_') &&
                (t.status == TaskStatus.running || t.status == TaskStatus.pending || t.isSeeding))
            .map((t) => t.taskId)
            .toList();
    final canResumeTasks = isCompletedTab
        ? canResumeSeedingTasks
        : selectedTasks
            .where((t) =>
                t.taskId.startsWith('qb_') &&
                (t.status == TaskStatus.paused || t.isSeedingStopped))
            .map((t) => t.taskId)
            .toList();

    final List<PopupMenuEntry<String>> menuItems = [];

    if (isSingle && singleTask != null) {
      if (singleTask.isSeeding) {
        menuItems.add(const PopupMenuItem(
          value: 'pause',
          child: Row(
            children: [
              Icon(Icons.pause_circle_outline_rounded, size: 18, color: AppColors.warningOrange),
              SizedBox(width: 10),
              Text('停止做种', style: TextStyle(fontSize: 13)),
            ],
          ),
        ));
      } else if (canPauseTasks.isNotEmpty) {
        menuItems.add(const PopupMenuItem(
          value: 'pause',
          child: Row(
            children: [
              Icon(Icons.pause_circle_outline_rounded, size: 18, color: AppColors.warningOrange),
              SizedBox(width: 10),
              Text('暂停下载', style: TextStyle(fontSize: 13)),
            ],
          ),
        ));
      }
      if (singleTask.isSeedingStopped) {
        menuItems.add(const PopupMenuItem(
          value: 'resume',
          child: Row(
            children: [
              Icon(Icons.play_circle_outline_rounded, size: 18, color: AppColors.successGreen),
              SizedBox(width: 10),
              Text('继续做种', style: TextStyle(fontSize: 13)),
            ],
          ),
        ));
      } else if (canResumeTasks.isNotEmpty) {
        menuItems.add(const PopupMenuItem(
          value: 'resume',
          child: Row(
            children: [
              Icon(Icons.play_circle_outline_rounded, size: 18, color: AppColors.successGreen),
              SizedBox(width: 10),
              Text('恢复下载', style: TextStyle(fontSize: 13)),
            ],
          ),
        ));
      }
      if (singleTask.taskId.startsWith('qb_')) {
        menuItems.add(PopupMenuItem(
          value: 'recheck',
          child: Row(
            children: [
              Icon(Icons.refresh_rounded,
                  size: 18,
                  color: context.isDark ? AppColors.accentCyan : AppColors.primaryBlue),
              const SizedBox(width: 10),
              const Text('重新校验', style: TextStyle(fontSize: 13)),
            ],
          ),
        ));
      }
      menuItems.add(PopupMenuItem(
        value: 'copy_id',
        child: Row(
          children: [
            Icon(Icons.copy_rounded, size: 18, color: context.subtextColor),
            const SizedBox(width: 10),
            const Text('复制任务 ID', style: TextStyle(fontSize: 13)),
          ],
        ),
      ));
      if (singleTask.detail['url'] != null) {
        menuItems.add(PopupMenuItem(
          value: 'copy_url',
          child: Row(
            children: [
              Icon(Icons.link_rounded, size: 18, color: context.subtextColor),
              const SizedBox(width: 10),
              const Text('复制下载链接', style: TextStyle(fontSize: 13)),
            ],
          ),
        ));
      }
      menuItems.add(const PopupMenuDivider(height: 1));
      menuItems.add(const PopupMenuItem(
        value: 'delete',
        child: Row(
          children: [
            Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.errorRed),
            SizedBox(width: 10),
            Text('删除任务', style: TextStyle(fontSize: 13, color: AppColors.errorRed)),
          ],
        ),
      ));
    } else {
      if (canPauseTasks.isNotEmpty) {
        menuItems.add(PopupMenuItem(
          value: 'batch_pause',
          child: Row(
            children: [
              const Icon(Icons.pause_circle_outline_rounded, size: 18, color: AppColors.warningOrange),
              const SizedBox(width: 10),
              Text(
                isCompletedTab ? '批量停止做种 (${canPauseTasks.length})' : '批量暂停 (${canPauseTasks.length})',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ));
      }
      if (canResumeTasks.isNotEmpty) {
        menuItems.add(PopupMenuItem(
          value: 'batch_resume',
          child: Row(
            children: [
              const Icon(Icons.play_circle_outline_rounded, size: 18, color: AppColors.successGreen),
              const SizedBox(width: 10),
              Text(
                isCompletedTab ? '批量继续做种 (${canResumeTasks.length})' : '批量恢复 (${canResumeTasks.length})',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ));
      }
      menuItems.add(PopupMenuItem(
        value: 'batch_delete',
        child: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, size: 18, color: AppColors.errorRed),
            const SizedBox(width: 10),
            Text('批量删除 (${selectedTasks.length})',
                style: const TextStyle(fontSize: 13, color: AppColors.errorRed)),
          ],
        ),
      ));
      menuItems.add(const PopupMenuDivider(height: 1));
      menuItems.add(PopupMenuItem(
        value: 'select_all',
        child: Row(
          children: [
            Icon(Icons.select_all_rounded, size: 18, color: context.subtextColor),
            const SizedBox(width: 10),
            const Text('全选当前列表', style: TextStyle(fontSize: 13)),
          ],
        ),
      ));
      menuItems.add(PopupMenuItem(
        value: 'deselect',
        child: Row(
          children: [
            Icon(Icons.deselect_rounded, size: 18, color: context.tertiaryTextColor),
            const SizedBox(width: 10),
            const Text('取消选择', style: TextStyle(fontSize: 13)),
          ],
        ),
      ));
    }

    final messenger = ScaffoldMessenger.of(context);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: menuItems,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    if (selected == null || !mounted) return;

    switch (selected) {
      case 'pause':
        if (singleTask != null) {
          final isSeeding = singleTask.isSeeding;
          final ok = await taskProv.pauseTask(singleTask.taskId);
          messenger.showSnackBar(SnackBar(
            content: Text(ok ? (isSeeding ? '已停止做种' : '任务已暂停') : (isSeeding ? '停止做种失败' : '暂停失败')),
            backgroundColor: ok ? AppColors.warningOrange : AppColors.errorRed,
          ));
        }
        break;
      case 'resume':
        if (singleTask != null) {
          final isSeedingStopped = singleTask.isSeedingStopped;
          final ok = await taskProv.resumeTask(singleTask.taskId);
          messenger.showSnackBar(SnackBar(
            content: Text(ok ? (isSeedingStopped ? '已恢复做种' : '任务已恢复下载') : (isSeedingStopped ? '恢复做种失败' : '恢复失败')),
            backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
          ));
        }
        break;
      case 'recheck':
        if (singleTask != null) {
          final ok = await taskProv.recheckTask(singleTask.taskId);
          messenger.showSnackBar(SnackBar(
            content: Text(ok ? '已发送重新校验指令' : '重新校验失败'),
            backgroundColor: ok ? AppColors.primaryBlue : AppColors.errorRed,
          ));
        }
        break;
      case 'copy_id':
        if (singleTask != null) {
          await Clipboard.setData(ClipboardData(text: singleTask.taskId));
          messenger.showSnackBar(const SnackBar(content: Text('已复制任务 ID 到剪贴板')));
        }
        break;
      case 'copy_url':
        if (singleTask?.detail['url'] != null) {
          await Clipboard.setData(ClipboardData(text: singleTask!.detail['url'].toString()));
          messenger.showSnackBar(const SnackBar(content: Text('已复制下载链接到剪贴板')));
        }
        break;
      case 'delete':
        if (singleTask != null) {
          _showBatchDeleteDialog([singleTask.taskId]);
        }
        break;
      case 'batch_pause':
        final ok = await taskProv.batchPauseTasks(canPauseTasks);
        messenger.showSnackBar(SnackBar(
          content: Text(ok
              ? (isCompletedTab ? '已停止选中的 ${canPauseTasks.length} 项做种' : '已暂停选中的 ${canPauseTasks.length} 项')
              : (isCompletedTab ? '批量停止做种失败' : '批量暂停失败')),
          backgroundColor: ok ? AppColors.warningOrange : AppColors.errorRed,
        ));
        break;
      case 'batch_resume':
        final ok = await taskProv.batchResumeTasks(canResumeTasks);
        messenger.showSnackBar(SnackBar(
          content: Text(ok
              ? (isCompletedTab ? '已恢复选中的 ${canResumeTasks.length} 项做种' : '已恢复选中的 ${canResumeTasks.length} 项')
              : (isCompletedTab ? '批量继续做种失败' : '批量恢复失败')),
          backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
        ));
        break;
      case 'batch_delete':
        _showBatchDeleteDialog(selectedTasks.map((t) => t.taskId).toList());
        break;
      case 'select_all':
        setState(() {
          _selectedTaskIds.addAll(currentList.map((t) => t.taskId));
        });
        break;
      case 'deselect':
        setState(() {
          _selectedTaskIds.clear();
        });
        break;
    }
  }

  void _handleCardTap({
    required int index,
    required List<TaskItem> currentList,
    required bool isWideScreen,
  }) {
    final task = currentList[index];
    final isSelectionMode = _isSelectionMode || _selectedTaskIds.isNotEmpty;

    // 大屏时未进入批量管理模式前，左击鼠标不选中下载任务
    if (!isSelectionMode) {
      return;
    }

    setState(() {
      if (isWideScreen) {
        final isShift = HardwareKeyboard.instance.isShiftPressed;

        if (isShift && _lastFocusedIndex != null) {
          final start = index < _lastFocusedIndex! ? index : _lastFocusedIndex!;
          final end = index > _lastFocusedIndex! ? index : _lastFocusedIndex!;
          for (int i = start; i <= end; i++) {
            _selectedTaskIds.add(currentList[i].taskId);
          }
        } else {
          if (_selectedTaskIds.contains(task.taskId)) {
            _selectedTaskIds.remove(task.taskId);
          } else {
            _selectedTaskIds.add(task.taskId);
          }
          _lastFocusedIndex = index;
        }
      } else {
        if (_selectedTaskIds.contains(task.taskId)) {
          _selectedTaskIds.remove(task.taskId);
        } else {
          _selectedTaskIds.add(task.taskId);
        }
      }
    });
  }

  void _showDownloaderConfigDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const _DownloaderConfigDialog(),
    );
  }

  void _showDownloaderTestDialog() {
    final taskProv = context.read<TaskProvider>();
    taskProv.testDownloader('qbittorrent');

    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer<TaskProvider>(
          builder: (context, prov, _) {
            final isTesting = prov.isTestingDownloader;
            final status = prov.downloaderStatus;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.network_check_rounded, color: AppColors.primaryBlue),
                  SizedBox(width: 8),
                  Text('qBittorrent 连通性测试', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 380,
                child: isTesting
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 12),
                              Text('正在探测下载器连通状态...', style: TextStyle(color: context.subtextColor)),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (status != null) ...[
                            () {
                              final isSuccess = status['status'] == 'ok' || status['connected'] == true;
                              return Row(
                                children: [
                                  Icon(
                                    isSuccess
                                        ? Icons.check_circle_rounded
                                        : Icons.error_rounded,
                                    color: isSuccess
                                        ? AppColors.successGreen
                                        : AppColors.errorRed,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isSuccess ? '连通正常' : '连通异常',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isSuccess
                                        ? AppColors.successGreen
                                        : AppColors.errorRed,
                                    ),
                                  ),
                                ],
                              );
                            }(),
                            const SizedBox(height: 14),
                            if (status['version'] != null)
                              Text('内核版本: ${status['version']}',
                                  style: TextStyle(color: context.subtextColor)),
                            if (status['api_version'] != null)
                              Text('WebAPI 版本: ${status['api_version']}',
                                  style: TextStyle(color: context.subtextColor)),
                            if (status['total_torrents'] != null)
                              Text('种子总数: ${status['total_torrents']} (活跃中: ${status['active_torrents'] ?? 0})',
                                  style: TextStyle(color: context.subtextColor)),
                            if (status['error'] != null)
                              Text(
                                '错误信息: ${status['error']}',
                                style: const TextStyle(color: AppColors.errorRed, fontSize: 13),
                              ),
                          ] else
                            Text('未获取到状态响应', style: TextStyle(color: context.subtextColor)),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: isTesting ? null : () => prov.testDownloader('qbittorrent'),
                  child: Text('重新检测',
                      style: TextStyle(
                          color: context.isDark ? AppColors.accentCyan : AppColors.primaryBlue)),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreateTaskDialog() {
    final urlController = TextEditingController();
    final filenameController = TextEditingController();
    String selectedSaveDir = '/volume1/Download';
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.add_link_rounded, color: AppColors.primaryBlue),
                  SizedBox(width: 8),
                  Text('新建下载任务', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '支持 HTTP/HTTPS 直链、磁力链 (magnet:?)、.torrent 或流媒体视频 URL：',
                      style: TextStyle(fontSize: 12, color: context.subtextColor),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlController,
                      maxLines: 3,
                      minLines: 1,
                      decoration: const InputDecoration(
                        hintText: 'magnet:?xt=urn:btih:... 或 https://...',
                        prefixIcon: Icon(Icons.link_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('落盘存储目录：', style: TextStyle(fontSize: 12, color: context.subtextColor)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: selectedSaveDir,
                      items: const [
                        DropdownMenuItem(
                          value: '/volume1/Download',
                          child: Text(
                            '/volume1/Download (通用下载池)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: '/volume1/Media',
                          child: Text(
                            '/volume1/Media (影视媒体库)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedSaveDir = val);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: filenameController,
                      decoration: const InputDecoration(
                        labelText: '自定义文件名 (可选)',
                        hintText: '留空将由引擎自动识别',
                        prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  child: Text('取消', style: TextStyle(color: context.subtextColor)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final url = urlController.text.trim();
                          if (url.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请输入合法的下载链接或磁力链')),
                            );
                            return;
                          }
                          final taskProv = context.read<TaskProvider>();
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(ctx);
                          setDialogState(() => isSubmitting = true);
                          final success = await taskProv.createTask(
                            url: url,
                            saveDir: selectedSaveDir,
                            filename: filenameController.text.trim().isEmpty
                                ? null
                                : filenameController.text.trim(),
                          );
                          nav.pop();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(success ? '下载任务已成功下发！' : '创建下载任务失败'),
                              backgroundColor:
                                  success ? AppColors.successGreen : AppColors.errorRed,
                            ),
                          );
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('开始下载'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSmallScreenBottomBar(List<TaskItem> currentList, TaskProvider taskProv) {
    final selectedTasks = currentList.where((t) => _selectedTaskIds.contains(t.taskId)).toList();
    final isCompletedTab = _tabController.index == 2;
    final canStopSeedingTasks = selectedTasks
        .where((t) => t.isSeeding)
        .map((t) => t.taskId)
        .toList();
    final canResumeSeedingTasks = selectedTasks
        .where((t) => t.isSeedingStopped)
        .map((t) => t.taskId)
        .toList();
    final canPauseTasks = isCompletedTab
        ? canStopSeedingTasks
        : selectedTasks
            .where((t) =>
                t.taskId.startsWith('qb_') &&
                (t.status == TaskStatus.running || t.status == TaskStatus.pending || t.isSeeding))
            .map((t) => t.taskId)
            .toList();
    final canResumeTasks = isCompletedTab
        ? canResumeSeedingTasks
        : selectedTasks
            .where((t) =>
                t.taskId.startsWith('qb_') &&
                (t.status == TaskStatus.paused || t.isSeedingStopped))
            .map((t) => t.taskId)
            .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(context.isDark ? 0.4 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已选 ${_selectedTaskIds.length} 项',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: context.isDark ? Colors.white : AppColors.lightTitle,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_selectedTaskIds.length == currentList.length) {
                        _selectedTaskIds.clear();
                      } else {
                        _selectedTaskIds.addAll(currentList.map((t) => t.taskId));
                      }
                    });
                  },
                  child: Text(
                    _selectedTaskIds.length == currentList.length ? '取消全选' : '全选',
                    style: TextStyle(
                        fontSize: 11,
                        color: context.isDark ? AppColors.accentCyan : AppColors.primaryBlue),
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (canPauseTasks.isNotEmpty)
              IconButton(
                tooltip: isCompletedTab ? '批量停止做种 (${canPauseTasks.length})' : '批量暂停 (${canPauseTasks.length})',
                icon: const Icon(Icons.pause_circle_outline_rounded,
                    color: AppColors.warningOrange, size: 24),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await taskProv.batchPauseTasks(canPauseTasks);
                  messenger.showSnackBar(SnackBar(
                    content: Text(ok
                        ? (isCompletedTab ? '已停止选中的 ${canPauseTasks.length} 项做种' : '已暂停选中的 ${canPauseTasks.length} 项')
                        : (isCompletedTab ? '批量停止做种失败' : '批量暂停失败')),
                    backgroundColor: ok ? AppColors.warningOrange : AppColors.errorRed,
                  ));
                },
              ),
            if (canResumeTasks.isNotEmpty)
              IconButton(
                tooltip: isCompletedTab ? '批量继续做种 (${canResumeTasks.length})' : '批量恢复 (${canResumeTasks.length})',
                icon: const Icon(Icons.play_circle_outline_rounded,
                    color: AppColors.successGreen, size: 24),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await taskProv.batchResumeTasks(canResumeTasks);
                  messenger.showSnackBar(SnackBar(
                    content: Text(ok
                        ? (isCompletedTab ? '已恢复选中的 ${canResumeTasks.length} 项做种' : '已恢复选中的 ${canResumeTasks.length} 项')
                        : (isCompletedTab ? '批量继续做种失败' : '批量恢复失败')),
                    backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
                  ));
                },
              ),
            IconButton(
              tooltip: '批量删除 (${selectedTasks.length})',
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.errorRed, size: 24),
              onPressed: () =>
                  _showBatchDeleteDialog(selectedTasks.map((t) => t.taskId).toList()),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedTaskIds.clear();
                  _isSelectionMode = false;
                });
              },
              child: Text('退出', style: TextStyle(color: context.subtextColor)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    final taskProv = context.watch<TaskProvider>();
    final isWs = WebSocketService.instance.isConnected;

    if (!conn.isConnected) {
      return Scaffold(
        appBar: AppBar(title: const Text('下载管理中心')),
        body: Center(
          child: Text('请先连接至 NAS 服务端', style: TextStyle(color: context.subtextColor)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 720;
        final isCompactBar = constraints.maxWidth < 480;
        final hasFailedTasks = taskProv.failedTasks.isNotEmpty;
        final isCompletedTab = _tabController.index == 2;

        List<TaskItem> currentList;
        switch (_tabController.index) {
          case 0:
            currentList = taskProv.activeTasks;
            break;
          case 2:
            currentList = taskProv.completedTasks;
            break;
          case 1:
          default:
            currentList = taskProv.allTasks;
            break;
        }
        currentList = _sortTasks(currentList, _tabSortStates[_tabController.index]);

        final selectedTasks = currentList.where((t) => _selectedTaskIds.contains(t.taskId)).toList();
        final canStopSeedingTasks = selectedTasks
            .where((t) => t.isSeeding)
            .map((t) => t.taskId)
            .toList();
        final canResumeSeedingTasks = selectedTasks
            .where((t) => t.isSeedingStopped)
            .map((t) => t.taskId)
            .toList();
        final canPauseTasks = isCompletedTab
            ? canStopSeedingTasks
            : selectedTasks
                .where((t) =>
                    t.taskId.startsWith('qb_') &&
                    (t.status == TaskStatus.running || t.status == TaskStatus.pending || t.isSeeding))
                .map((t) => t.taskId)
                .toList();
        final canResumeTasks = isCompletedTab
            ? canResumeSeedingTasks
            : selectedTasks
                .where((t) =>
                    t.taskId.startsWith('qb_') &&
                    (t.status == TaskStatus.paused || t.isSeedingStopped))
                .map((t) => t.taskId)
                .toList();

        final showSmallScreenBottomBar = !isWideScreen && _selectedTaskIds.isNotEmpty;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: '返回主页',
              onPressed: () => HomeScaffold.switchToTab(context, 0),
            ),
            titleSpacing: isCompactBar ? 4 : null,
            title: _selectedTaskIds.isNotEmpty
                ? Row(
                    children: [
                      Text(
                        '已选 ${_selectedTaskIds.length} 项',
                        style: TextStyle(fontSize: isCompactBar ? 15 : 17, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (_selectedTaskIds.length == currentList.length) {
                              _selectedTaskIds.clear();
                            } else {
                              _selectedTaskIds.addAll(currentList.map((t) => t.taskId));
                            }
                          });
                        },
                        child: Text(
                          _selectedTaskIds.length == currentList.length ? '取消全选' : '全选',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.isDark ? AppColors.accentCyan : AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  )
                : Text(
                    '下载管理中心',
                    style: TextStyle(fontSize: isCompactBar ? 16 : 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
            actions: _selectedTaskIds.isNotEmpty
                ? [
                    if (isCompletedTab) ...[
                      if (canStopSeedingTasks.isNotEmpty) ...[
                        if (isWideScreen)
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.warningOrange.withOpacity(0.15),
                              foregroundColor: AppColors.warningOrange,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.pause_circle_outline_rounded, size: 16),
                            label: Text('批量停止做种 (${canStopSeedingTasks.length})',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await taskProv.batchPauseTasks(canStopSeedingTasks);
                              messenger.showSnackBar(SnackBar(
                                content: Text(ok ? '已停止选中的 ${canStopSeedingTasks.length} 项做种' : '批量停止做种失败'),
                                backgroundColor: ok ? AppColors.warningOrange : AppColors.errorRed,
                              ));
                            },
                          )
                        else
                          IconButton(
                            tooltip: '批量停止做种 (${canStopSeedingTasks.length})',
                            icon: const Icon(Icons.pause_circle_outline_rounded, color: AppColors.warningOrange),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await taskProv.batchPauseTasks(canStopSeedingTasks);
                              messenger.showSnackBar(SnackBar(
                                content: Text(ok ? '已停止选中的 ${canStopSeedingTasks.length} 项做种' : '批量停止做种失败'),
                                backgroundColor: ok ? AppColors.warningOrange : AppColors.errorRed,
                              ));
                            },
                          ),
                        const SizedBox(width: 6),
                      ],
                      if (canResumeSeedingTasks.isNotEmpty) ...[
                        if (isWideScreen)
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.successGreen.withOpacity(0.15),
                              foregroundColor: AppColors.successGreen,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
                            label: Text('批量继续做种 (${canResumeSeedingTasks.length})',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await taskProv.batchResumeTasks(canResumeSeedingTasks);
                              messenger.showSnackBar(SnackBar(
                                content: Text(ok ? '已恢复选中的 ${canResumeSeedingTasks.length} 项做种' : '批量继续做种失败'),
                                backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
                              ));
                            },
                          )
                        else
                          IconButton(
                            tooltip: '批量继续做种 (${canResumeSeedingTasks.length})',
                            icon: const Icon(Icons.play_circle_outline_rounded, color: AppColors.successGreen),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await taskProv.batchResumeTasks(canResumeSeedingTasks);
                              messenger.showSnackBar(SnackBar(
                                content: Text(ok ? '已恢复选中的 ${canResumeSeedingTasks.length} 项做种' : '批量继续做种失败'),
                                backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
                              ));
                            },
                          ),
                        const SizedBox(width: 6),
                      ],
                    ] else ...[
                      if (canPauseTasks.isNotEmpty) ...[
                        if (isWideScreen)
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.warningOrange.withOpacity(0.15),
                              foregroundColor: AppColors.warningOrange,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.pause_circle_outline_rounded, size: 16),
                            label: Text('批量暂停 (${canPauseTasks.length})',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await taskProv.batchPauseTasks(canPauseTasks);
                              messenger.showSnackBar(SnackBar(
                                content: Text(ok ? '已暂停选中的 ${canPauseTasks.length} 项' : '批量暂停失败'),
                                backgroundColor: ok ? AppColors.warningOrange : AppColors.errorRed,
                              ));
                            },
                          )
                        else
                          IconButton(
                            tooltip: '批量暂停 (${canPauseTasks.length})',
                            icon: const Icon(Icons.pause_circle_outline_rounded, color: AppColors.warningOrange),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await taskProv.batchPauseTasks(canPauseTasks);
                              messenger.showSnackBar(SnackBar(
                                content: Text(ok ? '已暂停选中的 ${canPauseTasks.length} 项' : '批量暂停失败'),
                                backgroundColor: ok ? AppColors.warningOrange : AppColors.errorRed,
                              ));
                            },
                          ),
                        const SizedBox(width: 6),
                      ],
                      if (canResumeTasks.isNotEmpty) ...[
                        if (isWideScreen)
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.successGreen.withOpacity(0.15),
                              foregroundColor: AppColors.successGreen,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
                            label: Text('批量恢复 (${canResumeTasks.length})',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await taskProv.batchResumeTasks(canResumeTasks);
                              messenger.showSnackBar(SnackBar(
                                content: Text(ok ? '已恢复选中的 ${canResumeTasks.length} 项' : '批量恢复失败'),
                                backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
                              ));
                            },
                          )
                        else
                          IconButton(
                            tooltip: '批量恢复 (${canResumeTasks.length})',
                            icon: const Icon(Icons.play_circle_outline_rounded, color: AppColors.successGreen),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await taskProv.batchResumeTasks(canResumeTasks);
                              messenger.showSnackBar(SnackBar(
                                content: Text(ok ? '已恢复选中的 ${canResumeTasks.length} 项' : '批量恢复失败'),
                                backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
                              ));
                            },
                          ),
                        const SizedBox(width: 6),
                      ],
                    ],
                    if (isWideScreen)
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.errorRed.withOpacity(0.15),
                          foregroundColor: AppColors.errorRed,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        label: Text('批量删除 (${selectedTasks.length})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () =>
                            _showBatchDeleteDialog(selectedTasks.map((t) => t.taskId).toList()),
                      )
                    else
                      IconButton(
                        tooltip: '批量删除 (${selectedTasks.length})',
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.errorRed),
                        onPressed: () =>
                            _showBatchDeleteDialog(selectedTasks.map((t) => t.taskId).toList()),
                      ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: '退出多选',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _selectedTaskIds.clear();
                        _isSelectionMode = false;
                      }),
                    ),
                    SizedBox(width: isCompactBar ? 8 : 12),
                  ]
                : [
                    // WebSocket 状态指示
                    Tooltip(
                      message: isWs ? 'WS 实时流' : 'WS 离线',
                      child: Container(
                        margin: EdgeInsets.only(right: isCompactBar ? 4 : 8),
                        padding: EdgeInsets.symmetric(horizontal: isCompactBar ? 6 : 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isWs ? AppColors.successGreen : Colors.grey).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isWs ? AppColors.successGreen : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            if (!isCompactBar) ...[
                              const SizedBox(width: 6),
                              Text(
                                isWs ? 'WS 实时流' : 'WS 离线',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isWs ? AppColors.successGreen : Colors.grey,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    // 已完成 Tab 下且有失败任务时，展示清空失败任务按钮
                    if (isCompletedTab && hasFailedTasks)
                      if (isWideScreen)
                        TextButton.icon(
                          onPressed: _showClearFailedDialog,
                          icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.errorRed, size: 18),
                          label: Text(
                            '清空失败 (${taskProv.failedTasks.length})',
                            style: const TextStyle(color: AppColors.errorRed, fontSize: 13),
                          ),
                        )
                      else
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: _showClearFailedDialog,
                          tooltip: '清空失败 (${taskProv.failedTasks.length})',
                          icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.errorRed, size: 20),
                        ),
                    IconButton(
                      visualDensity: isWideScreen ? null : VisualDensity.compact,
                      icon: Icon(_isSelectionMode ? Icons.check_box_rounded : Icons.checklist_rounded),
                      tooltip: _isSelectionMode ? '退出批量' : '批量管理',
                      color: _isSelectionMode
                          ? (context.isDark ? AppColors.accentCyan : AppColors.primaryBlue)
                          : null,
                      onPressed: () {
                        setState(() {
                          _isSelectionMode = !_isSelectionMode;
                          if (!_isSelectionMode) {
                            _selectedTaskIds.clear();
                          }
                        });
                      },
                    ),
                    IconButton(
                      visualDensity: isWideScreen ? null : VisualDensity.compact,
                      icon: const Icon(Icons.tune_rounded),
                      tooltip: '下载参数配置 (限速/默认路径)',
                      onPressed: _showDownloaderConfigDialog,
                    ),
                    IconButton(
                      visualDensity: isWideScreen ? null : VisualDensity.compact,
                      icon: const Icon(Icons.downloading_rounded),
                      tooltip: '测试 qBittorrent 状态',
                      onPressed: _showDownloaderTestDialog,
                    ),
                    IconButton(
                      visualDensity: isWideScreen ? null : VisualDensity.compact,
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: '刷新列表',
                      onPressed: () => taskProv.loadTasks(),
                    ),
                    const SizedBox(width: 4),
                    if (isCompactBar)
                      IconButton.filled(
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                        ),
                        tooltip: '新建任务',
                        onPressed: _showCreateTaskDialog,
                        icon: const Icon(Icons.add_link_rounded, size: 18),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _showCreateTaskDialog,
                        icon: const Icon(Icons.add_link_rounded, size: 18),
                        label: Text(isWideScreen ? '新建下载任务' : '新建任务'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: isWideScreen ? 14 : 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    SizedBox(width: isCompactBar ? 8 : 12),
                  ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primaryBlue,
              labelColor: context.isDark ? Colors.white : AppColors.primaryBlue,
              unselectedLabelColor: context.subtextColor,
              tabs: [
                Tab(text: '进行中 (${taskProv.activeTasks.length})'),
                Tab(text: '全部任务 (${taskProv.allTasks.length})'),
                Tab(text: '已完成 (${taskProv.completedTasks.length})'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildTaskList(taskProv.activeTasks, '当前没有正在执行中的任务', taskProv, isWideScreen, 0),
              _buildTaskList(taskProv.allTasks, '任务队列为空', taskProv, isWideScreen, 1),
              _buildTaskList(taskProv.completedTasks, '暂无已完成下载任务', taskProv, isWideScreen, 2),
            ],
          ),
          bottomNavigationBar:
              showSmallScreenBottomBar ? _buildSmallScreenBottomBar(currentList, taskProv) : null,
        );
      },
    );
  }

  int _statusWeight(TaskStatus s) {
    switch (s) {
      case TaskStatus.running:
        return 0; // 下载中最先
      case TaskStatus.pending:
        return 1; // 等待中
      case TaskStatus.paused:
        return 2; // 已暂停
      case TaskStatus.completed:
        return 3; // 已完成
      case TaskStatus.failed:
        return 4; // 失败
      case TaskStatus.cancelled:
        return 5; // 取消
    }
  }

  double _parseSpeedToBytes(String speedStr) {
    final clean = speedStr.replaceAll(RegExp(r'[↓↑\s]'), '').toUpperCase();
    if (clean.endsWith('GB/S')) {
      final numStr = clean.replaceAll('GB/S', '');
      return (double.tryParse(numStr) ?? 0.0) * 1024 * 1024 * 1024;
    } else if (clean.endsWith('MB/S')) {
      final numStr = clean.replaceAll('MB/S', '');
      return (double.tryParse(numStr) ?? 0.0) * 1024 * 1024;
    } else if (clean.endsWith('KB/S')) {
      final numStr = clean.replaceAll('KB/S', '');
      return (double.tryParse(numStr) ?? 0.0) * 1024;
    } else if (clean.endsWith('B/S')) {
      final numStr = clean.replaceAll('B/S', '');
      return double.tryParse(numStr) ?? 0.0;
    }
    return 0.0;
  }

  List<TaskItem> _sortTasks(List<TaskItem> list, TabSortState sortState) {
    final copy = List<TaskItem>.from(list);
    copy.sort((a, b) {
      int cmp = 0;
      switch (sortState.field) {
        case TaskSortField.status:
          cmp = _statusWeight(a.status).compareTo(_statusWeight(b.status));
          break;
        case TaskSortField.name:
          cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case TaskSortField.progress:
          cmp = a.progress.compareTo(b.progress);
          break;
        case TaskSortField.speed:
          cmp = _parseSpeedToBytes(a.speed).compareTo(_parseSpeedToBytes(b.speed));
          break;
        case TaskSortField.createdAt:
          cmp = a.createdAt.compareTo(b.createdAt);
          break;
      }
      if (cmp != 0) {
        return sortState.isAscending ? cmp : -cmp;
      }
      // 二级排序：相同条件下一律按添加时间倒序（最新的排在前面）
      return b.createdAt.compareTo(a.createdAt);
    });
    return copy;
  }

  void _onSortColumnTapped(int tabIndex, TaskSortField field) {
    setState(() {
      final current = _tabSortStates[tabIndex];
      if (current.field == field) {
        current.isAscending = !current.isAscending;
      } else {
        current.field = field;
        if (field == TaskSortField.name || field == TaskSortField.status) {
          current.isAscending = true;
        } else {
          current.isAscending = false;
        }
      }
    });
  }

  Widget _buildTableHeader(int tabIndex, TabSortState sortState, bool isWideScreen) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: context.isDark
            ? const Color(0xFF1E293B).withOpacity(0.55)
            : const Color(0xFFE2E8F0).withOpacity(0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.customBorderColor),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: _buildHeaderItem(
              label: '任务名称',
              field: TaskSortField.name,
              sortState: sortState,
              alignment: Alignment.centerLeft,
              onTap: () => _onSortColumnTapped(tabIndex, TaskSortField.name),
            ),
          ),
          SizedBox(
            width: isWideScreen ? 90 : 75,
            child: _buildHeaderItem(
              label: '状态',
              field: TaskSortField.status,
              sortState: sortState,
              alignment: Alignment.center,
              onTap: () => _onSortColumnTapped(tabIndex, TaskSortField.status),
            ),
          ),
          SizedBox(
            width: isWideScreen ? 85 : 70,
            child: _buildHeaderItem(
              label: '进度',
              field: TaskSortField.progress,
              sortState: sortState,
              alignment: Alignment.center,
              onTap: () => _onSortColumnTapped(tabIndex, TaskSortField.progress),
            ),
          ),
          SizedBox(
            width: isWideScreen ? 115 : 85,
            child: _buildHeaderItem(
              label: '实时速度',
              field: TaskSortField.speed,
              sortState: sortState,
              alignment: Alignment.centerRight,
              onTap: () => _onSortColumnTapped(tabIndex, TaskSortField.speed),
            ),
          ),
          if (isWideScreen)
            SizedBox(
              width: 105,
              child: _buildHeaderItem(
                label: '添加时间',
                field: TaskSortField.createdAt,
                sortState: sortState,
                alignment: Alignment.centerRight,
                onTap: () => _onSortColumnTapped(tabIndex, TaskSortField.createdAt),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderItem({
    required String label,
    required TaskSortField field,
    required TabSortState sortState,
    required Alignment alignment,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final isSelected = sortState.field == field;
    final color = isSelected
        ? (context.isDark ? AppColors.accentCyan : AppColors.primaryBlue)
        : (context.isDark ? Colors.white60 : AppColors.lightSubtext);

    return Tooltip(
      message: tooltip ?? '点击按$label${isSelected ? (sortState.isAscending ? "降序" : "升序") : "排序"}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: context.isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Align(
            alignment: alignment,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 2),
                if (isSelected)
                  Icon(
                    sortState.isAscending ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                    size: 18,
                    color: context.isDark ? AppColors.accentCyan : AppColors.primaryBlue,
                  )
                else
                  Icon(
                    Icons.unfold_more_rounded,
                    size: 13,
                    color: context.isDark ? Colors.white24 : Colors.black26,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskList(
    List<TaskItem> tasks,
    String emptyText,
    TaskProvider taskProv,
    bool isWideScreen,
    int tabIndex,
  ) {
    if (taskProv.isLoading && tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 56, color: context.tertiaryTextColor),
            const SizedBox(height: 12),
            Text(emptyText, style: TextStyle(color: context.subtextColor, fontSize: 14)),
          ],
        ),
      );
    }

    final sortState = _tabSortStates[tabIndex];
    final sortedTasks = _sortTasks(tasks, sortState);
    final isSelectionMode = _isSelectionMode || _selectedTaskIds.isNotEmpty;

    return RefreshIndicator(
      onRefresh: () => taskProv.loadTasks(),
      child: Column(
        children: [
          _buildTableHeader(tabIndex, sortState, isWideScreen),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 16.0),
              itemCount: sortedTasks.length,
              itemBuilder: (ctx, idx) {
                final t = sortedTasks[idx];
                final isSelected = _selectedTaskIds.contains(t.taskId);

                return TaskCard(
                  task: t,
                  isSelected: isSelected,
                  isSelectionMode: isSelectionMode,
                  isWideScreen: isWideScreen,
                  onTap: () {
                    _handleCardTap(
                      index: idx,
                      currentList: sortedTasks,
                      isWideScreen: isWideScreen,
                    );
                  },
                  onLongPress: () {
                    setState(() {
                      _isSelectionMode = true;
                      _selectedTaskIds.add(t.taskId);
                      _lastFocusedIndex = idx;
                    });
                  },
                  onSecondaryTapDown: (details) {
                    if (isWideScreen) {
                      final wasSelectionMode = _isSelectionMode;
                      setState(() {
                        if (!_selectedTaskIds.contains(t.taskId)) {
                          _selectedTaskIds.clear();
                          _selectedTaskIds.add(t.taskId);
                          _lastFocusedIndex = idx;
                        }
                      });
                      _showContextMenu(
                        context: context,
                        position: details.globalPosition,
                        currentList: sortedTasks,
                        taskProv: taskProv,
                      ).then((_) {
                        if (!wasSelectionMode && !_isSelectionMode && mounted) {
                          setState(() {
                            _selectedTaskIds.clear();
                          });
                        }
                      });
                    }
                  },
                  onPause: () async {
                    final ok = await taskProv.pauseTask(t.taskId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok ? '任务已暂停' : '暂停失败'),
                          backgroundColor: ok ? AppColors.warningOrange : AppColors.errorRed,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  onResume: () async {
                    final ok = await taskProv.resumeTask(t.taskId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok ? '任务已恢复下载' : '恢复失败'),
                          backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  onRecheck: () async {
                    final ok = await taskProv.recheckTask(t.taskId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok ? '已发送重新校验指令' : '重新校验失败'),
                          backgroundColor: ok ? AppColors.primaryBlue : AppColors.errorRed,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  onDelete: (deleteFiles) async {
                    final ok = await taskProv.deleteTask(t.taskId, deleteFiles: deleteFiles);
                    if (mounted) {
                      setState(() {
                        _selectedTaskIds.remove(t.taskId);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok ? (deleteFiles ? '任务及本地文件已彻底删除' : '任务已删除') : '删除失败'),
                          backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  onCancel: () async {
                    final ok = await taskProv.cancelTask(t.taskId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok ? '任务已成功取消' : '取消失败'),
                          backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
                        ),
                      );
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloaderConfigDialog extends StatefulWidget {
  const _DownloaderConfigDialog();

  @override
  State<_DownloaderConfigDialog> createState() => _DownloaderConfigDialogState();
}

class _DownloaderConfigDialogState extends State<_DownloaderConfigDialog> {
  late final TextEditingController _dlLimitController;
  late final TextEditingController _upLimitController;
  late final TextEditingController _maxDlController;
  late final TextEditingController _maxTotalController;
  late final TextEditingController _categoryController;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _queueingEnabled = true;
  bool _autoStopSeeding = false;
  String _selectedSavePath = '/volume1/Download';
  List<String> _allowedPaths = ['/volume1/Download', '/volume1/Media'];
  DownloaderConfigModel? _config;

  @override
  void initState() {
    super.initState();
    _dlLimitController = TextEditingController();
    _upLimitController = TextEditingController();
    _maxDlController = TextEditingController();
    _maxTotalController = TextEditingController();
    _categoryController = TextEditingController();

    final cachedCfg = context.read<TaskProvider>().downloaderConfig;
    if (cachedCfg != null) {
      _applyConfig(cachedCfg);
      _isLoading = false;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadConfig();
      }
    });
  }

  @override
  void dispose() {
    _dlLimitController.dispose();
    _upLimitController.dispose();
    _maxDlController.dispose();
    _maxTotalController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final taskProv = context.read<TaskProvider>();
    if (_config == null) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      await taskProv.loadDownloaderConfig();
    } catch (_) {
      // taskProv.errorMessage 记录错误
    } finally {
      if (mounted) {
        final cfg = taskProv.downloaderConfig;
        if (cfg != null) {
          _applyConfig(cfg);
        }
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _applyConfig(DownloaderConfigModel config) {
    _config = config;
    _dlLimitController.text = '${config.qbittorrent.downloadLimitKb}';
    _upLimitController.text = '${config.qbittorrent.uploadLimitKb}';
    _maxDlController.text = config.qbittorrent.maxActiveDownloads >= 999
        ? '-1'
        : '${config.qbittorrent.maxActiveDownloads}';
    _maxTotalController.text = config.qbittorrent.maxActiveTorrents >= 999
        ? '-1'
        : '${config.qbittorrent.maxActiveTorrents}';
    _categoryController.text = config.qbittorrent.defaultCategory;
    _queueingEnabled = config.qbittorrent.queueingEnabled;
    _autoStopSeeding = config.qbittorrent.autoStopSeeding;
    _selectedSavePath = config.qbittorrent.defaultSavePath;
    final paths = List<String>.from(config.allowedPaths);
    if (!paths.contains(config.qbittorrent.defaultSavePath)) {
      paths.insert(0, config.qbittorrent.defaultSavePath);
    }
    _allowedPaths = paths.isNotEmpty ? paths : ['/volume1/Download', '/volume1/Media'];
  }

  @override
  Widget build(BuildContext context) {
    final taskProv = context.read<TaskProvider>();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.tune_rounded,
              color: context.isDark ? AppColors.accentCyan : AppColors.primaryBlue),
          const SizedBox(width: 8),
          const Text('下载参数全局配置', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: _isLoading && _config == null
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator()),
              )
            : _config == null
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.errorRed, size: 36),
                        const SizedBox(height: 12),
                        Text(
                          taskProv.errorMessage ?? '获取下载器配置失败，请检查网络或外部下载器状态',
                          style: TextStyle(color: context.subtextColor, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadConfig,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, dialogConstraints) {
                      final isNarrowDialog = dialogConstraints.maxWidth < 380;
                      return SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '在此动态调节 qBittorrent 的下载限速、并发队列与默认路径：',
                              style: TextStyle(fontSize: 12, color: context.subtextColor),
                            ),
                            const SizedBox(height: 16),
                            // 1. 全局限速
                            Text('带宽限速控制',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: context.isDark
                                        ? AppColors.accentCyan
                                        : AppColors.primaryBlueDark)),
                            const SizedBox(height: 8),
                            if (isNarrowDialog) ...[
                              TextField(
                                controller: _dlLimitController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '全局下载限速 (KB/s)',
                                  hintText: '0 为不限速',
                                  prefixIcon: Icon(Icons.arrow_downward_rounded),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _upLimitController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '全局上传限速 (KB/s)',
                                  hintText: '0 为不限速',
                                  prefixIcon: Icon(Icons.arrow_upward_rounded),
                                ),
                              ),
                            ] else
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _dlLimitController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: '全局下载限速 (KB/s)',
                                        hintText: '0 为不限速',
                                        prefixIcon: Icon(Icons.arrow_downward_rounded),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _upLimitController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: '全局上传限速 (KB/s)',
                                        hintText: '0 为不限速',
                                        prefixIcon: Icon(Icons.arrow_upward_rounded),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 20),
                            // 2. 并发队列
                            Text('并发与队列控制',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: context.isDark
                                        ? AppColors.accentCyan
                                        : AppColors.primaryBlueDark)),
                            const SizedBox(height: 8),
                            if (isNarrowDialog) ...[
                              TextField(
                                controller: _maxDlController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '最大同时下载数',
                                  hintText: '0 或 -1 为不限',
                                  prefixIcon: Icon(Icons.speed_rounded),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _maxTotalController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '最大总活动任务数',
                                  hintText: '0 或 -1 为不限',
                                  prefixIcon: Icon(Icons.format_list_numbered_rounded),
                                ),
                              ),
                            ] else
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _maxDlController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: '最大同时下载数',
                                        hintText: '0 或 -1 为不限',
                                        prefixIcon: Icon(Icons.speed_rounded),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _maxTotalController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: '最大总活动任务数',
                                        hintText: '0 或 -1 为不限',
                                        prefixIcon: Icon(Icons.format_list_numbered_rounded),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: context.isDark
                                    ? Colors.white.withOpacity(0.03)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: context.isDark ? Colors.white10 : AppColors.lightBorder),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('启用排队调度机制', style: TextStyle(fontSize: 13)),
                                        Text('开启后超额任务将自动等待排队',
                                            style: TextStyle(
                                                fontSize: 11, color: context.tertiaryTextColor)),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _queueingEnabled,
                                    activeColor: AppColors.primaryBlue,
                                    onChanged: (val) => setState(() => _queueingEnabled = val),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: context.isDark
                                    ? Colors.white.withOpacity(0.03)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: context.isDark ? Colors.white10 : AppColors.lightBorder),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('下载完成时自动停止做种', style: TextStyle(fontSize: 13)),
                                        Text('开启后任务下载完成自动转为已停止做种，避免持续上传',
                                            style: TextStyle(
                                                fontSize: 11, color: context.tertiaryTextColor)),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _autoStopSeeding,
                                    activeColor: AppColors.primaryBlue,
                                    onChanged: (val) => setState(() => _autoStopSeeding = val),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            // 3. 存储与分类
                            Text('保存路径与任务分类',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: context.isDark
                                        ? AppColors.accentCyan
                                        : AppColors.primaryBlueDark)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: '默认下载保存路径',
                                prefixIcon: Icon(Icons.folder_open_rounded),
                              ),
                              value: _allowedPaths.contains(_selectedSavePath)
                                  ? _selectedSavePath
                                  : (_allowedPaths.isNotEmpty ? _allowedPaths.first : null),
                              items: _allowedPaths.map((p) {
                                return DropdownMenuItem(
                                  value: p,
                                  child: Text(
                                    p,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedSavePath = val);
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _categoryController,
                              decoration: const InputDecoration(
                                labelText: '默认任务分类标签',
                                hintText: '如 nasio',
                                prefixIcon: Icon(Icons.label_outline_rounded),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.isDark
                                    ? Colors.white.withOpacity(0.04)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 16, color: context.subtextColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '当前下载引擎: ${_config?.defaultEngine ?? "qbittorrent"} (地址: ${_config?.qbittorrent.url ?? "-"})',
                                      style: TextStyle(fontSize: 11, color: context.subtextColor),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
          onPressed: (_isSaving || _config == null)
              ? null
              : () async {
                  final dlVal = int.tryParse(_dlLimitController.text.trim());
                  final upVal = int.tryParse(_upLimitController.text.trim());
                  final maxDlVal = int.tryParse(_maxDlController.text.trim());
                  final maxTotalVal = int.tryParse(_maxTotalController.text.trim());
                  final effectiveMaxDl = (maxDlVal != null && maxDlVal <= 0) ? 999 : maxDlVal;
                  final effectiveMaxTotal = (maxTotalVal != null && maxTotalVal <= 0) ? 999 : maxTotalVal;
                  final catVal = _categoryController.text.trim();
                  final messenger = ScaffoldMessenger.of(context);
                  final nav = Navigator.of(context);

                  setState(() => _isSaving = true);
                  final ok = await taskProv.updateDownloaderConfig(
                    downloadLimitKb: dlVal,
                    uploadLimitKb: upVal,
                    defaultSavePath: _selectedSavePath,
                    maxActiveDownloads: effectiveMaxDl,
                    maxActiveTorrents: effectiveMaxTotal,
                    defaultCategory: catVal.isNotEmpty ? catVal : null,
                    queueingEnabled: _queueingEnabled,
                    autoStopSeeding: _autoStopSeeding,
                  );

                  if (mounted) {
                    if (ok) {
                      nav.pop();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('下载参数配置已保存生效！'),
                          backgroundColor: AppColors.successGreen,
                        ),
                      );
                    } else {
                      setState(() => _isSaving = false);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(taskProv.errorMessage ?? '保存配置失败'),
                          backgroundColor: AppColors.errorRed,
                        ),
                      );
                    }
                  }
                },
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存生效'),
        ),
      ],
    );
  }
}

