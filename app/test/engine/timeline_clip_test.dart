import 'dart:io';

import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/timeline_clip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late int projectId;
  late int scriptId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-timeline-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '时间线测试');
    scriptId = engine.addScript(projectId: projectId, name: '一', content: 'x');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  int clipAsset(String rel, String name) {
    final f = File(engine.mediaAbsPath(rel));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync([1, 2, 3]);
    return engine.registerClipAsset(
      projectId: projectId,
      name: name,
      relPath: rel,
    );
  }

  test('addTimelineClipFromAsset 新增素材层时避让同轨已有片段', () {
    final clipA = clipAsset('p/add_overlap_a.mp4', 'A');
    final clipB = clipAsset('p/add_overlap_b.mp4', 'B');
    final clipC = clipAsset('p/add_overlap_c.mp4', 'C');
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipA,
      lane: 1,
      startMs: 1000,
      durationMs: 600,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipB,
      lane: 1,
      startMs: 1200,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipC,
      lane: 2,
      startMs: 1200,
      durationMs: 500,
    );

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).startMs, 1000);
    final avoided = clips.singleWhere((c) => c.id == clipIdB);
    expect(avoided.lane, 1);
    expect(avoided.startMs, 1600);
    expect(avoided.durationMs, 500);
    final otherLane = clips.singleWhere((c) => c.id == clipIdC);
    expect(otherLane.lane, 2);
    expect(otherLane.startMs, 1200);
    expect(otherLane.durationMs, 500);
  });

  test('deleteTimelineClipRipple 删除素材层并将同轨后续片段前移', () {
    final clipA = clipAsset('p/ripple_a.mp4', 'A');
    final clipB = clipAsset('p/ripple_b.mp4', 'B');
    final clipC = clipAsset('p/ripple_c.mp4', 'C');
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipB,
      lane: 1,
      startMs: 1400,
      durationMs: 600,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipC,
      lane: 2,
      startMs: 1400,
      durationMs: 600,
    );

    engine.deleteTimelineClipRipple(clipIdA);

    final clips = engine.timelineClips(scriptId);
    expect(clips.map((c) => c.id), isNot(contains(clipIdA)));
    final shifted = clips.singleWhere((c) => c.id == clipIdB);
    expect(shifted.lane, 1);
    expect(shifted.startMs, 400);
    expect(shifted.durationMs, 600);
    final otherLane = clips.singleWhere((c) => c.id == clipIdC);
    expect(otherLane.lane, 2);
    expect(otherLane.startMs, 1400);
    expect(otherLane.durationMs, 600);
  });

  test('resizeTimelineClipEndRipple 波纹裁剪尾部并移动同轨后续片段', () {
    final clipA = clipAsset('p/ripple_trim_a.mp4', 'A');
    final clipB = clipAsset('p/ripple_trim_b.mp4', 'B');
    final clipC = clipAsset('p/ripple_trim_c.mp4', 'C');
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipB,
      lane: 1,
      startMs: 1400,
      durationMs: 600,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipC,
      lane: 2,
      startMs: 1400,
      durationMs: 600,
    );

    engine.resizeTimelineClipEndRipple(clipId: clipIdA, durationMs: 600);

    final clips = engine.timelineClips(scriptId);
    final trimmed = clips.singleWhere((c) => c.id == clipIdA);
    expect(trimmed.durationMs, 600);
    final shifted = clips.singleWhere((c) => c.id == clipIdB);
    expect(shifted.startMs, 1000);
    expect(shifted.durationMs, 600);
    final otherLane = clips.singleWhere((c) => c.id == clipIdC);
    expect(otherLane.startMs, 1400);
    expect(otherLane.durationMs, 600);
  });

  test('addTimelineClipFromAssetRipple 插入素材层并后移同轨后续片段', () {
    final clipA = clipAsset('p/ripple_insert_a.mp4', 'A');
    final clipB = clipAsset('p/ripple_insert_b.mp4', 'B');
    final clipC = clipAsset('p/ripple_insert_c.mp4', 'C');
    final clipInsert = clipAsset('p/ripple_insert_new.mp4', 'Insert');
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipA,
      lane: 1,
      startMs: 0,
      durationMs: 500,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipB,
      lane: 1,
      startMs: 1000,
      durationMs: 600,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipC,
      lane: 2,
      startMs: 1000,
      durationMs: 600,
    );

    final insertedId = engine.addTimelineClipFromAssetRipple(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipInsert,
      lane: 1,
      startMs: 700,
      durationMs: 400,
    );

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).startMs, 0);
    final inserted = clips.singleWhere((c) => c.id == insertedId);
    expect(inserted.startMs, 700);
    expect(inserted.durationMs, 400);
    final shifted = clips.singleWhere((c) => c.id == clipIdB);
    expect(shifted.startMs, 1400);
    expect(shifted.durationMs, 600);
    final otherLane = clips.singleWhere((c) => c.id == clipIdC);
    expect(otherLane.startMs, 1000);
    expect(otherLane.durationMs, 600);
  });

  test('addTimelineClipFromAssetAutoLane 在同一时间寻找空素材层', () {
    final clipA = clipAsset('p/auto_lane_a.mp4', 'A');
    final clipB = clipAsset('p/auto_lane_b.mp4', 'B');
    final clipInsert = clipAsset('p/auto_lane_insert.mp4', 'Insert');
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipB,
      lane: 2,
      startMs: 0,
      durationMs: 1000,
    );

    final insertedId = engine.addTimelineClipFromAssetAutoLane(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipInsert,
      lane: 1,
      startMs: 200,
      durationMs: 500,
    );

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).lane, 1);
    expect(clips.singleWhere((c) => c.id == clipIdB).lane, 2);
    final inserted = clips.singleWhere((c) => c.id == insertedId);
    expect(inserted.lane, 3);
    expect(inserted.startMs, 200);
    expect(inserted.durationMs, 500);
  });

  test('duplicateTimelineClip 复制素材层并避让同轨后续片段', () {
    final clipA = clipAsset('p/duplicate_a.mp4', 'A');
    final clipB = clipAsset('p/duplicate_b.mp4', 'B');
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipA,
      lane: 1,
      startMs: 500,
      durationMs: 600,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipB,
      lane: 1,
      startMs: 1200,
      durationMs: 400,
    );

    final duplicateId = engine.duplicateTimelineClip(clipIdA);

    final clips = engine.timelineClips(scriptId);
    final duplicate = clips.singleWhere((c) => c.id == duplicateId);
    expect(duplicate.assetId, clipA);
    expect(duplicate.name, 'A');
    expect(duplicate.filePath, 'p/duplicate_a.mp4');
    expect(duplicate.lane, 1);
    expect(duplicate.startMs, 1600);
    expect(duplicate.durationMs, 600);
    expect(clips.singleWhere((c) => c.id == clipIdB).startMs, 1200);
  });
}
