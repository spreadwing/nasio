import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/chat_model.dart';
import '../../providers/chat_provider.dart';
import '../../providers/connection_provider.dart';
import '../../providers/storage_provider.dart';
import '../../providers/trash_provider.dart';
import '../../services/api_service.dart';
import '../home_scaffold.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  static const List<Map<String, dynamic>> _quickPrompts = [
    {
      'icon': Icons.analytics_outlined,
      'label': '目录结构智能摘要',
      'prompt': '扫描并生成下载目录的结构统计摘要（get_directory_digest）',
      'color': AppColors.primaryBlue,
    },
    {
      'icon': Icons.science_outlined,
      'label': '典型文件样本嗅探',
      'prompt': '对下载目录执行典型文件样本抽样（sample_directory_files），分析文件命名规律',
      'color': AppColors.accentCyan,
    },
    {
      'icon': Icons.cleaning_services_outlined,
      'label': '预览清理广告垃圾',
      'prompt': '试运行扫描下载目录中的发布站广告与垃圾文件（clean_resource_rubbish, dry_run=true）',
      'color': AppColors.warningOrange,
    },
    {
      'icon': Icons.storage_rounded,
      'label': '检查系统与存储状态',
      'prompt': '检查当前 NAS 存储池可用空间与正在运行的任务状态',
      'color': AppColors.successGreen,
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final conn = context.read<ConnectionProvider>();
      if (conn.isConnected) {
        context.read<ChatProvider>().loadAll();
      }
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend([String? presetPrompt]) async {
    final text = (presetPrompt ?? _inputCtrl.text).trim();
    if (text.isEmpty) return;
    if (presetPrompt == null) {
      _inputCtrl.clear();
    }
    final chatProv = context.read<ChatProvider>();
    _scrollToBottom();
    await chatProv.sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    final chatProv = context.watch<ChatProvider>();
    final storageProv = context.watch<StorageProvider>();
    final llmCfg = storageProv.config?.llm ?? {};
    final isLlmEnabled = llmCfg['enabled'] == true;
    final llmModelName = llmCfg['model']?.toString() ?? '未配置';

    final screenWidth = MediaQuery.of(context).size.width;
    final isCompactBar = screenWidth < 540;
    final showTitleBadge = screenWidth >= 820;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: isCompactBar ? 0 : null,
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: '返回主页',
          onPressed: () => HomeScaffold.switchToTab(context, 0),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(
              child: Text(
                'AI 副驾驶',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showTitleBadge) ...[
              const SizedBox(width: 10),
              Flexible(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showLlmAndWebhookConfigDialog(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isLlmEnabled ? AppColors.successGreen : AppColors.warningOrange)
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (isLlmEnabled ? AppColors.successGreen : AppColors.warningOrange)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isLlmEnabled ? Icons.bolt_rounded : Icons.touch_app_rounded,
                          size: 13,
                          color: isLlmEnabled ? AppColors.successGreen : AppColors.warningOrange,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            isLlmEnabled ? llmModelName : '快捷指令模式 (点击配置模型)',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isLlmEnabled
                                  ? AppColors.successGreen
                                  : AppColors.warningOrange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // 待审批按钮
          IconButton(
            visualDensity: isCompactBar ? VisualDensity.compact : null,
            padding: isCompactBar ? const EdgeInsets.all(6) : null,
            constraints: isCompactBar ? const BoxConstraints(minWidth: 34, minHeight: 34) : null,
            tooltip: '高危操作人工审批 (${chatProv.pendingApprovalsCount})',
            onPressed: () => _showApprovalsDialog(context),
            icon: Badge(
              isLabelVisible: chatProv.pendingApprovalsCount > 0,
              label: Text('${chatProv.pendingApprovalsCount}'),
              backgroundColor: AppColors.errorRed,
              child: const Icon(Icons.verified_user_outlined),
            ),
          ),
          // 事务回滚（后悔药）按钮
          IconButton(
            visualDensity: isCompactBar ? VisualDensity.compact : null,
            padding: isCompactBar ? const EdgeInsets.all(6) : null,
            constraints: isCompactBar ? const BoxConstraints(minWidth: 34, minHeight: 34) : null,
            tooltip: 'AI 批量操作事务与一键回滚',
            onPressed: () => _showTransactionsSheet(context),
            icon: Badge(
              isLabelVisible: chatProv.transactions
                  .where((t) => t.status == 'APPLIED')
                  .isNotEmpty,
              smallSize: 7,
              backgroundColor: AppColors.accentCyan,
              child: const Icon(Icons.undo_rounded),
            ),
          ),
          // 历史对话列表
          IconButton(
            visualDensity: isCompactBar ? VisualDensity.compact : null,
            padding: isCompactBar ? const EdgeInsets.all(6) : null,
            constraints: isCompactBar ? const BoxConstraints(minWidth: 34, minHeight: 34) : null,
            tooltip: '历史会话列表',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => _showSessionsSheet(context),
          ),
          // 新建会话
          IconButton(
            visualDensity: isCompactBar ? VisualDensity.compact : null,
            padding: isCompactBar ? const EdgeInsets.all(6) : null,
            constraints: isCompactBar ? const BoxConstraints(minWidth: 34, minHeight: 34) : null,
            tooltip: '开启新对话',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () => chatProv.startNewSession(),
          ),
          // 模型与 Webhook 设置
          IconButton(
            visualDensity: isCompactBar ? VisualDensity.compact : null,
            padding: isCompactBar ? const EdgeInsets.all(6) : null,
            constraints: isCompactBar ? const BoxConstraints(minWidth: 34, minHeight: 34) : null,
            tooltip: '配置服务端 AI 模型与主动事件 Webhook',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => _showLlmAndWebhookConfigDialog(context),
          ),
        ],
      ),
      body: !conn.isConnected
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('尚未连接至 Nasio 服务端'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => HomeScaffold.switchToTab(context, 5),
                    icon: const Icon(Icons.settings_rounded),
                    label: const Text('前往设置连接'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // 1. 顶部待审批高危操作提醒横幅 (Human-in-the-Loop)
                if (chatProv.pendingApprovals.isNotEmpty)
                  _buildPendingApprovalBanner(context, chatProv.pendingApprovals.first),

                // 2. 聊天消息流或空状态引导
                Expanded(
                  child: chatProv.messages.isEmpty
                      ? _buildEmptyGuide(context, isLlmEnabled)
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          itemCount: chatProv.messages.length + (chatProv.isSending ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == chatProv.messages.length) {
                              return _buildTypingIndicator(context);
                            }
                            final msg = chatProv.messages[index];
                            return _buildMessageBubble(context, msg);
                          },
                        ),
                ),

                // 3. 错误提示条
                if (chatProv.error != null)
                  Container(
                    width: double.infinity,
                    color: AppColors.errorRed.withValues(alpha: 0.12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 16, color: AppColors.errorRed),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            chatProv.error!,
                            style: const TextStyle(fontSize: 12, color: AppColors.errorRed),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 4. 底部输入栏
                _buildInputBar(context, chatProv.isSending),
              ],
            ),
    );
  }

  Widget _buildPendingApprovalBanner(BuildContext context, ApprovalItem item) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningOrange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warningOrange.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gpp_maybe_rounded, color: AppColors.warningOrange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '待审批高危操作：${item.title}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              TextButton(
                onPressed: () => _showApprovalsDialog(context),
                child: const Text('查看详情'),
              ),
            ],
          ),
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(item.description, style: const TextStyle(fontSize: 12)),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await context.read<ChatProvider>().decideApproval(
                        approvalId: item.approvalId,
                        approved: false,
                        comment: '客户端用户手动驳回',
                      );
                },
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('驳回操作'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.successGreen),
                onPressed: () async {
                  await context.read<ChatProvider>().decideApproval(
                        approvalId: item.approvalId,
                        approved: true,
                        comment: '客户端用户已批准执行',
                      );
                },
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('批准执行'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyGuide(BuildContext context, bool isLlmEnabled) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryBlue.withValues(alpha: 0.2),
                      AppColors.accentCyan.withValues(alpha: 0.2),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 42,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Nasio 智能副驾驶 (AI Copilot)',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                isLlmEnabled
                    ? '服务端大模型 Agent Loop 已激活。直接输入自然语言指令，AI 将自主组合调用 30+ 项 NAS 工具并在后台安全执行。'
                    : '支持 Token 极省的目录结构摘要、样本嗅探、去广告垃圾清理及操作事务一键回滚。点击下方快捷指令即可体验：',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: _quickPrompts.map((item) {
                  final Color c = item['color'] as Color;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _handleSend(item['prompt'] as String),
                    child: Container(
                      width: 280,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: c.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(item['icon'] as IconData, color: c, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['label'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item['prompt'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).textTheme.bodySmall?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessageItem msg) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.15),
              child: const Icon(Icons.smart_toy_rounded, size: 18, color: AppColors.primaryBlue),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  // 工具调用轨迹折叠卡片
                  if (!isUser && msg.toolCalls.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildToolCallsTraceCard(context, msg.toolCalls),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? AppColors.primaryBlue
                          : Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: isUser
                          ? null
                          : Border.all(
                              color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
                            ),
                    ),
                    child: SelectableText(
                      msg.content,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: isUser
                            ? Colors.white
                            : Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 10),
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.accentCyan.withValues(alpha: 0.18),
              child: const Icon(Icons.person_rounded, size: 18, color: AppColors.accentCyan),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolCallsTraceCard(BuildContext context, List<ToolCallTraceItem> calls) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          visualDensity: VisualDensity.compact,
          leading:
              const Icon(Icons.build_circle_outlined, size: 18, color: AppColors.primaryBlue),
          title: Text(
            '已调度 ${calls.length} 项 NAS 工具 (${calls.map((c) => c.toolName).join(", ")})',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          children: calls.map((tc) {
            final isOk = tc.status == 'SUCCESS';
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isOk ? Icons.check_circle_rounded : Icons.error_rounded,
                        size: 14,
                        color: isOk ? AppColors.successGreen : AppColors.errorRed,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          tc.toolName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${tc.durationMs} ms',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                  if (tc.arguments.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '入参: ${jsonEncode(tc.arguments)}',
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ],
                  if (tc.resultPreview.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SelectableText(
                        tc.resultPreview,
                        maxLines: 6,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.15),
            child: const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'AI 正在思考并调度 NAS 工具...',
            style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(BuildContext context, bool isSending) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              enabled: !isSending,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSend(),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: isSending ? null : () => _handleSend(),
            icon: isSending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded, size: 18),
            label: const Text('发送'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 弹窗 1：AI 批量操作事务与一键原子回滚 (Undo Engine)
  // ==========================================
  void _showTransactionsSheet(BuildContext context) {
    context.read<ChatProvider>().loadTransactions();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Consumer<ChatProvider>(
          builder: (ctx, prov, _) {
            final list = prov.transactions;
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.65,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              builder: (_, scrollController) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.undo_rounded, color: AppColors.accentCyan),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'AI 操作事务记录与一键回滚 (后悔药)',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded),
                            onPressed: () => prov.loadTransactions(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '每次批量文件整理、重命名、目录打平、多季剧集整理及软删除均会自动生成原子事务，支持一键逆向恢复。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      const Divider(height: 20),
                      Expanded(
                        child: list.isEmpty
                            ? const Center(child: Text('暂无批量操作事务记录'))
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: list.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (_, idx) {
                                  final tx = list[idx];
                                  final isApplied = tx.status == 'APPLIED';
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).cardColor,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Theme.of(context).dividerColor,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.primaryBlue
                                                          .withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      tx.operationType,
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: AppColors.primaryBlue,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    tx.transactionId,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontFamily: 'monospace',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                tx.summary,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '移动文件: ${tx.movementsCount} 项 | 软删除至回收站: ${tx.trashCount} 项 | 时间: ${Formatters.formatTimestamp(tx.createdAt)}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.color,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        isApplied
                                            ? FilledButton.tonalIcon(
                                                onPressed: () async {
                                                  final res = await prov
                                                      .rollbackTransaction(tx.transactionId);
                                                  if (ctx.mounted) {
                                                    final ok = res['success'] == true;
                                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          ok
                                                              ? '已成功回滚事务 ${tx.transactionId} (恢复移动 ${res['restored_movements_count']} 项，恢复回收站 ${res['restored_trash_count']} 项)'
                                                              : '回滚失败: ${res['error'] ?? res['errors']}',
                                                        ),
                                                      ),
                                                    );
                                                    context.read<TrashProvider>().loadTrash();
                                                  }
                                                },
                                                icon: const Icon(Icons.undo_rounded, size: 16),
                                                label: const Text('原子回滚'),
                                              )
                                            : Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Text(
                                                  '已回滚',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ==========================================
  // 弹窗 2：高危操作人机协同审批列表
  // ==========================================
  void _showApprovalsDialog(BuildContext context) {
    context.read<ChatProvider>().loadApprovals();
    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer<ChatProvider>(
          builder: (ctx, prov, _) {
            final list = prov.approvals;
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.verified_user_outlined, color: AppColors.warningOrange),
                  SizedBox(width: 8),
                  Text('高危操作人机协同审批'),
                ],
              ),
              content: SizedBox(
                width: 560,
                height: 400,
                child: list.isEmpty
                    ? const Center(child: Text('当前没有高危操作审批请求'))
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (_, idx) {
                          final item = list[idx];
                          final isPending = item.status == 'PENDING';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              item.title,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (item.description.isNotEmpty) Text(item.description),
                                if (item.diffPreview.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.diffPreview,
                                      maxLines: 5,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  '状态: ${item.status} | 时间: ${Formatters.formatTimestamp(item.createdAt)}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                            trailing: isPending
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: '驳回',
                                        icon: const Icon(Icons.close, color: AppColors.errorRed),
                                        onPressed: () => prov.decideApproval(
                                          approvalId: item.approvalId,
                                          approved: false,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '批准执行',
                                        icon: const Icon(
                                          Icons.check_circle,
                                          color: AppColors.successGreen,
                                        ),
                                        onPressed: () => prov.decideApproval(
                                          approvalId: item.approvalId,
                                          approved: true,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    item.status,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: item.status == 'APPROVED'
                                          ? AppColors.successGreen
                                          : Colors.grey,
                                    ),
                                  ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
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

  // ==========================================
  // 弹窗 3：历史会话管理抽屉
  // ==========================================
  void _showSessionsSheet(BuildContext context) {
    final chatProv = context.read<ChatProvider>();
    chatProv.loadSessions();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Consumer<ChatProvider>(
          builder: (ctx, prov, _) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.history_rounded, color: AppColors.primaryBlue),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '历史对话会话',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          prov.startNewSession();
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('新对话'),
                      ),
                    ],
                  ),
                  const Divider(),
                  Flexible(
                    child: prov.sessions.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: Text('暂无历史会话')),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: prov.sessions.length,
                            itemBuilder: (_, idx) {
                              final s = prov.sessions[idx];
                              final selected = s.sessionId == prov.currentSessionId;
                              return ListTile(
                                selected: selected,
                                leading: const Icon(Icons.chat_bubble_outline_rounded),
                                title: Text(
                                  s.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${s.messageCount} 条消息 · ${Formatters.formatTimestamp(s.updatedAt)}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  onPressed: () => prov.deleteSession(s.sessionId),
                                ),
                                onTap: () {
                                  prov.selectSession(s.sessionId);
                                  Navigator.pop(ctx);
                                },
                              );
                            },
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

  // ==========================================
  // 弹窗 4：服务端托管 AI 大模型与主动事件 Webhook 配置
  // ==========================================
  void _showLlmAndWebhookConfigDialog(BuildContext context) {
    final storageProv = context.read<StorageProvider>();
    final llmCfg = storageProv.config?.llm ?? {};
    final webhookCfg = storageProv.config?.webhook ?? {};

    bool llmEnabled = llmCfg['enabled'] == true;
    String provider = llmCfg['provider']?.toString() ?? 'openai_compatible';
    final baseUrlCtrl = TextEditingController(
      text: llmCfg['base_url']?.toString() ?? 'https://api.deepseek.com/v1',
    );
    final apiKeyCtrl = TextEditingController(
      text: llmCfg['api_key']?.toString() ?? '',
    );
    final modelCtrl = TextEditingController(
      text: llmCfg['model']?.toString() ?? 'deepseek-chat',
    );

    bool webhookEnabled = webhookCfg['enabled'] == true;
    final webhookUrlCtrl = TextEditingController(
      text: webhookCfg['url']?.toString() ?? '',
    );
    final webhookSecretCtrl = TextEditingController(
      text: webhookCfg['secret']?.toString() ?? '',
    );

    String? testResultMsg;
    bool isTesting = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.psychology_rounded, color: AppColors.primaryBlue),
                  SizedBox(width: 8),
                  Expanded(child: Text('服务端 AI 大模型与事件总线配置')),
                ],
              ),
              content: SizedBox(
                width: 540,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '启用服务端托管大模型 (Server-side Agent)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: const Text(
                          '在 NAS 服务端本地完成多步工具调用循环，手机锁屏或切后台不中断',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: llmEnabled,
                        onChanged: (v) => setDialogState(() => llmEnabled = v),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: ['openai_compatible', 'ollama'].contains(provider)
                            ? provider
                            : 'openai_compatible',
                        decoration: const InputDecoration(
                          labelText: '接口协议 / 供应商类型',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'openai_compatible',
                            child: Text('OpenAI 兼容接口 (DeepSeek / OpenAI / 硅基流动 / 通义千问)'),
                          ),
                          DropdownMenuItem(
                            value: 'ollama',
                            child: Text('本地 Ollama (内网免 Key，如 http://192.168.1.x:11434/v1)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() {
                              provider = v;
                              if (v == 'ollama' && baseUrlCtrl.text.contains('deepseek')) {
                                baseUrlCtrl.text = 'http://127.0.0.1:11434/v1';
                                modelCtrl.text = 'qwen2.5:14b';
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: baseUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'API Base URL',
                          hintText: 'https://api.deepseek.com/v1',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: modelCtrl,
                              decoration: const InputDecoration(
                                labelText: '模型名称 (Model)',
                                hintText: 'deepseek-chat / gpt-4o-mini',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: apiKeyCtrl,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'API Key (Ollama 可留空)',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: isTesting
                              ? null
                              : () async {
                                  setDialogState(() {
                                    isTesting = true;
                                    testResultMsg = '正在测试模型连通性...';
                                  });
                                  try {
                                    final res = await ApiService.instance.testLlmConnection(
                                      baseUrl: baseUrlCtrl.text.trim(),
                                      apiKey: apiKeyCtrl.text.trim(),
                                      model: modelCtrl.text.trim(),
                                      provider: provider,
                                    );
                                    setDialogState(() {
                                      if (res['success'] == true) {
                                        testResultMsg =
                                            '✅ 模型连通正常 (${res['latency_ms']} ms)，回复: ${res['reply']}';
                                      } else {
                                        testResultMsg = '❌ 模型测试失败: ${res['error']}';
                                      }
                                    });
                                  } catch (e) {
                                    setDialogState(() {
                                      testResultMsg =
                                          '❌ 测试异常: ${Formatters.formatErrorMessage(e)}';
                                    });
                                  } finally {
                                    setDialogState(() => isTesting = false);
                                  }
                                },
                          icon: const Icon(Icons.network_check_rounded, size: 16),
                          label: const Text('测试大模型连通性'),
                        ),
                      ),
                      const Divider(height: 20),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '启用主动事件 Webhook 广播 (Proactive Agent Triggers)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: const Text(
                          '当下载完成、RSS 命中新番或发起审批时，主动向 Dify / 外部智能体推送事件',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: webhookEnabled,
                        onChanged: (v) => setDialogState(() => webhookEnabled = v),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: webhookUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Webhook 接收 URL',
                          hintText: 'https://your-agent-gateway/webhook',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: webhookSecretCtrl,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'HMAC 签名密钥 Secret (选填)',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: isTesting
                                ? null
                                : () async {
                                    setDialogState(() {
                                      isTesting = true;
                                      testResultMsg = '正在发送测试 Webhook...';
                                    });
                                    try {
                                      final res =
                                          await ApiService.instance.testWebhookConnection(
                                        url: webhookUrlCtrl.text.trim(),
                                        secret: webhookSecretCtrl.text.trim(),
                                      );
                                      setDialogState(() {
                                        testResultMsg = res['success'] == true
                                            ? '✅ Webhook 推送成功 (HTTP ${res['status_code']})'
                                            : '❌ Webhook 推送失败: ${res['error'] ?? res['status_code']}';
                                      });
                                    } catch (e) {
                                      setDialogState(() {
                                        testResultMsg =
                                            '❌ Webhook 异常: ${Formatters.formatErrorMessage(e)}';
                                      });
                                    } finally {
                                      setDialogState(() => isTesting = false);
                                    }
                                  },
                            icon: const Icon(Icons.send_rounded, size: 15),
                            label: const Text('测试推送'),
                          ),
                        ],
                      ),
                      if (testResultMsg != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                          child: Text(
                            testResultMsg!,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final ok = await ApiService.instance.updateConfig({
                      'llm': {
                        'enabled': llmEnabled,
                        'provider': provider,
                        'base_url': baseUrlCtrl.text.trim(),
                        'api_key': apiKeyCtrl.text.trim(),
                        'model': modelCtrl.text.trim(),
                      },
                      'webhook': {
                        'enabled': webhookEnabled,
                        'url': webhookUrlCtrl.text.trim(),
                        'secret': webhookSecretCtrl.text.trim(),
                      },
                    });
                    if (ctx.mounted) {
                      await storageProv.loadConfig();
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok ? '服务端 AI 模型与 Webhook 配置已保存并热生效' : '保存失败'),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('保存并热生效'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
