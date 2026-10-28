import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasio_client/models/downloader_config_model.dart';
import 'package:nasio_client/models/task_model.dart';
import 'package:nasio_client/widgets/status_badge.dart';
import 'package:nasio_client/widgets/task_card.dart';

void main() {
  group('做种状态与模型扩展测试 (Seeding Status & Model)', () {
    test('TaskItem 做种与停种状态识别准确', () {
      final seedingTask = TaskItem(
        taskId: 'qb_hash_1',
        taskType: 'DOWNLOAD',
        status: TaskStatus.completed,
        progress: 100.0,
        createdAt: 1000,
        updatedAt: 1000,
        detail: {'state': 'uploading', 'name': 'Anime.S01E01.mkv'},
      );
      expect(seedingTask.isQb, isTrue);
      expect(seedingTask.isSeeding, isTrue);
      expect(seedingTask.isSeedingStopped, isFalse);

      final stalledSeedingTask = TaskItem(
        taskId: 'qb_hash_2',
        taskType: 'DOWNLOAD',
        status: TaskStatus.completed,
        progress: 100.0,
        createdAt: 1000,
        updatedAt: 1000,
        detail: {'state': 'stalledUP', 'name': 'Movie.2026.mkv'},
      );
      expect(stalledSeedingTask.isSeeding, isTrue);

      final stoppedSeedingTask = TaskItem(
        taskId: 'qb_hash_3',
        taskType: 'DOWNLOAD',
        status: TaskStatus.completed,
        progress: 100.0,
        createdAt: 1000,
        updatedAt: 1000,
        detail: {'state': 'pausedUP', 'name': 'Game.ISO'},
      );
      expect(stoppedSeedingTask.isSeeding, isFalse);
      expect(stoppedSeedingTask.isSeedingStopped, isTrue);

      final normalHttpTask = TaskItem(
        taskId: 'local_1',
        taskType: 'DOWNLOAD',
        status: TaskStatus.completed,
        progress: 100.0,
        createdAt: 1000,
        updatedAt: 1000,
        detail: {'name': 'normal.zip'},
      );
      expect(normalHttpTask.isQb, isFalse);
      expect(normalHttpTask.isSeeding, isFalse);
      expect(normalHttpTask.isSeedingStopped, isFalse);
    });

    test('DownloaderConfigModel 包含 auto_stop_seeding 序列化与反序列化', () {
      final json = {
        'default_engine': 'auto',
        'allowed_paths': ['/volume1/Download'],
        'qbittorrent': {
          'enabled': true,
          'url': 'http://127.0.0.1:8080',
          'default_category': 'test',
          'download_limit_kb': 100,
          'upload_limit_kb': 50,
          'default_save_path': '/volume1/Download',
          'max_active_downloads': 3,
          'max_active_torrents': 5,
          'queueing_enabled': true,
          'auto_stop_seeding': true,
        },
      };

      final model = DownloaderConfigModel.fromJson(json);
      expect(model.qbittorrent.autoStopSeeding, isTrue);
      expect(model.qbittorrent.downloadLimitKb, 100);
    });
  });

  group('状态徽章 Widget 测试 (StatusBadge)', () {
    testWidgets('做种中渲染为绿色徽章', (tester) async {
      final task = TaskItem(
        taskId: 'qb_hash_1',
        taskType: 'DOWNLOAD',
        status: TaskStatus.completed,
        progress: 100.0,
        createdAt: 1000,
        updatedAt: 1000,
        detail: {'state': 'uploading'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusBadge.fromTask(task),
          ),
        ),
      );

      expect(find.text('做种中'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('已停止做种渲染为灰色徽章', (tester) async {
      final task = TaskItem(
        taskId: 'qb_hash_2',
        taskType: 'DOWNLOAD',
        status: TaskStatus.completed,
        progress: 100.0,
        createdAt: 1000,
        updatedAt: 1000,
        detail: {'state': 'pausedUP'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusBadge.fromTask(task),
          ),
        ),
      );

      expect(find.text('已停止做种'), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_outline_rounded), findsOneWidget);
    });
  });

  group('任务卡片按钮交互测试 (TaskCard)', () {
    testWidgets('宽屏下做种中卡片显示【停止做种】按钮且点击触发回调', (tester) async {
      bool pauseCalled = false;
      final task = TaskItem(
        taskId: 'qb_hash_1',
        taskType: 'DOWNLOAD',
        status: TaskStatus.completed,
        progress: 100.0,
        createdAt: 1000,
        updatedAt: 1000,
        detail: {'state': 'uploading', 'name': 'Test Torrent'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskCard(
              task: task,
              isWideScreen: true,
              onPause: () => pauseCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('停止做种'), findsOneWidget);
      await tester.tap(find.text('停止做种'));
      expect(pauseCalled, isTrue);
    });

    testWidgets('宽屏下已停止做种卡片显示【继续做种】按钮且点击触发回调', (tester) async {
      bool resumeCalled = false;
      final task = TaskItem(
        taskId: 'qb_hash_2',
        taskType: 'DOWNLOAD',
        status: TaskStatus.completed,
        progress: 100.0,
        createdAt: 1000,
        updatedAt: 1000,
        detail: {'state': 'stoppedUP', 'name': 'Test Torrent 2'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskCard(
              task: task,
              isWideScreen: true,
              onResume: () => resumeCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('继续做种'), findsOneWidget);
      await tester.tap(find.text('继续做种'));
      expect(resumeCalled, isTrue);
    });
  });
}
