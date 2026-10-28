import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasio_client/core/utils/formatters.dart';

void main() {
  group('Formatters.formatErrorMessage Tests', () {
    test('Format 401 with server error message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/api/v1/config'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/config'),
          statusCode: 401,
          data: {'error': '未授权访问: 凭据无效或缺失 (请提供正确的 Bearer Token 或 HTTP Basic 账号密码)'},
        ),
      );

      final msg = Formatters.formatErrorMessage(dioError);
      expect(msg, contains('认证失败 (401)'));
      expect(msg, contains('未授权访问: 凭据无效或缺失'));
    });

    test('Format 401 without server error message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/api/v1/auth/login'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/auth/login'),
          statusCode: 401,
        ),
      );

      final msg = Formatters.formatErrorMessage(dioError);
      expect(msg, contains('认证失败 (401)'));
      expect(msg, contains('安全令牌 (Token) 无效或账号密码不正确'));
    });

    test('Format connection timeout', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/health'),
        type: DioExceptionType.connectionTimeout,
      );

      final msg = Formatters.formatErrorMessage(dioError);
      expect(msg, contains('连接超时'));
      expect(msg, contains('检查主机 IP'));
    });

    test('Format connection error', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/health'),
        type: DioExceptionType.connectionError,
      );

      final msg = Formatters.formatErrorMessage(dioError);
      expect(msg, contains('网络无法连通'));
      expect(msg, contains('确认 NAS 主机 IP/端口是否正确'));
    });

    test('Format 502 Bad Gateway', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/api/v1/config'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/config'),
          statusCode: 502,
        ),
      );

      final msg = Formatters.formatErrorMessage(dioError);
      expect(msg, contains('网关反代错误 (502)'));
      expect(msg, contains('容器是否处于运行状态'));
    });

    test('Format generic Exception', () {
      final ex = Exception('用户名和密码不能为空');
      final msg = Formatters.formatErrorMessage(ex);
      expect(msg, equals('用户名和密码不能为空'));
    });
  });
}
