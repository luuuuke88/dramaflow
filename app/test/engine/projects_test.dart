import 'dart:io';

import 'package:dio/dio.dart';

import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-projects-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('projects/addProject/editProject 完整字段 CRUD', () {
    final id = engine.addProject(
      projectType: 'series',
      name: '测试项目',
      intro: '简介',
      type: '短剧',
      artStyle: '电影感',
      directorManual: '导演手册',
      videoRatio: '16:9',
      imageModel: 'img-model',
      videoModel: 'vid-model',
      imageQuality: 'high',
      mode: 'normal',
    );

    var project = engine.projects().single;
    expect(project.id, id);
    expect(project.projectType, 'series');
    expect(project.name, '测试项目');
    expect(project.intro, '简介');
    expect(project.type, '短剧');
    expect(project.artStyle, '电影感');
    expect(project.directorManual, '导演手册');
    expect(project.videoRatio, '16:9');
    expect(project.imageModel, 'img-model');
    expect(project.videoModel, 'vid-model');
    expect(project.imageQuality, 'high');
    expect(project.mode, 'normal');

    engine.editProject(
      id,
      name: '改名',
      intro: '新简介',
      type: '动画',
      artStyle: '水彩',
      directorManual: '新版导演手册',
      videoRatio: '9:16',
      imageModel: 'img-2',
      videoModel: 'vid-2',
      imageQuality: 'standard',
      mode: 'fast',
    );

    project = engine.projects().single;
    expect(project.name, '改名');
    expect(project.intro, '新简介');
    expect(project.type, '动画');
    expect(project.artStyle, '水彩');
    expect(project.directorManual, '新版导演手册');
    expect(project.videoRatio, '9:16');
    expect(project.imageModel, 'img-2');
    expect(project.videoModel, 'vid-2');
    expect(project.imageQuality, 'standard');
    expect(project.mode, 'fast');
  });

  test('projectStats 按项目汇总章节/剧本/素材/分镜数量', () {
    final projectId = engine.addProject(projectType: 'series', name: '统计');
    final otherId = engine.addProject(projectType: 'series', name: '其他');

    db.execute(
      'INSERT INTO o_novel (projectId,chapterIndex,chapter) VALUES (?,?,?)',
      [projectId, 1, '第一章'],
    );
    db.execute(
      'INSERT INTO o_novel (projectId,chapterIndex,chapter) VALUES (?,?,?)',
      [projectId, 2, '第二章'],
    );
    db.execute(
      'INSERT INTO o_script (projectId,name,content) VALUES (?,?,?)',
      [projectId, '第一集', 'content'],
    );
    final scriptId = db.lastInsertRowId;
    db.execute(
      'INSERT INTO o_script (projectId,name,content) VALUES (?,?,?)',
      [otherId, '其他剧本', 'content'],
    );
    db.execute(
      'INSERT INTO o_assets (projectId,name,type) VALUES (?,?,?)',
      [projectId, '角色', 'role'],
    );
    db.execute(
      'INSERT INTO o_assets (projectId,name,type) VALUES (?,?,?)',
      [projectId, '场景', 'scene'],
    );
    db.execute(
      'INSERT INTO o_storyboard (projectId,scriptId,prompt) VALUES (?,?,?)',
      [projectId, scriptId, 'prompt'],
    );

    final stats = engine.projectStats();

    expect(stats[projectId]!.chapters, 2);
    expect(stats[projectId]!.scripts, 1);
    expect(stats[projectId]!.assets, 2);
    expect(stats[projectId]!.storyboards, 1);
    expect(stats[otherId]!.chapters, 0);
    expect(stats[otherId]!.scripts, 1);
    expect(stats[otherId]!.assets, 0);
    expect(stats[otherId]!.storyboards, 0);
  });

  test('deleteProject 按计划级联清除项目关联表与媒体目录', () {
    final projectId = engine.addProject(projectType: 'series', name: '待删除');
    final otherId = engine.addProject(projectType: 'series', name: '保留');
    _insertCascadeGraph(db, projectId);
    _insertCascadeGraph(db, otherId);
    final mediaFile = File(p.join(dir.path, 'media', '$projectId', 'x.png'));
    mediaFile.parent.createSync(recursive: true);
    mediaFile.writeAsStringSync('media');

    engine.deleteProject(projectId);

    for (final table in [
      'o_agentWorkData',
      'o_novel',
      'o_script',
      'o_scriptAssets',
      'o_storyboard',
      'o_assets2Storyboard',
      'o_image',
      'o_assets',
      'o_tasks',
      'o_timelineClip',
      'o_videoTrack',
      'o_video',
    ]) {
      expect(
        _count(db, table, projectId),
        0,
        reason: '$table should delete project rows',
      );
      expect(
        _count(db, table, otherId),
        greaterThan(0),
        reason: '$table should keep other project rows',
      );
    }
    expect(
      db.select(
        "SELECT COUNT(*) n FROM memories WHERE isolationKey LIKE ?",
        ['$projectId:%'],
      ).first['n'],
      0,
    );
    expect(
      db.select(
        "SELECT COUNT(*) n FROM memories WHERE isolationKey LIKE ?",
        ['$otherId:%'],
      ).first['n'],
      greaterThan(0),
    );
    expect(_agentMemoryCount(db, projectId), 0);
    expect(_agentMemoryCount(db, otherId), greaterThan(0));
    expect(Directory(p.join(dir.path, 'media', '$projectId')).existsSync(),
        isFalse);
    expect(
        Directory(p.join(dir.path, 'media', '$otherId')).existsSync(), isFalse);
  });
}

int _count(Database db, String table, int projectId) {
  final column = switch (table) {
    'o_scriptAssets' => 'scriptId',
    'o_assets2Storyboard' => 'storyboardId',
    'o_image' => 'assetsId',
    _ => 'projectId',
  };
  final sql = switch (table) {
    'o_scriptAssets' =>
      'SELECT COUNT(*) n FROM o_scriptAssets WHERE scriptId IN (SELECT id FROM o_script WHERE projectId=?)',
    'o_assets2Storyboard' =>
      'SELECT COUNT(*) n FROM o_assets2Storyboard WHERE storyboardId IN (SELECT id FROM o_storyboard WHERE projectId=?)',
    'o_image' =>
      'SELECT COUNT(*) n FROM o_image WHERE assetsId IN (SELECT id FROM o_assets WHERE projectId=?)',
    _ => 'SELECT COUNT(*) n FROM $table WHERE $column=?',
  };
  return db.select(sql, [projectId]).first['n'] as int;
}

int _agentMemoryCount(Database db, int projectId) => db.select(
      'SELECT COUNT(*) n FROM memories '
      'WHERE isolationKey IN (?,?) OR isolationKey LIKE ?',
      [
        'scriptAgent:$projectId',
        'productionAgent:$projectId',
        'productionAgent:$projectId:%',
      ],
    ).first['n'] as int;

void _insertCascadeGraph(Database db, int projectId) {
  db.execute(
    'INSERT INTO o_agentWorkData (projectId,key,data) VALUES (?,?,?)',
    [projectId, 'k', 'v'],
  );
  db.execute(
    'INSERT INTO o_novel (projectId,chapterIndex,chapter) VALUES (?,?,?)',
    [projectId, 1, '第一章'],
  );
  db.execute(
    'INSERT INTO o_script (projectId,name,content) VALUES (?,?,?)',
    [projectId, '剧本', 'content'],
  );
  final scriptId = db.lastInsertRowId;
  db.execute(
    'INSERT INTO o_assets (projectId,scriptId,name,type) VALUES (?,?,?,?)',
    [projectId, scriptId, '角色', 'role'],
  );
  final assetId = db.lastInsertRowId;
  db.execute(
    'INSERT INTO o_image (assetsId,filePath,state) VALUES (?,?,?)',
    [assetId, '$projectId/img.png', 'success'],
  );
  final imageId = db.lastInsertRowId;
  db.execute('UPDATE o_assets SET imageId=? WHERE id=?', [imageId, assetId]);
  db.execute(
    'INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
    [scriptId, assetId],
  );
  db.execute(
    'INSERT INTO o_storyboard (projectId,scriptId,prompt) VALUES (?,?,?)',
    [projectId, scriptId, 'prompt'],
  );
  final storyboardId = db.lastInsertRowId;
  db.execute(
    'INSERT INTO o_assets2Storyboard (assetId,storyboardId) VALUES (?,?)',
    [assetId, storyboardId],
  );
  db.execute(
    'INSERT INTO o_tasks (projectId,state,taskClass) VALUES (?,?,?)',
    [projectId, 'pending', 'event_generation'],
  );
  db.execute(
    'INSERT INTO o_videoTrack (projectId,scriptId,prompt) VALUES (?,?,?)',
    [projectId, scriptId, 'video'],
  );
  final trackId = db.lastInsertRowId;
  db.execute(
    'INSERT INTO o_video (projectId,scriptId,videoTrackId,state) VALUES (?,?,?,?)',
    [projectId, scriptId, trackId, 'success'],
  );
  db.execute(
    'INSERT INTO o_timelineClip (projectId,scriptId,filePath,lane,startMs) '
    'VALUES (?,?,?,?,?)',
    [projectId, scriptId, '$projectId/overlay.mp4', 1, 0],
  );
  db.execute(
    'INSERT INTO memories (id,content,createTime,isolationKey,type) VALUES (?,?,?,?,?)',
    ['m-$projectId', 'memory', 1, '$projectId:agent', 'text'],
  );
  db.execute(
    'INSERT INTO memories (id,content,createTime,isolationKey,type) VALUES (?,?,?,?,?)',
    [
      'script-agent-$projectId',
      'script memory',
      2,
      'scriptAgent:$projectId',
      'message'
    ],
  );
  db.execute(
    'INSERT INTO memories (id,content,createTime,isolationKey,type) VALUES (?,?,?,?,?)',
    [
      'production-agent-$projectId',
      'production memory',
      3,
      'productionAgent:$projectId',
      'message',
    ],
  );
  db.execute(
    'INSERT INTO memories (id,content,createTime,isolationKey,type) VALUES (?,?,?,?,?)',
    [
      'production-agent-episode-$projectId',
      'production scoped memory',
      4,
      'productionAgent:$projectId:episode-1',
      'summary',
    ],
  );
}

class _NoopGateway implements ProviderGateway {
  @override
  Future<TextResult> generateText(
    String system,
    String user, {
    required String stage,
    cancelToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> generateImage(
    String prompt,
    String projectId, {
    required String stage,
    cancelToken,
    List<String> referenceAbsPaths = const [],
    String? editInstruction,
    String? maskAbsPath,
    String? ratio,
    String? quality,
    String? modelOverride,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> generateVideo(
    String prompt,
    String firstFrameAbsPath,
    String projectId, {
    required String stage,
    cancelToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> generateSpeech(
    String text,
    String projectId, {
    required String stage,
    required String voice,
    CancelToken? cancelToken,
    String? format,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> generateToolJson(String system, String user,
          {required String stage,
          required String toolName,
          required Map<String, dynamic> schema,
          CancelToken? cancelToken}) async =>
      const <String, dynamic>{};

  @override
  Future<AgentTurnResult> generateAgentTurn(
    String system,
    List<Map<String, String>> messages,
    List<AgentToolDef> tools, {
    required String stage,
    CancelToken? cancelToken,
  }) async =>
      const AgentTurnResult.text('');
}
