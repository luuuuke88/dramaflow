import 'package:dramaflow/src/engine/db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('重复初始化保持 user_version 3', () {
    final db = openEngineDb(':memory:');
    addTearDown(db.close);

    initSchema(db);

    expect(db.select('PRAGMA user_version').first.values.first, 3);
  });

  test('nowIso 是 ISO8601 UTC', () {
    expect(nowIso(), matches(RegExp(r'^\d{4}-\d{2}-\d{2}T.*Z$')));
  });

  test('o_project id 自增', () {
    final db = openEngineDb(':memory:');
    addTearDown(db.close);

    db.execute("INSERT INTO o_project (name,projectType) VALUES ('a','drama')");
    db.execute("INSERT INTO o_project (name,projectType) VALUES ('b','drama')");

    expect(
        db.select('SELECT id FROM o_project ORDER BY id').map((r) => r['id']),
        [1, 2]);
  });

  test('TEXT 主键表接受字符串 id', () {
    final db = openEngineDb(':memory:');
    addTearDown(db.close);

    db.execute(
      "INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES ('vendor-a',1,'{}','[]')",
    );
    db.execute(
      "INSERT INTO o_skillList (id,createTime,description,md5,name,path,state,type,updateTime) VALUES ('skill-a',1,'d','m','n','p',1,'tool',2)",
    );

    expect(db.select('SELECT id FROM o_vendorConfig').first['id'], 'vendor-a');
    expect(db.select('SELECT id FROM o_skillList').first['id'], 'skill-a');
  });

  test('o_tasks 允许计划状态枚举值', () {
    final db = openEngineDb(':memory:');
    addTearDown(db.close);

    for (final state in ['pending', 'processing', 'success', 'failed']) {
      db.execute(
        'INSERT INTO o_tasks (projectId,state,taskClass) VALUES (?,?,?)',
        [1, state, 'event_generation'],
      );
    }

    expect(db.select('SELECT COUNT(*) n FROM o_tasks').first['n'], 4);
  });
}
