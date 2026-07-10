import 'dart:io';

import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/prompt_resolver.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-prompt-resolver-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    engine.saveVisualManual(
      name: 'Ink',
      pack: 'ink_pack',
      data: const {'director_storyboard': 'VISUAL'},
    );
    engine.saveDirectorManual(
      name: 'Fast Cut',
      pack: 'fast_cut',
      data: const {
        'director_storyboard_table_narrative': 'DIRECTOR',
      },
    );
    db.execute(
      'INSERT INTO o_prompt (name,type,data,useData) VALUES (?,?,?,?)',
      ['storyboard_gen', 'storyboard_gen', 'BASE DEFAULT', 'BASE'],
    );
    db.execute(
      'INSERT INTO o_setting (key,value) VALUES (?,?)',
      ['binding.storyboard_gen', 'volcengine:seedance'],
    );
    db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      [
        'volcengine',
        'seedance',
        'seedance2Multi-parameterMode.md',
        'video/seedance2Multi-parameterMode.md',
        'MODEL',
      ],
    );
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('按基础、视觉、导演、模型的固定顺序解析并记录稳定来源', () {
    final projectId = engine.addProject(
      projectType: 'drama',
      name: 'p',
      artStyle: 'ink_pack',
      directorManual: 'fast_cut',
    );
    db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      [
        'volcengine',
        'seedance',
        'seedance2Multi-parameterMode.md',
        'video/seedance2Multi-parameterMode.md',
        'MODEL NEWEST',
      ],
    );

    final resolution = engine.resolvePrompt(
      projectId: projectId,
      basePromptKey: 'storyboard_gen',
      visualSection: 'director_storyboard',
      directorSection: 'director_storyboard_table_narrative',
      modelStage: 'storyboard_gen',
      modelPromptPath: 'video/seedance2Multi-parameterMode.md',
    );

    expect(
      resolution.system,
      'BASE\n\nVISUAL\n\nDIRECTOR\n\nMODEL NEWEST',
    );
    expect(resolution.sources.map((source) => source.id), [
      'base:storyboard_gen',
      'visual:ink_pack:director_storyboard',
      'director:fast_cut:director_storyboard_table_narrative',
      'model:volcengine:seedance:video/seedance2Multi-parameterMode.md',
    ]);
    expect(
      resolution.toTaskJson()['promptSources'],
      everyElement(
        allOf(
          containsPair('id', isA<String>()),
          containsPair('kind', isA<String>()),
          containsPair('version', matches(RegExp(r'^[0-9a-f]{64}$'))),
          isNot(contains('content')),
        ),
      ),
    );

    final before = resolution.sources[1].version;
    engine.saveVisualManual(
      name: 'Ink',
      pack: 'ink_pack',
      data: const {'director_storyboard': 'VISUAL EDITED'},
    );
    final edited = engine.resolvePrompt(
      projectId: projectId,
      basePromptKey: 'storyboard_gen',
      visualSection: 'director_storyboard',
    );
    expect(edited.sources[1].version, isNot(before));
    expect(promptContentHash('VISUAL'), before);
  });

  test('缺少请求的手册章节时在付费调用前返回明确错误', () {
    final projectId = engine.addProject(
      projectType: 'drama',
      name: 'p',
      artStyle: 'ink_pack',
    );

    expect(
      () => engine.resolvePrompt(
        projectId: projectId,
        basePromptKey: 'storyboard_gen',
        visualSection: 'art_scene',
      ),
      throwsA(
        isA<EngineException>()
            .having((error) => error.errKey, 'errKey', errPromptMissing)
            .having(
              (error) => error.errParams['type'],
              'type',
              'visual:ink_pack:art_scene',
            ),
      ),
    );
  });

  test('重复基础模板按最新 id 确定性选择', () {
    final projectId = engine.addProject(
      projectType: 'drama',
      name: 'p',
    );
    db.execute(
      'INSERT INTO o_prompt (name,type,data,useData) VALUES (?,?,?,NULL)',
      ['storyboard_gen', 'storyboard_gen', 'BASE NEWEST'],
    );

    final resolution = engine.resolvePrompt(
      projectId: projectId,
      basePromptKey: 'storyboard_gen',
    );

    expect(resolution.system, 'BASE NEWEST');
    expect(resolution.sources.single.version, promptContentHash('BASE NEWEST'));
  });
}
