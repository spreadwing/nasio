import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nasio_client/app.dart';
import 'package:nasio_client/models/config_model.dart';
import 'package:nasio_client/models/task_model.dart';
import 'package:nasio_client/models/trash_model.dart';
import 'package:nasio_client/models/user_model.dart';
import 'package:nasio_client/models/agent_task_model.dart';
import 'package:nasio_client/models/missing_mcp_model.dart';
import 'package:nasio_client/models/rss_model.dart';
import 'package:nasio_client/models/chat_model.dart';
import 'package:nasio_client/providers/agent_task_provider.dart';
import 'package:nasio_client/providers/chat_provider.dart';
import 'package:nasio_client/providers/connection_provider.dart';
import 'package:nasio_client/providers/home_layout_provider.dart';
import 'package:nasio_client/providers/missing_mcp_provider.dart';
import 'package:nasio_client/providers/rss_provider.dart';
import 'package:nasio_client/providers/storage_provider.dart';
import 'package:nasio_client/providers/task_provider.dart';
import 'package:nasio_client/providers/theme_provider.dart';
import 'package:nasio_client/providers/trash_provider.dart';
import 'package:nasio_client/providers/update_provider.dart';
import 'package:nasio_client/providers/user_provider.dart';
import 'package:nasio_client/services/storage_service.dart';
import 'package:nasio_client/views/home_scaffold.dart';
import 'package:nasio_client/views/dashboard/dashboard_view.dart';
import 'package:nasio_client/views/tasks/tasks_view.dart';
import 'package:nasio_client/views/connection/connection_view.dart';

class MockConnectionProvider extends ConnectionProvider {
  @override
  bool get isConnected => true;
  @override
  String get host => '127.0.0.1';
  @override
  int get port => 8086;
  @override
  String get token => 'test-token';
  @override
  Future<void> refreshHealth() async {}
}

class MockStorageProvider extends StorageProvider {
  @override
  bool get isLoading => false;
  @override
  List<StoragePoolInfo> get storagePools => [
        StoragePoolInfo(
          path: '/volume1',
          totalBytes: 1000,
          usedBytes: 500,
          freeBytes: 500,
          usagePercent: 50.0,
          exists: true,
        ),
      ];
  @override
  List<String> get allowedPaths => ['/volume1/downloads'];
  @override
  String get trashDir => '/volume1/.trash';
  @override
  int get trashRetentionDays => 30;
  @override
  Future<void> loadConfig() async {}
}

class MockTaskProvider extends TaskProvider {
  @override
  bool get isLoading => false;
  @override
  List<TaskItem> get allTasks => [];
  @override
  Future<void> loadTasks({bool silent = false}) async {}
}

class MockTrashProvider extends TrashProvider {
  @override
  bool get isLoading => false;
  @override
  List<TrashItem> get items => [];
  @override
  int get total => 0;
  @override
  Future<void> loadTrash({int? page, String? keyword}) async {}
}

class MockAgentTaskProvider extends AgentTaskProvider {
  @override
  bool get isLoading => false;
  @override
  List<AgentTaskModel> get tasks => [];
  @override
  Future<void> loadTasks() async {}
}

class MockRssProvider extends RssProvider {
  @override
  bool get isLoading => false;
  @override
  List<RssSubscriptionModel> get subscriptions => [];
  @override
  Future<void> loadSubscriptions() async {}
}

class MockChatProvider extends ChatProvider {
  @override
  bool get isLoading => false;
  @override
  List<ChatSessionSummary> get sessions => [];
  @override
  List<ChatMessageItem> get messages => [];
  @override
  Future<void> loadSessions() async {}
}

class MockUserProvider extends UserProvider {
  @override
  List<UserModel> get users => [];
  @override
  Future<void> loadUsers() async {}
}

class MockMissingMcpProvider extends MissingMcpProvider {
  @override
  List<MissingMcpToolModel> get items => [];
  @override
  Future<void> loadItems() async {}
}

Widget createTestApp() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ConnectionProvider>(create: (_) => MockConnectionProvider()),
      ChangeNotifierProvider<StorageProvider>(create: (_) => MockStorageProvider()),
      ChangeNotifierProvider<TaskProvider>(create: (_) => MockTaskProvider()),
      ChangeNotifierProvider<TrashProvider>(create: (_) => MockTrashProvider()),
      ChangeNotifierProvider<AgentTaskProvider>(create: (_) => MockAgentTaskProvider()),
      ChangeNotifierProvider<RssProvider>(create: (_) => MockRssProvider()),
      ChangeNotifierProvider<ChatProvider>(create: (_) => MockChatProvider()),
      ChangeNotifierProvider<UserProvider>(create: (_) => MockUserProvider()),
      ChangeNotifierProvider<MissingMcpProvider>(create: (_) => MockMissingMcpProvider()),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<UpdateProvider>(create: (_) => UpdateProvider()),
      ChangeNotifierProvider<HomeLayoutProvider>(create: (_) => HomeLayoutProvider()),
    ],
    child: const NasioApp(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });

  group('返回手势导航测试 (Back Gesture Navigation Tests)', () {
    testWidgets('在主页时 PopScope.canPop 为 true，允许系统退出/最小化', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // 验证主页存在
      expect(find.byType(DashboardView), findsOneWidget);

      // 检查 PopScope 的 canPop 状态
      final popScopeFinder = find.byWidgetPredicate((w) => w is PopScope);
      expect(popScopeFinder, findsOneWidget);
      final PopScope popScope = tester.widget(popScopeFinder);
      expect(popScope.canPop, isTrue, reason: '主页状态下应允许退出/最小化');
    });

    testWidgets('从主页进入子页面后，手势返回回到主页而不是最小化', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // 1. 切换到「任务」子页面 (index 1)
      final dashboardContext = tester.element(find.byType(DashboardView));
      HomeScaffold.switchToTab(dashboardContext, 1);
      await tester.pumpAndSettle();

      // 验证当前处于子页面，PopScope.canPop 为 false（拦截最小化）
      final popScopeFinder = find.byWidgetPredicate((w) => w is PopScope);
      PopScope popScope = tester.widget(popScopeFinder);
      expect(popScope.canPop, isFalse, reason: '子页面状态下应拦截退出/最小化');

      // 2. 模拟手势返回 (调用 Navigator.maybePop)
      final didPop = await Navigator.of(tester.element(find.byType(TasksView))).maybePop();
      expect(didPop, isTrue, reason: 'Navigator 成功消费并处理了 Pop 事件');
      await tester.pumpAndSettle();

      // 3. 验证此时已切换回主页 (canPop 恢复为 true)
      popScope = tester.widget(popScopeFinder);
      expect(popScope.canPop, isTrue, reason: '已成功返回主页，canPop 恢复为 true');
    });

    testWidgets('设置页面进入二级菜单后，手势返回先回设置菜单首页，再次手势返回回到主页', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // 1. 切换到「设置」子页面 (index 5)
      final dashboardContext = tester.element(find.byType(DashboardView));
      HomeScaffold.switchToTab(dashboardContext, 5);
      await tester.pumpAndSettle();

      final popScopeFinder = find.byWidgetPredicate((w) => w is PopScope);
      PopScope popScope = tester.widget(popScopeFinder);
      expect(popScope.canPop, isFalse);

      // 2. 在手机布局下点击首屏可见的「用户与权限」进入钻取式二级页面
      final userTile = find.text('用户与权限');
      expect(userTile, findsOneWidget);
      await tester.tap(userTile);
      await tester.pumpAndSettle();

      // 验证此时进入了二级详情页 (存在「返回设置菜单」按钮)
      expect(find.byTooltip('返回设置菜单'), findsOneWidget);

      // 3. 第一次模拟手势返回：应退回设置菜单首页
      final navContext = tester.element(find.byTooltip('返回设置菜单'));
      final didPop1 = await Navigator.of(navContext).maybePop();
      expect(didPop1, isTrue);
      await tester.pumpAndSettle();

      // 验证已退回到设置菜单首页，「返回设置菜单」消失，但仍在设置页面
      expect(find.byTooltip('返回设置菜单'), findsNothing);
      expect(find.text('用户与权限'), findsOneWidget);
      popScope = tester.widget(popScopeFinder);
      expect(popScope.canPop, isFalse, reason: '仍处于设置菜单首页，尚未退出到主页');

      // 4. 第二次模拟手势返回：应退回主页
      final navContext2 = tester.element(find.byType(ConnectionView));
      final didPop2 = await Navigator.of(navContext2).maybePop();
      expect(didPop2, isTrue);
      await tester.pumpAndSettle();

      // 验证已成功回到主页
      popScope = tester.widget(popScopeFinder);
      expect(popScope.canPop, isTrue, reason: '已成功退回到主页');
    });
  });
}
