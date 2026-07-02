import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';

const _wideBreakpoint = 900.0;
const _timelineCardWidth = 150.0;
const _timelineCardHeight = 88.0;
const _timelineInsertWidth = 34.0;
const _timelineThumbSize = 58.0;

/// 分镜时间线看板：宽屏横向排镜，窄屏纵向长按调序。
class ShotsScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String episodeId;

  const ShotsScreen({
    super.key,
    required this.projectId,
    required this.episodeId,
  });

  @override
  ConsumerState<ShotsScreen> createState() => _ShotsScreenState();
}

class _ShotsScreenState extends ConsumerState<ShotsScreen> {
  final Set<String> _hiddenShotIds = {};
  final Map<String, Shot> _localInsertedShots = {};
  List<String> _orderedIds = const [];
  String? _selectedShotId;
  bool _reordering = false;

  Future<void> _generateAllImages(BuildContext context, WidgetRef ref) async {
    int? queued;
    await runAction(context, ref, () async {
      final ids = await ref
          .read(engineProvider)
          .generateAllShotImages(widget.episodeId);
      queued = ids.length;
    });
    if (queued != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            queued == 0 ? '没有需要生成的镜头图（已完成或进行中的会被跳过）' : '已排队 $queued 个镜头图生成任务'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  List<Shot> _displayShots(List<Shot> source) {
    final sourceIds = source.map((s) => s.id).toSet();
    _hiddenShotIds.removeWhere((id) => !sourceIds.contains(id));
    _localInsertedShots.removeWhere((id, _) => sourceIds.contains(id));

    final byId = <String, Shot>{
      for (final shot in source)
        if (!_hiddenShotIds.contains(shot.id)) shot.id: shot,
      ..._localInsertedShots,
    };

    final ids = byId.keys.toSet();
    if (_orderedIds.length != ids.length || !_orderedIds.every(ids.contains)) {
      _orderedIds = [
        for (final shot in source)
          if (!_hiddenShotIds.contains(shot.id)) shot.id,
        for (final id in _localInsertedShots.keys)
          if (!sourceIds.contains(id)) id,
      ];
    }

    if (_selectedShotId == null && _orderedIds.isNotEmpty) {
      _selectedShotId = _orderedIds.first;
    }

    return [
      for (final id in _orderedIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Shot? _selectedShot(List<Shot> shots) {
    if (shots.isEmpty) return null;
    final selectedId = _selectedShotId;
    if (selectedId != null) {
      for (final shot in shots) {
        if (shot.id == selectedId) return shot;
      }
    }
    if (selectedId == null) _selectedShotId = shots.first.id;
    return shots.first;
  }

  Future<void> _reorderShots(
    BuildContext context,
    WidgetRef ref,
    List<Shot> shots,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex || oldIndex < 0 || oldIndex >= shots.length) {
      return;
    }

    final previous = List<String>.from(_orderedIds);
    final updated = List<String>.from(_orderedIds);
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);

    setState(() {
      _reordering = true;
      _orderedIds = updated;
      _selectedShotId = moved;
    });

    var ok = false;
    try {
      await runAction(context, ref, () async {
        await ref.read(engineProvider).reorderShots(widget.episodeId, updated);
        ok = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _reordering = false;
          if (!ok) _orderedIds = previous;
        });
        ref.invalidate(shotsProvider(widget.episodeId));
      }
    }
  }

  Future<void> _insertAfter(
    BuildContext context,
    WidgetRef ref,
    Shot anchor,
    int visualIndex,
  ) async {
    Shot? inserted;
    await runAction(context, ref, () async {
      inserted = await ref
          .read(engineProvider)
          .insertShot(widget.episodeId, afterIdx: visualIndex + 1);
    }, successMessage: '已插入空镜头');
    final newShot = inserted;
    if (newShot == null || !mounted) return;

    setState(() {
      final updated = List<String>.from(_orderedIds);
      final anchorIndex = updated.indexOf(anchor.id);
      final insertIndex = anchorIndex == -1 ? updated.length : anchorIndex + 1;
      updated.insert(insertIndex, newShot.id);
      _orderedIds = updated;
      _localInsertedShots[newShot.id] = newShot;
      _selectedShotId = newShot.id;
    });
    ref.invalidate(shotsProvider(widget.episodeId));

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _ShotEditDialog(
        shot: newShot,
        episodeId: widget.episodeId,
      ),
    );
  }

  Future<bool> _deleteShot(
    BuildContext context,
    WidgetRef ref,
    Shot shot,
    List<Shot> shots,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除镜头 ${shot.idx}？'),
        content: const Text('删除后会重新编号后续镜头。已生成的镜头图和视频记录也会从时间线移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.df.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;

    final index = shots.indexWhere((s) => s.id == shot.id);
    final nextSelected = switch (index) {
      -1 => null,
      _ when shots.length <= 1 => null,
      _ when index < shots.length - 1 => shots[index + 1].id,
      _ => shots[index - 1].id,
    };

    var deleted = false;
    await runAction(context, ref, () async {
      await ref.read(engineProvider).deleteShot(shot.id);
      deleted = true;
    }, successMessage: '镜头已删除');
    if (!deleted || !mounted) return false;

    setState(() {
      _hiddenShotIds.add(shot.id);
      _localInsertedShots.remove(shot.id);
      _orderedIds = [
        for (final id in _orderedIds)
          if (id != shot.id) id,
      ];
      _selectedShotId = nextSelected;
    });
    ref.invalidate(shotsProvider(widget.episodeId));
    return true;
  }

  void _selectShot(String id) {
    if (_selectedShotId == id) return;
    setState(() => _selectedShotId = id);
  }

  void _showShotSheet(BuildContext context, Shot shot, List<Shot> shots) {
    _selectShot(shot.id);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.df.surface,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.45,
        maxChildSize: 0.96,
        builder: (context, controller) => Consumer(
          builder: (context, ref, _) {
            final latest = _findShot(
                    ref.watch(shotsProvider(widget.episodeId)).value,
                    shot.id) ??
                shot;
            return _ShotDetailPanel(
              shot: latest,
              episodeId: widget.episodeId,
              controller: controller,
              onDelete: (shot) async {
                final deleted = await _deleteShot(context, ref, shot, shots);
                if (deleted && context.mounted) {
                  Navigator.of(context).maybePop();
                }
                return deleted;
              },
              onChanged: () => ref.invalidate(shotsProvider(widget.episodeId)),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shotsAsync = ref.watch(shotsProvider(widget.episodeId));
    final episode = ref.watch(episodeProvider(widget.episodeId)).value;
    final compactActions = MediaQuery.sizeOf(context).width < 620;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回剧集',
          onPressed: () => context
              .go('/projects/${widget.projectId}/episodes/${widget.episodeId}'),
        ),
        title: Text(episode == null ? '分镜' : '分镜 · 第${episode.idx}集'),
        actions: [
          if (compactActions)
            IconButton.filled(
              tooltip: '批量生成镜头图',
              onPressed: () => _generateAllImages(context, ref),
              icon: const Icon(Icons.burst_mode_rounded, size: 20),
            )
          else
            FilledButton.icon(
              onPressed: () => _generateAllImages(context, ref),
              icon: const Icon(Icons.burst_mode_rounded, size: 18),
              label: const Text('批量生成镜头图'),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: PageContainer(
        child: AsyncView(
          value: shotsAsync,
          onRetry: () => ref.invalidate(shotsProvider(widget.episodeId)),
          builder: (sourceShots) {
            final shots = _displayShots(sourceShots);
            if (shots.isEmpty) {
              return EmptyHint(
                icon: Icons.view_carousel_outlined,
                title: '还没有分镜',
                subtitle: '回到剧集页点击「生成分镜」',
                action: FilledButton.icon(
                  onPressed: () => runAction(context, ref, () async {
                    await ref
                        .read(engineProvider)
                        .generateStoryboard(widget.episodeId);
                  }, successMessage: '分镜生成任务已排队'),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('生成分镜'),
                ),
              );
            }

            return LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= _wideBreakpoint;
              if (wide) {
                final selected = _selectedShot(shots);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 18),
                    _WideTimeline(
                      shots: shots,
                      selectedId: _selectedShotId,
                      reordering: _reordering,
                      onSelect: _selectShot,
                      onInsertAfter: (shot, index) =>
                          _insertAfter(context, ref, shot, index),
                      onReorder: (oldIndex, newIndex) => _reorderShots(
                          context, ref, shots, oldIndex, newIndex),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: selected == null
                          ? const SizedBox.shrink()
                          : _ShotDetailPanel(
                              shot: selected,
                              episodeId: widget.episodeId,
                              onDelete: (shot) =>
                                  _deleteShot(context, ref, shot, shots),
                              onChanged: () => ref
                                  .invalidate(shotsProvider(widget.episodeId)),
                            ),
                    ),
                    const SizedBox(height: 20),
                  ],
                );
              }

              return _NarrowShotList(
                shots: shots,
                selectedId: _selectedShotId,
                onOpen: (shot) => _showShotSheet(context, shot, shots),
                onInsertAfter: (shot, index) =>
                    _insertAfter(context, ref, shot, index),
                onReorder: (oldIndex, newIndex) =>
                    _reorderShots(context, ref, shots, oldIndex, newIndex),
              );
            });
          },
        ),
      ),
    );
  }
}

Shot? _findShot(List<Shot>? shots, String id) {
  if (shots == null) return null;
  for (final shot in shots) {
    if (shot.id == id) return shot;
  }
  return null;
}

String _formatDuration(double? seconds) {
  if (seconds == null || seconds <= 0) return '时长 --';
  final total = seconds.round();
  final minutes = total ~/ 60;
  final secs = total % 60;
  if (minutes == 0) return '时长 ${secs}s';
  return '时长 $minutes:${secs.toString().padLeft(2, '0')}';
}

class _WideTimeline extends StatelessWidget {
  final List<Shot> shots;
  final String? selectedId;
  final bool reordering;
  final ValueChanged<String> onSelect;
  final void Function(Shot shot, int index) onInsertAfter;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _WideTimeline({
    required this.shots,
    required this.selectedId,
    required this.reordering,
    required this.onSelect,
    required this.onInsertAfter,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: context.df.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.df.stroke),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                Icon(Icons.view_timeline_outlined,
                    size: 17, color: context.df.primary),
                const SizedBox(width: 8),
                Text('时间线',
                    style: TextStyle(
                        color: context.df.textHi,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('拖拽调序',
                    style: TextStyle(fontSize: 12, color: context.df.textLo)),
                const Spacer(),
                if (reordering)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.df.primary,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              buildDefaultDragHandles: false,
              itemCount: shots.length,
              onReorderItem: onReorder,
              itemBuilder: (context, index) {
                final shot = shots[index];
                return SizedBox(
                  key: ValueKey('timeline-${shot.id}'),
                  width: _timelineCardWidth + _timelineInsertWidth,
                  child: Row(
                    children: [
                      _TimelineShotCard(
                        shot: shot,
                        index: index,
                        selected: shot.id == selectedId,
                        onTap: () => onSelect(shot.id),
                      ),
                      _InsertSlotButton(
                        axis: Axis.horizontal,
                        tooltip: '在镜头 ${index + 1} 后插入',
                        onPressed: () => onInsertAfter(shot, index),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineShotCard extends StatelessWidget {
  final Shot shot;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  const _TimelineShotCard({
    required this.shot,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? context.df.primary : context.df.stroke;
    final imageDone = shot.imageStatus == 'done';

    return SizedBox(
      width: _timelineCardWidth,
      height: _timelineCardHeight,
      child: Material(
        color: selected
            ? context.df.primary.withValues(alpha: 0.08)
            : context.df.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: selected ? 2 : 1),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: _timelineThumbSize,
                  height: _timelineThumbSize,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: MediaImage(
                          shot.imageUrl,
                          width: _timelineThumbSize,
                          height: _timelineThumbSize,
                          radius: 8,
                        ),
                      ),
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color:
                                imageDone ? context.df.green : context.df.grey,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: context.df.card, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '#${index + 1}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: selected
                                    ? context.df.primary
                                    : context.df.textHi,
                              ),
                            ),
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: Icon(Icons.drag_indicator_rounded,
                                size: 17, color: context.df.textLo),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        '时长 --',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 11, color: context.df.textLo),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NarrowShotList extends StatelessWidget {
  final List<Shot> shots;
  final String? selectedId;
  final ValueChanged<Shot> onOpen;
  final void Function(Shot shot, int index) onInsertAfter;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _NarrowShotList({
    required this.shots,
    required this.selectedId,
    required this.onOpen,
    required this.onInsertAfter,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      buildDefaultDragHandles: false,
      itemCount: shots.length,
      onReorderItem: onReorder,
      itemBuilder: (context, index) {
        final shot = shots[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey('shot-list-${shot.id}'),
          index: index,
          child: Column(
            children: [
              _ShotListCard(
                shot: shot,
                index: index,
                selected: shot.id == selectedId,
                onTap: () => onOpen(shot),
              ),
              _InsertSlotButton(
                axis: Axis.vertical,
                tooltip: '在镜头 ${index + 1} 后插入',
                onPressed: () => onInsertAfter(shot, index),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShotListCard extends StatelessWidget {
  final Shot shot;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  const _ShotListCard({
    required this.shot,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final error = shot.imageStatus == 'failed'
        ? shot.imageError
        : shot.videoStatus == 'failed'
            ? shot.videoError
            : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? context.df.primary : context.df.stroke,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MediaImage(
                shot.imageUrl,
                width: 92,
                height: 92,
                radius: 10,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _IdxBadge(label: '镜头 ${index + 1}'),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '时长 --',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: context.df.textLo),
                          ),
                        ),
                        Icon(Icons.drag_indicator_rounded,
                            size: 20, color: context.df.textLo),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      shot.description.isEmpty ? '未填写画面描述' : shot.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusChip(shot.imageStatus,
                            dense: true, errorTooltip: shot.imageError),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('视频',
                                style: TextStyle(
                                    fontSize: 11, color: context.df.textLo)),
                            const SizedBox(width: 4),
                            StatusChip(shot.videoStatus,
                                dense: true, errorTooltip: shot.videoError),
                          ],
                        ),
                      ],
                    ),
                    if (error != null && error.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _FailureText(text: error),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsertSlotButton extends StatelessWidget {
  final Axis axis;
  final String tooltip;
  final VoidCallback onPressed;

  const _InsertSlotButton({
    required this.axis,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == Axis.horizontal;
    final line = Container(
      width: horizontal ? 1 : double.infinity,
      height: horizontal ? double.infinity : 1,
      color: context.df.stroke,
    );
    final button = Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: context.df.primaryDim.withValues(alpha: 0.45),
          foregroundColor: context.df.primary,
          minimumSize: const Size(26, 26),
          fixedSize: const Size(26, 26),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.add_rounded, size: 18),
      ),
    );

    if (horizontal) {
      return SizedBox(
        width: _timelineInsertWidth,
        height: _timelineCardHeight,
        child: Stack(
          alignment: Alignment.center,
          children: [line, button],
        ),
      );
    }

    return SizedBox(
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: line,
          ),
          button,
        ],
      ),
    );
  }
}

class _ShotDetailPanel extends ConsumerWidget {
  final Shot shot;
  final String episodeId;
  final ScrollController? controller;
  final Future<bool> Function(Shot shot) onDelete;
  final VoidCallback onChanged;

  const _ShotDetailPanel({
    required this.shot,
    required this.episodeId,
    required this.onDelete,
    required this.onChanged,
    this.controller,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(builder: (context, constraints) {
      final rowLayout = constraints.maxWidth >= 760;
      final content = SingleChildScrollView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(18, rowLayout ? 18 : 16, 18, 22),
        child: rowLayout
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ShotMediaColumn(
                    shot: shot,
                    episodeId: episodeId,
                    onChanged: onChanged,
                    size: 360,
                  ),
                  const SizedBox(width: 20),
                  Expanded(child: _DetailInfo(shot: shot)),
                  const SizedBox(width: 18),
                  SizedBox(
                    width: 220,
                    child: _ShotActions(
                      shot: shot,
                      episodeId: episodeId,
                      onDelete: onDelete,
                      onChanged: onChanged,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ShotMediaColumn(
                    shot: shot,
                    episodeId: episodeId,
                    onChanged: onChanged,
                  ),
                  const SizedBox(height: 16),
                  _DetailInfo(shot: shot),
                  const SizedBox(height: 14),
                  _ShotActions(
                    shot: shot,
                    episodeId: episodeId,
                    onDelete: onDelete,
                    onChanged: onChanged,
                  ),
                ],
              ),
      );

      if (controller != null) return content;
      return Card(child: content);
    });
  }
}

class _ShotMediaColumn extends StatelessWidget {
  final Shot shot;
  final String episodeId;
  final VoidCallback onChanged;
  final double? size;

  const _ShotMediaColumn({
    required this.shot,
    required this.episodeId,
    required this.onChanged,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    final image = size == null
        ? const SizedBox.shrink()
        : _HeroImage(shot: shot, size: size);
    if (size != null) {
      return SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            image,
            const SizedBox(height: 12),
            _VideoTakesStrip(
              shot: shot,
              episodeId: episodeId,
              onChanged: onChanged,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroImage(shot: shot),
        const SizedBox(height: 12),
        _VideoTakesStrip(
          shot: shot,
          episodeId: episodeId,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _HeroImage extends StatelessWidget {
  final Shot shot;
  final double? size;

  const _HeroImage({required this.shot, this.size});

  @override
  Widget build(BuildContext context) {
    if (size != null) {
      return MediaImage(
        shot.imageUrl,
        width: size,
        height: size,
        radius: 12,
      );
    }

    return AspectRatio(
      aspectRatio: 1,
      child: MediaImage(shot.imageUrl, radius: 12),
    );
  }
}

class _VideoTakesStrip extends ConsumerWidget {
  final Shot shot;
  final String episodeId;
  final VoidCallback onChanged;

  const _VideoTakesStrip({
    required this.shot,
    required this.episodeId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final takesAsync = ref.watch(takesProvider(shot.id));
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.df.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.df.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.video_library_outlined,
                  size: 15, color: context.df.textLo),
              const SizedBox(width: 6),
              Text(
                '视频版本',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.df.textMid,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          takesAsync.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            data: (takes) {
              if (takes.isEmpty) {
                return SizedBox(
                  height: 58,
                  child: Center(
                    child: Text(
                      '暂无视频版本',
                      style: TextStyle(fontSize: 12, color: context.df.textLo),
                    ),
                  ),
                );
              }
              return SizedBox(
                height: 66,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: takes.length,
                  separatorBuilder: (context, separatorIndex) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final take = takes[index];
                    final selected = take.id == shot.selectedTakeId;
                    return _VideoTakeTile(
                      label: '版本 ${takes.length - index}',
                      duration: _formatDuration(take.durationSec),
                      selected: selected,
                      onTap: selected
                          ? null
                          : () => runAction(context, ref, () async {
                                await ref
                                    .read(engineProvider)
                                    .selectTake(shot.id, take.id);
                                ref.invalidate(takesProvider(shot.id));
                                ref.invalidate(shotsProvider(episodeId));
                                onChanged();
                              }, successMessage: '已切换视频版本'),
                    );
                  },
                ),
              );
            },
            loading: () => SizedBox(
              height: 58,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.df.primary,
                  ),
                ),
              ),
            ),
            error: (e, _) => SizedBox(
              height: 58,
              child: Center(
                child: Text(
                  e.toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.df.red),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoTakeTile extends StatelessWidget {
  final String label;
  final String duration;
  final bool selected;
  final VoidCallback? onTap;

  const _VideoTakeTile({
    required this.label,
    required this.duration,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.df.primary : context.df.textMid;
    return SizedBox(
      width: 104,
      child: Material(
        color: selected
            ? context.df.primary.withValues(alpha: 0.1)
            : context.df.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? context.df.primary : context.df.stroke,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.play_circle_outline_rounded,
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  duration,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: context.df.textLo),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailInfo extends StatelessWidget {
  final Shot shot;

  const _DetailInfo({required this.shot});

  @override
  Widget build(BuildContext context) {
    final imageFailed = shot.imageStatus == 'failed' &&
        shot.imageError != null &&
        shot.imageError!.isNotEmpty;
    final videoFailed = shot.videoStatus == 'failed' &&
        shot.videoError != null &&
        shot.videoError!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _IdxBadge(label: '镜头 ${shot.idx}'),
            if (shot.camera.isNotEmpty) _CameraChip(camera: shot.camera),
            StatusChip(shot.imageStatus,
                dense: true, errorTooltip: shot.imageError),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('视频',
                    style: TextStyle(fontSize: 11, color: context.df.textLo)),
                const SizedBox(width: 4),
                StatusChip(shot.videoStatus,
                    dense: true, errorTooltip: shot.videoError),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        _TextSection(
          title: '画面描述',
          icon: Icons.notes_rounded,
          text: shot.description,
          emptyText: '未填写画面描述',
        ),
        const SizedBox(height: 12),
        _TextSection(
          title: '台词',
          icon: Icons.format_quote_rounded,
          text: shot.dialogue,
          emptyText: '无台词',
        ),
        const SizedBox(height: 12),
        _TextSection(
          title: '镜头语言',
          icon: Icons.videocam_outlined,
          text: shot.camera,
          emptyText: '未填写镜头语言',
        ),
        const SizedBox(height: 12),
        _TextSection(
          title: '图片提示词',
          icon: Icons.image_outlined,
          text: shot.imagePrompt,
          emptyText: '未填写图片提示词',
        ),
        const SizedBox(height: 12),
        _TextSection(
          title: '视频提示词',
          icon: Icons.movie_creation_outlined,
          text: shot.videoPrompt,
          emptyText: '未填写视频提示词',
        ),
        if (shot.assetNames.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in shot.assetNames)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.df.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: context.df.stroke),
                  ),
                  child: Text(name,
                      style:
                          TextStyle(fontSize: 11, color: context.df.textMid)),
                ),
            ],
          ),
        ],
        if (imageFailed) ...[
          const SizedBox(height: 10),
          _FailureText(text: '图片：${shot.imageError!}'),
        ],
        if (videoFailed) ...[
          const SizedBox(height: 8),
          _FailureText(text: '视频：${shot.videoError!}'),
        ],
      ],
    );
  }
}

class _ShotActions extends ConsumerWidget {
  final Shot shot;
  final String episodeId;
  final Future<bool> Function(Shot shot) onDelete;
  final VoidCallback onChanged;

  const _ShotActions({
    required this.shot,
    required this.episodeId,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageBusy =
        shot.imageStatus == 'queued' || shot.imageStatus == 'running';
    final videoBusy =
        shot.videoStatus == 'queued' || shot.videoStatus == 'running';
    final imageDone = shot.imageStatus == 'done';
    final imageFailed = shot.imageStatus == 'failed';
    final videoDone = shot.videoStatus == 'done';
    final videoFailed = shot.videoStatus == 'failed';

    final videoEnabled = imageDone && !videoBusy;
    final videoTooltip =
        !imageDone ? '需要先生成镜头图，完成后才能生成视频' : (videoBusy ? '视频任务进行中' : null);

    Widget videoButton = OutlinedButton.icon(
      onPressed: videoEnabled
          ? () => runAction(context, ref, () async {
                await ref.read(engineProvider).generateShotVideo(shot.id);
              }, successMessage: '视频版本生成任务已排队')
          : null,
      icon: const Icon(Icons.movie_creation_outlined, size: 16),
      label: Text(videoDone || videoFailed ? '新增视频版本' : '生成视频版本'),
      style: _compactOutlined,
    );
    if (videoTooltip != null) {
      videoButton = Tooltip(message: videoTooltip, child: videoButton);
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: imageBusy
              ? null
              : () => runAction(context, ref, () async {
                    await ref.read(engineProvider).generateShotImage(shot.id);
                  }, successMessage: '镜头图生成任务已排队'),
          icon: Icon(
              imageDone || imageFailed
                  ? Icons.refresh_rounded
                  : Icons.image_outlined,
              size: 16),
          label: Text(imageDone ? '重新生成' : (imageFailed ? '重试' : '生成镜头图')),
          style: _compactOutlined,
        ),
        videoButton,
        TextButton.icon(
          onPressed: () async {
            await showDialog<void>(
              context: context,
              builder: (_) => _ShotEditDialog(shot: shot, episodeId: episodeId),
            );
            onChanged();
          },
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('编辑'),
          style: _compactText,
        ),
        if (shot.videoUrl != null && shot.videoUrl!.isNotEmpty)
          TextButton.icon(
            onPressed: () async {
              final abs = ref.read(engineProvider).mediaAbsPath(shot.videoUrl!);
              await Clipboard.setData(ClipboardData(text: abs));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('视频文件路径已复制'),
                  duration: Duration(seconds: 2),
                ));
              }
            },
            icon: const Icon(Icons.link_rounded, size: 16),
            label: const Text('复制视频路径'),
            style: _compactText,
          ),
        TextButton.icon(
          onPressed: () {
            onDelete(shot);
          },
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: const Text('删除'),
          style: _compactText.copyWith(
            foregroundColor: WidgetStatePropertyAll(context.df.red),
          ),
        ),
      ],
    );
  }

  ButtonStyle get _compactOutlined => OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      );

  ButtonStyle get _compactText => TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      );
}

class _TextSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final String text;
  final String emptyText;

  const _TextSection({
    required this.title,
    required this.icon,
    required this.text,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final body = text.trim().isEmpty ? emptyText : text.trim();
    final empty = text.trim().isEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.df.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.df.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: context.df.textLo),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.df.textMid)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  color: empty ? context.df.textLo : context.df.textHi,
                ),
          ),
        ],
      ),
    );
  }
}

class _IdxBadge extends StatelessWidget {
  final String label;

  const _IdxBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: context.df.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: context.df.primary.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.df.primary)),
    );
  }
}

class _CameraChip extends StatelessWidget {
  final String camera;

  const _CameraChip({required this.camera});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.df.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.df.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_outlined, size: 13, color: context.df.textLo),
          const SizedBox(width: 4),
          Text(camera,
              style: TextStyle(fontSize: 11.5, color: context.df.textMid)),
        ],
      ),
    );
  }
}

class _FailureText extends StatelessWidget {
  final String text;

  const _FailureText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: text,
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: context.df.red, height: 1.4),
      ),
    );
  }
}

/// 编辑弹窗：描述 / 运镜 / 台词 / 图片提示词 / 视频提示词，只提交改动的字段。
class _ShotEditDialog extends ConsumerStatefulWidget {
  final Shot shot;
  final String episodeId;

  const _ShotEditDialog({required this.shot, required this.episodeId});

  @override
  ConsumerState<_ShotEditDialog> createState() => _ShotEditDialogState();
}

class _ShotEditDialogState extends ConsumerState<_ShotEditDialog> {
  late final _desc = TextEditingController(text: widget.shot.description);
  late final _camera = TextEditingController(text: widget.shot.camera);
  late final _dialogue = TextEditingController(text: widget.shot.dialogue);
  late final _imagePrompt =
      TextEditingController(text: widget.shot.imagePrompt);
  late final _videoPrompt =
      TextEditingController(text: widget.shot.videoPrompt);
  bool _saving = false;

  @override
  void dispose() {
    _desc.dispose();
    _camera.dispose();
    _dialogue.dispose();
    _imagePrompt.dispose();
    _videoPrompt.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final patch = <String, String>{};
    void addIfChanged(String key, String original, TextEditingController c) {
      final v = c.text.trim();
      if (v != original) patch[key] = v;
    }

    addIfChanged('description', widget.shot.description, _desc);
    addIfChanged('camera', widget.shot.camera, _camera);
    addIfChanged('dialogue', widget.shot.dialogue, _dialogue);
    addIfChanged('imagePrompt', widget.shot.imagePrompt, _imagePrompt);
    addIfChanged('videoPrompt', widget.shot.videoPrompt, _videoPrompt);

    if (patch.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _saving = true);
    var ok = false;
    await runAction(context, ref, () async {
      await ref.read(engineProvider).updateShot(widget.shot.id, patch);
      ok = true;
    }, successMessage: '分镜已保存');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ref.invalidate(shotsProvider(widget.episodeId));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('编辑镜头 ${widget.shot.idx}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _desc,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: '画面描述', alignLabelWithHint: true),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _camera,
                decoration: const InputDecoration(labelText: '运镜'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _dialogue,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: '台词', alignLabelWithHint: true),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _imagePrompt,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                    labelText: '图片提示词', alignLabelWithHint: true),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _videoPrompt,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                    labelText: '视频提示词', alignLabelWithHint: true),
              ),
            ],
          ),
        ),
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
