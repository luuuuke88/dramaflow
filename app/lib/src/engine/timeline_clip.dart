import 'dart:io';

import 'package:sqlite3/sqlite3.dart' show Database, Row;

import 'engine.dart';
import 'errors.dart';

const _defaultTimelineClipDurationMs = 1000;
const _minTimelineClipDurationMs = 100;

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
  });
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
    return db.lastInsertRowId;
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
  }) {
    final normalizedLane = lane < 1 ? 1 : lane;
    final normalizedStart = startMs < 0 ? 0 : startMs;
    final normalizedDuration =
        durationMs != null && durationMs > 0 ? durationMs : null;
    db.execute(
      'UPDATE o_timelineClip SET lane=?, startMs=?, durationMs=? WHERE id=?',
      [normalizedLane, normalizedStart, normalizedDuration, clipId],
    );
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
      '(projectId,scriptId,assetId,name,filePath,lane,startMs,durationMs) '
      'VALUES (?,?,?,?,?,?,?,?)',
      [
        row['projectId'],
        row['scriptId'],
        row['assetId'],
        row['name'],
        row['filePath'],
        row['lane'],
        startMs + splitOffset,
        secondDuration,
      ],
    );
    return db.lastInsertRowId;
  }

  int duplicateTimelineClip(int clipId) {
    final row = db.select(
        'SELECT * FROM o_timelineClip WHERE id=?', [clipId]).firstOrNull;
    if (row == null) {
      throw const EngineException(errManualInvalid);
    }
    final scriptId = (row['scriptId'] as int?) ?? 0;
    final lane = (row['lane'] as int?) ?? 1;
    final startMs = (row['startMs'] as int?) ?? 0;
    final durationMs =
        (row['durationMs'] as int?) ?? _defaultTimelineClipDurationMs;
    final resolvedStart = _avoidTimelineOverlapForward(
      db: db,
      scriptId: scriptId,
      lane: lane,
      startMs: startMs + durationMs,
      durationMs: durationMs,
    );
    db.execute(
      'INSERT INTO o_timelineClip '
      '(projectId,scriptId,assetId,name,filePath,lane,startMs,durationMs) '
      'VALUES (?,?,?,?,?,?,?,?)',
      [
        row['projectId'],
        scriptId,
        row['assetId'],
        row['name'],
        row['filePath'],
        lane,
        resolvedStart,
        row['durationMs'],
      ],
    );
    return db.lastInsertRowId;
  }

  void deleteTimelineClip(int clipId) {
    db.execute('DELETE FROM o_timelineClip WHERE id=?', [clipId]);
  }

  void deleteTimelineClipRipple(int clipId) {
    final row = db.select(
        'SELECT * FROM o_timelineClip WHERE id=?', [clipId]).firstOrNull;
    if (row == null) return;
    final scriptId = (row['scriptId'] as int?) ?? 0;
    final lane = (row['lane'] as int?) ?? 1;
    final startMs = (row['startMs'] as int?) ?? 0;
    final durationMs =
        (row['durationMs'] as int?) ?? _defaultTimelineClipDurationMs;
    final endMs = startMs + durationMs;
    db.execute('DELETE FROM o_timelineClip WHERE id=?', [clipId]);
    db.execute(
      'UPDATE o_timelineClip '
      'SET startMs=CASE WHEN startMs - ? < 0 THEN 0 ELSE startMs - ? END '
      'WHERE scriptId=? AND lane=? AND startMs>=?',
      [durationMs, durationMs, scriptId, lane, endMs],
    );
  }

  void resizeTimelineClipEndRipple({
    required int clipId,
    required int durationMs,
  }) {
    final row = db.select(
        'SELECT * FROM o_timelineClip WHERE id=?', [clipId]).firstOrNull;
    if (row == null) return;
    final scriptId = (row['scriptId'] as int?) ?? 0;
    final lane = (row['lane'] as int?) ?? 1;
    final startMs = (row['startMs'] as int?) ?? 0;
    final oldDurationMs =
        (row['durationMs'] as int?) ?? _defaultTimelineClipDurationMs;
    final nextDurationMs = durationMs < _minTimelineClipDurationMs
        ? _minTimelineClipDurationMs
        : durationMs;
    final deltaMs = nextDurationMs - oldDurationMs;
    final oldEndMs = startMs + oldDurationMs;
    db.execute('UPDATE o_timelineClip SET durationMs=? WHERE id=?', [
      nextDurationMs,
      clipId,
    ]);
    if (deltaMs == 0) return;
    db.execute(
      'UPDATE o_timelineClip '
      'SET startMs=CASE WHEN startMs + ? < 0 THEN 0 ELSE startMs + ? END '
      'WHERE scriptId=? AND lane=? AND startMs>=?',
      [deltaMs, deltaMs, scriptId, lane, oldEndMs],
    );
  }
}

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
    );

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

int _avoidTimelineOverlapForward({
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
      candidate = otherEnd;
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
