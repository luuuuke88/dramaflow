import 'package:flutter_test/flutter_test.dart';
import 'package:dramaflow/src/engine/db.dart';

void main() {
  test('建库含全部 v1 表', () {
    final db = openEngineDb(':memory:');
    final tables = db
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((r) => r['name'] as String)
        .toSet();
    for (final t in [
      'projects',
      'novels',
      'episodes',
      'assets',
      'shots',
      'jobs',
      'settings',
      'providers',
      'provider_models',
      'prompts',
      'video_takes',
      'image_takes'
    ]) {
      expect(tables, contains(t), reason: '缺表 $t');
    }
    expect(db.select('PRAGMA user_version').first.values.first, 1);
    final assetCols =
        db.select('PRAGMA table_info(assets)').map((r) => r['name']).toSet();
    expect(assetCols, containsAll(['note', 'voiceId', 'userId']));
    final shotCols =
        db.select('PRAGMA table_info(shots)').map((r) => r['name']).toSet();
    expect(shotCols,
        containsAll(['selectedTakeId', 'audioPath', 'audioStatus']));
    db.close();
  });

  test('重复初始化幂等（IF NOT EXISTS）', () {
    final db = openEngineDb(':memory:');
    initSchema(db);
    db.close();
  });

  test('nowIso 是 ISO8601 UTC', () {
    expect(nowIso(), matches(RegExp(r'^\d{4}-\d{2}-\d{2}T.*Z$')));
  });

  test('assets kind 约束含 prop', () {
    final db = openEngineDb(':memory:');
    db.execute(
        "INSERT INTO projects (id,name,createdAt,updatedAt) VALUES ('p','t','x','x')");
    db.execute(
        "INSERT INTO assets (id,projectId,kind,name,createdAt) VALUES ('a1','p','prop','剑','x')");
    expect(
        () => db.execute(
            "INSERT INTO assets (id,projectId,kind,name,createdAt) VALUES ('a2','p','bogus','x','x')"),
        throwsA(anything));
    db.close();
  });
}
