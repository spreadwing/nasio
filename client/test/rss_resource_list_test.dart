import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasio_client/models/rss_model.dart';
import 'package:nasio_client/providers/connection_provider.dart';
import 'package:nasio_client/providers/rss_provider.dart';
import 'package:nasio_client/services/api_service.dart';
import 'package:nasio_client/services/storage_service.dart';
import 'package:nasio_client/views/rss/rss_resource_list_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

RssSubscriptionModel createTestSubscription({
  String rssId = 'sub-test-123',
  String title = '鬼灭之刃 柱训练篇',
  String feedUrl = 'https://example.com/rss/demonslayer.xml',
  String saveDir = '/volume1/Media/Anime/DemonSlayer',
  List<RssFilterRule> filterRules = const [],
  int totalDownloadedCount = 1,
}) {
  return RssSubscriptionModel(
    rssId: rssId,
    title: title,
    feedUrl: feedUrl,
    saveDir: saveDir,
    filterRules: filterRules,
    checkIntervalMinutes: 15,
    downloadEngine: 'qbittorrent',
    enabled: true,
    lastCheckedAt: 0,
    totalDownloadedCount: totalDownloadedCount,
    downloadedGuids: const [],
    downloadHistory: const [],
    createdAt: 0,
    updatedAt: 0,
  );
}

class MockRssApiService extends ApiService {
  final List<RssItemPreview> mockItems;
  List<RssItemPreview>? lastDownloadedItems;

  MockRssApiService({required this.mockItems}) : super.custom();

  @override
  Future<RssSubscriptionItemsResponse> getRssSubscriptionItems(String rssId) async {
    return RssSubscriptionItemsResponse(
      rssId: rssId,
      title: '测试新番订阅',
      feedUrl: 'https://example.com/feed.xml',
      saveDir: '/volume1/Media/Anime',
      downloadEngine: 'qbittorrent',
      totalItems: mockItems.length,
      matchedCount: mockItems.where((i) => i.matched).length,
      downloadedCount: mockItems.where((i) => i.isDownloaded).length,
      items: mockItems,
    );
  }

  @override
  Future<RssBatchDownloadResult> downloadRssSubscriptionItems({
    required String rssId,
    required List<RssItemPreview> items,
  }) async {
    lastDownloadedItems = items;
    return RssBatchDownloadResult(
      rssId: rssId,
      totalRequested: items.length,
      dispatchedCount: items.length,
      failedCount: 0,
      totalDownloadedCount: items.length,
    );
  }

  @override
  Future<RssSubscriptionModel> getRssSubscriptionDetail(String rssId) async {
    return createTestSubscription(
      rssId: rssId,
      totalDownloadedCount: lastDownloadedItems?.length ?? 0,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });

  group('RSS Resource Models Test', () {
    test('RssItemPreview fromJson and toDownloadJson', () {
      final json = {
        'guid': 'item-101',
        'title': '[Fansub] My Hero Academia - 01 [1080P]',
        'link': 'https://example.com/topic/101',
        'download_url': 'magnet:?xt=urn:btih:hash101',
        'pub_date': '2026-10-11T12:00:00Z',
        'matched': true,
        'is_downloaded': false,
        'tag_values': {'category': 'Anime'},
      };

      final item = RssItemPreview.fromJson(json);
      expect(item.guid, equals('item-101'));
      expect(item.title, contains('My Hero Academia'));
      expect(item.downloadUrl, startsWith('magnet:'));
      expect(item.matched, isTrue);
      expect(item.isDownloaded, isFalse);

      final dlJson = item.toDownloadJson();
      expect(dlJson['guid'], equals('item-101'));
      expect(dlJson['title'], equals(item.title));
      expect(dlJson['download_url'], equals(item.downloadUrl));
    });

    test('RssSubscriptionItemsResponse fromJson', () {
      final json = {
        'rss_id': 'rss-anime-1',
        'title': '新番更新',
        'feed_url': 'https://example.com/rss.xml',
        'save_dir': '/volume1/Media/Comic',
        'download_engine': 'auto',
        'total_items': 2,
        'matched_count': 1,
        'downloaded_count': 1,
        'items': [
          {
            'guid': 'item-1',
            'title': 'Ep 1',
            'download_url': 'magnet:?xt=1',
            'matched': true,
            'is_downloaded': true,
          },
          {
            'guid': 'item-2',
            'title': 'Ep 2',
            'download_url': 'magnet:?xt=2',
            'matched': false,
            'is_downloaded': false,
          },
        ],
      };

      final resp = RssSubscriptionItemsResponse.fromJson(json);
      expect(resp.rssId, equals('rss-anime-1'));
      expect(resp.items.length, equals(2));
      expect(resp.matchedCount, equals(1));
      expect(resp.downloadedCount, equals(1));
      expect(resp.items[0].isDownloaded, isTrue);
      expect(resp.items[1].isDownloaded, isFalse);
    });

    test('RssBatchDownloadResult fromJson', () {
      final json = {
        'rss_id': 'rss-anime-1',
        'total_requested': 3,
        'dispatched_count': 3,
        'failed_count': 0,
        'total_downloaded_count': 10,
      };

      final result = RssBatchDownloadResult.fromJson(json);
      expect(result.totalRequested, equals(3));
      expect(result.dispatchedCount, equals(3));
      expect(result.failedCount, equals(0));
      expect(result.totalDownloadedCount, equals(10));
    });
  });

  group('RssResourceListView UI & Interaction Widget Tests', () {
    late RssSubscriptionModel testSub;
    late List<RssItemPreview> sampleItems;

    setUp(() {
      testSub = createTestSubscription();

      sampleItems = [
        RssItemPreview(
          guid: 'ep-01',
          title: '[字幕组] 鬼灭之刃 柱训练篇 01 [1080P]',
          link: 'https://example.com/1',
          downloadUrl: 'magnet:?xt=urn:btih:ep01',
          pubDate: '2026-10-10 10:00',
          matched: true,
          isDownloaded: true,
        ),
        RssItemPreview(
          guid: 'ep-02',
          title: '[字幕组] 鬼灭之刃 柱训练篇 02 [1080P]',
          link: 'https://example.com/2',
          downloadUrl: 'magnet:?xt=urn:btih:ep02',
          pubDate: '2026-10-11 10:00',
          matched: true,
          isDownloaded: false,
        ),
        RssItemPreview(
          guid: 'ep-other',
          title: '[字幕组] 咒术回战 01 [720P]',
          link: 'https://example.com/other',
          downloadUrl: 'magnet:?xt=urn:btih:other',
          pubDate: '2026-10-09 10:00',
          matched: false,
          isDownloaded: false,
        ),
      ];
    });

    testWidgets('Renders items and supports filter chips and batch selection', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockApi = MockRssApiService(mockItems: sampleItems);
      final rssProv = RssProvider(apiService: mockApi);
      final connProv = ConnectionProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<RssProvider>.value(value: rssProv),
            ChangeNotifierProvider<ConnectionProvider>.value(value: connProv),
          ],
          child: MaterialApp(
            home: RssResourceListView(subscription: testSub),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 验证标题与顶部统计
      expect(find.text('鬼灭之刃 柱训练篇'), findsOneWidget);
      expect(find.text('全部 (3)'), findsOneWidget);

      // 默认全部条目展示
      expect(find.textContaining('鬼灭之刃 柱训练篇 01'), findsOneWidget);
      expect(find.textContaining('鬼灭之刃 柱训练篇 02'), findsOneWidget);
      expect(find.textContaining('咒术回战 01'), findsOneWidget);

      // 切换过滤标签：命中规则 (matched)
      final matchedFilterChip = find.text('命中规则 (2)');
      expect(matchedFilterChip, findsOneWidget);
      await tester.tap(matchedFilterChip);
      await tester.pumpAndSettle();

      // 此时仅有 2 个匹配项，不匹配项被过滤
      expect(find.textContaining('鬼灭之刃 柱训练篇 01'), findsOneWidget);
      expect(find.textContaining('鬼灭之刃 柱训练篇 02'), findsOneWidget);
      expect(find.textContaining('咒术回战 01'), findsNothing);

      // 切换过滤标签：未下载 (notDownloaded)
      final notDownloadedFilterChip = find.text('未下载 (2)');
      expect(notDownloadedFilterChip, findsOneWidget);
      await tester.tap(notDownloadedFilterChip);
      await tester.pumpAndSettle();

      expect(find.textContaining('鬼灭之刃 柱训练篇 02'), findsOneWidget);
      expect(find.textContaining('咒术回战 01'), findsOneWidget);
      expect(find.textContaining('鬼灭之刃 柱训练篇 01'), findsNothing);

      // 切回“全部”
      await tester.tap(find.text('全部 (3)'));
      await tester.pumpAndSettle();

      // 测试“全选符合规则未下载项”按钮：点击全选未下载且命中匹配规则的项 (只命中 ep-02)
      final selectAllButton = find.byTooltip('全选符合规则未下载项');
      expect(selectAllButton, findsOneWidget);
      await tester.tap(selectAllButton);
      await tester.pumpAndSettle();

      // 底部批量下载栏弹出，显示勾选了 1 项（未下载且匹配规则的 ep-02）
      expect(find.text('反选/全选当前'), findsOneWidget);
      expect(find.text('立即下载 (1)'), findsOneWidget);

      // 点击批量下载
      await tester.tap(find.text('立即下载 (1)'));
      await tester.pumpAndSettle();

      // 弹出确认对话框
      expect(find.text('确认下载选定资源'), findsOneWidget);
      // 点击对话框中的“开始下载”
      await tester.tap(find.text('开始下载'));
      await tester.pumpAndSettle();

      // 验证 MockApi 被调用，并且传参正确
      expect(mockApi.lastDownloadedItems, isNotNull);
      expect(mockApi.lastDownloadedItems!.length, equals(1));
      expect(mockApi.lastDownloadedItems!.first.guid, equals('ep-02'));
    });
  });
}
