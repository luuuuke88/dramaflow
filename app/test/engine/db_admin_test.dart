import 'dart:io';

import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/db_admin.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/novel.dart';
import 'package:dramaflow/src/engine/novel_parse.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
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
    dir = Directory.systemTemp.createTempSync('dramaflow-dbadmin-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 10),
    );
    // 直接构造 Engine 不会跑 boot 的种子逻辑，手动预置一条供应商 + 绑定，
    // 用于验证 clearAllData 保留用户配置。
    db.execute(
      "INSERT INTO o_vendorConfig (id,enable,inputValues,models) "
      "VALUES ('azt',1,'{}','[]')",
    );
    db.execute(
      "INSERT OR REPLACE INTO o_setting (key,value) "
      "VALUES ('binding.script_gen','azt:gpt-5.5')",
    );
    projectId = engine.addProject(projectType: 'novel', name: '清空测试');
    engine.addNovels(projectId, const [
      ChapterItem(index: 1, reel: '正文卷', chapter: '一', chapterData: 'x'),
    ]);
    engine.addScript(projectId: projectId, name: '一', content: 'x');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('dbInfo 列出各表行数（含 o_project 至少 1 行）', () {
    final info = engine.dbInfo();
    final byTable = {for (final row in info) row.table: row.rowCount};
    expect(byTable.containsKey('o_project'), isTrue);
    expect(byTable['o_project'], 1);
    expect(byTable['o_novel'], 1);
    expect(byTable['o_script'], 1);
    // sqlite_ 内部表不出现在列表里
    expect(info.every((row) => !row.table.startsWith('sqlite_')), isTrue);
  });

  test('clearAllData 清空内容数据但保留供应商与绑定配置', () {
    // 预置一条媒体文件，验证清空后被删除。
    final rel = engine.media.saveImage([1, 2, 3], projectId.toString());
    expect(File(engine.media.absPath(rel)).existsSync(), isTrue);

    // 预置一条密钥，验证清空后随供应商一起保留（否则供应商还在却丢了 Key）。
    db.execute(
      "INSERT INTO o_secret (ref,value) "
      "VALUES ('dramaflow.provider.azt.api-key','sk-keep-me')",
    );

    final providersBefore =
        db.select('SELECT COUNT(*) n FROM o_vendorConfig').first['n'] as int;
    final bindingsBefore = db
        .select("SELECT COUNT(*) n FROM o_setting WHERE key LIKE 'binding.%'")
        .first['n'] as int;
    expect(providersBefore, greaterThan(0));
    expect(bindingsBefore, greaterThan(0));

    engine.clearAllData();

    // 内容数据被清空
    expect(db.select('SELECT COUNT(*) n FROM o_project').first['n'], 0);
    expect(db.select('SELECT COUNT(*) n FROM o_novel').first['n'], 0);
    expect(db.select('SELECT COUNT(*) n FROM o_script').first['n'], 0);
    // 媒体文件被删除
    expect(File(engine.media.absPath(rel)).existsSync(), isFalse);
    // 供应商、密钥与绑定配置被保留
    expect(db.select('SELECT COUNT(*) n FROM o_vendorConfig').first['n'],
        providersBefore);
    expect(
        db.select(
                "SELECT value FROM o_secret WHERE ref='dramaflow.provider.azt.api-key'")
            .single['value'],
        'sk-keep-me');
    expect(
        db
            .select(
                "SELECT COUNT(*) n FROM o_setting WHERE key LIKE 'binding.%'")
            .first['n'],
        bindingsBefore);
  });

  test('clearAllData 保留模型、提示词与画风配置', () {
    db.execute(
      "INSERT INTO o_agentDeploy (key,name,type,modelName,vendorId) "
      "VALUES ('script_gen','剧本','text','gpt-5.5','azt')",
    );
    db.execute(
      "INSERT INTO o_modelPromptTemplate "
      "(path,name,kind,prompt,createTime,updateTime) "
      "VALUES ('video/custom.md','自定义视频','video','x',1,1)",
    );
    db.execute(
      "INSERT INTO o_artStyle (name,label,prompt) VALUES ('ink','水墨','水墨画')",
    );

    engine.clearAllData();

    expect(db.select('SELECT COUNT(*) n FROM o_agentDeploy').single['n'], 1);
    expect(
      db.select('SELECT COUNT(*) n FROM o_modelPromptTemplate').single['n'],
      1,
    );
    expect(db.select('SELECT COUNT(*) n FROM o_artStyle').single['n'], 1);
  });

  test('clearableDbTables 只列出可删除的内容表', () {
    final tables = engine.clearableDbTables().map((row) => row.table).toSet();

    expect(tables, containsAll(['o_project', 'o_novel', 'o_script']));
    expect(
      tables.intersection({
        'o_secret',
        'o_vendorConfig',
        'o_setting',
        'o_agentDeploy',
        'o_modelPromptTemplate',
        'o_artStyle',
      }),
      isEmpty,
    );
    expect(tables.every((table) => !table.startsWith('sqlite_')), isTrue);
  });

  test('clearTable 只删除选中的内容表', () {
    db.execute(
      "INSERT INTO o_secret (ref,value) "
      "VALUES ('dramaflow.provider.azt.api-key','sk-keep-me')",
    );

    engine.clearTable('o_novel');

    expect(db.select('SELECT COUNT(*) n FROM o_novel').single['n'], 0);
    expect(db.select('SELECT COUNT(*) n FROM o_project').single['n'], 1);
    expect(db.select('SELECT COUNT(*) n FROM o_script').single['n'], 1);
    expect(
      db
          .select(
              "SELECT value FROM o_secret WHERE ref='dramaflow.provider.azt.api-key'")
          .single['value'],
      'sk-keep-me',
    );
  });

  test('clearTable 拒绝密钥、配置与任意表名', () {
    for (final table in [
      'o_secret',
      'o_vendorConfig',
      'o_agentDeploy',
      'missing_table',
      'o_novel; DELETE FROM o_secret',
    ]) {
      expect(
        () => engine.clearTable(table),
        throwsA(isA<EngineException>()),
        reason: table,
      );
    }
  });

  test('clearTable(o_script) 级联清理分镜/视频/视频轨与磁盘文件，不留孤儿行', () {
    final scriptId =
        engine.addScript(projectId: projectId, name: '二', content: 'y');
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '主角',
      describe: '',
    );
    db.execute(
      'INSERT INTO o_scriptAssets (assetId,scriptId) VALUES (?,?)',
      [assetId, scriptId],
    );

    final storyboardRel = engine.media.saveImage([1, 2, 3], '$projectId');
    db.execute(
      'INSERT INTO o_storyboard (projectId,scriptId,filePath,"index",state) '
      "VALUES (?,?,?,1,'done')",
      [projectId, scriptId, storyboardRel],
    );
    final storyboardId = db.lastInsertRowId;
    db.execute(
      'INSERT INTO o_assets2Storyboard (assetId,storyboardId) VALUES (?,?)',
      [assetId, storyboardId],
    );

    db.execute(
      "INSERT INTO o_videoTrack (projectId,scriptId,state) VALUES (?,?,'idle')",
      [projectId, scriptId],
    );
    final trackId = db.lastInsertRowId;
    final videoRel = engine.media.saveVideo([4, 5, 6], '$projectId');
    db.execute(
      "INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) "
      "VALUES (?,?,?,?,'done')",
      [projectId, scriptId, trackId, videoRel],
    );

    expect(File(engine.media.absPath(storyboardRel)).existsSync(), isTrue);
    expect(File(engine.media.absPath(videoRel)).existsSync(), isTrue);

    engine.clearTable('o_script');

    expect(db.select('SELECT COUNT(*) n FROM o_script').single['n'], 0);
    expect(
      db.select('SELECT COUNT(*) n FROM o_storyboard WHERE scriptId=?',
          [scriptId]).single['n'],
      0,
    );
    expect(
      db.select(
          'SELECT COUNT(*) n FROM o_assets2Storyboard WHERE storyboardId=?',
          [storyboardId]).single['n'],
      0,
    );
    expect(
      db.select('SELECT COUNT(*) n FROM o_video WHERE scriptId=?',
          [scriptId]).single['n'],
      0,
    );
    expect(
      db.select('SELECT COUNT(*) n FROM o_videoTrack WHERE scriptId=?',
          [scriptId]).single['n'],
      0,
    );
    expect(
      db.select('SELECT COUNT(*) n FROM o_scriptAssets WHERE scriptId=?',
          [scriptId]).single['n'],
      0,
    );
    expect(File(engine.media.absPath(storyboardRel)).existsSync(), isFalse);
    expect(File(engine.media.absPath(videoRel)).existsSync(), isFalse);
    // o_assets 不是 o_script 的子孙表：清空 o_script 不该连累素材库本身。
    expect(
      db.select(
          'SELECT COUNT(*) n FROM o_assets WHERE id=?', [assetId]).single['n'],
      1,
    );
  });

  test('clearTable(o_novel) 级联清理事件关联，不留孤儿事件行', () {
    final novelId = db.select('SELECT id FROM o_novel WHERE projectId=?',
        [projectId]).single['id'] as int;
    db.execute(
        "INSERT INTO o_event (name,detail,createTime) VALUES ('冲突','x',0)");
    final eventId = db.lastInsertRowId;
    db.execute(
      'INSERT INTO o_eventChapter (eventId,novelId) VALUES (?,?)',
      [eventId, novelId],
    );

    engine.clearTable('o_novel');

    expect(db.select('SELECT COUNT(*) n FROM o_novel').single['n'], 0);
    expect(
      db.select('SELECT COUNT(*) n FROM o_eventChapter WHERE novelId=?',
          [novelId]).single['n'],
      0,
    );
    // 这条事件唯一挂靠的章节没了，应随之清理，不留下再也查不到的孤儿事件行
    // （events() 对 o_novel 是 INNER JOIN，孤儿行会从事件列表里彻底消失）。
    expect(
      db.select(
          'SELECT COUNT(*) n FROM o_event WHERE id=?', [eventId]).single['n'],
      0,
    );
    expect(db.select('SELECT COUNT(*) n FROM o_project').single['n'], 1);
    expect(db.select('SELECT COUNT(*) n FROM o_script').single['n'], 1);
  });

  test('clearTable(o_project) 级联清理全部子孙数据并删除项目媒体目录', () {
    final novelId = db.select('SELECT id FROM o_novel WHERE projectId=?',
        [projectId]).single['id'] as int;
    final rel = engine.media.saveImage([9, 9, 9], '$projectId');
    db.execute(
      'INSERT INTO o_storyboard (projectId,filePath,"index",state) '
      "VALUES (?,?,1,'done')",
      [projectId, rel],
    );
    expect(
        Directory(p.dirname(engine.media.absPath(rel))).existsSync(), isTrue);

    engine.clearTable('o_project');

    expect(db.select('SELECT COUNT(*) n FROM o_project').single['n'], 0);
    expect(db.select('SELECT COUNT(*) n FROM o_novel').single['n'], 0);
    expect(db.select('SELECT COUNT(*) n FROM o_script').single['n'], 0);
    expect(
      db.select('SELECT COUNT(*) n FROM o_storyboard WHERE projectId=?',
          [projectId]).single['n'],
      0,
    );
    expect(File(engine.media.absPath(rel)).existsSync(), isFalse);
    expect(
      db.select('SELECT COUNT(*) n FROM o_eventChapter WHERE novelId=?',
          [novelId]).single['n'],
      0,
    );
  });

  test('clearTable(o_image) 清空图片表时同步清空 o_assets.imageId 并删除磁盘文件', () {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '主角',
      describe: '',
    );
    final rel = engine.media.saveImage([1, 2, 3], '$projectId');
    db.execute(
      "INSERT INTO o_image (assetsId,filePath,type,state) VALUES (?,?,'role','done')",
      [assetId, rel],
    );
    final imageId = db.lastInsertRowId;
    db.execute('UPDATE o_assets SET imageId=? WHERE id=?', [imageId, assetId]);
    expect(File(engine.media.absPath(rel)).existsSync(), isTrue);

    engine.clearTable('o_image');

    expect(db.select('SELECT COUNT(*) n FROM o_image').single['n'], 0);
    expect(File(engine.media.absPath(rel)).existsSync(), isFalse);
    // 资产行本身还在（o_assets 不是 o_image 的子孙表），但不能留一个指向
    // 已删行的 imageId 孤儿引用。
    final assetRow =
        db.select('SELECT imageId FROM o_assets WHERE id=?', [assetId]).single;
    expect(assetRow['imageId'], isNull);
  });

  test('clearTable(o_tasks) 清空任务表时同步删除私有载荷文件', () {
    db.execute(
      "INSERT INTO o_tasks (projectId,state,taskClass,describe,startTime) "
      "VALUES (?,'pending','video_generation','x',0)",
      [projectId],
    );
    final taskId = db.lastInsertRowId;
    engine.writeTaskPrivatePayload(taskId, '{"secret":true}');
    expect(engine.readTaskPrivatePayload(taskId), isNotNull);

    engine.clearTable('o_tasks');

    expect(db.select('SELECT COUNT(*) n FROM o_tasks').single['n'], 0);
    expect(engine.readTaskPrivatePayload(taskId), isNull);
  });

  test('clearTable(o_video) 逐条复用 deleteVideo：删除磁盘文件并清空视频轨引用', () {
    final scriptId =
        engine.addScript(projectId: projectId, name: '三', content: 'z');
    db.execute(
      "INSERT INTO o_videoTrack (projectId,scriptId,state) VALUES (?,?,'idle')",
      [projectId, scriptId],
    );
    final trackId = db.lastInsertRowId;
    final rel = engine.media.saveVideo([1, 2, 3], '$projectId');
    db.execute(
      "INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) "
      "VALUES (?,?,?,?,'done')",
      [projectId, scriptId, trackId, rel],
    );
    final videoId = db.lastInsertRowId;
    db.execute(
      'UPDATE o_videoTrack SET videoId=?, selectVideoId=? WHERE id=?',
      [videoId, videoId, trackId],
    );

    engine.clearTable('o_video');

    expect(db.select('SELECT COUNT(*) n FROM o_video').single['n'], 0);
    expect(File(engine.media.absPath(rel)).existsSync(), isFalse);
    // deleteVideo 会顺带清空引用它的轨道指针；o_video 不是 o_videoTrack 的父表，
    // 清空前者不该删掉后者的行，只应该清掉指向已删视频的孤儿指针。
    final trackRow = db.select(
        'SELECT videoId,selectVideoId FROM o_videoTrack WHERE id=?',
        [trackId]).single;
    expect(trackRow['videoId'], isNull);
    expect(trackRow['selectVideoId'], isNull);
    expect(db.select('SELECT COUNT(*) n FROM o_videoTrack').single['n'], 1);
  });

  test('clearTable(o_videoTrack) 逐条复用 deleteVideoTrack：级联删除候选视频与磁盘文件', () {
    final scriptId =
        engine.addScript(projectId: projectId, name: '四', content: 'w');
    db.execute(
      "INSERT INTO o_videoTrack (projectId,scriptId,state) VALUES (?,?,'idle')",
      [projectId, scriptId],
    );
    final trackId = db.lastInsertRowId;
    final rel = engine.media.saveVideo([7, 8, 9], '$projectId');
    db.execute(
      "INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) "
      "VALUES (?,?,?,?,'done')",
      [projectId, scriptId, trackId, rel],
    );

    engine.clearTable('o_videoTrack');

    expect(db.select('SELECT COUNT(*) n FROM o_videoTrack').single['n'], 0);
    expect(
      db.select('SELECT COUNT(*) n FROM o_video WHERE videoTrackId=?',
          [trackId]).single['n'],
      0,
    );
    expect(File(engine.media.absPath(rel)).existsSync(), isFalse);
  });

  test('tableClearCascades 标出尚未接入级联清理的表', () {
    expect(engine.tableClearCascades('o_novel'), isTrue);
    expect(engine.tableClearCascades('o_script'), isTrue);
    expect(engine.tableClearCascades('o_project'), isTrue);
    expect(engine.tableClearCascades('o_assets'), isTrue);
    expect(engine.tableClearCascades('o_imageFlow'), isFalse);
  });

  test('dataDirPath 是媒体根目录的父目录', () {
    expect(engine.dataDirPath(), dir.path);
  });
}
