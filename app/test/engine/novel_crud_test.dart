import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/novel.dart';
import 'package:dramaflow/src/engine/novel_parse.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-novel-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<ChapterItem> chapters(int n, {String prefix = '章'}) => [
        for (var i = 1; i <= n; i++)
          ChapterItem(
            index: i,
            reel: '正文卷',
            chapter: '$prefix$i',
            chapterData: '内容$i',
          ),
      ];

  test('addNovels 落库：eventState=0、chapterIndex 续排、回调收到新 id', () {
    int? cbProject;
    List<int>? cbIds;
    engine.onNovelsAdded = (pid, ids) {
      cbProject = pid;
      cbIds = ids;
    };
    final first = engine.addNovels(projectId, chapters(2));
    expect(first, hasLength(2));
    expect(cbProject, projectId);
    expect(cbIds, first);

    final second = engine.addNovels(projectId, chapters(1, prefix: '续'));
    final all = engine.novels(projectId, limit: 10).data;
    expect(all.map((n) => n.chapterIndex), [1, 2, 3]);
    expect(all.map((n) => n.eventState), everyElement(0));
    expect(all.last.id, second.single);
  });

  test('novels 分页与搜索', () {
    engine.addNovels(projectId, chapters(25));
    final page2 = engine.novels(projectId, page: 2, limit: 10);
    expect(page2.total, 25);
    expect(page2.data, hasLength(10));
    expect(page2.data.first.chapterIndex, 11);

    final hit = engine.novels(projectId, search: '章2');
    expect(hit.total, 7, reason: '章2 与 章20-25 共 7 条');
  });

  test('updateNovel 局部字段更新', () {
    final id = engine.addNovels(projectId, chapters(1)).single;
    engine.updateNovel(id, chapter: '新标题', event: '事件文本', index: 9);
    final row = engine.novels(projectId).data.single;
    expect(row.chapter, '新标题');
    expect(row.event, '事件文本');
    expect(row.chapterIndex, 9);
    expect(row.chapterData, '内容1', reason: '未传字段不动');
  });

  test('deleteNovels 级联清除事件关联与孤儿事件', () {
    final ids = engine.addNovels(projectId, chapters(2));
    db.execute(
        "INSERT INTO o_event (id,name,detail,createTime) VALUES (1,'共享事件','d',0)");
    db.execute(
        "INSERT INTO o_event (id,name,detail,createTime) VALUES (2,'独占事件','d',0)");
    // 事件1 关联两章、事件2 只关联第一章
    db.execute(
        'INSERT INTO o_eventChapter (eventId,novelId) VALUES (1,?),(1,?),(2,?)',
        [ids[0], ids[1], ids[0]]);

    engine.deleteNovels([ids[0]]);
    expect(
        db.select('SELECT COUNT(*) n FROM o_novel').first['n'], 1);
    expect(
        db.select('SELECT id FROM o_event').map((r) => r['id']).toList(), [1],
        reason: '事件1 仍被第二章引用保留，事件2 成孤儿被清');

    engine.deleteNovels([ids[1]]);
    expect(db.select('SELECT COUNT(*) n FROM o_event').first['n'], 0);
    expect(db.select('SELECT COUNT(*) n FROM o_eventChapter').first['n'], 0);
  });

  test('novelIndex 返回精简目录', () {
    engine.addNovels(projectId, chapters(3));
    final idx = engine.novelIndex(projectId);
    expect(idx.map((e) => e.index), [1, 2, 3]);
    expect(idx.first.chapter, '章1');
  });
}

class _NoopGateway implements ProviderGateway {
  @override
  Future<TextResult> generateText(String system, String user,
          {required String stage, CancelToken? cancelToken}) async =>
      const TextResult('');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
