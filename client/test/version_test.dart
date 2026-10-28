import 'package:flutter_test/flutter_test.dart';
import 'package:nasio_client/models/app_version_model.dart';
import 'package:nasio_client/services/update_service.dart';

void main() {
  group('AppVersionModel Tests', () {
    test('Version comparison logic', () {
      expect(AppVersionModel.compareVersion('1.0.21', '1.0.0+1'), greaterThan(0));
      expect(AppVersionModel.compareVersion('1.0.21', '1.0.20'), greaterThan(0));
      expect(AppVersionModel.compareVersion('1.0.21', '1.0.22'), lessThan(0));
      expect(AppVersionModel.compareVersion('1.0.21', '1.0.21'), equals(0));
      expect(AppVersionModel.compareVersion('2.0.0', '1.9.99'), greaterThan(0));
      expect(AppVersionModel.compareVersion('1.0.0.24', '1.0.0+1'), greaterThan(0));
      expect(AppVersionModel.compareVersion('1.0.0.24', '1.0.0+24'), equals(0));
      expect(AppVersionModel.compareVersion('1.0.0.25', '1.0.0+24'), greaterThan(0));
      expect(UpdateService.formatVersionAndBuild('1.0.0', '25'), equals('1.0.0.25'));
      expect(UpdateService.formatVersionAndBuild('1.0.0.25', '25'), equals('1.0.0.25'));
    });

    test('Platform matching logic', () {
      final apkFile = PackageFileModel.fromJson({
        'id': 1,
        'name': 'nasio-client-1.0.21.apk',
        'size': 54756379,
      }, giteaBaseUrl: 'https://git.example.com', owner: 'test_user', packageName: 'nasio-client', version: '1.0.21');

      expect(apkFile.platformType, equals(AppPlatformType.android));
      expect(apkFile.downloadUrl, equals('https://git.example.com/api/packages/test_user/generic/nasio-client/1.0.21/nasio-client-1.0.21.apk'));

      final winFile = PackageFileModel.fromJson({
        'id': 2,
        'name': 'nasio-client-1.0.21-windows.zip',
        'size': 60000000,
      }, giteaBaseUrl: 'https://git.example.com', owner: 'test_user', packageName: 'nasio-client', version: '1.0.21');

      expect(winFile.platformType, equals(AppPlatformType.windows));

      final release = AppVersionModel(
        id: 3,
        name: 'nasio-client',
        version: '1.0.21',
        htmlUrl: 'https://git.example.com/test_user/-/packages/generic/nasio-client/1.0.21',
        createdAt: DateTime.now(),
        files: [apkFile, winFile],
      );

      expect(release.apkFile, isNotNull);
      expect(release.apkFile!.name, equals('nasio-client-1.0.21.apk'));
      expect(release.windowsFile, isNotNull);
      expect(release.windowsFile!.name, equals('nasio-client-1.0.21-windows.zip'));
      expect(release.isNewerThan('1.0.0+1'), isTrue);
      expect(release.isNewerThan('1.0.21'), isFalse);
    });
  });

  group('UpdateService Gitea API Integration', () {
    test('Fetch latest release from real Gitea server', () async {
      final service = UpdateService();
      final release = await service.fetchLatestRelease(
        giteaUrl: 'https://git.example.com',
        owner: 'test_user',
        packageName: 'nasio-client',
      );

      expect(release, isNotNull);
      expect(release!.version, isNotEmpty);
      expect(release.files, isNotEmpty);
      expect(release.apkFile, isNotNull);
      print('✅ 成功连接 Gitea 获取到版本: v${release.version}, 文件: ${release.files.map((e) => e.name).toList()}');
    });
  });
}
