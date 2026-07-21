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

  test('视频轨为后台运镜提示词保留独立状态和任务归属字段', () {
    final db = openEngineDb(':memory:');
    addTearDown(db.close);

    final columns = db
        .select('PRAGMA table_info(o_videoTrack)')
        .map((row) => row['name'] as String)
        .toSet();

    expect(columns,
        containsAll(['promptState', 'promptErrorReason', 'promptTaskId']));
  });

  test('v12 升级保留视频轨并补齐提示词生命周期字段', () {
    final dir = Directory.systemTemp.createTempSync('dramaflow-db-v12-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final path = p.join(dir.path, 'dramaflow.sqlite');
    final old = sqlite3.open(path);
    old.execute('''
CREATE TABLE o_videoTrack (
  duration INTEGER,
  filterPreset TEXT,
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  promptProvenance TEXT,
  projectId INTEGER,
  prompt TEXT,
  reason TEXT,
  scriptId INTEGER,
  selectVideoId INTEGER,
  state TEXT,
  transition TEXT,
  videoId INTEGER,
  videoRequest TEXT
);
''');
    old.execute(
      "INSERT INTO o_videoTrack (id,projectId,prompt,state) VALUES (8,7,'保留提示词','未生成')",
    );
    old.execute('PRAGMA user_version = 12');
    old.close();

    final db = openEngineDb(path);
    addTearDown(db.close);

    final track = db.select('SELECT * FROM o_videoTrack WHERE id=8').single;
    expect(track['prompt'], '保留提示词');
    expect(track['state'], '未生成');
    expect(track['promptState'], isNull);
    expect(track['promptErrorReason'], isNull);
    expect(track['promptTaskId'], isNull);
    expect(
      db.select('PRAGMA user_version').single.values.single,
      schemaVersion,
    );
  });

  test('nowIso 是 ISO8601 UTC', () {
    expect(nowIso(), matches(RegExp(r'^\d{4}-\d{2}-\d{2}T.*Z$')));
  });

  group('迁移失败时关闭 db 句柄（任务 3：不能让重试反复累积泄漏的原生句柄）', () {
    // chmod 模拟只读文件只在 POSIX 平台可靠；Windows 的只读语义不同。
    final skipOnWindows =
        Platform.isWindows ? 'chmod 模拟只读文件依赖 POSIX 权限位，Windows 需要另一套技术' : null;

    /// 只读文件恢复可写。WAL 模式下失败的一次打开会顺带创建 -wal/-shm 边车
    /// 文件、且这些新文件会继承主文件当时的只读权限位，所以必须和主文件
    /// 一起放开，否则下一次打开会在边车文件上继续失败，而不是真的复原。
    void chmodWritable(String dbPath) {
      Process.runSync('sh', ['-c', "chmod u+w '$dbPath'* 2>/dev/null || true"]);
    }

    /// 构造一个"需要迁移、且迁移会在事务内失败"的库：schema 用真正的
    /// initSchema() 建完整（避免手写 schema 漏字段），只把 user_version 降到
    /// 8 强制走迁移分支，再整个文件改只读。重新打开时 _configure/
    /// _userVersion 等纯读操作、以及所有 `CREATE TABLE/INDEX IF NOT EXISTS`
    /// 都因为对象已存在而是无操作，唯独迁移末尾 `PRAGMA user_version=14`
    /// 必须真正写文件头，因此只读会精确命中 db.dart 里
    /// `catch (_) { db.execute('ROLLBACK'); ... }` 这个分支。
    String makeReadonlyPendingMigrationDb(Directory dir) {
      final dbPath = p.join(dir.path, 'dramaflow.sqlite');
      final old = sqlite3.open(dbPath);
      old.execute('PRAGMA journal_mode = WAL');
      initSchema(old, setVersion: false);
      old.execute(
        "INSERT INTO o_novel (projectId,chapterIndex,chapter) VALUES (1,1,'保留章节')",
      );
      old.execute('PRAGMA user_version = 8');
      old.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      old.close();
      Process.runSync('chmod', ['a-w', dbPath]);
      return dbPath;
    }

    test('回滚后关闭句柄：文件保持可以立即重新打开，而不是卡死或残留半迁移状态', () {
      final dir =
          Directory.systemTemp.createTempSync('dramaflow-migrate-fail-');
      final dbPath = p.join(dir.path, 'dramaflow.sqlite');
      addTearDown(() {
        chmodWritable(dbPath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      makeReadonlyPendingMigrationDb(dir);

      expect(
        () => openEngineDb(dbPath),
        throwsA(isA<SqliteException>()),
      );

      // 只读文件本身没有被破坏：直接重新打开（绕过 openEngineDb）应该还能读到
      // 回滚前的旧 user_version 和原有数据，证明 ROLLBACK 生效、
      // 没有把半迁移状态提交、也没有损坏既有行。
      final readonlyCheck = sqlite3.open(dbPath);
      expect(
          readonlyCheck.select('PRAGMA user_version').single.values.single, 8);
      expect(
          readonlyCheck.select('SELECT chapter FROM o_novel').single['chapter'],
          '保留章节');
      readonlyCheck.close();

      // 权限恢复后可以立即重试并成功迁移到当前版本——如果上一次失败的 db
      // 没有被正确 close()，很多平台上这里会因为残留的独占锁而失败或挂起。
      chmodWritable(dbPath);
      final recovered = openEngineDb(dbPath);
      addTearDown(recovered.close);
      expect(recovered.select('PRAGMA user_version').single.values.single,
          schemaVersion);
      expect(
        recovered.select('SELECT chapter FROM o_novel').single['chapter'],
        '保留章节',
      );
    }, skip: skipOnWindows);

    test('同一份坏库反复触发迁移失败不会累积异常或让后续调用变慢/挂起', () {
      final dir =
          Directory.systemTemp.createTempSync('dramaflow-migrate-fail-repeat-');
      final dbPath = p.join(dir.path, 'dramaflow.sqlite');
      addTearDown(() {
        chmodWritable(dbPath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      makeReadonlyPendingMigrationDb(dir);

      // 如果失败路径漏关 db（这批任务修复前的状态），每次调用都会新泄漏一个
      // 原生 sqlite 句柄；反复调用几十次足以在多数环境下暴露句柄耗尽或行为
      // 劣化。这里只断言每次都抛出同一种干净的异常，不劣化成别的错误、不挂起。
      for (var i = 0; i < 30; i++) {
        expect(
          () => openEngineDb(dbPath),
          throwsA(isA<SqliteException>()),
          reason: '第 $i 次调用',
        );
      }
    }, skip: skipOnWindows);
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

    expect(
        db.select('PRAGMA user_version').single.values.single, schemaVersion);
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
