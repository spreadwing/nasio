import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../providers/connection_provider.dart';
import '../providers/home_layout_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/update_provider.dart';
import 'connection/connection_view.dart';
import 'dashboard/dashboard_view.dart';
import 'tasks/tasks_view.dart';
import 'agent_tasks/agent_tasks_view.dart';
import 'rss/rss_view.dart';
import 'trash/trash_view.dart';
import 'chat/chat_view.dart';

class HomeScaffold extends StatefulWidget {
  const HomeScaffold({super.key});

  /// 供子树页面便捷触发主导航 Tab 切换 (例如从主页快捷入口跳转或点击返回主页)
  static void switchToTab(BuildContext context, int index, {String? rssId}) {
    context.findAncestorStateOfType<_HomeScaffoldState>()?._switchTab(index, rssId: rssId);
  }

  @override
  State<HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<HomeScaffold> {
  int _currentIndex = 0;
  String? _pendingRssId;
  final GlobalKey<ConnectionViewState> _connectionKey = GlobalKey<ConnectionViewState>();

  void _switchTab(int index, {String? rssId}) {
    if (mounted) {
      setState(() {
        _currentIndex = index;
        if (rssId != null) {
          _pendingRssId = rssId;
        }
      });
    }
  }

  List<Widget> get _views => [
    DashboardView(onNavigateTab: (idx) => _switchTab(idx)),
    const TasksView(),
    const AgentTasksView(),
    RssView(initialSelectedRssId: _pendingRssId),
    const TrashView(),
    ConnectionView(key: _connectionKey),
    const ChatView(),
  ];

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    final updateProv = context.watch<UpdateProvider>();
    final layout = context.watch<HomeLayoutProvider>();
    final activeNavItems = layout.activeNavItems;
    final showSettingsBadge = !conn.isConnected || updateProv.hasUpdate;
    final badgeColor = !conn.isConnected ? AppColors.errorRed : AppColors.successGreen;

    // 当前视图索引对应激活导航项的索引（如当前视图在导航栏中被隐藏则为 -1）
    final selectedNavIndex = activeNavItems.indexWhere((n) => n.viewIndex == _currentIndex);

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        // 若当前处于设置视图，优先检查内部是否有钻取二级页面需要返回至菜单
        if (_currentIndex == 5) {
          final handled = _connectionKey.currentState?.handleBack() ?? false;
          if (handled) return;
        }

        // 不在主页时，通过手势或系统返回一律回到主页，避免直接最小化
        _switchTab(0);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 720;

        if (isWideScreen) {
          // -------------------------------------------------------------
          // 桌面 / 平板 / 宽屏响应式布局 (侧边 NavigationRail)
          // -------------------------------------------------------------
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedNavIndex == -1 ? null : selectedNavIndex,
                  onDestinationSelected: (index) {
                    final targetViewIndex = activeNavItems[index].viewIndex;
                    setState(() => _currentIndex = targetViewIndex);
                  },
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primaryBlue, AppColors.accentCyan],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.dns_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Nasio',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  destinations: activeNavItems.map((item) {
                    final isSettings = item.id == 'settings';
                    Widget iconWidget = Icon(item.icon);
                    Widget selectedIconWidget = Icon(item.selectedIcon);
                    if (isSettings) {
                      iconWidget = Badge(
                        isLabelVisible: showSettingsBadge,
                        backgroundColor: badgeColor,
                        smallSize: 8,
                        child: Icon(
                          item.icon,
                          color: conn.isConnected ? null : AppColors.errorRed,
                        ),
                      );
                      selectedIconWidget = Badge(
                        isLabelVisible: showSettingsBadge,
                        backgroundColor: badgeColor,
                        smallSize: 8,
                        child: Icon(item.selectedIcon),
                      );
                    }
                    return NavigationRailDestination(
                      icon: iconWidget,
                      selectedIcon: selectedIconWidget,
                      label: Text(item.title),
                    );
                  }).toList(),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Consumer<ThemeProvider>(
                          builder: (context, themeProv, _) {
                            IconData icon;
                            String tooltip;
                            switch (themeProv.themeMode) {
                              case ThemeMode.light:
                                icon = Icons.light_mode_rounded;
                                tooltip = '当前：明亮浅色（点击切换）';
                                break;
                              case ThemeMode.dark:
                                icon = Icons.dark_mode_rounded;
                                tooltip = '当前：科技暗黑（点击切换）';
                                break;
                              case ThemeMode.system:
                                icon = Icons.brightness_auto_rounded;
                                tooltip = '当前：跟随系统（点击切换）';
                                break;
                            }
                            return IconButton(
                              icon: Icon(icon),
                              tooltip: tooltip,
                              onPressed: () => themeProv.toggleTheme(context),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                VerticalDivider(width: 1, thickness: 1, color: Theme.of(context).dividerColor),
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: _views,
                  ),
                ),
              ],
            ),
          );
        } else {
          // -------------------------------------------------------------
          // 移动端手机布局 (底部 NavigationBar)
          // -------------------------------------------------------------
          return Scaffold(
            body: IndexedStack(
              index: _currentIndex,
              children: _views,
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: selectedNavIndex == -1 ? 0 : selectedNavIndex,
              onDestinationSelected: (index) {
                final targetViewIndex = activeNavItems[index].viewIndex;
                setState(() => _currentIndex = targetViewIndex);
              },
              destinations: activeNavItems.map((item) {
                final isSettings = item.id == 'settings';
                Widget iconWidget = Icon(item.icon);
                Widget selectedIconWidget = Icon(item.selectedIcon);
                if (isSettings) {
                  iconWidget = Badge(
                    isLabelVisible: showSettingsBadge,
                    backgroundColor: badgeColor,
                    smallSize: 8,
                    child: Icon(
                      item.icon,
                      color: conn.isConnected ? null : AppColors.errorRed,
                    ),
                  );
                  selectedIconWidget = Badge(
                    isLabelVisible: showSettingsBadge,
                    backgroundColor: badgeColor,
                    smallSize: 8,
                    child: Icon(item.selectedIcon),
                  );
                }
                return NavigationDestination(
                  icon: iconWidget,
                  selectedIcon: selectedIconWidget,
                  label: item.shortTitle,
                );
              }).toList(),
            ),
          );
        }
      },
    ),
  );
}
}
