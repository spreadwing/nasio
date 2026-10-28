import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/skill_model.dart';
import '../../providers/connection_provider.dart';
import '../../services/storage_service.dart';
import 'mcp_config_section.dart';

class SkillsConfigSection extends StatefulWidget {
  const SkillsConfigSection({super.key});

  @override
  State<SkillsConfigSection> createState() => _SkillsConfigSectionState();
}

class _SkillsConfigSectionState extends State<SkillsConfigSection> {
  McpAgentType _selectedAgent = McpAgentType.antigravity;
  final TextEditingController _searchController = TextEditingController();

  List<SkillModel> _serverSkills = [];
  Set<String> _selectedSkillNames = {};
  final Set<String> _expandedSkillNames = {};
  bool _isLoadingSkills = false;
  bool _isGeneratingBootstrappingPrompt = false;
  String? _skillsError;
  String _lastConnSignature = '';

  String _computeConnSignature(ConnectionProvider conn) {
    return '${conn.isConnected}|${conn.host}|${conn.port}|${conn.isHttps}|${conn.authType.name}|${conn.token}|${conn.username}|${conn.password}';
  }

  @override
  void initState() {
    super.initState();
    final conn = context.read<ConnectionProvider>();
    _lastConnSignature = _computeConnSignature(conn);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchServerSkills();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Dio _createDioForEndpoint() {
    final conn = context.read<ConnectionProvider>();
    final host = conn.host.isEmpty ? '127.0.0.1' : conn.host;
    final port = conn.port == 8086 ? 8000 : conn.port;
    final baseUrl = McpConfigGenerator.buildBaseUrl(
      host: host,
      port: port,
      isHttps: conn.isHttps,
    );
    final headers = <String, dynamic>{
      if (conn.token.isNotEmpty)
        'Authorization': 'Bearer ${conn.token}'
      else if (conn.authType == AuthType.credentials &&
          conn.username.isNotEmpty &&
          conn.password.isNotEmpty)
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${conn.username}:${conn.password}'))}',
    };
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 8),
        headers: headers,
      ),
    );
  }

  Future<void> _fetchServerSkills() async {
    if (!mounted) return;
    setState(() {
      _isLoadingSkills = true;
      _skillsError = null;
    });

    try {
      final dio = _createDioForEndpoint();
      final res = await dio.get('/api/v1/skills');
      final list = (res.data as List<dynamic>)
          .map((e) => SkillModel.fromJson(e as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() {
        _isLoadingSkills = false;
        _serverSkills = list;
        _selectedSkillNames = list.map((s) => s.name).toSet();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingSkills = false;
        _skillsError = Formatters.formatErrorMessage(e, '拉取技能列表失败');
      });
    }
  }

  Future<SkillModel?> _fetchSkillDetail(String name) async {
    try {
      final dio = _createDioForEndpoint();
      final res = await dio.get('/api/v1/skills/$name');
      final detail = SkillModel.fromJson(res.data as Map<String, dynamic>);
      final idx = _serverSkills.indexWhere((s) => s.name == name);
      if (idx >= 0) {
        _serverSkills[idx] = detail;
      }
      return detail;
    } catch (_) {
      return null;
    }
  }

  void _toggleSelectAllSkills(bool? selectAll) {
    setState(() {
      if (selectAll == true) {
        _selectedSkillNames = _serverSkills.map((s) => s.name).toSet();
      } else {
        _selectedSkillNames.clear();
      }
    });
  }

  void _toggleSkillSelected(String name) {
    setState(() {
      if (_selectedSkillNames.contains(name)) {
        _selectedSkillNames.remove(name);
      } else {
        _selectedSkillNames.add(name);
      }
    });
  }

  Future<void> _toggleSkillExpanded(SkillModel skill) async {
    final name = skill.name;
    final isExpanded = _expandedSkillNames.contains(name);
    if (isExpanded) {
      setState(() => _expandedSkillNames.remove(name));
    } else {
      setState(() => _expandedSkillNames.add(name));
      if (skill.content == null || skill.content!.isEmpty) {
        final detail = await _fetchSkillDetail(name);
        if (mounted && detail != null) {
          setState(() {});
        }
      }
    }
  }

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

  Future<void> _deleteSkill(String name) async {
    try {
      final dio = _createDioForEndpoint();
      final res = await dio.delete('/api/v1/skills/$name');
      if (res.statusCode == 200 || res.data?['deleted'] == true) {
        setState(() {
          _serverSkills.removeWhere((s) => s.name == name);
          _selectedSkillNames.remove(name);
          _expandedSkillNames.remove(name);
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已从服务端删除技能: $name'),
            backgroundColor: AppColors.successGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Formatters.formatErrorMessage(e, '删除技能失败')),
          backgroundColor: AppColors.errorRed,
        ),
      );
    }
  }

  Future<void> _confirmDeleteSkill(SkillModel skill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.errorRed, size: 22),
            SizedBox(width: 8),
            Text('删除技能确认', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Text(
          '确定要从 Nasio 服务端永久删除技能 "${skill.name}" 吗？\n此操作将移除服务端的 SKILL.md 文件及对应目录。',
          style: const TextStyle(fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteSkill(skill.name);
    }
  }

  Future<void> _confirmBatchDeleteSkills() async {
    final count = _selectedSkillNames.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_outlined, color: AppColors.errorRed, size: 22),
            SizedBox(width: 8),
            Text('批量删除技能确认', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Text(
          '确定要从 Nasio 服务端删除已勾选的 $count 项技能吗？\n删除后不可恢复。',
          style: const TextStyle(fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('确认批量删除 ($count)'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final namesToDelete = _selectedSkillNames.toList();
      int successCount = 0;
      for (final name in namesToDelete) {
        try {
          final dio = _createDioForEndpoint();
          await dio.delete('/api/v1/skills/$name');
          successCount++;
        } catch (_) {}
      }
      setState(() {
        _serverSkills.removeWhere((s) => namesToDelete.contains(s.name));
        _selectedSkillNames.removeAll(namesToDelete);
        _expandedSkillNames.removeAll(namesToDelete);
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已从服务端批量删除 $successCount 项技能'),
          backgroundColor: AppColors.successGreen,
        ),
      );
    }
  }

  Future<void> _copyBootstrappingPrompt() async {
    setState(() => _isGeneratingBootstrappingPrompt = true);
    final conn = context.read<ConnectionProvider>();
    final host = conn.host.isEmpty ? '127.0.0.1' : conn.host;
    final port = conn.port == 8086 ? 8000 : conn.port;

    try {
      final selectedList = <SkillModel>[];
      for (final name in _selectedSkillNames) {
        var skill = _serverSkills.firstWhere(
          (s) => s.name == name,
          orElse: () => SkillModel(name: name, description: '', updatedAt: ''),
        );
        if (skill.content == null || skill.content!.isEmpty) {
          final detail = await _fetchSkillDetail(name);
          if (detail != null) {
            skill = detail;
          }
        }
        selectedList.add(skill);
      }

      final prompt = McpConfigGenerator.generateBootstrappingPrompt(
        agent: _selectedAgent,
        host: host,
        port: port,
        isHttps: conn.isHttps,
        token: conn.token,
        transport: McpTransportMode.sse,
        skills: selectedList,
        authType: conn.authType,
        username: conn.username,
        password: conn.password,
      );

      await Clipboard.setData(ClipboardData(text: prompt));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已复制 ${_selectedAgent.shortTitle} 初始化自举 Prompt 到剪贴板（含 ${selectedList.length} 项技能）'),
          backgroundColor: AppColors.successGreen,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Formatters.formatErrorMessage(e, '生成自举 Prompt 失败')),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingBootstrappingPrompt = false);
    }
  }

  List<SkillModel> get _filteredSkills {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _serverSkills;
    return _serverSkills.where((s) {
      return s.name.toLowerCase().contains(query) ||
          s.description.toLowerCase().contains(query) ||
          s.tags.any((t) => t.toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    final sig = _computeConnSignature(conn);
    if (_lastConnSignature != sig) {
      _lastConnSignature = sig;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchServerSkills();
      });
    }

    final isDark = context.isDark;
    final activeAccent = isDark ? AppColors.accentCyan : AppColors.primaryBlue;
    final allSelected = _serverSkills.isNotEmpty &&
        _selectedSkillNames.length == _serverSkills.length;
    final filtered = _filteredSkills;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 顶部技能中心概览卡片
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
                        Icons.auto_stories_rounded,
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
                                '技能与工作流中心',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryBlue.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '已选 ${_selectedSkillNames.length} / 共 ${_serverSkills.length} 项',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: activeAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '管理 NAS 服务端持久化落盘的标准化 SOP 规范（data/skills/），支持按 Agent 生成自举提示词',
                            style: TextStyle(fontSize: 12, color: context.subtextColor),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: _isLoadingSkills ? null : _fetchServerSkills,
                      tooltip: '从服务端刷新技能列表',
                      icon: _isLoadingSkills
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 目标 Agent 选择器（决定自举 Prompt 生成的路径规范）
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    const Text(
                      '自举目标 AI Agent 客户端:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '决定生成的技能安装路径与配置结构',
                      style: TextStyle(fontSize: 11, color: context.subtextColor),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                              Icon(agent.icon, size: 19, color: activeAccent),
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
          ),
        ),
        const SizedBox(height: 16),

        // 2. 状态展示：加载中 / 失败 / 空列表 / 技能列表卡片
        if (_isLoadingSkills && _serverSkills.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            child: const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('正在拉取服务端持久化技能列表...', style: TextStyle(fontSize: 13)),
              ],
            ),
          )
        else if (_skillsError != null && _serverSkills.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.errorRed.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.errorRed.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.errorRed, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _skillsError!,
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : AppColors.errorRed),
                  ),
                ),
                TextButton(
                  onPressed: _fetchServerSkills,
                  child: const Text('重试'),
                ),
              ],
            ),
          )
        else if (_serverSkills.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              children: [
                Icon(Icons.auto_stories_outlined, size: 40, color: context.subtextColor),
                const SizedBox(height: 12),
                const Text(
                  '服务端当前尚未沉淀技能规范',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'AI Agent 可通过 MCP 工具 sync_skill 沉淀业务 SOP，落盘至服务端 data/skills/ 目录下。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: context.subtextColor, height: 1.4),
                ),
              ],
            ),
          )
        else ...[
          // 搜索与过滤栏
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '按技能名称、说明或标签快速检索...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
            ),
          ),

          // 顶部批量操作栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: allSelected,
                      tristate: _selectedSkillNames.isNotEmpty && !allSelected,
                      onChanged: _toggleSelectAllSkills,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      allSelected ? '取消全选' : '全选所有技能',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.lightTitle,
                      ),
                    ),
                    if (_selectedSkillNames.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.errorRed,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _confirmBatchDeleteSkills,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                        label: Text(
                          '删除 (${_selectedSkillNames.length})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_selectedAgent.icon, size: 13, color: activeAccent),
                      const SizedBox(width: 4),
                      Text(
                        '适配: ${_selectedAgent.shortTitle}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: activeAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 技能卡片列表
          ...filtered.map((skill) {
            final isSelected = _selectedSkillNames.contains(skill.name);
            final isExpanded = _expandedSkillNames.contains(skill.name);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? activeAccent.withOpacity(0.6)
                      : Theme.of(context).dividerColor,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 卡片头部
                  InkWell(
                    onTap: () => _toggleSkillSelected(skill.name),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: isSelected,
                            onChanged: (_) => _toggleSkillSelected(skill.name),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: activeAccent.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        skill.name,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'monospace',
                                          color: activeAccent,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    if (skill.updatedAt.isNotEmpty)
                                      Text(
                                        Formatters.formatTimestamp(skill.updatedAt),
                                        style: TextStyle(fontSize: 11, color: context.subtextColor),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  skill.description.isNotEmpty ? skill.description : '暂无功能描述',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.4,
                                    color: isDark ? Colors.white : AppColors.lightTitle,
                                  ),
                                ),
                                if (skill.tags.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: skill.tags.map((t) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white.withOpacity(0.06)
                                              : Colors.black.withOpacity(0.05),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '#$t',
                                          style: TextStyle(fontSize: 10.5, color: context.subtextColor),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton.icon(
                                onPressed: () => _toggleSkillExpanded(skill),
                                icon: Icon(
                                  isExpanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  isExpanded ? '收起' : '预览',
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 17),
                                color: AppColors.errorRed.withOpacity(0.85),
                                tooltip: '从服务端删除此技能',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _confirmDeleteSkill(skill),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 展开 Markdown 原文预览
                  if (isExpanded) ...[
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.black.withOpacity(0.25)
                            : Colors.grey.withOpacity(0.05),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'SKILL.md 规范全文预览',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: context.subtextColor,
                                ),
                              ),
                              const Spacer(),
                              FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => _copyToClipboard(
                                  skill.content ?? skill.body ?? '',
                                  '${skill.name} 规范 Markdown',
                                ),
                                icon: const Icon(Icons.copy_rounded, size: 13),
                                label: const Text('复制 Markdown', style: TextStyle(fontSize: 11.5)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(maxHeight: 280),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF030712) : const Color(0xFFFFFFFF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).dividerColor),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                skill.content ?? skill.body ?? '正在拉取内容...',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontFamily: 'monospace',
                                  height: 1.45,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),

          const SizedBox(height: 16),

          // 3. 底部一键复制自举 Prompt 卡片
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryBlue.withOpacity(isDark ? 0.2 : 0.12),
                  AppColors.accentCyan.withOpacity(isDark ? 0.15 : 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primaryBlue.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_fix_high_rounded, color: activeAccent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '一键集成与自举引导',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.lightTitle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '点击下方按钮，将生成针对 ${_selectedAgent.title} 的初始化自举 Prompt（内含 MCP 服务端配置与已勾选的 ${_selectedSkillNames.length} 项技能完整内容）。直接将复制内容粘贴发送给智能体即可完成全自动集成配置。',
                  style: TextStyle(fontSize: 12, color: context.subtextColor, height: 1.45),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: AppColors.primaryBlue,
                  ),
                  onPressed: _isGeneratingBootstrappingPrompt ? null : _copyBootstrappingPrompt,
                  icon: _isGeneratingBootstrappingPrompt
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.copy_all_rounded, size: 18),
                  label: Text(
                    _isGeneratingBootstrappingPrompt
                        ? '正在生成自举 Prompt...'
                        : '一键复制 ${_selectedAgent.shortTitle} 初始化自举 Prompt (含 ${_selectedSkillNames.length} 项技能)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
