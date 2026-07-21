import 'dart:io';

import 'package:sqlite3/sqlite3.dart' show Database, Row;

import 'engine.dart';
import 'errors.dart';

const _defaultTimelineClipDurationMs = 1000;
const _minTimelineClipDurationMs = 100;
const _defaultTimelineClipOpacity = 1.0;

class TimelineClipRow {
  final int id;
  final int projectId;
  final int scriptId;
  final int? assetId;
  final String? name;
  final String filePath;
  final int lane;
  final int startMs;
  final int? durationMs;
  final double opacity;

  const TimelineClipRow({
    required this.id,
    required this.projectId,
    required this.scriptId,
    required this.assetId,
    required this.name,
    required this.filePath,
    required this.lane,
    required this.startMs,
    required this.durationMs,
    required this.opacity,
  });

  // 值相等而非引用相等：engine.timelineClips() 每次调用都返回全新实例，
  // 依赖默认引用相等会让任何无关重建都被判定为"片段变了"（见工作台检查器
  // 面板 _syncFromClip 的 didUpdateWidget 判断）。全仓库确认无代码依赖
  // TimelineClipRow 的引用相等语义（未用作 Map/Set key）。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TimelineClipRow &&
        other.id == id &&
        other.projectId == projectId &&
        other.scriptId == scriptId &&
        other.assetId == assetId &&
        other.name == name &&
        other.filePath == filePath &&
        other.lane == lane &&
        other.startMs == startMs &&
        other.durationMs == durationMs &&
        other.opacity == opacity;
  }

  @override
  int get hashCode => Object.hash(
        id,
        projectId,
        scriptId,
        assetId,
        name,
        filePath,
        lane,
        startMs,
        durationMs,
        opacity,
      );
}

extension TimelineClipApi on Engine {
  int addTimelineClipFromAsset({
    required int projectId,
    required int scriptId,
    required int clipAssetId,
    int lane = 1,
    int startMs = 0,
    int? durationMs,
  }) {
    final clipRow = db.select(
      'SELECT a.name name, a.type type, i.filePath filePath '
      'FROM o_assets a LEFT JOIN o_image i ON i.id=a.imageId '
      'WHERE a.id=? AND a.projectId=?',
      [clipAssetId, projectId],
    ).firstOrNull;
    final rel = clipRow?['filePath'] as String?;
    if (clipRow == null ||
        clipRow['type'] != 'clip' ||
        rel == null ||
        rel.isEmpty ||
        !File(media.absPath(rel)).existsSync()) {
      throw const EngineException(errFileType, {'type': 'clip'});
    }
    final normalizedLane = lane < 1 ? 1 : lane;
    final normalizedStart = startMs < 0 ? 0 : startMs;
    final normalizedDuration =
        durationMs != null && durationMs > 0 ? durationMs : null;
    final resolvedStart = _avoidTimelineOverlapOnAdd(
      db: db,
      scriptId: scriptId,
      lane: normalizedLane,
      startMs: normalizedStart,
      durationMs: normalizedDuration ?? _defaultTimelineClipDurationMs,
    );
    db.execute(
      'INSERT INTO o_timelineClip '
      '(projectId,scriptId,assetId,name,filePath,lane,startMs,durationMs) '
      'VALUES (?,?,?,?,?,?,?,?)',
      [
        projectId,
        scriptId,
        clipAssetId,
        clipRow['name'],
        rel,
        normalizedLane,
        resolvedStart,
        normalizedDuration,
      ],
    );
    return db.lastInsertRowId;
  }

  int addTimelineClipFromAssetRipple({
    required int projectId,
    required int scriptId,
    required int clipAssetId,
    int lane = 1,
    int startMs = 0,
    int? durationMs,
  }) {
    final clipRow = db.select(
      'SELECT a.name name, a.type type, i.filePath filePath '
      'FROM o_assets a LEFT JOIN o_image i ON i.id=a.imageId '
      'WHERE a.id=? AND a.projectId=?',
      [clipAssetId, projectId],
    ).firstOrNull;
    final rel = clipRow?['filePath'] as String?;
    if (clipRow == null ||
        clipRow['type'] != 'clip' ||
        rel == null ||
        rel.isEmpty ||
        !File(media.absPath(rel)).existsSync()) {
      throw const EngineException(errFileType, {'type': 'clip'});
    }
    final normalizedLane = lane < 1 ? 1 : lane;
    final normalizedStart = startMs < 0 ? 0 : startMs;
    final normalizedDuration =
        durationMs != null && durationMs > 0 ? durationMs : null;
    final shiftMs = normalizedDuration ?? _defaultTimelineClipDurationMs;
    // 共用分割器（与批量移动同一实现，语义单一来源）
    final split = _computeSplitAt(
      snapshot: _snapshotClips(db, scriptId),
      lane: normalizedLane,
      atMs: normalizedStart,
      tailStartMs: normalizedStart + shiftMs,
      excludeIds: const {},
    );
    if (split != null) {
      db.execute(
        'UPDATE o_timelineClip SET durationMs=? WHERE id=?',
        [split.headDuration, split.spanningId],
      );
    }
    db.execute(
      'UPDATE o_timelineClip '
      'SET startMs=startMs + ? '
      'WHERE scriptId=? AND lane=? AND startMs>=?',
      [shiftMs, scriptId, normalizedLane, normalizedStart],
    );
    db.execute(
      'INSERT INTO o_timelineClip '
      '(projectId,scriptId,assetId,name,filePath,lane,startMs,durationMs) '
      'VALUES (?,?,?,?,?,?,?,?)',
      [
        projectId,
        scriptId,
        clipAssetId,
        clipRow['name'],
        rel,
        normalizedLane,
        normalizedStart,
        normalizedDuration,
      ],
    );
    final insertedId = db.lastInsertRowId;
    if (split != null) {
      db.execute(_timelineClipInsertSql, split.tailInsert);
    }
    return insertedId;
  }

  int addTimelineClipFromAssetAutoLane({
    required int projectId,
    required int scriptId,
    required int clipAssetId,
    int lane = 1,
    int startMs = 0,
    int? durationMs,
  }) {
    final clipRow = db.select(
      'SELECT a.name name, a.type type, i.filePath filePath '
      'FROM o_assets a LEFT JOIN o_image i ON i.id=a.imageId '
      'WHERE a.id=? AND a.projectId=?',
      [clipAssetId, projectId],
    ).firstOrNull;
    final rel = clipRow?['filePath'] as String?;
    if (clipRow == null ||
        clipRow['type'] != 'clip' ||
        rel == null ||
        rel.isEmpty ||
        !File(media.absPath(rel)).existsSync()) {
      throw const EngineException(errFileType, {'type': 'clip'});
    }
    final normalizedLane = lane < 1 ? 1 : lane;
    final normalizedStart = startMs < 0 ? 0 : startMs;
    final normalizedDuration =
        durationMs != null && durationMs > 0 ? durationMs : null;
    final resolvedLane = _findFreeTimelineLane(
      db: db,
      scriptId: scriptId,
      preferredLane: normalizedLane,
      startMs: normalizedStart,
      durationMs: normalizedDuration ?? _defaultTimelineClipDurationMs,
    );
    db.execute(
      'INSERT INTO o_timelineClip '
      '(projectId,scriptId,assetId,name,filePath,lane,startMs,durationMs) '
      'VALUES (?,?,?,?,?,?,?,?)',
      [
        projectId,
        scriptId,
        clipAssetId,
        clipRow['name'],
        rel,
        resolvedLane,
        normalizedStart,
        normalizedDuration,
      ],
    );
    return db.lastInsertRowId;
  }

  List<TimelineClipRow> timelineClips(int scriptId) {
    return db
        .select(
          'SELECT * FROM o_timelineClip WHERE scriptId=? '
          'ORDER BY startMs ASC, lane ASC, id ASC',
          [scriptId],
        )
        .map(_timelineClipFromRow)
        .toList();
  }

  void updateTimelineClip({
    required int clipId,
    required int lane,
    required int startMs,
    int? durationMs,
    double? opacity,
    String? name,
  }) {
    final normalizedLane = lane < 1 ? 1 : lane;
    final normalizedStart = startMs < 0 ? 0 : startMs;
    final normalizedDuration =
        durationMs != null && durationMs > 0 ? durationMs : null;
    final normalizedOpacity =
        opacity == null ? null : _normalizeTimelineClipOpacity(opacity);
    db.execute(
      'UPDATE o_timelineClip '
      'SET name=COALESCE(?, name), lane=?, startMs=?, durationMs=?, '
      'opacity=COALESCE(?, opacity, ?) '
      'WHERE id=?',
      [
        name?.trim(),
        normalizedLane,
        normalizedStart,
        normalizedDuration,
        normalizedOpacity,
        _defaultTimelineClipOpacity,
        clipId,
      ],
    );
  }

  void moveTimelineClips({
    required List<int> clipIds,
    required int deltaStartMs,
    int deltaLane = 0,
  }) {
    if (clipIds.isEmpty) return;
    final placeholders = List.filled(clipIds.length, '?').join(',');
    final rows = db
        .select(
          'SELECT id,scriptId,startMs,lane,durationMs FROM o_timelineClip '
          'WHERE id IN ($placeholders)',
          clipIds,
        )
        .toList();
    if (rows.isEmpty) return;
    final minStart = rows
        .map((row) => (row['startMs'] as int?) ?? 0)
        .reduce((a, b) => a < b ? a : b);
    final minLane = rows
        .map((row) => (row['lane'] as int?) ?? 1)
        .reduce((a, b) => a < b ? a : b);
    final appliedStartDelta =
        deltaStartMs < -minStart ? -minStart : deltaStartMs;
    final appliedLaneDelta = deltaLane < 1 - minLane ? 1 - minLane : deltaLane;
    if (appliedStartDelta == 0 && appliedLaneDelta == 0) return;
    final selectedIds = rows.map((row) => row['id'] as int).toSet();
    final resolvedStartDelta = _timelineGroupMoveOffset(
      db: db,
      rows: rows,
      selectedIds: selectedIds,
      deltaStartMs: appliedStartDelta,
      deltaLane: appliedLaneDelta,
    );
    for (final row in rows) {
      final id = row['id'] as int;
      final nextStart = ((row['startMs'] as int?) ?? 0) + resolvedStartDelta;
      final nextLane = ((row['lane'] as int?) ?? 1) + appliedLaneDelta;
      db.execute(
        'UPDATE o_timelineClip SET startMs=?, lane=? WHERE id=?',
        [nextStart, nextLane, id],
      );
    }
  }

  void moveTimelineClipRipple({
    required int clipId,
    required int startMs,
  }) {
    final exists = db.select(
        'SELECT id FROM o_timelineClip WHERE id=?', [clipId]).firstOrNull;
    if (exists == null) {
      throw const EngineException(errManualInvalid);
    }
    moveTimelineClipsRipple(clipIds: [clipId], startMs: startMs);
  }

  void moveTimelineClipsRipple({
    required List<int> clipIds,
    required int startMs,
  }) {
    if (clipIds.isEmpty) return;
    final idSet = clipIds.toSet();
    final placeholders = List.filled(clipIds.length, '?').join(',');
    final anyRow = db
        .select(
          'SELECT scriptId FROM o_timelineClip '
          'WHERE id IN ($placeholders) LIMIT 1',
          clipIds,
        )
        .firstOrNull;
    if (anyRow == null) return;
    final scriptId = (anyRow['scriptId'] as int?) ?? 0;
    final snapshot = _snapshotClips(db, scriptId);
    final selected = snapshot.where((c) => idSet.contains(c.id)).toList();
    if (selected.isEmpty) return;
    final groupStart =
        selected.map((c) => c.startMs).reduce((a, b) => a < b ? a : b);
    final groupEnd =
        selected.map((c) => c.endMs).reduce((a, b) => a > b ? a : b);
    final nextGroupStart = startMs < 0 ? 0 : startMs;
    final deltaMs = nextGroupStart - groupStart;
    if (deltaMs == 0) return;
    final lanes = selected.map((c) => c.lane).toSet();

    final startWrites = <int, int>{};
    final durationWrites = <int, int>{};
    final tailInserts = <({int lane, List<Object?> params})>[];

    // ① 选中成员刚体位移
    for (final c in selected) {
      final ns = c.startMs + deltaMs;
      startWrites[c.id] = ns < 0 ? 0 : ns;
    }
    // ② 向后移动时分割让位：每个选中 clip 落点严格在非选中 clip 内部则缩头+出尾
    //    （单个版既有语义推广到批量，修复"批量移动产生真实重叠"）
    if (deltaMs < 0) {
      for (final c in selected) {
        final ns = startWrites[c.id]!;
        final split = _computeSplitAt(
          snapshot: snapshot,
          lane: c.lane,
          atMs: ns,
          tailStartMs: ns + c.durationMs,
          excludeIds: idSet,
        );
        if (split != null && !durationWrites.containsKey(split.spanningId)) {
          durationWrites[split.spanningId] = split.headDuration;
          tailInserts.add((lane: c.lane, params: split.tailInsert));
        }
      }
    }
    // ③ 非选中下游刚体让位（原语义：选中车道 startMs>=groupEnd 平移 delta）
    for (final c in snapshot) {
      if (idSet.contains(c.id) || !lanes.contains(c.lane)) continue;
      if (c.startMs < groupEnd) continue;
      final ns = c.startMs + deltaMs;
      startWrites[c.id] = ns < 0 ? 0 : ns;
    }
    _batchWriteColumn(db, 'durationMs', durationWrites);
    _batchWriteColumn(db, 'startMs', startWrites);
    final normalizeByLane = <int, List<int>>{};
    for (final ins in tailInserts) {
      db.execute(_timelineClipInsertSql, ins.params);
      final tailId = db.lastInsertRowId;
      final priority = normalizeByLane.putIfAbsent(
          ins.lane,
          () => [
                for (final c in selected)
                  if (c.lane == ins.lane) c.id,
              ]);
      priority.add(tailId);
    }
    for (final entry in normalizeByLane.entries) {
      _normalizeTimelineLaneForward(
        db: db,
        scriptId: scriptId,
        lane: entry.key,
        priorityIds: entry.value,
      );
    }
  }

  int splitTimelineClip({
    required int clipId,
    required int offsetMs,
  }) {
    final row = db.select(
        'SELECT * FROM o_timelineClip WHERE id=?', [clipId]).firstOrNull;
    if (row == null) {
      throw const EngineException(errManualInvalid);
    }
    final duration =
        (row['durationMs'] as int?) ?? _defaultTimelineClipDurationMs;
    var splitOffset = offsetMs;
    if (splitOffset < _minTimelineClipDurationMs) {
      splitOffset = _minTimelineClipDurationMs;
    }
    if (splitOffset > duration - _minTimelineClipDurationMs) {
      splitOffset = duration - _minTimelineClipDurationMs;
    }
    final secondDuration = duration - splitOffset;
    if (splitOffset <= 0 || secondDuration <= 0) {
      throw const EngineException(errManualInvalid);
    }
    final startMs = (row['startMs'] as int?) ?? 0;
    db.execute('UPDATE o_timelineClip SET durationMs=? WHERE id=?', [
      splitOffset,
      clipId,
    ]);
    db.execute(
      'INSERT INTO o_timelineClip '
      '(projectId,scriptId,assetId,name,filePath,lane,startMs,durationMs,opacity) '
      'VALUES (?,?,?,?,?,?,?,?,?)',
      [
        row['projectId'],
        row['scriptId'],
        row['assetId'],
        row['name'],
        row['filePath'],
        row['lane'],
        startMs + splitOffset,
        secondDuration,
        _normalizeTimelineClipOpacity(row['opacity'] as num?),
      ],
    );
    return db.lastInsertRowId;
  }

  List<int> splitTimelineClipsAt({
    required List<int> clipIds,
    required int playheadMs,
  }) {
    final newIds = <int>[];
    for (final clipId in clipIds) {
      final row = db.select(
          'SELECT * FROM o_timelineClip WHERE id=?', [clipId]).firstOrNull;
      if (row == null) continue;
      final startMs = (row['startMs'] as int?) ?? 0;
      final durationMs =
          (row['durationMs'] as int?) ?? _defaultTimelineClipDurationMs;
      final offsetMs = playheadMs - startMs;
      if (offsetMs < _minTimelineClipDurationMs ||
          offsetMs > durationMs - _minTimelineClipDurationMs) {
        continue;
      }
      newIds.add(splitTimelineClip(clipId: clipId, offsetMs: offsetMs));
    }
    return newIds;
  }

  int duplicateTimelineClip(int clipId) {
    final exists = db.select(
        'SELECT id FROM o_timelineClip WHERE id=?', [clipId]).firstOrNull;
    if (exists == null) {
      throw const EngineException(errManualInvalid);
    }
    return duplicateTimelineClips([clipId]).single;
  }

  int duplicateTimelineClipRipple(int clipId) {
    final exists = db.select(
        'SELECT id FROM o_timelineClip WHERE id=?', [clipId]).firstOrNull;
    if (exists == null) {
      throw const EngineException(errManualInvalid);
    }
    return duplicateTimelineClipsRipple([clipId]).single;
  }

  List<int> duplicateTimelineClips(List<int> clipIds) {
    if (clipIds.isEmpty) return const [];
    final placeholders = List.filled(clipIds.length, '?').join(',');
    final rows = db
        .select(
          'SELECT * FROM o_timelineClip WHERE id IN ($placeholders) '
          'ORDER BY startMs ASC, lane ASC, id ASC',
          clipIds,
        )
        .toList();
    if (rows.isEmpty) return const [];
    final selectedIds = rows.map((row) => row['id'] as int).toSet();
    final scriptId = (rows.first['scriptId'] as int?) ?? 0;
    final groupStart = rows
        .map((row) => (row['startMs'] as int?) ?? 0)
        .reduce((a, b) => a < b ? a : b);
    final groupEnd = rows.map((row) {
      final start = (row['startMs'] as int?) ?? 0;
      final duration =
          (row['durationMs'] as int?) ?? _defaultTimelineClipDurationMs;
      return start + duration;
    }).reduce((a, b) => a > b ? a : b);
    final initialOffset = groupEnd - groupStart;
    final offset = _timelineGroupDuplicateOffset(
      db: db,
      scriptId: scriptId,
      rows: rows,
      selectedIds: selectedIds,
      initialOffset: initialOffset,
    );
    final duplicateIds = <int>[];
    for (final row in rows) {
      final startMs = (row['startMs'] as int?) ?? 0;
      db.execute(
        'INSERT INTO o_timelineClip '
        '(projectId,scriptId,assetId,name,filePath,lane,startMs,durationMs,opacity) '
        'VALUES (?,?,?,?,?,?,?,?,?)',
        [
          row['projectId'],
          row['scriptId'],
          row['assetId'],
          row['name'],
          row['filePath'],
          row['lane'],
          startMs + offset,
          row['durationMs'],
          _normalizeTimelineClipOpacity(row['opacity'] as num?),
        ],
      );
      duplicateIds.add(db.lastInsertRowId);
    }
    return duplicateIds;
  }

  List<int> duplicateTimelineClipsRipple(List<int> clipIds) {
    if (clipIds.isEmpty) return const [];
    final placeholders = List.filled(clipIds.length, '?').join(',');
    final rows = db
        .select(
          'SELECT * FROM o_timelineClip WHERE id IN ($placeholders) '
          'ORDER BY startMs ASC, lane ASC, id ASC',
          clipIds,
        )
        .toList();
    if (rows.isEmpty) return const [];
    final selectedIds = rows.map((row) => row['id'] as int).toList();
    final scriptId = (rows.first['scriptId'] as int?) ?? 0;
    final groupStart = rows
        .map((row) => (row['startMs'] as int?) ?? 0)
        .reduce((a, b) => a < b ? a : b);
    final groupEnd = rows.map((row) {
      final start = (row['startMs'] as int?) ?? 0;
      final duration =
          (row['durationMs'] as int?) ?? _defaultTimelineClipDurationMs;
      return start + duration;
    }).reduce((a, b) => a > b ? a : b);
    final groupDuration = groupEnd - groupStart <= 0
        ? _defaultTimelineClipDurationMs
        : groupEnd - groupStart;
    final lanes = rows.map((row) => (row['lane'] as int?) ?? 1).toSet().toList()
      ..sort();
    final lanePlaceholders = List.filled(lanes.length, '?').join(',');
    final idPlaceholders = List.filled(selectedIds.length, '?').join(',');
    db.execute(
      'UPDATE o_timelineClip SET startMs=startMs + ? '
      'WHERE scriptId=? AND lane IN ($lanePlaceholders) AND startMs>=? '
      'AND id NOT IN ($idPlaceholders)',
      [groupDuration, scriptId, ...lanes, groupEnd, ...selectedIds],
    );
    final duplicateIds = <int>[];
    for (final row in rows) {
      final startMs = (row['startMs'] as int?) ?? 0;
      db.execute(
        'INSERT INTO o_timelineClip '
        '(projectId,scriptId,assetId,name,filePath,lane,startMs,durationMs,opacity) '
        'VALUES (?,?,?,?,?,?,?,?,?)',
        [
          row['projectId'],
          row['scriptId'],
          row['assetId'],
          row['name'],
          row['filePath'],
          row['lane'],
          startMs + groupDuration,
          row['durationMs'],
          _normalizeTimelineClipOpacity(row['opacity'] as num?),
        ],
      );
      duplicateIds.add(db.lastInsertRowId);
    }
    return duplicateIds;
  }

  void deleteTimelineClip(int clipId) {
    db.execute('DELETE FROM o_timelineClip WHERE id=?', [clipId]);
  }

  void deleteTimelineClips(List<int> clipIds) {
    if (clipIds.isEmpty) return;
    final placeholders = List.filled(clipIds.length, '?').join(',');
    db.execute(
        'DELETE FROM o_timelineClip WHERE id IN ($placeholders)', clipIds);
  }

  void deleteTimelineClipsRipple(List<int> clipIds) {
    if (clipIds.isEmpty) return;
    final idSet = clipIds.toSet();
    final placeholders = List.filled(clipIds.length, '?').join(',');
    final scriptIds = db
        .select(
          'SELECT DISTINCT scriptId FROM o_timelineClip '
          'WHERE id IN ($placeholders)',
          clipIds,
        )
        .map((r) => (r['scriptId'] as int?) ?? 0)
        .toList();
    if (scriptIds.isEmpty) return;
    for (final scriptId in scriptIds) {
      final snapshot = _snapshotClips(db, scriptId);
      final selected = snapshot.where((c) => idSet.contains(c.id)).toList();
      if (selected.isEmpty) continue;
      final startWrites = <int, int>{};
      for (final c in snapshot) {
        if (idSet.contains(c.id)) continue;
        var shiftMs = 0;
        for (final s in selected) {
          if (s.lane != c.lane) continue;
          if (c.startMs >= s.endMs) shiftMs += s.durationMs;
        }
        if (shiftMs <= 0) continue;
        final ns = c.startMs - shiftMs;
        startWrites[c.id] = ns < 0 ? 0 : ns;
      }
      final delIds = selected.map((c) => c.id).toList();
      final delPh = List.filled(delIds.length, '?').join(',');
      db.execute('DELETE FROM o_timelineClip WHERE id IN ($delPh)', delIds);
      _batchWriteColumn(db, 'startMs', startWrites);
    }
  }

  void deleteTimelineClipRipple(int clipId) {
    deleteTimelineClipsRipple([clipId]);
  }

  void resizeTimelineClipEndRipple({
    required int clipId,
    required int durationMs,
  }) {
    resizeTimelineClipsEndRipple(clipIds: [clipId], durationMs: durationMs);
  }

  void resizeTimelineClipsEnd({
    required List<int> clipIds,
    required int durationMs,
  }) {
    if (clipIds.isEmpty) return;
    final idSet = clipIds.toSet();
    final nextDurationMs = durationMs < _minTimelineClipDurationMs
        ? _minTimelineClipDurationMs
        : durationMs;
    final placeholders = List.filled(clipIds.length, '?').join(',');
    final scriptIds = db
        .select(
          'SELECT DISTINCT scriptId FROM o_timelineClip '
          'WHERE id IN ($placeholders)',
          clipIds,
        )
        .map((r) => (r['scriptId'] as int?) ?? 0)
        .toList();
    // 一次快照+内存钳制+一条 CASE 批量写（还原 82a2839 之前的批量语义，消灭 N+1）
    for (final scriptId in scriptIds) {
      final snapshot = _snapshotClips(db, scriptId);
      final durationWrites = <int, int>{};
      for (final c in snapshot) {
        if (!idSet.contains(c.id)) continue;
        var resolved = nextDurationMs;
        int? blockerStart;
        for (final other in snapshot) {
          if (other.id == c.id || other.lane != c.lane) continue;
          if (other.startMs > c.startMs &&
              (blockerStart == null || other.startMs < blockerStart)) {
            blockerStart = other.startMs;
          }
        }
        if (blockerStart != null && blockerStart - c.startMs < resolved) {
          resolved = blockerStart - c.startMs;
        }
        if (resolved < _minTimelineClipDurationMs) {
          resolved = _minTimelineClipDurationMs;
        }
        durationWrites[c.id] = resolved;
      }
      _batchWriteColumn(db, 'durationMs', durationWrites);
    }
  }

  void resizeTimelineClipsEndRipple({
    required List<int> clipIds,
    required int durationMs,
  }) {
    if (clipIds.isEmpty) return;
    final idSet = clipIds.toSet();
    final nextDurationMs = durationMs < _minTimelineClipDurationMs
        ? _minTimelineClipDurationMs
        : durationMs;
    final placeholders = List.filled(clipIds.length, '?').join(',');
    final scriptIds = db
        .select(
          'SELECT DISTINCT scriptId FROM o_timelineClip '
          'WHERE id IN ($placeholders)',
          clipIds,
        )
        .map((r) => (r['scriptId'] as int?) ?? 0)
        .toList();
    for (final scriptId in scriptIds) {
      final snapshot = _snapshotClips(db, scriptId);
      final selected = snapshot.where((c) => idSet.contains(c.id)).toList();
      if (selected.isEmpty) continue;
      final startWrites = <int, int>{};
      final durationWrites = <int, int>{};
      for (final s in selected) {
        durationWrites[s.id] = nextDurationMs;
      }
      final byLane = <int, List<_ClipSnap>>{};
      for (final s in selected) {
        byLane.putIfAbsent(s.lane, () => []).add(s);
      }
      for (final entry in byLane.entries) {
        final lane = entry.key;
        final laneClips = entry.value;
        final oldGroupEnd =
            laneClips.map((c) => c.endMs).reduce((a, b) => a > b ? a : b);
        laneClips.sort((a, b) {
          final byStart = a.startMs.compareTo(b.startMs);
          return byStart != 0 ? byStart : a.id.compareTo(b.id);
        });
        final selectedStarts = <int, int>{};
        var cursor = -1 << 30;
        for (final s in laneClips) {
          var ns = s.startMs;
          if (ns < cursor) {
            ns = cursor;
            startWrites[s.id] = ns;
          }
          selectedStarts[s.id] = ns;
          cursor = ns + nextDurationMs;
        }
        final newGroupEnd = laneClips
            .map((c) => (selectedStarts[c.id] ?? c.startMs) + nextDurationMs)
            .reduce((a, b) => a > b ? a : b);
        final netShiftMs = newGroupEnd - oldGroupEnd;
        if (netShiftMs == 0) continue;
        for (final c in snapshot) {
          if (idSet.contains(c.id) || c.lane != lane) continue;
          if (c.startMs < oldGroupEnd) continue;
          final ns = c.startMs + netShiftMs;
          startWrites[c.id] = ns < 0 ? 0 : ns;
        }
      }
      _batchWriteColumn(db, 'startMs', startWrites);
      _batchWriteColumn(db, 'durationMs', durationWrites);
    }
  }
}

// ───────────────── 排布引擎共享核心（v0.4 spec §5）─────────────────
// 设计约束：每个波纹操作①只取一次全量快照②计算全在内存③写库用 CASE 批量语句。
// 单个操作一律委托批量版（batch-of-1 ≡ singular 由构造保证，等价性测试锁死）。

class _ClipSnap {
  final int id;
  final Object? projectId;
  final int scriptId;
  final Object? assetId;
  final Object? name;
  final Object? filePath;
  final int lane;
  int startMs;
  int durationMs;
  final Object? opacity;
  _ClipSnap(Row r)
      : id = r['id'] as int,
        projectId = r['projectId'],
        scriptId = (r['scriptId'] as int?) ?? 0,
        assetId = r['assetId'],
        name = r['name'],
        filePath = r['filePath'],
        lane = (r['lane'] as int?) ?? 1,
        startMs = (r['startMs'] as int?) ?? 0,
        durationMs =
            (r['durationMs'] as int?) ?? _defaultTimelineClipDurationMs,
        opacity = r['opacity'];
  int get endMs => startMs + durationMs;
}

List<_ClipSnap> _snapshotClips(Database db, int scriptId) => db
    .select(
      'SELECT * FROM o_timelineClip WHERE scriptId=? '
      'ORDER BY lane ASC, startMs ASC, id ASC',
      [scriptId],
    )
    .map(_ClipSnap.new)
    .toList();

/// 批量绝对值写回：一条 CASE 语句搞定 N 行（分块防超长 SQL）。
void _batchWriteColumn(Database db, String column, Map<int, int> valueById) {
  if (valueById.isEmpty) return;
  final entries = valueById.entries.toList();
  const chunk = 200;
  for (var i = 0; i < entries.length; i += chunk) {
    final part = entries.sublist(
        i, i + chunk > entries.length ? entries.length : i + chunk);
    final cases = part.map((_) => 'WHEN ? THEN ?').join(' ');
    final ids = part.map((e) => e.key).toList();
    final idPh = List.filled(ids.length, '?').join(',');
    db.execute(
      'UPDATE o_timelineClip SET $column=CASE id $cases END '
      'WHERE id IN ($idPh)',
      [
        for (final e in part) ...[e.key, e.value],
        ...ids
      ],
    );
  }
}

/// 分割器：目标位置 atMs 严格落在某个非排除 clip 内部时，缩头 + 产出尾段模板。
/// 返回 (缩头写入的 durationMs 更新, 尾段 INSERT 参数)；不命中返回 null。
({int spanningId, int headDuration, List<Object?> tailInsert})?
    _computeSplitAt({
  required List<_ClipSnap> snapshot,
  required int lane,
  required int atMs,
  required int tailStartMs,
  required Set<int> excludeIds,
}) {
  _ClipSnap? spanning;
  for (final c in snapshot) {
    if (c.lane != lane || excludeIds.contains(c.id)) continue;
    if (c.startMs < atMs && c.endMs > atMs) {
      if (spanning == null ||
          c.startMs > spanning.startMs ||
          (c.startMs == spanning.startMs && c.id > spanning.id)) {
        spanning = c;
      }
    }
  }
  if (spanning == null) return null;
  final headDuration = atMs - spanning.startMs;
  final tailDuration = spanning.endMs - atMs;
  if (headDuration <= 0 || tailDuration <= 0) return null;
  return (
    spanningId: spanning.id,
    headDuration: headDuration,
    tailInsert: [
      spanning.projectId,
      spanning.scriptId,
      spanning.assetId,
      spanning.name,
      spanning.filePath,
      spanning.lane,
      tailStartMs,
      tailDuration,
      _normalizeTimelineClipOpacity(spanning.opacity as num?),
    ],
  );
}

const _timelineClipInsertSql = 'INSERT INTO o_timelineClip '
    '(projectId,scriptId,assetId,name,filePath,lane,startMs,durationMs,opacity) '
    'VALUES (?,?,?,?,?,?,?,?,?)';

TimelineClipRow _timelineClipFromRow(Row row) => TimelineClipRow(
      id: row['id'] as int,
      projectId: (row['projectId'] as int?) ?? 0,
      scriptId: (row['scriptId'] as int?) ?? 0,
      assetId: row['assetId'] as int?,
      name: row['name'] as String?,
      filePath: (row['filePath'] as String?) ?? '',
      lane: (row['lane'] as int?) ?? 1,
      startMs: (row['startMs'] as int?) ?? 0,
      durationMs: row['durationMs'] as int?,
      opacity: _normalizeTimelineClipOpacity(row['opacity'] as num?),
    );

double _normalizeTimelineClipOpacity(num? value) {
  final resolved = value?.toDouble() ?? _defaultTimelineClipOpacity;
  if (resolved < 0) return 0;
  if (resolved > 1) return 1;
  return resolved;
}

int _avoidTimelineOverlapOnAdd({
  required Database db,
  required int scriptId,
  required int lane,
  required int startMs,
  required int durationMs,
}) {
  var candidate = startMs < 0 ? 0 : startMs;
  final others = db.select(
    'SELECT startMs,durationMs FROM o_timelineClip '
    'WHERE scriptId=? AND lane=? ORDER BY startMs ASC, id ASC',
    [scriptId, lane < 1 ? 1 : lane],
  ).toList();
  var changed = true;
  var guard = 0;
  while (changed && guard < others.length + 1) {
    changed = false;
    guard += 1;
    for (final other in others) {
      final otherStart = (other['startMs'] as int?) ?? 0;
      final otherDuration =
          (other['durationMs'] as int?) ?? _defaultTimelineClipDurationMs;
      final otherEnd = otherStart + otherDuration;
      final candidateEnd = candidate + durationMs;
      final overlaps = candidate < otherEnd && candidateEnd > otherStart;
      if (!overlaps) continue;
      candidate = candidate < otherStart ? otherStart - durationMs : otherEnd;
      if (candidate < 0) candidate = 0;
      changed = true;
      break;
    }
  }
  return candidate;
}

int _findFreeTimelineLane({
  required Database db,
  required int scriptId,
  required int preferredLane,
  required int startMs,
  required int durationMs,
}) {
  var lane = preferredLane < 1 ? 1 : preferredLane;
  final maxLaneRow = db.select(
    'SELECT MAX(lane) maxLane FROM o_timelineClip WHERE scriptId=?',
    [scriptId],
  ).firstOrNull;
  final maxLane = (maxLaneRow?['maxLane'] as int?) ?? lane;
  final guardLimit = maxLane + 2;
  while (lane <= guardLimit) {
    if (_timelineLaneHasSpace(
      db: db,
      scriptId: scriptId,
      lane: lane,
      startMs: startMs,
      durationMs: durationMs,
    )) {
      return lane;
    }
    lane += 1;
  }
  return guardLimit + 1;
}

bool _timelineLaneHasSpace({
  required Database db,
  required int scriptId,
  required int lane,
  required int startMs,
  required int durationMs,
}) {
  final endMs = startMs + durationMs;
  final conflicts = db.select(
    'SELECT 1 FROM o_timelineClip '
    'WHERE scriptId=? AND lane=? '
    'AND ? < startMs + COALESCE(durationMs, ?) '
    'AND ? > startMs '
    'LIMIT 1',
    [
      scriptId,
      lane < 1 ? 1 : lane,
      startMs,
      _defaultTimelineClipDurationMs,
      endMs
    ],
  );
  return conflicts.isEmpty;
}

int _timelineGroupDuplicateOffset({
  required Database db,
  required int scriptId,
  required List<Row> rows,
  required Set<int> selectedIds,
  required int initialOffset,
}) {
  var offset =
      initialOffset <= 0 ? _defaultTimelineClipDurationMs : initialOffset;
  final placeholders = List.filled(selectedIds.length, '?').join(',');
  final others = db.select(
    'SELECT id,lane,startMs,durationMs FROM o_timelineClip '
    'WHERE scriptId=? AND id NOT IN ($placeholders) '
    'ORDER BY startMs ASC, id ASC',
    [scriptId, ...selectedIds],
  ).toList();
  var guard = 0;
  while (guard < others.length + rows.length + 4) {
    guard += 1;
    int? nextOffset;
    for (final row in rows) {
      final lane = (row['lane'] as int?) ?? 1;
      final start = (row['startMs'] as int?) ?? 0;
      final duration =
          (row['durationMs'] as int?) ?? _defaultTimelineClipDurationMs;
      final candidateStart = start + offset;
      final candidateEnd = candidateStart + duration;
      for (final other in others) {
        final otherLane = (other['lane'] as int?) ?? 1;
        if (otherLane != lane) continue;
        final otherStart = (other['startMs'] as int?) ?? 0;
        final otherDuration =
            (other['durationMs'] as int?) ?? _defaultTimelineClipDurationMs;
        final otherEnd = otherStart + otherDuration;
        final overlaps = candidateStart < otherEnd && candidateEnd > otherStart;
        if (!overlaps) continue;
        final shiftedOffset = otherEnd - start;
        if (shiftedOffset > offset &&
            (nextOffset == null || shiftedOffset > nextOffset)) {
          nextOffset = shiftedOffset;
        }
      }
    }
    if (nextOffset == null) return offset;
    offset = nextOffset;
  }
  return offset;
}

int _timelineGroupMoveOffset({
  required Database db,
  required List<Row> rows,
  required Set<int> selectedIds,
  required int deltaStartMs,
  required int deltaLane,
}) {
  var offset = deltaStartMs;
  final scriptIds =
      rows.map((row) => (row['scriptId'] as int?) ?? 0).toSet().toList();
  final scriptPlaceholders = List.filled(scriptIds.length, '?').join(',');
  final selectedPlaceholders = List.filled(selectedIds.length, '?').join(',');
  final others = db.select(
    'SELECT id,scriptId,lane,startMs,durationMs FROM o_timelineClip '
    'WHERE scriptId IN ($scriptPlaceholders) '
    'AND id NOT IN ($selectedPlaceholders) '
    'ORDER BY startMs ASC, id ASC',
    [...scriptIds, ...selectedIds],
  ).toList();
  var guard = 0;
  while (guard < others.length + rows.length + 4) {
    guard += 1;
    int? nextOffset;
    for (final row in rows) {
      final scriptId = (row['scriptId'] as int?) ?? 0;
      final lane = ((row['lane'] as int?) ?? 1) + deltaLane;
      final start = (row['startMs'] as int?) ?? 0;
      final duration =
          (row['durationMs'] as int?) ?? _defaultTimelineClipDurationMs;
      final candidateStart = start + offset;
      final candidateEnd = candidateStart + duration;
      for (final other in others) {
        final otherScriptId = (other['scriptId'] as int?) ?? 0;
        final otherLane = (other['lane'] as int?) ?? 1;
        if (otherScriptId != scriptId || otherLane != lane) continue;
        final otherStart = (other['startMs'] as int?) ?? 0;
        final otherDuration =
            (other['durationMs'] as int?) ?? _defaultTimelineClipDurationMs;
        final otherEnd = otherStart + otherDuration;
        final overlaps = candidateStart < otherEnd && candidateEnd > otherStart;
        if (!overlaps) continue;
        final shiftedOffset = otherEnd - start;
        if (shiftedOffset > offset &&
            (nextOffset == null || shiftedOffset > nextOffset)) {
          nextOffset = shiftedOffset;
        }
      }
    }
    if (nextOffset == null) return offset;
    offset = nextOffset;
  }
  return offset;
}

void _normalizeTimelineLaneForward({
  required Database db,
  required int scriptId,
  required int lane,
  List<int> priorityIds = const [],
}) {
  final priority = <int, int>{
    for (var i = 0; i < priorityIds.length; i++) priorityIds[i]: i,
  };
  final rows = db.select(
    'SELECT id,startMs,durationMs FROM o_timelineClip '
    'WHERE scriptId=? AND lane=?',
    [scriptId, lane < 1 ? 1 : lane],
  ).toList()
    ..sort((a, b) {
      final startA = (a['startMs'] as int?) ?? 0;
      final startB = (b['startMs'] as int?) ?? 0;
      if (startA != startB) return startA.compareTo(startB);
      final idA = a['id'] as int;
      final idB = b['id'] as int;
      final priorityA = priority[idA] ?? priorityIds.length;
      final priorityB = priority[idB] ?? priorityIds.length;
      if (priorityA != priorityB) return priorityA.compareTo(priorityB);
      return idA.compareTo(idB);
    });
  var cursorMs = 0;
  for (final row in rows) {
    final id = row['id'] as int;
    final startMs = (row['startMs'] as int?) ?? 0;
    final durationMs =
        (row['durationMs'] as int?) ?? _defaultTimelineClipDurationMs;
    final nextStartMs = startMs < cursorMs ? cursorMs : startMs;
    if (nextStartMs != startMs) {
      db.execute(
        'UPDATE o_timelineClip SET startMs=? WHERE id=?',
        [nextStartMs, id],
      );
    }
    cursorMs = nextStartMs + durationMs;
  }
}
