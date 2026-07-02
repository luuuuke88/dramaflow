import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';

const _assetKinds = [
  _AssetKind('character', '角色', Icons.person_outline_rounded),
  _AssetKind('prop', '道具', Icons.category_outlined),
  _AssetKind('scene', '场景', Icons.landscape_outlined),
];

class _AssetKind {
  final String value;
  final String label;
  final IconData icon;

  const _AssetKind(this.value, this.label, this.icon);
}

/// 素材库：按角色 / 道具 / 场景管理资产，宽屏为表格，窄屏为卡片流。
class AssetsScreen extends ConsumerStatefulWidget {
  final String projectId;

  const AssetsScreen({super.key, required this.projectId});

  @override
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen> {
  final _search = TextEditingController();
  final _selectedIds = <String>{};
  final _expandedIds = <String>{};

  int _tabIndex = 0;
  int _page = 0;
  int _pageSize = 10;

  String get _kind => _assetKinds[_tabIndex].value;
  String get _kindLabel => _assetKinds[_tabIndex].label;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _changeTab(int index) {
    if (index == _tabIndex) return;
    setState(() {
      _tabIndex = index;
      _page = 0;
      _selectedIds.clear();
      _expandedIds.clear();
    });
  }

  void _changeSearch(String value) {
    setState(() {
      _page = 0;
      _selectedIds.clear();
      _expandedIds.clear();
    });
  }

  void _clearSearch() {
    _search.clear();
    _changeSearch('');
  }

  void _invalidateAssets() {
    ref.invalidate(assetsProvider(widget.projectId));
  }

  List<Asset> _selectedAssets(List<Asset> scoped) =>
      scoped.where((asset) => _selectedIds.contains(asset.id)).toList();

  bool _canGenerate(Asset asset) =>
      asset.status != 'done' &&
      asset.status != 'queued' &&
      asset.status != 'running';

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectPage(List<Asset> pageItems) {
    final allSelected =
        pageItems.every((asset) => _selectedIds.contains(asset.id));
    setState(() {
      if (allSelected) {
        for (final asset in pageItems) {
          _selectedIds.remove(asset.id);
        }
      } else {
        for (final asset in pageItems) {
          _selectedIds.add(asset.id);
        }
      }
    });
  }

  void _toggleExpanded(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  void _openCreateDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => _AssetCreateDialog(
        projectId: widget.projectId,
        kind: _kind,
        kindLabel: _kindLabel,
      ),
    );
  }

  void _openEditDialog(Asset asset) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          _AssetEditDialog(asset: asset, projectId: widget.projectId),
    );
  }

  Future<void> _generateOne(Asset asset) async {
    await runAction(context, ref, () async {
      await ref.read(engineProvider).generateAssetImage(asset.id);
    }, successMessage: '图片生成任务已排队');
    _invalidateAssets();
  }

  Future<void> _generateSelected(List<Asset> scoped) async {
    final selected = _selectedAssets(scoped);
    if (selected.isEmpty) return;

    final generatable = selected.where(_canGenerate).toList();
    final skipped = selected.length - generatable.length;
    var queued = 0;
    var ok = false;

    await runAction(context, ref, () async {
      for (final asset in generatable) {
        final jobId =
            await ref.read(engineProvider).generateAssetImage(asset.id);
        if (jobId != null) queued++;
      }
      ok = true;
    });
    _invalidateAssets();

    if (!mounted || !ok) return;
    final message = queued == 0
        ? '没有可生成的选中资产，已跳过 $skipped 个'
        : '已排队 $queued 个图片生成任务，跳过 $skipped 个已完成或进行中的资产';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _deleteOne(Asset asset) async {
    final confirmed = await _confirmDelete(context, count: 1);
    if (!mounted || !confirmed) return;

    await runAction(context, ref, () async {
      await ref.read(engineProvider).deleteAssets([asset.id]);
    }, successMessage: '资产已删除');
    setState(() {
      _selectedIds.remove(asset.id);
      _expandedIds.remove(asset.id);
    });
    _invalidateAssets();
  }

  Future<void> _deleteSelected(List<Asset> scoped) async {
    final selected = _selectedAssets(scoped);
    if (selected.isEmpty) return;

    final confirmed = await _confirmDelete(context, count: selected.length);
    if (!mounted || !confirmed) return;

    await runAction(context, ref, () async {
      await ref
          .read(engineProvider)
          .deleteAssets(selected.map((asset) => asset.id).toList());
    }, successMessage: '已删除 ${selected.length} 个资产');
    setState(() {
      for (final asset in selected) {
        _selectedIds.remove(asset.id);
        _expandedIds.remove(asset.id);
      }
    });
    _invalidateAssets();
  }

  @override
  Widget build(BuildContext context) {
    final assetsAsync = ref.watch(assetsProvider(widget.projectId));
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回项目',
          onPressed: () => context.go('/projects/${widget.projectId}'),
        ),
        title: const Text('素材库'),
      ),
      body: PageContainer(
        maxWidth: 1240,
        child: AsyncView(
          value: assetsAsync,
          onRetry: _invalidateAssets,
          builder: (assets) {
            final counts = {
              for (final kind in _assetKinds)
                kind.value:
                    assets.where((asset) => asset.kind == kind.value).length,
            };
            final scoped =
                assets.where((asset) => asset.kind == _kind).toList();
            final query = _search.text.trim().toLowerCase();
            final filtered = query.isEmpty
                ? scoped
                : scoped
                    .where((asset) => asset.name.toLowerCase().contains(query))
                    .toList();
            final total = filtered.length;
            final totalPages = math.max(1, (total / _pageSize).ceil());
            final page = math.min(_page, totalPages - 1);
            final pageItems =
                filtered.skip(page * _pageSize).take(_pageSize).toList();
            final selectedCount = _selectedAssets(scoped).length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                DefaultTabController(
                  length: _assetKinds.length,
                  initialIndex: _tabIndex,
                  child: _AssetTabs(
                    counts: counts,
                    onTap: _changeTab,
                  ),
                ),
                const SizedBox(height: 12),
                _AssetToolbar(
                  searchController: _search,
                  selectedCount: selectedCount,
                  onSearchChanged: _changeSearch,
                  onClearSearch: _clearSearch,
                  onCreate: _openCreateDialog,
                  onGenerate: selectedCount == 0
                      ? null
                      : () => _generateSelected(scoped),
                  onDelete:
                      selectedCount == 0 ? null : () => _deleteSelected(scoped),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: filtered.isEmpty
                      ? _AssetEmptyState(
                          hasQuery: query.isNotEmpty,
                          kindLabel: _kindLabel,
                          onCreate: _openCreateDialog,
                        )
                      : wide
                          ? _AssetTable(
                              assets: pageItems,
                              selectedIds: _selectedIds,
                              expandedIds: _expandedIds,
                              onToggleSelected: _toggleSelected,
                              onToggleSelectPage: () =>
                                  _toggleSelectPage(pageItems),
                              onToggleExpanded: _toggleExpanded,
                              onPreview: (asset) =>
                                  _showAssetDetail(context, asset),
                              onGenerate: _generateOne,
                              onEdit: _openEditDialog,
                              onDelete: _deleteOne,
                            )
                          : _AssetCardGrid(
                              assets: pageItems,
                              selectedIds: _selectedIds,
                              selectionMode: _selectedIds.isNotEmpty,
                              onToggleSelected: _toggleSelected,
                              onPreview: (asset) =>
                                  _showAssetDetail(context, asset),
                              onGenerate: _generateOne,
                              onEdit: _openEditDialog,
                              onDelete: _deleteOne,
                            ),
                ),
                const SizedBox(height: 12),
                _PaginationBar(
                  total: total,
                  page: page,
                  pageSize: _pageSize,
                  totalPages: totalPages,
                  onPageSizeChanged: (value) {
                    setState(() {
                      _pageSize = value;
                      _page = 0;
                    });
                  },
                  onPrevious:
                      page == 0 ? null : () => setState(() => _page = page - 1),
                  onNext: page >= totalPages - 1
                      ? null
                      : () => setState(() => _page = page + 1),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AssetTabs extends StatelessWidget {
  final Map<String, int> counts;
  final ValueChanged<int> onTap;

  const _AssetTabs({required this.counts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.df.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.df.stroke),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TabBar(
          isScrollable: true,
          onTap: onTap,
          labelColor: context.df.primary,
          unselectedLabelColor: context.df.textMid,
          indicatorColor: context.df.primary,
          dividerColor: context.df.stroke,
          tabs: [
            for (final kind in _assetKinds)
              Tab(
                height: 48,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(kind.icon, size: 18),
                    const SizedBox(width: 7),
                    Text(kind.label),
                    const SizedBox(width: 8),
                    _CountBadge(count: counts[kind.value] ?? 0),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: context.df.primaryDim.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.df.primary.withValues(alpha: 0.22)),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: context.df.primary,
        ),
      ),
    );
  }
}

class _AssetToolbar extends StatelessWidget {
  final TextEditingController searchController;
  final int selectedCount;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onCreate;
  final VoidCallback? onGenerate;
  final VoidCallback? onDelete;

  const _AssetToolbar({
    required this.searchController,
    required this.selectedCount,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onCreate,
    required this.onGenerate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = [
      FilledButton.icon(
        onPressed: onCreate,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('新增资产'),
      ),
      OutlinedButton.icon(
        onPressed: onGenerate,
        icon: const Icon(Icons.burst_mode_rounded, size: 18),
        label: const Text('批量生成'),
      ),
      OutlinedButton.icon(
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline_rounded, size: 18),
        label: const Text('批量删除'),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.df.red,
          side: BorderSide(color: context.df.red.withValues(alpha: 0.45)),
        ),
      ),
      if (selectedCount > 0)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            '已选 $selectedCount',
            style: TextStyle(
              color: context.df.textMid,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
    ];

    final search = _AssetSearchBar(
      controller: searchController,
      onChanged: onSearchChanged,
      onClear: onClearSearch,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: buttons),
            ],
          );
        }

        return Row(
          children: [
            Wrap(spacing: 10, runSpacing: 8, children: buttons),
            const Spacer(),
            SizedBox(width: 300, child: search),
          ],
        );
      },
    );
  }
}

class _AssetSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _AssetSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return SearchBar(
      controller: controller,
      hintText: '按名称搜索',
      leading: Icon(Icons.search_rounded, color: context.df.textLo, size: 20),
      trailing: [
        if (controller.text.isNotEmpty)
          IconButton(
            tooltip: '清空搜索',
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
      ],
      constraints: const BoxConstraints(minHeight: 44),
      elevation: WidgetStateProperty.all(0),
      backgroundColor: WidgetStateProperty.all(context.df.surface),
      surfaceTintColor: WidgetStateProperty.all(context.df.surface),
      side: WidgetStateProperty.all(BorderSide(color: context.df.stroke)),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      hintStyle: WidgetStateProperty.all(TextStyle(color: context.df.textLo)),
      textStyle: WidgetStateProperty.all(TextStyle(color: context.df.textHi)),
      onChanged: onChanged,
    );
  }
}

class _AssetTable extends StatelessWidget {
  final List<Asset> assets;
  final Set<String> selectedIds;
  final Set<String> expandedIds;
  final ValueChanged<String> onToggleSelected;
  final VoidCallback onToggleSelectPage;
  final ValueChanged<String> onToggleExpanded;
  final ValueChanged<Asset> onPreview;
  final ValueChanged<Asset> onGenerate;
  final ValueChanged<Asset> onEdit;
  final ValueChanged<Asset> onDelete;

  const _AssetTable({
    required this.assets,
    required this.selectedIds,
    required this.expandedIds,
    required this.onToggleSelected,
    required this.onToggleSelectPage,
    required this.onToggleExpanded,
    required this.onPreview,
    required this.onGenerate,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected = assets.isNotEmpty &&
        assets.every((asset) => selectedIds.contains(asset.id));
    final anySelected = assets.any((asset) => selectedIds.contains(asset.id));

    return Container(
      decoration: BoxDecoration(
        color: context.df.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.df.stroke),
      ),
      child: Column(
        children: [
          _AssetTableHeader(
            allSelected: allSelected,
            partiallySelected: anySelected && !allSelected,
            onToggleSelectPage: onToggleSelectPage,
          ),
          Expanded(
            child: ListView.builder(
              itemCount: assets.length,
              itemBuilder: (context, index) {
                final asset = assets[index];
                return _AssetTableRow(
                  asset: asset,
                  selected: selectedIds.contains(asset.id),
                  expanded: expandedIds.contains(asset.id),
                  onToggleSelected: () => onToggleSelected(asset.id),
                  onToggleExpanded: () => onToggleExpanded(asset.id),
                  onPreview: () => onPreview(asset),
                  onGenerate: () => onGenerate(asset),
                  onEdit: () => onEdit(asset),
                  onDelete: () => onDelete(asset),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetTableHeader extends StatelessWidget {
  final bool allSelected;
  final bool partiallySelected;
  final VoidCallback onToggleSelectPage;

  const _AssetTableHeader({
    required this.allSelected,
    required this.partiallySelected,
    required this.onToggleSelectPage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: context.df.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: Border(bottom: BorderSide(color: context.df.stroke)),
      ),
      child: Row(
        children: [
          _FixedCell(
            width: 48,
            child: Checkbox(
              tristate: true,
              value: allSelected ? true : (partiallySelected ? null : false),
              onChanged: (_) => onToggleSelectPage(),
            ),
          ),
          const _HeaderCell(width: 84, label: '预览图'),
          const _HeaderFlexCell(flex: 16, label: '名称'),
          const _HeaderFlexCell(flex: 24, label: '提示词'),
          const _HeaderFlexCell(flex: 22, label: '描述'),
          const _HeaderFlexCell(flex: 16, label: '备注'),
          const _HeaderCell(width: 100, label: '状态'),
          const _HeaderCell(width: 178, label: '操作'),
        ],
      ),
    );
  }
}

class _AssetTableRow extends StatelessWidget {
  final Asset asset;
  final bool selected;
  final bool expanded;
  final VoidCallback onToggleSelected;
  final VoidCallback onToggleExpanded;
  final VoidCallback onPreview;
  final VoidCallback onGenerate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AssetTableRow({
    required this.asset,
    required this.selected,
    required this.expanded,
    required this.onToggleSelected,
    required this.onToggleExpanded,
    required this.onPreview,
    required this.onGenerate,
    required this.onEdit,
    required this.onDelete,
  });

  bool get _busy => asset.status == 'queued' || asset.status == 'running';
  bool get _done => asset.status == 'done';
  bool get _failed => asset.status == 'failed';

  @override
  Widget build(BuildContext context) {
    final rowColor = selected
        ? context.df.primaryDim.withValues(alpha: 0.35)
        : context.df.surface;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: rowColor,
        border: Border(bottom: BorderSide(color: context.df.stroke)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggleExpanded,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 82),
              child: Row(
                children: [
                  _FixedCell(
                    width: 48,
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => onToggleSelected(),
                    ),
                  ),
                  _FixedCell(
                    width: 84,
                    child: Center(
                      child: InkWell(
                        onTap: onPreview,
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: MediaImage(asset.imageUrl, radius: 8),
                        ),
                      ),
                    ),
                  ),
                  _AssetTextCell(
                    flex: 16,
                    text: asset.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: context.df.textHi,
                    ),
                  ),
                  _AssetTextCell(
                    flex: 24,
                    text: asset.imagePrompt,
                    emptyText: '—',
                    tooltip: asset.imagePrompt,
                  ),
                  _AssetTextCell(
                    flex: 22,
                    text: asset.description,
                    emptyText: '—',
                  ),
                  _AssetTextCell(
                    flex: 16,
                    text: asset.note,
                    emptyText: '—',
                  ),
                  _FixedCell(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StatusChip(
                        asset.status,
                        dense: true,
                        errorTooltip: asset.error,
                      ),
                    ),
                  ),
                  _FixedCell(
                    width: 178,
                    child: _TableRowActions(
                      done: _done,
                      failed: _failed,
                      busy: _busy,
                      onGenerate: onGenerate,
                      onEdit: onEdit,
                      onDelete: onDelete,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) _AssetExpandedRow(asset: asset),
        ],
      ),
    );
  }
}

class _TableRowActions extends StatelessWidget {
  final bool done;
  final bool failed;
  final bool busy;
  final VoidCallback onGenerate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TableRowActions({
    required this.done,
    required this.failed,
    required this.busy,
    required this.onGenerate,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final label = failed ? '重试' : (done ? '重新生成' : '生成');
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          TextButton.icon(
            onPressed: busy ? null : onGenerate,
            style: TextButton.styleFrom(
              foregroundColor: context.df.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            icon: Icon(
              done || failed ? Icons.refresh_rounded : Icons.image_outlined,
              size: 16,
            ),
            label: Text(label),
          ),
          IconButton(
            tooltip: '编辑',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: '删除',
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline_rounded,
                size: 18, color: context.df.red),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _AssetExpandedRow extends StatelessWidget {
  final Asset asset;

  const _AssetExpandedRow({required this.asset});

  @override
  Widget build(BuildContext context) {
    final error = asset.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(132, 14, 18, 18),
      decoration: BoxDecoration(
        color: context.df.bg,
        border: Border(top: BorderSide(color: context.df.stroke)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _showAssetDetail(context, asset),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 148,
              height: 148,
              child: MediaImage(asset.imageUrl, radius: 8),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Wrap(
              spacing: 18,
              runSpacing: 14,
              children: [
                _DetailBlock(
                  label: '图片提示词',
                  text: asset.imagePrompt,
                  minWidth: 280,
                ),
                _DetailBlock(
                  label: '描述',
                  text: asset.description,
                  minWidth: 240,
                ),
                _DetailBlock(
                  label: '备注',
                  text: asset.note,
                  minWidth: 200,
                ),
                if (asset.status == 'failed' &&
                    error != null &&
                    error.isNotEmpty)
                  _DetailBlock(
                    label: '失败原因',
                    text: error,
                    minWidth: 280,
                    color: context.df.red,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  final String label;
  final String text;
  final double minWidth;
  final Color? color;

  const _DetailBlock({
    required this.label,
    required this.text,
    required this.minWidth,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth, maxWidth: 460),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.df.textLo,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            text.trim().isEmpty ? '—' : text,
            style: TextStyle(
              color: color ?? context.df.textMid,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final double width;
  final String label;

  const _HeaderCell({required this.width, required this.label});

  @override
  Widget build(BuildContext context) {
    return _FixedCell(
      width: width,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: context.df.textMid,
        ),
      ),
    );
  }
}

class _HeaderFlexCell extends StatelessWidget {
  final int flex;
  final String label;

  const _HeaderFlexCell({required this.flex, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.df.textMid,
          ),
        ),
      ),
    );
  }
}

class _AssetTextCell extends StatelessWidget {
  final int flex;
  final String text;
  final String emptyText;
  final String? tooltip;
  final TextStyle? style;

  const _AssetTextCell({
    required this.flex,
    required this.text,
    this.emptyText = '',
    this.tooltip,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final value = text.trim().isEmpty ? emptyText : text;
    final child = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style ??
          TextStyle(
            color: text.trim().isEmpty ? context.df.textLo : context.df.textMid,
          ),
    );

    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: tooltip == null || tooltip!.trim().isEmpty
            ? child
            : Tooltip(message: tooltip!, child: child),
      ),
    );
  }
}

class _FixedCell extends StatelessWidget {
  final double width;
  final Widget child;

  const _FixedCell({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: child,
      ),
    );
  }
}

class _AssetCardGrid extends StatelessWidget {
  final List<Asset> assets;
  final Set<String> selectedIds;
  final bool selectionMode;
  final ValueChanged<String> onToggleSelected;
  final ValueChanged<Asset> onPreview;
  final ValueChanged<Asset> onGenerate;
  final ValueChanged<Asset> onEdit;
  final ValueChanged<Asset> onDelete;

  const _AssetCardGrid({
    required this.assets,
    required this.selectedIds,
    required this.selectionMode,
    required this.onToggleSelected,
    required this.onPreview,
    required this.onGenerate,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        childAspectRatio: 0.74,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
      ),
      itemCount: assets.length,
      itemBuilder: (context, index) {
        final asset = assets[index];
        return _AssetCard(
          asset: asset,
          selected: selectedIds.contains(asset.id),
          selectionMode: selectionMode,
          onToggleSelected: () => onToggleSelected(asset.id),
          onPreview: () => onPreview(asset),
          onGenerate: () => onGenerate(asset),
          onEdit: () => onEdit(asset),
          onDelete: () => onDelete(asset),
        );
      },
    );
  }
}

/// 单个素材卡片：方图 + 状态角标 + 名称/描述 + 操作行。
class _AssetCard extends StatelessWidget {
  final Asset asset;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onToggleSelected;
  final VoidCallback onPreview;
  final VoidCallback onGenerate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AssetCard({
    required this.asset,
    required this.selected,
    required this.selectionMode,
    required this.onToggleSelected,
    required this.onPreview,
    required this.onGenerate,
    required this.onEdit,
    required this.onDelete,
  });

  bool get _busy => asset.status == 'queued' || asset.status == 'running';
  bool get _done => asset.status == 'done';
  bool get _failed => asset.status == 'failed';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final error = asset.error;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: selectionMode ? onToggleSelected : onPreview,
        onLongPress: onToggleSelected,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Stack(
                      children: [
                        Positioned.fill(child: MediaImage(asset.imageUrl)),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: StatusChip(
                            asset.status,
                            dense: true,
                            errorTooltip: error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.name,
                        style: theme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (asset.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          asset.description,
                          style: theme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (asset.note.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          asset.note,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.df.textLo,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (_failed && error != null && error.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Tooltip(
                          message: error,
                          child: Text(
                            error,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.df.red,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _MiniButton(
                              icon: _done || _failed
                                  ? Icons.refresh_rounded
                                  : Icons.image_rounded,
                              label: _failed ? '重试' : (_done ? '重新生成' : '生成图片'),
                              color: context.df.primary,
                              onPressed: _busy ? null : onGenerate,
                            ),
                            const SizedBox(width: 4),
                            _MiniButton(
                              icon: Icons.edit_outlined,
                              label: '编辑',
                              color: context.df.textMid,
                              onPressed: onEdit,
                            ),
                            const SizedBox(width: 4),
                            _MiniButton(
                              icon: Icons.delete_outline_rounded,
                              label: '删除',
                              color: context.df.red,
                              onPressed: onDelete,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (selectionMode || selected)
              Positioned(
                top: 8,
                left: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.df.surface.withValues(alpha: 0.92),
                    shape: BoxShape.circle,
                  ),
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => onToggleSelected(),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 紧凑型文字按钮（卡片脚部用）。
class _MiniButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _MiniButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;
  final ValueChanged<int> onPageSizeChanged;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _PaginationBar({
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
    required this.onPageSizeChanged,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final start = total == 0 ? 0 : page * pageSize + 1;
    final end = math.min(total, (page + 1) * pageSize);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.df.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.df.stroke),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text(
            '显示 $start-$end / 共 $total 个',
            style: TextStyle(color: context.df.textMid),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('每页', style: TextStyle(color: context.df.textMid)),
              const SizedBox(width: 8),
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: context.df.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.df.stroke),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: pageSize,
                    items: const [
                      DropdownMenuItem(value: 10, child: Text('10')),
                      DropdownMenuItem(value: 20, child: Text('20')),
                      DropdownMenuItem(value: 50, child: Text('50')),
                    ],
                    onChanged: (value) {
                      if (value != null) onPageSizeChanged(value);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: '上一页',
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(
                '第 ${page + 1} / $totalPages 页',
                style: TextStyle(
                  color: context.df.textHi,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                tooltip: '下一页',
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssetEmptyState extends StatelessWidget {
  final bool hasQuery;
  final String kindLabel;
  final VoidCallback onCreate;

  const _AssetEmptyState({
    required this.hasQuery,
    required this.kindLabel,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyHint(
      icon: hasQuery ? Icons.search_off_rounded : Icons.palette_outlined,
      title: hasQuery ? '没有匹配的资产' : '还没有$kindLabel资产',
      subtitle: hasQuery ? '换一个名称关键词试试' : '可以手动新增，或从流水线生成素材后回到这里管理',
      action: FilledButton.icon(
        onPressed: onCreate,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('新增资产'),
      ),
    );
  }
}

/// 详情弹窗：大图 + 描述 / 图片提示词 / 备注（可选中复制）。
void _showAssetDetail(BuildContext context, Asset asset) {
  showDialog<void>(
    context: context,
    builder: (context) => Consumer(builder: (context, ref, _) {
      final latest = _findAsset(
              asset.projectId.isEmpty
                  ? null
                  : ref.watch(assetsProvider(asset.projectId)).value,
              asset.id) ??
          asset;
      final error = latest.error;
      final theme = Theme.of(context).textTheme;
      final takesAsync = ref.watch(assetImageTakesProvider(latest.id));
      final selectedImagePath =
          _selectedImagePath(latest.imageUrl, takesAsync.value);
      final imageBusy = latest.status == 'queued' || latest.status == 'running';
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        latest.name,
                        style: theme.titleLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    StatusChip(latest.status, errorTooltip: error),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: 480, maxHeight: 480),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: MediaImage(selectedImagePath, radius: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ImageTakesStrip(
                  value: takesAsync,
                  onSelect: (take) => runAction(context, ref, () async {
                    await ref.read(engineProvider).selectImageTake(take.id);
                    ref.invalidate(assetImageTakesProvider(latest.id));
                    if (latest.projectId.isNotEmpty) {
                      ref.invalidate(assetsProvider(latest.projectId));
                    }
                  }, successMessage: '已切换图片版本'),
                ),
                if (latest.status == 'failed' &&
                    error != null &&
                    error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    error,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.df.red,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _DialogTextBlock(label: '描述', text: latest.description),
                const SizedBox(height: 16),
                _DialogTextBlock(label: '图片提示词', text: latest.imagePrompt),
                const SizedBox(height: 16),
                _DialogTextBlock(label: '备注', text: latest.note),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: imageBusy
                            ? null
                            : () async {
                                final instruction =
                                    await showRepaintInstructionDialog(context);
                                if (instruction == null || !context.mounted) {
                                  return;
                                }
                                await runAction(context, ref, () async {
                                  await ref
                                      .read(engineProvider)
                                      .repaintAsset(latest.id, instruction);
                                  ref.invalidate(
                                      assetImageTakesProvider(latest.id));
                                  if (latest.projectId.isNotEmpty) {
                                    ref.invalidate(
                                        assetsProvider(latest.projectId));
                                  }
                                }, successMessage: '重绘任务已排队');
                              },
                        icon: const Icon(Icons.brush_outlined, size: 18),
                        label: const Text('重绘'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }),
  );
}

Asset? _findAsset(List<Asset>? assets, String id) {
  if (assets == null) return null;
  for (final asset in assets) {
    if (asset.id == id) return asset;
  }
  return null;
}

String? _selectedImagePath(String? fallback, List<ImageTake>? takes) {
  if (takes == null) return fallback;
  for (final take in takes) {
    if (take.selected) return take.imagePath;
  }
  return fallback;
}

class _DialogTextBlock extends StatelessWidget {
  final String label;
  final String text;

  const _DialogTextBlock({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.df.textLo,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.df.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.df.stroke),
          ),
          child: SelectableText(
            text.trim().isEmpty ? '—' : text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.6),
          ),
        ),
      ],
    );
  }
}

class _AssetCreateDialog extends ConsumerStatefulWidget {
  final String projectId;
  final String kind;
  final String kindLabel;

  const _AssetCreateDialog({
    required this.projectId,
    required this.kind,
    required this.kindLabel,
  });

  @override
  ConsumerState<_AssetCreateDialog> createState() => _AssetCreateDialogState();
}

class _AssetCreateDialogState extends ConsumerState<_AssetCreateDialog> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _prompt = TextEditingController();
  final _note = TextEditingController();
  String? _nameError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _prompt.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = '请输入名称');
      return;
    }

    setState(() {
      _saving = true;
      _nameError = null;
    });
    var ok = false;
    await runAction(context, ref, () async {
      await ref.read(engineProvider).createAsset(
            widget.projectId,
            kind: widget.kind,
            name: _name.text.trim(),
            description: _desc.text.trim(),
            imagePrompt: _prompt.text.trim(),
            note: _note.text.trim(),
          );
      ok = true;
    }, successMessage: '资产已新增');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ref.invalidate(assetsProvider(widget.projectId));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('新增${widget.kindLabel}资产'),
      content: _AssetFields(
        name: _name,
        desc: _desc,
        prompt: _prompt,
        note: _note,
        nameError: _nameError,
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('新增'),
        ),
      ],
    );
  }
}

/// 编辑弹窗：名称 / 描述 / 图片提示词 / 备注。
class _AssetEditDialog extends ConsumerStatefulWidget {
  final Asset asset;
  final String projectId;

  const _AssetEditDialog({required this.asset, required this.projectId});

  @override
  ConsumerState<_AssetEditDialog> createState() => _AssetEditDialogState();
}

class _AssetEditDialogState extends ConsumerState<_AssetEditDialog> {
  late final _name = TextEditingController(text: widget.asset.name);
  late final _desc = TextEditingController(text: widget.asset.description);
  late final _prompt = TextEditingController(text: widget.asset.imagePrompt);
  late final _note = TextEditingController(text: widget.asset.note);
  String? _nameError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _prompt.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = '请输入名称');
      return;
    }

    setState(() {
      _saving = true;
      _nameError = null;
    });
    var ok = false;
    await runAction(context, ref, () async {
      await ref.read(engineProvider).updateAsset(
            widget.asset.id,
            name: _name.text.trim(),
            description: _desc.text.trim(),
            imagePrompt: _prompt.text.trim(),
            note: _note.text.trim(),
          );
      ok = true;
    }, successMessage: '素材已保存');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ref.invalidate(assetsProvider(widget.projectId));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑素材'),
      content: _AssetFields(
        name: _name,
        desc: _desc,
        prompt: _prompt,
        note: _note,
        nameError: _nameError,
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}

class _AssetFields extends StatelessWidget {
  final TextEditingController name;
  final TextEditingController desc;
  final TextEditingController prompt;
  final TextEditingController note;
  final String? nameError;

  const _AssetFields({
    required this.name,
    required this.desc,
    required this.prompt,
    required this.note,
    required this.nameError,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration:
                  InputDecoration(labelText: '名称 *', errorText: nameError),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: desc,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: '描述',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: prompt,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '图片提示词',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '备注',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> _confirmDelete(BuildContext context, {required int count}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(count == 1 ? '删除资产' : '批量删除资产'),
          content: Text(
            count == 1
                ? '确定要删除这个资产吗？此操作不可撤销。'
                : '确定要删除选中的 $count 个资产吗？此操作不可撤销。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: context.df.red,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;
}
