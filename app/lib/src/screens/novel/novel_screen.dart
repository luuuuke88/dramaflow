// 章节管理页（照抄 views/novel/index.vue）：
// 工具栏【导入原文｜批量删除+数｜事件分析+数 ‖ 搜索】+ 章节表（复选/序号/卷/章节名/
// 章节内容截断+查看详情/事件三态/操作）+ 分页；事件列表为页内第二 Tab。
// 数据刷新：watch 队列事件（jobsGeneration），无轮询。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/novel.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_data_table.dart';
import '../../widgets/df_empty.dart';
import '../../widgets/df_search_field.dart';
import '../../widgets/df_status_tag.dart';
import 'edit_novel_dialog.dart';
import 'event_analysis_view.dart';
import 'event_tab.dart';
import 'import_novel_dialog.dart';

const _previewMaxLength = 80;

class NovelScreen extends ConsumerStatefulWidget {
  final int projectId;
  const NovelScreen({super.key, required this.projectId});

  @override
  ConsumerState<NovelScreen> createState() => _NovelScreenState();
}

class _NovelScreenState extends ConsumerState<NovelScreen> {
  int _page = 1;
  static const _limit = 10;
  String _search = '';
  final Set<String> _selected = {};

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<int> get _selectedIds => _selected.map(int.parse).toList();

  Future<void> _batchDelete() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.novelMsgBatchDeleteHeader),
        content: Text(l10n.novelMsgBatchDeleteBody('${_selected.length}')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.commonCancel)),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: context.df.danger),
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(engineProvider).deleteNovels(_selectedIds);
    setState(() => _selected.clear());
    _toast(l10n.novelMsgBatchDeleteSuccess);
  }

  Future<void> _deleteOne(NovelRow row) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.novelMsgDeleteHeader),
        content: Text(l10n.novelMsgDeleteBody(row.chapter ?? '')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.commonCancel)),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: context.df.danger),
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(engineProvider).deleteNovels([row.id]);
    setState(() => _selected.remove('${row.id}'));
    _toast(l10n.novelMsgDeleteSuccess);
  }

  Future<void> _eventAnalysis() async {
    final l10n = context.l10n;
    if (_selected.isEmpty) {
      _toast(l10n.novelImportMsgSelectChapters);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.novelMsgEventAnalysisHeader),
        content: Text(l10n.novelMsgEventAnalysisBody('${_selected.length}')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.commonConfirm)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await showEventAnalysisView(context, ref,
        projectId: widget.projectId, novelIds: _selectedIds);
  }

  void _showDetail(String title, String content) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: SelectableText(content)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(context.l10n.commonConfirm)),
        ],
      ),
    );
  }

  Widget _eventCell(NovelRow row) {
    final l10n = context.l10n;
    final df = context.df;
    switch (row.eventState) {
      case 0:
        return DFStatusTag(kind: DFStatusKind.processing, text: l10n.novelGenerating);
      case -1:
        return InkWell(
          onTap: () => _showDetail(
              l10n.novelGenFailed,
              localizeReason(l10n, row.errorReason) ??
                  (row.errorReason ?? '')),
          child: Text(l10n.novelGenFailed,
              style: TextStyle(color: df.danger, fontSize: 13)),
        );
      default:
        final event = row.event ?? '';
        if (event.isEmpty) {
          return Text(l10n.novelNone,
              style: TextStyle(color: df.textTertiary, fontSize: 13));
        }
        final truncated = event.length > _previewMaxLength;
        return Row(children: [
          Expanded(
            child: Text(
              truncated ? event.substring(0, _previewMaxLength) : event,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (truncated)
            InkWell(
              onTap: () => _showDetail(l10n.novelColEvent, event),
              child: Text(l10n.novelViewDetail,
                  style: TextStyle(color: df.primary, fontSize: 12)),
            ),
        ]);
    }
  }

  Widget _chaptersTab() {
    final l10n = context.l10n;
    final df = context.df;
    // 队列事件驱动刷新
    ref.watch(jobsGenerationProvider);
    final engine = ref.watch(engineProvider);
    final result = engine.novels(widget.projectId,
        page: _page, limit: _limit, search: _search.isEmpty ? null : _search);

    Widget contentCell(NovelRow row) {
      final content = row.chapterData ?? '';
      final truncated = content.length > _previewMaxLength;
      return Row(children: [
        Expanded(
          child: Text(
            truncated ? content.substring(0, _previewMaxLength) : content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (truncated)
          InkWell(
            onTap: () =>
                _showDetail(row.chapter ?? l10n.novelColChapterData, content),
            child: Text(l10n.novelViewDetail,
                style: TextStyle(color: df.primary, fontSize: 12)),
          ),
      ]);
    }

    Widget operationCell(NovelRow row) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(
            onPressed: () async {
              final saved = await showEditNovelDialog(context, ref, row: row);
              if (saved == true) setState(() {});
            },
            child: Text(l10n.novelEdit, style: const TextStyle(fontSize: 13)),
          ),
          TextButton(
            onPressed: () => _deleteOne(row),
            child: Text(l10n.novelDelete,
                style: TextStyle(fontSize: 13, color: df.danger)),
          ),
        ]);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        child: Row(children: [
          FilledButton.icon(
            onPressed: () async {
              final saved = await showImportNovelDialog(context, ref,
                  projectId: widget.projectId);
              if (saved == true) setState(() {});
            },
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.novelImportText),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _selected.isEmpty ? null : _batchDelete,
            style: FilledButton.styleFrom(
                backgroundColor: df.danger,
                disabledBackgroundColor: df.danger.withValues(alpha: 0.35)),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(_selected.isEmpty
                ? l10n.novelBatchDelete
                : '${l10n.novelBatchDelete} (${_selected.length})'),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _eventAnalysis,
            icon: const Icon(Icons.analytics_outlined, size: 18),
            label: Text(_selected.isEmpty
                ? l10n.novelEventAnalysis
                : '${l10n.novelEventAnalysis} (${_selected.length})'),
          ),
          const Spacer(),
          DFSearchField(
            hint: l10n.novelSearchPlaceholder,
            onSearch: (q) => setState(() {
              _search = q;
              _page = 1;
            }),
          ),
        ]),
      ),
      Expanded(
        child: result.total == 0 && _search.isEmpty
            ? Center(
                child: DFEmpty(
                  text: l10n.novelEventNoData,
                  action: FilledButton.icon(
                    onPressed: () async {
                      final saved = await showImportNovelDialog(context, ref,
                          projectId: widget.projectId);
                      if (saved == true) setState(() {});
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.novelImportText),
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: DFDataTable(
                  columns: [
                    DFDataColumn(label: l10n.novelColId),
                    DFDataColumn(label: l10n.novelColReel),
                    DFDataColumn(label: l10n.novelColChapter),
                    DFDataColumn(label: l10n.novelColChapterData),
                    DFDataColumn(label: l10n.novelColEvent),
                    DFDataColumn(label: l10n.novelColOperation),
                  ],
                  selectable: true,
                  selectedIds: _selected,
                  onSelectionChanged: (ids) =>
                      setState(() => _selected
                        ..clear()
                        ..addAll(ids)),
                  pagination: DFPagination(
                      page: _page, pageSize: _limit, total: result.total),
                  onPageChange: (p) => setState(() => _page = p),
                  rows: [
                    for (final row in result.data)
                      DFDataRow(
                        id: '${row.id}',
                        cells: [
                          Text('${row.chapterIndex}'),
                          Text(row.reel ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(row.chapter ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          contentCell(row),
                          _eventCell(row),
                          operationCell(row),
                        ],
                      ),
                  ],
                  mobileCardBuilder: (c, dfRow) {
                    final row = result.data
                        .firstWhere((n) => '${n.id}' == dfRow.id);
                    return ListTile(
                      title: Text('${row.chapterIndex} · ${row.chapter ?? ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row.reel ?? '',
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 4),
                            _eventCell(row),
                          ]),
                      trailing: operationCell(row),
                    );
                  },
                ),
              ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 12),
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l10n.menuNovel),
              Tab(text: l10n.novelColEvent),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(children: [
            _chaptersTab(),
            EventTab(projectId: widget.projectId),
          ]),
        ),
      ]),
    );
  }
}
