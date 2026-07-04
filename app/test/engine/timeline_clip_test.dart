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
}
