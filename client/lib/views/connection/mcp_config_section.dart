import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/connection_provider.dart';
import '../../services/storage_service.dart';
import '../../models/skill_model.dart';

/// 支持区分的 AI Agent 集成类型
enum McpAgentType {
  antigravity(
    id: 'antigravity',
    title: 'Antigravity / Gemini CLI',
    shortTitle: 'Antigravity',
    subtitle: 'Google Antigravity IDE 及 Gemini CLI 智能体配置',
    icon: Icons.auto_awesome_rounded,
  ),
  claude(
    id: 'claude',
    title: 'Claude Desktop / Claude Code',
    shortTitle: 'Claude',
    subtitle: 'Anthropic Claude 桌面端 (mcp-remote) 与 CLI 一键命令',
    icon: Icons.terminal_rounded,
  ),
  cursorWindsurf(
    id: 'cursor_windsurf',
    title: 'Cursor / Windsurf',
    shortTitle: 'Cursor / Windsurf',
    subtitle: 'AI 代码编辑器全局或项目级 MCP 配置文件',
    icon: Icons.code_rounded,
  ),
  cherryStudio(
    id: 'cherry_studio',
    title: 'Cherry Studio',
    shortTitle: 'Cherry Studio',
    subtitle: '桌面 GUI 智能体客户端表单分项复制与 JSON 导入',
    icon: Icons.chat_bubble_outline_rounded,
  ),
  difyGeneric(
    id: 'dify_generic',
    title: 'Dify / 通用端点',
    shortTitle: 'Dify / 通用',
    subtitle: '适配 Dify 工作流、n8n、NextChat 等平台的 SSE 与 HTTP 端点',
    icon: Icons.hub_outlined,
  );

  final String id;
  final String title;
  final String shortTitle;
  final String subtitle;
  final IconData icon;

  const McpAgentType({
    required this.id,
    required this.title,
    required this.shortTitle,
    required this.subtitle,
    required this.icon,
  });
}

/// MCP 传输协议模式
enum McpTransportMode {
  sse('SSE 协议 (/sse)', '兼容性最佳，支持 Query Token 与 Header 双模鉴权'),
  streamableHttp('Streamable HTTP (/mcp)', '新一代标准流式 HTTP 协议端点');

  final String label;
  final String description;
  const McpTransportMode(this.label, this.description);
}

/// MCP 工具分类元数据
class McpToolCategory {
  final String title;
  final IconData icon;
  final List<McpToolInfo> tools;

  const McpToolCategory({
    required this.title,
    required this.icon,
    required this.tools,
  });
}

class McpToolInfo {
  final String name;
  final String description;
  final bool isAsync;

  const McpToolInfo({
    required this.name,
    required this.description,
    this.isAsync = false,
  });
}

/// MCP 配置生成辅助工具类（支持单元测试与复现）
class McpConfigGenerator {
  static String maskToken(String token, {bool mask = false}) {
    if (token.isEmpty) return '';
    if (!mask) return token;
    if (token.length <= 8) return '••••••••';
    return '${token.substring(0, 4)}••••••••${token.substring(token.length - 4)}';
  }

  static String buildAuthHeader({
    required AuthType authType,
    required String token,
    String username = '',
    String password = '',
  }) {
    if (authType == AuthType.credentials) {
      if (username.isNotEmpty && password.isNotEmpty) {
        final creds = base64Encode(utf8.encode('$username:$password'));
        return 'Basic $creds';
      }
    }
    if (token.trim().isNotEmpty) {
      return 'Bearer ${token.trim()}';
    }
    return '';
  }

  static String buildBaseUrl({
    required String host,
    required int port,
    required bool isHttps,
  }) {
    final cleanHost = host.trim().isEmpty ? '127.0.0.1' : host.trim();
    final scheme = isHttps ? 'https' : 'http';
    final isDefaultPort = (isHttps && port == 443) || (!isHttps && port == 80);
    return isDefaultPort ? '$scheme://$cleanHost' : '$scheme://$cleanHost:$port';
  }

  static String buildEndpointUrl({
    required String host,
    required int port,
    required bool isHttps,
    required McpTransportMode transport,
    required String token,
    bool includeQueryToken = true,
    AuthType authType = AuthType.token,
  }) {
    final base = buildBaseUrl(host: host, port: port, isHttps: isHttps);
    final path = transport == McpTransportMode.sse ? '/sse' : '/mcp';
    final cleanToken = token.trim();
    if (authType == AuthType.token && includeQueryToken && cleanToken.isNotEmpty) {
      return '$base$path?token=$cleanToken';
    }
    return '$base$path';
  }

  static String generateAntigravityJson({
    required String host,
    required int port,
    required bool isHttps,
    required String token,
    required McpTransportMode transport,
    AuthType authType = AuthType.token,
    String username = '',
    String password = '',
  }) {
    final url = buildEndpointUrl(
      host: host,
      port: port,
      isHttps: isHttps,
      transport: transport,
      token: token,
      includeQueryToken: authType == AuthType.token,
      authType: authType,
    );
    final authHeader = buildAuthHeader(
      authType: authType,
      token: token,
      username: username,
      password: password,
    );
    final map = <String, dynamic>{
      'mcpServers': {
        'nasio': {
          'serverUrl': url,
          if (authHeader.isNotEmpty)
            'headers': {
              'Authorization': authHeader,
            },
        },
      },
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static String generateClaudeDesktopJson({
    required String host,
    required int port,
    required bool isHttps,
    required String token,
    required McpTransportMode transport,
    AuthType authType = AuthType.token,
    String username = '',
    String password = '',
  }) {
    final url = buildEndpointUrl(
      host: host,
      port: port,
      isHttps: isHttps,
      transport: transport,
      token: token,
      includeQueryToken: false,
      authType: authType,
    );
    final authHeader = buildAuthHeader(
      authType: authType,
      token: token,
      username: username,
      password: password,
    );
    final args = <String>[
      '-y',
      'mcp-remote',
      url,
      if (authHeader.isNotEmpty) ...[
        '--header',
        'Authorization: $authHeader',
      ],
    ];
    final map = <String, dynamic>{
      'mcpServers': {
        'nasio': {
          'command': 'npx',
          'args': args,
        },
      },
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static String generateClaudeCodeCliCommand({
    required String host,
    required int port,
    required bool isHttps,
    required String token,
    required McpTransportMode transport,
    AuthType authType = AuthType.token,
    String username = '',
    String password = '',
  }) {
    final url = buildEndpointUrl(
      host: host,
      port: port,
      isHttps: isHttps,
      transport: transport,
      token: token,
      includeQueryToken: authType == AuthType.token,
      authType: authType,
    );
    final transportFlag = transport == McpTransportMode.sse ? 'sse' : 'http';
    final authHeader = buildAuthHeader(
      authType: authType,
      token: token,
      username: username,
      password: password,
    );
    if (authHeader.isNotEmpty) {
      return 'claude mcp add --transport $transportFlag Nasio "$url" --header "Authorization: $authHeader"';
    }
    return 'claude mcp add --transport $transportFlag Nasio "$url"';
  }

  static String generateCursorJson({
    required String host,
    required int port,
    required bool isHttps,
    required String token,
    required McpTransportMode transport,
    AuthType authType = AuthType.token,
    String username = '',
    String password = '',
  }) {
    final url = buildEndpointUrl(
      host: host,
      port: port,
      isHttps: isHttps,
      transport: transport,
      token: token,
      includeQueryToken: authType == AuthType.token,
      authType: authType,
    );
    final authHeader = buildAuthHeader(
      authType: authType,
      token: token,
      username: username,
      password: password,
    );
    final map = <String, dynamic>{
      'mcpServers': {
        'nasio': {
          'url': url,
          if (authHeader.isNotEmpty)
            'headers': {
              'Authorization': authHeader,
            },
        },
      },
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static String generateWindsurfJson({
    required String host,
    required int port,
    required bool isHttps,
    required String token,
    required McpTransportMode transport,
    AuthType authType = AuthType.token,
    String username = '',
    String password = '',
  }) {
    return generateAntigravityJson(
      host: host,
      port: port,
      isHttps: isHttps,
      token: token,
      transport: transport,
      authType: authType,
      username: username,
      password: password,
    );
  }

  static String generateCherryStudioJson({
    required String host,
    required int port,
    required bool isHttps,
    required String token,
    required McpTransportMode transport,
    AuthType authType = AuthType.token,
    String username = '',
    String password = '',
  }) {
    final url = buildEndpointUrl(
      host: host,
      port: port,
      isHttps: isHttps,
      transport: transport,
      token: token,
      includeQueryToken: authType == AuthType.token,
      authType: authType,
    );
    final authHeader = buildAuthHeader(
      authType: authType,
      token: token,
      username: username,
      password: password,
    );
    final map = <String, dynamic>{
      'mcpServers': {
        'nasio': {
          'name': 'Nasio (绿联 NAS 智能中枢)',
          'type': transport == McpTransportMode.sse ? 'sse' : 'streamableHttp',
          'baseUrl': url,
          if (authHeader.isNotEmpty)
            'headers': {
              'Authorization': authHeader,
            },
        },
      },
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static String generateBootstrappingPrompt({
    required McpAgentType agent,
    required String host,
    required int port,
    required bool isHttps,
    required String token,
    required McpTransportMode transport,
    required List<SkillModel> skills,
    AuthType authType = AuthType.token,
    String username = '',
    String password = '',
  }) {
    final buffer = StringBuffer();
    final baseUrl = buildBaseUrl(host: host, port: port, isHttps: isHttps);
    final endpointUrl = buildEndpointUrl(
      host: host,
      port: port,
      isHttps: isHttps,
      transport: transport,
      token: token,
      includeQueryToken: authType == AuthType.token,
      authType: authType,
    );
    final authHeader = buildAuthHeader(
      authType: authType,
      token: token,
      username: username,
      password: password,
    );

    buffer.writeln('# 🚀 Nasio 智能中枢与工作流规范自举指令 (${agent.shortTitle})\n');
    buffer.writeln('请按照以下说明，在当前环境中初始化与我的私有 NAS (Nasio) 的深度集成，并安装指定的业务工作流规范（Skills）：\n');

    // 1. MCP 配置
    buffer.writeln('---');
    buffer.writeln('## 第一步：配置 Nasio MCP 服务端');
    buffer.writeln('- **基准地址**: `$baseUrl`');
    buffer.writeln('- **端点 URL**: `$endpointUrl`');
    if (authHeader.isNotEmpty) {
      buffer.writeln('- **认证头 (Header)**: `$authHeader`');
    }
    buffer.writeln();

    if (agent == McpAgentType.antigravity) {
      final configJson = generateAntigravityJson(
        host: host,
        port: port,
        isHttps: isHttps,
        token: token,
        transport: transport,
        authType: authType,
        username: username,
        password: password,
      );
      buffer.writeln('请在当前系统的 Antigravity / Gemini CLI MCP 配置文件中（全局 `~/.gemini/config/mcp_config.json` 或项目级 `.agents/mcp_config.json`），添加或合并以下 `Nasio` 服务配置：');
      buffer.writeln('```json');
      buffer.writeln(configJson);
      buffer.writeln('```\n');
    } else if (agent == McpAgentType.claude) {
      final cliCmd = generateClaudeCodeCliCommand(
        host: host,
        port: port,
        isHttps: isHttps,
        token: token,
        transport: transport,
        authType: authType,
        username: username,
        password: password,
      );
      final desktopJson = generateClaudeDesktopJson(
        host: host,
        port: port,
        isHttps: isHttps,
        token: token,
        transport: transport,
        authType: authType,
        username: username,
        password: password,
      );
      buffer.writeln('若使用 **Claude Code (CLI)**，请直接在终端执行注册命令：');
      buffer.writeln('```bash');
      buffer.writeln(cliCmd);
      buffer.writeln('```\n');
      buffer.writeln('若使用 **Claude Desktop (桌面端)**，请将以下内容合并至 `claude_desktop_config.json`：');
      buffer.writeln('```json');
      buffer.writeln(desktopJson);
      buffer.writeln('```\n');
    } else if (agent == McpAgentType.cursorWindsurf) {
      final cursorJson = generateCursorJson(
        host: host,
        port: port,
        isHttps: isHttps,
        token: token,
        transport: transport,
        authType: authType,
        username: username,
        password: password,
      );
      buffer.writeln('请在 `.cursor/mcp.json`（或 Windsurf 全局/项目级 MCP 设置）中添加以下配置：');
      buffer.writeln('```json');
      buffer.writeln(cursorJson);
      buffer.writeln('```\n');
    } else {
      buffer.writeln('请在你的 Agent 客户端中配置 MCP 协议端点指向 `$endpointUrl`，并带上相应认证信息。\n');
    }

    // 2. 技能文件安装
    buffer.writeln('---');
    buffer.writeln('## 第二步：安装工作流技能规范 (Skills)');
    if (skills.isEmpty) {
      buffer.writeln('当前服务端暂无预选技能。Nasio MCP 服务端已内置技能中心，你可以随时调用 MCP 工具 `list_skills` 查阅或调用 `get_skill(name)` 获取最新规范。\n');
    } else {
      buffer.writeln('请利用你的本地文件读写工具（例如 write_to_file 或终端脚本），在技能目录下分别创建并写入以下 ${skills.length} 项工作流技能文件：\n');

      for (int i = 0; i < skills.length; i++) {
        final skill = skills[i];
        final skillName = skill.name;
        String skillPath;
        if (agent == McpAgentType.antigravity) {
          skillPath = '~/.gemini/config/skills/$skillName/SKILL.md';
        } else if (agent == McpAgentType.claude) {
          skillPath = '.claude/skills/$skillName/SKILL.md';
        } else {
          skillPath = '.agents/skills/$skillName/SKILL.md';
        }

        buffer.writeln('### ${i + 1}. 技能: `${skill.name}`');
        buffer.writeln('- **功能说明**: ${skill.description}');
        if (skill.tags.isNotEmpty) {
          buffer.writeln('- **标签**: ${skill.tags.join(', ')}');
        }
        buffer.writeln('- **建议安装路径**: `$skillPath`');
        buffer.writeln('- **完整文件内容 (`SKILL.md`)**:');
        buffer.writeln('````markdown');
        final rawContent = (skill.content != null && skill.content!.trim().isNotEmpty)
            ? skill.content!.trim()
            : '---\nname: $skillName\ndescription: ${skill.description}\n---\n\n# ${skill.name}\n';
        buffer.writeln(rawContent);
        buffer.writeln('````\n');
      }
    }

    // 3. 校验与执行准则
    buffer.writeln('---');
    buffer.writeln('## 第三步：连通性自检与日常执行准则');
    buffer.writeln('1. **连通自检**: 请调用 MCP 工具 `get_system_status` 或 `list_skills`，确认能正常与 Nasio 通信。');
    buffer.writeln('2. **规范执行**: 当接收到涉及私有 NAS 存储管理、下载调度或对应业务需求时，请严格遵守已安装的各 `SKILL.md` 操作标准。');
    buffer.writeln('3. **经验回流**: 在任务执行中提炼了新 SOP 或沉淀了新能力时，可主动调用 MCP 工具 `sync_skill` 将新技能同步回 Nasio 服务端！\n');

    return buffer.toString();
  }

  static const List<McpToolCategory> toolCategories = [
    McpToolCategory(
      title: '系统与运维 (3 项)',
      icon: Icons.dns_outlined,
      tools: [
        McpToolInfo(
          name: 'get_system_status',
          description: '获取允许访问存储池的磁盘可用空间、使用率及系统当前活跃任务数',
        ),
        McpToolInfo(
          name: 'get_mcp_config',
          description: '查看当前运行配置（目录白名单、回收站路径及外部下载器接入状态）',
        ),
        McpToolInfo(
          name: 'test_downloader_connection',
          description: '诊断外部下载器 (qBittorrent / aria2) 连通性与健康状态',
        ),
      ],
    ),
    McpToolCategory(
      title: '智能体协同生命周期 (5 项)',
      icon: Icons.smart_toy_outlined,
      tools: [
        McpToolInfo(
          name: 'start_agent_task',
          description: '初始化多步复合长任务并返回唯一 agent_task_id 供监控大屏追踪',
        ),
        McpToolInfo(
          name: 'report_agent_task_step',
          description: '实时汇报复合长任务当前步骤执行状态、进度百分比与时间轴日志',
        ),
        McpToolInfo(
          name: 'complete_agent_task',
          description: '完成并归档长任务，沉淀标准化可复现的 Prompt 模板',
        ),
        McpToolInfo(
          name: 'fail_agent_task',
          description: '标记复合长任务遭遇不可逆异常失败并记录原因',
        ),
        McpToolInfo(
          name: 'report_missing_mcp_tool',
          description: '当缺少底层业务支撑工具时，主动上报缺失的 MCP 接口诉求',
        ),
      ],
    ),
    McpToolCategory(
      title: '混合下载与异步任务管控 (3 项)',
      icon: Icons.download_outlined,
      tools: [
        McpToolInfo(
          name: 'create_download_task',
          description: '统一创建直链、网页流媒体 (yt-dlp) 或磁力链 (qB/aria2) 下载任务',
          isAsync: true,
        ),
        McpToolInfo(
          name: 'get_task_status',
          description: '依据 task_id 查询后台下载、解压或查重任务的实时进度与速率',
        ),
        McpToolInfo(
          name: 'cancel_task',
          description: '中断并取消正在执行中的后台异步任务',
        ),
      ],
    ),
    McpToolCategory(
      title: '文件检索与深度元数据 (3 项)',
      icon: Icons.manage_search_rounded,
      tools: [
        McpToolInfo(
          name: 'search_files',
          description: '支持按文件名正则、扩展名、体积区间与修改时间组合实时检索',
        ),
        McpToolInfo(
          name: 'get_file_metadata',
          description: '深度解析视频分辨率/音轨/字幕、音频 ID3、图片 EXIF 与文档摘要',
        ),
        McpToolInfo(
          name: 'list_directory_tree',
          description: '以轻量树状层级结构快速概览目标目录内容',
        ),
      ],
    ),
    McpToolCategory(
      title: '文件整理与数据治理 (5 项)',
      icon: Icons.folder_special_outlined,
      tools: [
        McpToolInfo(
          name: 'batch_organize_files',
          description: '按扩展名、日期或自定义规则智能分类归档（支持 dry_run 预演）',
        ),
        McpToolInfo(
          name: 'batch_rename_files',
          description: '批量正则表达式替换与模板重命名（支持 dry_run 预演）',
        ),
        McpToolInfo(
          name: 'flatten_directory',
          description: '目录扁平化提取与多层冗余嵌套目录清理（支持 dry_run 预演）',
        ),
        McpToolInfo(
          name: 'find_duplicate_files',
          description: '三级漏斗哈希（体积 -> 首尾 4KB -> 全量 SHA256）极速全盘查重',
          isAsync: true,
        ),
        McpToolInfo(
          name: 'extract_archive',
          description: '解压 zip/rar/7z 压缩包并自动修复 Windows 中文编码乱码',
          isAsync: true,
        ),
      ],
    ),
    McpToolCategory(
      title: '防灾回收站管理 (3 项)',
      icon: Icons.delete_outline_rounded,
      tools: [
        McpToolInfo(
          name: 'safe_delete_files',
          description: '安全软删除文件或目录至 .trash 分区并记录原始路径元数据',
        ),
        McpToolInfo(
          name: 'list_trash_files',
          description: '检索与分页浏览防灾回收站中已删除的文件列表',
        ),
        McpToolInfo(
          name: 'restore_trash_file',
          description: '从回收站一键原路还原文件（若原目录不存在将自动重建）',
        ),
      ],
    ),
    McpToolCategory(
      title: '技能与工作流中心 (3 项)',
      icon: Icons.auto_stories_outlined,
      tools: [
        McpToolInfo(
          name: 'list_skills',
          description: '列出 Nasio 服务端持久化注册的全部 AI Agent 技能与工作流规范清单',
        ),
        McpToolInfo(
          name: 'get_skill',
          description: '获取 Nasio 服务端指定技能的完整 Markdown 指导规范与端到端操作 SOP',
        ),
        McpToolInfo(
          name: 'sync_skill',
          description: '向 Nasio 服务端注册或更新 Agent 技能（原子落盘至 data/skills/<name>/SKILL.md）',
        ),
      ],
    ),
  ];
}

class McpConfigSection extends StatefulWidget {
  const McpConfigSection({super.key});

  @override
  State<McpConfigSection> createState() => _McpConfigSectionState();
}

class _McpConfigSectionState extends State<McpConfigSection> {
  McpAgentType _selectedAgent = McpAgentType.antigravity;
  McpTransportMode _transportMode = McpTransportMode.sse;

  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _tokenController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  AuthType _authType = AuthType.token;
  bool _isHttps = false;
  bool _maskTokenInPreview = false;
  bool _showParamEditor = false;
  bool _showToolsCatalog = false;

  // 端点连通性自检状态
  bool _isTestingEndpoint = false;
  bool? _endpointTestSuccess;
  String? _endpointTestMessage;
  int? _endpointLatencyMs;

  // 记录上次同步的连接配置，当用户在「服务连接」修改并保存时自动同步
  String _lastSyncedConnSignature = '';

  @override
  void initState() {
    super.initState();
    final conn = context.read<ConnectionProvider>();
    // 若当前是通过 Web 控制台 8086 端口访问，默认提供 8000 作为推荐直连 MCP 端口（同时支持一键切换 8086 反代端口）
    final initialPort = conn.port == 8086 ? 8000 : conn.port;
    _hostController = TextEditingController(text: conn.host);
    _portController = TextEditingController(text: initialPort.toString());
    _tokenController = TextEditingController(text: conn.token);
    _authType = conn.authType;
    _usernameController = TextEditingController(text: conn.username.isNotEmpty ? conn.username : 'admin');
    _passwordController = TextEditingController(text: conn.password);
    _isHttps = conn.isHttps;
    _lastSyncedConnSignature = '${conn.host}:${conn.port}:${conn.token}:${conn.isHttps}:${conn.authType.value}:${conn.username}:${conn.password}';
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

  void _syncFromConnectionProviderIfNeeded(ConnectionProvider conn) {
    final sig = '${conn.host}:${conn.port}:${conn.token}:${conn.isHttps}:${conn.authType.value}:${conn.username}:${conn.password}';
    if (sig != _lastSyncedConnSignature) {
      _lastSyncedConnSignature = sig;
      _hostController.text = conn.host;
      _portController.text = (conn.port == 8086 ? 8000 : conn.port).toString();
      _tokenController.text = conn.token;
      _authType = conn.authType;
      _usernameController.text = conn.username.isNotEmpty ? conn.username : 'admin';
      _passwordController.text = conn.password;
      _isHttps = conn.isHttps;
    }
  }

  String get _effectiveHost => _hostController.text.trim().isEmpty
      ? '127.0.0.1'
      : _hostController.text.trim();

  int get _effectivePort => int.tryParse(_portController.text.trim()) ?? 8000;

  String get _realToken => _tokenController.text.trim();

  String get _effectiveUsername => _usernameController.text.trim();

  String get _effectivePassword => _passwordController.text.trim();

  String get _previewToken =>
      McpConfigGenerator.maskToken(_realToken, mask: _maskTokenInPreview);

  Future<void> _copyToClipboard(String text, String label) async {
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

  Future<void> _testMcpEndpoint() async {
    setState(() {
      _isTestingEndpoint = true;
      _endpointTestSuccess = null;
      _endpointTestMessage = null;
      _endpointLatencyMs = null;
    });

    final baseUrl = McpConfigGenerator.buildBaseUrl(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
    );
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 6),
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final sw = Stopwatch()..start();
    try {
      // 1. 探测基础网关健康检查
      final healthRes = await dio.get('/health');
      final latency = sw.elapsedMilliseconds;

      if (healthRes.statusCode != 200) {
        setState(() {
          _isTestingEndpoint = false;
          _endpointTestSuccess = false;
          _endpointTestMessage =
              '网关返回状态码 ${healthRes.statusCode}，请确认端口 $_effectivePort 是否为 Nasio 服务端口';
        });
        return;
      }

      // 2. 校验凭证与配置权限 (支持 Bearer Token 或 HTTP Basic)
      final authHeader = McpConfigGenerator.buildAuthHeader(
        authType: _authType,
        token: _realToken,
        username: _effectiveUsername,
        password: _effectivePassword,
      );
      final headers = <String, dynamic>{
        if (authHeader.isNotEmpty) 'Authorization': authHeader,
      };
      final authRes = await dio.get(
        '/api/v1/config',
        options: Options(headers: headers),
      );

      if (authRes.statusCode == 401) {
        setState(() {
          _isTestingEndpoint = false;
          _endpointTestSuccess = false;
          _endpointLatencyMs = latency;
          _endpointTestMessage = '网络已连通 (${latency}ms)，但凭据鉴权失败 (401)，请核对安全令牌或账号密码';
        });
        return;
      }

      setState(() {
        _isTestingEndpoint = false;
        _endpointTestSuccess = true;
        _endpointLatencyMs = latency;
        _endpointTestMessage =
            'MCP 网关与鉴权校验通过！SSE (/sse) 与 Streamable HTTP (/mcp) 端点就绪';
      });
    } catch (e) {
      setState(() {
        _isTestingEndpoint = false;
        _endpointTestSuccess = false;
        _endpointTestMessage =
            '无法连接到 $baseUrl，请确认主机地址与端口（如 8000 直连端口）是否开放';
      });
    } finally {
      sw.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    _syncFromConnectionProviderIfNeeded(conn);

    final presets = StorageService.getConnectionHistory();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 顶部 MCP 端点参数概览与自检卡片
        _buildEndpointHeaderCard(context, conn, presets),
        const SizedBox(height: 20),

        // 2. Agent 选择器卡片
        _buildAgentSelectorSection(context),
        const SizedBox(height: 16),

        // 3. 当前选中 Agent 的专属配置与接入指南
        _buildSelectedAgentConfigCard(context),
        const SizedBox(height: 20),

        // 4. 已暴露 MCP Tools 能力速览
        _buildToolsCatalogCard(context),
      ],
    );
  }

  Widget _buildEndpointHeaderCard(
    BuildContext context,
    ConnectionProvider conn,
    List<ConnectionPreset> presets,
  ) {
    final isDark = context.isDark;
    final activeAccent = isDark ? AppColors.accentCyan : AppColors.primaryBlue;
    final currentEndpointUrl = McpConfigGenerator.buildEndpointUrl(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      transport: _transportMode,
      token: _previewToken,
      includeQueryToken: false,
    );

    return Card(
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
                    Icons.hub_rounded,
                    color: AppColors.primaryBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'MCP 协议网关与接入参数',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '25 项原子 Tools',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: activeAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '自动同步当前 NAS 连接凭证，支持按不同 AI Agent 客户端生成专属接入配置',
                        style: TextStyle(fontSize: 12, color: context.subtextColor),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _showParamEditor = !_showParamEditor),
                  icon: Icon(
                    _showParamEditor ? Icons.expand_less_rounded : Icons.tune_rounded,
                    size: 16,
                  ),
                  label: Text(
                    _showParamEditor ? '收起参数' : '微调地址/端口',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 当前生效的网关信息摘要条
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link_rounded, size: 16, color: activeAccent),
                          const SizedBox(width: 6),
                          Flexible(
                            child: SelectableText(
                              currentEndpointUrl,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                color: isDark ? Colors.white : AppColors.lightTitle,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Builder(
                        builder: (context) {
                          final hasBasicCreds = _authType == AuthType.credentials &&
                              _effectiveUsername.isNotEmpty &&
                              _effectivePassword.isNotEmpty;
                          final hasTokenAuth = _realToken.isNotEmpty;
                          final isConfigured = hasBasicCreds || hasTokenAuth;
                          final badgeLabel = hasBasicCreds
                              ? 'Basic 鉴权 ($_effectiveUsername)'
                              : hasTokenAuth
                                  ? 'Token 鉴权已填入'
                                  : (_authType == AuthType.token
                                      ? '免密模式 (未填 Token)'
                                      : '未配置账号密码');
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isConfigured ? AppColors.successGreen : AppColors.warningOrange)
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badgeLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isConfigured ? AppColors.successGreen : AppColors.warningOrange,
                              ),
                            ),
                          );
                        },
                      ),
                      if (conn.port == 8086 && _effectivePort == 8000)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryBlue.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '已智能映射 8000 直连端口',
                            style: TextStyle(
                              fontSize: 11,
                              color: activeAccent,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 快捷端口与操作栏
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '常用端口切换:',
                        style: TextStyle(fontSize: 12, color: context.subtextColor),
                      ),
                      ChoiceChip(
                        label: const Text('8000 (MCP 直连推荐)', style: TextStyle(fontSize: 11)),
                        selected: _effectivePort == 8000,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          setState(() {
                            _portController.text = '8000';
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('8086 (Web 网关反代)', style: TextStyle(fontSize: 11)),
                        selected: _effectivePort == 8086,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          setState(() {
                            _portController.text = '8086';
                          });
                        },
                      ),
                      const SizedBox(width: 4),
                      FilterChip(
                        avatar: Icon(
                          _maskTokenInPreview
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 14,
                        ),
                        label: Text(
                          _maskTokenInPreview ? '预览已脱敏凭据' : '预览显示明文凭据',
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: _maskTokenInPreview,
                        visualDensity: VisualDensity.compact,
                        onSelected: (val) => setState(() => _maskTokenInPreview = val),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 可展开的自定义微调面板
            if (_showParamEditor) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.02)
                      : Colors.black.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '生成配置所用的地址与凭证 (仅影响下方配置生成，不改动当前客户端连接)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.subtextColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _hostController.text = conn.host;
                              _portController.text =
                                  (conn.port == 8086 ? 8000 : conn.port).toString();
                              _tokenController.text = conn.token;
                              _authType = conn.authType;
                              _usernameController.text =
                                  conn.username.isNotEmpty ? conn.username : 'admin';
                              _passwordController.text = conn.password;
                              _isHttps = conn.isHttps;
                            });
                          },
                          icon: const Icon(Icons.restore_rounded, size: 14),
                          label: const Text('重置为当前连接', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                    if (presets.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: presets.map((p) {
                          final isSelected = _hostController.text.trim() == p.host &&
                              _portController.text.trim() == p.port.toString();
                          return ActionChip(
                            avatar: Icon(
                              p.isHttps ? Icons.lock_outline_rounded : Icons.dns_rounded,
                              size: 13,
                            ),
                            label: Text(p.displayTitle, style: const TextStyle(fontSize: 11)),
                            backgroundColor: isSelected
                                ? AppColors.primaryBlue.withOpacity(0.2)
                                : null,
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              setState(() {
                                _hostController.text = p.host;
                                _portController.text =
                                    (p.port == 8086 ? 8000 : p.port).toString();
                                if (p.token.isNotEmpty) {
                                  _tokenController.text = p.token;
                                }
                                _authType = p.authType;
                                if (p.username != null && p.username!.isNotEmpty) {
                                  _usernameController.text = p.username!;
                                }
                                if (p.password != null) {
                                  _passwordController.text = p.password!;
                                }
                                _isHttps = p.isHttps;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (ctx, box) {
                        final isRow = box.maxWidth >= 460;
                        final hostField = TextField(
                          controller: _hostController,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'MCP 主机名 / IP',
                            hintText: '如 192.168.1.100 或 mynas.lan',
                            prefixIcon: Icon(Icons.router_rounded, size: 18),
                            isDense: true,
                          ),
                        );
                        final portField = TextField(
                          controller: _portController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'MCP 端口',
                            hintText: '默认 8000',
                            prefixIcon: Icon(Icons.numbers_rounded, size: 18),
                            isDense: true,
                          ),
                        );
                        if (isRow) {
                          return Row(
                            children: [
                              Expanded(flex: 3, child: hostField),
                              const SizedBox(width: 12),
                              Expanded(flex: 2, child: portField),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            hostField,
                            const SizedBox(height: 10),
                            portField,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('接入鉴权模式: ', style: TextStyle(fontSize: 12, color: context.subtextColor)),
                        ChoiceChip(
                          label: const Text('安全令牌 (Token)', style: TextStyle(fontSize: 11)),
                          selected: _authType == AuthType.token,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _authType = AuthType.token),
                        ),
                        ChoiceChip(
                          label: const Text('账号密码 (HTTP Basic)', style: TextStyle(fontSize: 11)),
                          selected: _authType == AuthType.credentials,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _authType = AuthType.credentials),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_authType == AuthType.token)
                      TextField(
                        controller: _tokenController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'MCP_AUTH_TOKEN (Bearer 令牌)',
                          hintText: '留空则生成无鉴权配置',
                          prefixIcon: Icon(Icons.key_rounded, size: 18),
                          isDense: true,
                        ),
                      )
                    else
                      LayoutBuilder(
                        builder: (ctx, box) {
                          final isRow = box.maxWidth >= 460;
                          final userField = TextField(
                            controller: _usernameController,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: '用户名 (Username)',
                              hintText: '如 admin',
                              prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
                              isDense: true,
                            ),
                          );
                          final passField = TextField(
                            controller: _passwordController,
                            obscureText: _maskTokenInPreview,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: '密码 (Password)',
                              hintText: '输入用户登录密码',
                              prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                              isDense: true,
                            ),
                          );
                          if (isRow) {
                            return Row(
                              children: [
                                Expanded(child: userField),
                                const SizedBox(width: 12),
                                Expanded(child: passField),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              userField,
                              const SizedBox(height: 10),
                              passField,
                            ],
                          );
                        },
                      ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '使用 HTTPS 加密协议生成地址',
                            style: TextStyle(fontSize: 13, color: context.subtextColor),
                          ),
                        ),
                        Switch(
                          value: _isHttps,
                          activeColor: AppColors.primaryBlue,
                          onChanged: (val) => setState(() => _isHttps = val),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),

            // 传输协议切换 + 连通性自检按钮
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<McpTransportMode>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  segments: McpTransportMode.values
                      .map(
                        (m) => ButtonSegment<McpTransportMode>(
                          value: m,
                          icon: Icon(
                            m == McpTransportMode.sse
                                ? Icons.stream_rounded
                                : Icons.http_rounded,
                            size: 16,
                          ),
                          label: Text(
                            m.label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                  selected: {_transportMode},
                  onSelectionChanged: (sel) {
                    setState(() => _transportMode = sel.first);
                  },
                ),
                FilledButton.tonalIcon(
                  onPressed: _isTestingEndpoint ? null : _testMcpEndpoint,
                  icon: _isTestingEndpoint
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_rounded, size: 17),
                  label: Text(
                    _isTestingEndpoint ? '正在探测端点...' : '测试 MCP 端点连通性',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),

            // 自检结果横幅
            if (_endpointTestMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: (_endpointTestSuccess == true
                          ? AppColors.successGreen
                          : AppColors.errorRed)
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (_endpointTestSuccess == true
                            ? AppColors.successGreen
                            : AppColors.errorRed)
                        .withOpacity(0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _endpointTestSuccess == true
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      size: 18,
                      color: _endpointTestSuccess == true
                          ? AppColors.successGreen
                          : AppColors.errorRed,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _endpointTestMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _endpointTestSuccess == true
                              ? (isDark ? Colors.white : AppColors.lightTitle)
                              : AppColors.errorRed,
                        ),
                      ),
                    ),
                    if (_endpointLatencyMs != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.successGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${_endpointLatencyMs}ms',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.successGreen,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAgentSelectorSection(BuildContext context) {
    final isDark = context.isDark;
    final activeColor = isDark ? AppColors.accentCyan : AppColors.primaryBlue;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              const Text(
                '选择目标集成的 AI Agent 客户端',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
              Text(
                '根据客户端规范自动生成对应结构',
                style: TextStyle(fontSize: 11.5, color: context.subtextColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<McpAgentType>(
                value: _selectedAgent,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
                dropdownColor: isDark ? const Color(0xFF1E2430) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                items: McpAgentType.values.map((agent) {
                  return DropdownMenuItem<McpAgentType>(
                    value: agent,
                    child: Row(
                      children: [
                        Icon(agent.icon, size: 19, color: activeColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                agent.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : AppColors.lightTitle,
                                ),
                              ),
                              Text(
                                agent.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.subtextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (McpAgentType? newAgent) {
                  if (newAgent != null) {
                    setState(() => _selectedAgent = newAgent);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedAgentConfigCard(BuildContext context) {
    switch (_selectedAgent) {
      case McpAgentType.antigravity:
        return _buildAntigravityConfigCard(context);
      case McpAgentType.claude:
        return _buildClaudeConfigCard(context);
      case McpAgentType.cursorWindsurf:
        return _buildCursorWindsurfConfigCard(context);
      case McpAgentType.cherryStudio:
        return _buildCherryStudioConfigCard(context);
      case McpAgentType.difyGeneric:
        return _buildDifyGenericConfigCard(context);
    }
  }

  Widget _buildAntigravityConfigCard(BuildContext context) {
    final previewJson = McpConfigGenerator.generateAntigravityJson(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      token: _previewToken,
      transport: _transportMode,
      authType: _authType,
      username: _effectiveUsername,
      password: _effectivePassword,
    );
    final realJson = McpConfigGenerator.generateAntigravityJson(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      token: _realToken,
      transport: _transportMode,
      authType: _authType,
      username: _effectiveUsername,
      password: _effectivePassword,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAgentCardHeader(
              context,
              agent: McpAgentType.antigravity,
              badgeText: '原生支持 SSE & Streamable HTTP',
            ),
            const SizedBox(height: 16),
            _buildPathHintTile(
              context,
              label: '全局配置文件路径',
              path: '~/.gemini/config/mcp_config.json',
              note: 'Windows 路径示例: C:\\Users\\<用户名>\\.gemini\\config\\mcp_config.json',
            ),
            const SizedBox(height: 8),
            _buildPathHintTile(
              context,
              label: '项目级配置文件路径',
              path: '.agents/mcp_config.json',
              note: '置于工作区根目录下，仅对当前工程生效',
            ),
            const SizedBox(height: 16),
            _buildCodeBlockCard(
              context,
              title: 'mcp_config.json 配置内容',
              previewCode: previewJson,
              copyCode: realJson,
              copyLabel: 'Antigravity MCP 配置 JSON',
            ),
            const SizedBox(height: 12),
            _buildStepTipBanner(
              context,
              '将上述 JSON 合并到配置文件的 mcpServers 节点下，保存后在 Antigravity / Gemini CLI 中刷新 MCP 服务即可直接调用全部 25 个 NAS 工具。',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClaudeConfigCard(BuildContext context) {
    final previewCli = McpConfigGenerator.generateClaudeCodeCliCommand(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      token: _previewToken,
      transport: _transportMode,
      authType: _authType,
      username: _effectiveUsername,
      password: _effectivePassword,
    );
    final realCli = McpConfigGenerator.generateClaudeCodeCliCommand(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      token: _realToken,
      transport: _transportMode,
      authType: _authType,
      username: _effectiveUsername,
      password: _effectivePassword,
    );

    final previewDesktopJson = McpConfigGenerator.generateClaudeDesktopJson(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      token: _previewToken,
      transport: _transportMode,
      authType: _authType,
      username: _effectiveUsername,
      password: _effectivePassword,
    );
    final realDesktopJson = McpConfigGenerator.generateClaudeDesktopJson(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      token: _realToken,
      transport: _transportMode,
      authType: _authType,
      username: _effectiveUsername,
      password: _effectivePassword,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAgentCardHeader(
              context,
              agent: McpAgentType.claude,
              badgeText: 'CLI 命令 + 桌面端桥接',
            ),
            const SizedBox(height: 16),
            _buildCodeBlockCard(
              context,
              title: '方式一：Claude Code CLI 一键终端添加命令 (推荐)',
              previewCode: previewCli,
              copyCode: realCli,
              copyLabel: 'Claude Code CLI 添加命令',
            ),
            const SizedBox(height: 16),
            _buildPathHintTile(
              context,
              label: 'Claude Desktop 配置文件 (Windows)',
              path: r'%APPDATA%\Claude\claude_desktop_config.json',
            ),
            const SizedBox(height: 8),
            _buildPathHintTile(
              context,
              label: 'Claude Desktop 配置文件 (macOS)',
              path: '~/Library/Application Support/Claude/claude_desktop_config.json',
            ),
            const SizedBox(height: 12),
            _buildCodeBlockCard(
              context,
              title: '方式二：Claude Desktop 配置文件 (通过 npx mcp-remote 桥接)',
              previewCode: previewDesktopJson,
              copyCode: realDesktopJson,
              copyLabel: 'Claude Desktop 配置 JSON',
            ),
            const SizedBox(height: 12),
            _buildStepTipBanner(
              context,
              'Claude Desktop 原生依赖 stdio 传输，通过官方推荐的 npx -y mcp-remote 桥接器可零配置接入远程 SSE/HTTP 端点并携带 Bearer 鉴权头（需本机已安装 Node.js）。',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCursorWindsurfConfigCard(BuildContext context) {
    final previewCursor = McpConfigGenerator.generateCursorJson(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      token: _previewToken,
      transport: _transportMode,
      authType: _authType,
      username: _effectiveUsername,
      password: _effectivePassword,
    );
    final realCursor = McpConfigGenerator.generateCursorJson(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      token: _realToken,
      transport: _transportMode,
      authType: _authType,
      username: _effectiveUsername,
      password: _effectivePassword,
    );

    final previewWindsurf = McpConfigGenerator.generateWindsurfJson(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      token: _previewToken,
      transport: _transportMode,
      authType: _authType,
      username: _effectiveUsername,
      password: _effectivePassword,
    );
    final realWindsurf = McpConfigGenerator.generateWindsurfJson(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      token: _realToken,
      transport: _transportMode,
      authType: _authType,
      username: _effectiveUsername,
      password: _effectivePassword,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAgentCardHeader(
              context,
              agent: McpAgentType.cursorWindsurf,
              badgeText: '支持 Cursor / Windsurf / Cline',
            ),
            const SizedBox(height: 16),
            _buildPathHintTile(
              context,
              label: 'Cursor 配置文件路径',
              path: '~/.cursor/mcp.json 或项目内 .cursor/mcp.json',
            ),
            const SizedBox(height: 10),
            _buildCodeBlockCard(
              context,
              title: 'Cursor MCP 配置 (使用 url 字段)',
              previewCode: previewCursor,
              copyCode: realCursor,
              copyLabel: 'Cursor MCP 配置 JSON',
            ),
            const SizedBox(height: 18),
            _buildPathHintTile(
              context,
              label: 'Windsurf 配置文件路径',
              path: '~/.codeium/windsurf/mcp_config.json',
            ),
            const SizedBox(height: 10),
            _buildCodeBlockCard(
              context,
              title: 'Windsurf MCP 配置 (使用 serverUrl 字段)',
              previewCode: previewWindsurf,
              copyCode: realWindsurf,
              copyLabel: 'Windsurf MCP 配置 JSON',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCherryStudioConfigCard(BuildContext context) {
    final realUrlWithToken = McpConfigGenerator.buildEndpointUrl(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      transport: _transportMode,
      token: _realToken,
      includeQueryToken: _authType == AuthType.token,
      authType: _authType,
    );
    final previewUrlWithToken = McpConfigGenerator.buildEndpointUrl(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      transport: _transportMode,
      token: _previewToken,
      includeQueryToken: _authType == AuthType.token,
      authType: _authType,
    );
    final realUrlClean = McpConfigGenerator.buildEndpointUrl(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      transport: _transportMode,
      token: _realToken,
      includeQueryToken: false,
      authType: _authType,
    );

    final previewJson = McpConfigGenerator.generateCherryStudioJson(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      token: _previewToken,
      transport: _transportMode,
      authType: _authType,
      username: _effectiveUsername,
      password: _effectivePassword,
    );
    final realJson = McpConfigGenerator.generateCherryStudioJson(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      token: _realToken,
      transport: _transportMode,
      authType: _authType,
      username: _effectiveUsername,
      password: _effectivePassword,
    );

    final realAuthHeader = McpConfigGenerator.buildAuthHeader(
      authType: _authType,
      token: _realToken,
      username: _effectiveUsername,
      password: _effectivePassword,
    );
    final previewAuthHeader = McpConfigGenerator.buildAuthHeader(
      authType: _authType,
      token: _previewToken,
      username: _effectiveUsername,
      password: _effectivePassword,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAgentCardHeader(
              context,
              agent: McpAgentType.cherryStudio,
              badgeText: '支持表单分项粘贴 & JSON 导入',
            ),
            const SizedBox(height: 16),
            const Text(
              '方式一：GUI 表单字段分项复制（设置 -> MCP 服务器 -> 添加服务器）',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildCopyableFieldRow(
              context,
              label: '名称',
              displayValue: 'nasio',
              copyValue: 'nasio',
            ),
            const SizedBox(height: 8),
            _buildCopyableFieldRow(
              context,
              label: '类型',
              displayValue: _transportMode == McpTransportMode.sse
                  ? 'SSE (Server-Sent Events)'
                  : '可流式传输的 HTTP (streamableHttp)',
              copyValue: _transportMode == McpTransportMode.sse ? 'sse' : 'streamableHttp',
            ),
            const SizedBox(height: 8),
            _buildCopyableFieldRow(
              context,
              label: '服务器地址 (包含免填请求头)',
              displayValue: previewUrlWithToken,
              copyValue: realUrlWithToken,
            ),
            const SizedBox(height: 8),
            _buildCopyableFieldRow(
              context,
              label: '纯净服务器地址 (配合请求头使用)',
              displayValue: realUrlClean,
              copyValue: realUrlClean,
            ),
            if (realAuthHeader.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildCopyableFieldRow(
                context,
                label: '请求头 (Authorization)',
                displayValue: 'Authorization=$previewAuthHeader',
                copyValue: 'Authorization=$realAuthHeader',
              ),
            ],
            const SizedBox(height: 18),
            _buildCodeBlockCard(
              context,
              title: '方式二：Cherry Studio「从 JSON 导入」配置',
              previewCode: previewJson,
              copyCode: realJson,
              copyLabel: 'Cherry Studio 导入 JSON',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDifyGenericConfigCard(BuildContext context) {
    final sseUrlWithToken = McpConfigGenerator.buildEndpointUrl(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      transport: McpTransportMode.sse,
      token: _realToken,
      includeQueryToken: _authType == AuthType.token,
      authType: _authType,
    );
    final sseUrlPreview = McpConfigGenerator.buildEndpointUrl(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      transport: McpTransportMode.sse,
      token: _previewToken,
      includeQueryToken: _authType == AuthType.token,
      authType: _authType,
    );
    final sseUrlClean = McpConfigGenerator.buildEndpointUrl(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      transport: McpTransportMode.sse,
      token: _realToken,
      includeQueryToken: false,
      authType: _authType,
    );

    final httpUrlWithToken = McpConfigGenerator.buildEndpointUrl(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      transport: McpTransportMode.streamableHttp,
      token: _realToken,
      includeQueryToken: _authType == AuthType.token,
      authType: _authType,
    );
    final httpUrlPreview = McpConfigGenerator.buildEndpointUrl(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      transport: McpTransportMode.streamableHttp,
      token: _previewToken,
      includeQueryToken: _authType == AuthType.token,
      authType: _authType,
    );
    final httpUrlClean = McpConfigGenerator.buildEndpointUrl(
      host: _effectiveHost,
      port: _effectivePort,
      isHttps: _isHttps,
      transport: McpTransportMode.streamableHttp,
      token: _realToken,
      includeQueryToken: false,
      authType: _authType,
    );

    final realAuthHeader = McpConfigGenerator.buildAuthHeader(
      authType: _authType,
      token: _realToken,
      username: _effectiveUsername,
      password: _effectivePassword,
    );
    final previewAuthHeader = McpConfigGenerator.buildAuthHeader(
      authType: _authType,
      token: _previewToken,
      username: _effectiveUsername,
      password: _effectivePassword,
    );

    final headersJsonReal = const JsonEncoder.withIndent('  ').convert({
      if (realAuthHeader.isNotEmpty) 'Authorization': realAuthHeader,
    });
    final headersJsonPreview = const JsonEncoder.withIndent('  ').convert({
      if (previewAuthHeader.isNotEmpty) 'Authorization': previewAuthHeader,
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAgentCardHeader(
              context,
              agent: McpAgentType.difyGeneric,
              badgeText: 'SSE + Streamable HTTP 双协议栈',
            ),
            const SizedBox(height: 16),
            _buildCopyableFieldRow(
              context,
              label: 'SSE 免 Header 完整端点 (推荐 Dify 等不支持自定义 Header 的场景)',
              displayValue: sseUrlPreview,
              copyValue: sseUrlWithToken,
            ),
            const SizedBox(height: 8),
            _buildCopyableFieldRow(
              context,
              label: 'Streamable HTTP (/mcp) 免 Header 完整端点',
              displayValue: httpUrlPreview,
              copyValue: httpUrlWithToken,
            ),
            const SizedBox(height: 8),
            _buildCopyableFieldRow(
              context,
              label: 'SSE 标准端点 (需配 Authorization Header)',
              displayValue: sseUrlClean,
              copyValue: sseUrlClean,
            ),
            const SizedBox(height: 8),
            _buildCopyableFieldRow(
              context,
              label: 'Streamable HTTP 标准端点 (/mcp)',
              displayValue: httpUrlClean,
              copyValue: httpUrlClean,
            ),
            if (_realToken.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildCopyableFieldRow(
                context,
                label: 'Authorization Header 值',
                displayValue: 'Bearer $_previewToken',
                copyValue: 'Bearer $_realToken',
              ),
              const SizedBox(height: 16),
              _buildCodeBlockCard(
                context,
                title: 'HTTP 鉴权请求头 (JSON 格式)',
                previewCode: headersJsonPreview,
                copyCode: headersJsonReal,
                copyLabel: 'HTTP Headers JSON',
              ),
            ],
            const SizedBox(height: 12),
            _buildStepTipBanner(
              context,
              'Nasio 网关同时支持在 HTTP Header 传递 Authorization: Bearer <token> 与在 URL Query 参数传递 ?token=<token>，确保在 Dify、n8n、FastGPT、NextChat 等各类智能体编排平台均可无缝鉴权调用。',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentCardHeader(
    BuildContext context, {
    required McpAgentType agent,
    required String badgeText,
  }) {
    final isDark = context.isDark;
    final activeAccent = isDark ? AppColors.accentCyan : AppColors.primaryBlue;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(agent.icon, color: AppColors.primaryBlue, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    agent.title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: activeAccent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                agent.subtitle,
                style: TextStyle(fontSize: 12, color: context.subtextColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPathHintTile(
    BuildContext context, {
    required String label,
    required String path,
    String? note,
  }) {
    final isDark = context.isDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open_rounded, size: 16, color: context.subtextColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    Text(
                      '$label: ',
                      style: TextStyle(fontSize: 12, color: context.subtextColor),
                    ),
                    SelectableText(
                      path,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.accentCyan : AppColors.primaryBlueDark,
                      ),
                    ),
                  ],
                ),
                if (note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: TextStyle(fontSize: 11, color: context.tertiaryTextColor),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 15),
            tooltip: '复制路径',
            visualDensity: VisualDensity.compact,
            onPressed: () => _copyToClipboard(path, label),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyableFieldRow(
    BuildContext context, {
    required String label,
    required String displayValue,
    required String copyValue,
  }) {
    final isDark = context.isDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: context.subtextColor),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  displayValue,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppColors.lightTitle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => _copyToClipboard(copyValue, label),
            icon: const Icon(Icons.copy_rounded, size: 14),
            label: const Text('复制', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeBlockCard(
    BuildContext context, {
    required String title,
    required String previewCode,
    required String copyCode,
    required String copyLabel,
  }) {
    final isDark = context.isDark;
    final accent = isDark ? AppColors.accentCyan : AppColors.primaryBlue;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.data_object_rounded, size: 16, color: accent),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _copyToClipboard(copyCode, copyLabel),
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('一键复制配置', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: SelectableText(
              previewCode,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.45,
                color: isDark ? Colors.white.withOpacity(0.9) : AppColors.lightTitle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepTipBanner(BuildContext context, String text) {
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withOpacity(isDark ? 0.1 : 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primaryBlue.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            size: 16,
            color: isDark ? AppColors.accentCyan : AppColors.primaryBlue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: context.subtextColor, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildToolsCatalogCard(BuildContext context) {
    final isDark = context.isDark;
    final activeAccent = isDark ? AppColors.accentCyan : AppColors.primaryBlue;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _showToolsCatalog = !_showToolsCatalog),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.extension_rounded,
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
                          '服务端已暴露 MCP Tools 能力清单 (共 25 项)',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '涵盖存储运维、复合长任务监控、混合下载、文件检索治理、防灾回收站与技能规范中心',
                          style: TextStyle(fontSize: 12, color: context.subtextColor),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _showToolsCatalog = !_showToolsCatalog),
                    icon: Icon(
                      _showToolsCatalog
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _showToolsCatalog ? '收起清单' : '展开查看',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            if (_showToolsCatalog) ...[
              const SizedBox(height: 16),
              ...McpConfigGenerator.toolCategories.map((cat) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(cat.icon, size: 16, color: activeAccent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              cat.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: activeAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: cat.tools.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: Theme.of(context).dividerColor),
                          itemBuilder: (ctx, idx) {
                            final tool = cat.tools[idx];
                            return ListTile(
                              dense: true,
                              title: Row(
                                children: [
                                  Flexible(
                                    child: SelectableText(
                                      tool.name,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : AppColors.lightTitle,
                                      ),
                                    ),
                                  ),
                                  if (tool.isAsync) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryBlue.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '异步长任务',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: activeAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                tool.description,
                                style: TextStyle(fontSize: 11.5, color: context.subtextColor),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 14),
                                tooltip: '复制工具名 ${tool.name}',
                                onPressed: () =>
                                    _copyToClipboard(tool.name, '工具标识 ${tool.name}'),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
