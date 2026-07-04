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

  test('duplicateTimelineClipRipple 波纹复制素材层并后移同轨后续片段', () {
    final clipA = clipAsset('p/ripple_duplicate_a.mp4', 'A');
    final clipB = clipAsset('p/ripple_duplicate_b.mp4', 'B');
    final clipC = clipAsset('p/ripple_duplicate_c.mp4', 'C');
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
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipC,
      lane: 2,
      startMs: 1200,
      durationMs: 400,
    );

    final duplicateId = engine.duplicateTimelineClipRipple(clipIdA);

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).startMs, 500);
    final duplicate = clips.singleWhere((c) => c.id == duplicateId);
    expect(duplicate.assetId, clipA);
    expect(duplicate.name, 'A');
    expect(duplicate.filePath, 'p/ripple_duplicate_a.mp4');
    expect(duplicate.lane, 1);
    expect(duplicate.startMs, 1100);
    expect(duplicate.durationMs, 600);
    final shifted = clips.singleWhere((c) => c.id == clipIdB);
    expect(shifted.startMs, 1800);
    expect(shifted.durationMs, 400);
    final otherLane = clips.singleWhere((c) => c.id == clipIdC);
    expect(otherLane.startMs, 1200);
    expect(otherLane.durationMs, 400);
  });

  test('duplicateTimelineClips 批量复制选中素材层并保留相对时间', () {
    final clipA = clipAsset('p/batch_duplicate_a.mp4', 'A');
    final clipB = clipAsset('p/batch_duplicate_b.mp4', 'B');
    final clipC = clipAsset('p/batch_duplicate_c.mp4', 'C');
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipA,
      lane: 1,
      startMs: 200,
      durationMs: 500,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipB,
      lane: 2,
      startMs: 900,
      durationMs: 400,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipC,
      lane: 1,
      startMs: 1300,
      durationMs: 300,
    );

    final duplicateIds = engine.duplicateTimelineClips([clipIdA, clipIdB]);

    final clips = engine.timelineClips(scriptId);
    expect(duplicateIds, hasLength(2));
    final duplicateA = clips.singleWhere((c) => c.id == duplicateIds[0]);
    final duplicateB = clips.singleWhere((c) => c.id == duplicateIds[1]);
    expect(duplicateA.assetId, clipA);
    expect(duplicateA.lane, 1);
    expect(duplicateA.startMs, 1600);
    expect(duplicateA.durationMs, 500);
    expect(duplicateB.assetId, clipB);
    expect(duplicateB.lane, 2);
    expect(duplicateB.startMs, 2300);
    expect(duplicateB.durationMs, 400);
    expect(clips.singleWhere((c) => c.id == clipIdC).startMs, 1300);
  });

  test('moveTimelineClipRipple 波纹移动素材层并移动同轨后续片段', () {
    final clipA = clipAsset('p/ripple_move_a.mp4', 'A');
    final clipB = clipAsset('p/ripple_move_b.mp4', 'B');
    final clipC = clipAsset('p/ripple_move_c.mp4', 'C');
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
      startMs: 1400,
      durationMs: 400,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipC,
      lane: 2,
      startMs: 1400,
      durationMs: 400,
    );

    engine.moveTimelineClipRipple(clipId: clipIdA, startMs: 900);

    final clips = engine.timelineClips(scriptId);
    final moved = clips.singleWhere((c) => c.id == clipIdA);
    expect(moved.lane, 1);
    expect(moved.startMs, 900);
    expect(moved.durationMs, 600);
    final shifted = clips.singleWhere((c) => c.id == clipIdB);
    expect(shifted.startMs, 1800);
    expect(shifted.durationMs, 400);
    final otherLane = clips.singleWhere((c) => c.id == clipIdC);
    expect(otherLane.startMs, 1400);
    expect(otherLane.durationMs, 400);
  });

  test('splitTimelineClipsAt 批量按播放头切分命中的素材层', () {
    final clipA = clipAsset('p/batch_split_a.mp4', 'A');
    final clipB = clipAsset('p/batch_split_b.mp4', 'B');
    final clipC = clipAsset('p/batch_split_c.mp4', 'C');
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
      startMs: 200,
      durationMs: 1000,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipC,
      lane: 3,
      startMs: 1200,
      durationMs: 500,
    );

    final newIds = engine.splitTimelineClipsAt(
      clipIds: [clipIdA, clipIdB, clipIdC],
      playheadMs: 700,
    );

    expect(newIds, hasLength(2));
    final clips = engine.timelineClips(scriptId);
    final firstA = clips.singleWhere((c) => c.id == clipIdA);
    expect(firstA.startMs, 0);
    expect(firstA.durationMs, 700);
    final secondA = clips.singleWhere((c) => c.id == newIds[0]);
    expect(secondA.assetId, clipA);
    expect(secondA.lane, 1);
    expect(secondA.startMs, 700);
    expect(secondA.durationMs, 300);

    final firstB = clips.singleWhere((c) => c.id == clipIdB);
    expect(firstB.startMs, 200);
    expect(firstB.durationMs, 500);
    final secondB = clips.singleWhere((c) => c.id == newIds[1]);
    expect(secondB.assetId, clipB);
    expect(secondB.lane, 2);
    expect(secondB.startMs, 700);
    expect(secondB.durationMs, 500);

    final untouched = clips.singleWhere((c) => c.id == clipIdC);
    expect(untouched.startMs, 1200);
    expect(untouched.durationMs, 500);
  });

  test('deleteTimelineClips 批量删除选中的素材层且保留未选中片段', () {
    final clipA = clipAsset('p/batch_delete_a.mp4', 'A');
    final clipB = clipAsset('p/batch_delete_b.mp4', 'B');
    final clipC = clipAsset('p/batch_delete_c.mp4', 'C');
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
      lane: 2,
      startMs: 0,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipC,
      lane: 3,
      startMs: 0,
      durationMs: 500,
    );

    engine.deleteTimelineClips([clipIdA, clipIdC]);

    final clips = engine.timelineClips(scriptId);
    expect(clips.map((c) => c.id), isNot(contains(clipIdA)));
    expect(clips.map((c) => c.id), contains(clipIdB));
    expect(clips.map((c) => c.id), isNot(contains(clipIdC)));
    final survivor = clips.singleWhere((c) => c.id == clipIdB);
    expect(survivor.assetId, clipB);
    expect(survivor.lane, 2);
    expect(survivor.startMs, 0);
  });

  test('moveTimelineClips 批量移动选中素材层并保留相对时间', () {
    final clipA = clipAsset('p/batch_move_a.mp4', 'A');
    final clipB = clipAsset('p/batch_move_b.mp4', 'B');
    final clipC = clipAsset('p/batch_move_c.mp4', 'C');
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipA,
      lane: 1,
      startMs: 200,
      durationMs: 500,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipB,
      lane: 2,
      startMs: 900,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipC,
      lane: 3,
      startMs: 900,
      durationMs: 500,
    );

    engine.moveTimelineClips(
      clipIds: [clipIdA, clipIdB],
      deltaStartMs: 300,
    );

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).startMs, 500);
    expect(clips.singleWhere((c) => c.id == clipIdB).startMs, 1200);
    expect(clips.singleWhere((c) => c.id == clipIdC).startMs, 900);
  });
}
