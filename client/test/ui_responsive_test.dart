import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nasio_client/app.dart';
import 'package:nasio_client/models/agent_task_model.dart';
import 'package:nasio_client/models/app_version_model.dart';
import 'package:nasio_client/models/config_model.dart';
import 'package:nasio_client/models/downloader_config_model.dart';
import 'package:nasio_client/models/missing_mcp_model.dart';
import 'package:nasio_client/models/task_model.dart';
import 'package:nasio_client/models/trash_model.dart';
import 'package:nasio_client/providers/agent_task_provider.dart';
import 'package:nasio_client/models/user_model.dart';
import 'package:nasio_client/providers/connection_provider.dart';
import 'package:nasio_client/providers/missing_mcp_provider.dart';
import 'package:nasio_client/providers/storage_provider.dart';
import 'package:nasio_client/providers/task_provider.dart';
import 'package:nasio_client/providers/theme_provider.dart';
import 'package:nasio_client/providers/trash_provider.dart';
import 'package:nasio_client/providers/update_provider.dart';
import 'package:nasio_client/providers/user_provider.dart';
import 'package:nasio_client/providers/home_layout_provider.dart';
import 'package:nasio_client/providers/rss_provider.dart';
import 'package:nasio_client/providers/chat_provider.dart';
import 'package:nasio_client/models/rss_model.dart';
import 'package:nasio_client/models/chat_model.dart';
import 'package:nasio_client/services/storage_service.dart';
import 'package:nasio_client/views/connection/connection_view.dart';
import 'package:nasio_client/views/connection/mcp_config_section.dart';
import 'package:nasio_client/views/connection/skills_config_section.dart';

class FakeConnectionProvider extends ConnectionProvider {
  bool mockConnected = true;
  @override
  bool get isConnected => mockConnected;
  @override
  String get host => '192.168.1.100';
  @override
  int get port => 8086;
  @override
  String get token => 'secret-token-1234567890';
  @override
  bool get isHttps => false;
  @override
  Future<void> refreshHealth() async {}
}

class FakeStorageProvider extends StorageProvider {
  @override
  bool get isLoading => false;

  @override
  List<StoragePoolInfo> get storagePools => [
        StoragePoolInfo(
          path: '/volume1/nasio_media_storage_pool',
          totalBytes: 16 * 1024 * 1024 * 1024 * 1024,
          usedBytes: 13 * 1024 * 1024 * 1024 * 1024,
          freeBytes: 3 * 1024 * 1024 * 1024 * 1024,
          usagePercent: 81.25,
          exists: true,
        ),
        StoragePoolInfo(
          path: '/volume2/backup_archive',
          totalBytes: 8 * 1024 * 1024 * 1024 * 1024,
          usedBytes: 2 * 1024 * 1024 * 1024 * 1024,
          freeBytes: 6 * 1024 * 1024 * 1024 * 1024,
          usagePercent: 25.0,
          exists: true,
        ),
      ];

  @override
  List<String> get allowedPaths => [
        '/volume1/Download',
        '/volume1/Media/Movies_4K_HDR_Remux_Collection',
        '/volume2/Backup/Personal_Documents_Archive',
      ];

  @override
  String get trashDir => '/volume1/nasio/.trash_recovery_partition';

  @override
  int get trashRetentionDays => 30;

  @override
  Future<void> loadConfig() async {}
}

class FakeTaskProvider extends TaskProvider {
  final List<TaskItem> _mockTasks = [
    TaskItem(
      taskId: 'qb_10001_abcdef',
      taskType: 'DOWNLOAD',
      status: TaskStatus.running,
      progress: 64.5,
      createdAt: 1759000000,
      updatedAt: 1759000500,
      detail: {
        'name': 'Ubuntu-24.04.2-Desktop-amd64-ISO-Official-Release.iso',
        'engine': 'qbittorrent',
        'speed': '↓ 45.8 MB/s',
        'downloaded_bytes': 2952790016,
        'total_bytes': 4578096128,
        'eta_seconds': 35,
        'save_path': '/volume1/Download/ISO_Images',
        'url': 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef',
      },
    ),
    TaskItem(
      taskId: 'qb_10002_paused',
      taskType: 'DOWNLOAD',
      status: TaskStatus.paused,
      progress: 32.0,
      createdAt: 1758990000,
      updatedAt: 1758995000,
      detail: {
        'name': '4K.HDR.Demo.Video.2160p.HEVC.Atmos.mkv',
        'engine': 'qbittorrent',
        'speed': '0 B/s',
        'downloaded_bytes': 3435973836,
        'total_bytes': 10737418240,
        'eta_seconds': 0,
        'save_path': '/volume1/Media/Movies',
      },
    ),
    TaskItem(
      taskId: 'dl_10003_failed',
      taskType: 'DOWNLOAD',
      status: TaskStatus.failed,
      progress: 12.4,
      createdAt: 1758980000,
      updatedAt: 1758981000,
      error: '远端服务器连接超时 (HTTP 504 Gateway Timeout)',
      detail: {
        'name': 'broken-archive-package-v2.0.tar.gz',
        'engine': 'aria2',
        'speed': '0 B/s',
        'downloaded_bytes': 104857600,
        'total_bytes': 838860800,
        'save_path': '/volume1/Download',
      },
    ),
    TaskItem(
      taskId: 'scan_10004_done',
      taskType: 'DUPLICATE_SCAN',
      status: TaskStatus.completed,
      progress: 100.0,
      createdAt: 1758970000,
      updatedAt: 1758972000,
      detail: {
        'name': '全盘三级漏斗哈希查重 (/volume1/Media)',
        'save_path': '/volume1/Media',
      },
    ),
  ];

  @override
  List<TaskItem> get allTasks => _mockTasks;

  @override
  DownloaderConfigModel? get downloaderConfig => DownloaderConfigModel(
        defaultEngine: 'qbittorrent',
        allowedPaths: ['/volume1/Download', '/volume1/Media'],
        qbittorrent: QbittorrentConfig(
          enabled: true,
          url: 'http://192.168.1.100:8080',
          defaultCategory: 'nasio',
          downloadLimitKb: 0,
          uploadLimitKb: 2048,
          defaultSavePath: '/volume1/Download',
          maxActiveDownloads: 5,
          maxActiveTorrents: 10,
          queueingEnabled: true,
        ),
      );

  @override
  Map<String, dynamic>? get downloaderStatus => {
        'status': 'ok',
        'connected': true,
        'version': 'v5.0.3',
        'api_version': '2.11.2',
        'total_torrents': 18,
        'active_torrents': 2,
      };

  @override
  Future<void> loadTasks({bool silent = false}) async {}

  @override
  Future<void> loadDownloaderConfig() async {}

  @override
  Future<void> testDownloader([String type = 'qbittorrent']) async {}
}

class FakeAgentTaskProvider extends AgentTaskProvider {
  late final List<AgentTaskModel> _mockTasks = [
    AgentTaskModel(
      agentTaskId: 'agent_task_20260928_001',
      title: '下载资料库季度归档与全量三级哈希去重清理',
      description: '自动扫描 /volume1/Download 目录下所有重复视频与归档压缩包，提取有效文件并移入防灾回收站。',
      status: 'COMPLETED',
      progress: 100.0,
      totalSteps: 3,
      currentStep: 3,
      createdAt: 1759010000,
      updatedAt: 1759010600,
      steps: [
        AgentTaskStep(
          stepIndex: 1,
          stepName: '扫描目标目录结构与大文件分布',
          status: 'COMPLETED',
          progress: 100.0,
          logMessage: '共发现 1,248 个媒体与文档文件，总计 428.5 GB',
          timestamp: 1759010100,
        ),
        AgentTaskStep(
          stepIndex: 2,
          stepName: '执行三级漏斗哈希查重与压缩包智能解压',
          status: 'COMPLETED',
          progress: 100.0,
          logMessage: '定位到 14 组完全重复文件，释放空间 18.4 GB',
          timestamp: 1759010350,
        ),
        AgentTaskStep(
          stepIndex: 3,
          stepName: '按扩展名及年份归档并软删除冗余副本',
          status: 'COMPLETED',
          progress: 100.0,
          logMessage: '已安全移入 .trash 回收站并生成原路径恢复索引',
          timestamp: 1759010600,
        ),
      ],
      subActions: [
        AgentSubAction(
          actionType: 'FILE_ORGANIZE',
          actionId: 'org_001',
          summary: '归档 86 个视频文件至 /volume1/Media/2026',
          status: 'COMPLETED',
          timestamp: 1759010400,
        ),
        AgentSubAction(
          actionType: 'TRASH_DELETE',
          actionId: 'trash_002',
          summary: '软删除 14 个重复大文件至防灾回收站',
          status: 'COMPLETED',
          timestamp: 1759010550,
        ),
      ],
      result: '归档完成：整理文件 86 项，清理冗余副本 14 项（释放 18.4 GB 空间）。',
      promptTemplate:
          '请扫描 /volume1/Download 目录，使用 find_duplicate_files 查找重复文件并移入回收站，随后按文件类型分类归档。',
    ),
    AgentTaskModel(
      agentTaskId: 'agent_task_20260928_002',
      title: '自动拉取最新 Linux 发行版镜像并校验 SHA256',
      description: '正在通过 qBittorrent 引擎高速下载 Ubuntu 24.04.2 镜像。',
      status: 'RUNNING',
      progress: 65.0,
      totalSteps: 3,
      currentStep: 2,
      createdAt: 1759020000,
      updatedAt: 1759020300,
      steps: [
        AgentTaskStep(
          stepIndex: 1,
          stepName: '创建磁力链下载任务',
          status: 'COMPLETED',
          progress: 100.0,
          logMessage: '已下发至 qBittorrent (ID: qb_10001_abcdef)',
          timestamp: 1759020050,
        ),
      ],
      subActions: [],
    ),
  ];

  AgentTaskModel? _sel;

  @override
  List<AgentTaskModel> get tasks => _mockTasks;

  @override
  AgentTaskModel? get selectedTask => _sel ?? _mockTasks.first;

  @override
  void selectTask(AgentTaskModel? task) {
    _sel = task;
    notifyListeners();
  }

  @override
  Future<void> loadTasks() async {}
}

class FakeMissingMcpProvider extends MissingMcpProvider {
  @override
  List<MissingMcpToolModel> get items => [
        MissingMcpToolModel(
          id: 'missing_001',
          toolName: 'transcode_video_hardware_hevc_to_av1',
          description: '调用 NAS Intel QSV 硬件加速转码器将 4K 视频批量压缩为 AV1 编码格式',
          suggestedParameters: '{"source_path": "string", " preset": "qsv_av1_10bit", "crf": 24}',
          scenario: '用户在整理家庭 4K 摄像机原片时希望自动转码瘦身节省存储池空间',
          agentTaskId: 'agent_task_20260928_001',
          createdAt: 1759015000,
        ),
      ];

  @override
  Future<void> loadItems() async {}
}

class FakeTrashProvider extends TrashProvider {
  @override
  List<TrashItem> get items => [
        TrashItem(
          fileId: 'trash_file_001',
          name: 'Duplicate_Movie_Remux_2160p_BluRay_x265_10bit.mkv',
          originalPath: '/volume1/Media/Movies/2026_Collection/Duplicate_Movie_Remux_2160p_BluRay_x265_10bit.mkv',
          deletedAt: '2026-09-28 18:30:00',
          sizeBytes: 18454937600,
          isDir: false,
        ),
        TrashItem(
          fileId: 'trash_dir_002',
          name: 'Old_Temporary_Unpack_Folder_Backup',
          originalPath: '/volume1/Download/Temp/Old_Temporary_Unpack_Folder_Backup',
          deletedAt: '2026-09-28 19:00:00',
          sizeBytes: 536870912,
          isDir: true,
        ),
      ];

  @override
  int get total => 45;

  @override
  int get page => 1;

  @override
  int get limit => 20;

  @override
  Future<void> loadTrash({int? page, String? keyword}) async {}
}

class FakeUpdateProvider extends UpdateProvider {
  @override
  String get currentVersion => '1.0.0+26';

  @override
  String get giteaUrl => 'http://192.168.1.100:3000';

  @override
  bool get hasUpdate => true;

  @override
  AppVersionModel? get latestRelease => AppVersionModel(
        id: 99,
        name: 'v1.0.27',
        version: '1.0.27',
        htmlUrl: 'http://192.168.1.100:3000/test_user/nasio/releases/tag/v1.0.27',
        createdAt: DateTime(2026, 9, 28, 19, 0),
        files: const [
          PackageFileModel(
            id: 1,
            name: 'nasio-client-v1.0.27-android-arm64.apk',
            size: 24117248,
            downloadUrl: 'http://192.168.1.100:3000/apk',
          ),
          PackageFileModel(
            id: 2,
            name: 'nasio-client-v1.0.27-windows-x64.zip',
            size: 18874368,
            downloadUrl: 'http://192.168.1.100:3000/win.zip',
          ),
        ],
      );

  @override
  Future<void> init() async {}
}

class FakeUserProvider extends UserProvider {
  @override
  bool get isLoading => false;

  @override
  List<UserModel> get users => [
        UserModel(
          id: 'admin_test_id',
          username: 'admin',
          role: UserRole.admin,
          isMaster: false,
          createdAt: '2026-09-29T00:00:00',
        ),
        UserModel(
          id: 'user_test_id',
          username: 'guest',
          role: UserRole.user,
          isMaster: false,
          createdAt: '2026-09-29T00:00:00',
        ),
      ];

  @override
  Future<void> loadUsers() async {}
}

class FakeRssProvider extends RssProvider {
  @override
  bool get isLoading => false;

  @override
  List<RssSubscriptionModel> get subscriptions => [
        RssSubscriptionModel(
          rssId: 'rss_test_1',
          title: '测试新番订阅',
          feedUrl: 'https://example.com/feed.xml',
          saveDir: '/volume1/Media/Anime',
          filterRules: [
            RssFilterRule(tag: 'title', pattern: '1080p', mode: 'INCLUDE'),
          ],
          checkIntervalMinutes: 15,
          downloadEngine: 'auto',
          enabled: true,
          lastCheckedAt: 1727580000.0,
          totalDownloadedCount: 5,
          downloadedGuids: ['g1', 'g2'],
          downloadHistory: [],
          createdAt: 1727580000.0,
          updatedAt: 1727580000.0,
        ),
      ];

  @override
  Future<void> loadSubscriptions() async {}
}

class FakeChatProvider extends ChatProvider {
  @override
  bool get isLoading => false;

  @override
  List<ChatSessionSummary> get sessions => [
        ChatSessionSummary(
          sessionId: 'sess_test_1',
          title: 'NAS 治理助手会话',
          messageCount: 2,
          lastMessage: '已完成目录结构摘要：共 42 个文件，VIDEO 占比 85%。',
          createdAt: 1759010000.0,
          updatedAt: 1759010500.0,
        ),
      ];

  @override
  String? get currentSessionId => 'sess_test_1';

  @override
  List<ChatMessageItem> get messages => [
        ChatMessageItem(
          id: 'msg_1',
          role: 'user',
          content: '生成 /volume1/Download 的目录结构摘要',
          createdAt: 1759010100.0,
        ),
        ChatMessageItem(
          id: 'msg_2',
          role: 'assistant',
          content: '已完成目录结构摘要：共 42 个文件，VIDEO 占比 85%。',
          createdAt: 1759010150.0,
          mode: 'llm',
          toolCalls: [
            ToolCallTraceItem(
              toolName: 'get_directory_digest',
              arguments: {'directory': '/volume1/Download'},
              resultPreview: '{"status":"success","total_files":42}',
              status: 'SUCCESS',
              durationMs: 18,
            ),
          ],
        ),
      ];

  @override
  List<ApprovalItem> get approvals => [
        ApprovalItem(
          approvalId: 'appr_test_1',
          title: '清理冗余大文件',
          description: '即将移入回收站 14 个重复 MKV 文件 (18.4 GB)',
          diffPreview: '/volume1/Download/dup1.mkv',
          status: 'PENDING',
          decisionComment: '',
          createdAt: 1759010200.0,
        ),
      ];

  @override
  List<ActionTransactionItem> get transactions => [
        ActionTransactionItem(
          transactionId: 'tx_test_1',
          operationType: 'CLEAN_RUBBISH',
          summary: '清理 /volume1/Download 下 6 个垃圾广告文件',
          status: 'APPLIED',
          movementsCount: 0,
          trashCount: 6,
          createdAt: 1759010300.0,
        ),
      ];

  @override
  Future<void> loadAll() async {}

  @override
  Future<void> loadSessions() async {}

  @override
  Future<void> loadTransactions() async {}

  @override
  Future<void> loadApprovals() async {}
}

Widget buildTestApp({bool isConnected = true, ThemeMode themeMode = ThemeMode.dark}) {
  final connProv = FakeConnectionProvider()..mockConnected = isConnected;
  final themeProv = ThemeProvider()..setThemeMode(themeMode);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>.value(value: themeProv),
      ChangeNotifierProvider<ConnectionProvider>.value(value: connProv),
      ChangeNotifierProvider<HomeLayoutProvider>(create: (_) => HomeLayoutProvider()),
      ChangeNotifierProvider<StorageProvider>(create: (_) => FakeStorageProvider()),
      ChangeNotifierProvider<TaskProvider>(create: (_) => FakeTaskProvider()),
      ChangeNotifierProvider<AgentTaskProvider>(create: (_) => FakeAgentTaskProvider()),
      ChangeNotifierProvider<MissingMcpProvider>(create: (_) => FakeMissingMcpProvider()),
      ChangeNotifierProvider<RssProvider>(create: (_) => FakeRssProvider()),
      ChangeNotifierProvider<ChatProvider>(create: (_) => FakeChatProvider()),
      ChangeNotifierProvider<TrashProvider>(create: (_) => FakeTrashProvider()),
      ChangeNotifierProvider<UpdateProvider>(create: (_) => FakeUpdateProvider()),
      ChangeNotifierProvider<UserProvider>(create: (_) => FakeUserProvider()),
    ],
    child: const NasioApp(),
  );
}

Future<void> exerciseAllViews(WidgetTester tester, {required bool isWideScreen}) async {
  await tester.pumpAndSettle();

  // 1. 主页工作台 (DashboardView)
  expect(find.text('主页工作台'), findsOneWidget);
  // 点击添加目录弹窗再关闭
  final addDirBtn = find.text('添加目录');
  if (addDirBtn.evaluate().isNotEmpty) {
    await tester.ensureVisible(addDirBtn);
    await tester.tap(addDirBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  }

  // 点击回收站物理目录一键跳转到回收站并返回主页
  final trashDirTile = find.text('回收站物理目录:');
  if (trashDirTile.evaluate().isNotEmpty) {
    await tester.ensureVisible(trashDirTile);
    await tester.tap(trashDirTile);
    await tester.pumpAndSettle();
    expect(find.textContaining('回收站'), findsWidgets);
    if (isWideScreen) {
      await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('主页')));
    } else {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('主页')));
    }
    await tester.pumpAndSettle();
  }

  // 2. 切换到「下载管理」(TasksView)
  if (isWideScreen) {
    await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('下载管理')));
  } else {
    await tester.tap(find.text('下载'));
  }
  await tester.pumpAndSettle();

  // 切换 TasksView 的 3 个 Tab：进行中 -> 全部任务 -> 已完成 (含清空失败按钮!)
  await tester.tap(
    find.descendant(of: find.byType(TabBar), matching: find.textContaining('全部任务')),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(TabBar), matching: find.textContaining('已完成')),
  );
  await tester.pumpAndSettle();

  // 打开下载参数全局配置弹窗
  final tuneBtn = find.byTooltip('下载参数配置 (限速/默认路径)');
  if (tuneBtn.evaluate().isNotEmpty) {
    await tester.tap(tuneBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  }

  // 打开新建下载任务弹窗
  final createTaskBtn = find.byIcon(Icons.add_link_rounded);
  if (createTaskBtn.evaluate().isNotEmpty) {
    await tester.tap(createTaskBtn.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  }

  // 3. 切换到「智能体任务」(AgentTasksView)
  if (isWideScreen) {
    await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('智能体任务')));
  } else {
    await tester.tap(find.text('智能体'));
  }
  await tester.pumpAndSettle();

  // 如果窄屏或分栏未直接展开详情，点击第一条任务打开详情 BottomSheet
  final firstAgentTask = find.text('下载资料库季度归档与全量三级哈希去重清理');
  if (firstAgentTask.evaluate().length == 1) {
    await tester.tap(firstAgentTask);
    await tester.pumpAndSettle();
    // 关闭 BottomSheet
    if (Navigator.of(tester.element(find.byType(Scaffold).first)).canPop()) {
      Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
      await tester.pumpAndSettle();
    }
  }

  // 切换到「缺失接口上报」Tab
  await tester.tap(
    find.descendant(of: find.byType(TabBar), matching: find.text('缺失接口上报')),
  );
  await tester.pumpAndSettle();

  // 3.2 切换到「AI 副驾驶」(ChatView)
  if (isWideScreen) {
    await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('AI 副驾驶')));
  } else {
    await tester.tap(find.text('副驾驶'));
  }
  await tester.pumpAndSettle();
  expect(find.text('AI 副驾驶'), findsWidgets);

  // 3.5 切换到「RSS 订阅」(RssView)
  if (isWideScreen) {
    await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('RSS 订阅')));
  } else {
    await tester.tap(find.text('订阅'));
  }
  await tester.pumpAndSettle();

  // 打开新建 RSS 订阅弹窗并验证无溢出后关闭
  final addRssBtn = find.text('新建订阅');
  if (addRssBtn.evaluate().isNotEmpty) {
    await tester.tap(addRssBtn.first);
    await tester.pumpAndSettle();
    expect(find.text('新建 RSS 订阅与正则过滤'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  }

  // 4. 切换到「回收站」(TrashView)
  if (isWideScreen) {
    await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('回收站')));
  } else {
    await tester.tap(find.text('回收站'));
  }
  await tester.pumpAndSettle();

  // 5. 切换到「设置」(ConnectionView)
  if (isWideScreen) {
    await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('设置')));
  } else {
    await tester.tap(find.text('设置'));
  }
  await tester.pumpAndSettle();

  Future<void> exerciseUsersSection() async {
    final copyMasterMcpBtn = find.byTooltip('复制当前 Master 的 MCP 配置');
    if (copyMasterMcpBtn.evaluate().isNotEmpty) {
      await tester.ensureVisible(copyMasterMcpBtn.first);
      await tester.tap(copyMasterMcpBtn.first);
      await tester.pumpAndSettle();
      expect(find.textContaining('MCP 配置'), findsWidgets);
      final closeDialogBtn = find.text('关闭');
      if (closeDialogBtn.evaluate().isNotEmpty) {
        await tester.tap(closeDialogBtn.last);
        await tester.pumpAndSettle();
      }
    }
  }

  Future<void> exerciseMcpSection() async {
    final tuneParamBtn = find.text('微调地址/端口');
    if (tuneParamBtn.evaluate().isNotEmpty) {
      await tester.ensureVisible(tuneParamBtn);
      await tester.tap(tuneParamBtn);
      await tester.pumpAndSettle();
    }

    final dropdownFinder = find.byType(DropdownButton<McpAgentType>);
    if (dropdownFinder.evaluate().isNotEmpty) {
      for (final agentTitle in [
        'Claude Desktop / Claude Code',
        'Cursor / Windsurf',
        'Cherry Studio',
        'Dify / 通用端点',
      ]) {
        await tester.ensureVisible(dropdownFinder.first);
        await tester.tap(dropdownFinder.first);
        await tester.pumpAndSettle();

        final itemFinder = find.text(agentTitle).last;
        await tester.tap(itemFinder);
        await tester.pumpAndSettle();
      }
    }

    final expandToolsBtn = find.text('展开查看');
    if (expandToolsBtn.evaluate().isNotEmpty) {
      await tester.ensureVisible(expandToolsBtn);
      await tester.tap(expandToolsBtn);
      await tester.pumpAndSettle();
    }
  }

  Future<void> exerciseSkillsSection() async {
    final searchField = find.byType(TextField);
    if (searchField.evaluate().isNotEmpty) {
      await tester.enterText(searchField.first, 'anime');
      await tester.pumpAndSettle();
      await tester.enterText(searchField.first, '');
      await tester.pumpAndSettle();
    }
  }

  Future<void> exerciseAboutSection() async {
    final updateBtn = find.text('查看并更新');
    if (updateBtn.evaluate().isNotEmpty) {
      await tester.ensureVisible(updateBtn);
      await tester.tap(updateBtn);
      await tester.pumpAndSettle();
      final closeBtn = find.text('稍后再说');
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn);
        await tester.pumpAndSettle();
      }
    }
  }

  // 点击「服务连接」后判断当前 ConnectionView 是分栏模式还是钻取式二级页面模式
  await tester.tap(find.text('服务连接').first);
  await tester.pumpAndSettle();
  final isDrillDownSettings = find.byTooltip('返回设置菜单').evaluate().isNotEmpty;

  if (!isDrillDownSettings) {
    // 宽屏双栏：依次点击左侧二级分类
    await tester.tap(find.text('用户与权限').first);
    await tester.pumpAndSettle();
    await exerciseUsersSection();

    await tester.tap(find.text('MCP 接入').first);
    await tester.pumpAndSettle();
    await exerciseMcpSection();

    await tester.tap(find.text('技能中心').first);
    await tester.pumpAndSettle();
    expect(find.byType(SkillsConfigSection), findsOneWidget);
    await exerciseSkillsSection();

    await tester.tap(find.text('外观偏好').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('关于与更新').first);
    await tester.pumpAndSettle();
    await exerciseAboutSection();
  } else {
    // 窄屏/紧凑平板钻取式测试：依次从二级页面返回并进入下一个二级页面
    await tester.tap(find.byTooltip('返回设置菜单'));
    await tester.pumpAndSettle();

    // 用户与权限
    final userTile = find.text('用户与权限');
    if (userTile.evaluate().isNotEmpty) {
      await tester.tap(userTile);
      await tester.pumpAndSettle();
      await exerciseUsersSection();
      await tester.tap(find.byTooltip('返回设置菜单'));
      await tester.pumpAndSettle();
    }

    // (2) MCP 接入
    await tester.tap(find.text('MCP 接入'));
    await tester.pumpAndSettle();
    await exerciseMcpSection();
    await tester.tap(find.byTooltip('返回设置菜单'));
    await tester.pumpAndSettle();

    // (2.5) 技能中心
    final settingsScrollable0 = find
        .descendant(
          of: find.byType(ConnectionView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('技能中心'),
      100,
      scrollable: settingsScrollable0,
    );
    await tester.ensureVisible(find.text('技能中心'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('技能中心'));
    await tester.pumpAndSettle();
    expect(find.byType(SkillsConfigSection), findsOneWidget);
    await exerciseSkillsSection();
    await tester.tap(find.byTooltip('返回设置菜单'));
    await tester.pumpAndSettle();

    // (3) 外观偏好
    final settingsScrollable = find
        .descendant(
          of: find.byType(ConnectionView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('外观偏好'),
      100,
      scrollable: settingsScrollable,
    );
    await tester.ensureVisible(find.text('外观偏好'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观偏好'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回设置菜单'));
    await tester.pumpAndSettle();

    // (4) 关于与更新
    final settingsScrollable2 = find
        .descendant(
          of: find.byType(ConnectionView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('关于与更新'),
      100,
      scrollable: settingsScrollable2,
    );
    await tester.ensureVisible(find.text('关于与更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于与更新'));
    await tester.pumpAndSettle();
    await exerciseAboutSection();
    await tester.tap(find.byTooltip('返回设置菜单'));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'nasio_connection_history':
          '[{"host":"192.168.1.100","port":8086,"token":"secret","is_https":false,"label":"绿联DXP4800Plus"}]',
    });
    await StorageService.init();
  });

  group('UI 大屏与小屏全场景布局与交互测试', () {
    testWidgets('小屏手机场景 (360x780) 全页面与弹窗渲染无溢出', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp());
      await exerciseAllViews(tester, isWideScreen: false);
    });

    testWidgets('紧凑小屏手机场景 (320x640) 全页面与弹窗渲染无溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp());
      await exerciseAllViews(tester, isWideScreen: false);
    });

    testWidgets('平板临界大屏场景 (720x800) 全页面与弹窗渲染无溢出', (tester) async {
      tester.view.physicalSize = const Size(720, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp());
      await exerciseAllViews(tester, isWideScreen: true);
    });

    testWidgets('中等桌面大屏场景 (840x800) 全页面与弹窗渲染无溢出', (tester) async {
      tester.view.physicalSize = const Size(840, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp());
      await exerciseAllViews(tester, isWideScreen: true);
    });

    testWidgets('标准桌面大屏场景 (1440x900) 全页面与弹窗渲染无溢出', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(themeMode: ThemeMode.light));
      await exerciseAllViews(tester, isWideScreen: true);
    });
  });
}
