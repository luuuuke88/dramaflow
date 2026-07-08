import 'dart:io';

import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/timeline_clip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TimelineHarness {
  final Directory dir;
  final Engine engine;
  final int projectId;
  final int scriptId;

  _TimelineHarness._(this.dir, this.engine, this.projectId, this.scriptId);

  factory _TimelineHarness.create() {
    final dir = Directory.systemTemp.createTempSync('dramaflow-eq-');
    final db = openEngineDb(':memory:');
    final engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    final projectId = engine.addProject(projectType: 'novel', name: 'eq');
    final scriptId =
        engine.addScript(projectId: projectId, name: '一', content: 'x');
    return _TimelineHarness._(dir, engine, projectId, scriptId);
  }

  void dispose() {
    engine.dispose();
    engine.db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  int insertClip({
    required int lane,
    required int startMs,
    required int durationMs,
    required String filePath,
  }) {
    engine.db.execute(
      'INSERT INTO o_timelineClip '
      '(projectId,scriptId,assetId,name,filePath,lane,startMs,durationMs) '
      'VALUES (?,?,?,?,?,?,?,?)',
      [
        projectId,
        scriptId,
        null,
        p.basenameWithoutExtension(filePath),
        filePath,
        lane,
        startMs,
        durationMs,
      ],
    );
    return engine.db.lastInsertRowId;
  }
}

class _SeededTimeline {
  final _TimelineHarness harness;
  final int a;
  final int b;
  final int c;
  final int otherLane;

  const _SeededTimeline(this.harness, this.a, this.b, this.c, this.otherLane);
}

void main() {
  _TimelineHarness harness() {
    final h = _TimelineHarness.create();
    addTearDown(h.dispose);
    return h;
  }

  _SeededTimeline seedThreeClips() {
    final h = harness();
    final a = h.insertClip(
      lane: 1,
      startMs: 0,
      durationMs: 1000,
      filePath: 'p/a.mp4',
    );
    final b = h.insertClip(
      lane: 1,
      startMs: 1500,
      durationMs: 1000,
      filePath: 'p/b.mp4',
    );
    final c = h.insertClip(
      lane: 1,
      startMs: 3000,
      durationMs: 1000,
      filePath: 'p/c.mp4',
    );
    final otherLane = h.insertClip(
      lane: 2,
      startMs: 1500,
      durationMs: 1000,
      filePath: 'p/d.mp4',
    );
    return _SeededTimeline(h, a, b, c, otherLane);
  }

  List<Map<String, Object?>> dumpClips(_TimelineHarness h) {
    final rows = [
      for (final clip in h.engine.timelineClips(h.scriptId))
        {
          'lane': clip.lane,
          'startMs': clip.startMs,
          'durationMs': clip.durationMs,
          'filePath': clip.filePath,
        },
    ];
    rows.sort((a, b) {
      for (final key in ['lane', 'startMs', 'durationMs']) {
        final cmp = (a[key] as int).compareTo(b[key] as int);
        if (cmp != 0) return cmp;
      }
      return (a['filePath'] as String).compareTo(b['filePath'] as String);
    });
    return rows;
  }

  void expectNoLaneOverlap(_TimelineHarness h) {
    final byLane = <int, List<TimelineClipRow>>{};
    for (final clip in h.engine.timelineClips(h.scriptId)) {
      byLane.putIfAbsent(clip.lane, () => []).add(clip);
    }
    for (final laneClips in byLane.values) {
      laneClips.sort((a, b) => a.startMs.compareTo(b.startMs));
      for (var i = 1; i < laneClips.length; i++) {
        final previous = laneClips[i - 1];
        final current = laneClips[i];
        final previousEnd = previous.startMs + (previous.durationMs ?? 1000);
        expect(
          previousEnd <= current.startMs,
          isTrue,
          reason:
              'lane ${current.lane} overlap: ${previous.id} ends $previousEnd, '
              '${current.id} starts ${current.startMs}',
        );
      }
    }
  }

  group('single/batch equivalence', () {
    test('moveTimelineClipRipple ≡ moveTimelineClipsRipple', () {
      final single = seedThreeClips();
      final batch = seedThreeClips();

      single.harness.engine
          .moveTimelineClipRipple(clipId: single.b, startMs: 500);
      batch.harness.engine
          .moveTimelineClipsRipple(clipIds: [batch.b], startMs: 500);

      expect(dumpClips(single.harness), dumpClips(batch.harness));
    });

    test('updateTimelineClip(startMs) ≡ moveTimelineClips 单元素', () {
      final single = seedThreeClips();
      final batch = seedThreeClips();
      final row = single.harness.engine
          .timelineClips(single.harness.scriptId)
          .singleWhere((clip) => clip.id == single.b);

      single.harness.engine.updateTimelineClip(
        clipId: single.b,
        lane: row.lane,
        startMs: row.startMs + 300,
        durationMs: row.durationMs,
      );
      batch.harness.engine.moveTimelineClips(
        clipIds: [batch.b],
        deltaStartMs: 300,
      );

      expect(dumpClips(single.harness), dumpClips(batch.harness));
    });

    test('duplicateTimelineClip ≡ duplicateTimelineClips', () {
      final single = seedThreeClips();
      final batch = seedThreeClips();

      single.harness.engine.duplicateTimelineClip(single.b);
      batch.harness.engine.duplicateTimelineClips([batch.b]);

      expect(dumpClips(single.harness), dumpClips(batch.harness));
    });

    test('duplicateTimelineClipRipple ≡ duplicateTimelineClipsRipple', () {
      final single = seedThreeClips();
      final batch = seedThreeClips();

      single.harness.engine.duplicateTimelineClipRipple(single.b);
      batch.harness.engine.duplicateTimelineClipsRipple([batch.b]);

      expect(dumpClips(single.harness), dumpClips(batch.harness));
    });

    test('deleteTimelineClip ≡ deleteTimelineClips', () {
      final single = seedThreeClips();
      final batch = seedThreeClips();

      single.harness.engine.deleteTimelineClip(single.b);
      batch.harness.engine.deleteTimelineClips([batch.b]);

      expect(dumpClips(single.harness), dumpClips(batch.harness));
    });

    test('deleteTimelineClipRipple ≡ deleteTimelineClipsRipple', () {
      final single = seedThreeClips();
      final batch = seedThreeClips();

      single.harness.engine.deleteTimelineClipRipple(single.b);
      batch.harness.engine.deleteTimelineClipsRipple([batch.b]);

      expect(dumpClips(single.harness), dumpClips(batch.harness));
    });

    test('resizeTimelineClipEndRipple ≡ resizeTimelineClipsEndRipple', () {
      final single = seedThreeClips();
      final batch = seedThreeClips();

      single.harness.engine.resizeTimelineClipEndRipple(
        clipId: single.b,
        durationMs: 600,
      );
      batch.harness.engine.resizeTimelineClipsEndRipple(
        clipIds: [batch.b],
        durationMs: 600,
      );

      expect(dumpClips(single.harness), dumpClips(batch.harness));
    });

    test('resizeTimelineClipsEnd 单元素重复执行保持稳定', () {
      final seeded = seedThreeClips();

      seeded.harness.engine.resizeTimelineClipsEnd(
        clipIds: [seeded.b],
        durationMs: 600,
      );
      final once = dumpClips(seeded.harness);
      seeded.harness.engine.resizeTimelineClipsEnd(
        clipIds: [seeded.b],
        durationMs: 600,
      );

      expect(dumpClips(seeded.harness), once);
    });
  });

  group('spec §5 regressions', () {
    test('批量波纹移动进另一 clip 中间会分割且无重叠', () {
      final seeded = seedThreeClips();

      seeded.harness.engine.moveTimelineClipsRipple(
        clipIds: [seeded.b],
        startMs: 500,
      );

      expect(seeded.harness.engine.timelineClips(seeded.harness.scriptId),
          hasLength(greaterThan(4)));
      expectNoLaneOverlap(seeded.harness);
    });

    test('相邻两选中批量波纹裁尾只移动下游净位移且选中互不重叠', () {
      final h = harness();
      final a = h.insertClip(
        lane: 1,
        startMs: 0,
        durationMs: 1000,
        filePath: 'p/a.mp4',
      );
      final b = h.insertClip(
        lane: 1,
        startMs: 1000,
        durationMs: 1000,
        filePath: 'p/b.mp4',
      );
      final bystander = h.insertClip(
        lane: 1,
        startMs: 2500,
        durationMs: 1000,
        filePath: 'p/c.mp4',
      );

      h.engine.resizeTimelineClipsEndRipple(
        clipIds: [a, b],
        durationMs: 500,
      );

      final clips = h.engine.timelineClips(h.scriptId);
      expect(clips.singleWhere((clip) => clip.id == a).durationMs, 500);
      expect(clips.singleWhere((clip) => clip.id == b).durationMs, 500);
      expect(clips.singleWhere((clip) => clip.id == bystander).startMs, 2000);
      expectNoLaneOverlap(h);
    });
  });
}
