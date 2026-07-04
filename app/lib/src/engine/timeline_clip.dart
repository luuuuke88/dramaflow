import 'dart:io';

import 'package:sqlite3/sqlite3.dart' show Row;

import 'engine.dart';
import 'errors.dart';

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

  void deleteTimelineClip(int clipId) {
    db.execute('DELETE FROM o_timelineClip WHERE id=?', [clipId]);
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
