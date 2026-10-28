import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import '../../providers/connection_provider.dart';
import '../../providers/storage_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/agent_task_provider.dart';
import '../../providers/missing_mcp_provider.dart';
import '../../providers/trash_provider.dart';
import '../../providers/rss_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/update_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/storage_service.dart';
import '../../widgets/update_dialog.dart';
import '../dashboard/home_layout_config_dialog.dart';
import '../home_scaffold.dart';
import 'mcp_config_section.dart';
import 'skills_config_section.dart';

/// 设置页二级菜单分类枚举
enum SettingsSection {
  connection(
    title: '服务连接',
    subtitle: 'NAS 网关地址、端口与安全令牌',
    icon: Icons.dns_outlined,
    selectedIcon: Icons.dns_rounded,
  ),
  users(
    title: '用户与权限',
    subtitle: '系统账号管理与管理员/普通用户角色',
    icon: Icons.manage_accounts_outlined,
    selectedIcon: Icons.manage_accounts_rounded,
  ),
  mcp(
    title: 'MCP 接入',
    subtitle: '按需生成各 AI Agent 专属配置',
    icon: Icons.hub_outlined,
    selectedIcon: Icons.hub_rounded,
  ),
  skills(
    title: '技能中心',
    subtitle: 'SOP 规范管理、预览删除与 Agent 自举集成',
    icon: Icons.auto_stories_outlined,
    selectedIcon: Icons.auto_stories_rounded,
  ),
  appearance(
    title: '外观偏好',
    subtitle: '客户端主题风格与视觉显示模式',
    icon: Icons.palette_outlined,
    selectedIcon: Icons.palette_rounded,
  ),
  about(
    title: '关于与更新',
    subtitle: '版本检测、跨端更新与软件源配置',
    icon: Icons.system_update_outlined,
    selectedIcon: Icons.system_update_rounded,
  );

  final String title;
  final String subtitle;
  final IconData icon;
  final IconData selectedIcon;

  const SettingsSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selectedIcon,
  });
}

class ConnectionView extends StatefulWidget {
  const ConnectionView({super.key});

  @override
  State<ConnectionView> createState() => ConnectionViewState();
}

class ConnectionViewState extends State<ConnectionView> {
  // 宽屏当前选中的二级菜单项
  SettingsSection _selectedSection = SettingsSection.connection;
  // 窄屏/手机端钻取状态：为 null 时显示二级菜单列表首页，非 null 时进入对应二级详情页
  SettingsSection? _mobileActiveSection;

  /// 处理手势或系统返回。若内部处于二级详情页，则返回设置菜单首页并返回 true；否则返回 false 由外层回到主页。
  bool handleBack() {
    if (_mobileActiveSection != null) {
      setState(() => _mobileActiveSection = null);
      return true;
    }
    return false;
  }

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _tokenController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  AuthType _authType = AuthType.token;
  bool _isHttps = false;
  bool _obscureToken = true;
  bool _obscurePassword = true;
  List<ConnectionPreset> _historyPresets = [];

  @override
  void initState() {
    super.initState();
    final conn = context.read<ConnectionProvider>();
    _hostController = TextEditingController(text: conn.host);
    _portController = TextEditingController(text: conn.port.toString());
    _tokenController = TextEditingController(text: conn.token);
    _authType = conn.authType;
    _usernameController = TextEditingController(text: conn.username.isNotEmpty ? conn.username : 'admin');
    _passwordController = TextEditingController(text: conn.password);
    _isHttps = conn.isHttps;
    _historyPresets = StorageService.getConnectionHistory();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _selectSection(SettingsSection section, {required bool isWideScreen}) {
    setState(() {
      _selectedSection = section;
      if (!isWideScreen) {
        _mobileActiveSection = section;
      }
    });
    if (section == SettingsSection.users) {
      context.read<UserProvider>().loadUsers();
    }
  }

  void _fillPreset(ConnectionPreset preset) {
    setState(() {
      _hostController.text = preset.host;
      _portController.text = preset.port.toString();
      _tokenController.text = preset.token;
      _isHttps = preset.isHttps;
      _authType = preset.authType;
      if (preset.username != null && preset.username!.isNotEmpty) {
        _usernameController.text = preset.username!;
      }
      if (preset.password != null) {
        _passwordController.text = preset.password!;
      }
    });
  }

  Future<void> _removePreset(ConnectionPreset preset) async {
    await StorageService.removeConnectionPreset(preset.host, preset.port);
    setState(() {
      _historyPresets = StorageService.getConnectionHistory();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已从预设中移除: ${preset.displayTitle}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _submitConnect() async {
    if (!_formKey.currentState!.validate()) return;

    final conn = context.read<ConnectionProvider>();
    final success = await conn.connect(
      host: _hostController.text.trim(),
      port: int.parse(_portController.text.trim()),
      token: _tokenController.text.trim(),
      isHttps: _isHttps,
      authType: _authType,
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
    );

    if (mounted) {
      setState(() {
        _historyPresets = StorageService.getConnectionHistory();
      });

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已成功连接到 Nasio 服务端！连接已保持。'),
            backgroundColor: AppColors.successGreen,
          ),
        );
        // 全量载入/刷新业务数据
        _reloadAllBusinessData(context, conn);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(conn.errorMessage ?? '连接失败，请检查配置'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    }
  }

  void _reloadAllBusinessData(BuildContext context, ConnectionProvider conn) {
    context.read<StorageProvider>().loadConfig();
    context.read<TaskProvider>().loadTasks();
    context.read<AgentTaskProvider>().loadTasks();
    context.read<MissingMcpProvider>().loadItems();
    context.read<TrashProvider>().loadTrash();
    context.read<RssProvider>().loadSubscriptions();
    context.read<ChatProvider>().loadAll();
    if (conn.isAdmin) {
      context.read<UserProvider>().loadUsers();
    }
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '明亮浅色';
      case ThemeMode.dark:
        return '科技暗黑';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  String _sectionStatusSummary(
    SettingsSection section,
    ConnectionProvider conn,
    ThemeProvider themeProv,
    UpdateProvider updateProv,
  ) {
    switch (section) {
      case SettingsSection.connection:
        return conn.isConnected ? '已连接 ${conn.host}:${conn.port}' : '未连接服务';
      case SettingsSection.users:
        return conn.isAdmin ? '管理员（可管理系统用户）' : '普通用户模式';
      case SettingsSection.mcp:
        return '支持 5 类主流 Agent';
      case SettingsSection.skills:
        return 'SOP 规范与自举 Prompt';
      case SettingsSection.appearance:
        return '当前：${_themeModeLabel(themeProv.themeMode)}';
      case SettingsSection.about:
        return updateProv.hasUpdate && updateProv.latestRelease != null
            ? '发现新版本 v${updateProv.latestRelease!.version}'
            : '当前版本 v${updateProv.currentVersion}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    final themeProv = context.watch<ThemeProvider>();
    final updateProv = context.watch<UpdateProvider>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 720;

        if (isWideScreen) {
          return _buildWideScreenLayout(context, conn, themeProv, updateProv);
        } else {
          return _buildMobileLayout(context, conn, themeProv, updateProv);
        }
      },
    );
  }

  // ===========================================================================
  // 1. 桌面 / 宽屏分栏布局（左侧二级导航菜单 + 右侧配置内容区）
  // ===========================================================================
  Widget _buildWideScreenLayout(
    BuildContext context,
    ConnectionProvider conn,
    ThemeProvider themeProv,
    UpdateProvider updateProv,
  ) {
    final isDark = context.isDark;
    final activeAccent = isDark ? AppColors.accentCyan : AppColors.primaryBlue;

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧二级菜单侧边栏
          Container(
            width: 248,
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 18, 16, 14),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: '返回主页',
                        onPressed: () => HomeScaffold.switchToTab(context, 0),
                      ),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Text(
                          '系统设置',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Theme.of(context).dividerColor),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: SettingsSection.values.map((section) {
                      final isSelected = _selectedSection == section;
                      final statusText =
                          _sectionStatusSummary(section, conn, themeProv, updateProv);

                      Color? badgeColor;
                      if (section == SettingsSection.connection) {
                        badgeColor =
                            conn.isConnected ? AppColors.successGreen : AppColors.errorRed;
                      } else if (section == SettingsSection.about && updateProv.hasUpdate) {
                        badgeColor = AppColors.successGreen;
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6.0),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _selectSection(section, isWideScreen: true),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primaryBlue
                                      .withOpacity(isDark ? 0.2 : 0.1)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? activeAccent.withOpacity(0.6)
                                    : Colors.transparent,
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primaryBlue.withOpacity(0.2)
                                        : (isDark
                                            ? Colors.white.withOpacity(0.05)
                                            : const Color(0xFFF1F5F9)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isSelected ? section.selectedIcon : section.icon,
                                    size: 20,
                                    color: isSelected
                                        ? activeAccent
                                        : context.subtextColor,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              section.title,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.w600,
                                                color: isSelected
                                                    ? (isDark
                                                        ? Colors.white
                                                        : AppColors.primaryBlueDark)
                                                    : (isDark
                                                        ? Colors.white70
                                                        : AppColors.lightTitle),
                                              ),
                                            ),
                                          ),
                                          if (badgeColor != null)
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: badgeColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        statusText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isSelected
                                              ? activeAccent
                                              : context.tertiaryTextColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          VerticalDivider(width: 1, thickness: 1, color: Theme.of(context).dividerColor),

          // 右侧二级内容面板
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 右侧面板顶部标题栏
                Container(
                  padding: const EdgeInsets.fromLTRB(28, 18, 24, 14),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedSection.selectedIcon,
                        color: activeAccent,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedSection.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                        ),
                        tooltip: isDark ? '切换至明亮浅色主题' : '切换至科技暗黑主题',
                        onPressed: () =>
                            context.read<ThemeProvider>().toggleTheme(context),
                      ),
                    ],
                  ),
                ),

                // 右侧主体内容（使用 IndexedStack 保持各二级面板状态）
                Expanded(
                  child: IndexedStack(
                    index: _selectedSection.index,
                    children: [
                      _buildSectionScrollWrapper(
                        maxWidth: 680,
                        child: _buildConnectionSectionContent(context, conn),
                      ),
                      _buildSectionScrollWrapper(
                        maxWidth: 760,
                        child: _buildUserManagementSectionContent(context, conn),
                      ),
                      _buildSectionScrollWrapper(
                        maxWidth: 820,
                        child: const McpConfigSection(),
                      ),
                      _buildSectionScrollWrapper(
                        maxWidth: 820,
                        child: const SkillsConfigSection(),
                      ),
                      _buildSectionScrollWrapper(
                        maxWidth: 680,
                        child: _buildAppearanceSectionContent(context, themeProv),
                      ),
                      _buildSectionScrollWrapper(
                        maxWidth: 680,
                        child: _buildAboutAndUpdateSectionContent(context, updateProv),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionScrollWrapper({
    required double maxWidth,
    required Widget child,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: child,
        ),
      ),
    );
  }

  // ===========================================================================
  // 2. 手机 / 窄屏钻取式布局（二级菜单入口列表 -> 点击进入二级详情页）
  // ===========================================================================
  Widget _buildMobileLayout(
    BuildContext context,
    ConnectionProvider conn,
    ThemeProvider themeProv,
    UpdateProvider updateProv,
  ) {
    final activeSection = _mobileActiveSection;

    return activeSection == null
        ? _buildMobileMenuListScaffold(context, conn, themeProv, updateProv)
        : _buildMobileSubPageScaffold(
            context,
            activeSection,
            conn,
            themeProv,
            updateProv,
          );
  }

  Widget _buildMobileMenuListScaffold(
    BuildContext context,
    ConnectionProvider conn,
    ThemeProvider themeProv,
    UpdateProvider updateProv,
  ) {
    final isDark = context.isDark;
    final activeAccent = isDark ? AppColors.accentCyan : AppColors.primaryBlue;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回主页',
          onPressed: () => HomeScaffold.switchToTab(context, 0),
        ),
        title: const Text('系统设置'),
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
            tooltip: isDark ? '切换至明亮浅色主题' : '切换至科技暗黑主题',
            onPressed: () => context.read<ThemeProvider>().toggleTheme(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 顶部当前连接状态快捷卡片
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _selectSection(
                SettingsSection.connection,
                isWideScreen: false,
              ),
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (conn.isConnected ? AppColors.successGreen : Colors.grey)
                            .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        conn.isConnected
                            ? Icons.cloud_done_rounded
                            : Icons.cloud_off_rounded,
                        color: conn.isConnected ? AppColors.successGreen : Colors.grey,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  conn.isConnected ? 'NAS 服务已连接' : '尚未连接 NAS 服务',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (conn.isConnected
                                          ? AppColors.successGreen
                                          : AppColors.errorRed)
                                      .withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  conn.isConnected ? '在线' : '未连接',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: conn.isConnected
                                        ? AppColors.successGreen
                                        : AppColors.errorRed,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            conn.isConnected
                                ? '网关地址: ${conn.host}:${conn.port}'
                                : '点击前往配置绿联 NAS 服务器地址与访问令牌',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: context.subtextColor),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: context.subtextColor),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '功能设置菜单',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: context.subtextColor,
              ),
            ),
          ),

          // 二级菜单列表卡片
          ...SettingsSection.values.map((section) {
            final statusSummary =
                _sectionStatusSummary(section, conn, themeProv, updateProv);
            final hasHighlightBadge =
                (section == SettingsSection.connection && !conn.isConnected) ||
                    (section == SettingsSection.about && updateProv.hasUpdate);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onTap: () => _selectSection(section, isWideScreen: false),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      section.selectedIcon,
                      color: activeAccent,
                      size: 22,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          section.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (hasHighlightBadge) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: (section == SettingsSection.about
                                    ? AppColors.successGreen
                                    : AppColors.errorRed)
                                .withOpacity(0.18),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            section == SettingsSection.about ? 'NEW' : '待配置',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: section == SettingsSection.about
                                  ? AppColors.successGreen
                                  : AppColors.errorRed,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.subtitle,
                          style: TextStyle(fontSize: 12, color: context.subtextColor),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          statusSummary,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: activeAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.subtextColor,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMobileSubPageScaffold(
    BuildContext context,
    SettingsSection section,
    ConnectionProvider conn,
    ThemeProvider themeProv,
    UpdateProvider updateProv,
  ) {
    Widget bodyContent;
    switch (section) {
      case SettingsSection.connection:
        bodyContent = _buildConnectionSectionContent(context, conn);
        break;
      case SettingsSection.users:
        bodyContent = _buildUserManagementSectionContent(context, conn);
        break;
      case SettingsSection.mcp:
        bodyContent = const McpConfigSection();
        break;
      case SettingsSection.skills:
        bodyContent = const SkillsConfigSection();
        break;
      case SettingsSection.appearance:
        bodyContent = _buildAppearanceSectionContent(context, themeProv);
        break;
      case SettingsSection.about:
        bodyContent = _buildAboutAndUpdateSectionContent(context, updateProv);
        break;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回设置菜单',
          onPressed: () => setState(() => _mobileActiveSection = null),
        ),
        title: Text(section.title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: bodyContent,
      ),
    );
  }

  // ===========================================================================
  // 二级页面 1：服务连接 (Connection)
  // ===========================================================================
  Widget _buildConnectionSectionContent(
    BuildContext context,
    ConnectionProvider conn,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 连接状态卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (conn.isConnected ? AppColors.successGreen : Colors.grey)
                              .withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          conn.isConnected
                              ? Icons.cloud_done_rounded
                              : Icons.cloud_off_rounded,
                          color: conn.isConnected ? AppColors.successGreen : Colors.grey,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    conn.isConnected ? '服务连接正常' : '未连接到服务',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (conn.isConnected) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.successGreen.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '保持连接中',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.successGreen,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              conn.isConnected
                                  ? '当前地址: ${conn.host}:${conn.port}'
                                  : '请输入绿联 NAS 内网 IP 或反向代理地址',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.subtextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (conn.isConnected)
                        TextButton.icon(
                          onPressed: () {
                            conn.disconnect();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已断开连接')),
                            );
                          },
                          icon: const Icon(Icons.link_off_rounded,
                              size: 16, color: AppColors.errorRed),
                          label: const Text(
                            '断开',
                            style: TextStyle(color: AppColors.errorRed, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                  if (conn.errorMessage != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.errorRed.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.errorRed.withOpacity(0.35),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.error_outline_rounded,
                              size: 18,
                              color: AppColors.errorRed,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      '连接失败',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.errorRed,
                                      ),
                                    ),
                                    const Spacer(),
                                    InkWell(
                                      onTap: () => conn.clearErrorMessage(),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.all(2.0),
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 16,
                                          color: context.subtextColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  conn.errorMessage!,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.45,
                                    color: context.isDark ? Colors.white70 : const Color(0xFF991B1B),
                                  ),
                                ),
                                if (conn.errorMessage!.contains('401') ||
                                    conn.errorMessage!.contains('认证失败') ||
                                    conn.errorMessage!.contains('连接超时') ||
                                    conn.errorMessage!.contains('网络无法连通')) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    conn.errorMessage!.contains('401') || conn.errorMessage!.contains('认证失败')
                                        ? '💡 排查建议：请检查是否在右上方选择了正确的鉴权方式（Token 或 账号密码），并核对安全令牌或密码是否正确。'
                                        : '💡 排查建议：① 确认手机/电脑与 NAS 处于同一局域网；② 检查端口（8000 为直连，8086 为 Web 网关反代）；③ 确认 Nasio 容器正在运行。',
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.4,
                                      color: context.subtextColor,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 快速预填历史记录栏
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '快速填充预设 (历史连接记录):',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.subtextColor,
                  ),
                ),
              ),
              if (kIsWeb && Uri.base.host.isNotEmpty && Uri.base.host != 'localhost')
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _hostController.text = Uri.base.host;
                      _portController.text =
                          (Uri.base.hasPort && Uri.base.port != 0)
                              ? Uri.base.port.toString()
                              : (Uri.base.scheme == 'https' ? '443' : '80');
                      _isHttps = Uri.base.scheme == 'https';
                    });
                  },
                  icon: Icon(
                    Icons.language_rounded,
                    size: 14,
                    color: context.isDark ? AppColors.accentCyan : AppColors.primaryBlue,
                  ),
                  label: Text(
                    '填入当前站点',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.isDark ? AppColors.accentCyan : AppColors.primaryBlue,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (_historyPresets.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: context.isDark
                    ? Colors.white.withOpacity(0.03)
                    : Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Text(
                '暂无连接历史记录。成功连接后，系统会自动保存为历史预设方便快速切换。',
                style: TextStyle(fontSize: 12, color: context.tertiaryTextColor),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _historyPresets.map((preset) {
                final isCurrentSelected =
                    _hostController.text.trim() == preset.host &&
                        _portController.text.trim() == preset.port.toString() &&
                        _isHttps == preset.isHttps;
                final activeColor =
                    context.isDark ? AppColors.accentCyan : AppColors.primaryBlue;

                return InputChip(
                  avatar: Icon(
                    preset.isHttps ? Icons.lock_outline_rounded : Icons.dns_rounded,
                    size: 15,
                    color: isCurrentSelected ? activeColor : context.subtextColor,
                  ),
                  label: Text(
                    preset.displayTitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isCurrentSelected
                          ? activeColor
                          : (context.isDark ? Colors.white : AppColors.lightTitle),
                      fontWeight:
                          isCurrentSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isCurrentSelected,
                  selectedColor:
                      AppColors.primaryBlue.withOpacity(context.isDark ? 0.25 : 0.15),
                  backgroundColor: context.isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF1F5F9),
                  onPressed: () => _fillPreset(preset),
                  deleteIcon: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: context.tertiaryTextColor,
                  ),
                  deleteButtonTooltipMessage: '移除此预设',
                  onDeleted: () => _removePreset(preset),
                );
              }).toList(),
            ),
          const SizedBox(height: 20),

          // 输入表单
          TextFormField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'NAS 服务器 IP 或主机名',
              hintText: '如 192.168.1.100 或 mynas.lan',
              prefixIcon: Icon(Icons.router_rounded),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? '请输入主机名或IP' : null,
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _portController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '统一网关端口',
              hintText: '如 8086 或 8000',
              helperText: '提示：若在 Web 控制台访问，请填写与页面一致的端口（如 8086，由 Nginx 反代）；局域网直连填写 8000',
              prefixIcon: Icon(Icons.numbers_rounded),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return '请输入端口号';
              final n = int.tryParse(v);
              if (n == null || n <= 0 || n > 65535) return '请输入合法的端口号 (1-65535)';
              return null;
            },
          ),
          // 认证方式选择 (SegmentedButton)
          const SizedBox(height: 16),
          SegmentedButton<AuthType>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: AuthType.token,
                label: Text('安全令牌'),
                icon: Icon(Icons.key_rounded, size: 16),
              ),
              ButtonSegment(
                value: AuthType.credentials,
                label: Text('账号密码'),
                icon: Icon(Icons.person_outline_rounded, size: 16),
              ),
            ],
            selected: {_authType},
            onSelectionChanged: (val) => setState(() => _authType = val.first),
          ),
          const SizedBox(height: 16),

          if (_authType == AuthType.token) ...[
            TextFormField(
              controller: _tokenController,
              obscureText: _obscureToken,
              decoration: InputDecoration(
                labelText: '安全访问令牌 (Master Token)',
                hintText: '与服务端 MCP_AUTH_TOKEN 对应',
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureToken
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                  onPressed: () => setState(() => _obscureToken = !_obscureToken),
                ),
              ),
            ),
            // 当已连接且具备管理员权限时，提供重新生成令牌按钮
            if (conn.isConnected && conn.isAdmin) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Tooltip(
                    message: '重新生成 Master Token 并自动重连',
                    child: OutlinedButton.icon(
                      onPressed: conn.isChecking ? null : () => _confirmRegenerateToken(conn),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('重新生成安全令牌'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.isDark ? AppColors.accentCyan : AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ] else ...[
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '登录用户名',
                hintText: '输入您的 Nasio 账号',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? '请输入用户名' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '登录密码',
                hintText: '输入您的账号密码',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? '请输入密码' : null,
            ),
          ],
          const SizedBox(height: 16),

          Container(
            decoration: BoxDecoration(
              color: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '启用 HTTPS / WSS 加密',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.isDark ? Colors.white : AppColors.lightTitle,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '若已为 NAS 配置 SSL 证书请开启',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.subtextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isHttps,
                  activeColor: AppColors.primaryBlue,
                  onChanged: (val) => setState(() => _isHttps = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: conn.isChecking ? null : _submitConnect,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: conn.isChecking
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    '保存并测试连接',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 二级页面 3：外观偏好 (Appearance)
  // ===========================================================================
  Widget _buildAppearanceSectionContent(
    BuildContext context,
    ThemeProvider themeProv,
  ) {
    final isDark = context.isDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.palette_outlined,
                          color: AppColors.primaryBlue, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '外观与主题风格',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '个性化客户端显示效果，支持手动锁定浅色/暗色或跟随系统自动切换',
                            style: TextStyle(
                                fontSize: 12, color: context.subtextColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    segments: const [
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_rounded, size: 16),
                        label: Text(
                          '跟随系统',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_rounded, size: 16),
                        label: Text(
                          '明亮浅色',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_rounded, size: 16),
                        label: Text(
                          '科技暗黑',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                    selected: {themeProv.themeMode},
                    onSelectionChanged: (newSelection) {
                      themeProv.setThemeMode(newSelection.first);
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                        color: isDark ? AppColors.accentCyan : AppColors.primaryBlue,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '当前实际渲染风格：${isDark ? "科技暗黑" : "明亮浅色"}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '全局采用 MiSans / HarmonyOS Sans 字体栈并开启等宽数字对齐 (tabularFigures)，确保实时速率与进度百分比显示稳定不抖动。',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.subtextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.dashboard_customize_rounded,
                          color: AppColors.primaryBlue, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '主页布局与卡片管理',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '自定义主页顶部功能金刚区入口与资源看板卡片的显隐及显示顺序',
                            style: TextStyle(
                                fontSize: 12, color: context.subtextColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => HomeLayoutConfigDialog.show(context),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('自定义主页功能与卡片'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 二级页面 4：关于与更新 (About & Updates)
  // ===========================================================================
  Widget _buildAboutAndUpdateSectionContent(
    BuildContext context,
    UpdateProvider updateProv,
  ) {
    final isDark = context.isDark;

    String platformName = '跨平台客户端';
    IconData platformIcon = Icons.devices_rounded;
    if (kIsWeb) {
      platformName = 'Web 控制台 (网页端)';
      platformIcon = Icons.language_rounded;
    } else if (Platform.isAndroid) {
      platformName = 'Android 客户端';
      platformIcon = Icons.android_rounded;
    } else if (Platform.isWindows) {
      platformName = 'Windows 桌面端';
      platformIcon = Icons.window_rounded;
    } else if (Platform.isIOS) {
      platformName = 'iOS 客户端';
      platformIcon = Icons.apple_rounded;
    } else if (Platform.isMacOS) {
      platformName = 'macOS 客户端';
      platformIcon = Icons.laptop_mac_rounded;
    } else if (Platform.isLinux) {
      platformName = 'Linux 客户端';
      platformIcon = Icons.terminal_rounded;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        color: AppColors.primaryBlue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '客户端版本与跨平台更新',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '支持 Android (APK)、Windows 桌面与 Web 端的版本检测与应用内更新',
                            style: TextStyle(fontSize: 12, color: context.subtextColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 版本与平台信息条
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(platformIcon, size: 16, color: context.subtextColor),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  platformName,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13, color: context.subtextColor),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '当前版本: v${updateProv.currentVersion}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            '更新源: ${updateProv.giteaUrl}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: context.tertiaryTextColor),
                          ),
                          if (updateProv.latestRelease != null)
                            Text(
                              '最新发布: v${updateProv.latestRelease!.version}',
                              style: TextStyle(
                                  fontSize: 11, color: context.tertiaryTextColor),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 如果已检查到新版本提示框
                if (updateProv.hasUpdate && updateProv.latestRelease != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.successGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.successGreen.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.new_releases_rounded,
                            color: AppColors.successGreen, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '检测到新版本 v${updateProv.latestRelease!.version}！包含多端更新包。',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              UpdateDialogHelper.showUpdateInfoDialog(context),
                          child: const Text('查看并更新'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 检查更新按钮与高级源配置
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: updateProv.isChecking
                            ? null
                            : () async {
                                final hasNew = await updateProv.checkUpdate();
                                if (!context.mounted) return;
                                if (hasNew) {
                                  UpdateDialogHelper.showUpdateInfoDialog(context);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          updateProv.statusMessage ?? '当前已是最新版本'),
                                      backgroundColor: updateProv.errorMessage != null
                                          ? AppColors.errorRed
                                          : AppColors.successGreen,
                                    ),
                                  );
                                }
                              },
                        icon: updateProv.isChecking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.sync_rounded, size: 18),
                        label: Text(
                            updateProv.isChecking ? '正在查询最新版本...' : '检查新版本'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.outlined(
                      icon: const Icon(Icons.tune_rounded, size: 20),
                      tooltip: '配置 Gitea 软件包更新源地址',
                      onPressed: () => _showGiteaConfigDialog(context, updateProv),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showGiteaConfigDialog(BuildContext context, UpdateProvider updateProv) {
    final controller = TextEditingController(text: updateProv.giteaUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('配置 Gitea 更新源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '可根据当前处于局域网或公网环境，指定 Gitea 服务的基础访问地址：',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Gitea 服务地址',
                hintText: '如 http://192.168.1.100:3000',
                prefixIcon: Icon(Icons.link_rounded),
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
            onPressed: () async {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                await updateProv.updateGiteaConfig(giteaUrl: newUrl);
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已更新 Gitea 软件包更新源地址')),
                  );
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 重新生成 Token 确认对话框
  // ===========================================================================
  Future<void> _confirmRegenerateToken(ConnectionProvider conn) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.warningOrange),
            SizedBox(width: 8),
            Text('确认重新生成安全令牌？'),
          ],
        ),
        content: const Text(
          '重新生成后，旧的安全令牌 (Master Token) 将立即永久失效！\n\n'
          '系统将把新令牌保存至服务端，并自动在客户端更新并使用新令牌重新建立连接。是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warningOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('立即生成并重连'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await conn.regenerateTokenAndReconnect();
      if (mounted) {
        if (success) {
          setState(() {
            _tokenController.text = conn.token;
            _historyPresets = StorageService.getConnectionHistory();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 安全令牌已成功重新生成，客户端已自动建立新连接！'),
              backgroundColor: AppColors.successGreen,
            ),
          );
          _reloadAllBusinessData(context, conn);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(conn.errorMessage ?? '重新生成令牌失败'),
              backgroundColor: AppColors.errorRed,
            ),
          );
        }
      }
    }
  }

  // ===========================================================================
  // 二级页面 2：用户与权限管理 (Users & Permissions)
  // ===========================================================================
  Widget _buildUserManagementSectionContent(
    BuildContext context,
    ConnectionProvider conn,
  ) {
    final userProv = Provider.of<UserProvider?>(context);
    if (userProv == null) {
      return const SizedBox.shrink();
    }
    final isDark = context.isDark;
    final activeAccent = isDark ? AppColors.accentCyan : AppColors.primaryBlue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部当前权限卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final isCompact = constraints.maxWidth < 480;
                final content = Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (conn.isAdmin ? AppColors.primaryBlue : Colors.grey).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        conn.isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                        color: conn.isAdmin ? activeAccent : Colors.grey,
                        size: 24,
                      ),
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
                                  conn.currentUser?.username.isNotEmpty == true
                                      ? conn.currentUser!.username
                                      : (conn.isAdmin ? 'Master 管理员' : '当前用户'),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (conn.isAdmin ? AppColors.primaryBlue : Colors.grey).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  conn.isAdmin ? '管理员 (ADMIN)' : '普通用户 (USER)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: conn.isAdmin ? activeAccent : Colors.grey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            conn.isAdmin
                                ? '您具备系统最高管理权限，可创建新账号并分配角色。'
                                : '当前为受限普通用户，仅限管理员操作用户与权限分配。',
                            style: TextStyle(fontSize: 12, color: context.subtextColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                if (!conn.isAdmin) return content;

                final actions = Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 19),
                      tooltip: '复制当前 Master 的 MCP 配置',
                      onPressed: () => _showUserMcpConfigDialog(
                        context,
                        username: conn.currentUser?.username.isNotEmpty == true
                            ? conn.currentUser!.username
                            : 'Master 管理员',
                        roleLabel: '管理员 (Master)',
                        token: conn.token,
                        conn: conn,
                        isMaster: true,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.vpn_key_rounded, size: 19),
                      tooltip: '重新生成 Master Token',
                      onPressed: () => _showRegenerateMasterTokenDialog(context, conn),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: '刷新用户列表',
                      onPressed: () => userProv.loadUsers(),
                    ),
                    FilledButton.icon(
                      onPressed: () => _showCreateUserDialog(context, userProv),
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                      label: const Text('新建用户'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      content,
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerRight, child: actions),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: content),
                    const SizedBox(width: 8),
                    actions,
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 用户统计条
        if (conn.isAdmin) ...[
          Row(
            children: [
              _buildCountBadge(
                label: '管理员',
                count: userProv.adminCount,
                color: activeAccent,
                icon: Icons.shield_outlined,
              ),
              const SizedBox(width: 12),
              _buildCountBadge(
                label: '普通用户',
                count: userProv.normalUserCount,
                color: Colors.teal,
                icon: Icons.person_outline_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // 用户列表
        if (!conn.isAdmin)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Center(
              child: Text(
                '如需管理系统用户或重置角色，请使用 Master Token 或管理员账号连接 NAS 服务。',
                style: TextStyle(color: context.subtextColor, fontSize: 13),
              ),
            ),
          )
        else if (userProv.isLoading && userProv.users.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40.0),
              child: CircularProgressIndicator(),
            ),
          )
        else if (userProv.users.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.group_off_rounded, size: 48, color: context.tertiaryTextColor),
                    const SizedBox(height: 12),
                    Text(
                      '暂无配置的用户账号',
                      style: TextStyle(fontSize: 14, color: context.subtextColor),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '点击右上角「新建用户」即可添加管理员或普通用户',
                      style: TextStyle(fontSize: 12, color: context.tertiaryTextColor),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (ctx, constraints) {
              final isCompact = constraints.maxWidth < 500;
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: userProv.users.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, index) {
                  final user = userProv.users[index];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: user.isAdmin
                            ? AppColors.primaryBlue.withOpacity(0.18)
                            : Colors.teal.withOpacity(0.18),
                        child: Icon(
                          user.isAdmin ? Icons.shield_rounded : Icons.person_rounded,
                          color: user.isAdmin ? activeAccent : Colors.teal,
                          size: 20,
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: user.isAdmin
                                  ? AppColors.primaryBlue.withOpacity(0.15)
                                  : Colors.teal.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              user.role.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: user.isAdmin ? activeAccent : Colors.teal,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (user.token != null && user.token!.isNotEmpty)
                              Text(
                                '专属 Token: ${user.token!.substring(0, user.token!.length > 12 ? 12 : user.token!.length)}••••',
                                style: TextStyle(fontSize: 11, color: context.subtextColor),
                              ),
                            if (user.createdAt.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  '创建时间: ${user.createdAt.split('T').first}',
                                  style: TextStyle(fontSize: 11, color: context.tertiaryTextColor),
                                ),
                              ),
                          ],
                        ),
                      ),
                      trailing: isCompact
                          ? PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, size: 20),
                              tooltip: '更多操作',
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              onSelected: (value) {
                                switch (value) {
                                  case 'copy_mcp':
                                    _showUserMcpConfigDialog(
                                      context,
                                      username: user.username,
                                      roleLabel: user.role.label,
                                      token: user.token ?? '',
                                      conn: conn,
                                    );
                                    break;
                                  case 'regen_token':
                                    _showRegenerateUserTokenDialog(
                                      context,
                                      userProv: userProv,
                                      user: user,
                                      conn: conn,
                                    );
                                    break;
                                  case 'edit':
                                    _showEditUserDialog(context, userProv, user);
                                    break;
                                  case 'delete':
                                    _showDeleteUserDialog(context, userProv, user);
                                    break;
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'copy_mcp',
                                  child: Row(
                                    children: [
                                      Icon(Icons.copy_rounded, size: 18),
                                      SizedBox(width: 10),
                                      Text('复制 MCP 配置', style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'regen_token',
                                  child: Row(
                                    children: [
                                      Icon(Icons.vpn_key_rounded, size: 18),
                                      SizedBox(width: 10),
                                      Text('重新生成 Token', style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 18),
                                      SizedBox(width: 10),
                                      Text('修改密码或权限', style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.errorRed),
                                      SizedBox(width: 10),
                                      Text('删除用户', style: TextStyle(fontSize: 13, color: AppColors.errorRed)),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.copy_rounded, size: 18),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  tooltip: '复制 MCP 配置',
                                  onPressed: () => _showUserMcpConfigDialog(
                                    context,
                                    username: user.username,
                                    roleLabel: user.role.label,
                                    token: user.token ?? '',
                                    conn: conn,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.vpn_key_rounded, size: 18),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  tooltip: '重新生成 Token',
                                  onPressed: () => _showRegenerateUserTokenDialog(
                                    context,
                                    userProv: userProv,
                                    user: user,
                                    conn: conn,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  tooltip: '修改密码或权限',
                                  onPressed: () => _showEditUserDialog(context, userProv, user),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.errorRed),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  tooltip: '删除用户',
                                  onPressed: () => _showDeleteUserDialog(context, userProv, user),
                                ),
                              ],
                            ),
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }

  Widget _buildCountBadge({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 12, color: context.subtextColor)),
            const Spacer(),
            Text(
              '$count',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateUserDialog(BuildContext context, UserProvider userProv) {
    final formKey = GlobalKey<FormState>();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    UserRole selectedRole = UserRole.user;
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.person_add_rounded, color: AppColors.primaryBlue),
              SizedBox(width: 8),
              Text('新建系统用户'),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      hintText: '输入字母、数字或下划线',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? '请输入用户名' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: passwordCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: '初始密码',
                      hintText: '不少于 6 位',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                        onPressed: () => setDialogState(() => obscure = !obscure),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return '请输入初始密码';
                      if (v.trim().length < 6) return '密码不能少于 6 位';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('分配角色权限:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<UserRole>(
                    segments: const [
                      ButtonSegment(
                        value: UserRole.user,
                        label: Text('普通用户'),
                        icon: Icon(Icons.person_rounded, size: 14),
                      ),
                      ButtonSegment(
                        value: UserRole.admin,
                        label: Text('系统管理员'),
                        icon: Icon(Icons.shield_rounded, size: 14),
                      ),
                    ],
                    selected: {selectedRole},
                    onSelectionChanged: (val) => setDialogState(() => selectedRole = val.first),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    selectedRole == UserRole.admin
                        ? '管理员拥有系统全部控制权（可管理用户、修改系统配置与白名单、彻底删除文件等）。'
                        : '普通用户可正常进行文件检索、下载、创建任务与使用常规 MCP 工具，无法修改系统配置与用户。',
                    style: TextStyle(fontSize: 11, color: context.subtextColor),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final ok = await userProv.createUser(
                  username: usernameCtrl.text.trim(),
                  password: passwordCtrl.text.trim(),
                  role: selectedRole.value,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  if (ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('🎉 用户「${usernameCtrl.text.trim()}」创建成功！'),
                        backgroundColor: AppColors.successGreen,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(userProv.errorMessage ?? '创建用户失败'),
                        backgroundColor: AppColors.errorRed,
                      ),
                    );
                  }
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditUserDialog(BuildContext context, UserProvider userProv, UserModel user) {
    final formKey = GlobalKey<FormState>();
    final passwordCtrl = TextEditingController();
    UserRole selectedRole = user.role;
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.manage_accounts_rounded, color: AppColors.primaryBlue),
              const SizedBox(width: 8),
              Text('编辑用户: ${user.username}'),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: passwordCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: '新密码 (留空则不修改)',
                      hintText: '输入新密码（至少6位）',
                      prefixIcon: const Icon(Icons.lock_reset_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                        onPressed: () => setDialogState(() => obscure = !obscure),
                      ),
                    ),
                    validator: (v) {
                      if (v != null && v.isNotEmpty && v.length < 6) {
                        return '密码不能少于 6 位';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('变更角色权限:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<UserRole>(
                    segments: const [
                      ButtonSegment(
                        value: UserRole.user,
                        label: Text('普通用户'),
                        icon: Icon(Icons.person_rounded, size: 14),
                      ),
                      ButtonSegment(
                        value: UserRole.admin,
                        label: Text('系统管理员'),
                        icon: Icon(Icons.shield_rounded, size: 14),
                      ),
                    ],
                    selected: {selectedRole},
                    onSelectionChanged: (val) => setDialogState(() => selectedRole = val.first),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final pass = passwordCtrl.text.trim();
                final ok = await userProv.updateUser(
                  user.id,
                  password: pass.isNotEmpty ? pass : null,
                  role: selectedRole.value,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  if (ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已更新用户「${user.username}」的配置'),
                        backgroundColor: AppColors.successGreen,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(userProv.errorMessage ?? '更新用户失败'),
                        backgroundColor: AppColors.errorRed,
                      ),
                    );
                  }
                }
              },
              child: const Text('保存修改'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteUserDialog(BuildContext context, UserProvider userProv, UserModel user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppColors.errorRed),
            SizedBox(width: 8),
            Text('确认删除用户？'),
          ],
        ),
        content: Text('确定要永久删除用户「${user.username}」吗？\n删除后该用户将无法再访问 Nasio 服务。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await userProv.deleteUser(user.id);
              if (context.mounted) {
                if (ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已删除用户「${user.username}」'),
                      backgroundColor: AppColors.successGreen,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(userProv.errorMessage ?? '删除用户失败'),
                      backgroundColor: AppColors.errorRed,
                    ),
                  );
                }
              }
            },
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
  }

  void _showUserMcpConfigDialog(
    BuildContext context, {
    required String username,
    required String roleLabel,
    required String token,
    required ConnectionProvider conn,
    bool isMaster = false,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _UserMcpConfigDialogWidget(
        username: username,
        roleLabel: roleLabel,
        token: token,
        conn: conn,
        isMaster: isMaster,
      ),
    );
  }

  void _showRegenerateUserTokenDialog(
    BuildContext context, {
    required UserProvider userProv,
    required UserModel user,
    required ConnectionProvider conn,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('重新生成 Token？'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要为用户「${user.username}」重新生成专属访问 Token 吗？'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '注意：旧 Token 将立即作废失效，该用户当前已配置的 MCP 或外部客户端需重新更新 Token 方可连接。',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final newToken = await userProv.regenerateUserToken(user.id);
              if (context.mounted) {
                if (newToken != null && newToken.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已为用户「${user.username}」重新生成 Token'),
                      backgroundColor: AppColors.successGreen,
                    ),
                  );
                  _showUserMcpConfigDialog(
                    context,
                    username: user.username,
                    roleLabel: user.role.label,
                    token: newToken,
                    conn: conn,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(userProv.errorMessage ?? '重新生成 Token 失败'),
                      backgroundColor: AppColors.errorRed,
                    ),
                  );
                }
              }
            },
            child: const Text('确认重新生成'),
          ),
        ],
      ),
    );
  }

  void _showRegenerateMasterTokenDialog(
    BuildContext context,
    ConnectionProvider conn,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.errorRed),
            SizedBox(width: 8),
            Text('重新生成 Master Token？'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('确定要重新生成服务端的全局 Master Token 吗？'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.errorRed.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.error_outline, size: 18, color: AppColors.errorRed),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '高危提示：重新生成后，服务端全局 Master Token 将被重写，当前已连接的所有 MCP 智能体和管理员客户端将立即断开，需重新配置新 Token。',
                      style: TextStyle(fontSize: 12, color: AppColors.errorRed),
                    ),
                  ),
                ],
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
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await conn.regenerateTokenAndReconnect();
              if (context.mounted) {
                if (success && conn.token.isNotEmpty) {
                  _reloadAllBusinessData(context, conn);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已重新生成 Master Token 并完成重连'),
                      backgroundColor: AppColors.successGreen,
                    ),
                  );
                  _showUserMcpConfigDialog(
                    context,
                    username: conn.currentUser?.username.isNotEmpty == true
                        ? conn.currentUser!.username
                        : 'Master 管理员',
                    roleLabel: '管理员 (Master)',
                    token: conn.token,
                    conn: conn,
                    isMaster: true,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(conn.errorMessage ?? '重新生成 Master Token 失败'),
                      backgroundColor: AppColors.errorRed,
                    ),
                  );
                }
              }
            },
            child: const Text('确认生成'),
          ),
        ],
      ),
    );
  }
}

class _UserMcpConfigDialogWidget extends StatefulWidget {
  final String username;
  final String roleLabel;
  final String token;
  final ConnectionProvider conn;
  final bool isMaster;

  const _UserMcpConfigDialogWidget({
    required this.username,
    required this.roleLabel,
    required this.token,
    required this.conn,
    this.isMaster = false,
  });

  @override
  State<_UserMcpConfigDialogWidget> createState() => _UserMcpConfigDialogWidgetState();
}

class _UserMcpConfigDialogWidgetState extends State<_UserMcpConfigDialogWidget> {
  int _selectedClientIndex = 0;
  bool _revealToken = false;

  final List<({String title, String desc, IconData icon})> _clients = [
    (title: 'Antigravity', desc: 'Google Antigravity / Gemini CLI 配置', icon: Icons.auto_awesome_rounded),
    (title: 'Claude Desktop', desc: 'Anthropic Claude Desktop (mcp-remote)', icon: Icons.terminal_rounded),
    (title: 'Cursor / Windsurf', desc: 'Cursor & Windsurf AI 代码编辑器', icon: Icons.code_rounded),
    (title: '通用 SSE URL', desc: 'Dify、n8n、FastGPT 等工作流平台', icon: Icons.link_rounded),
  ];

  int get _effectivePort => widget.conn.port == 8086 ? 8000 : widget.conn.port;

  String _getConfigContent() {
    final host = widget.conn.host;
    final port = _effectivePort;
    final isHttps = widget.conn.isHttps;
    final token = widget.token;

    switch (_selectedClientIndex) {
      case 0:
        return McpConfigGenerator.generateAntigravityJson(
          host: host,
          port: port,
          isHttps: isHttps,
          token: token,
          transport: McpTransportMode.sse,
        );
      case 1:
        return McpConfigGenerator.generateClaudeDesktopJson(
          host: host,
          port: port,
          isHttps: isHttps,
          token: token,
          transport: McpTransportMode.sse,
        );
      case 2:
        return McpConfigGenerator.generateCursorJson(
          host: host,
          port: port,
          isHttps: isHttps,
          token: token,
          transport: McpTransportMode.sse,
        );
      case 3:
      default:
        return McpConfigGenerator.buildEndpointUrl(
          host: host,
          port: port,
          isHttps: isHttps,
          transport: McpTransportMode.sse,
          token: token,
          includeQueryToken: true,
        );
    }
  }

  Future<void> _copyText(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 $label 到剪贴板'),
        backgroundColor: AppColors.successGreen,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final codeContent = _getConfigContent();
    final client = _clients[_selectedClientIndex];

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.hub_rounded, color: AppColors.primaryBlue, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '「${widget.username}」MCP 配置',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (widget.isMaster ? AppColors.primaryBlue : Colors.teal).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.roleLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: widget.isMaster ? AppColors.primaryBlue : Colors.teal,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '根据当前 NAS 地址 (${widget.conn.host}:$_effectivePort) 动态生成专属配置',
                  style: TextStyle(fontSize: 11, color: context.subtextColor),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.key_rounded, size: 16, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: '专属 Token: ',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            TextSpan(
                              text: widget.token.isEmpty
                                  ? '(未生成或为空)'
                                  : (_revealToken
                                      ? widget.token
                                      : McpConfigGenerator.maskToken(widget.token, mask: true)),
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _revealToken ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 16,
                      ),
                      tooltip: _revealToken ? '隐藏 Token' : '显示完整 Token',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                      onPressed: () => setState(() => _revealToken = !_revealToken),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      tooltip: '复制纯 Token',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                      onPressed: () => _copyText(widget.token, 'Token 凭据'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_clients.length, (i) {
                  final isSelected = _selectedClientIndex == i;
                  final item = _clients[i];
                  return ChoiceChip(
                    avatar: Icon(
                      item.icon,
                      size: 16,
                      color: isSelected ? Colors.white : context.subtextColor,
                    ),
                    label: Text(item.title),
                    selected: isSelected,
                    selectedColor: AppColors.primaryBlue,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : null,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _selectedClientIndex = i);
                    },
                  );
                }),
              ),
              const SizedBox(height: 12),
              Text(
                '• 格式：${client.desc}',
                style: TextStyle(fontSize: 12, color: context.subtextColor),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 240),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFF282C34),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 14, 48, 14),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SelectableText(
                          codeContent,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Color(0xFF98C379),
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.white70),
                        tooltip: '复制此配置',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _copyText(codeContent, '${client.title} 配置'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: () => _copyText(codeContent, '${client.title} 配置'),
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: Text('一键复制 ${client.title} 配置'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
