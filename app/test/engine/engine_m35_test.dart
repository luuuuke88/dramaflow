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
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/util.dart';

Future<void> waitForM35(bool Function() cond,
    {String reason = '', Duration timeout = const Duration(seconds: 8)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('waitFor 超时${reason.isEmpty ? '' : '：$reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

class M35Gateway implements ProviderGateway {
  bool failNextShotImage = false;
  final stageCalls = <String, int>{};

  int _count(String stage) {
    final next = (stageCalls[stage] ?? 0) + 1;
    stageCalls[stage] = next;
    return next;
  }

  @override
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken}) async {
    _count(stage);
    return switch (stage) {
      'script_gen' => const TextResult('''
{
  "episodes": [
    {
      "title": "第一集",
      "synopsis": "主角相遇",
      "scenes": [
        {
          "location": "街口",
          "timeOfDay": "白天",
          "action": "主角发现线索",
          "dialogues": []
        }
      ]
    },
    {
      "title": "第二集",
      "synopsis": "追查真相",
      "scenes": [
        {
          "location": "仓库",
          "timeOfDay": "夜晚",
          "action": "主角进入仓库",
          "dialogues": []
        }
      ]
    }
  ]
}
'''),
      'asset_extract' => const TextResult('''
{
  "assets": [
    {
      "kind": "character",
      "name": "林澈",
      "description": "年轻侦探",
      "imagePrompt": "年轻侦探，蓝色外套"
    }
  ]
}
'''),
      'storyboard_gen' => const TextResult('''
{
  "shots": [
    {
      "description": "主角推门进入",
      "camera": "中景",
      "dialogue": "",
      "assetNames": ["林澈"],
      "imagePrompt": "主角推门进入，电影感",
      "videoPrompt": "镜头缓慢推进"
    }
  ]
}
'''),
      _ => throw EngineException('未知文本环节：$stage'),
    };
  }

  @override
  Future<String> generateImage(String prompt, String projectId,
      {required String stage, CancelToken? cancelToken}) async {
    final n = _count(stage);
    if (stage == 'shot_image' && failNextShotImage) {
      failNextShotImage = false;
      throw EngineException('图片服务断开');
    }
    return '$projectId/${stage}_$n.png';
  }

  @override
  Future<String> generateVideo(
      String prompt, String firstFrameAbsPath, String projectId,
      {required String stage, CancelToken? cancelToken}) async {
    final n = _count(stage);
    return '$projectId/video_$n.mp4';
  }
}

class M35FfmpegRunner implements FfmpegRunner {
  @override
  Future<MediaProbe> probe(String inputPath) async =>
      const MediaProbe(durationSec: 1.5, hasAudio: false);

  @override
  Future<FfmpegRunResult> run(List<String> args) async =>
      const FfmpegRunResult(success: true);
}

void main() {
  late Database db;
  late Directory tmp;
  late M35Gateway gateway;
  late Engine engine;

  Future<String> createProjectWithNovel() async {
    final project = await engine.createProject('自动连跑测试', artStyle: '电影感');
    await engine.saveNovel(project.id, title: '测试小说', content: '主角追查真相。');
    return project.id;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('engine_m35');
    db = openEngineDb(':memory:');
    gateway = M35Gateway();
    engine = Engine(
      db: db,
      media: MediaStore(tmp.path),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
      ffmpegRunner: M35FfmpegRunner(),
      queueTick: const Duration(milliseconds: 5),
    );
  });

  tearDown(() {
    engine.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('startAuto 从空项目自动推进到全部合成完成并关闭自动模式', () async {
    final projectId = await createProjectWithNovel();

    engine.queue.start();
    await engine.startAuto(projectId);

    await waitForM35(
      () {
        final state = engine.directorState(projectId);
        return state.mode == 'off' && state.finished;
      },
      reason: '等待自动连跑完成',
    );

    final state = engine.directorState(projectId);
    expect(state.pausedReason, isEmpty);
    expect(db.select("SELECT COUNT(*) n FROM episodes").first['n'], 2);
    expect(
        db
            .select(
                "SELECT COUNT(*) n FROM episodes WHERE composeStatus='done' AND composedPath IS NOT NULL")
            .first['n'],
        2);
    expect(db.select("SELECT COUNT(*) n FROM shots").first['n'], 2);
    expect(
        db
            .select(
                "SELECT COUNT(*) n FROM shots WHERE imageStatus='done' AND videoStatus='done'")
            .first['n'],
        2);
    expect(db.select("SELECT COUNT(*) n FROM video_takes").first['n'], 2);
  });

  test('任一 job failed 时暂停自动模式，重新 startAuto 可从当前状态续跑', () async {
    final projectId = await createProjectWithNovel();
    gateway.failNextShotImage = true;

    engine.queue.start();
    await engine.startAuto(projectId);

    await waitForM35(
      () => engine.directorState(projectId).pausedReason.isNotEmpty,
      reason: '等待失败暂停',
    );

    final paused = engine.directorState(projectId);
    expect(paused.mode, 'auto');
    expect(paused.pausedReason, contains('镜头图失败：图片服务断开'));
    expect(
        db
            .select("SELECT COUNT(*) n FROM jobs WHERE state='failed'")
            .first['n'],
        1);

    await engine.startAuto(projectId);

    await waitForM35(
      () {
        final state = engine.directorState(projectId);
        return state.mode == 'off' && state.finished;
      },
      reason: '等待失败后续跑完成',
    );

    final finished = engine.directorState(projectId);
    expect(finished.pausedReason, isEmpty);
    expect(
        db
            .select(
                "SELECT COUNT(*) n FROM episodes WHERE composeStatus='done'")
            .first['n'],
        2);
  });

  test('startAuto 立即评估但不会对同一目标重复入队', () async {
    final projectId = await createProjectWithNovel();

    await engine.startAuto(projectId);
    await engine.startAuto(projectId);

    expect(engine.directorState(projectId).mode, 'auto');
    expect(
        db.select(
            "SELECT COUNT(*) n FROM jobs WHERE kind='script_gen' AND targetId=? AND state IN ('queued','running')",
            [projectId]).first['n'],
        1);
  });

  test('自动补跑 failed 素材图最多一次，避免失败资产死循环', () async {
    final projectId = (await engine.createProject('已有失败资产')).id;
    db.execute(
        "INSERT INTO episodes (id,projectId,idx,title,scriptJson,createdAt) VALUES ('e1',?,1,'第一集','[]','x')",
        [projectId]);
    db.execute(
        "INSERT INTO assets (id,projectId,kind,name,imagePrompt,status,error,createdAt) VALUES ('a1',?,'character','林澈','人物图','failed','旧失败','x')",
        [projectId]);
    db.execute(
        "INSERT INTO jobs (id,projectId,kind,targetId,targetLabel,state,attempt,error,createdAt) VALUES ('old',?,'asset_image','a1','素材图·林澈','failed',1,'旧失败','x')",
        [projectId]);

    await engine.startAuto(projectId);

    final retry = db
        .select(
            "SELECT attempt,state FROM jobs WHERE kind='asset_image' AND targetId='a1' ORDER BY rowid DESC LIMIT 1")
        .first;
    expect(retry['attempt'], 2);
    expect(retry['state'], 'queued');

    db.execute(
        "UPDATE jobs SET state='failed', error='再次失败' WHERE id != 'old'");
    db.execute("UPDATE assets SET status='failed', error='再次失败' WHERE id='a1'");

    await engine.startAuto(projectId);

    expect(
        engine.directorState(projectId).pausedReason, contains('素材图失败：再次失败'));
    expect(
        db
            .select("SELECT COUNT(*) n FROM jobs WHERE kind='asset_image'")
            .first['n'],
        2);
  });
}
