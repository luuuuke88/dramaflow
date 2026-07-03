import 'dart:io';

import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard_table.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Engine engine;
  late int projectId;
  late int scriptA;
  late int scriptB;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-sbtable-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '分镜表测试');
    scriptA = engine.addScript(projectId: projectId, name: '第一集', content: 'a');
    scriptB = engine.addScript(projectId: projectId, name: '第二集', content: 'b');
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('未写入时返回空串', () {
    expect(engine.storyboardTable(projectId, scriptA), '');
  });

  test('保存/回读/更新（剧集级 upsert）', () {
    engine.saveStoryboardTable(projectId, scriptA, '# 分镜\nS01 开场');
    expect(engine.storyboardTable(projectId, scriptA), '# 分镜\nS01 开场');

    // 更新同一剧集（应为 update 而非新增行）。
    engine.saveStoryboardTable(projectId, scriptA, '# 分镜\nS01 改写');
    expect(engine.storyboardTable(projectId, scriptA), '# 分镜\nS01 改写');
    final rows = engine.db.select(
      "SELECT COUNT(*) n FROM o_agentWorkData WHERE key='storyboardTable' AND episodesId=?",
      [scriptA],
    );
    expect(rows.first['n'], 1, reason: '同剧集重复保存应 upsert，不新增行');
  });

  test('不同剧集互不干扰', () {
    engine.saveStoryboardTable(projectId, scriptA, 'A 表');
    engine.saveStoryboardTable(projectId, scriptB, 'B 表');
    expect(engine.storyboardTable(projectId, scriptA), 'A 表');
    expect(engine.storyboardTable(projectId, scriptB), 'B 表');
  });
}
