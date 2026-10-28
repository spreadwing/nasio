import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/app_version_model.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';

class UpdateProvider extends ChangeNotifier {
  final UpdateService _service = UpdateService();

  String _currentVersion = '1.0.0';
  String _giteaUrl = StorageService.defaultGiteaUrl;
  String _owner = 'spreadwing';
  String _packageName = 'nasio-client';

  bool _isChecking = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _statusMessage;
  String? _errorMessage;

  AppVersionModel? _latestRelease;
  bool _hasUpdate = false;
  CancelToken? _cancelToken;

  String get currentVersion => _currentVersion;
  String get giteaUrl => _giteaUrl;
  String get owner => _owner;
  String get packageName => _packageName;
  bool get isChecking => _isChecking;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  int get receivedBytes => _receivedBytes;
  int get totalBytes => _totalBytes;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  AppVersionModel? get latestRelease => _latestRelease;
  bool get hasUpdate => _hasUpdate;

  UpdateProvider() {
    init();
  }

  Future<void> init() async {
    _giteaUrl = StorageService.getGiteaUrl();
    _currentVersion = await _service.getCurrentVersion();
    notifyListeners();
  }

  Future<void> updateGiteaConfig({
    required String giteaUrl,
    String? owner,
    String? packageName,
  }) async {
    _giteaUrl = giteaUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (owner != null && owner.trim().isNotEmpty) {
      _owner = owner.trim();
    }
    if (packageName != null && packageName.trim().isNotEmpty) {
      _packageName = packageName.trim();
    }
    await StorageService.setGiteaUrl(_giteaUrl);
    notifyListeners();
  }

  /// 检查是否有新版本
  Future<bool> checkUpdate({bool showSnackbarOnLatest = true}) async {
    if (_isChecking) return false;

    _isChecking = true;
    _errorMessage = null;
    _statusMessage = '正在连接 Gitea 软件包仓库查询...';
    notifyListeners();

    try {
      // 重新读取一次最新版本号以防更新
      _currentVersion = await _service.getCurrentVersion();

      final release = await _service.fetchLatestRelease(
        giteaUrl: _giteaUrl,
        owner: _owner,
        packageName: _packageName,
      );

      _latestRelease = release;

      if (release == null) {
        _hasUpdate = false;
        _statusMessage = '未在 Gitea 软件包中查询到此客户端的发布记录';
      } else {
        _hasUpdate = release.isNewerThan(_currentVersion);
        if (_hasUpdate) {
          _statusMessage = '发现新版本 ${release.version}！可立即更新。';
        } else {
          _statusMessage = '当前已是最新版本 ($_currentVersion)';
        }
      }

      _isChecking = false;
      notifyListeners();
      return _hasUpdate;
    } catch (e) {
      _isChecking = false;
      _errorMessage = '检查更新失败: $e';
      _statusMessage = '检查更新异常，请检查 Gitea 地址与网络连接';
      notifyListeners();
      return false;
    }
  }

  /// 下载并安装对应平台的更新包
  Future<void> downloadAndInstall({
    required PackageFileModel file,
    void Function(String savePath)? onSuccess,
    void Function(String error)? onError,
  }) async {
    if (_isDownloading) return;

    _isDownloading = true;
    _downloadProgress = 0.0;
    _receivedBytes = 0;
    _totalBytes = file.size;
    _errorMessage = null;
    _cancelToken = CancelToken();
    notifyListeners();

    try {
      final savePath = await _service.downloadPackage(
        file: file,
        cancelToken: _cancelToken,
        onProgress: (received, total) {
          _receivedBytes = received;
          if (total > 0) {
            _totalBytes = total;
            _downloadProgress = received / total;
          } else if (_totalBytes > 0) {
            _downloadProgress = received / _totalBytes;
          }
          notifyListeners();
        },
      );

      _isDownloading = false;
      _downloadProgress = 1.0;
      notifyListeners();

      if (!kIsWeb) {
        // 自动拉起系统安装意图或打开文件
        await _service.installOrOpenFile(savePath);
      }

      onSuccess?.call(savePath);
    } catch (e) {
      _isDownloading = false;
      if (CancelToken.isCancel(e as dynamic)) {
        _statusMessage = '下载已取消';
      } else {
        _errorMessage = '下载失败: $e';
        onError?.call(_errorMessage!);
      }
      notifyListeners();
    }
  }

  /// 取消当前正在进行的下载任务
  void cancelDownload() {
    if (_isDownloading && _cancelToken != null) {
      _cancelToken?.cancel('用户手动取消');
      _isDownloading = false;
      _downloadProgress = 0.0;
      notifyListeners();
    }
  }

  /// 针对 Web 端打开指定下载链接
  Future<void> openExternalUrl(String url) async {
    await _service.openDownloadUrl(url);
  }
}
