import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/util.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/pipeline/runners.dart';

/// 可编程 fake：text 按调用序返回脚本；image/video 返回固定 rel 或抛错。
class FakeGateway implements ProviderGateway {
  final List<String> textResponses;
  final List<String> textUsers = [];
  int textCalls = 0;
  Object? imageError;
  FakeGateway({this.textResponses = const []});

  @override
  Future<TextResult> generateText(String system, String user,
      {CancelToken? cancelToken}) async {
    textUsers.add(user);
    final r = textResponses[textCalls.clamp(0, textResponses.length - 1)];
    textCalls++;
    return TextResult(r);
  }

  @override
  Future<String> generateImage(String prompt, String projectId,
      {CancelToken? cancelToken}) async {
    if (imageError != null) throw imageError!;
    return '$projectId/img_fake.png';
  }

  @override
  Future<String> generateVideo(
          String prompt, String firstFrameAbsPath, String projectId,
          {CancelToken? cancelToken}) async =>
      '$projectId/vid_fake.mp4';
}

void main() {
  late Database db;
  late Directory tmp;
  late MediaStore media;
  final token = CancelToken();

  setUp(() {
    db = openEngineDb(':memory:');
    tmp = Directory.systemTemp.createTempSync('runners');
    media = MediaStore(tmp.path);
    db.execute(
        "INSERT INTO projects (id,name,artStyle,createdAt,updatedAt) VALUES ('p1','测试','国风','x','x')");
  });
  tearDown(() {
    db.dispose();
    tmp.deleteSync(recursive: true);
  });

  const goodScript =
      '{"episodes":[{"title":"雪夜","synopsis":"s","scenes":[{"location":"山门","action":"守夜","dialogues":[]}]},'
      '{"title":"旧账","scenes":[{"location":"大殿","action":"对峙"}]},'
      '{"title":"归来","scenes":[{"location":"密室","action":"收账"}]}]}';

  test('scriptGen 正常：3 集入库 idx 1..3', () async {
    db.execute(
        "INSERT INTO novels (id,projectId,title,content,updatedAt) VALUES ('n1','p1','书','正文','x')");
    final r = Runners(db, FakeGateway(textResponses: [goodScript]), media);
    final msg = await r.run(
        const JobRow('j1', 'p1', 'script_gen', 'p1', '{}'), token);
    expect(msg, contains('3 集'));
    final rows = db.select('SELECT idx,title FROM episodes ORDER BY idx');
    expect(rows.length, 3);
    expect(rows.first['title'], '雪夜');
  });

  test('scriptGen 无小说 → 请先导入小说', () async {
    final r = Runners(db, FakeGateway(textResponses: [goodScript]), media);
    expect(
        () =>
            r.run(const JobRow('j', 'p1', 'script_gen', 'p1', '{}'), token),
        throwsA(predicate(
            (e) => e is EngineException && e.message.contains('请先导入小说'))));
  });

  test('structuredText 自愈：坏 JSON 后重试成功且带反馈', () async {
    db.execute(
        "INSERT INTO novels (id,projectId,title,content,updatedAt) VALUES ('n1','p1','书','正文','x')");
    final gw = FakeGateway(textResponses: ['这不是json', goodScript]);
    await Runners(db, gw, media)
        .run(const JobRow('j', 'p1', 'script_gen', 'p1', '{}'), token);
    expect(gw.textCalls, 2);
    expect(gw.textUsers[1], contains('你上一次的输出无法解析'));
  });

  test('assetImage 空提示词：实体落 failed（卡 queued 回归防护）', () async {
    db.execute(
        "INSERT INTO assets (id,projectId,kind,name,status,createdAt) VALUES ('a1','p1','character','某人','queued','x')");
    final r = Runners(db, FakeGateway(), media);
    await expectLater(
        r.run(const JobRow('j', 'p1', 'asset_image', 'a1', '{}'), token),
        throwsA(isA<EngineException>()));
    final row = db.select('SELECT status,error FROM assets').first;
    expect(row['status'], 'failed');
    expect(row['error'], contains('没有图片提示词'));
  });

  test('assetImage 成功：done + imagePath', () async {
    db.execute(
        "INSERT INTO assets (id,projectId,kind,name,imagePrompt,status,createdAt) VALUES ('a1','p1','character','某人','a hero','queued','x')");
    await Runners(db, FakeGateway(), media)
        .run(const JobRow('j', 'p1', 'asset_image', 'a1', '{}'), token);
    final row = db.select('SELECT status,imagePath FROM assets').first;
    expect(row['status'], 'done');
    expect(row['imagePath'], 'p1/img_fake.png');
  });

  test('shotVideo 缺首帧：videoStatus failed 带原因', () async {
    db.execute(
        "INSERT INTO episodes (id,projectId,idx,createdAt) VALUES ('e1','p1',1,'x')");
    db.execute(
        "INSERT INTO shots (id,episodeId,projectId,idx,videoPrompt,createdAt) VALUES ('s1','e1','p1',1,'动','x')");
    await expectLater(
        Runners(db, FakeGateway(), media)
            .run(const JobRow('j', 'p1', 'shot_video', 's1', '{}'), token),
        throwsA(isA<EngineException>()));
    final row = db.select('SELECT videoStatus,videoError FROM shots').first;
    expect(row['videoStatus'], 'failed');
    expect(row['videoError'], contains('请先生成镜头图'));
  });

  test('assetExtract upsert：同名更新不重复', () async {
    db.execute(
        "INSERT INTO episodes (id,projectId,idx,title,scriptJson,createdAt) VALUES ('e1','p1',1,'第一集','[]','x')");
    db.execute(
        "INSERT INTO assets (id,projectId,kind,name,createdAt) VALUES ('old','p1','character','陈默','x')");
    const out =
        '{"assets":[{"kind":"character","name":"陈默","description":"新设定","imagePrompt":"x"},'
        '{"kind":"prop","name":"霜纹玉","description":"信物","imagePrompt":"jade"}]}';
    final msg = await Runners(db, FakeGateway(textResponses: [out]), media)
        .run(const JobRow('j', 'p1', 'asset_extract', 'p1', '{}'), token);
    expect(msg, contains('新增 1 个'));
    expect(msg, contains('更新 1 个'));
    expect(db.select('SELECT COUNT(*) n FROM assets').first['n'], 2);
    expect(
        db.select("SELECT description FROM assets WHERE name='陈默'")
            .first['description'],
        '新设定');
  });

  test('storyboardGen：分镜入库且道具进上下文', () async {
    db.execute(
        "INSERT INTO episodes (id,projectId,idx,title,scriptJson,createdAt) VALUES ('e1','p1',1,'雪夜','[]','x')");
    db.execute(
        "INSERT INTO assets (id,projectId,kind,name,description,createdAt) VALUES ('a1','p1','prop','霜纹玉','焦黑信物','x')");
    const out =
        '{"shots":[{"description":"开场","camera":"远景","dialogue":"","assetNames":["霜纹玉"],"imagePrompt":"snow gate","videoPrompt":"推近"}]}';
    final gw = FakeGateway(textResponses: [out]);
    final msg = await Runners(db, gw, media)
        .run(const JobRow('j', 'p1', 'storyboard_gen', 'e1', '{}'), token);
    expect(msg, contains('1 个镜头'));
    expect(gw.textUsers.single, contains('[道具] 霜纹玉'));
    final shot = db.select('SELECT * FROM shots').first;
    expect(jsonDecode(shot['assetNames'] as String), ['霜纹玉']);
  });
}
