import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nasio_client/models/config_model.dart';
import 'package:nasio_client/models/home_layout_model.dart';
import 'package:nasio_client/providers/connection_provider.dart';
import 'package:nasio_client/providers/home_layout_provider.dart';
import 'package:nasio_client/providers/storage_provider.dart';
import 'package:nasio_client/services/storage_service.dart';
import 'package:nasio_client/views/dashboard/dashboard_view.dart';

class MockConnectionProvider extends ConnectionProvider {
  @override
  bool get isConnected => true;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });

  group('HomeLayoutModel & HomeLayoutConfig Tests', () {
    test('Default layout contains 6 features, 7 nav items and 3 cards', () {
      final config = HomeLayoutDefaults.defaultConfig;
      expect(config.features.length, 6);
      expect(config.navItems.length, 7);
      expect(config.cards.length, 3);
      expect(config.features.every((f) => f.enabled), isTrue);
      expect(config.navItems.every((n) => n.enabled), isTrue);
      expect(config.cards.every((c) => c.enabled), isTrue);
    });

    test('Json serialization and deserialization roundtrip', () {
      final config = HomeLayoutConfig(
        features: [
          HomeLayoutDefaults.defaultFeatures[0].copyWith(enabled: false),
          HomeLayoutDefaults.defaultFeatures[1],
        ],
        navItems: [
          HomeLayoutDefaults.defaultNavItems[0],
          HomeLayoutDefaults.defaultNavItems[1].copyWith(enabled: false),
        ],
        cards: [
          HomeLayoutDefaults.defaultCards[1],
          HomeLayoutDefaults.defaultCards[0].copyWith(enabled: false),
        ],
      );

      final jsonStr = config.toJsonString();
      final parsed = HomeLayoutConfig.fromJsonString(jsonStr);

      expect(parsed.features.firstWhere((f) => f.id == 'tasks').enabled, isFalse);
      expect(parsed.features.firstWhere((f) => f.id == 'agent_tasks').enabled, isTrue);
      expect(parsed.navItems.firstWhere((n) => n.id == 'tasks').enabled, isFalse);
      expect(parsed.cards.first.id, 'sandbox_whitelist');
    });
  });

  group('HomeLayoutProvider Tests', () {
    test('Toggle feature and resetToDefault', () async {
      final provider = HomeLayoutProvider();
      expect(provider.activeFeatures.length, 6);

      provider.toggleFeature('tasks', false);
      expect(provider.activeFeatures.length, 5);
      expect(provider.activeFeatures.any((f) => f.id == 'tasks'), isFalse);

      await provider.resetToDefault();
      expect(provider.activeFeatures.length, 6);
    });

    test('Toggle nav items and enforce minimum 2 active', () async {
      final provider = HomeLayoutProvider();
      expect(provider.activeNavItems.length, 7);

      // Fixed home cannot be toggled off
      final homeToggled = provider.toggleNavItem('home', false);
      expect(homeToggled, isFalse);
      expect(provider.activeNavItems.first.id, 'home');

      // Toggle off 5 items
      expect(provider.toggleNavItem('tasks', false), isTrue);
      expect(provider.toggleNavItem('agent_tasks', false), isTrue);
      expect(provider.toggleNavItem('ai_chat', false), isTrue);
      expect(provider.toggleNavItem('rss', false), isTrue);
      expect(provider.toggleNavItem('trash', false), isTrue);
      expect(provider.activeNavItems.length, 2);

      // Attempt to toggle off 6th item (settings) must fail because at least 2 are required
      expect(provider.toggleNavItem('settings', false), isFalse);
      expect(provider.activeNavItems.length, 2);

      await provider.resetToDefault();
      expect(provider.activeNavItems.length, 7);
    });

    test('Reorder features, nav items and cards', () async {
      final provider = HomeLayoutProvider();
      expect(provider.features.first.id, 'tasks');

      // Move tasks to second position
      provider.reorderFeatures(0, 2);
      expect(provider.features[1].id, 'tasks');

      // Reorder nav items (home stays at index 0)
      provider.reorderNavItems(1, 3);
      expect(provider.navItems[0].id, 'home');
      expect(provider.navItems[2].id, 'tasks');

      // Reorder cards
      expect(provider.cards.first.id, 'storage_pools');
      provider.reorderCards(0, 2);
      expect(provider.cards[1].id, 'storage_pools');
    });
  });

  group('DashboardView & HomeLayoutConfigDialog Widget Tests', () {
    testWidgets('DashboardView displays quick features and allows opening customizer', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      int navigatedTab = -1;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ConnectionProvider>(create: (_) => MockConnectionProvider()),
            ChangeNotifierProvider<StorageProvider>(create: (_) => MockStorageProvider()),
            ChangeNotifierProvider<HomeLayoutProvider>(create: (_) => HomeLayoutProvider()),
          ],
          child: MaterialApp(
            home: DashboardView(
              onNavigateTab: (index) => navigatedTab = index,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header and quick actions
      expect(find.text('主页工作台'), findsOneWidget);
      expect(find.text('下载管理'), findsWidgets);
      expect(find.text('智能体任务'), findsWidgets);
      expect(find.text('RSS 订阅'), findsWidgets);
      expect(find.text('回收站'), findsWidgets);
      expect(find.text('设置'), findsWidgets);

      // Check dashboard cards
      expect(find.text('物理存储池状态'), findsOneWidget);
      expect(find.text('沙箱白名单管控'), findsOneWidget);
      expect(find.text('防灾安全配置'), findsOneWidget);

      // Tap on 下载管理 feature entry
      await tester.tap(find.text('下载管理').first);
      await tester.pumpAndSettle();
      expect(navigatedTab, 1);

      // Open layout configuration dialog from app bar
      await tester.tap(find.byIcon(Icons.dashboard_customize_outlined));
      await tester.pumpAndSettle();

      expect(find.text('主页与导航管理'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('恢复默认'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('主页与导航管理'), findsNothing);
    });
  });
}
