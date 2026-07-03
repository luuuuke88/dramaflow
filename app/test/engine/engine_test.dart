import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/util.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';

class StubGateway implements ProviderGateway {
  @override
  Future<TextResult> generateText(String system, String user,
          {required String stage, CancelToken? cancelToken}) async =>
      const TextResult('{}');
  @override
  Future<String> generateImage(String prompt, String projectId,
          {required String stage,
          CancelToken? cancelToken,
          String? refImageAbsPath,
          String? editInstruction}) async =>
      '$projectId/img_stub.png';
  @override
  Future<String> generateVideo(
          String prompt, String firstFrameAbsPath, String projectId,
          {required String stage, CancelToken? cancelToken}) async =>
      '$projectId/vid_stub.mp4';
}

void main() {
  late Engine e;
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('engine');
    final db = openEngineDb(':memory:');
    e = Engine(
        db: db,
        media: MediaStore(tmp.path),
        gateway: StubGateway(),
        config: EngineConfig(db, isMobile: false));
    // 不 start queue：门面测试只验证入队与守卫，不执行任务
  });
  tearDown(() {
    e.dispose();
    tmp.deleteSync(recursive: true);
  });

  group('projects/novel', () {
    test('CRUD 往返 + stats', () async {
      final p = await e.createProject('测试', artStyle: '国风');
      expect(p.stats.hasNovel, isFalse);
      await e.saveNovel(p.id, title: '书', content: '正文');
      final got = await e.getProject(p.id);
      expect(got.stats.hasNovel, isTrue);
      final renamed = await e.updateProject(p.id, name: '新名');
      expect(renamed.name, '新名');
      expect(renamed.artStyle, '国风');
      await e.deleteProject(p.id);
      expect(await e.listProjects(), isEmpty);
    });

    test('saveNovel 空内容抛错', () async {
      final p = await e.createProject('x');
      expect(
          () => e.saveNovel(p.id, title: '', content: '  '),
          throwsA(predicate(
              (x) => x is EngineException && x.message.contains('小说内容不能为空'))));
    });
  });

  group('generateScript 守卫', () {
    test('无小说抛错；入队后重复触发抛已在进行中', () async {
      final p = await e.createProject('x');
      expect(
          () => e.generateScript(p.id),
          throwsA(predicate(
              (x) => x is EngineException && x.message.contains('请先导入小说'))));
      await e.saveNovel(p.id, title: 't', content: 'c');
      final jobId = await e.generateScript(p.id, episodeCount: 2);
      expect(jobId, isNotEmpty);
      expect(
          () => e.generateScript(p.id),
          throwsA(predicate(
              (x) => x is EngineException && x.message.contains('已在进行中'))));
    });

    test('下游任务活跃时禁止重写剧本', () async {
      final p = await e.createProject('x');
      await e.saveNovel(p.id, title: 't', content: 'c');
      e.db.execute(
          "INSERT INTO jobs (id,projectId,kind,state,createdAt) VALUES ('jd','${p.id}','shot_image','queued','x')");
      expect(
          () => e.generateScript(p.id),
          throwsA(predicate((x) =>
              x is EngineException && x.message.contains('镜头图/视频任务进行中'))));
    });
  });

  group('assets/shots', () {
    late String pid;
    setUp(() async {
      pid = (await e.createProject('x')).id;
      e.db.execute(
          "INSERT INTO episodes (id,projectId,idx,title,scriptJson,createdAt) VALUES ('e1','$pid',1,'一','[]','x')");
      e.db.execute(
          "INSERT INTO assets (id,projectId,kind,name,imagePrompt,createdAt) VALUES ('a1','$pid','prop','玉','jade','x')");
      e.db.execute(
          "INSERT INTO shots (id,episodeId,projectId,idx,imagePrompt,createdAt) VALUES ('s1','e1','$pid',1,'shot1','x')");
    });

    test('generateAssetImage 置 queued 并入队；重复抛错', () async {
      final jobId = await e.generateAssetImage('a1');
      expect(jobId, isNotNull);
      final a = (await e.listAssets(pid)).single;
      expect(a.status, 'queued');
      expect(() => e.generateAssetImage('a1'), throwsA(isA<EngineException>()));
    });

    test('generateAll 跳过 done/queued/running', () async {
      e.db.execute(
          "INSERT INTO assets (id,projectId,kind,name,status,createdAt) VALUES ('a2','$pid','scene','门','done','x')");
      await e.generateAssetImage('a1'); // a1 → queued
      final ids = await e.generateAllAssetImages(pid);
      expect(ids, isEmpty); // a1 queued、a2 done → 无可入队
    });

    test('generateShotVideo 前置校验镜头图', () async {
      expect(
          () => e.generateShotVideo('s1'),
          throwsA(predicate(
              (x) => x is EngineException && x.message.contains('请先生成镜头图'))));
      e.db.execute(
          "UPDATE shots SET imageStatus='done', imagePath='p/i.png' WHERE id='s1'");
      final id = await e.generateShotVideo('s1');
      expect(id, isNotEmpty);
      final s = (await e.listShots('e1')).single;
      expect(s.videoStatus, 'queued');
    });

    test('generateStoryboard 本集下游活跃时抛错', () async {
      e.db.execute(
          "INSERT INTO jobs (id,projectId,kind,targetId,state,createdAt) VALUES ('jj','$pid','shot_image','s1','running','x')");
      expect(
          () => e.generateStoryboard('e1'),
          throwsA(predicate((x) =>
              x is EngineException && x.message.contains('镜头图/视频任务进行中'))));
    });
  });

  group('jobs/settings', () {
    test('retryJob 仅 failed，恢复实体 queued，attempt+1', () async {
      final pid = (await e.createProject('x')).id;
      e.db.execute(
          "INSERT INTO assets (id,projectId,kind,name,status,createdAt) VALUES ('a1','$pid','character','x','failed','x')");
      e.db.execute(
          "INSERT INTO jobs (id,projectId,kind,targetId,state,attempt,createdAt) VALUES ('jf','$pid','asset_image','a1','failed',1,'x')");
      final newId = await e.retryJob('jf');
      final nj = e.db
          .select('SELECT attempt, state FROM jobs WHERE id=?', [newId]).first;
      expect(nj['attempt'], 2);
      expect(nj['state'], 'queued');
      expect(
          e.db.select("SELECT status FROM assets").first['status'], 'queued');
      // done 任务不可重试
      e.db.execute(
          "INSERT INTO jobs (id,projectId,kind,state,createdAt) VALUES ('jd2','$pid','script_gen','done','x')");
      expect(() => e.retryJob('jd2'), throwsA(isA<EngineException>()));
    });

    test('settings 打码往返', () async {
      await e.updateSettings({'videoApiKey': 'vk-secret9999'});
      final s = await e.getSettings();
      expect(s.videoApiKey, '****9999');
      expect(s.textModel, 'gpt-5.5'); // 桌面默认
    });

    test('themeMode 读写且拒绝非法值', () async {
      expect(await e.getThemeMode(), 'light');
      await e.setThemeMode('system');
      expect(await e.getThemeMode(), 'system');
      await e.setThemeMode('dark');
      expect(await e.getThemeMode(), 'dark');
      expect(
          () => e.setThemeMode('sepia'),
          throwsA(predicate(
              (x) => x is EngineException && x.message.contains('主题模式无效'))));
    });

    test('app.locale 读写且拒绝非法值', () async {
      expect(await e.getAppLocale(), '');
      await e.setAppLocale('zh');
      expect(await e.getAppLocale(), 'zh');
      await e.setAppLocale('en');
      expect(await e.getAppLocale(), 'en');
      await e.setAppLocale('');
      expect(await e.getAppLocale(), '');
      expect(
          () => e.setAppLocale('fr'),
          throwsA(predicate(
              (x) => x is EngineException && x.message.contains('语言设置无效'))));
    });
  });
}
