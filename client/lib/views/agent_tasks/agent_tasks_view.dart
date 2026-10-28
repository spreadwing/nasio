import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/agent_task_model.dart';
import '../../models/missing_mcp_model.dart';
import '../../models/task_model.dart';
import '../../providers/agent_task_provider.dart';
import '../../providers/missing_mcp_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/connection_provider.dart';
import '../../core/utils/formatters.dart';
import '../home_scaffold.dart';

class AgentTasksView extends StatefulWidget {
  const AgentTasksView({super.key});

  @override
  State<AgentTasksView> createState() => _AgentTasksViewState();
}

class _AgentTasksViewState extends State<AgentTasksView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _wasConnected = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final conn = context.read<ConnectionProvider>();
      if (conn.isConnected) {
        _wasConnected = true;
        context.read<AgentTaskProvider>().loadTasks();
        context.read<MissingMcpProvider>().loadItems();
        context.read<TaskProvider>().loadTasks(silent: true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final conn = context.watch<ConnectionProvider>();
    if (conn.isConnected && !_wasConnected) {
      _wasConnected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<AgentTaskProvider>().loadTasks();
          context.read<MissingMcpProvider>().loadItems();
          context.read<TaskProvider>().loadTasks(silent: true);
        }
      });
    } else if (!conn.isConnected) {
      _wasConnected = false;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatTime(double sec) {
    if (sec <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch((sec * 1000).toInt());
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  Widget _buildStatusChip(String status) {
    Color bg;
    Color fg;
    String text;
    IconData icon;

    switch (status.toUpperCase()) {
      case 'RUNNING':
        bg = AppColors.primaryBlue.withOpacity(0.2);
        fg = AppColors.primaryBlue;
        text = '进行中';
        icon = Icons.sync_rounded;
        break;
      case 'COMPLETED':
        bg = AppColors.successGreen.withOpacity(0.2);
        fg = AppColors.successGreen;
        text = '已完成';
        icon = Icons.check_circle_rounded;
        break;
      case 'FAILED':
        bg = AppColors.errorRed.withOpacity(0.2);
        fg = AppColors.errorRed;
        text = '失败';
        icon = Icons.error_rounded;
        break;
      case 'CANCELLED':
        bg = context.isDark ? Colors.white12 : Colors.black.withOpacity(0.06);
        fg = context.subtextColor;
        text = '已取消';
        icon = Icons.cancel_outlined;
        break;
      default:
        bg = context.isDark ? Colors.white12 : Colors.black.withOpacity(0.06);
        fg = context.isDark ? Colors.white70 : AppColors.lightTitle;
        text = status;
        icon = Icons.help_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    final agentProv = context.watch<AgentTaskProvider>();
    final missingMcpProv = context.watch<MissingMcpProvider>();
    final taskProv = context.watch<TaskProvider>();

    // 针对首次登录或路由切换进入时的双重保底：如果已连接但尚未完成初始数据加载，自动触发静默加载
    if (conn.isConnected && !agentProv.hasLoaded && !agentProv.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !agentProv.hasLoaded && !agentProv.isLoading) {
          agentProv.loadTasks();
          missingMcpProv.loadItems();
          taskProv.loadTasks(silent: true);
        }
      });
    }

    if (!conn.isConnected) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: '返回主页',
            onPressed: () => HomeScaffold.switchToTab(context, 0),
          ),
          title: const Text('智能体任务流监控'),
        ),
        body: Center(
          child: Text('请先连接至 NAS 服务端', style: TextStyle(color: context.subtextColor)),
        ),
      );
    }

    final isTaskTab = _tabController.index == 0;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回主页',
          onPressed: () => HomeScaffold.switchToTab(context, 0),
        ),
        title: const Text('智能体任务监控'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryBlue,
          labelColor: context.isDark ? Colors.white : AppColors.primaryBlueDark,
          unselectedLabelColor: context.subtextColor,
          tabs: [
            const Tab(
              icon: Icon(Icons.account_tree_outlined),
              text: '任务流监控',
            ),
            Tab(
              icon: Badge(
                isLabelVisible: missingMcpProv.items.isNotEmpty,
                label: Text('${missingMcpProv.items.length}'),
                child: const Icon(Icons.extension_outlined),
              ),
              text: '缺失接口上报',
            ),
          ],
        ),
        actions: isTaskTab
            ? [
                IconButton(
                  icon: const Icon(Icons.cleaning_services_rounded),
                  tooltip: '清空已结束记录',
                  onPressed: () => _confirmClearFinishedTasks(context, agentProv),
                ),
                // 状态筛选 Chips
                PopupMenuButton<String>(
                  tooltip: '筛选状态',
                  icon: const Icon(Icons.filter_list_rounded),
                  initialValue: agentProv.statusFilter,
                  onSelected: (val) => agentProv.setStatusFilter(val),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'ALL', child: Text('全部状态')),
                    const PopupMenuItem(value: 'RUNNING', child: Text('仅进行中')),
                    const PopupMenuItem(value: 'COMPLETED', child: Text('仅已完成')),
                    const PopupMenuItem(value: 'FAILED', child: Text('仅异常/失败')),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: '刷新任务',
                  onPressed: () {
                    agentProv.loadTasks();
                    context.read<TaskProvider>().loadTasks(silent: true);
                  },
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.cleaning_services_rounded),
                  tooltip: '清空所有上报记录',
                  onPressed: () => _confirmClearMissingMcpTools(context, missingMcpProv),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: '刷新上报记录',
                  onPressed: () => missingMcpProv.loadItems(),
                ),
              ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTasksMonitorTab(agentProv, taskProv),
          _buildMissingMcpTab(missingMcpProv),
        ],
      ),
    );
  }

  Widget _buildTasksMonitorTab(AgentTaskProvider agentProv, TaskProvider taskProv) {
    return LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          if (agentProv.isLoading && agentProv.tasks.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (agentProv.tasks.isEmpty) {
            final isFiltered = agentProv.statusFilter != 'ALL' && agentProv.statusFilter.isNotEmpty;
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.smart_toy_outlined,
                    size: 64,
                    color: context.isDark ? Colors.white24 : Colors.black26,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无 AI 智能体长任务记录',
                    style: TextStyle(
                      color: context.isDark ? Colors.white70 : AppColors.lightTitle,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isFiltered
                        ? '可尝试重置过滤条件查看全部'
                        : '当 AI Agent 通过 start_agent_task 发起复合长任务时将在此实时呈现',
                    style: TextStyle(color: context.subtextColor, fontSize: 12),
                  ),
                  if (isFiltered) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryBlue,
                        side: const BorderSide(color: AppColors.primaryBlue),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.restart_alt_rounded, size: 16),
                      label: const Text('重置为全部状态'),
                      onPressed: () => agentProv.setStatusFilter('ALL'),
                    ),
                  ],
                ],
              ),
            );
          }

          if (isWide) {
            // 宽屏模式：左侧列表，右侧时间轴详情
            final selected = agentProv.selectedTask ?? agentProv.tasks.first;
            return Row(
              children: [
                SizedBox(
                  width: 380,
                  child: _buildTaskList(agentProv, selected.agentTaskId),
                ),
                VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
                Expanded(
                  child: _buildTaskDetail(selected, agentProv, taskProv),
                ),
              ],
            );
          }

          // 窄屏模式：列表，点击弹窗展示详情
          return _buildTaskList(agentProv, null, (task) {
            agentProv.selectTask(task);
            _showDetailBottomSheet(context, task, agentProv);
          });
        },
      );
  }

  Widget _buildTaskList(
    AgentTaskProvider agentProv,
    String? selectedId, [
    void Function(AgentTaskModel task)? onTap,
  ]) {
    final isDark = context.isDark;
    final activeAccent = isDark ? AppColors.accentCyan : AppColors.primaryBlue;

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: agentProv.tasks.length,
      itemBuilder: (ctx, idx) {
        final t = agentProv.tasks[idx];
        final isSelected = t.agentTaskId == selectedId;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          color: isSelected
              ? AppColors.primaryBlue.withOpacity(isDark ? 0.12 : 0.08)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? AppColors.primaryBlue : context.customBorderColor,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (onTap != null) {
                onTap(t);
              } else {
                agentProv.selectTask(t);
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: activeAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.smart_toy_rounded,
                            size: 18, color: activeAccent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              t.agentTaskId,
                              style: TextStyle(fontSize: 11, color: context.subtextColor),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusChip(t.status),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (t.progress / 100.0).clamp(0.0, 1.0),
                      backgroundColor: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        t.isRunning
                            ? AppColors.primaryBlue
                            : (t.isCompleted ? AppColors.successGreen : AppColors.errorRed),
                      ),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '进度: ${t.progress.toStringAsFixed(0)}% (步骤 ${t.currentStep}/${t.totalSteps < t.currentStep ? t.currentStep : t.totalSteps})',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white70 : AppColors.lightTitle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(t.createdAt),
                        style: TextStyle(fontSize: 11, color: context.subtextColor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTaskDetail(
    AgentTaskModel task,
    AgentTaskProvider agentProv,
    TaskProvider taskProv, {
    bool isInBottomSheet = false,
    ScrollController? scrollController,
  }) {
    final isDark = context.isDark;
    final activeAccent = isDark ? AppColors.accentCyan : AppColors.primaryBlue;

    return SingleChildScrollView(
      controller: scrollController,
      padding: EdgeInsets.all(isInBottomSheet ? 16.0 : 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            padding: EdgeInsets.all(isInBottomSheet ? 16.0 : 20.0),
            decoration: BoxDecoration(
              color: context.customCardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white12 : AppColors.lightBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.3),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                '识别码: ',
                                style: TextStyle(fontSize: 11.5, color: context.subtextColor),
                              ),
                              Expanded(
                                child: SelectableText(
                                  task.agentTaskId,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? AppColors.accentCyan : AppColors.primaryBlueDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildStatusChip(task.status),
                  ],
                ),
                if (task.description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    task.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : AppColors.lightSubtext,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (task.progress / 100.0).clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      task.isRunning
                          ? AppColors.primaryBlue
                          : (task.isCompleted ? AppColors.successGreen : AppColors.errorRed),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            '${task.progress.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: task.isRunning
                                  ? (isDark ? AppColors.accentCyan : AppColors.primaryBlue)
                                  : (task.isCompleted ? AppColors.successGreen : AppColors.errorRed),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: isDark ? Colors.white12 : AppColors.lightBorder,
                              ),
                            ),
                            child: Text(
                              '步骤 ${task.currentStep} / ${task.totalSteps < task.currentStep ? task.currentStep : task.totalSteps}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: context.subtextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (task.isRunning)
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.errorRed.withOpacity(0.15),
                          foregroundColor: AppColors.errorRed,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => agentProv.cancelTask(task.agentTaskId),
                        icon: const Icon(Icons.stop_circle_outlined, size: 15),
                        label: const Text('终止任务', style: TextStyle(fontSize: 12)),
                      )
                    else
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.errorRed.withOpacity(0.12),
                          foregroundColor: AppColors.errorRed,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _confirmDeleteTask(
                          context,
                          task,
                          agentProv,
                          isInBottomSheet: isInBottomSheet,
                        ),
                        icon: const Icon(Icons.delete_outline_rounded, size: 15),
                        label: const Text('删除记录', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 步骤时间轴
          const Text('执行时间轴',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (task.steps.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.03) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.hourglass_empty_rounded, size: 16, color: context.subtextColor),
                  const SizedBox(width: 8),
                  Text('智能体尚未汇报步骤详情...',
                      style: TextStyle(color: context.subtextColor, fontSize: 13)),
                ],
              ),
            )
          else
            ...task.steps.asMap().entries.map((entry) {
              final idx = entry.key;
              final step = entry.value;
              final isLast = idx == task.steps.length - 1;

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Timeline line & indicator
                    Column(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: step.status == 'COMPLETED'
                                ? AppColors.successGreen
                                : (step.status == 'FAILED'
                                    ? AppColors.errorRed
                                    : AppColors.primaryBlue),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${step.stepIndex}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: isDark ? Colors.white24 : AppColors.lightBorder,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    // Timeline Content
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: context.customCardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? Colors.white12 : AppColors.lightBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    step.stepName,
                                    style: const TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Text(
                                  _formatTime(step.timestamp),
                                  style: TextStyle(fontSize: 11, color: context.subtextColor),
                                ),
                              ],
                            ),
                            if (step.logMessage.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                step.logMessage,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : AppColors.lightSubtext,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

          // 子操作关联 (如创建的下载任务、整理的文件等)
          if (task.subActions.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('关联底层操作',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...task.subActions.map(
              (action) => _buildSubActionCard(action, taskProv, isDark, activeAccent),
            ),
          ],

          // 结果或错误
          if (task.result != null) ...[
            const SizedBox(height: 16),
            const Text('任务总结与产出',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.successGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.successGreen.withOpacity(0.3)),
              ),
              child: Text(
                task.result.toString(),
                style: TextStyle(
                  color: isDark ? Colors.white70 : AppColors.lightTitle,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          if (task.error != null) ...[
            const SizedBox(height: 16),
            const Text('失败异常信息',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.errorRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.errorRed.withOpacity(0.3)),
              ),
              child: Text(
                task.error!,
                style: const TextStyle(color: AppColors.errorRed, fontSize: 13),
              ),
            ),
          ],
          if (task.promptTemplate != null && task.promptTemplate!.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF161F30) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: (context.isDark ? AppColors.accentCyan : AppColors.primaryBlue)
                        .withOpacity(0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: (context.isDark ? AppColors.accentCyan : AppColors.primaryBlue)
                                    .withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.auto_awesome_rounded,
                                  color: context.isDark ? AppColors.accentCyan : AppColors.primaryBlue,
                                  size: 16),
                            ),
                            const SizedBox(width: 8),
                            const Flexible(
                              child: Text(
                                '任务复现提示词',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              (context.isDark ? AppColors.accentCyan : AppColors.primaryBlue)
                                  .withOpacity(0.15),
                          foregroundColor:
                              context.isDark ? AppColors.accentCyan : AppColors.primaryBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        label: const Text('复制提示词', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: task.promptTemplate!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('提示词已复制到剪贴板，可直接发送给智能体执行'),
                              backgroundColor: AppColors.successGreen,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.isDark ? Colors.black26 : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: context.isDark ? Colors.white10 : AppColors.lightBorder),
                    ),
                    child: SelectableText(
                      task.promptTemplate!,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: context.isDark ? Colors.white70 : AppColors.lightTitle,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '💡 此提示词由智能体在完成任务时提炼总结，可直接复制发送给智能体执行相同任务。',
                    style: TextStyle(fontSize: 11, color: context.tertiaryTextColor),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 智能匹配底层关联的长任务对象（支持直接 TaskId、磁力链 Hash、URL 关联）
  TaskItem? _findRelatedTask(AgentSubAction action, TaskProvider taskProv) {
    if (action.actionId.isNotEmpty) {
      final direct = taskProv.getTaskById(action.actionId);
      if (direct != null) return direct;
    }
    // 从 summary 中提取磁力链 Hash (btih) 匹配 qb_{hash}
    final magnetMatch = RegExp(r'urn:btih:([a-zA-Z0-9]+)', caseSensitive: false)
        .firstMatch(action.summary);
    if (magnetMatch != null) {
      final hash = magnetMatch.group(1)!.toLowerCase();
      final qbTask = taskProv.getTaskById('qb_$hash');
      if (qbTask != null) return qbTask;
      for (final t in taskProv.allTasks) {
        final tHash = t.detail['hash']?.toString().toLowerCase();
        if (tHash == hash || t.taskId.toLowerCase() == 'qb_$hash') {
          return t;
        }
      }
    }
    // 按 summary 中包含的 URL 匹配
    for (final t in taskProv.allTasks) {
      final url = t.detail['url']?.toString();
      if (url != null && url.isNotEmpty && action.summary.contains(url)) {
        return t;
      }
    }
    return null;
  }

  /// 构建底层操作卡片，对于 DOWNLOAD 下载任务专项展示实时进度条、下载速率与文件体量
  Widget _buildSubActionCard(
    AgentSubAction action,
    TaskProvider taskProv,
    bool isDark,
    Color activeAccent,
  ) {
    final isDownload = action.actionType == 'DOWNLOAD';

    if (isDownload) {
      final relatedTask = _findRelatedTask(action, taskProv);

      double progress;
      Color progressColor;
      String statusLabel;
      String speed = '';
      String bytesText = '';

      if (relatedTask != null) {
        progress = relatedTask.progress.clamp(0.0, 100.0);
        statusLabel = relatedTask.status.label;
        speed = relatedTask.speed;
        if (relatedTask.totalBytes > 0) {
          bytesText =
              '(${Formatters.formatBytes(relatedTask.downloadedBytes)} / ${Formatters.formatBytes(relatedTask.totalBytes)})';
        }

        switch (relatedTask.status) {
          case TaskStatus.completed:
            progressColor = AppColors.successGreen;
            break;
          case TaskStatus.paused:
            progressColor = AppColors.warningOrange;
            break;
          case TaskStatus.failed:
            progressColor = AppColors.errorRed;
            break;
          case TaskStatus.cancelled:
            progressColor = Colors.grey;
            break;
          case TaskStatus.pending:
            progressColor = AppColors.warningOrange;
            break;
          case TaskStatus.running:
            progressColor = isDark ? AppColors.accentCyan : AppColors.primaryBlue;
            break;
        }
      } else {
        // 未在本地任务缓存中命中详细 TaskItem 时，依据底层操作本身的终态推断
        if (action.status == 'COMPLETED') {
          progress = 100.0;
          statusLabel = '已下发';
          progressColor = AppColors.successGreen;
        } else if (action.status == 'FAILED') {
          progress = 0.0;
          statusLabel = '失败';
          progressColor = AppColors.errorRed;
        } else {
          progress = 0.0;
          statusLabel = '下载中';
          progressColor = isDark ? AppColors.accentCyan : AppColors.primaryBlue;
        }
      }

      String displayTitle = action.summary;
      if (relatedTask != null) {
        final name = relatedTask.detail['name']?.toString();
        if (name != null && name.isNotEmpty && name != relatedTask.taskId) {
          displayTitle = '下载: $name';
        }
      }

      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: progressColor.withOpacity(0.15),
                    child: Icon(Icons.download_rounded, color: progressColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '类型: DOWNLOAD • ID: ${action.actionId}',
                                style: TextStyle(fontSize: 11, color: context.subtextColor),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatTime(action.timestamp),
                              style: TextStyle(fontSize: 11, color: context.subtextColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (progress / 100.0).clamp(0.0, 1.0),
                  backgroundColor: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        '${progress.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: progressColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (bytesText.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          bytesText,
                          style: TextStyle(fontSize: 11, color: context.subtextColor),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      if (speed.isNotEmpty && speed != '0 B/s') ...[
                        Icon(
                          Icons.speed_rounded,
                          size: 13,
                          color: isDark ? AppColors.accentCyan : AppColors.primaryBlueDark,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          speed,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppColors.accentCyan : AppColors.primaryBlueDark,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: progressColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: progressColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: progressColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // 针对 RSS_TASK 专属卡片渲染与快速跳转
    if (action.actionType == 'RSS_TASK') {
      const rssColor = Color(0xFFFF7A00);
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: rssColor.withOpacity(0.35)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context, rootNavigator: false).maybePop();
            HomeScaffold.switchToTab(context, 3, rssId: action.actionId);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: rssColor.withOpacity(0.15),
                      child: const Icon(Icons.rss_feed_rounded, color: rssColor, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            action.summary,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: rssColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'RSS 自动订阅',
                              style: TextStyle(fontSize: 10.5, color: rssColor, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: rssColor.withOpacity(0.15),
                        foregroundColor: rssColor,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 13),
                      label: const Text('详情', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.of(context, rootNavigator: false).maybePop();
                        HomeScaffold.switchToTab(context, 3, rssId: action.actionId);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Divider(height: 1, thickness: 0.5, color: isDark ? Colors.white12 : AppColors.lightBorder),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '编号: ${action.actionId}',
                        style: TextStyle(fontSize: 11, color: context.subtextColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(action.timestamp),
                      style: TextStyle(fontSize: 11, color: context.subtextColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 非下载任务保持原有紧凑列表卡片布局
    IconData icon;
    switch (action.actionType) {
      case 'FILE_ORGANIZE':
        icon = Icons.folder_special_rounded;
        break;
      case 'TRASH_DELETE':
        icon = Icons.delete_outline_rounded;
        break;
      default:
        icon = Icons.hub_rounded;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: activeAccent.withOpacity(0.15),
          child: Icon(icon, color: activeAccent, size: 20),
        ),
        title: Text(action.summary, style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          '类型: ${action.actionType} • ID: ${action.actionId}',
          style: TextStyle(fontSize: 11, color: context.subtextColor),
        ),
        trailing: Text(
          _formatTime(action.timestamp),
          style: TextStyle(fontSize: 11, color: context.subtextColor),
        ),
      ),
    );
  }

  void _showDetailBottomSheet(
    BuildContext context,
    AgentTaskModel task,
    AgentTaskProvider agentProv,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          context.isDark ? const Color(0xFF0F172A) : Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Consumer<TaskProvider>(
        builder: (ctx, taskProv, _) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) => SafeArea(
            top: false,
            child: Column(
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Expanded(
                  child: _buildTaskDetail(
                    task,
                    agentProv,
                    taskProv,
                    isInBottomSheet: true,
                    scrollController: scrollController,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTask(
    BuildContext context,
    AgentTaskModel task,
    AgentTaskProvider agentProv, {
    bool isInBottomSheet = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: AppColors.errorRed),
            SizedBox(width: 8),
            Text('删除任务记录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '确定要删除任务「${task.title}」（${task.agentTaskId}）的执行记录吗？\n删除后任务历史明细与时间轴将无法恢复。',
          style: TextStyle(color: context.subtextColor, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      if (isInBottomSheet && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      final ok = await agentProv.deleteTask(task.agentTaskId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? '任务记录已删除' : '删除失败: ${agentProv.errorMessage ?? ""}'),
            backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _confirmClearFinishedTasks(
    BuildContext context,
    AgentTaskProvider agentProv,
  ) async {
    final finishedCount = agentProv.tasks.where((t) => !t.isRunning).length;
    if (finishedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('暂无可清理的已结束任务'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: AppColors.errorRed),
            SizedBox(width: 8),
            Text('清空已结束记录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '确定要批量清空全部已结束（已完成、已失败或已取消）的智能体任务吗？\n当前共有 $finishedCount 条历史记录将被彻底删除，此操作不可撤销。',
          style: TextStyle(color: context.subtextColor, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final count = await agentProv.clearFinishedTasks();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已清空 $count 条已结束任务记录'),
            backgroundColor: AppColors.successGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildMissingMcpTab(MissingMcpProvider missingMcpProv) {
    final isDark = context.isDark;
    final accentColor = isDark ? AppColors.accentCyan : AppColors.primaryBlue;

    if (missingMcpProv.isLoading && missingMcpProv.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (missingMcpProv.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFE2E8F0).withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.extension_off_rounded, size: 48, color: context.tertiaryTextColor),
            ),
            const SizedBox(height: 16),
            Text('暂无缺失接口上报记录',
                style: TextStyle(
                  color: isDark ? Colors.white70 : AppColors.lightTitle,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                )),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                '当 AI Agent 执行任务需要调用特定底层能力但系统尚未提供对应 MCP 接口时，将自动通过 report_missing_mcp_tool 上报至此处供开发者扩展实现。',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.subtextColor, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: missingMcpProv.items.length,
      itemBuilder: (ctx, idx) {
        final item = missingMcpProv.items[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: context.customBorderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.extension_rounded, color: accentColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.toolName,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : AppColors.lightTitle,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryBlue.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'MCP 工具诉求',
                                  style: TextStyle(fontSize: 10, color: AppColors.primaryBlue, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '上报时间: ${_formatTime(item.createdAt)}${item.agentTaskId != null ? " • 关联任务: ${item.agentTaskId}" : ""}',
                            style: TextStyle(fontSize: 11, color: context.tertiaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      color: context.tertiaryTextColor,
                      tooltip: '删除此记录',
                      onPressed: () => _confirmDeleteMissingMcp(context, item, missingMcpProv),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  item.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : AppColors.lightTitle,
                    height: 1.4,
                  ),
                ),
                if (item.suggestedParameters != null && item.suggestedParameters!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.customBorderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '建议入参规格:',
                          style: TextStyle(
                            fontSize: 11,
                            color: accentColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          item.suggestedParameters!,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: isDark ? Colors.white70 : AppColors.lightTitle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (item.scenario != null && item.scenario!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '业务场景: ${item.scenario!}',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.subtextColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accentColor,
                        side: BorderSide(color: accentColor.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text('复制接口草案', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        final draft =
                            '【MCP 缺失工具草案】\n名称: ${item.toolName}\n描述: ${item.description}\n建议参数: ${item.suggestedParameters ?? "无"}\n场景: ${item.scenario ?? "无"}';
                        Clipboard.setData(ClipboardData(text: draft));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('接口规格草案已复制到剪贴板'),
                            backgroundColor: AppColors.successGreen,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteMissingMcp(
    BuildContext context,
    MissingMcpToolModel item,
    MissingMcpProvider missingMcpProv,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: AppColors.errorRed),
            SizedBox(width: 8),
            Text('删除上报记录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '确定要删除缺失接口「${item.toolName}」的上报记录吗？',
          style: TextStyle(color: context.subtextColor, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final ok = await missingMcpProv.deleteItem(item.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? '上报记录已删除' : '删除失败'),
            backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _confirmClearMissingMcpTools(
    BuildContext context,
    MissingMcpProvider missingMcpProv,
  ) async {
    if (missingMcpProv.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可清空的上报记录'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final count = missingMcpProv.items.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: AppColors.errorRed),
            SizedBox(width: 8),
            Text('清空上报记录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '确定要清空全部缺失接口上报记录（共 $count 条）吗？此操作不可撤销。',
          style: TextStyle(color: context.subtextColor, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final cleared = await missingMcpProv.clearAll();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已清空 $cleared 条上报记录'),
            backgroundColor: AppColors.successGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
