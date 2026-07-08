import 'dart:io';

import 'package:dramaflow/src/engine/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const _legacyVectorTable = 'o_memory' 'Vector';
const _legacyVectorScopeIndex = 'idx_o_memory' 'Vector_scope';

const toonflowTables = [
  'memories',
  'o_agentDeploy',
  'o_agentWorkData',
  'o_artStyle',
  'o_assets',
  'o_assets2Storyboard',
  'o_assetsRole2Audio',
  'o_event',
  'o_eventChapter',
  'o_image',
  'o_imageFlow',
  'o_modelPrompt',
  _legacyVectorTable,
  'o_novel',
  'o_project',
  'o_prompt',
  'o_script',
  'o_scriptAssets',
  'o_setting',
  'o_skillAttribution',
  'o_skillList',
  'o_storyboard',
  'o_tasks',
  'o_timelineClip',
  'o_user',
  'o_vendorConfig',
  'o_video',
  'o_videoTrack',
];

void main() {
  group('schema v8', () {
    test('新库 user_version==schemaVersion 且 ToonFlow 表齐全', () {
      final db = openEngineDb(':memory:');
      addTearDown(db.close);

      final version = db.select('PRAGMA user_version').first.values.first;
      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((row) => row['name'] as String)
          .toSet();

      expect(version, schemaVersion);
      expect(tables, containsAll(toonflowTables));
      expect(tables.length, greaterThanOrEqualTo(toonflowTables.length));
    });

    test('关键字段按 d.ts 映射类型与主键', () {
      final db = openEngineDb(':memory:');
      addTearDown(db.close);

      final projectColumns = _columns(db, 'o_project');
      expect(projectColumns['id']!.type, 'INTEGER');
      expect(projectColumns['id']!.pk, 1);
      expect(projectColumns['name']!.type, 'TEXT');

      final vendorColumns = _columns(db, 'o_vendorConfig');
      expect(vendorColumns['id']!.type, 'TEXT');
      expect(vendorColumns['id']!.pk, 1);

      final skillColumns = _columns(db, 'o_skillList');
      expect(skillColumns['id']!.type, 'TEXT');
      expect(skillColumns['id']!.pk, 1);
      expect(skillColumns['state']!.type, 'INTEGER');

      final taskColumns = _columns(db, 'o_tasks');
      expect(
          taskColumns.keys,
          containsAll([
            'state',
            'reason',
            'relatedObjects',
            'taskClass',
            'startTime',
            'model',
            'projectId',
            'describe',
          ]));

      final storyboardColumns = _columns(db, 'o_storyboard');
      expect(
          storyboardColumns.keys,
          containsAll([
            'audioAssetId',
            'audioText',
            'audioPath',
            'audioState',
            'audioError',
          ]));

      final videoTrackColumns = _columns(db, 'o_videoTrack');
      expect(
          videoTrackColumns.keys,
          containsAll([
            'duration',
            'transition',
            'filterPreset',
          ]));

      final timelineClipColumns = _columns(db, 'o_timelineClip');
      expect(
          timelineClipColumns.keys,
          containsAll([
            'projectId',
            'scriptId',
            'assetId',
            'filePath',
            'lane',
            'startMs',
            'durationMs',
            'opacity',
          ]));

      final memoryVectorColumns = _columns(db, _legacyVectorTable);
      expect(memoryVectorColumns['memoryId']!.type, 'TEXT');
      expect(memoryVectorColumns['memoryId']!.pk, 1);
      expect(
          memoryVectorColumns.keys,
          containsAll([
            'isolationKey',
            'type',
            'provider',
            'model',
            'dimension',
            'vector',
            'updatedAt',
          ]));
    });

    test('计划指定索引存在', () {
      final db = openEngineDb(':memory:');
      addTearDown(db.close);

      final indexes = db
          .select("SELECT name FROM sqlite_master WHERE type='index'")
          .map((row) => row['name'] as String)
          .toSet();

      expect(
          indexes,
          containsAll([
            'idx_o_novel_project_chapter',
            'idx_o_eventChapter_event',
            'idx_o_eventChapter_novel',
            'idx_o_scriptAssets_script',
            'idx_o_tasks_project_state',
            'idx_o_timelineClip_script',
            _legacyVectorScopeIndex,
          ]));
    });

    test('打开旧版本磁盘库会删库重建但不碰 media 目录', () {
      final dir = Directory.systemTemp.createTempSync('dramaflow-db-v6-');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final dbPath = p.join(dir.path, 'dramaflow.sqlite');
      final mediaDir = Directory(p.join(dir.path, 'media', 'keep'));
      mediaDir.createSync(recursive: true);
      File(p.join(mediaDir.path, 'asset.txt')).writeAsStringSync('keep');

      final old = sqlite3.open(dbPath);
      old.execute('CREATE TABLE legacy_data (id INTEGER PRIMARY KEY)');
      old.execute('INSERT INTO legacy_data (id) VALUES (1)');
      old.execute('PRAGMA user_version = 2');
      old.close();
      File('$dbPath-wal').writeAsStringSync('wal');
      File('$dbPath-shm').writeAsStringSync('shm');

      final db = openEngineDb(dbPath);
      addTearDown(db.close);

      expect(
          db.select('PRAGMA user_version').first.values.first, schemaVersion);
      expect(
        db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='legacy_data'",
        ),
        isEmpty,
      );
      if (File('$dbPath-wal').existsSync()) {
        expect(File('$dbPath-wal').readAsBytesSync(), isNot([119, 97, 108]));
      }
      if (File('$dbPath-shm').existsSync()) {
        expect(File('$dbPath-shm').readAsBytesSync(), isNot([115, 104, 109]));
      }
      expect(
          File(p.join(mediaDir.path, 'asset.txt')).readAsStringSync(), 'keep');
    });
  });
}

Map<String, _Column> _columns(Database db, String table) => {
      for (final row in db.select('PRAGMA table_info($table)'))
        row['name'] as String: _Column(
          type: row['type'] as String,
          pk: row['pk'] as int,
        ),
    };

class _Column {
  final String type;
  final int pk;

  const _Column({required this.type, required this.pk});
}
