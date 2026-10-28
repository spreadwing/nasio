import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trash_model.dart';
import '../../providers/connection_provider.dart';
import '../../providers/trash_provider.dart';
import '../../widgets/trash_item_tile.dart';
import '../home_scaffold.dart';

class TrashView extends StatefulWidget {
  const TrashView({super.key});

  @override
  State<TrashView> createState() => _TrashViewState();
}

class _TrashViewState extends State<TrashView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final conn = context.read<ConnectionProvider>();
      if (conn.isConnected) {
        context.read<TrashProvider>().loadTrash();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _confirmRestore(TrashItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('一键原路恢复确认'),
        content: Text(
          '确定将文件 "${item.name}" 恢复至原路径吗？\n原路径: ${item.originalPath}\n\n系统将自动重建原目录树结构。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.successGreen),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await context.read<TrashProvider>().restoreFile(item.fileId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? '文件已成功原路恢复' : '恢复失败'),
                    backgroundColor: success ? AppColors.successGreen : AppColors.errorRed,
                  ),
                );
              }
            },
            child: const Text('确认恢复', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(TrashItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除确认'),
        content: Text('确定从回收站永久抹除 "${item.name}" 吗？该操作不可撤销！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorRed),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await context.read<TrashProvider>().deleteFile(item.fileId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? '文件已永久抹除' : '删除失败'),
                    backgroundColor: success ? AppColors.successGreen : AppColors.errorRed,
                  ),
                );
              }
            },
            child: const Text('确认抹除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmEmptyTrash() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站确认'),
        content: const Text('确定清空整个回收站中的所有软删除文件吗？此操作无法恢复！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorRed),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await context.read<TrashProvider>().emptyTrash();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? '回收站已成功清空' : '清空失败'),
                    backgroundColor: success ? AppColors.successGreen : AppColors.errorRed,
                  ),
                );
              }
            },
            child: const Text('全部清空', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    final trash = context.watch<TrashProvider>();

    if (!conn.isConnected) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: '返回主页',
            onPressed: () => HomeScaffold.switchToTab(context, 0),
          ),
          title: const Text('回收站'),
        ),
        body: Center(
          child: Text('请先连接至 NAS 服务端', style: TextStyle(color: context.subtextColor)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回主页',
          onPressed: () => HomeScaffold.switchToTab(context, 0),
        ),
        title: Text('回收站 (${trash.total} 项)'),
        actions: [
          if (trash.items.isNotEmpty)
            TextButton.icon(
              onPressed: _confirmEmptyTrash,
              icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.errorRed),
              label: const Text('清空回收站', style: TextStyle(color: AppColors.errorRed)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
            onPressed: () => trash.loadTrash(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索与过滤栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '按文件名关键字检索软删除条目...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          trash.loadTrash(page: 1, keyword: '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (val) {
                trash.loadTrash(page: 1, keyword: val.trim());
              },
            ),
          ),

          // 列表区域
          Expanded(
            child: trash.isLoading && trash.items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : trash.items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_delete_outlined,
                                size: 56,
                                color: context.isDark ? Colors.white24 : Colors.black26),
                            const SizedBox(height: 12),
                            Text(
                              trash.keyword.isNotEmpty ? '没有匹配的已删除文件' : '回收站空空如也，资产安全无虞',
                              style: TextStyle(color: context.subtextColor),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => trash.loadTrash(),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16.0),
                          itemCount: trash.items.length,
                          itemBuilder: (ctx, idx) {
                            final item = trash.items[idx];
                            return TrashItemTile(
                              item: item,
                              onRestore: () => _confirmRestore(item),
                              onDelete: () => _confirmDelete(item),
                            );
                          },
                        ),
                      ),
          ),

          // 分页控制栏
          if (trash.totalPages > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '第 ${trash.page} / ${trash.totalPages} 页 (共 ${trash.total} 项)',
                    style: TextStyle(fontSize: 12, color: context.subtextColor),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded),
                        onPressed: trash.page > 1
                            ? () => trash.loadTrash(page: trash.page - 1)
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded),
                        onPressed: trash.page < trash.totalPages
                            ? () => trash.loadTrash(page: trash.page + 1)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
