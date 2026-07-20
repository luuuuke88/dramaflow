import 'dart:io';

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

  test('dataDirPath 是媒体根目录的父目录', () {
    expect(engine.dataDirPath(), dir.path);
  });
}
