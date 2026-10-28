import 'package:flutter_test/flutter_test.dart';
import 'package:nasio_client/core/constants/api_constants.dart';
import 'package:nasio_client/providers/connection_provider.dart';
import 'package:nasio_client/providers/agent_task_provider.dart';
import 'package:nasio_client/providers/missing_mcp_provider.dart';
import 'package:nasio_client/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });

  group('ConnectionProvider & Token Validation Tests', () {
    test('ApiConstants.defaultToken is empty to prevent using stale tokens', () {
      expect(ApiConstants.defaultToken, isEmpty);
    });

    test('Initial ConnectionProvider state loads empty token when no prefs saved', () {
      final provider = ConnectionProvider();
      expect(provider.token, isEmpty);
      expect(provider.isConnected, isFalse);
      expect(provider.isAdmin, isFalse);
    });

    test('clearErrorMessage resets errorMessage', () {
      final provider = ConnectionProvider();
      provider.clearErrorMessage();
      expect(provider.errorMessage, isNull);
    });

    test('disconnect properly clears user and connection state', () {
      final provider = ConnectionProvider();
      provider.disconnect();
      expect(provider.isConnected, isFalse);
      expect(provider.wasConnected, isFalse);
      expect(provider.currentUser, isNull);
    });

    test('Restores provisional currentUser from StorageService when wasConnected is true', () async {
      SharedPreferences.setMockInitialValues({
        'nasio_host': '192.168.1.100',
        'nasio_port': 8000,
        'nasio_token': 'u_tok_test_123456',
        'nasio_auth_type': 'credentials',
        'nasio_username': 'spreadwing91',
        'nasio_user_role': 'ADMIN',
        'nasio_was_connected': true,
      });
      await StorageService.init();

      final provider = ConnectionProvider();
      expect(provider.isConnected, isTrue);
      expect(provider.currentUser, isNotNull);
      expect(provider.currentUser!.username, equals('spreadwing91'));
      expect(provider.isAdmin, isTrue);
    });

    test('AgentTaskProvider hasLoaded initial is false and reset clears state', () {
      final agentProv = AgentTaskProvider();
      expect(agentProv.hasLoaded, isFalse);
      expect(agentProv.tasks, isEmpty);

      agentProv.reset();
      expect(agentProv.hasLoaded, isFalse);
      expect(agentProv.tasks, isEmpty);
      expect(agentProv.selectedTask, isNull);
    });

    test('MissingMcpProvider hasLoaded initial is false and reset clears state', () {
      final missingProv = MissingMcpProvider();
      expect(missingProv.hasLoaded, isFalse);
      expect(missingProv.items, isEmpty);

      missingProv.reset();
      expect(missingProv.hasLoaded, isFalse);
      expect(missingProv.items, isEmpty);
    });
  });
}
