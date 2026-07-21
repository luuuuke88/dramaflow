import 'dart:io';

import 'package:dramaflow/src/engine/assistant_chat.dart';
import 'package:dramaflow/src/engine/assistant_deploy.dart';
import 'package:dramaflow/src/engine/assistant_skill_library.dart';
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
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-skills-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '技能测试');
  });

  AssistantSkill importSkill(String name, String description, String body) {
    final file = File(p.join(dir.path, '$name.md'))
      ..writeAsStringSync(
        '---\nname: $name\ndescription: $description\n---\n$body',
      );
    return engine.saveMarkdownAssistantSkill(filePath: file.path);
  }

  AssistantSkill importSkillPackage(
    String name, {
    required String body,
    String? resource,
  }) {
    final package = Directory(p.join(dir.path, '$name-package'))
      ..createSync();
    final entry = File(p.join(package.path, 'SKILL.md'))
      ..writeAsStringSync(
        '---\nname: $name\ndescription: 运镜规范\n---\n$body',
      );
    if (resource != null) {
      File(p.join(package.path, resource)).writeAsStringSync('资源：$resource');
    }
    return engine.saveMarkdownAssistantSkill(filePath: entry.path);
  }

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('assistant_skills', () {
    test('14 个内置动作自动播种为可开关技能', () {
      final skills = engine.assistantSkills();
      final toolIds = skills
          .where((s) => s.type == assistantToolSkillType)
          .map((s) => s.id)
          .toSet();
      expect(toolIds, contains('get_status'));
      expect(toolIds, contains('generate_scripts'));
      expect(toolIds, contains('generate_derived_assets'));
      expect(toolIds, contains('generate_videos'));
      expect(toolIds, hasLength(14));
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

    test('markdown 技能导入后独立于被删除的源文件', () {
      final f = File(p.join(dir.path, 'style_guide.md'))
        ..writeAsStringSync('---\nname: style_guide\ndescription: 画风指南\n---\n'
            '所有画面统一水墨风。');
      final saved = engine.saveMarkdownAssistantSkill(filePath: f.path);
      expect(saved.type, markdownAssistantSkillType);

      final contexts = engine.assistantSkillContexts();
      expect(contexts.single, contains('水墨'));
      expect(contexts.single, contains('style_guide'));

      f.deleteSync();
      expect(engine.assistantSkillContexts().single, contains('水墨'),
          reason: '应用工作区副本不能依赖用户原始文件继续存在');
    });

    test('技能包资源随 SKILL.md 导入且拒绝路径穿越', () {
      final skillDir = Directory(p.join(dir.path, 'pack'))..createSync();
      final f = File(p.join(skillDir.path, 'skill.md'))
        ..writeAsStringSync('---\nname: pack\n---\nbody');
      File(p.join(skillDir.path, 'extra.md')).writeAsStringSync('资源内容');
      engine.saveMarkdownAssistantSkill(filePath: f.path);

      f.deleteSync();
      File(p.join(skillDir.path, 'extra.md')).deleteSync();

      expect(engine.readAssistantSkillFile('pack', 'extra.md'), '资源内容');
      expect(() => engine.readAssistantSkillFile('pack', '../../etc/passwd'),
          throwsA(isA<EngineException>()));
    });

    test('遗留外部路径技能不再进入上下文或读取资源', () {
      final external = File(p.join(dir.path, 'external.md'))
        ..writeAsStringSync('---\nname: legacy_external\n---\n不得读取');
      db.execute(
        'INSERT INTO o_skillList '
        '(id,name,description,state,type,createTime,updateTime,path,md5,embedding) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          'legacy_external',
          'legacy_external',
          '',
          1,
          markdownAssistantSkillType,
          1,
          1,
          external.path,
          '',
          '',
        ],
      );

      expect(engine.assistantSkillContexts(), isEmpty);
      expect(() => engine.readAssistantSkillFile('legacy_external', 'extra.md'),
          throwsA(isA<EngineException>()));
    });

    group('on-demand skill runtime', () {
      test('目录仅暴露启用技能元数据，不包含正文', () {
        final skill = importSkill('camera_guide', '运镜规范', '绝密正文');

        final catalog = engine.assistantSkillCatalog();
        expect(catalog, hasLength(1));
        expect(catalog.single.id, skill.id);
        expect(catalog.single.name, 'camera_guide');
        expect(catalog.single.description, '运镜规范');
      });

      test('激活技能按项目和家族持久化，重复激活不重复记录', () {
        importSkillPackage('camera_guide', body: '镜头规则', resource: 'notes.md');

        final reply = engine.activateAssistantSkill(
          projectId,
          family: assistantFamilyScript,
          skillName: 'camera_guide',
        );
        engine.activateAssistantSkill(
          projectId,
          family: assistantFamilyScript,
          skillName: 'camera_guide',
        );

        expect(reply, contains('镜头规则'));
        expect(reply, contains('notes.md'));
        expect(
          engine.activatedAssistantSkillIds(
            projectId,
            family: assistantFamilyScript,
          ),
          {'camera_guide'},
        );
        expect(
          engine.activatedAssistantSkillIds(
            projectId,
            family: assistantFamilyProduction,
          ),
          isEmpty,
        );
      });

      test('资源读取必须先激活，且符号链接不能逃逸技能包', () {
        importSkillPackage('camera_guide', body: '镜头规则', resource: 'notes.md');

        expect(
          () => engine.readActivatedAssistantSkillFile(
            projectId,
            family: assistantFamilyScript,
            skillName: 'camera_guide',
            relativePath: 'notes.md',
          ),
          throwsA(isA<EngineException>()),
        );
        engine.activateAssistantSkill(
          projectId,
          family: assistantFamilyScript,
          skillName: 'camera_guide',
        );
        expect(
          engine.readActivatedAssistantSkillFile(
            projectId,
            family: assistantFamilyScript,
            skillName: 'camera_guide',
            relativePath: 'notes.md',
          ),
          '资源：notes.md',
        );

        final packageRoot =
            File(engine.managedAssistantSkillPath('camera_guide')).parent;
        final outside = File(p.join(dir.path, 'outside.md'))
          ..writeAsStringSync('不可读取');
        Link(p.join(packageRoot.path, 'escape.md')).createSync(outside.path);
        expect(
          () => engine.readActivatedAssistantSkillFile(
            projectId,
            family: assistantFamilyScript,
            skillName: 'camera_guide',
            relativePath: 'escape.md',
          ),
          throwsA(isA<EngineException>()),
        );
        expect(
          () => engine.readActivatedAssistantSkillFile(
            projectId,
            family: assistantFamilyScript,
            skillName: 'camera_guide',
            relativePath: '../outside.md',
          ),
          throwsA(isA<EngineException>()),
        );
      });

      test('禁用技能不能激活，清空家族状态不影响另一个家族', () {
        final skill = importSkill('camera_guide', '运镜规范', '镜头规则');
        engine.updateAssistantSkill(skill.id, enabled: false);
        expect(
          () => engine.activateAssistantSkill(
            projectId,
            family: assistantFamilyScript,
            skillName: skill.id,
          ),
          throwsA(isA<EngineException>()),
        );

        engine.updateAssistantSkill(skill.id, enabled: true);
        engine.activateAssistantSkill(
          projectId,
          family: assistantFamilyScript,
          skillName: skill.id,
        );
        engine.activateAssistantSkill(
          projectId,
          family: assistantFamilyProduction,
          skillName: skill.id,
        );
        engine.clearActivatedAssistantSkills(
          projectId,
          family: assistantFamilyScript,
        );
        expect(
          engine.activatedAssistantSkillIds(
            projectId,
            family: assistantFamilyScript,
          ),
          isEmpty,
        );
        expect(
          engine.activatedAssistantSkillIds(
            projectId,
            family: assistantFamilyProduction,
          ),
          {skill.id},
        );
      });

      test('技能正文缺失时激活失败且不写入陈旧会话状态', () {
        final skill = importSkill('camera_guide', '运镜规范', '镜头规则');
        File(engine.managedAssistantSkillPath(skill.id)).deleteSync();

        expect(
          () => engine.activateAssistantSkill(
            projectId,
            family: assistantFamilyScript,
            skillName: skill.id,
          ),
          throwsA(isA<EngineException>()),
        );
        expect(
          engine.activatedAssistantSkillIds(
            projectId,
            family: assistantFamilyScript,
          ),
          isEmpty,
        );
      });
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
