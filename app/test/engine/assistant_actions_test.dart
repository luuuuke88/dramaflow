import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/src/engine/assistant_actions.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/novel.dart';
import 'package:dramaflow/src/engine/novel_parse.dart';
import 'package:dramaflow/src/engine/project_notes.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
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
    dir = Directory.systemTemp.createTempSync('dramaflow-actions-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '动作测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('assistantActions 注册表', () {
    test('12 个动作齐全且金钱/破坏标记正确', () {
      final actions = assistantActions();
      final byName = {for (final a in actions) a.name: a};
      expect(
          byName.keys,
          containsAll([
            'get_status',
            'generate_events',
            'extract_assets',
            'generate_storyboards',
            'generate_shot_images',
            'generate_videos',
            'bind_audio',
            'compose_episode',
            'write_script',
            'note_save',
            'note_search',
            'note_delete',
          ]));
      expect(byName['generate_events']!.costsMoney, isTrue);
      expect(byName['generate_videos']!.costsMoney, isTrue);
      expect(byName['get_status']!.costsMoney, isFalse);
      expect(byName['compose_episode']!.costsMoney, isFalse,
          reason: '合成走本地合成器，不花供应商的钱');
      expect(byName['write_script']!.destructive, isTrue);
      expect(byName['note_delete']!.destructive, isTrue);
      expect(byName['note_save']!.destructive, isFalse);
      expect(byName['generate_events']!.taskClass, 'event_generation');
      expect(byName['generate_videos']!.taskClass, 'video_generation');
    });
  });

  group('normalizeActionArgs 通用归一化', () {
    final schema = <String, dynamic>{
      'scriptIds': {'type': 'array'},
      'novelIds': {'type': 'array'},
      'prompt': {'type': 'string'},
    };

    test('snake_case → camelCase', () {
      final out = normalizeActionArgs({
        'script_ids': [1, 2]
      }, schema);
      expect(out['scriptIds'], [1, 2]);
    });

    test('单数键 → 复数期望键', () {
      final out = normalizeActionArgs({'scriptId': 3}, schema);
      expect(out['scriptIds'], 3);
    });

    test('显式空数组视同未传（沿用既有修复语义）', () {
      final out = normalizeActionArgs({'novelIds': <int>[]}, schema);
      expect(out.containsKey('novelIds'), isFalse);
    });

    test('中文别名命中', () {
      final out = normalizeActionArgs({'剧本id': 5}, schema);
      expect(out['scriptIds'], 5);
    });

    test('未知键丢弃、已知键类型原样保留', () {
      final out =
          normalizeActionArgs({'unknown_field': 'x', 'prompt': '青霜剑'}, schema);
      expect(out.containsKey('unknown_field'), isFalse);
      expect(out['prompt'], '青霜剑');
    });

    test('精确键直通优先', () {
      final out = normalizeActionArgs({
        'scriptIds': [9]
      }, schema);
      expect(out['scriptIds'], [9]);
    });
  });

  group('runAssistantAction 分发', () {
    test('generate_events 入队 event_generation（默认取未生成章节）', () async {
      engine.addNovels(projectId, const [
        ChapterItem(index: 1, reel: '正文卷', chapter: '一', chapterData: 'x'),
      ]);
      final summary = await runAssistantAction(
          engine, projectId, 'generate_events', const {});
      expect(summary, contains('1'));
      final tasks = db.select(
          "SELECT taskClass FROM o_tasks WHERE projectId=?", [projectId]);
      expect(tasks.map((t) => t['taskClass']), contains('event_generation'));
    });

    test('write_script 分发到 updateScript', () async {
      final scriptId =
          engine.addScript(projectId: projectId, name: '一', content: '旧内容');
      await runAssistantAction(engine, projectId, 'write_script',
          {'scriptId': scriptId, 'content': '新内容'});
      expect(engine.scripts(projectId).single.content, '新内容');
    });

    test('note_save/note_search 分发到项目笔记', () async {
      await runAssistantAction(
          engine, projectId, 'note_save', {'name': '设定', 'content': '林朝雪的青霜剑'});
      expect(engine.projectNotes(projectId), hasLength(1));
      final found = await runAssistantAction(
          engine, projectId, 'note_search', {'query': '青霜'});
      expect(found, contains('青霜剑'));
    });

    test('get_status 汇总各阶段进度', () async {
      final summary =
          await runAssistantAction(engine, projectId, 'get_status', const {});
      expect(summary, contains('章节'));
      expect(summary, contains('剧本'));
    });

    test('generate_videos uses the same local preflight as the workbench',
        () async {
      db.execute(
        'INSERT INTO o_vendorConfig (id,enable,inputValues,models) '
        'VALUES (?,?,?,?)',
        [
          'volcengine',
          1,
          '{}',
          jsonEncode([
            {
              'modelId': 'test-video',
              'kind': 'video',
              'enabled': true,
              'capabilities': {
                'video': {
                  'modes': ['first_frame'],
                  'references': {'image': 1},
                  'durations': [5],
                  'resolutions': ['720p'],
                  'ratios': ['16:9'],
                  'audio': 'none',
                },
              },
            },
          ]),
        ],
      );
      db.execute(
        "INSERT INTO o_setting (key,value) VALUES "
        "('binding.shot_video','volcengine:test-video')",
      );
      final scriptId =
          engine.addScript(projectId: projectId, name: '一', content: 'x');
      engine.addStoryboard(projectId: projectId, scriptId: scriptId);

      final result = await runAssistantAction(
          engine, projectId, 'generate_videos', {'scriptId': scriptId});

      expect(result, contains('无法提交视频生成'));
      expect(db.select('SELECT id FROM o_tasks'), isEmpty);
    });

    test('未知动作返回错误文案不崩溃', () async {
      final summary =
          await runAssistantAction(engine, projectId, 'no_such_tool', const {});
      expect(summary, contains('no_such_tool'));
    });
  });
}
