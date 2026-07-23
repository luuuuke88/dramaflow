// 章节管理页（照抄 views/novel/index.vue）：
// 工具栏【导入原文｜批量删除+数｜事件分析+数 ‖ 搜索】+ 章节表（复选/序号/卷/章节名/
// 章节内容截断+查看详情/事件三态/操作）+ 分页。
// 数据刷新：watch 队列事件（jobsGeneration），无轮询。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../engine/events.dart';
import '../../engine/novel.dart';
import '../../engine/scripts.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';
import '../../widgets/df_data_table.dart';
import '../../widgets/df_empty.dart';
import '../../widgets/df_search_field.dart';
import '../../widgets/df_status_tag.dart';
import '../../widgets/policy_confirm.dart';
import 'edit_novel_dialog.dart';
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
  bool _nextStepBannerDismissed = false;

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<int> get _selectedIds => _selected.map(int.parse).toList();

  Future<void> _batchDelete() async {
    final l10n = context.l10n;
    final engine = ref.read(engineProvider);
    // 与单行操作栏的 isGenerating 保护对齐：事件生成 worker 在网络请求期间持有
    // novelId，若此时把行删掉，worker 返回后会对已删除的 novelId 插入新事件行，
    // 产生 events() 的 INNER JOIN 永远查不到、UI 也删不掉的孤儿事件行。
    final selectedIds = _selectedIds;
    final generating = engine.generatingNovelIds(selectedIds).toSet();
    final deletableIds =
        selectedIds.where((id) => !generating.contains(id)).toList();
    if (deletableIds.isEmpty) {
      _toast(l10n.novelMsgBatchDeleteAllGenerating);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.novelMsgBatchDeleteHeader),
        content: Text(l10n.novelMsgBatchDeleteBody('${deletableIds.length}')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.commonCancel)),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.df.danger),
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    engine.deleteNovels(deletableIds);
    setState(() => _selected.removeAll(deletableIds.map((id) => '$id')));
    if (generating.isNotEmpty) {
      _toast(l10n.novelMsgBatchDeleteSkippedGenerating('${generating.length}'));
    } else {
      _toast(l10n.novelMsgBatchDeleteSuccess);
    }
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
              style: FilledButton.styleFrom(backgroundColor: context.df.danger),
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

  Future<void> _generateSelectedEvents() async {
    final l10n = context.l10n;
    if (_selected.isEmpty) {
      _toast(l10n.novelImportMsgSelectChapters);
      return;
    }
    final config = ref.read(engineProvider).config;
    if (!await confirmPolicyAction(
      context,
      config,
      taskClass: 'event_generation',
      description: l10n.novelGenerateSelectedEvents,
      units: _selected.length,
    )) {
      return;
    }
    if (!mounted) return;
    ref.read(engineProvider).generateEvents(widget.projectId, _selectedIds);
    _toast(l10n.novelEventGeneratingHint);
  }

  void _showDetail(String title, String content) {
    showDFAdaptiveDialog<void>(
      context,
      title: title,
      desktopWidthFactor: 0.5,
      builder: (c) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SelectableText(content),
      ),
    );
  }

  Widget _eventCell(NovelRow row) {
    final l10n = context.l10n;
    final df = context.df;
    switch (row.eventState) {
      case 0:
        return DFStatusTag(
            kind: DFStatusKind.processing, text: l10n.novelGenerating);
      case -1:
        return InkWell(
          onTap: () => _showDetail(l10n.novelGenFailed,
              localizeReason(l10n, row.errorReason) ?? (row.errorReason ?? '')),
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

    Widget contentCell(NovelRow row, {int maxLines = 1}) {
      final content = row.chapterData ?? '';
      final truncated = content.length > _previewMaxLength;
      return Row(children: [
        Expanded(
          child: Text(
            truncated ? content.substring(0, _previewMaxLength) : content,
            maxLines: maxLines,
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

    Widget operationCell(NovelRow row) {
      final isGenerating = row.eventState == 0;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton(
          onPressed: isGenerating
              ? null
              : () async {
                  final saved =
                      await showEditNovelDialog(context, ref, row: row);
                  if (saved == true) setState(() {});
                },
          child: Text(l10n.novelEdit, style: const TextStyle(fontSize: 13)),
        ),
        TextButton(
          onPressed: isGenerating ? null : () => _deleteOne(row),
          child: Text(l10n.novelDelete,
              style: TextStyle(fontSize: 13, color: df.danger)),
        ),
      ]);
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        child: LayoutBuilder(builder: (context, constraints) {
          // 可用宽度 720-839dp 时仍处在 AppShell 的移动布局；这里的
          // 搜索框加三项操作在 760dp（800dp 设备扣掉两侧 padding）已发生
          // RenderFlex 溢出，故与移动壳边界一致地改用纵向搜索 + Wrap。
          final compact = constraints.maxWidth < 840;

          Future<void> openImport() async {
            final saved = await showImportNovelDialog(context, ref,
                projectId: widget.projectId);
            if (saved == true) setState(() {});
          }

          final search = DFSearchField(
            hint: l10n.novelSearchPlaceholder,
            width: compact ? constraints.maxWidth : 240,
            onSearch: (q) => setState(() {
              _search = q;
              _page = 1;
            }),
          );
          final actions = <Widget>[
            FilledButton.icon(
              onPressed: openImport,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.novelImportText),
            ),
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
            OutlinedButton.icon(
              onPressed: _selected.isEmpty ? null : _generateSelectedEvents,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text(_selected.isEmpty
                  ? l10n.novelEventAnalysis
                  : '${l10n.novelEventAnalysis} (${_selected.length})'),
            ),
          ];

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            );
          }

          return Row(children: [
            ...actions.expand((button) => [button, const SizedBox(width: 10)]),
            const Spacer(),
            search,
          ]);
        }),
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
                  onSelectionChanged: (ids) => setState(() => _selected
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
                    final row =
                        result.data.firstWhere((n) => '${n.id}' == dfRow.id);
                    return ListTile(
                      title: Text('${row.chapterIndex} · ${row.chapter ?? ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row.reel ?? '',
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 4),
                            contentCell(row, maxLines: 2),
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

  Widget? _nextStepBanner() {
    if (_nextStepBannerDismissed) return null;
    ref.watch(jobsGenerationProvider);
    final engine = ref.watch(engineProvider);
    final hasEvents = engine.events(widget.projectId, limit: 1).total > 0;
    if (!hasEvents) return null;
    final hasScript = engine.scripts(widget.projectId).isNotEmpty;
    if (hasScript) return null;

    final l10n = context.l10n;
    final df = context.df;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: df.primarySubtle,
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        border: Border.all(color: df.primary.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(Icons.auto_awesome_rounded, size: 20, color: df.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l10n.novelNextStepBannerText,
            style: DFTokens.body14.copyWith(color: df.textPrimary),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: () => context.go('/p/${widget.projectId}/scriptAgent'),
          child: Text(l10n.novelNextStepBannerButton),
        ),
        IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(Icons.close_rounded, size: 18),
          onPressed: () => setState(() => _nextStepBannerDismissed = true),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final banner = _nextStepBanner();
    if (banner == null) return _chaptersTab();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: banner,
      ),
      Expanded(child: _chaptersTab()),
    ]);
  }
}
