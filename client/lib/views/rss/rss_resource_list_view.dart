import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/rss_model.dart';
import '../../providers/rss_provider.dart';

enum RssItemFilterType {
  all,
  matched,
  notDownloaded,
  downloaded,
}

class RssResourceListView extends StatefulWidget {
  final RssSubscriptionModel subscription;

  const RssResourceListView({
    super.key,
    required this.subscription,
  });

  @override
  State<RssResourceListView> createState() => _RssResourceListViewState();
}

class _RssResourceListViewState extends State<RssResourceListView> {
  bool _isLoading = true;
  String? _errorMessage;
  RssSubscriptionItemsResponse? _data;
  final Set<String> _selectedGuids = {};
  final Set<String> _downloadingGuids = {};
  RssItemFilterType _currentFilter = RssItemFilterType.all;
  String _searchKeyword = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadItems();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final prov = context.read<RssProvider>();
    final res = await prov.fetchSubscriptionItems(widget.subscription.rssId);

    if (mounted) {
      setState(() {
        _isLoading = false;
        _data = res;
        if (res == null) {
          _errorMessage = prov.errorMessage ?? '获取远端资源失败';
        }
      });
    }
  }

  List<RssItemPreview> get _filteredItems {
    if (_data == null) return [];
    var list = _data!.items;

    // 分类过滤
    switch (_currentFilter) {
      case RssItemFilterType.all:
        break;
      case RssItemFilterType.matched:
        list = list.where((it) => it.matched).toList();
        break;
      case RssItemFilterType.notDownloaded:
        list = list.where((it) => !it.isDownloaded).toList();
        break;
      case RssItemFilterType.downloaded:
        list = list.where((it) => it.isDownloaded).toList();
        break;
    }

    // 搜索关键字过滤
    if (_searchKeyword.trim().isNotEmpty) {
      final kw = _searchKeyword.trim().toLowerCase();
      list = list.where((it) => it.title.toLowerCase().contains(kw)).toList();
    }

    return list;
  }

  void _toggleSelectAll() {
    final currentList = _filteredItems;
    final allSelected = currentList.isNotEmpty &&
        currentList.every((it) => _selectedGuids.contains(it.guid));

    setState(() {
      if (allSelected) {
        for (final it in currentList) {
          _selectedGuids.remove(it.guid);
        }
      } else {
        for (final it in currentList) {
          _selectedGuids.add(it.guid);
        }
      }
    });
  }

  void _selectAllNotDownloadedAndMatched() {
    if (_data == null) return;
    setState(() {
      for (final it in _data!.items) {
        if (!it.isDownloaded && it.matched && it.downloadUrl.isNotEmpty) {
          _selectedGuids.add(it.guid);
        }
      }
    });
  }

  /// 单条下载
  Future<void> _downloadSingleItem(RssItemPreview item) async {
    if (item.downloadUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('该条目无有效下载链接'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    setState(() => _downloadingGuids.add(item.guid));

    final prov = context.read<RssProvider>();
    final result = await prov.downloadSubscriptionItems(
      rssId: widget.subscription.rssId,
      items: [item],
    );

    if (mounted) {
      setState(() => _downloadingGuids.remove(item.guid));
      if (result != null && result.dispatchedCount > 0) {
        // 更新本地条目状态为已下载
        _markItemsDownloaded([item.guid]);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功派发下载: "${item.title}"'),
            backgroundColor: AppColors.successGreen,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(prov.errorMessage ?? '派发下载失败'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    }
  }

  /// 批量下载已选条目
  Future<void> _downloadSelectedItems() async {
    if (_selectedGuids.isEmpty || _data == null) return;

    final targetItems = _data!.items
        .where((it) => _selectedGuids.contains(it.guid) && it.downloadUrl.isNotEmpty)
        .toList();

    if (targetItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('选中的条目中没有可下载的有效链接'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    final count = targetItems.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认下载选定资源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('即将批量派发 $count 项资源至下载引擎。'),
            const SizedBox(height: 8),
            Text('• 目标目录: ${widget.subscription.saveDir}', style: const TextStyle(fontSize: 12)),
            Text('• 引擎: ${widget.subscription.downloadEngine}', style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF7A00)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始下载', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final prov = context.read<RssProvider>();
    final result = await prov.downloadSubscriptionItems(
      rssId: widget.subscription.rssId,
      items: targetItems,
    );

    if (mounted) {
      if (result != null && result.dispatchedCount > 0) {
        _markItemsDownloaded(targetItems.map((e) => e.guid).toList());
        setState(() => _selectedGuids.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('成功派发 ${result.dispatchedCount} 项资源下载任务！'),
            backgroundColor: AppColors.successGreen,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(prov.errorMessage ?? '批量下载失败'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    }
  }

  void _markItemsDownloaded(List<String> guids) {
    if (_data == null) return;
    final guidSet = guids.toSet();
    setState(() {
      final updatedList = _data!.items.map((it) {
        if (guidSet.contains(it.guid)) {
          return RssItemPreview(
            guid: it.guid,
            title: it.title,
            link: it.link,
            downloadUrl: it.downloadUrl,
            pubDate: it.pubDate,
            matched: it.matched,
            isDownloaded: true,
            tagValues: it.tagValues,
          );
        }
        return it;
      }).toList();

      final downloadedCount = updatedList.where((e) => e.isDownloaded).length;
      _data = RssSubscriptionItemsResponse(
        rssId: _data!.rssId,
        title: _data!.title,
        feedUrl: _data!.feedUrl,
        saveDir: _data!.saveDir,
        downloadEngine: _data!.downloadEngine,
        totalItems: _data!.totalItems,
        matchedCount: _data!.matchedCount,
        downloadedCount: downloadedCount,
        items: updatedList,
      );
    });
  }

  String _formatPubDate(String dateStr) {
    if (dateStr.isEmpty) return '未知时间';
    return dateStr;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final sub = widget.subscription;
    final filtered = _filteredItems;
    final totalCount = _data?.totalItems ?? 0;
    final matchedCount = _data?.matchedCount ?? 0;
    final downloadedCount = _data?.downloadedCount ?? 0;
    final notDownloadedCount = totalCount - downloadedCount;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sub.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${sub.feedUrl} • ${sub.saveDir}',
              style: TextStyle(fontSize: 11, color: context.subtextColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '刷新远端资源',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadItems,
          ),
          IconButton(
            tooltip: '全选符合规则未下载项',
            icon: const Icon(Icons.playlist_add_check_rounded),
            onPressed: _selectAllNotDownloadedAndMatched,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // 搜索与过滤栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索资源标题...',
                hintStyle: TextStyle(fontSize: 13, color: context.subtextColor),
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _searchKeyword.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchKeyword = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                isDense: true,
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (val) => setState(() => _searchKeyword = val),
            ),
          ),

          // 状态筛选 Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _buildFilterChip('全部 ($totalCount)', RssItemFilterType.all),
                const SizedBox(width: 8),
                _buildFilterChip('命中规则 ($matchedCount)', RssItemFilterType.matched),
                const SizedBox(width: 8),
                _buildFilterChip('未下载 ($notDownloadedCount)', RssItemFilterType.notDownloaded),
                const SizedBox(width: 8),
                _buildFilterChip('已下载 ($downloadedCount)', RssItemFilterType.downloaded),
              ],
            ),
          ),

          const Divider(height: 1),

          // 列表主体
          Expanded(
            child: _buildBodyContent(filtered, isDark),
          ),
        ],
      ),
      bottomNavigationBar: _selectedGuids.isNotEmpty
          ? _buildBatchBottomBar(context, isDark)
          : null,
    );
  }

  Widget _buildFilterChip(String label, RssItemFilterType type) {
    final isSelected = _currentFilter == type;
    final color = const Color(0xFFFF7A00);

    return FilterChip(
      selected: isSelected,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? color : null,
      ),
      selectedColor: color.withOpacity(0.15),
      checkmarkColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      visualDensity: VisualDensity.compact,
      onSelected: (_) => setState(() => _currentFilter = type),
    );
  }

  Widget _buildBodyContent(List<RssItemPreview> items, bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.errorRed),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.errorRed, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('重试加载'),
                onPressed: _loadItems,
              ),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 56, color: context.subtextColor.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(
              '没有符合条件的资源条目',
              style: TextStyle(color: context.subtextColor, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadItems,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 80),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final isSelected = _selectedGuids.contains(item.guid);
          final isDownloading = _downloadingGuids.contains(item.guid);

          return _buildItemCard(item, isSelected, isDownloading, isDark);
        },
      ),
    );
  }

  Widget _buildItemCard(
    RssItemPreview item,
    bool isSelected,
    bool isDownloading,
    bool isDark,
  ) {
    final borderColor = isSelected
        ? const Color(0xFFFF7A00).withOpacity(0.7)
        : context.customBorderColor;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: isSelected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedGuids.remove(item.guid);
            } else {
              _selectedGuids.add(item.guid);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：复选框 + 标题 + 快捷操作
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: isSelected,
                    activeColor: const Color(0xFFFF7A00),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedGuids.add(item.guid);
                        } else {
                          _selectedGuids.remove(item.guid);
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        if (item.pubDate.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _formatPubDate(item.pubDate),
                            style: TextStyle(fontSize: 11, color: context.subtextColor),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isDownloading)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (item.isDownloaded)
                    IconButton(
                      icon: const Icon(Icons.check_circle_rounded, color: AppColors.successGreen, size: 22),
                      tooltip: '已下载 (点击可再次下载)',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _downloadSingleItem(item),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.download_rounded, color: Color(0xFFFF7A00), size: 22),
                      tooltip: '立即下载该条目',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _downloadSingleItem(item),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // 第二行：状态徽章与链接操作
              Row(
                children: [
                  const SizedBox(width: 32), // 对齐复选框宽度
                  // 规则匹配徽章
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.matched
                          ? AppColors.primaryBlue.withOpacity(0.12)
                          : Colors.grey.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.matched ? '匹配规则' : '未匹配',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: item.matched ? AppColors.primaryBlue : Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 下载状态徽章
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.isDownloaded
                          ? AppColors.successGreen.withOpacity(0.15)
                          : const Color(0xFFFF7A00).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.isDownloaded ? '已下载' : '未下载',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: item.isDownloaded ? AppColors.successGreen : const Color(0xFFFF7A00),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (item.downloadUrl.isNotEmpty)
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: item.downloadUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('下载地址已复制到剪贴板')),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.copy_rounded, size: 12, color: context.subtextColor),
                            const SizedBox(width: 4),
                            Text(
                              item.downloadUrl.startsWith('magnet:') ? '磁力链' : '下载链接',
                              style: TextStyle(fontSize: 11, color: context.subtextColor),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBatchBottomBar(BuildContext context, bool isDark) {
    final count = _selectedGuids.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.customCardColor,
        border: Border(top: BorderSide(color: context.customBorderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            offset: const Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            TextButton(
              onPressed: _toggleSelectAll,
              child: const Text('反选/全选当前', style: TextStyle(fontSize: 12)),
            ),
            const Spacer(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7A00),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text('立即下载 ($count)'),
              onPressed: _downloadSelectedItems,
            ),
          ],
        ),
      ),
    );
  }
}
