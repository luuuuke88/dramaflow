// 资产中心（照抄 views/assets/index.vue，详见 docs/reference/p2-assets-brief.md）：
// 5 tabs（角色/道具/场景/素材/音频）+ 工具栏（新增/生成提示词/生成图片/批量删除/搜索）
// + 父子层级表（预览缩略图/提示词生成态/操作），行可展开子资产。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../engine/assets.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/local_media_preview.dart';
import '../../widgets/df_data_table.dart';
import '../../widgets/df_empty.dart';
import '../../widgets/df_search_field.dart';
import '../../widgets/df_status_tag.dart';
import 'add_asset_dialog.dart';
import 'add_audio_asset_dialog.dart';
import 'add_tts_audio_dialog.dart';
import 'batch_generation_dialog.dart';
import 'generate_image_dialog.dart';
import '../../widgets/df_toast.dart';

const assetTabs = ['role', 'tool', 'scene', 'clip', 'audio'];

class AssetsScreen extends ConsumerStatefulWidget {
  final int projectId;
  const AssetsScreen({super.key, required this.projectId});

  @override
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: assetTabs.length, vsync: this)
        ..addListener(() {
          if (!_tab.indexIsChanging) {
            setState(() {
              _search = '';
              _page = 1;
              _selected.clear();
            });
          }
        });
  String _search = '';
  int _page = 1;
  DFSortState _sort = DFSortState.none;
  static const _limit = 10;
  final Set<String> _selected = {};
  final Set<int> _expanded = {};

  String get _type => assetTabs[_tab.index];

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    showDFToast(context, msg);
  }

  String _tabLabel(String type) => switch (type) {
        'role' => context.l10n.assetsTabRole,
        'tool' => context.l10n.assetsTabTool,
        'scene' => context.l10n.assetsTabScene,
        'clip' => context.l10n.assetsTabClip,
        _ => context.l10n.assetsTabAudio,
      };

  Future<void> _batchDelete() async {
    final l10n = context.l10n;
    if (_selected.isEmpty) {
      _toast(l10n.assetsSelectAtLeastOne);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.assetsConfirmDeleteHeader),
        content: Text(l10n.assetsConfirmBatchDeleteBody('${_selected.length}')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.assetsCancelBtn)),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.df.danger),
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.assetsDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(engineProvider).deleteAssets(_selected.map(int.parse).toList());
    setState(() => _selected.clear());
    _toast(l10n.assetsDeleteSuccess);
  }

  Future<void> _deleteOne(AssetRow row) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.assetsConfirmDeleteHeader),
        content: Text(l10n.assetsConfirmDeleteBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.assetsCancelBtn)),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.df.danger),
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.assetsDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(engineProvider).deleteAssets([row.id]);
    setState(() => _selected.remove('${row.id}'));
    _toast(l10n.assetsDeleteSuccess);
  }

  Future<void> _openAdd({AssetRow? existing}) async {
    final saved = _type == 'audio'
        ? await showAddAudioAssetDialog(context, ref,
            projectId: widget.projectId, existing: existing)
        : await showAddAssetDialog(context, ref,
            projectId: widget.projectId, type: _type, existing: existing);
    if (saved == true) setState(() {});
  }

  Widget _preview(AssetRow row) {
    final df = context.df;
    if (row.imageState == stateGenerating) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: df.surfaceMuted,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    final rel = row.filePath;
    if (rel == null || rel.isEmpty) {
      if (row.type == 'audio') {
        return Icon(Icons.music_note_outlined,
            size: 28, color: df.textSecondary);
      }
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: df.surfaceMuted,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(Icons.image_not_supported_outlined,
            size: 20, color: df.textTertiary),
      );
    }
    final abs = ref.read(engineProvider).mediaAbsPath(rel);
    final kind = localMediaKind(rel);
    if (kind == LocalMediaKind.video || kind == LocalMediaKind.audio) {
      final icon = kind == LocalMediaKind.video
          ? Icons.play_circle_outline
          : Icons.music_note_outlined;
      return InkWell(
        key: ValueKey('asset-media-trigger-${row.id}'),
        onTap: () => showLocalMediaPreview(context,
            absPath: abs, kind: kind, title: row.name),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: df.surfaceMuted,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 28, color: df.textSecondary),
        ),
      );
    }
    return InkWell(
      onTap: () => showLocalMediaPreview(context,
          absPath: abs, kind: LocalMediaKind.image),
      borderRadius: BorderRadius.circular(6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(File(abs),
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => Container(
                width: 56,
                height: 56,
                color: df.surfaceMuted,
                child: Icon(Icons.broken_image_outlined,
                    size: 20, color: df.textTertiary))),
      ),
    );
  }

  /// 出图状态角标：和「状态」栏的排序口径一致（未生成 → 失败 → 生成中 → 已完成）。
  Widget _imageStatusCell(AssetRow row) {
    final l10n = context.l10n;
    return switch (row.imageState) {
      stateGenerating =>
        DFStatusTag(kind: DFStatusKind.processing, text: l10n.statusRunning),
      stateFailed => Tooltip(
          message: localizeReason(l10n, row.imageErrorReason) ?? '',
          child:
              DFStatusTag(kind: DFStatusKind.failed, text: l10n.statusFailed),
        ),
      stateDone =>
        DFStatusTag(kind: DFStatusKind.success, text: l10n.statusDone),
      _ => DFStatusTag(
          kind: DFStatusKind.pending, text: l10n.statusNotGenerated),
    };
  }

  Widget _promptCell(AssetRow row) {
    final l10n = context.l10n;
    final df = context.df;
    if (row.promptState == stateGenerating) {
      return DFStatusTag(
          kind: DFStatusKind.processing, text: l10n.assetsGenerating);
    }
    if (row.promptState == stateFailed) {
      return Tooltip(
        message: localizeReason(l10n, row.promptErrorReason) ?? '',
        child:
            DFStatusTag(kind: DFStatusKind.failed, text: l10n.assetsGenerating),
      );
    }
    return Text(row.prompt ?? '',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: df.textSecondary));
  }

  Widget _operations(AssetRow row) {
    final l10n = context.l10n;
    final df = context.df;
    final generating =
        row.imageState == stateGenerating || row.promptState == stateGenerating;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (row.type != 'clip' && row.type != 'audio')
        TextButton(
          onPressed: generating
              ? null
              : () async {
                  final saved = await showGenerateImageDialog(context, ref,
                      projectId: widget.projectId, asset: row);
                  if (saved == true) setState(() {});
                },
          child:
              Text(l10n.assetsGenerate, style: const TextStyle(fontSize: 13)),
        ),
      TextButton(
        onPressed: () => _openAdd(existing: row),
        child: Text(l10n.assetsEdit, style: const TextStyle(fontSize: 13)),
      ),
      TextButton(
        onPressed: generating ? null : () => _deleteOne(row),
        child: Text(l10n.assetsDelete,
            style: TextStyle(fontSize: 13, color: df.danger)),
      ),
    ]);
  }

  List<DFDataRow> _rowsFor(List<AssetRow> assets, {required bool isAudio}) {
    final df = context.df;
    final rows = <DFDataRow>[];
    for (final row in assets) {
      rows.add(DFDataRow(
        id: '${row.id}',
        onTap: row.sonAssets.isEmpty
            ? null
            : () => setState(() {
                  if (!_expanded.remove(row.id)) {
                    _expanded.add(row.id);
                    while (_expanded.length > 3) {
                      _expanded.remove(_expanded.first);
                    }
                  }
                }),
        cells: [
          _preview(row),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (row.sonAssets.isNotEmpty)
              Icon(
                  _expanded.contains(row.id)
                      ? Icons.expand_more
                      : Icons.chevron_right,
                  size: 16,
                  color: df.textTertiary),
            Flexible(
              child: Text(row.name ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
          if (isAudio)
            Text(row.sex, style: const TextStyle(fontSize: 12))
          else
            _promptCell(row),
          Text(isAudio ? row.audioDescribe : (row.describe ?? ''),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)),
          if (!isAudio)
            Text(row.remark ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          if (!isAudio) _imageStatusCell(row),
          Text(
            row.startTime == null
                ? ''
                : DateFormat('yyyy-MM-dd HH:mm:ss').format(
                    DateTime.fromMillisecondsSinceEpoch(row.startTime!)),
            style: const TextStyle(fontSize: 11),
          ),
          _operations(row),
        ],
      ));
      if (_expanded.contains(row.id)) {
        for (final son in row.sonAssets) {
          rows.add(DFDataRow(
            id: '${son.id}',
            cells: [
              Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: _preview(son)),
              Text('└ ${son.name ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: df.textSecondary)),
              if (isAudio)
                Text(son.prompt ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12))
              else
                _promptCell(son),
              Text(son.describe ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
              if (!isAudio)
                Text(son.remark ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
              // 子行同样要补上「状态」这一格，否则列与表头会整体错位。
              if (!isAudio) _imageStatusCell(son),
              const SizedBox.shrink(),
              _operations(son),
            ],
          ));
        }
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    ref.watch(jobsGenerationProvider);
    final result = ref.watch(engineProvider).getAssets(widget.projectId,
        type: _type,
        page: _page,
        limit: _limit,
        search: _search.isEmpty ? null : _search,
        sort: _sort.key,
        descending: _sort.descending);
    final isAudio = _type == 'audio';
    final canGenerate = _type == 'role' || _type == 'tool' || _type == 'scene';

    return Column(children: [
      Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 12),
        child: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in assetTabs) Tab(text: _tabLabel(t))],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;

          Future<void> openTts() async {
            final saved = await showAddTtsAudioDialog(context, ref,
                projectId: widget.projectId);
            if (saved == true) setState(() {});
          }

          Future<void> openBatch(int mode) async {
            final done = await showBatchGenerationDialog(context, ref,
                projectId: widget.projectId, type: _type, mode: mode);
            if (done == true) setState(() {});
          }

          final search = DFSearchField(
            hint: l10n.assetsSearchPlaceholder,
            width: compact ? constraints.maxWidth : 240,
            onSearch: (q) => setState(() {
              _search = q;
              _page = 1;
            }),
          );
          final actions = <Widget>[
            FilledButton.icon(
              onPressed: () => _openAdd(),
              icon: const Icon(Icons.add, size: 18),
              label: Text('${l10n.assetsAddPrefix}${_tabLabel(_type)}'),
            ),
            if (_type == 'audio')
              OutlinedButton.icon(
                onPressed: openTts,
                icon: const Icon(Icons.record_voice_over_outlined, size: 18),
                label: Text(l10n.assetsGenerateSpeech),
              ),
            if (canGenerate) ...[
              OutlinedButton.icon(
                onPressed: () => openBatch(1),
                icon: const Icon(Icons.translate_outlined, size: 18),
                label: Text(l10n.assetsGeneratePrompt),
              ),
              OutlinedButton.icon(
                onPressed: () => openBatch(2),
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(l10n.assetsGenerateImage),
              ),
            ],
            FilledButton.icon(
              onPressed: _selected.isEmpty ? null : _batchDelete,
              style: FilledButton.styleFrom(
                  backgroundColor: df.danger,
                  disabledBackgroundColor: df.danger.withValues(alpha: 0.35)),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(_selected.isEmpty
                  ? l10n.assetsBatchDelete
                  : '${l10n.assetsBatchDelete} (${_selected.length})'),
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
            ...actions.expand((button) => [button, const SizedBox(width: 8)]),
            const Spacer(),
            search,
          ]);
        }),
      ),
      Expanded(
        child: result.total == 0 && _search.isEmpty
            ? Center(
                child: DFEmpty(
                  text: l10n.projectEmpty,
                  action: FilledButton.icon(
                    onPressed: () => _openAdd(),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text('${l10n.assetsAddPrefix}${_tabLabel(_type)}'),
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: LayoutBuilder(builder: (context, tableConstraints) {
                  final table = DFDataTable(
                    columns: [
                      // 预览栏按「当前选中图的生成先后」排：点它＝最近出的图排前面。
                      DFDataColumn(
                          label: l10n.assetsColPreview,
                          sortKey: isAudio ? null : 'generated'),
                      DFDataColumn(
                          label: isAudio
                              ? l10n.assetsAudioName
                              : l10n.assetsColName,
                          sortKey: 'name'),
                      DFDataColumn(
                          label:
                              isAudio ? l10n.assetsSex : l10n.assetsColPrompt,
                          sortKey: isAudio ? null : 'prompt'),
                      DFDataColumn(label: l10n.assetsColDescribe),
                      if (!isAudio) DFDataColumn(label: l10n.assetsColRemark),
                      if (!isAudio)
                        DFDataColumn(
                            label: l10n.assetsColStatus, sortKey: 'status'),
                      DFDataColumn(
                          label: l10n.assetsColCreateTime, sortKey: 'created'),
                      DFDataColumn(label: l10n.assetsColOperation),
                    ],
                    sort: _sort,
                    onSortChanged: (next) => setState(() {
                      _sort = next;
                      _page = 1; // 换了排序还停在第 5 页会看得一头雾水
                    }),
                    selectable: true,
                    selectedIds: _selected,
                    onSelectionChanged: (ids) => setState(() => _selected
                      ..clear()
                      ..addAll(ids)),
                    pagination: DFPagination(
                        page: _page, pageSize: _limit, total: result.total),
                    onPageChange: (p) => setState(() => _page = p),
                    rows: _rowsFor(result.data, isAudio: isAudio),
                    mobileCardBuilder: (c, dfRow) {
                      AssetRow? found;
                      for (final parent in result.data) {
                        if ('${parent.id}' == dfRow.id) found = parent;
                        for (final son in parent.sonAssets) {
                          if ('${son.id}' == dfRow.id) found = son;
                        }
                      }
                      final row = found!;
                      final hasChildren = row.sonAssets.isNotEmpty;
                      final expanded = _expanded.contains(row.id);
                      return ListTile(
                        leading: _preview(row),
                        title: Row(children: [
                          if (hasChildren)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                  width: 32, height: 32),
                              icon: Icon(
                                expanded
                                    ? Icons.expand_more
                                    : Icons.chevron_right,
                                size: 20,
                              ),
                              onPressed: () => setState(() {
                                if (!_expanded.remove(row.id)) {
                                  _expanded.add(row.id);
                                  while (_expanded.length > 3) {
                                    _expanded.remove(_expanded.first);
                                  }
                                }
                              }),
                            ),
                          Expanded(
                            child: Text(row.name ?? '',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                        subtitle: _promptCell(row),
                        trailing: IconButton(
                          icon: const Icon(Icons.more_horiz),
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            builder: (c) => SafeArea(
                              child: Wrap(children: [
                                if (row.type != 'clip' && row.type != 'audio')
                                  ListTile(
                                    leading: const Icon(Icons.image_outlined),
                                    title: Text(l10n.assetsGenerate),
                                    onTap: () async {
                                      Navigator.pop(c);
                                      final saved =
                                          await showGenerateImageDialog(
                                              context, ref,
                                              projectId: widget.projectId,
                                              asset: row);
                                      if (saved == true) setState(() {});
                                    },
                                  ),
                                ListTile(
                                  leading: const Icon(Icons.edit_outlined),
                                  title: Text(l10n.assetsEdit),
                                  onTap: () {
                                    Navigator.pop(c);
                                    _openAdd(existing: row);
                                  },
                                ),
                                ListTile(
                                  leading: Icon(Icons.delete_outline,
                                      color: df.danger),
                                  title: Text(l10n.assetsDelete,
                                      style: TextStyle(color: df.danger)),
                                  onTap: () {
                                    Navigator.pop(c);
                                    _deleteOne(row);
                                  },
                                ),
                              ]),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                  // Below DFDataTable's mobile breakpoint, `_MobileRows`
                  // renders a shrink-wrapped ListView with
                  // NeverScrollableScrollPhysics, which assumes a genuinely
                  // scrollable ancestor with unbounded height sits above it.
                  // The `Expanded` below only gives bounded height, so
                  // without this a full page of mobile cards silently
                  // clips/overflows instead of scrolling into view. Give it
                  // that scrollable ancestor on the mobile layout only; the
                  // desktop table already manages its own bounded layout.
                  if (tableConstraints.maxWidth < DFDataTable.breakpoint) {
                    return SingleChildScrollView(child: table);
                  }
                  return table;
                }),
              ),
      ),
    ]);
  }
}
