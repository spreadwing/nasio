class ApiConstants {
  // 默认 NAS 连接参数
  static const String defaultHost = '127.0.0.1';
  static const int defaultPort = 8000;
  static const String defaultToken = '';

  // REST API 路径
  static const String pathHealth = '/health';
  static const String pathAuthLogin = '/api/v1/auth/login';
  static const String pathAuthMe = '/api/v1/auth/me';
  static const String pathAuthToken = '/api/v1/auth/token';
  static const String pathAuthTokenRegenerate = '/api/v1/auth/token/regenerate';
  static const String pathAuthUsers = '/api/v1/auth/users';
  static String pathAuthUserDetail(String id) => '/api/v1/auth/users/$id';
  static String pathAuthUserTokenRegenerate(String id) => '/api/v1/auth/users/$id/token/regenerate';

  static const String pathConfig = '/api/v1/config';
  static const String pathWhitelistAdd = '/api/v1/config/whitelist/add';
  static const String pathWhitelistRemove = '/api/v1/config/whitelist/remove';
  
  static const String pathTrash = '/api/v1/trash';
  static String pathTrashRestore(String fileId) => '/api/v1/trash/$fileId/restore';
  static String pathTrashDelete(String fileId) => '/api/v1/trash/$fileId';

  static const String pathTasks = '/api/v1/tasks';
  static String pathTasksClearFailed({bool deleteFiles = false}) =>
      '/api/v1/tasks/clear-failed?delete_files=$deleteFiles';
  static const String pathTasksBatchPause = '/api/v1/tasks/batch-pause';
  static const String pathTasksBatchResume = '/api/v1/tasks/batch-resume';
  static const String pathTasksBatchDelete = '/api/v1/tasks/batch-delete';
  static String pathTaskDetail(String taskId) => '/api/v1/tasks/$taskId';
  static String pathTaskCancel(String taskId, {bool deleteFiles = false}) =>
      '/api/v1/tasks/$taskId/cancel?delete_files=$deleteFiles';
  static String pathTaskPause(String taskId) => '/api/v1/tasks/$taskId/pause';
  static String pathTaskResume(String taskId) => '/api/v1/tasks/$taskId/resume';
  static String pathTaskRecheck(String taskId) => '/api/v1/tasks/$taskId/recheck';
  static String pathTaskDelete(String taskId, {bool deleteFiles = false}) =>
      '/api/v1/tasks/$taskId?delete_files=$deleteFiles';

  static const String pathDownloadersTest = '/api/v1/downloaders/test';
  static const String pathDownloadersConfig = '/api/v1/downloaders/config';

  static const String pathAgentTasks = '/api/v1/agent-tasks';
  static String pathAgentTaskDetail(String id) => '/api/v1/agent-tasks/$id';
  static String pathAgentTaskCancel(String id) => '/api/v1/agent-tasks/$id/cancel';

  static const String pathMissingMcpTools = '/api/v1/missing-mcp-tools';
  static String pathMissingMcpToolDetail(String id) => '/api/v1/missing-mcp-tools/$id';

  static const String pathSkills = '/api/v1/skills';
  static String pathSkillDetail(String name) => '/api/v1/skills/$name';

  static const String pathRss = '/api/v1/rss';
  static const String pathRssPreview = '/api/v1/rss/preview';
  static String pathRssDetail(String rssId) => '/api/v1/rss/$rssId';
  static String pathRssRefresh(String rssId) => '/api/v1/rss/$rssId/refresh';
  static String pathRssToggle(String rssId) => '/api/v1/rss/$rssId/toggle';
  static String pathRssItems(String rssId) => '/api/v1/rss/$rssId/items';
  static String pathRssDownload(String rssId) => '/api/v1/rss/$rssId/download';

  static const String pathChatSessions = '/api/v1/chat/sessions';
  static String pathChatSessionDetail(String sessionId) => '/api/v1/chat/sessions/$sessionId';
  static const String pathChatMessages = '/api/v1/chat/messages';
  static const String pathChatTestLlm = '/api/v1/chat/test-llm';
  static const String pathChatTestWebhook = '/api/v1/chat/test-webhook';
  static const String pathChatApprovals = '/api/v1/chat/approvals';
  static String pathChatApprovalDecide(String approvalId) => '/api/v1/chat/approvals/$approvalId/decide';
  static const String pathChatTransactions = '/api/v1/chat/transactions';
  static String pathChatTransactionRollback(String txId) => '/api/v1/chat/transactions/$txId/rollback';

  // WebSocket 实时推送路径
  static const String wsTasksPath = '/api/v1/tasks/ws';

}

