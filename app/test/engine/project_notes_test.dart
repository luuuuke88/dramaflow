import 'dart:io';

import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/project_notes.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _Gateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-notes-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '笔记测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('CRUD 往返：新增→列表→更新→删除', () {
    final id = engine.saveProjectNote(projectId,
        name: '主角设定', content: '林朝雪，寒山派弟子');
    expect(engine.projectNotes(projectId), hasLength(1));
    expect(engine.projectNotes(projectId).single.name, '主角设定');

    engine.saveProjectNote(projectId,
        id: id, name: '主角设定', content: '林朝雪，寒山派大弟子');
    final notes = engine.projectNotes(projectId);
    expect(notes, hasLength(1), reason: '带 id 保存是更新不是新增');
    expect(notes.single.content, contains('大弟子'));

    engine.deleteProjectNote(projectId, id);
    expect(engine.projectNotes(projectId), isEmpty);
  });

  test('项目隔离：不同项目的笔记互不可见', () {
    final other = engine.addProject(projectType: 'novel', name: '另一个');
    engine.saveProjectNote(projectId, name: 'A', content: 'a');
    engine.saveProjectNote(other, name: 'B', content: 'b');
    expect(engine.projectNotes(projectId).single.name, 'A');
    expect(engine.projectNotes(other).single.name, 'B');
  });

  test('中文检索：子串命中排第一', () {
    engine.saveProjectNote(projectId, name: '道具', content: '林朝雪的青霜剑');
    engine.saveProjectNote(projectId, name: '场景', content: '寒山派山门场景');
    engine.saveProjectNote(projectId, name: '配置', content: '视频模型用 seedance');

    expect(engine.searchProjectNotes(projectId, '青霜').first.content,
        contains('青霜剑'));
    expect(engine.searchProjectNotes(projectId, '山门').first.content,
        contains('山门'));
    expect(engine.searchProjectNotes(projectId, 'seedance').first.content,
        contains('seedance'));
  });

  test('中文检索：乱序子串靠 bi-gram 部分重叠命中', () {
    engine.saveProjectNote(projectId, name: '道具', content: '林朝雪的青霜剑');
    engine.saveProjectNote(projectId, name: '场景', content: '寒山派山门场景');
    final hits = engine.searchProjectNotes(projectId, '朝雪剑');
    expect(hits, isNotEmpty);
    expect(hits.first.content, contains('林朝雪'),
        reason: '「朝雪」bi-gram 与「林朝雪的青霜剑」重叠，应命中且排第一');
    expect(hits.any((n) => n.content.contains('山门')), isFalse,
        reason: '零重叠的笔记不得出现在结果里');
  });

  test('空查询与全不相关查询返回空', () {
    engine.saveProjectNote(projectId, name: 'A', content: '林朝雪');
    expect(engine.searchProjectNotes(projectId, ''), isEmpty);
    expect(engine.searchProjectNotes(projectId, '   '), isEmpty);
    expect(engine.searchProjectNotes(projectId, '毫无关联词汇'), isEmpty);
  });

  test('limit 生效且按分数降序', () {
    for (var i = 0; i < 8; i++) {
      engine.saveProjectNote(projectId, name: '笔记$i', content: '青霜剑相关内容$i');
    }
    engine.saveProjectNote(projectId, name: '最相关', content: '青霜剑 青霜剑 青霜剑');
    final hits = engine.searchProjectNotes(projectId, '青霜剑', limit: 5);
    expect(hits, hasLength(5));
  });
}
