import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

class Formatters {
  /// 格式化存储与网络字节（如 1024 -> 1.00 KB, 1.2 GB）
  static String formatBytes(dynamic bytes, [int decimals = 2]) {
    if (bytes == null) return '0 B';
    num b = 0;
    if (bytes is num) {
      b = bytes;
    } else if (bytes is String) {
      b = num.tryParse(bytes) ?? 0;
    }
    if (b <= 0) return '0 B';

    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    var i = 0;
    double val = b.toDouble();
    while (val >= 1024 && i < suffixes.length - 1) {
      val /= 1024;
      i++;
    }
    return '${val.toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  /// 格式化即时下载速率
  static String formatSpeed(dynamic speed) {
    if (speed == null) return '0 B/s';
    if (speed is String) {
      if (speed.endsWith('/s')) return speed;
      final n = num.tryParse(speed);
      if (n != null) return '${formatBytes(n)}/s';
      return speed;
    }
    if (speed is num) {
      return '${formatBytes(speed)}/s';
    }
    return '0 B/s';
  }

  /// 格式化时间戳或时间字符串
  static String formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '-';
    DateTime? dt;
    if (timestamp is num) {
      // 秒或毫秒
      final int ms = timestamp > 10000000000 ? timestamp.toInt() : (timestamp * 1000).toInt();
      dt = DateTime.fromMillisecondsSinceEpoch(ms);
    } else if (timestamp is String) {
      dt = DateTime.tryParse(timestamp);
    }
    if (dt == null) return timestamp.toString();
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt.toLocal());
  }

  /// 格式化剩余秒数为 mm:ss 或 hh:mm:ss
  static String formatDuration(int? totalSeconds) {
    if (totalSeconds == null || totalSeconds <= 0) return '--';
    if (totalSeconds >= 86400) {
      final days = totalSeconds ~/ 86400;
      return '$days 天+';
    }
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 智能解析并人性化格式化网络、Dio 与系统异常
  static String formatErrorMessage(dynamic error, [String? prefix]) {
    if (error == null) return '';
    String result = '';

    if (error is DioException) {
      final res = error.response;
      final statusCode = res?.statusCode;
      String? serverMsg;

      // 提取服务端返回的友好提示
      if (res?.data != null) {
        if (res!.data is Map) {
          final map = res.data as Map;
          serverMsg = map['error']?.toString() ??
              map['detail']?.toString() ??
              map['message']?.toString();
        } else if (res.data is String && (res.data as String).trim().isNotEmpty) {
          final str = (res.data as String).trim();
          if (!str.startsWith('<!DOCTYPE') && !str.startsWith('<html')) {
            serverMsg = str;
          }
        }
      }

      if (statusCode != null) {
        switch (statusCode) {
          case 401:
            result = serverMsg != null && serverMsg.isNotEmpty
                ? '认证失败 (401)：$serverMsg'
                : '认证失败 (401)：安全令牌 (Token) 无效或账号密码不正确，请核对凭证';
            break;
          case 403:
            result = serverMsg != null && serverMsg.isNotEmpty
                ? '权限不足 (403)：$serverMsg'
                : '访问被拒绝 (403)：当前账号权限不足，无法执行此操作';
            break;
          case 404:
            result = serverMsg != null && serverMsg.isNotEmpty
                ? '资源不存在 (404)：$serverMsg'
                : '请求目标接口或资源不存在 (404)，请检查服务端版本或网关路径';
            break;
          case 400:
            result = serverMsg != null && serverMsg.isNotEmpty
                ? '请求参数错误 (400)：$serverMsg'
                : '请求参数或格式有误 (400)';
            break;
          case 422:
            result = serverMsg != null && serverMsg.isNotEmpty
                ? '数据校验不通过 (422)：$serverMsg'
                : '提交的表单字段未通过服务端校验 (422)';
            break;
          case 500:
            result = serverMsg != null && serverMsg.isNotEmpty
                ? '服务端内部错误 (500)：$serverMsg'
                : 'Nasio 服务端发生内部异常 (500)，请查看服务端 Docker 日志';
            break;
          case 502:
            result = '网关反代错误 (502)：无法连接到后端应用服务，请确认容器是否处于运行状态';
            break;
          case 503:
            result = '服务暂不可用 (503)：NAS 服务端正在维护或系统资源过载';
            break;
          case 504:
            result = '网关响应超时 (504)：上游服务未在规定时间内返回数据';
            break;
          default:
            result = serverMsg != null && serverMsg.isNotEmpty
                ? 'HTTP $statusCode 异常：$serverMsg'
                : '服务返回状态码 $statusCode';
        }
      } else {
        switch (error.type) {
          case DioExceptionType.connectionTimeout:
            result = '连接超时：连接 NAS 服务端超时，请检查主机 IP、端口及网络连通性';
            break;
          case DioExceptionType.sendTimeout:
            result = '发送数据超时：网络连接不稳定，请稍后重试';
            break;
          case DioExceptionType.receiveTimeout:
            result = '接收响应超时：NAS 服务端处理时间过长，未及时响应';
            break;
          case DioExceptionType.badCertificate:
            result = 'SSL 证书无效：若配置了 HTTPS，请确认证书是否有效或改用 HTTP';
            break;
          case DioExceptionType.connectionError:
            result = '网络无法连通：无法与目标主机建立连接，请确认 NAS 主机 IP/端口是否正确且服务已启动';
            break;
          case DioExceptionType.cancel:
            result = '网络请求已被主动取消';
            break;
          default:
            final errStr = error.error?.toString() ?? error.message ?? '';
            if (errStr.contains('Connection refused')) {
              result = '连接被拒绝：目标端口未开放或 Nasio 服务未运行';
            } else if (errStr.contains('Network is unreachable')) {
              result = '网络不可达：当前设备可能未联网或不在同一局域网';
            } else {
              result = '网络通信失败：${errStr.isNotEmpty ? errStr : "无法连接到 NAS 服务端"}';
            }
        }
      }
    } else {
      String raw = error.toString().trim();
      if (raw.startsWith('Exception: ')) {
        raw = raw.substring('Exception: '.length).trim();
      }
      if (raw.contains('SocketException')) {
        result = '网络连接异常：无法连接目标主机，请核对 IP 与端口';
      } else if (raw.contains('Connection refused')) {
        result = '连接被拒绝：请确认目标端口服务已启动';
      } else {
        result = raw.isNotEmpty ? raw : '发生未知错误';
      }
    }

    if (prefix != null && prefix.trim().isNotEmpty) {
      return '$prefix: $result';
    }
    return result;
  }
}
