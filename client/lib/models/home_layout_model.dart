import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

/// 首页顶部功能快捷入口配置项
class HomeFeatureItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int tabIndex;
  final bool enabled;

  const HomeFeatureItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.tabIndex,
    this.enabled = true,
  });

  HomeFeatureItem copyWith({
    String? title,
    String? subtitle,
    IconData? icon,
    Color? color,
    int? tabIndex,
    bool? enabled,
  }) {
    return HomeFeatureItem(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      tabIndex: tabIndex ?? this.tabIndex,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
      };
}

/// 首页原资源看板卡片配置项
class HomeCardItem {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final bool enabled;

  const HomeCardItem({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.enabled = true,
  });

  HomeCardItem copyWith({
    String? title,
    String? description,
    IconData? icon,
    bool? enabled,
  }) {
    return HomeCardItem(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
      };
}

/// 侧边栏/底部导航栏配置项
class HomeNavItem {
  final String id;
  final String title;
  final String shortTitle;
  final IconData icon;
  final IconData selectedIcon;
  final int viewIndex;
  final bool enabled;
  final bool isFixed;

  const HomeNavItem({
    required this.id,
    required this.title,
    required this.shortTitle,
    required this.icon,
    required this.selectedIcon,
    required this.viewIndex,
    this.enabled = true,
    this.isFixed = false,
  });

  HomeNavItem copyWith({
    String? title,
    String? shortTitle,
    IconData? icon,
    IconData? selectedIcon,
    int? viewIndex,
    bool? enabled,
    bool? isFixed,
  }) {
    return HomeNavItem(
      id: id,
      title: title ?? this.title,
      shortTitle: shortTitle ?? this.shortTitle,
      icon: icon ?? this.icon,
      selectedIcon: selectedIcon ?? this.selectedIcon,
      viewIndex: viewIndex ?? this.viewIndex,
      enabled: enabled ?? this.enabled,
      isFixed: isFixed ?? this.isFixed,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
      };
}

/// 首页整体布局配置（功能项、导航栏与卡片的排序及显隐）
class HomeLayoutConfig {
  final List<HomeFeatureItem> features;
  final List<HomeNavItem> navItems;
  final List<HomeCardItem> cards;

  const HomeLayoutConfig({
    required this.features,
    required this.navItems,
    required this.cards,
  });

  Map<String, dynamic> toJson() => {
        'features': features.map((f) => f.toJson()).toList(),
        'navItems': navItems.map((n) => n.toJson()).toList(),
        'cards': cards.map((c) => c.toJson()).toList(),
      };

  String toJsonString() => jsonEncode(toJson());

  factory HomeLayoutConfig.fromJsonString(String rawJson) {
    try {
      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      final rawFeatures = map['features'] as List<dynamic>? ?? [];
      final rawNavItems = map['navItems'] as List<dynamic>? ?? [];
      final rawCards = map['cards'] as List<dynamic>? ?? [];

      // 依据默认配置映射，保证新增字段或缺失字段的前后兼容
      final defaultFeaturesMap = {
        for (final f in HomeLayoutDefaults.defaultFeatures) f.id: f
      };
      final List<HomeFeatureItem> resolvedFeatures = [];

      for (final item in rawFeatures) {
        if (item is Map<String, dynamic>) {
          final id = item['id']?.toString();
          if (id != null && defaultFeaturesMap.containsKey(id)) {
            final def = defaultFeaturesMap.remove(id)!;
            resolvedFeatures.add(def.copyWith(enabled: item['enabled'] == true));
          }
        }
      }
      // 追加未在配置中出现的新增功能项
      resolvedFeatures.addAll(defaultFeaturesMap.values);

      final defaultNavItemsMap = {
        for (final n in HomeLayoutDefaults.defaultNavItems) n.id: n
      };
      final List<HomeNavItem> resolvedNavItems = [];

      for (final item in rawNavItems) {
        if (item is Map<String, dynamic>) {
          final id = item['id']?.toString();
          if (id != null && defaultNavItemsMap.containsKey(id)) {
            final def = defaultNavItemsMap.remove(id)!;
            final isEnabled = def.isFixed ? true : (item['enabled'] == true);
            resolvedNavItems.add(def.copyWith(enabled: isEnabled));
          }
        }
      }
      // 追加未在配置中出现的新增导航项
      resolvedNavItems.addAll(defaultNavItemsMap.values);

      // 保证至少有 2 个启用的导航项以满足 NavigationBar / NavigationRail 规范
      if (resolvedNavItems.where((n) => n.enabled).length < 2) {
        for (int i = 0; i < resolvedNavItems.length && i < 2; i++) {
          resolvedNavItems[i] = resolvedNavItems[i].copyWith(enabled: true);
        }
      }

      final defaultCardsMap = {
        for (final c in HomeLayoutDefaults.defaultCards) c.id: c
      };
      final List<HomeCardItem> resolvedCards = [];

      for (final item in rawCards) {
        if (item is Map<String, dynamic>) {
          final id = item['id']?.toString();
          if (id != null && defaultCardsMap.containsKey(id)) {
            final def = defaultCardsMap.remove(id)!;
            resolvedCards.add(def.copyWith(enabled: item['enabled'] == true));
          }
        }
      }
      // 追加未在配置中出现的新增卡片
      resolvedCards.addAll(defaultCardsMap.values);

      return HomeLayoutConfig(
        features: resolvedFeatures,
        navItems: resolvedNavItems,
        cards: resolvedCards,
      );
    } catch (_) {
      return HomeLayoutDefaults.defaultConfig;
    }
  }
}

/// 默认配置常数
class HomeLayoutDefaults {
  static const List<HomeNavItem> defaultNavItems = [
    HomeNavItem(
      id: 'home',
      title: '主页',
      shortTitle: '主页',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
      viewIndex: 0,
      enabled: true,
      isFixed: true,
    ),
    HomeNavItem(
      id: 'tasks',
      title: '下载管理',
      shortTitle: '下载',
      icon: Icons.download_outlined,
      selectedIcon: Icons.download_rounded,
      viewIndex: 1,
      enabled: true,
    ),
    HomeNavItem(
      id: 'agent_tasks',
      title: '智能体任务',
      shortTitle: '智能体',
      icon: Icons.smart_toy_outlined,
      selectedIcon: Icons.smart_toy_rounded,
      viewIndex: 2,
      enabled: true,
    ),
    HomeNavItem(
      id: 'ai_chat',
      title: 'AI 副驾驶',
      shortTitle: '副驾驶',
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome_rounded,
      viewIndex: 6,
      enabled: true,
    ),
    HomeNavItem(
      id: 'rss',
      title: 'RSS 订阅',
      shortTitle: '订阅',
      icon: Icons.rss_feed_outlined,
      selectedIcon: Icons.rss_feed_rounded,
      viewIndex: 3,
      enabled: true,
    ),
    HomeNavItem(
      id: 'trash',
      title: '回收站',
      shortTitle: '回收站',
      icon: Icons.delete_outline_rounded,
      selectedIcon: Icons.delete_rounded,
      viewIndex: 4,
      enabled: true,
    ),
    HomeNavItem(
      id: 'settings',
      title: '设置',
      shortTitle: '设置',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      viewIndex: 5,
      enabled: true,
    ),
  ];

  static const List<HomeFeatureItem> defaultFeatures = [
    HomeFeatureItem(
      id: 'tasks',
      title: '下载管理',
      subtitle: '查看与管控下载任务',
      icon: Icons.download_rounded,
      color: AppColors.primaryBlue,
      tabIndex: 1,
      enabled: true,
    ),
    HomeFeatureItem(
      id: 'agent_tasks',
      title: '智能体任务',
      subtitle: '调度自动化 AI 任务',
      icon: Icons.smart_toy_rounded,
      color: AppColors.accentCyan,
      tabIndex: 2,
      enabled: true,
    ),
    HomeFeatureItem(
      id: 'ai_chat',
      title: 'AI 副驾驶',
      subtitle: '对话治理与事务回滚',
      icon: Icons.auto_awesome_rounded,
      color: Color(0xFF8B5CF6),
      tabIndex: 6,
      enabled: true,
    ),
    HomeFeatureItem(
      id: 'rss',
      title: 'RSS 订阅',
      subtitle: '自动监听与过滤下载',
      icon: Icons.rss_feed_rounded,
      color: Color(0xFFFF7A00),
      tabIndex: 3,
      enabled: true,
    ),
    HomeFeatureItem(
      id: 'trash',
      title: '回收站',
      subtitle: '软删除文件安全保护',
      icon: Icons.delete_rounded,
      color: AppColors.warningOrange,
      tabIndex: 4,
      enabled: true,
    ),
    HomeFeatureItem(
      id: 'settings',
      title: '设置',
      subtitle: '节点连接与工具配置',
      icon: Icons.settings_rounded,
      color: AppColors.successGreen,
      tabIndex: 5,
      enabled: true,
    ),
  ];

  static const List<HomeCardItem> defaultCards = [
    HomeCardItem(
      id: 'storage_pools',
      title: '物理存储池状态',
      description: '实时挂载存储池容量与使用概览',
      icon: Icons.pie_chart_outline_rounded,
      enabled: true,
    ),
    HomeCardItem(
      id: 'sandbox_whitelist',
      title: '沙箱白名单管控',
      description: 'AI 智能体可访问目录安全名单',
      icon: Icons.security_rounded,
      enabled: true,
    ),
    HomeCardItem(
      id: 'disaster_recovery',
      title: '防灾安全配置',
      description: '回收站物理目录及保留周期',
      icon: Icons.restore_from_trash_rounded,
      enabled: true,
    ),
  ];

  static HomeLayoutConfig get defaultConfig => const HomeLayoutConfig(
        features: defaultFeatures,
        navItems: defaultNavItems,
        cards: defaultCards,
      );
}
