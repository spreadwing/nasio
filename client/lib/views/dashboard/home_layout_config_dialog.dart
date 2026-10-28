import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/home_layout_provider.dart';

class HomeLayoutConfigDialog extends StatefulWidget {
  const HomeLayoutConfigDialog({super.key});

  /// 唤起主页布局与卡片管理弹窗
  static Future<void> show(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 640;
    if (isNarrow) {
      return showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => const FractionallySizedBox(
          heightFactor: 0.88,
          child: HomeLayoutConfigDialog(),
        ),
      );
    } else {
      return showDialog(
        context: context,
        builder: (_) => const Dialog(
          insetPadding: EdgeInsets.all(24),
          child: SizedBox(
            width: 580,
            height: 640,
            child: HomeLayoutConfigDialog(),
          ),
        ),
      );
    }
  }

  @override
  State<HomeLayoutConfigDialog> createState() => _HomeLayoutConfigDialogState();
}

class _HomeLayoutConfigDialogState extends State<HomeLayoutConfigDialog> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _confirmReset(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认布局确认'),
        content: const Text('确定将主页顶部入口、侧栏/底部导航及资源看板卡片的展示状态与排序全部恢复为系统默认吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<HomeLayoutProvider>().resetToDefault();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已恢复默认布局与导航配置'),
                  backgroundColor: AppColors.successGreen,
                ),
              );
            },
            child: const Text('确认恢复', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutProvider>();

    return Column(
      children: [
        // 弹窗头部标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.dashboard_customize_rounded,
                  color: AppColors.primaryBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '主页与导航管理',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '自定义功能入口、侧栏/底部导航及资产看板的显隐与顺序',
                      style: TextStyle(fontSize: 12, color: context.subtextColor),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),

        // 分段切换 Tab
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: context.isDark ? AppColors.darkCard : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            indicator: BoxDecoration(
              color: AppColors.primaryBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: context.subtextColor,
            tabs: [
              Tab(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.grid_view_rounded, size: 15),
                      const SizedBox(width: 4),
                      Text('功能 (${layout.activeFeatures.length}/${layout.features.length})', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
              Tab(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.navigation_rounded, size: 15),
                      const SizedBox(width: 4),
                      Text('导航 (${layout.activeNavItems.length}/${layout.navItems.length})', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
              Tab(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.view_agenda_rounded, size: 15),
                      const SizedBox(width: 4),
                      Text('卡片 (${layout.activeCards.length}/${layout.cards.length})', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 标签页内容
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildFeaturesTab(context, layout),
              _buildNavItemsTab(context, layout),
              _buildCardsTab(context, layout),
            ],
          ),
        ),

        // 底部操作栏
        Divider(height: 1, color: Theme.of(context).dividerColor),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: () => _confirmReset(context),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('恢复默认'),
                style: TextButton.styleFrom(foregroundColor: context.subtextColor),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 顶部功能入口排序与显隐配置
  Widget _buildFeaturesTab(BuildContext context, HomeLayoutProvider layout) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Text(
            '💡 开关控制主页金刚区是否展示，长按右侧手柄可拖拽上下排序',
            style: TextStyle(fontSize: 12, color: context.subtextColor),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            buildDefaultDragHandles: false,
            itemCount: layout.features.length,
            onReorder: (oldIndex, newIndex) => layout.reorderFeatures(oldIndex, newIndex),
            itemBuilder: (ctx, index) {
              final item = layout.features[index];
              return Card(
                key: ValueKey('feat_${item.id}'),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: item.color.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(item.icon, color: item.color, size: 22),
                  ),
                  title: Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: item.enabled ? null : context.subtextColor,
                    ),
                  ),
                  subtitle: Text(
                    item.subtitle,
                    style: TextStyle(fontSize: 12, color: context.subtextColor),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch.adaptive(
                        value: item.enabled,
                        activeColor: AppColors.primaryBlue,
                        onChanged: (val) => layout.toggleFeature(item.id, val),
                      ),
                      const SizedBox(width: 4),
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            color: context.subtextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 侧边栏/底部导航栏排序与显隐配置
  Widget _buildNavItemsTab(BuildContext context, HomeLayoutProvider layout) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Text(
            '💡 “主页”固定保留在首位。长按手柄可拖拽排序，关闭的模块仍可通过主页入口访问。',
            style: TextStyle(fontSize: 12, color: context.subtextColor),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            buildDefaultDragHandles: false,
            itemCount: layout.navItems.length,
            onReorder: (oldIndex, newIndex) => layout.reorderNavItems(oldIndex, newIndex),
            itemBuilder: (ctx, index) {
              final item = layout.navItems[index];
              return Card(
                key: ValueKey('nav_${item.id}'),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(item.icon, color: AppColors.primaryBlue, size: 22),
                  ),
                  title: Row(
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '移动端: ${item.shortTitle}',
                          style: TextStyle(fontSize: 11, color: context.subtextColor),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    item.isFixed ? '核心页面（固定常驻）' : (item.enabled ? '已在侧栏与底部导航中展示' : '已从侧栏与底部导航中隐藏'),
                    style: TextStyle(fontSize: 12, color: context.subtextColor),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.isFixed)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Tooltip(
                            message: '主页为核心入口，不可隐藏',
                            child: Icon(Icons.lock_rounded, size: 18, color: Colors.grey),
                          ),
                        )
                      else
                        Switch.adaptive(
                          value: item.enabled,
                          activeColor: AppColors.primaryBlue,
                          onChanged: (val) {
                            final success = layout.toggleNavItem(item.id, val);
                            if (!success && !val) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('至少需要保留 2 个导航项'),
                                  backgroundColor: AppColors.warningOrange,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        ),
                      if (!item.isFixed)
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Icon(
                              Icons.drag_handle_rounded,
                              color: context.subtextColor,
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 32),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 资源看板卡片排序与显隐配置
  Widget _buildCardsTab(BuildContext context, HomeLayoutProvider layout) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Text(
            '💡 开关控制主页是否展示对应卡片，长按右侧手柄可调整展示次序',
            style: TextStyle(fontSize: 12, color: context.subtextColor),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            buildDefaultDragHandles: false,
            itemCount: layout.cards.length,
            onReorder: (oldIndex, newIndex) => layout.reorderCards(oldIndex, newIndex),
            itemBuilder: (ctx, index) {
              final card = layout.cards[index];
              return Card(
                key: ValueKey('card_${card.id}'),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(card.icon, color: AppColors.primaryBlue, size: 22),
                  ),
                  title: Text(
                    card.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: card.enabled ? null : context.subtextColor,
                    ),
                  ),
                  subtitle: Text(
                    card.description,
                    style: TextStyle(fontSize: 12, color: context.subtextColor),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch.adaptive(
                        value: card.enabled,
                        activeColor: AppColors.primaryBlue,
                        onChanged: (val) => layout.toggleCard(card.id, val),
                      ),
                      const SizedBox(width: 4),
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            color: context.subtextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
