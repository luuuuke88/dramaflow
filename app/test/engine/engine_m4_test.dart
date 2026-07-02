import 'dart:convert';
import 'dart:io';
// ignore_for_file: depend_on_referenced_packages

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/pipeline/runners.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/util.dart';

class M4Gateway implements ProviderGateway {
  var imageCalls = 0;
  final imagePrompts = <String>[];
  final imageStages = <String>[];
  String? lastRefImageAbsPath;
  String? lastEditInstruction;

  @override
  Future<TextResult> generateText(String system, String user,
          {required String stage, CancelToken? cancelToken}) async =>
      const TextResult('{}');

  @override
  Future<String> generateImage(
    String prompt,
    String projectId, {
    required String stage,
    CancelToken? cancelToken,
    String? refImageAbsPath,
    String? editInstruction,
  }) async {
    imageCalls++;
    imagePrompts.add(prompt);
    imageStages.add(stage);
    lastRefImageAbsPath = refImageAbsPath;
    lastEditInstruction = editInstruction;
    return '$projectId/img_$imageCalls.png';
  }

  @override
  Future<String> generateVideo(
          String prompt, String firstFrameAbsPath, String projectId,
          {required String stage, CancelToken? cancelToken}) async =>
      '$projectId/vid_stub.mp4';
}

void main() {
  late Database db;
  late Directory tmp;
  late MediaStore media;
  late String pid;
  final token = CancelToken();

  setUp(() {
    db = openEngineDb(':memory:');
    tmp = Directory.systemTemp.createTempSync('engine_m4');
    media = MediaStore(tmp.path);
    pid = 'p1';
    db.execute(
        "INSERT INTO projects (id,name,artStyle,createdAt,updatedAt) VALUES (?,?,?,?,?)",
        [pid, '项目', '国风', 'x', 'x']);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Engine makeEngine([ProviderGateway? gateway]) => Engine(
        db: db,
        media: media,
        gateway: gateway ?? M4Gateway(),
        config: EngineConfig(db, isMobile: false),
      );

  void insertAsset({
    String id = 'a1',
    String imagePrompt = '青衣少女',
    String? imagePath,
    String status = 'queued',
  }) {
    db.execute(
        "INSERT INTO assets (id,projectId,kind,name,description,imagePrompt,imagePath,status,createdAt) VALUES (?,?,?,?,?,?,?,?,?)",
        [
          id,
          pid,
          'character',
          '阿青',
          '女主',
          imagePrompt,
          imagePath,
          status,
          'x'
        ]);
  }

  void insertShot({
    String id = 's1',
    String imagePrompt = '雪夜近景',
    String? imagePath,
    String imageStatus = 'queued',
  }) {
    db.execute(
        "INSERT INTO episodes (id,projectId,idx,title,scriptJson,createdAt) VALUES ('e1',?,1,'第一集','[]','x')",
        [pid]);
    db.execute(
        "INSERT INTO shots (id,episodeId,projectId,idx,description,imagePrompt,imagePath,imageStatus,createdAt) VALUES (?,?,?,?,?,?,?,?,?)",
        [id, 'e1', pid, 1, '开场', imagePrompt, imagePath, imageStatus, 'x']);
  }

  test('asset_image 和 shot_image 完成后写入图片版本并选中新版本', () async {
    insertAsset();
    insertShot();
    final gateway = M4Gateway();
    final runners = Runners(db, gateway, media);

    await runners.run(
        const JobRow('j1', 'p1', 'asset_image', 'a1', '{}'), token);
    await runners.run(
        const JobRow('j2', 'p1', 'asset_image', 'a1', '{}'), token);
    await runners.run(
        const JobRow('j3', 'p1', 'shot_image', 's1', '{}'), token);

    final asset = db
        .select('SELECT status,imagePath FROM assets WHERE id=?', ['a1']).first;
    expect(asset['status'], 'done');
    expect(asset['imagePath'], 'p1/img_2.png');

    final assetTakes = db.select(
        'SELECT imagePath,selected FROM image_takes WHERE assetId=? ORDER BY createdAt ASC, id ASC',
        ['a1']);
    expect(assetTakes.map((r) => r['imagePath']).toList(),
        ['p1/img_1.png', 'p1/img_2.png']);
    expect(assetTakes.map((r) => r['selected']).toList(), [0, 1]);

    final shot = db.select(
        'SELECT imageStatus,imagePath FROM shots WHERE id=?', ['s1']).first;
    expect(shot['imageStatus'], 'done');
    expect(shot['imagePath'], 'p1/img_3.png');
    expect(
        db.select('SELECT imagePath,selected FROM image_takes WHERE shotId=?',
            ['s1']).single['selected'],
        1);
  });

  test('selectImageTake 切换选中版本并同步冗余 imagePath', () async {
    insertAsset(imagePath: 'p1/new.png', status: 'done');
    db.execute(
        "INSERT INTO image_takes (id,assetId,imagePath,selected,createdAt) VALUES ('old','a1','p1/old.png',0,'1')");
    db.execute(
        "INSERT INTO image_takes (id,assetId,imagePath,selected,createdAt) VALUES ('new','a1','p1/new.png',1,'2')");
    final engine = makeEngine();
    addTearDown(engine.queue.dispose);

    await engine.selectImageTake('old');

    final asset = db.select(
        'SELECT imagePath,status,error FROM assets WHERE id=?', ['a1']).first;
    expect(asset['imagePath'], 'p1/old.png');
    expect(asset['status'], 'done');
    expect(asset['error'], isNull);
    final takes = await engine.listImageTakes(assetId: 'a1');
    expect(takes.map((take) => '${take.id}:${take.selected}').toList(),
        ['new:false', 'old:true']);
  });

  test('启动迁移为已有 imagePath 补首条 take 且幂等', () {
    insertAsset(imagePath: 'p1/a.png', status: 'done');
    insertShot(imagePath: 'p1/s.png', imageStatus: 'done');

    final first = makeEngine();
    final second = makeEngine();
    addTearDown(first.queue.dispose);
    addTearDown(second.queue.dispose);

    expect(db.select('SELECT COUNT(*) n FROM image_takes').first['n'], 2);
    expect(
        db
            .select(
                "SELECT COUNT(*) n FROM image_takes WHERE assetId='a1' AND imagePath='p1/a.png' AND selected=1")
            .first['n'],
        1);
    expect(
        db
            .select(
                "SELECT COUNT(*) n FROM image_takes WHERE shotId='s1' AND imagePath='p1/s.png' AND selected=1")
            .first['n'],
        1);
  });

  test('repaintAsset 和 repaintShot 当前无图时提示请先生成图片', () async {
    insertAsset(status: 'draft');
    insertShot(imageStatus: 'none');
    final engine = makeEngine();
    addTearDown(engine.queue.dispose);

    expect(
        () => engine.repaintAsset('a1', '把衣服改成红色'),
        throwsA(
            predicate((e) => e is EngineException && e.message == '请先生成图片')));
    expect(
        () => engine.repaintShot('s1', '改成雨夜'),
        throwsA(
            predicate((e) => e is EngineException && e.message == '请先生成图片')));
  });

  test('repaint 入队 payload，runner 传递参考图绝对路径与修改意见', () async {
    insertAsset(imagePath: 'p1/original.png', status: 'done');
    db.execute(
        "INSERT INTO image_takes (id,assetId,imagePath,selected,createdAt) VALUES ('take1','a1','p1/original.png',1,'1')");
    File(media.absPath('p1/original.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    final gateway = M4Gateway();
    final engine = makeEngine(gateway);
    addTearDown(engine.queue.dispose);

    final jobId = await engine.repaintAsset('a1', '把衣服改成红色');

    final job = db.select('SELECT * FROM jobs WHERE id=?', [jobId]).first;
    final payload =
        jsonDecode(job['payload'] as String) as Map<String, dynamic>;
    expect(payload['refTakeId'], 'take1');
    expect(payload['editInstruction'], '把衣服改成红色');

    await Runners(db, gateway, media).run(
      JobRow(
        job['id'] as String,
        job['projectId'] as String,
        job['kind'] as String,
        job['targetId'] as String,
        job['payload'] as String,
      ),
      token,
    );

    expect(gateway.lastRefImageAbsPath, media.absPath('p1/original.png'));
    expect(gateway.lastEditInstruction, '把衣服改成红色');
    expect(gateway.imagePrompts.single, '青衣少女');
  });
}
