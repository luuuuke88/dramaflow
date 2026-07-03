import 'dart:io';

import 'package:dramaflow/src/engine/compose.dart';
import 'package:dramaflow/src/engine/compose_episode.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/video_track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 回归测试：Engine 构造函数曾接受 composer 参数但从未存成字段（T3 重写遗留 bug，
/// 2026-07-03 修复）。此处锁定 engine.composer 确实是传入的实例。
class _FakeComposer implements VideoComposer {
  final List<List<String>> concatCalls = [];
  double? probedDuration = 4.0;

  @override
  Future<void> concat(List<String> segmentAbsPaths, String outputAbsPath) async {
    concatCalls.add(segmentAbsPaths);
    File(outputAbsPath).writeAsBytesSync([0]);
  }

  @override
  Future<double?> probeDurationSec(String inputAbsPath) async => probedDuration;
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late _FakeComposer composer;
  late int projectId;
  late int scriptId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-compose-');
    db = openEngineDb(':memory:');
    composer = _FakeComposer();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
      composer: composer,
    );
    projectId = engine.addProject(projectType: 'novel', name: '合成测试');
    scriptId = engine.addScript(projectId: projectId, name: '一', content: 'x');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('回归：Engine.composer 字段确实持有构造时传入的合成器（曾被静默丢弃）', () {
    expect(identical(engine.composer, composer), isTrue);
  });

  test('未传 composer 时默认回落 UnsupportedComposer（不为 null）', () {
    final other = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media2')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    expect(other.composer, isA<UnsupportedComposer>());
  });

  test('orderedSelectedVideoPaths 按分镜序号返回选中视频（未选中为 null）', () {
    final sb1 = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final sb2 = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final track1 = engine.ensureTrackForStoryboard(sb1);
    db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [track1, 'p/vid_1.mp4', vtDone]);
    final videoId = db.lastInsertRowId;
    engine.selectVideo(track1, videoId);
    engine.ensureTrackForStoryboard(sb2); // 未生成任何候选

    final paths = engine.orderedSelectedVideoPaths(scriptId);
    expect(paths, ['p/vid_1.mp4', null]);
  });

  test('composeEpisode：全部已选时拼接成功并返回时长', () async {
    final sb1 = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final track1 = engine.ensureTrackForStoryboard(sb1);
    db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [track1, 'p/vid_1.mp4', vtDone]);
    engine.selectVideo(track1, db.lastInsertRowId);

    final result = await engine.composeEpisode(projectId, scriptId);
    expect(result.segmentCount, 1);
    expect(result.durationSec, 4.0);
    expect(composer.concatCalls.single.single, contains('vid_1.mp4'));
    expect(File(engine.mediaAbsPath(result.outputRelPath)).existsSync(), isTrue);
  });

  test('composeEpisode：存在未选中分镜时抛 errPromptMissing 且不拼接', () async {
    engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    expect(
      () => engine.composeEpisode(projectId, scriptId),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errPromptMissing)),
    );
    expect(composer.concatCalls, isEmpty);
  });

  test('composeEpisode：无任何分镜时抛 errNoChapters', () async {
    final emptyScriptId =
        engine.addScript(projectId: projectId, name: '空', content: 'x');
    expect(
      () => engine.composeEpisode(projectId, emptyScriptId),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errNoChapters)),
    );
  });
}
