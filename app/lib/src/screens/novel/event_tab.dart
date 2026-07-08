// 事件列表 Tab（照抄 event.vue）：事件表（ID/事件名称/来源章节/事件过程/创建时间/操作）
// + 重新生成事件 + 批量删除 + 空态生成按钮。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../engine/events.dart';
import '../../engine/novel.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_data_table.dart';
import '../../widgets/df_empty.dart';
import '../../widgets/df_search_field.dart';
import '../../widgets/policy_confirm.dart';

class EventTab extends ConsumerStatefulWidget {
  final int projectId;
  const EventTab({super.key, required this.projectId});

  @override
  ConsumerState<EventTab> createState() => _EventTabState();
}

class _EventTabState extends ConsumerState<EventTab> {
  int _page = 1;
  static const _limit = 10;
  String _search = '';
  final Set<String> _selected = {};

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _regenerate() async {
    final engine = ref.read(engineProvider);
    final novelIds =
        engine.novelIndex(widget.projectId).map((e) => e.id).toList();
    if (novelIds.isEmpty) {
      _toast(context.l10n.novelImportMsgSelectChapters);
      return;
    }
    if (!await confirmPolicyAction(
      context,
      engine.config,
      taskClass: 'event_generation',
      description: context.l10n.novelEventRegenerate,
      units: novelIds.length,
    )) {
      return;
    }
    if (!mounted) return;
    engine.generateEvents(widget.projectId, novelIds);
    _toast(context.l10n.novelEventGeneratingHint);
  }

  Future<void> _batchDelete() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.novelEventMsgBatchDeleteHeader),
        content: Text(l10n.novelEventMsgBatchDeleteBody('${_selected.length}')),
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
    ref.read(engineProvider).deleteEvents(_selected.map(int.parse).toList());
    setState(() => _selected.clear());
    _toast(l10n.novelEventMsgBatchDeleteSuccess);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    ref.watch(jobsGenerationProvider);
    final result = ref.watch(engineProvider).events(widget.projectId,
        page: _page, limit: _limit, search: _search.isEmpty ? null : _search);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        child: Row(children: [
          FilledButton.icon(
            onPressed: _regenerate,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l10n.novelEventRegenerate),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _selected.isEmpty ? null : _batchDelete,
            style: FilledButton.styleFrom(
                backgroundColor: df.danger,
                disabledBackgroundColor: df.danger.withValues(alpha: 0.35)),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(_selected.isEmpty
                ? l10n.novelEventBatchDelete
                : '${l10n.novelEventBatchDelete} (${_selected.length})'),
          ),
          const Spacer(),
          DFSearchField(
            hint: l10n.novelEventColEventName,
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
                  action: FilledButton(
                    onPressed: _regenerate,
                    child: Text(l10n.novelEventGenerate),
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: DFDataTable(
                  columns: [
                    DFDataColumn(label: l10n.novelEventColId),
                    DFDataColumn(label: l10n.novelEventColEventName),
                    DFDataColumn(label: l10n.novelEventColChapters),
                    DFDataColumn(label: l10n.novelEventColDetail),
                    DFDataColumn(label: l10n.novelEventColCreateTime),
                    DFDataColumn(label: l10n.novelEventColOperation),
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
                    for (final e in result.list)
                      DFDataRow(
                        id: '${e.id}',
                        cells: [
                          Text('${e.id}'),
                          Text(e.name ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(e.chapters.join(','),
                              style: const TextStyle(fontSize: 12)),
                          Text(e.detail ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                          Text(
                            e.createTime == null
                                ? ''
                                : DateFormat('yyyy-MM-dd HH:mm').format(
                                    DateTime.fromMillisecondsSinceEpoch(
                                        e.createTime!)),
                            style: const TextStyle(fontSize: 12),
                          ),
                          TextButton(
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: Text(l10n.novelEventMsgDeleteHeader),
                                  content: Text(l10n.novelEventMsgDeleteBody),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, false),
                                        child: Text(l10n.commonCancel)),
                                    FilledButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child: Text(l10n.commonDelete)),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                ref.read(engineProvider).deleteEvents([e.id]);
                                setState(() {});
                                _toast(l10n.novelEventMsgDeleteSuccess);
                              }
                            },
                            child: Text(l10n.novelEventDelete,
                                style:
                                    TextStyle(fontSize: 13, color: df.danger)),
                          ),
                        ],
                      ),
                  ],
                  mobileCardBuilder: (c, dfRow) {
                    final e =
                        result.list.firstWhere((x) => '${x.id}' == dfRow.id);
                    return ListTile(
                      title: Text(e.name ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${l10n.novelEventColChapters}: ${e.chapters.join(',')}',
                          style: const TextStyle(fontSize: 12)),
                    );
                  },
                ),
              ),
      ),
    ]);
  }
}
