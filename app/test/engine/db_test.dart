import 'dart:io';

import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('重复初始化保持当前 user_version', () {
    final db = openEngineDb(':memory:');
    addTearDown(db.close);

    initSchema(db);

    expect(db.select('PRAGMA user_version').first.values.first, schemaVersion);
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

  test('v9 升级保留视频数据并添加可恢复请求列', () {
    final dir = Directory.systemTemp.createTempSync('dramaflow-db-v9-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final path = p.join(dir.path, 'dramaflow.sqlite');
    final old = sqlite3.open(path);
    old.execute('''
CREATE TABLE o_project (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT,
  videoModel TEXT,
  videoRatio TEXT
);
CREATE TABLE o_videoTrack (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  projectId INTEGER,
  scriptId INTEGER,
  prompt TEXT,
  reason TEXT,
  state TEXT,
  duration INTEGER,
  transition TEXT,
  filterPreset TEXT,
  selectVideoId INTEGER,
  videoId INTEGER
);
CREATE TABLE o_video (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  projectId INTEGER,
  scriptId INTEGER,
  videoTrackId INTEGER,
  state TEXT,
  filePath TEXT,
  errorReason TEXT,
  time INTEGER
);
''');
    old.execute(
        "INSERT INTO o_project (id,name,videoModel,videoRatio) VALUES (7,'保留项目','volcengine:seedance','9:16')");
    old.execute(
        "INSERT INTO o_videoTrack (id,projectId,scriptId,prompt,reason,state,duration,transition,filterPreset,selectVideoId,videoId) VALUES (8,7,9,'prompt','reason','生成中',5,'fade','film',10,10)");
    old.execute(
        "INSERT INTO o_video (id,projectId,scriptId,videoTrackId,state,filePath,errorReason,time) VALUES (10,7,9,8,'生成中','p/video.mp4','old error',123)");
    old.execute('PRAGMA user_version = 9');
    old.close();

    final db = openEngineDb(path);
    addTearDown(db.close);

    expect(db.select('PRAGMA user_version').single.values.single, schemaVersion);
    expect(db.select('SELECT * FROM o_project').single['name'], '保留项目');
    expect(db.select('SELECT * FROM o_project').single['videoModel'],
        'volcengine:seedance');
    expect(db.select('SELECT * FROM o_videoTrack').single['prompt'], 'prompt');
    expect(db.select('SELECT * FROM o_videoTrack').single['reason'], 'reason');
    expect(
        db.select('SELECT * FROM o_videoTrack').single['transition'], 'fade');
    expect(
        db.select('SELECT * FROM o_video').single['filePath'], 'p/video.mp4');
    expect(
        db.select('SELECT * FROM o_video').single['errorReason'], 'old error');

    Map<String, dynamic> columns(String table) => {
          for (final row in db.select('PRAGMA table_info($table)'))
            row['name'] as String: row,
        };
    final tracks = columns('o_videoTrack');
    final videos = columns('o_video');
    for (final name in ['videoRequest', 'promptProvenance']) {
      expect(tracks[name], isNotNull);
      expect(tracks[name]!['notnull'], 0);
    }
    for (final name in [
      'modelBinding',
      'requestFingerprint',
      'submissionState',
      'upstreamTaskId',
      'upstreamState',
      'upstreamUpdatedAt',
    ]) {
      expect(videos[name], isNotNull);
      expect(videos[name]!['notnull'], 0);
    }
  });

  test('v10 升级保留项目并创建生产依赖状态表', () {
    final dir = Directory.systemTemp.createTempSync('dramaflow-db-v10-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final path = p.join(dir.path, 'dramaflow.sqlite');
    final old = sqlite3.open(path);
    old.execute('''
CREATE TABLE o_project (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT,
  projectType TEXT
);
''');
    old.execute(
        "INSERT INTO o_project (id,name,projectType) VALUES (7,'保留项目','novel')");
    old.execute('PRAGMA user_version = 10');
    old.close();

    final db = openEngineDb(path);
    addTearDown(db.close);

    expect(
        db.select('PRAGMA user_version').single.values.single, schemaVersion);
    expect(db.select('SELECT name FROM o_project WHERE id=7').single['name'],
        '保留项目');
    expect(
      db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='o_productionDependencyState'"),
      hasLength(1),
    );
  });

  test('cold-start resumer opts a processing task into pending or failure', () {
    final db = openEngineDb(':memory:');
    addTearDown(db.close);
    db.execute("INSERT INTO o_project (id,name) VALUES (1,'p')");
    db.execute(
        "INSERT INTO o_tasks (id,projectId,state,taskClass,reason) VALUES (44,1,'processing','video_generation','old')");
    final queue = JobQueue(db, run: (task, token) async {});
    addTearDown(queue.dispose);

    queue.registerColdStartResumer('video_generation', (task) {
      expect(task.id, 44);
      return ColdStartDisposition.resume;
    });
    queue.recoverOnColdStart();
    expect(db.select('SELECT state,reason FROM o_tasks WHERE id=44').single,
        containsPair('state', 'pending'));
    expect(db.select('SELECT state,reason FROM o_tasks WHERE id=44').single,
        containsPair('reason', isNull));

    db.execute("UPDATE o_tasks SET state='processing' WHERE id=44");
    queue.registerColdStartResumer(
        'video_generation', (_) => ColdStartDisposition.fail);
    queue.recoverOnColdStart();
    expect(db.select('SELECT state FROM o_tasks WHERE id=44').single['state'],
        'failed');
  });
}
