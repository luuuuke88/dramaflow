import 'dart:io';

import 'package:dramaflow/src/engine/assistant_deploy.dart';
import 'package:dramaflow/src/engine/assistant_skills.dart';
import 'package:dramaflow/src/engine/assistant_stage_registry.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
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

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-skills-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: false),
    );
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('assistant_skills', () {
    test('13 个内置动作自动播种为可开关技能', () {
      final skills = engine.assistantSkills();
      final toolIds = skills
          .where((s) => s.type == assistantToolSkillType)
          .map((s) => s.id)
          .toSet();
      expect(toolIds, contains('get_status'));
      expect(toolIds, contains('generate_scripts'));
      expect(toolIds, contains('generate_videos'));
      expect(toolIds, hasLength(13));
      expect(skills.every((s) => s.enabled), isTrue, reason: '默认全启用');
    });

    test('关闭技能后 enabledAssistantActionNames 过滤之', () {
      engine.updateAssistantSkill('generate_videos', enabled: false);
      final enabled = engine.enabledAssistantActionNames();
      expect(enabled, isNot(contains('generate_videos')));
      expect(enabled, contains('get_status'));
      engine.updateAssistantSkill('generate_videos', enabled: true);
      expect(engine.enabledAssistantActionNames(), contains('generate_videos'));
    });

    test('custom-js-agent 类型的旧行不出现在技能列表', () {
      db.execute(
        "INSERT INTO o_skillList (id,name,description,state,type,createTime,updateTime,path,md5,embedding) "
        "VALUES ('legacy_js','旧JS技能','x',1,'custom-js-agent',1,1,'','','')",
      );
      expect(engine.assistantSkills().any((s) => s.id == 'legacy_js'), isFalse);
    });

    test('markdown 技能导入/正文注入/文件缺失时静默跳过', () {
      final f = File(p.join(dir.path, 'style_guide.md'))
        ..writeAsStringSync('---\nname: style_guide\ndescription: 画风指南\n---\n'
            '所有画面统一水墨风。');
      final saved = engine.saveMarkdownAssistantSkill(filePath: f.path);
      expect(saved.type, markdownAssistantSkillType);

      final contexts = engine.assistantSkillContexts();
      expect(contexts.single, contains('水墨'));
      expect(contexts.single, contains('style_guide'));

      f.deleteSync();
      expect(engine.assistantSkillContexts(), isEmpty, reason: '文件被删后跳过，不抛异常');
    });

    test('readAssistantSkillFile 拒绝路径穿越', () {
      final skillDir = Directory(p.join(dir.path, 'pack'))..createSync();
      final f = File(p.join(skillDir.path, 'skill.md'))
        ..writeAsStringSync('---\nname: pack\n---\nbody');
      File(p.join(skillDir.path, 'extra.md')).writeAsStringSync('资源内容');
      engine.saveMarkdownAssistantSkill(filePath: f.path);

      expect(engine.readAssistantSkillFile('pack', 'extra.md'), '资源内容');
      expect(() => engine.readAssistantSkillFile('pack', '../../etc/passwd'),
          throwsA(isA<EngineException>()));
    });
  });

  group('assistant_deploy', () {
    test('两个家族基座自动播种且可更新参数', () {
      final deployments = engine.assistantDeployments();
      expect(deployments.map((d) => d.key),
          containsAll(['scriptAgent', 'productionAgent']));
      expect(deployments, hasLength(2));

      engine.updateAssistantDeployment('scriptAgent',
          maxOutputTokens: 4000, temperature: 50);
      final updated = engine
          .assistantDeployments()
          .singleWhere((d) => d.key == 'scriptAgent');
      expect(updated.maxOutputTokens, 4000);
      expect(updated.temperature, 50);
    });

    test('未知阶段更新抛 errModelMissing', () {
      expect(
        () => engine.updateAssistantDeployment('no_such_stage',
            maxOutputTokens: 1000),
        throwsA(isA<EngineException>()),
      );
    });

    test('注册表回退：scriptAgent→script_gen，未知键→自身', () {
      expect(assistantStageFallback('scriptAgent'), 'script_gen');
      expect(assistantStageFallback('productionAgent'), 'storyboard_gen');
      expect(assistantStageFallback('anything_else'), 'anything_else');
    });
  });
}
