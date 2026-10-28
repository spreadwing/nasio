import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/connection_provider.dart';
import 'providers/storage_provider.dart';
import 'providers/task_provider.dart';
import 'providers/agent_task_provider.dart';
import 'providers/missing_mcp_provider.dart';
import 'providers/trash_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/update_provider.dart';
import 'providers/user_provider.dart';
import 'providers/home_layout_provider.dart';
import 'providers/rss_provider.dart';
import 'providers/chat_provider.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化本地持久化服务
  await StorageService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider(create: (_) => HomeLayoutProvider()),
        ChangeNotifierProvider(create: (_) => StorageProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        ChangeNotifierProvider(create: (_) => AgentTaskProvider()),
        ChangeNotifierProvider(create: (_) => MissingMcpProvider()),
        ChangeNotifierProvider(create: (_) => TrashProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => RssProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: const _AppInitializer(),
    ),
  );
}

class _AppInitializer extends StatefulWidget {
  const _AppInitializer();

  @override
  State<_AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<_AppInitializer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 启动时检查上次是否处于连接状态，若已连接则自动恢复连接并载入业务数据
      final conn = context.read<ConnectionProvider>();
      if (conn.wasConnected && conn.host.isNotEmpty && (conn.token.isNotEmpty || conn.username.isNotEmpty)) {
        final ok = await conn.connect(
          host: conn.host,
          port: conn.port,
          token: conn.token,
          isHttps: conn.isHttps,
          authType: conn.authType,
          username: conn.username,
          password: conn.password,
        );
        if (ok && mounted) {
          context.read<StorageProvider>().loadConfig();
          context.read<TaskProvider>().loadTasks();
          context.read<AgentTaskProvider>().loadTasks();
          context.read<MissingMcpProvider>().loadItems();
          context.read<TrashProvider>().loadTrash();
          context.read<RssProvider>().loadSubscriptions();
          context.read<ChatProvider>().loadAll();
          if (conn.isAdmin) {
            context.read<UserProvider>().loadUsers();
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const NasioApp();
  }
}
