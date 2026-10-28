import 'dart:convert';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../models/config_model.dart';
import '../models/downloader_config_model.dart';
import '../models/agent_task_model.dart';
import '../models/missing_mcp_model.dart';
import '../models/task_model.dart';
import '../models/trash_model.dart';
import '../models/user_model.dart';
import '../models/skill_model.dart';
import '../models/rss_model.dart';
import '../models/chat_model.dart';
import 'storage_service.dart';


class ApiService {
  static ApiService? _instance;
  late Dio _dio;

  ApiService.custom([Dio? dio]) {
    _dio = dio ?? Dio();
  }

  ApiService._() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.baseUrl = StorageService.getBaseUrl();
          final authType = StorageService.getAuthType();
          final token = StorageService.getToken();
          final username = StorageService.getUsername();
          final password = StorageService.getPassword();

          if (!options.headers.containsKey('Authorization')) {
            if (authType == AuthType.token && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            } else if (authType == AuthType.credentials) {
              if (token.isNotEmpty) {
                options.headers['Authorization'] = 'Bearer $token';
              } else if (username.isNotEmpty) {
                final creds = base64Encode(utf8.encode('$username:$password'));
                options.headers['Authorization'] = 'Basic $creds';
              }
            } else if (token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) {
          return handler.next(e);
        },
      ),
    );
  }

  static ApiService get instance {
    _instance ??= ApiService._();
    return _instance!;
  }

  /// 服务健康检查
  Future<bool> checkHealth() async {
    try {
      final res = await _dio.get(ApiConstants.pathHealth);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 获取脱敏配置及存储池容量
  Future<ConfigResponse> getConfig() async {
    final res = await _dio.get(ApiConstants.pathConfig);
    return ConfigResponse.fromJson(res.data as Map<String, dynamic>);
  }

  /// 更新业务配置
  Future<bool> updateConfig(Map<String, dynamic> payload) async {
    final res = await _dio.put(ApiConstants.pathConfig, data: payload);
    return res.data['success'] == true;
  }

  /// 添加白名单路径
  Future<bool> addWhitelistPath(String path) async {
    final res = await _dio.post(
      ApiConstants.pathWhitelistAdd,
      data: {'path': path},
    );
    return res.data['success'] == true;
  }

  /// 移除白名单路径
  Future<bool> removeWhitelistPath(String path) async {
    final res = await _dio.post(
      ApiConstants.pathWhitelistRemove,
      data: {'path': path},
    );
    return res.data['success'] == true;
  }

  /// 获取回收站列表
  Future<TrashResponse> getTrashList({
    String? keyword,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _dio.get(
      ApiConstants.pathTrash,
      queryParameters: {
        if (keyword != null && keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
        'page': page,
        'limit': limit,
      },
    );
    return TrashResponse.fromJson(res.data as Map<String, dynamic>);
  }

  /// 原路恢复回收站文件
  Future<bool> restoreTrashFile(String fileId, [String? customDir]) async {
    final res = await _dio.post(
      ApiConstants.pathTrashRestore(fileId),
      data: customDir != null ? {'custom_target_dir': customDir} : null,
    );
    return res.data['success'] == true;
  }

  /// 彻底删除回收站文件
  Future<bool> deleteTrashFile(String fileId) async {
    final res = await _dio.delete(ApiConstants.pathTrashDelete(fileId));
    return res.data['success'] == true;
  }

  /// 清空回收站
  Future<int> emptyTrash() async {
    final res = await _dio.delete(ApiConstants.pathTrash);
    return (res.data['cleared_count'] as num?)?.toInt() ?? 0;
  }

  /// 创建下载任务
  Future<Map<String, dynamic>> createTask({
    required String url,
    required String saveDir,
    String? filename,
  }) async {
    final res = await _dio.post(
      ApiConstants.pathTasks,
      data: {
        'url': url.trim(),
        'save_dir': saveDir.trim(),
        if (filename != null && filename.isNotEmpty) 'filename': filename.trim(),
      },
    );
    return res.data as Map<String, dynamic>;
  }

  /// 获取任务列表
  Future<List<TaskItem>> getTasks({int limit = 100}) async {
    final res = await _dio.get(
      ApiConstants.pathTasks,
      queryParameters: {'limit': limit},
    );
    final list = res.data as List<dynamic>? ?? [];
    return list.map((e) => TaskItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 取消指定任务 (兼容老接口)
  Future<bool> cancelTask(String taskId, {bool deleteFiles = false}) async {
    final res = await _dio.post(ApiConstants.pathTaskCancel(taskId, deleteFiles: deleteFiles));
    return res.data['cancelled'] == true;
  }

  /// 暂停下载任务
  Future<bool> pauseTask(String taskId) async {
    final res = await _dio.post(ApiConstants.pathTaskPause(taskId));
    return res.data['paused'] == true;
  }

  /// 恢复/继续下载任务
  Future<bool> resumeTask(String taskId) async {
    final res = await _dio.post(ApiConstants.pathTaskResume(taskId));
    return res.data['resumed'] == true;
  }

  /// 重新校验种子任务
  Future<bool> recheckTask(String taskId) async {
    final res = await _dio.post(ApiConstants.pathTaskRecheck(taskId));
    return res.data['rechecked'] == true;
  }

  /// 删除任务（可选择是否一并清理本地文件）
  Future<bool> deleteTask(String taskId, {bool deleteFiles = false}) async {
    final res = await _dio.delete(ApiConstants.pathTaskDelete(taskId, deleteFiles: deleteFiles));
    return res.data['deleted'] == true;
  }

  /// 一键清空所有失败任务
  Future<int> clearFailedTasks({bool deleteFiles = false}) async {
    try {
      final res = await _dio.post(ApiConstants.pathTasksClearFailed(deleteFiles: deleteFiles));
      return (res.data['cleared_count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return -1;
    }
  }

  /// 批量暂停下载任务
  Future<bool> batchPauseTasks(List<String> taskIds) async {
    if (taskIds.isEmpty) return true;
    try {
      final res = await _dio.post(
        ApiConstants.pathTasksBatchPause,
        data: {'task_ids': taskIds},
      );
      if (res.data['success'] == true) return true;
    } catch (_) {}
    final results = await Future.wait(taskIds.map((tid) => pauseTask(tid)));
    return results.any((r) => r);
  }

  /// 批量恢复下载任务
  Future<bool> batchResumeTasks(List<String> taskIds) async {
    if (taskIds.isEmpty) return true;
    try {
      final res = await _dio.post(
        ApiConstants.pathTasksBatchResume,
        data: {'task_ids': taskIds},
      );
      if (res.data['success'] == true) return true;
    } catch (_) {}
    final results = await Future.wait(taskIds.map((tid) => resumeTask(tid)));
    return results.any((r) => r);
  }

  /// 批量删除下载任务
  Future<bool> batchDeleteTasks(List<String> taskIds, {bool deleteFiles = false}) async {
    if (taskIds.isEmpty) return true;
    try {
      final res = await _dio.post(
        ApiConstants.pathTasksBatchDelete,
        data: {'task_ids': taskIds, 'delete_files': deleteFiles},
      );
      if (res.data['success'] == true) return true;
    } catch (_) {}
    final results = await Future.wait(taskIds.map((tid) => deleteTask(tid, deleteFiles: deleteFiles)));
    return results.any((r) => r);
  }

  /// 获取下载器限速与全局路径配置
  Future<DownloaderConfigModel> getDownloaderConfig() async {
    final res = await _dio.get(ApiConstants.pathDownloadersConfig);
    return DownloaderConfigModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// 设置下载器限速、并发队列与路径
  Future<bool> setDownloaderConfig({
    int? downloadLimitKb,
    int? uploadLimitKb,
    String? defaultSavePath,
    int? maxActiveDownloads,
    int? maxActiveTorrents,
    String? defaultCategory,
    bool? queueingEnabled,
    bool? autoStopSeeding,
  }) async {
    final res = await _dio.post(
      ApiConstants.pathDownloadersConfig,
      data: {
        if (downloadLimitKb != null) 'download_limit_kb': downloadLimitKb,
        if (uploadLimitKb != null) 'upload_limit_kb': uploadLimitKb,
        if (defaultSavePath != null && defaultSavePath.isNotEmpty)
          'default_save_path': defaultSavePath,
        if (maxActiveDownloads != null) 'max_active_downloads': maxActiveDownloads,
        if (maxActiveTorrents != null) 'max_active_torrents': maxActiveTorrents,
        if (defaultCategory != null) 'default_category': defaultCategory,
        if (queueingEnabled != null) 'queueing_enabled': queueingEnabled,
        if (autoStopSeeding != null) 'auto_stop_seeding': autoStopSeeding,
      },
    );
    return res.data['success'] == true;
  }

  /// 获取 AI Agent 复合长任务列表
  Future<List<AgentTaskModel>> getAgentTasks({String? status, int limit = 50}) async {
    final res = await _dio.get(
      ApiConstants.pathAgentTasks,
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
        'limit': limit,
      },
    );
    final list = res.data as List<dynamic>? ?? [];
    return list.map((e) => AgentTaskModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 取消 AI Agent 任务
  Future<bool> cancelAgentTask(String id) async {
    final res = await _dio.post(ApiConstants.pathAgentTaskCancel(id));
    return res.data['cancelled'] == true;
  }

  /// 删除 AI Agent 任务记录
  Future<bool> deleteAgentTask(String id) async {
    final res = await _dio.delete(ApiConstants.pathAgentTaskDetail(id));
    return res.data['deleted'] == true;
  }

  /// 批量清空已结束（已完成/已失败/已取消）的 AI Agent 任务记录
  Future<int> clearFinishedAgentTasks() async {
    final res = await _dio.delete(ApiConstants.pathAgentTasks);
    return (res.data['cleared_count'] as num?)?.toInt() ?? 0;
  }

  /// 获取所有智能体上报的缺失 MCP 工具诉求记录
  Future<List<MissingMcpToolModel>> getMissingMcpTools({int limit = 100}) async {
    final res = await _dio.get(
      ApiConstants.pathMissingMcpTools,
      queryParameters: {'limit': limit},
    );
    final list = res.data as List<dynamic>? ?? [];
    return list.map((e) => MissingMcpToolModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 删除单条缺失 MCP 工具上报记录
  Future<bool> deleteMissingMcpTool(String id) async {
    final res = await _dio.delete(ApiConstants.pathMissingMcpToolDetail(id));
    return res.data['deleted'] == true;
  }

  /// 批量清空缺失 MCP 工具上报记录
  Future<int> clearMissingMcpTools() async {
    final res = await _dio.delete(ApiConstants.pathMissingMcpTools);
    return (res.data['cleared_count'] as num?)?.toInt() ?? 0;
  }

  /// 测试下载器（qBittorrent / aria2）连通性
  Future<Map<String, dynamic>> testDownloaderConnection([
    String downloaderType = 'qbittorrent',
  ]) async {
    final res = await _dio.post(
      ApiConstants.pathDownloadersTest,
      queryParameters: {'downloader_type': downloaderType},
    );
    return res.data as Map<String, dynamic>;
  }

  // -------------------------------------------------------------
  // 认证与用户权限管理相关接口
  // -------------------------------------------------------------

  /// 通过用户名与密码登录
  Future<LoginResult> login(String username, String password) async {
    final res = await _dio.post(
      ApiConstants.pathAuthLogin,
      data: {
        'username': username.trim(),
        'password': password.trim(),
      },
    );
    return LoginResult.fromJson(res.data as Map<String, dynamic>);
  }

  /// 获取当前登录会话的用户信息
  Future<UserModel> getMe() async {
    final res = await _dio.get(ApiConstants.pathAuthMe);
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// 获取当前生效的 Master Token (需管理员权限)
  Future<String> getMasterToken() async {
    final res = await _dio.get(ApiConstants.pathAuthToken);
    return res.data['master_token']?.toString() ?? '';
  }

  /// 重新生成 Master Token (需管理员权限)
  Future<String> regenerateMasterToken() async {
    final res = await _dio.post(ApiConstants.pathAuthTokenRegenerate);
    return res.data['master_token']?.toString() ?? '';
  }

  /// 获取系统所有配置的用户列表 (需管理员权限)
  Future<List<UserModel>> getUsers() async {
    final res = await _dio.get(ApiConstants.pathAuthUsers);
    final list = res.data['users'] as List<dynamic>? ?? [];
    return list.map((e) => UserModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 创建新用户 (需管理员权限)
  Future<UserModel> createUser({
    required String username,
    required String password,
    required String role,
  }) async {
    final res = await _dio.post(
      ApiConstants.pathAuthUsers,
      data: {
        'username': username.trim(),
        'password': password.trim(),
        'role': role,
      },
    );
    return UserModel.fromJson(res.data['user'] as Map<String, dynamic>);
  }

  /// 更新用户密码或角色 (需管理员权限)
  Future<UserModel> updateUser(
    String userId, {
    String? password,
    String? role,
  }) async {
    final data = <String, dynamic>{};
    if (password != null && password.trim().isNotEmpty) {
      data['password'] = password.trim();
    }
    if (role != null && role.trim().isNotEmpty) {
      data['role'] = role.trim();
    }
    final res = await _dio.put(
      ApiConstants.pathAuthUserDetail(userId),
      data: data,
    );
    return UserModel.fromJson(res.data['user'] as Map<String, dynamic>);
  }

  /// 删除用户 (需管理员权限)
  Future<bool> deleteUser(String userId) async {
    final res = await _dio.delete(ApiConstants.pathAuthUserDetail(userId));
    return res.data['success'] == true;
  }

  /// 为指定用户重新生成专属访问 Token (需管理员权限)
  Future<String> regenerateUserToken(String userId) async {
    final res = await _dio.post(ApiConstants.pathAuthUserTokenRegenerate(userId));
    return res.data['token']?.toString() ?? '';
  }

  /// 获取服务端所有已持久化技能列表
  Future<List<SkillModel>> getSkills({String? keyword}) async {
    final queryParams = <String, dynamic>{};
    if (keyword != null && keyword.trim().isNotEmpty) {
      queryParams['keyword'] = keyword.trim();
    }
    final res = await _dio.get(
      ApiConstants.pathSkills,
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );
    final list = res.data as List<dynamic>;
    return list.map((e) => SkillModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取指定技能详情（含完整 Markdown 与 Frontmatter）
  Future<SkillModel> getSkillDetail(String name) async {
    final res = await _dio.get(ApiConstants.pathSkillDetail(name));
    return SkillModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// 同步/保存技能到服务端
  Future<SkillModel> saveSkill({
    required String name,
    required String description,
    required String content,
    List<String> tags = const [],
    String version = '1.0.0',
  }) async {
    final res = await _dio.post(
      ApiConstants.pathSkills,
      data: {
        'name': name.trim(),
        'description': description.trim(),
        'content': content,
        'tags': tags,
        'version': version,
      },
    );
    return SkillModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// 删除指定技能
  Future<bool> deleteSkill(String name) async {
    final res = await _dio.delete(ApiConstants.pathSkillDetail(name));
    return res.data['deleted'] == true;
  }

  // -------------------------------------------------------------
  // RSS 订阅相关 API
  // -------------------------------------------------------------

  /// 在线预览并测试 RSS 过滤规则
  Future<RssPreviewResponse> previewRssFeed({
    required String feedUrl,
    List<RssFilterRule>? filterRules,
    Map<String, dynamic>? urlExtractRule,
    String? subtitleLanguage,
  }) async {
    final res = await _dio.post(
      ApiConstants.pathRssPreview,
      data: {
        'feed_url': feedUrl,
        if (filterRules != null) 'filter_rules': filterRules.map((e) => e.toJson()).toList(),
        if (urlExtractRule != null) 'url_extract_rule': urlExtractRule,
        if (subtitleLanguage != null && subtitleLanguage.isNotEmpty) 'subtitle_language': subtitleLanguage,
      },
    );
    return RssPreviewResponse.fromJson(res.data as Map<String, dynamic>);
  }

  /// 获取所有 RSS 订阅列表
  Future<List<RssSubscriptionModel>> getRssSubscriptions() async {
    final res = await _dio.get(ApiConstants.pathRss);
    final list = res.data as List<dynamic>;
    return list.map((e) => RssSubscriptionModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取单个 RSS 订阅详情与历史抓取记录
  Future<RssSubscriptionModel> getRssSubscriptionDetail(String rssId) async {
    final res = await _dio.get(ApiConstants.pathRssDetail(rssId));
    return RssSubscriptionModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// 创建 RSS 订阅任务
  Future<RssSubscriptionModel> createRssSubscription({
    required String feedUrl,
    required String saveDir,
    String? title,
    List<RssFilterRule>? filterRules,
    Map<String, dynamic>? urlExtractRule,
    int checkIntervalMinutes = 15,
    String downloadEngine = 'auto',
    List<String>? selectedGuids,
    bool downloadExisting = true,
    String? agentTaskId,
    String? subtitleLanguage,
  }) async {
    final res = await _dio.post(
      ApiConstants.pathRss,
      data: {
        'feed_url': feedUrl,
        'save_dir': saveDir,
        if (title != null && title.isNotEmpty) 'title': title,
        if (filterRules != null) 'filter_rules': filterRules.map((e) => e.toJson()).toList(),
        if (urlExtractRule != null) 'url_extract_rule': urlExtractRule,
        'check_interval_minutes': checkIntervalMinutes,
        'download_engine': downloadEngine,
        if (selectedGuids != null) 'selected_guids': selectedGuids,
        'download_existing': downloadExisting,
        if (agentTaskId != null && agentTaskId.isNotEmpty) 'agent_task_id': agentTaskId,
        if (subtitleLanguage != null && subtitleLanguage.isNotEmpty) 'subtitle_language': subtitleLanguage,
      },
    );
    return RssSubscriptionModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// 更新 RSS 订阅设置
  Future<RssSubscriptionModel> updateRssSubscription({
    required String rssId,
    String? title,
    String? saveDir,
    List<RssFilterRule>? filterRules,
    int? checkIntervalMinutes,
    String? downloadEngine,
    bool? enabled,
    String? subtitleLanguage,
  }) async {
    final res = await _dio.put(
      ApiConstants.pathRssDetail(rssId),
      data: {
        if (title != null) 'title': title,
        if (saveDir != null) 'save_dir': saveDir,
        if (filterRules != null) 'filter_rules': filterRules.map((e) => e.toJson()).toList(),
        if (checkIntervalMinutes != null) 'check_interval_minutes': checkIntervalMinutes,
        if (downloadEngine != null) 'download_engine': downloadEngine,
        if (enabled != null) 'enabled': enabled,
        if (subtitleLanguage != null) 'subtitle_language': subtitleLanguage,
      },
    );
    return RssSubscriptionModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// 删除 RSS 订阅
  Future<bool> deleteRssSubscription(String rssId) async {
    final res = await _dio.delete(ApiConstants.pathRssDetail(rssId));
    return res.data['deleted'] == true;
  }

  /// 立即强制刷新检查 RSS 订阅
  Future<Map<String, dynamic>> refreshRssSubscription(String rssId) async {
    final res = await _dio.post(ApiConstants.pathRssRefresh(rssId));
    return res.data as Map<String, dynamic>;
  }

  /// 切换 RSS 订阅启用/暂停状态
  Future<bool> toggleRssSubscription(String rssId) async {
    final res = await _dio.post(ApiConstants.pathRssToggle(rssId));
    return res.data['enabled'] as bool;
  }

  /// 获取指定 RSS 订阅当前远端的资源条目列表
  Future<RssSubscriptionItemsResponse> getRssSubscriptionItems(String rssId) async {
    final res = await _dio.get(ApiConstants.pathRssItems(rssId));
    return RssSubscriptionItemsResponse.fromJson(res.data as Map<String, dynamic>);
  }

  /// 选摘下载指定的 RSS 资源条目
  Future<RssBatchDownloadResult> downloadRssSubscriptionItems({
    required String rssId,
    required List<RssItemPreview> items,
  }) async {
    final res = await _dio.post(
      ApiConstants.pathRssDownload(rssId),
      data: {
        'items': items.map((e) => e.toDownloadJson()).toList(),
      },
    );
    return RssBatchDownloadResult.fromJson(res.data as Map<String, dynamic>);
  }

  // ==========================================
  // AI Copilot 对话、人机审批与操作事务回滚接口
  // ==========================================

  /// 获取 AI 对话会话列表
  Future<List<ChatSessionSummary>> getChatSessions() async {
    final res = await _dio.get(ApiConstants.pathChatSessions);
    final list = (res.data['sessions'] as List<dynamic>?) ?? [];
    return list
        .map((e) => ChatSessionSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 创建新的 AI 对话会话
  Future<String> createChatSession({String title = '新对话'}) async {
    final res = await _dio.post(
      ApiConstants.pathChatSessions,
      data: {'title': title},
    );
    final sess = res.data['session'] as Map<String, dynamic>? ?? {};
    return sess['session_id']?.toString() ?? '';
  }

  /// 获取指定对话会话的完整消息列表
  Future<List<ChatMessageItem>> getChatSessionMessages(String sessionId) async {
    final res = await _dio.get(ApiConstants.pathChatSessionDetail(sessionId));
    final sess = res.data['session'] as Map<String, dynamic>? ?? {};
    final list = sess['messages'] as List<dynamic>? ?? [];
    return list
        .map((e) => ChatMessageItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 删除对话会话
  Future<bool> deleteChatSession(String sessionId) async {
    final res = await _dio.delete(ApiConstants.pathChatSessionDetail(sessionId));
    return res.data['success'] == true;
  }

  /// 发送消息给服务端托管 AI Agent 并获取回复及工具轨迹
  Future<Map<String, dynamic>> sendChatMessage({
    required String content,
    String? sessionId,
  }) async {
    final res = await _dio.post(
      ApiConstants.pathChatMessages,
      data: {
        'content': content,
        if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
      },
      options: Options(receiveTimeout: const Duration(seconds: 95)),
    );
    return res.data as Map<String, dynamic>;
  }

  /// 测试服务端大模型 API 连通性
  Future<Map<String, dynamic>> testLlmConnection({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String provider,
  }) async {
    final res = await _dio.post(
      ApiConstants.pathChatTestLlm,
      data: {
        'base_url': baseUrl,
        'api_key': apiKey,
        'model': model,
        'provider': provider,
      },
      options: Options(receiveTimeout: const Duration(seconds: 25)),
    );
    return res.data as Map<String, dynamic>;
  }

  /// 测试主动事件 Webhook 连通性
  Future<Map<String, dynamic>> testWebhookConnection({
    required String url,
    required String secret,
  }) async {
    final res = await _dio.post(
      ApiConstants.pathChatTestWebhook,
      data: {
        'url': url,
        'secret': secret,
      },
      options: Options(receiveTimeout: const Duration(seconds: 15)),
    );
    return res.data as Map<String, dynamic>;
  }

  /// 获取人机协同审批列表
  Future<List<ApprovalItem>> getApprovals({String? status}) async {
    final res = await _dio.get(
      ApiConstants.pathChatApprovals,
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    final list = (res.data['approvals'] as List<dynamic>?) ?? [];
    return list
        .map((e) => ApprovalItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 审批决定（同意 / 拒绝）
  Future<bool> decideApproval({
    required String approvalId,
    required bool approved,
    String comment = '',
  }) async {
    final res = await _dio.post(
      ApiConstants.pathChatApprovalDecide(approvalId),
      data: {
        'approved': approved,
        'comment': comment,
      },
    );
    return res.data['success'] == true;
  }

  /// 获取近期 AI 批量操作事务列表
  Future<List<ActionTransactionItem>> getTransactions({int limit = 50}) async {
    final res = await _dio.get(
      ApiConstants.pathChatTransactions,
      queryParameters: {'limit': limit},
    );
    final list = (res.data['transactions'] as List<dynamic>?) ?? [];
    return list
        .map((e) => ActionTransactionItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 一键原子回滚指定的 AI 批量操作事务
  Future<Map<String, dynamic>> rollbackTransaction(String txId) async {
    final res = await _dio.post(ApiConstants.pathChatTransactionRollback(txId));
    return res.data as Map<String, dynamic>;
  }
}



