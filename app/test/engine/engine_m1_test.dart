import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/util.dart';

class StubGateway implements ProviderGateway {
  @override
  Future<TextResult> generateText(String system, String user,
          {CancelToken? cancelToken}) async =>
      const TextResult('{}');

  @override
  Future<String> generateImage(String prompt, String projectId,
          {CancelToken? cancelToken}) async =>
      '$projectId/img_stub.png';

  @override
  Future<String> generateVideo(
          String prompt, String firstFrameAbsPath, String projectId,
          {CancelToken? cancelToken}) async =>
      '$projectId/vid_stub.mp4';
}

void main() {
  late Engine e;
  late Directory tmp;
  late String pid;
  late String eid;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('engine_m1');
    final db = openEngineDb(':memory:');
    e = Engine(
        db: db,
        media: MediaStore(tmp.path),
        gateway: StubGateway(),
        config: EngineConfig(db, isMobile: false));
    pid = (await e.createProject('项目')).id;
    eid = 'ep1';
    e.db.execute(
        "INSERT INTO episodes (id,projectId,idx,title,scriptJson,createdAt) VALUES (?,?,?,?,?,?)",
        [eid, pid, 1, '第一集', '[]', 'x']);
  });

  tearDown(() {
    e.dispose();
    tmp.deleteSync(recursive: true);
  });

  void insertShot(String id, int idx) {
    e.db.execute(
        "INSERT INTO shots (id,episodeId,projectId,idx,description,dialogue,camera,imagePrompt,videoPrompt,imageStatus,videoStatus,createdAt) VALUES (?,?,?,?,?,?,?,?,?,'none','none',?)",
        [
          id,
          eid,
          pid,
          idx,
          'd$id',
          'line$id',
          'cam$id',
          'img$id',
          'vid$id',
          'x'
        ]);
  }

  Future<List<String>> shotIdsByIdx() async =>
      (await e.listShots(eid)).map((s) => s.id).toList();

  Future<List<int>> shotIdxs() async =>
      (await e.listShots(eid)).map((s) => s.idx).toList();

  group('asset CRUD', () {
    test('createAsset 创建 draft 素材并保存 note', () async {
      final asset = await e.createAsset(
        pid,
        kind: 'character',
        name: '  阿青  ',
        description: '女主',
        imagePrompt: '青衣少女',
        note: '主角',
      );

      expect(asset.kind, 'character');
      expect(asset.name, '阿青');
      expect(asset.description, '女主');
      expect(asset.imagePrompt, '青衣少女');
      expect(asset.note, '主角');
      expect(asset.status, 'draft');

      final listed = (await e.listAssets(pid)).single;
      expect(listed.note, '主角');
    });

    test('createAsset 拒绝无效 kind、空名称、同项目同类同名', () async {
      expect(
          () => e.createAsset(pid, kind: 'weapon', name: '剑'),
          throwsA(
              predicate((x) => x is EngineException && x.message == '资产类型无效')));
      expect(
          () => e.createAsset(pid, kind: 'prop', name: '  '),
          throwsA(
              predicate((x) => x is EngineException && x.message == '名称不能为空')));

      await e.createAsset(pid, kind: 'prop', name: '玉佩');
      expect(
          () => e.createAsset(pid, kind: 'prop', name: '玉佩'),
          throwsA(predicate(
              (x) => x is EngineException && x.message == '同名资产已存在')));

      final otherProject = (await e.createProject('另一个项目')).id;
      final sameNameOtherProject =
          await e.createAsset(otherProject, kind: 'prop', name: '玉佩');
      final sameNameOtherKind =
          await e.createAsset(pid, kind: 'scene', name: '玉佩');
      expect(sameNameOtherProject.id, isNotEmpty);
      expect(sameNameOtherKind.id, isNotEmpty);
    });

    test('updateAsset 支持 note 的 COALESCE 更新', () async {
      final asset = await e.createAsset(pid,
          kind: 'scene', name: '码头', description: '旧描述', note: '旧备注');

      final updated = await e.updateAsset(asset.id, description: '新描述');
      expect(updated.description, '新描述');
      expect(updated.note, '旧备注');

      final noted = await e.updateAsset(asset.id, note: '新备注');
      expect(noted.description, '新描述');
      expect(noted.note, '新备注');
    });

    test('deleteAssets 批量删除；任一活跃图片任务则全部拒绝', () async {
      final a1 = await e.createAsset(pid, kind: 'character', name: '甲');
      final a2 = await e.createAsset(pid, kind: 'prop', name: '乙');
      final a3 = await e.createAsset(pid, kind: 'scene', name: '丙');

      e.db.execute(
          "INSERT INTO jobs (id,projectId,kind,targetId,state,createdAt) VALUES (?,?,?,?,?,?)",
          ['job1', pid, 'asset_image', a2.id, 'queued', 'x']);

      expect(
          () => e.deleteAssets([a1.id, a2.id]),
          throwsA(predicate((x) =>
              x is EngineException && x.message == '有资产正在生成图片，请先取消或等待完成')));
      expect((await e.listAssets(pid)).map((a) => a.id),
          containsAll([a1.id, a2.id, a3.id]));

      e.db.execute("UPDATE jobs SET state='canceled' WHERE id='job1'");
      await e.deleteAssets([a1.id, a2.id]);
      expect((await e.listAssets(pid)).map((a) => a.id), [a3.id]);
    });
  });

  group('shot ordering mutations', () {
    test('reorderShots 按给定顺序重写连续 idx', () async {
      insertShot('s1', 1);
      insertShot('s2', 2);
      insertShot('s3', 3);

      await e.reorderShots(eid, ['s3', 's1', 's2']);

      final shots = await e.listShots(eid);
      expect(shots.map((s) => s.id), ['s3', 's1', 's2']);
      expect(shots.map((s) => s.idx), [1, 2, 3]);
    });

    test('reorderShots 拒绝数量、成员或重复不一致的列表', () async {
      insertShot('s1', 1);
      insertShot('s2', 2);
      insertShot('s3', 3);

      Future<void> expectMismatch(List<String> ids) async {
        expect(
            () => e.reorderShots(eid, ids),
            throwsA(predicate((x) =>
                x is EngineException && x.message == '镜头列表与当前不一致，请刷新后重试')));
        expect(await shotIdsByIdx(), ['s1', 's2', 's3']);
        expect(await shotIdxs(), [1, 2, 3]);
      }

      await expectMismatch(['s1', 's2']);
      await expectMismatch(['s1', 's2', 'missing']);
      await expectMismatch(['s1', 's1', 's2']);
    });

    test('insertShot 在指定位置或末尾插入空镜头并保持 idx 连续', () async {
      insertShot('s1', 1);
      insertShot('s2', 2);

      final inserted = await e.insertShot(eid, afterIdx: 1);
      expect(inserted.idx, 2);
      expect(inserted.description, '');
      expect(inserted.dialogue, '');
      expect(inserted.camera, '');
      expect(inserted.imagePrompt, '');
      expect(inserted.videoPrompt, '');
      expect(inserted.imageStatus, 'none');
      expect(inserted.videoStatus, 'none');

      expect(await shotIdsByIdx(), ['s1', inserted.id, 's2']);
      expect(await shotIdxs(), [1, 2, 3]);

      final appended = await e.insertShot(eid);
      expect(appended.idx, 4);
      expect(await shotIdsByIdx(), ['s1', inserted.id, 's2', appended.id]);
      expect(await shotIdxs(), [1, 2, 3, 4]);

      expect(
          () => e.insertShot(eid, afterIdx: 99),
          throwsA(predicate(
              (x) => x is EngineException && x.message == '插入位置不存在，请刷新后重试')));
      expect(await shotIdxs(), [1, 2, 3, 4]);
    });

    test('deleteShot 删除并补齐后续 idx；活跃任务时拒绝删除', () async {
      insertShot('s1', 1);
      insertShot('s2', 2);
      insertShot('s3', 3);

      e.db.execute(
          "INSERT INTO jobs (id,projectId,kind,targetId,state,createdAt) VALUES (?,?,?,?,?,?)",
          ['job1', pid, 'shot_image', 's2', 'running', 'x']);
      expect(
          () => e.deleteShot('s2'),
          throwsA(predicate(
              (x) => x is EngineException && x.message == '该镜头有任务进行中，请先取消')));
      expect(await shotIdsByIdx(), ['s1', 's2', 's3']);

      e.db.execute("UPDATE jobs SET state='canceled' WHERE id='job1'");
      e.db.execute(
          "INSERT INTO jobs (id,projectId,kind,targetId,state,createdAt) VALUES (?,?,?,?,?,?)",
          ['job2', pid, 'shot_video', 's2', 'queued', 'x']);
      expect(
          () => e.deleteShot('s2'),
          throwsA(predicate(
              (x) => x is EngineException && x.message == '该镜头有任务进行中，请先取消')));

      e.db.execute("UPDATE jobs SET state='canceled' WHERE id='job2'");
      await e.deleteShot('s2');
      expect(await shotIdsByIdx(), ['s1', 's3']);
      expect(await shotIdxs(), [1, 2]);
    });
  });
}
