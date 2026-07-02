import 'dart:io';
// ignore_for_file: depend_on_referenced_packages

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'package:dramaflow/src/engine/compose.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/pipeline/runners.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/util.dart';

class StubGateway implements ProviderGateway {
  final List<String> videos;
  int videoCalls = 0;

  StubGateway({this.videos = const ['p1/vid_fake.mp4']});

  @override
  Future<TextResult> generateText(String system, String user,
          {required String stage, CancelToken? cancelToken}) async =>
      const TextResult('{}');

  @override
  Future<String> generateImage(String prompt, String projectId,
          {required String stage, CancelToken? cancelToken}) async =>
      '$projectId/img_fake.png';

  @override
  Future<String> generateVideo(
    String prompt,
    String firstFrameAbsPath,
    String projectId, {
    required String stage,
    CancelToken? cancelToken,
  }) async {
    final index = videoCalls.clamp(0, videos.length - 1);
    videoCalls++;
    return videos[index];
  }
}

class FakeComposer implements VideoComposer {
  final List<String> probed = [];
  final List<({List<String> segments, String output})> concatCalls = [];
  final Map<String, double?> durations;
  String? concatFailure;

  FakeComposer({
    this.durations = const {},
    this.concatFailure,
  });

  @override
  Future<double?> probeDurationSec(String inputPath) async {
    probed.add(inputPath);
    return durations[inputPath] ?? 4.2;
  }

  @override
  Future<void> concat(
      List<String> segmentAbsPaths, String outputAbsPath) async {
    concatCalls.add(
        (segments: List<String>.from(segmentAbsPaths), output: outputAbsPath));
    final failure = concatFailure;
    if (failure != null) {
      throw EngineException(failure);
    }
  }
}

void main() {
  late Database db;
  late Directory tmp;
  late MediaStore media;
  late Engine engine;

  void seedEpisode({int shotCount = 2}) {
    db.execute(
        "INSERT INTO projects (id,name,createdAt,updatedAt) VALUES ('p1','测试','x','x')");
    db.execute(
        "INSERT INTO episodes (id,projectId,idx,title,createdAt) VALUES ('e1','p1',1,'第一集','x')");
    for (var i = 1; i <= shotCount; i++) {
      db.execute(
          "INSERT INTO shots (id,episodeId,projectId,idx,imageStatus,imagePath,videoPrompt,createdAt) VALUES ('s$i','e1','p1',$i,'done','p1/img_$i.png','动起来','x')");
    }
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('engine_m3');
    db = openEngineDb(':memory:');
    media = MediaStore(tmp.path);
    final composer = FakeComposer();
    engine = Engine(
      db: db,
      media: media,
      gateway: StubGateway(),
      config: EngineConfig(db, isMobile: false),
      composer: composer,
    );
  });

  tearDown(() {
    engine.dispose();
    tmp.deleteSync(recursive: true);
  });

  group('video takes', () {
    test('shot_video 成功后新增 take 并自动选中，同步 shots.videoPath', () async {
      seedEpisode(shotCount: 1);
      final fake = FakeComposer();
      final runners = Runners(
        db,
        StubGateway(videos: const ['p1/vid_take_1.mp4']),
        media,
        composer: fake,
      );

      await runners.run(
          const JobRow('j1', 'p1', 'shot_video', 's1', '{}'), CancelToken());

      final takes = await engine.listTakes('s1');
      expect(takes, hasLength(1));
      expect(takes.single.videoPath, 'p1/vid_take_1.mp4');
      expect(takes.single.durationSec, 4.2);
      final shot = db.select(
          'SELECT selectedTakeId, videoPath, videoStatus FROM shots WHERE id=?',
          ['s1']).first;
      expect(shot['selectedTakeId'], takes.single.id);
      expect(shot['videoPath'], takes.single.videoPath);
      expect(shot['videoStatus'], 'done');
    });

    test('selectTake 切换选中版本并同步 videoPath', () async {
      seedEpisode(shotCount: 1);
      db.execute(
          "INSERT INTO video_takes (id,shotId,videoPath,durationSec,createdAt) VALUES ('t1','s1','p1/a.mp4',1.5,'2026-01-01T00:00:00Z')");
      db.execute(
          "INSERT INTO video_takes (id,shotId,videoPath,durationSec,createdAt) VALUES ('t2','s1','p1/b.mp4',2.5,'2026-01-02T00:00:00Z')");

      await engine.selectTake('s1', 't1');

      final shot = db.select(
          'SELECT selectedTakeId, videoPath, videoStatus FROM shots WHERE id=?',
          ['s1']).first;
      expect(shot['selectedTakeId'], 't1');
      expect(shot['videoPath'], 'p1/a.mp4');
      expect(shot['videoStatus'], 'done');
    });

    test('deleteTake 删除选中版本时回退最新版本，无剩余则回到 none', () async {
      seedEpisode(shotCount: 1);
      db.execute(
          "INSERT INTO video_takes (id,shotId,videoPath,durationSec,createdAt) VALUES ('old','s1','p1/old.mp4',1.0,'2026-01-01T00:00:00Z')");
      db.execute(
          "INSERT INTO video_takes (id,shotId,videoPath,durationSec,createdAt) VALUES ('new','s1','p1/new.mp4',2.0,'2026-01-02T00:00:00Z')");
      await engine.selectTake('s1', 'new');

      await engine.deleteTake('new');
      var shot = db.select(
          'SELECT selectedTakeId, videoPath, videoStatus FROM shots WHERE id=?',
          ['s1']).first;
      expect(shot['selectedTakeId'], 'old');
      expect(shot['videoPath'], 'p1/old.mp4');
      expect(shot['videoStatus'], 'done');

      await engine.deleteTake('old');
      shot = db.select(
          'SELECT selectedTakeId, videoPath, videoStatus FROM shots WHERE id=?',
          ['s1']).first;
      expect(shot['selectedTakeId'], isNull);
      expect(shot['videoPath'], isNull);
      expect(shot['videoStatus'], 'none');
    });
  });

  group('compose', () {
    test('composeEpisode 前置校验列出缺少选中 take 的镜头号', () async {
      seedEpisode(shotCount: 3);
      db.execute(
          "INSERT INTO video_takes (id,shotId,videoPath,durationSec,createdAt) VALUES ('t1','s1','p1/1.mp4',1,'x')");
      db.execute(
          "INSERT INTO video_takes (id,shotId,videoPath,durationSec,createdAt) VALUES ('t3','s3','p1/3.mp4',1,'x')");
      await engine.selectTake('s1', 't1');
      await engine.selectTake('s3', 't3');

      expect(
        () => engine.composeEpisode('e1'),
        throwsA(predicate(
            (e) => e is EngineException && e.message.contains('第 2 镜缺少视频'))),
      );
    });

    test('compose job 编排转码与 concat 命令并写入 done 状态', () async {
      seedEpisode();
      final fake = FakeComposer(durations: {
        media.absPath('p1/1.mp4'): 1.2,
        media.absPath('p1/2.mp4'): 2.3,
      });
      final compose = ComposeService(db: db, media: media, composer: fake);
      await compose.addTake(shotId: 's1', videoPath: 'p1/1.mp4');
      await compose.addTake(shotId: 's2', videoPath: 'p1/2.mp4');

      final runners = Runners(
        db,
        StubGateway(),
        media,
        composer: fake,
      );
      final result = await runners.run(
          const JobRow('j1', 'p1', 'compose', 'e1', '{}'), CancelToken());

      expect(result, startsWith('p1/ep_e1_'));
      expect(fake.concatCalls, hasLength(1));
      expect(fake.concatCalls.single.segments, [
        media.absPath('p1/1.mp4'),
        media.absPath('p1/2.mp4'),
      ]);
      expect(fake.concatCalls.single.output, media.absPath(result));
      final episode = db.select(
          'SELECT composedPath, composeStatus, composeError FROM episodes WHERE id=?',
          ['e1']).first;
      expect(episode['composeStatus'], 'done');
      expect(episode['composeError'], isNull);
      expect(episode['composedPath'], result);
    });

    test('compose job 失败时落 failed 并保留 stderr 尾部', () async {
      seedEpisode();
      final longStderr = '${List.filled(520, 'x').join()}最后的错误';
      final fake = FakeComposer(concatFailure: longStderr);
      final compose = ComposeService(db: db, media: media, composer: fake);
      await compose.addTake(shotId: 's1', videoPath: 'p1/1.mp4');
      await compose.addTake(shotId: 's2', videoPath: 'p1/2.mp4');
      final runners = Runners(
        db,
        StubGateway(),
        media,
        composer: fake,
      );

      await expectLater(
        runners.run(
            const JobRow('j1', 'p1', 'compose', 'e1', '{}'), CancelToken()),
        throwsA(isA<EngineException>()),
      );

      final episode = db.select(
          'SELECT composeStatus, composeError FROM episodes WHERE id=?',
          ['e1']).first;
      expect(episode['composeStatus'], 'failed');
      expect(episode['composeError'], contains('最后的错误'));
      expect((episode['composeError'] as String).length, lessThan(650));
    });
  });

  test('boot 时将旧 shots.videoPath 迁为首条 take 且幂等', () async {
    final dataDir = Directory.systemTemp.createTempSync('engine_m3_boot');
    try {
      final path = '${dataDir.path}/dramaflow.sqlite';
      final bootDb = openEngineDb(path);
      bootDb.execute(
          "INSERT INTO projects (id,name,createdAt,updatedAt) VALUES ('p1','测试','x','x')");
      bootDb.execute(
          "INSERT INTO episodes (id,projectId,idx,title,createdAt) VALUES ('e1','p1',1,'第一集','x')");
      bootDb.execute(
          "INSERT INTO shots (id,episodeId,projectId,idx,videoPath,videoStatus,createdAt) VALUES ('s1','e1','p1',1,'p1/legacy.mp4','done','x')");
      bootDb.close();

      final first = await Engine.boot(dataDir: dataDir.path, isMobile: false);
      first.dispose();
      final second = await Engine.boot(dataDir: dataDir.path, isMobile: false);
      final count = second.db.select(
          'SELECT COUNT(*) n FROM video_takes WHERE shotId=?',
          ['s1']).first['n'];
      final shot = second.db.select(
          'SELECT selectedTakeId, videoPath, videoStatus FROM shots WHERE id=?',
          ['s1']).first;

      expect(count, 1);
      expect(shot['selectedTakeId'], isNotNull);
      expect(shot['videoPath'], 'p1/legacy.mp4');
      expect(shot['videoStatus'], 'done');
      second.dispose();
    } finally {
      dataDir.deleteSync(recursive: true);
    }
  });
}
