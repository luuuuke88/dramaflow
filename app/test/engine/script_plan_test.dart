import 'dart:io';

import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/script_plan.dart';
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
    dir = Directory.systemTemp.createTempSync('dramaflow-plan-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '规划测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('剧本规划：初始为空串', () {
    expect(engine.scriptPlan(projectId), '');
  });

  test('剧本规划：写入后可读回，二次写入为更新而非新增', () {
    engine.saveScriptPlan(projectId, '# 第一幕\n\n少年下山。');
    expect(engine.scriptPlan(projectId), '# 第一幕\n\n少年下山。');

    engine.saveScriptPlan(projectId, '# 第一幕（修订）\n\n少年雪夜下山。');
    expect(engine.scriptPlan(projectId), '# 第一幕（修订）\n\n少年雪夜下山。');

    final rows = db.select(
      "SELECT id FROM o_agentWorkData WHERE projectId=? AND key='scriptPlan'",
      [projectId],
    );
    expect(rows, hasLength(1), reason: '二次写入应为 upsert，仅一行');
  });

  test('剧本规划与 Agent 对话（同表不同 key）互不干扰', () {
    engine.saveScriptPlan(projectId, '规划内容');
    db.execute(
      "INSERT INTO o_agentWorkData (projectId,key,data) VALUES (?,'agentChat','[]')",
      [projectId],
    );
    expect(engine.scriptPlan(projectId), '规划内容');
  });
}
