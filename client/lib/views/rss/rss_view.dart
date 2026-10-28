import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/rss_model.dart';
import '../../providers/connection_provider.dart';
import '../../providers/rss_provider.dart';
import '../../providers/storage_provider.dart';
import '../home_scaffold.dart';
import 'rss_resource_list_view.dart';

class RssView extends StatefulWidget {
  final String? initialSelectedRssId;

  const RssView({super.key, this.initialSelectedRssId});

  @override
  State<RssView> createState() => _RssViewState();
}

class _RssViewState extends State<RssView> {
  bool _handledInitialId = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final conn = context.read<ConnectionProvider>();
      if (conn.isConnected) {
        await context.read<RssProvider>().loadSubscriptions();
        if (mounted) {
          context.read<StorageProvider>().loadConfig();
        }
        _checkInitialSelected();
      }
    });
  }

  @override
  void didUpdateWidget(covariant RssView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSelectedRssId != oldWidget.initialSelectedRssId &&
        widget.initialSelectedRssId != null) {
      _handledInitialId = false;
      _checkInitialSelected();
    }
  }

  void _checkInitialSelected() {
    if (_handledInitialId || widget.initialSelectedRssId == null || !mounted) return;
    _handledInitialId = true;
    final prov = context.read<RssProvider>();
    final target = prov.subscriptions.cast<RssSubscriptionModel?>().firstWhere(
          (s) => s?.rssId == widget.initialSelectedRssId,
          orElse: () => null,
        );
    if (target != null) {
      _showDetailSheet(target);
    }
  }

  String _formatTime(double timestamp) {
    if (timestamp <= 0) return '尚未检查';
    final dt = DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).toInt());
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final rssProv = context.watch<RssProvider>();
    final isDark = context.isDark;

    final totalCount = rssProv.subscriptions.length;
    final activeCount = rssProv.subscriptions.where((s) => s.enabled).length;
    final totalDownloaded = rssProv.subscriptions.fold<int>(
      0,
      (sum, s) => sum + s.totalDownloadedCount,
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 顶部应用栏
          SliverAppBar(
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: '返回主页',
              onPressed: () => HomeScaffold.switchToTab(context, 0),
            ),
            title: const Text(
              'RSS 订阅',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                tooltip: '刷新订阅列表',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => rssProv.loadSubscriptions(),
              ),
              IconButton(
                tooltip: '新建订阅',
                icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFFFF7A00)),
                onPressed: () => _showAddSubscriptionDialog(context),
              ),
              const SizedBox(width: 8),
            ],
          ),

          // 概览统计指标条
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      '订阅总数',
                      '$totalCount',
                      Icons.bookmarks_outlined,
                      AppColors.primaryBlue,
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      '活跃监听',
                      '$activeCount',
                      Icons.sensors_rounded,
                      AppColors.successGreen,
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      '累计抓取下载',
                      '$totalDownloaded',
                      Icons.cloud_download_outlined,
                      const Color(0xFFFF7A00),
                      isDark,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 列表内容
          if (rssProv.isLoading && rssProv.subscriptions.isEmpty)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (rssProv.subscriptions.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.rss_feed_rounded, size: 64, color: context.subtextColor.withOpacity(0.4)),
                    const SizedBox(height: 16),
                    Text(
                      '暂无 RSS 订阅任务',
                      style: TextStyle(fontSize: 16, color: context.subtextColor),
                    ),
                    if (MediaQuery.of(context).size.width >= 640) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text(
                          '点击右上角“新建订阅”添加新番/影视等 RSS 源，设置正则自动抓取并下载',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: context.tertiaryTextColor),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final sub = rssProv.subscriptions[index];
                    return _buildSubscriptionCard(sub, isDark);
                  },
                  childCount: rssProv.subscriptions.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: context.customCardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.customBorderColor),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color.withOpacity(0.12),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 10.5, color: context.subtextColor),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openResourceList(RssSubscriptionModel sub) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            RssResourceListView(subscription: sub),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
      ),
    );
  }

  Widget _buildSubscriptionCard(RssSubscriptionModel sub, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openResourceList(sub),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行与开关
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: (sub.enabled ? const Color(0xFFFF7A00) : Colors.grey).withOpacity(0.15),
                    child: Icon(
                      Icons.rss_feed_rounded,
                      color: sub.enabled ? const Color(0xFFFF7A00) : Colors.grey,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sub.title,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: sub.feedUrl));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制 RSS 地址到剪贴板')),
                            );
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  sub.feedUrl,
                                  style: TextStyle(fontSize: 11, color: context.subtextColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.copy_rounded, size: 11, color: context.subtextColor),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: sub.enabled,
                    activeColor: const Color(0xFFFF7A00),
                    onChanged: (val) async {
                      await context.read<RssProvider>().toggleSubscription(sub.rssId);
                    },
                  ),
                ],
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // 参数信息与标签规则
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInfoBadge(Icons.folder_outlined, sub.saveDir),
                  _buildInfoBadge(Icons.timer_outlined, '每 ${sub.checkIntervalMinutes} 分钟'),
                  _buildInfoBadge(Icons.cloud_download_outlined, '已下载 ${sub.totalDownloadedCount} 项'),
                  _buildInfoBadge(Icons.hub_outlined, '引擎: ${sub.downloadEngine}'),
                  if (sub.agentTaskId != null && sub.agentTaskId!.isNotEmpty)
                    _buildInfoBadge(Icons.smart_toy_outlined, 'AI 托管: ${sub.agentTaskId}'),
                ],
              ),

              if (sub.filterRules.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: sub.filterRules.map((r) {
                    final attrPart = r.attribute != null && r.attribute!.isNotEmpty ? '@${r.attribute}' : '';
                    final isExclude = r.mode == 'EXCLUDE';
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isExclude
                            ? AppColors.errorRed.withOpacity(0.1)
                            : AppColors.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isExclude
                              ? AppColors.errorRed.withOpacity(0.3)
                              : AppColors.primaryBlue.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        '${isExclude ? '排除' : '匹配'} <${r.tag}$attrPart>: /${r.pattern}/',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isExclude ? AppColors.errorRed : AppColors.primaryBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              if (sub.lastError != null && sub.lastError!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.errorRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.errorRed, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '检查异常: ${sub.lastError}',
                          style: const TextStyle(fontSize: 11, color: AppColors.errorRed),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // 底部操作栏
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '上次轮询: ${_formatTime(sub.lastCheckedAt)}',
                    style: TextStyle(fontSize: 11, color: context.subtextColor),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                          foregroundColor: const Color(0xFFFF7A00),
                          side: const BorderSide(color: Color(0xFFFF7A00)),
                        ),
                        icon: const Icon(Icons.list_alt_rounded, size: 13),
                        label: const Text('资源', style: TextStyle(fontSize: 11)),
                        onPressed: () => _openResourceList(sub),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 13),
                        label: const Text('编辑', style: TextStyle(fontSize: 11)),
                        onPressed: () => _showEditSubscriptionDialog(context, sub),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 13),
                        label: const Text('检查', style: TextStyle(fontSize: 11)),
                        onPressed: () async {
                          final ok = await context.read<RssProvider>().refreshSubscription(sub.rssId);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok ? '已触发即时轮询检查' : '检查失败'),
                                backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
                              ),
                            );
                          }
                        },
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.history_rounded, size: 13),
                        label: const Text('历史', style: TextStyle(fontSize: 11)),
                        onPressed: () => _showDetailSheet(sub),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        tooltip: '删除订阅',
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.errorRed, size: 17),
                        onPressed: () => _confirmDelete(sub),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: context.subtextColor),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, color: context.subtextColor)),
        ],
      ),
    );
  }

  void _confirmDelete(RssSubscriptionModel sub) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除订阅'),
        content: Text('确定删除 RSS 订阅 "${sub.title}" 吗？已下载的文件不会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorRed),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await context.read<RssProvider>().deleteSubscription(sub.rssId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? '订阅已成功删除' : '删除失败'),
                    backgroundColor: ok ? AppColors.successGreen : AppColors.errorRed,
                  ),
                );
              }
            },
            child: const Text('确认删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // 详情与历史抓取记录弹窗
  // -------------------------------------------------------------
  void _showDetailSheet(RssSubscriptionModel sub) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: ListView(
                controller: scrollController,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          sub.title,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                          foregroundColor: const Color(0xFFFF7A00),
                          side: const BorderSide(color: Color(0xFFFF7A00)),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 13),
                        label: const Text('编辑', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showEditSubscriptionDialog(context, sub);
                        },
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'RSS: ${sub.feedUrl}',
                    style: TextStyle(fontSize: 12, color: context.subtextColor),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '保存路径: ${sub.saveDir}',
                          style: TextStyle(fontSize: 12, color: context.subtextColor),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _showEditSubscriptionDialog(context, sub);
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(
                            '修改路径',
                            style: TextStyle(fontSize: 11, color: Color(0xFFFF7A00), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('过滤规则', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (sub.filterRules.isEmpty)
                    Text('未配置过滤规则（抓取全量更新）', style: TextStyle(fontSize: 12, color: context.subtextColor))
                  else
                    ...sub.filterRules.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '• [${r.mode}] 标签: <${r.tag}${r.attribute != null ? '@${r.attribute}' : ''}>  正则: /${r.pattern}/',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('历史抓取下载记录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      Text(
                        '共 ${sub.downloadHistory.length} 条',
                        style: TextStyle(fontSize: 12, color: context.subtextColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (sub.downloadHistory.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('暂无历史抓取下载记录', style: TextStyle(color: context.subtextColor)),
                      ),
                    )
                  else
                    ...sub.downloadHistory.map(
                      (h) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          leading: const CircleAvatar(
                            radius: 14,
                            backgroundColor: Color(0x1AFF7A00),
                            child: Icon(Icons.download_done_rounded, color: Color(0xFFFF7A00), size: 16),
                          ),
                          title: Text(h.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text('引擎: ${h.engine} • 任务ID: ${h.taskId ?? 'N/A'}', style: TextStyle(fontSize: 11, color: context.subtextColor)),
                              Text(_formatTime(h.downloadTime), style: TextStyle(fontSize: 10, color: context.subtextColor)),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            tooltip: '复制下载链接',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: h.downloadUrl));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('下载链接已复制')),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------
  // 新建 RSS 订阅弹窗（含规则编辑与存量条目选摘下载预览）
  // -------------------------------------------------------------
  void _showAddSubscriptionDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _AddSubscriptionDialog(),
    );
  }

  // -------------------------------------------------------------
  // 编辑 RSS 订阅弹窗（支持下载目录、标题、规则、轮询等完整修改）
  // -------------------------------------------------------------
  void _showEditSubscriptionDialog(BuildContext context, RssSubscriptionModel sub) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EditSubscriptionDialog(subscription: sub),
    );
  }
}

class _AddSubscriptionDialog extends StatefulWidget {
  const _AddSubscriptionDialog();

  @override
  State<_AddSubscriptionDialog> createState() => _AddSubscriptionDialogState();
}

class _AddSubscriptionDialogState extends State<_AddSubscriptionDialog> {
  final _feedUrlController = TextEditingController();
  final _titleController = TextEditingController();
  final _saveDirController = TextEditingController(text: '/volume1/Download');
  final _intervalController = TextEditingController(text: '15');
  String _downloadEngine = 'auto';

  final List<RssFilterRule> _rules = [
    RssFilterRule(tag: 'title', attribute: null, pattern: '1080p', mode: 'INCLUDE'),
  ];

  bool _isPreviewing = false;
  RssPreviewResponse? _previewResponse;
  final Set<String> _selectedGuids = {};
  bool _markUnselectedAsProcessed = true;
  bool _isCreating = false;

  @override
  void dispose() {
    _feedUrlController.dispose();
    _titleController.dispose();
    _saveDirController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _runPreview() async {
    final url = _feedUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入 RSS 源地址')),
      );
      return;
    }

    setState(() {
      _isPreviewing = true;
      _previewResponse = null;
      _selectedGuids.clear();
    });

    final res = await context.read<RssProvider>().previewFeed(
          feedUrl: url,
          filterRules: _rules,
        );

    if (mounted) {
      setState(() {
        _isPreviewing = false;
        _previewResponse = res;
        if (res != null) {
          if (_titleController.text.trim().isEmpty && res.channelTitle.isNotEmpty) {
            _titleController.text = res.channelTitle;
          }
          // 默认全选匹配到的条目供用户挑选
          for (final it in res.items) {
            _selectedGuids.add(it.guid);
          }
        }
      });
    }
  }

  Future<void> _submitCreate() async {
    final url = _feedUrlController.text.trim();
    final saveDir = _saveDirController.text.trim();
    if (url.isEmpty || saveDir.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RSS 地址与保存目录为必填项')),
      );
      return;
    }

    setState(() => _isCreating = true);

    final interval = int.tryParse(_intervalController.text.trim()) ?? 15;
    List<String>? selectedGuidsParam;
    if (_previewResponse != null) {
      selectedGuidsParam = _selectedGuids.toList();
    }

    final sub = await context.read<RssProvider>().createSubscription(
          feedUrl: url,
          saveDir: saveDir,
          title: _titleController.text.trim().isEmpty ? null : _titleController.text.trim(),
          filterRules: _rules,
          checkIntervalMinutes: interval,
          downloadEngine: _downloadEngine,
          selectedGuids: selectedGuidsParam,
          downloadExisting: true,
        );

    if (mounted) {
      setState(() => _isCreating = false);
      if (sub != null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('RSS 订阅 "${sub.title}" 创建成功！'),
            backgroundColor: AppColors.successGreen,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.read<RssProvider>().errorMessage ?? '创建失败'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 850),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      '新建 RSS 订阅与正则过滤',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 主表单区
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWideForm = constraints.maxWidth >= 480;

                    final titleField = TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: '订阅名称 (选填，默认读取源标题)',
                        prefixIcon: Icon(Icons.title_rounded),
                      ),
                    );
                    final saveDirField = TextField(
                      controller: _saveDirController,
                      decoration: const InputDecoration(
                        labelText: '落地保存目录 *',
                        prefixIcon: Icon(Icons.folder_outlined),
                      ),
                    );
                    final intervalField = TextField(
                      controller: _intervalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '轮询间隔 (分钟)',
                        prefixIcon: Icon(Icons.timer_outlined),
                      ),
                    );
                    final engineDropdown = DropdownButtonFormField<String>(
                      value: _downloadEngine,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '下载路由引擎',
                        prefixIcon: Icon(Icons.hub_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'auto', child: Text('智能路由 (auto)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'qbittorrent', child: Text('qBittorrent', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'aria2', child: Text('Aria2', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'builtin', child: Text('内置多线程 HTTP', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _downloadEngine = val);
                      },
                    );

                    return ListView(
                      children: [
                        TextField(
                          controller: _feedUrlController,
                          decoration: const InputDecoration(
                            labelText: 'RSS / Atom 源地址 *',
                            hintText: 'https://mikanani.me/RSS/Bangumi?bangumiId=... 或 Nyaa RSS',
                            prefixIcon: Icon(Icons.rss_feed_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        titleField,
                        const SizedBox(height: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            saveDirField,
                            _buildPathChips(_saveDirController, context),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (isWideForm)
                          Row(
                            children: [
                              Expanded(child: intervalField),
                              const SizedBox(width: 12),
                              Expanded(child: engineDropdown),
                            ],
                          )
                        else ...[
                          intervalField,
                          const SizedBox(height: 12),
                          engineDropdown,
                        ],

                        const SizedBox(height: 20),

                        // 正则过滤规则配置区
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            const Text(
                              '属性过滤规则 (全部满足时触发下载)',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('添加规则'),
                              onPressed: () {
                                setState(() {
                                  _rules.add(RssFilterRule(tag: 'title', pattern: '', mode: 'INCLUDE'));
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        if (_rules.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '未添加过滤规则，将无条件下载 RSS 中的所有新资源',
                              style: TextStyle(fontSize: 12, color: context.subtextColor),
                            ),
                          )
                        else
                          ...List.generate(_rules.length, (idx) {
                            final r = _rules[idx];
                            final modeField = SizedBox(
                              width: 92,
                              child: DropdownButtonFormField<String>(
                                value: r.mode,
                                isDense: true,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'INCLUDE', child: Text('包含', style: TextStyle(fontSize: 12))),
                                  DropdownMenuItem(value: 'EXCLUDE', child: Text('排除', style: TextStyle(fontSize: 12))),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _rules[idx] = RssFilterRule(
                                          tag: r.tag,
                                          attribute: r.attribute,
                                          pattern: r.pattern,
                                          mode: val,
                                        ));
                                  }
                                },
                              ),
                            );
                            final tagField = TextFormField(
                              initialValue: r.tag,
                              decoration: const InputDecoration(
                                labelText: '标签 (tag)',
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              style: const TextStyle(fontSize: 12),
                              onChanged: (val) => _rules[idx] = RssFilterRule(
                                tag: val,
                                attribute: r.attribute,
                                pattern: r.pattern,
                                mode: r.mode,
                              ),
                            );
                            final attrField = TextFormField(
                              initialValue: r.attribute ?? '',
                              decoration: const InputDecoration(
                                labelText: '属性 (可选)',
                                hintText: '如 url / type',
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              style: const TextStyle(fontSize: 12),
                              onChanged: (val) => _rules[idx] = RssFilterRule(
                                tag: r.tag,
                                attribute: val.isEmpty ? null : val,
                                pattern: r.pattern,
                                mode: r.mode,
                              ),
                            );
                            final patternField = TextFormField(
                              initialValue: r.pattern,
                              decoration: const InputDecoration(
                                labelText: '正则表达式',
                                hintText: '如 1080p|2160p',
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              style: const TextStyle(fontSize: 12),
                              onChanged: (val) => _rules[idx] = RssFilterRule(
                                tag: r.tag,
                                attribute: r.attribute,
                                pattern: val,
                                mode: r.mode,
                              ),
                            );
                            final removeBtn = IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.errorRed, size: 20),
                              onPressed: () {
                                setState(() => _rules.removeAt(idx));
                              },
                            );

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: context.customBorderColor),
                              ),
                              child: isWideForm
                                  ? Row(
                                      children: [
                                        modeField,
                                        const SizedBox(width: 8),
                                        Expanded(flex: 2, child: tagField),
                                        const SizedBox(width: 8),
                                        Expanded(flex: 2, child: attrField),
                                        const SizedBox(width: 8),
                                        Expanded(flex: 3, child: patternField),
                                        removeBtn,
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            modeField,
                                            const SizedBox(width: 8),
                                            Expanded(child: tagField),
                                            removeBtn,
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(flex: 2, child: attrField),
                                            const SizedBox(width: 8),
                                            Expanded(flex: 3, child: patternField),
                                          ],
                                        ),
                                      ],
                                    ),
                            );
                          }),

                    const SizedBox(height: 12),

                    // 预览测试按钮
                    Center(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        onPressed: _isPreviewing ? null : _runPreview,
                        icon: _isPreviewing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.manage_search_rounded, size: 18),
                        label: Text(_isPreviewing ? '正在拉取并解析 RSS...' : '解析测试 / 预览匹配条目'),
                      ),
                    ),

                    // 预览结果区与选摘下载
                    if (_previewResponse != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF131D2E) : const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '解析频道: ${_previewResponse!.channelTitle.isEmpty ? '未命名' : _previewResponse!.channelTitle}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                Text(
                                  '匹配 ${_previewResponse!.matchedCount} / 共 ${_previewResponse!.totalItems} 项',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                TextButton(
                                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                  onPressed: () {
                                    setState(() {
                                      for (final it in _previewResponse!.items) {
                                        _selectedGuids.add(it.guid);
                                      }
                                    });
                                  },
                                  child: const Text('全选'),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                  onPressed: () {
                                    setState(() => _selectedGuids.clear());
                                  },
                                  child: const Text('清空'),
                                ),
                                const Spacer(),
                                Text(
                                  '首次立即下载已选 ${_selectedGuids.length} 项',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const Divider(height: 1),
                            const SizedBox(height: 6),
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                '将未勾选的存量条目也记录为已处理（避免下次轮询再次触发）',
                                style: TextStyle(fontSize: 12),
                              ),
                              value: _markUnselectedAsProcessed,
                              onChanged: (val) {
                                if (val != null) setState(() => _markUnselectedAsProcessed = val);
                              },
                            ),
                            const SizedBox(height: 6),
                            if (_previewResponse!.items.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text('当前 RSS 源中暂无符合上述正则规则的条目', style: TextStyle(fontSize: 12, color: context.subtextColor)),
                              )
                            else
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 240),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _previewResponse!.items.length,
                                  itemBuilder: (ctx, i) {
                                    final item = _previewResponse!.items[i];
                                    final isSelected = _selectedGuids.contains(item.guid);
                                    return CheckboxListTile(
                                      dense: true,
                                      value: isSelected,
                                      title: Text(item.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                      subtitle: Text(
                                        '${item.pubDate.isNotEmpty ? '${item.pubDate} • ' : ''}${item.downloadUrl}',
                                        style: TextStyle(fontSize: 10.5, color: context.subtextColor),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) {
                                            _selectedGuids.add(item.guid);
                                          } else {
                                            _selectedGuids.remove(item.guid);
                                          }
                                        });
                                      },
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 16),
          // 底部确认按钮
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF7A00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: _isCreating ? null : _submitCreate,
                  child: _isCreating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('确认保存并启动订阅', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);
  }
}


// -------------------------------------------------------------
// 快捷落地保存目录标签（Chips）组件
// -------------------------------------------------------------
Widget _buildPathChips(TextEditingController controller, BuildContext context) {
  final storageProv = context.watch<StorageProvider>();
  final List<String> paths = [];
  if (storageProv.allowedPaths.isNotEmpty) {
    for (final p in storageProv.allowedPaths) {
      if (!paths.contains(p)) paths.add(p);
    }
  }
  for (final defaultPath in ['/volume1/Download', '/volume1/Media']) {
    if (!paths.contains(defaultPath)) paths.add(defaultPath);
  }

  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '快捷目录填入:',
          style: TextStyle(fontSize: 11, color: context.subtextColor),
        ),
        ...paths.map((p) {
          final isSelected = controller.text == p || controller.text.startsWith('$p/');
          return ActionChip(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            label: Text(p, style: TextStyle(fontSize: 11, color: isSelected ? const Color(0xFFFF7A00) : null)),
            avatar: Icon(Icons.folder_open_rounded, size: 13, color: isSelected ? const Color(0xFFFF7A00) : null),
            onPressed: () {
              controller.text = p;
              controller.selection = TextSelection.fromPosition(TextPosition(offset: p.length));
            },
          );
        }),
      ],
    ),
  );
}

// -------------------------------------------------------------
// 编辑 RSS 订阅弹窗（含下载目录、规则、轮询间隔等）
// -------------------------------------------------------------
class _EditSubscriptionDialog extends StatefulWidget {
  final RssSubscriptionModel subscription;

  const _EditSubscriptionDialog({required this.subscription});

  @override
  State<_EditSubscriptionDialog> createState() => _EditSubscriptionDialogState();
}

class _EditSubscriptionDialogState extends State<_EditSubscriptionDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _saveDirController;
  late final TextEditingController _intervalController;
  late String _downloadEngine;
  late String _subtitleLanguage;
  late List<RssFilterRule> _rules;

  bool _isUpdating = false;
  bool _isPreviewing = false;
  RssPreviewResponse? _previewResponse;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.subscription.title);
    _saveDirController = TextEditingController(text: widget.subscription.saveDir);
    _intervalController = TextEditingController(text: '${widget.subscription.checkIntervalMinutes}');
    _downloadEngine = widget.subscription.downloadEngine;
    _subtitleLanguage = widget.subscription.subtitleLanguage ?? '全部';
    _rules = widget.subscription.filterRules
        .map((r) => RssFilterRule(
              tag: r.tag,
              attribute: r.attribute,
              pattern: r.pattern,
              mode: r.mode,
            ))
        .toList();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _saveDirController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _runPreview() async {
    setState(() {
      _isPreviewing = true;
      _previewResponse = null;
    });

    final res = await context.read<RssProvider>().previewFeed(
          feedUrl: widget.subscription.feedUrl,
          filterRules: _rules,
        );

    if (mounted) {
      setState(() {
        _isPreviewing = false;
        _previewResponse = res;
      });
    }
  }

  Future<void> _submitUpdate() async {
    final saveDir = _saveDirController.text.trim();
    if (saveDir.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('落地保存目录不能为空')),
      );
      return;
    }

    setState(() => _isUpdating = true);

    final interval = int.tryParse(_intervalController.text.trim()) ?? widget.subscription.checkIntervalMinutes;
    final title = _titleController.text.trim();
    final subLang = _subtitleLanguage == '全部' ? null : _subtitleLanguage;

    final updated = await context.read<RssProvider>().updateSubscription(
          rssId: widget.subscription.rssId,
          title: title.isEmpty ? widget.subscription.title : title,
          saveDir: saveDir,
          filterRules: _rules,
          checkIntervalMinutes: interval,
          downloadEngine: _downloadEngine,
          subtitleLanguage: subLang,
        );

    if (mounted) {
      setState(() => _isUpdating = false);
      if (updated != null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('RSS 订阅 "${updated.title}" 配置已成功保存！'),
            backgroundColor: AppColors.successGreen,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.read<RssProvider>().errorMessage ?? '保存失败，请检查落地目录白名单'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 850),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      '编辑 RSS 订阅与规则',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 主表单区
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWideForm = constraints.maxWidth >= 480;

                    final titleField = TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: '订阅名称',
                        prefixIcon: Icon(Icons.title_rounded),
                      ),
                    );

                    final saveDirField = TextField(
                      controller: _saveDirController,
                      decoration: const InputDecoration(
                        labelText: '落地保存目录 *',
                        prefixIcon: Icon(Icons.folder_outlined),
                      ),
                    );

                    final intervalField = TextField(
                      controller: _intervalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '轮询间隔 (分钟)',
                        prefixIcon: Icon(Icons.timer_outlined),
                      ),
                    );

                    final engineDropdown = DropdownButtonFormField<String>(
                      value: _downloadEngine,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '下载路由引擎',
                        prefixIcon: Icon(Icons.hub_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'auto', child: Text('智能路由 (auto)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'qbittorrent', child: Text('qBittorrent', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'aria2', child: Text('Aria2', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'builtin', child: Text('内置多线程 HTTP', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _downloadEngine = val);
                      },
                    );

                    final subtitleDropdown = DropdownButtonFormField<String>(
                      value: ['全部', '简中', '繁中'].contains(_subtitleLanguage) ? _subtitleLanguage : '全部',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '字幕语言偏好',
                        prefixIcon: Icon(Icons.subtitles_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: '全部', child: Text('全部语言', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: '简中', child: Text('简体中文 (CHS/GB)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: '繁中', child: Text('繁体中文 (CHT/BIG5)', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _subtitleLanguage = val);
                      },
                    );

                    return ListView(
                      children: [
                        // RSS 源只读展示卡片
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: context.customBorderColor),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.rss_feed_rounded, color: Color(0xFFFF7A00), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.subscription.feedUrl,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'RSS 源地址为唯一订阅凭据（只读展示）',
                                      style: TextStyle(fontSize: 10.5, color: context.subtextColor),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                tooltip: '复制源地址',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: widget.subscription.feedUrl));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('RSS 源地址已复制到剪贴板')),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (isWideForm)
                          Row(
                            children: [
                              Expanded(child: titleField),
                              const SizedBox(width: 12),
                              Expanded(child: subtitleDropdown),
                            ],
                          )
                        else ...[
                          titleField,
                          const SizedBox(height: 12),
                          subtitleDropdown,
                        ],
                        const SizedBox(height: 12),

                        // 保存目录 + 快捷标签
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            saveDirField,
                            _buildPathChips(_saveDirController, context),
                          ],
                        ),
                        const SizedBox(height: 12),

                        if (isWideForm)
                          Row(
                            children: [
                              Expanded(child: intervalField),
                              const SizedBox(width: 12),
                              Expanded(child: engineDropdown),
                            ],
                          )
                        else ...[
                          intervalField,
                          const SizedBox(height: 12),
                          engineDropdown,
                        ],

                        const SizedBox(height: 20),

                        // 正则过滤规则配置区
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            const Text(
                              '属性过滤规则 (全部满足时触发下载)',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('添加规则'),
                              onPressed: () {
                                setState(() {
                                  _rules.add(RssFilterRule(tag: 'title', pattern: '', mode: 'INCLUDE'));
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        if (_rules.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '未添加过滤规则，将无条件下载 RSS 中的所有新资源',
                              style: TextStyle(fontSize: 12, color: context.subtextColor),
                            ),
                          )
                        else
                          ...List.generate(_rules.length, (idx) {
                            final r = _rules[idx];
                            final modeField = SizedBox(
                              width: 92,
                              child: DropdownButtonFormField<String>(
                                value: r.mode,
                                isDense: true,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'INCLUDE', child: Text('包含', style: TextStyle(fontSize: 12))),
                                  DropdownMenuItem(value: 'EXCLUDE', child: Text('排除', style: TextStyle(fontSize: 12))),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _rules[idx] = RssFilterRule(
                                          tag: r.tag,
                                          attribute: r.attribute,
                                          pattern: r.pattern,
                                          mode: val,
                                        ));
                                  }
                                },
                              ),
                            );
                            final tagField = TextFormField(
                              initialValue: r.tag,
                              decoration: const InputDecoration(
                                labelText: '标签 (tag)',
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              style: const TextStyle(fontSize: 12),
                              onChanged: (val) => _rules[idx] = RssFilterRule(
                                tag: val,
                                attribute: r.attribute,
                                pattern: r.pattern,
                                mode: r.mode,
                              ),
                            );
                            final attrField = TextFormField(
                              initialValue: r.attribute ?? '',
                              decoration: const InputDecoration(
                                labelText: '属性 (可选)',
                                hintText: '如 url / type',
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              style: const TextStyle(fontSize: 12),
                              onChanged: (val) => _rules[idx] = RssFilterRule(
                                tag: r.tag,
                                attribute: val.isEmpty ? null : val,
                                pattern: r.pattern,
                                mode: r.mode,
                              ),
                            );
                            final patternField = TextFormField(
                              initialValue: r.pattern,
                              decoration: const InputDecoration(
                                labelText: '正则表达式',
                                hintText: '如 1080p|2160p',
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              style: const TextStyle(fontSize: 12),
                              onChanged: (val) => _rules[idx] = RssFilterRule(
                                tag: r.tag,
                                attribute: r.attribute,
                                pattern: val,
                                mode: r.mode,
                              ),
                            );
                            final removeBtn = IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.errorRed, size: 20),
                              onPressed: () {
                                setState(() => _rules.removeAt(idx));
                              },
                            );

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: context.customBorderColor),
                              ),
                              child: isWideForm
                                  ? Row(
                                      children: [
                                        modeField,
                                        const SizedBox(width: 8),
                                        Expanded(flex: 2, child: tagField),
                                        const SizedBox(width: 8),
                                        Expanded(flex: 2, child: attrField),
                                        const SizedBox(width: 8),
                                        Expanded(flex: 3, child: patternField),
                                        removeBtn,
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            modeField,
                                            const SizedBox(width: 8),
                                            Expanded(child: tagField),
                                            removeBtn,
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(flex: 2, child: attrField),
                                            const SizedBox(width: 8),
                                            Expanded(flex: 3, child: patternField),
                                          ],
                                        ),
                                      ],
                                    ),
                            );
                          }),

                        const SizedBox(height: 12),

                        // 预览测试按钮
                        Center(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            onPressed: _isPreviewing ? null : _runPreview,
                            icon: _isPreviewing
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.manage_search_rounded, size: 18),
                            label: Text(_isPreviewing ? '正在测试匹配...' : '测试修改后的过滤规则'),
                          ),
                        ),

                        // 预览匹配摘要
                        if (_previewResponse != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF131D2E) : const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('规则命中结果:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                Text(
                                  '匹配 ${_previewResponse!.matchedCount} / 共 ${_previewResponse!.totalItems} 项',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF2563EB)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),
              // 底部确认保存按钮
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF7A00),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: _isUpdating ? null : _submitUpdate,
                      child: _isUpdating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('保存修改', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
