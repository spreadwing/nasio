import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/home_layout_model.dart';
import '../../providers/connection_provider.dart';
import '../../providers/home_layout_provider.dart';
import '../../providers/storage_provider.dart';
import '../../widgets/storage_pool_card.dart';
import '../home_scaffold.dart';
import 'home_layout_config_dialog.dart';

class DashboardView extends StatefulWidget {
  final ValueChanged<int>? onNavigateTab;

  const DashboardView({super.key, this.onNavigateTab});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  final TextEditingController _pathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final conn = context.read<ConnectionProvider>();
      if (conn.isConnected) {
        context.read<StorageProvider>().loadConfig();
      }
    });
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  void _showAddWhitelistDialog() {
    _pathController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加沙箱白名单目录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '请输入绿联 NAS 宿主机或容器内挂载的绝对路径（如 /volume1/data）：',
              style: TextStyle(fontSize: 13, color: context.subtextColor),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                hintText: '/volume1/photos',
                prefixIcon: Icon(Icons.create_new_folder_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
            onPressed: () async {
              final path = _pathController.text.trim();
              if (path.isNotEmpty) {
                Navigator.pop(ctx);
                final success = await context.read<StorageProvider>().addWhitelist(path);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? '白名单路径已添加并生效' : '添加失败，请检查路径'),
                      backgroundColor: success ? AppColors.successGreen : AppColors.errorRed,
                    ),
                  );
                }
              }
            },
            child: const Text('添加', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveWhitelist(String path) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除白名单确认'),
        content: Text('确定将目录 "$path" 从沙箱白名单中移除吗？移除后 AI 智能体将无法访问该目录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorRed),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await context.read<StorageProvider>().removeWhitelist(path);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? '已成功移除白名单目录' : '移除失败'),
                    backgroundColor: success ? AppColors.successGreen : AppColors.errorRed,
                  ),
                );
              }
            },
            child: const Text('确认移除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _navigateToTrash() {
    if (widget.onNavigateTab != null) {
      widget.onNavigateTab!(4);
    } else {
      HomeScaffold.switchToTab(context, 4);
    }
  }

  void _navigateToTab(int index) {
    if (widget.onNavigateTab != null) {
      widget.onNavigateTab!(index);
    } else {
      HomeScaffold.switchToTab(context, index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    final storage = context.watch<StorageProvider>();
    final layout = context.watch<HomeLayoutProvider>();

    if (!conn.isConnected) {
      return Scaffold(
        appBar: AppBar(title: const Text('主页工作台')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.link_off_rounded, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text('尚未连接到 NAS 服务端', style: TextStyle(fontSize: 16, color: context.subtextColor)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => conn.refreshHealth(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试连接'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('主页工作台'),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_customize_outlined),
            tooltip: '自定义主页布局',
            onPressed: () => HomeLayoutConfigDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新存储状态',
            onPressed: () => storage.loadConfig(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => storage.loadConfig(),
        child: storage.isLoading && storage.storagePools.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. 顶部快捷功能入口金刚区
                    _buildQuickFeaturesSection(context, layout),

                    if (layout.activeFeatures.isNotEmpty) const SizedBox(height: 16),

                    // 2. 动态可排序资源看板卡片区
                    if (layout.activeCards.isEmpty)
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.view_agenda_outlined, size: 44, color: context.subtextColor),
                                const SizedBox(height: 12),
                                Text(
                                  '资产看板卡片已全部隐藏',
                                  style: TextStyle(fontSize: 14, color: context.subtextColor),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () => HomeLayoutConfigDialog.show(context),
                                  icon: const Icon(Icons.tune_rounded, size: 16),
                                  label: const Text('自定义开启卡片'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryBlue,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      for (final card in layout.activeCards) ...[
                        _buildCardById(context, storage, card.id),
                        const SizedBox(height: 20),
                      ],
                  ],
                ),
              ),
      ),
    );
  }

  /// 顶部功能入口区（类 App 图标设计）
  Widget _buildQuickFeaturesSection(BuildContext context, HomeLayoutProvider layout) {
    final activeFeatures = layout.activeFeatures;
    if (activeFeatures.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        if (isWide) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              children: activeFeatures.map((item) {
                return SizedBox(
                  width: 92,
                  child: _buildFeatureCard(context, item, isWide: true),
                );
              }).toList(),
            ),
          );
        } else {
          if (activeFeatures.length <= 4) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  for (int i = 0; i < activeFeatures.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: _buildFeatureCard(context, activeFeatures[i], isWide: false),
                    ),
                  ],
                ],
              ),
            );
          } else {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: activeFeatures.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 6,
                  childAspectRatio: 0.76,
                ),
                itemBuilder: (ctx, idx) => _buildFeatureCard(ctx, activeFeatures[idx], isWide: false),
              ),
            );
          }
        }
      },
    );
  }

  /// 功能项渐变质感
  LinearGradient _getFeatureGradient(HomeFeatureItem item) {
    switch (item.id) {
      case 'tasks':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF29B6F6), Color(0xFF0277BD)],
        );
      case 'agent_tasks':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF00E5FF), Color(0xFF536DFE)],
        );
      case 'trash':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFB74D), Color(0xFFF4511E)],
        );
      case 'settings':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)],
        );
      default:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [item.color, item.color.withOpacity(0.8)],
        );
    }
  }

  /// 单个功能项（类 App 图标设计，名称置于图标下方）
  Widget _buildFeatureCard(BuildContext context, HomeFeatureItem item, {required bool isWide}) {
    final gradient = _getFeatureGradient(item);
    final iconBoxSize = isWide ? 56.0 : 48.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _navigateToTab(item.tabIndex),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: isWide ? 8 : 6,
            horizontal: isWide ? 6 : 2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: iconBoxSize,
                height: iconBoxSize,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: item.color.withOpacity(context.isDark ? 0.35 : 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  item.icon,
                  color: Colors.white,
                  size: isWide ? 28 : 26,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 按 ID 动态渲染卡片
  Widget _buildCardById(BuildContext context, StorageProvider storage, String cardId) {
    switch (cardId) {
      case 'storage_pools':
        return _buildStoragePoolsSection(context, storage);
      case 'sandbox_whitelist':
        return _buildWhitelistSection(context, storage);
      case 'disaster_recovery':
        return _buildDisasterRecoverySection(context, storage);
      default:
        return const SizedBox.shrink();
    }
  }

  /// 存储池容量展示卡片
  Widget _buildStoragePoolsSection(BuildContext context, StorageProvider storage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '物理存储池状态',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (storage.storagePools.isNotEmpty)
              Text(
                '共 ${storage.storagePools.length} 个存储池',
                style: TextStyle(fontSize: 12, color: context.subtextColor),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (storage.storagePools.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Text(
                  '暂未探测到挂载存储池',
                  style: TextStyle(color: context.subtextColor),
                ),
              ),
            ),
          )
        else
          ...storage.storagePools.map((p) => StoragePoolCard(pool: p)),
      ],
    );
  }

  /// 白名单安全管控卡片
  Widget _buildWhitelistSection(BuildContext context, StorageProvider storage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                '沙箱白名单管控',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: _showAddWhitelistDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加目录'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: storage.allowedPaths.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: Text('白名单为空', style: TextStyle(color: context.subtextColor)),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: storage.allowedPaths.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                  itemBuilder: (ctx, idx) {
                    final p = storage.allowedPaths[idx];
                    return ListTile(
                      leading: const Icon(Icons.folder_outlined, color: AppColors.primaryBlue),
                      title: Text(p, style: const TextStyle(fontSize: 14)),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded,
                            color: AppColors.errorRed, size: 20),
                        tooltip: '移除白名单',
                        onPressed: () => _confirmRemoveWhitelist(p),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 防灾安全配置卡片
  Widget _buildDisasterRecoverySection(BuildContext context, StorageProvider storage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '防灾安全配置',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Tooltip(
                message: '点击直接前往防灾回收站',
                child: InkWell(
                  onTap: _navigateToTrash,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('回收站物理目录:'),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: Text(
                                  storage.trashDir.isNotEmpty ? storage.trashDir : '/volume1/.trash',
                                  textAlign: TextAlign.end,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.isDark ? AppColors.accentCyan : AppColors.primaryBlueDark,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 13,
                                color: context.isDark ? AppColors.accentCyan : AppColors.primaryBlueDark,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('软删除保留周期:'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${storage.trashRetentionDays} 天 (超期自动清理)',
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
