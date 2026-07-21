import 'dart:io';

import 'package:dramaflow/src/engine/assistant_skill_library.dart';
import 'package:dramaflow/src/engine/assistant_skills.dart';
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
    dir = Directory.systemTemp.createTempSync('dramaflow-skill-library-');
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

  test('导入复制到应用技能根，源文件消失后仍可读取', () {
    final sourceDir = Directory(p.join(dir.path, 'picked'))..createSync();
    final source = File(p.join(sourceDir.path, 'SKILL.md'))
      ..writeAsStringSync('''---
name: camera_guide
description: 运镜规范
---
景别由远到近，保持轴线一致。
''');

    final skill = engine.importMarkdownAssistantSkill(source.path);

    expect(
      p.isWithin(engine.assistantSkillLibraryRoot(), skill.path),
      isTrue,
      reason: 'root=${engine.assistantSkillLibraryRoot()} path=${skill.path}',
    );
    expect(File(skill.path).readAsStringSync(), contains('保持轴线一致'));
    expect(
      db.select(
          'SELECT md5 FROM o_skillList WHERE id=?', [skill.id]).single['md5'],
      isNotEmpty,
    );

    source.deleteSync();
    expect(engine.readManagedAssistantSkill(skill.id), contains('保持轴线一致'));
  });

  test('重扫精确报告新增、更新、丢失和无效技能文件', () {
    File source(String name, String body) {
      final picked = Directory(p.join(dir.path, 'picked-$name'))
        ..createSync(recursive: true);
      return File(p.join(picked.path, 'SKILL.md'))..writeAsStringSync(body);
    }

    final changed = engine.importMarkdownAssistantSkill(source('changed', '''---
name: changed_skill
description: 初版
---
初始正文
''').path);
    final missing = engine.importMarkdownAssistantSkill(source('missing', '''---
name: missing_skill
---
将被删除
''').path);

    File(changed.path).writeAsStringSync('''---
name: changed_skill
description: 新版
---
更新后的正文
''');
    File(missing.path).deleteSync();

    final root = Directory(engine.assistantSkillLibraryRoot());
    final addedDir = Directory(p.join(root.path, 'added_skill'))
      ..createSync(recursive: true);
    File(p.join(addedDir.path, 'SKILL.md')).writeAsStringSync('''---
name: added_skill
description: 新增
---
新增正文
''');
    final invalidDir = Directory(p.join(root.path, 'invalid'))
      ..createSync(recursive: true);
    File(p.join(invalidDir.path, 'SKILL.md')).writeAsStringSync('''---
name: 不可用技能
---
无效
''');

    final result = engine.scanMarkdownAssistantSkills();

    expect(result.added.map((item) => item.id), contains('added_skill'));
    expect(result.updated.map((item) => item.id), contains('changed_skill'));
    expect(result.missing.map((item) => item.id), contains('missing_skill'));
    expect(result.invalid.map((item) => item.path),
        contains(p.join(invalidDir.path, 'SKILL.md')));
  });

  test('托管技能编辑同步内容和元数据，但拒绝改变稳定 ID', () {
    final sourceDir = Directory(p.join(dir.path, 'picked-edit'))..createSync();
    final source = File(p.join(sourceDir.path, 'SKILL.md'))
      ..writeAsStringSync('''---
name: camera_guide
description: 初版
---
旧正文
''');
    final skill = engine.importMarkdownAssistantSkill(source.path);
    final before = db.select(
        'SELECT md5 FROM o_skillList WHERE id=?', [skill.id]).single['md5'];

    engine.saveManagedAssistantSkill(skill.id, '''---
name: camera_guide
description: 改版
---
新正文
''');

    expect(engine.readManagedAssistantSkill(skill.id), contains('新正文'));
    final row = db.select('SELECT description,md5 FROM o_skillList WHERE id=?',
        [skill.id]).single;
    expect(row['description'], '改版');
    expect(row['md5'], isNot(before));
    expect(
      () => engine.saveManagedAssistantSkill(skill.id, '''---
name: different_skill
---
不能改 ID
'''),
      throwsA(isA<EngineException>()),
    );
  });

  test('解析器保留既有 YAML 折叠描述语义', () {
    final parsed = parseAssistantSkillMarkdown('''---
name: camera_guide
description: >
  先建立空间关系，
  再推进人物动作。
---
正文
''', fallbackName: 'fallback');

    expect(parsed.description, '先建立空间关系， 再推进人物动作。');
    expect(parsed.body, '正文');
  });

  test('重扫不会把技能包内的 Markdown 资源注册成独立技能', () {
    final sourceDir = Directory(p.join(dir.path, 'picked-resource'))
      ..createSync();
    final source = File(p.join(sourceDir.path, 'SKILL.md'))
      ..writeAsStringSync('''---
name: camera_guide
---
主技能正文
''');
    File(p.join(sourceDir.path, 'shot-notes.md')).writeAsStringSync('资源正文');
    engine.importMarkdownAssistantSkill(source.path);

    final result = engine.scanMarkdownAssistantSkills();

    expect(result.added, isEmpty);
    expect(
      engine.assistantSkills().map((skill) => skill.id),
      isNot(contains('shot-notes')),
    );
  });

  test('已托管但 frontmatter 无效的文件不会同时报告为丢失', () {
    final sourceDir = Directory(p.join(dir.path, 'picked-invalid'))
      ..createSync();
    final source = File(p.join(sourceDir.path, 'SKILL.md'))
      ..writeAsStringSync('---\nname: recoverable_skill\n---\n原内容');
    final skill = engine.importMarkdownAssistantSkill(source.path);
    File(skill.path).writeAsStringSync('---\nname: 不可用\n---\n坏内容');

    final result = engine.scanMarkdownAssistantSkills();

    expect(result.invalid.map((item) => item.path), contains(skill.path));
    expect(result.missing.map((item) => item.id), isNot(contains(skill.id)));
  });

  group('managed skill library files', () {
    ManagedAssistantSkill importPackage(String id) {
      final sourceDir = Directory(p.join(dir.path, 'picked-$id'))..createSync();
      final source = File(p.join(sourceDir.path, 'SKILL.md'))
        ..writeAsStringSync('''---
name: $id
description: 初版
---
技能正文
''');
      return engine.importMarkdownAssistantSkill(source.path);
    }

    test('递归列出稳定排序的托管 Markdown，忽略二进制和符号链接', () {
      final skill = importPackage('camera_guide');
      final root = File(engine.managedAssistantSkillPath(skill.id)).parent;
      File(p.join(root.path, 'notes.md')).writeAsStringSync('笔记');
      Directory(p.join(root.path, 'references')).createSync();
      File(p.join(root.path, 'references', 'shot-list.md'))
          .writeAsStringSync('镜头');
      File(p.join(root.path, 'photo.png')).writeAsBytesSync([0]);
      final outside = File(p.join(dir.path, 'outside.md'))
        ..writeAsStringSync('外部');
      Link(p.join(root.path, 'escape.md')).createSync(outside.path);

      expect(
          engine.managedSkillLibraryFiles().map((file) => file.displayPath), [
        'camera_guide/SKILL.md',
        'camera_guide/notes.md',
        'camera_guide/references/shot-list.md',
      ]);
    });

    test('单个已登记技能文件缺失时仍列出其余可用包', () {
      final missing = importPackage('missing_skill');
      final available = importPackage('available_skill');
      File(missing.path).deleteSync();

      expect(
        engine.managedSkillLibraryFiles().map((file) => file.displayPath),
        ['available_skill/SKILL.md'],
      );
      expect(engine.readManagedAssistantSkill(available.id), contains('技能正文'));
    });

    test('入口编辑同步元数据，资源编辑只替换同包既有 Markdown', () {
      final skill = importPackage('camera_guide');
      final root = File(engine.managedAssistantSkillPath(skill.id)).parent;
      File(p.join(root.path, 'notes.md')).writeAsStringSync('旧资源');
      final before = db.select(
          'SELECT name,description,md5 FROM o_skillList WHERE id=?',
          [skill.id]).single;

      engine.saveManagedSkillLibraryFile(skill.id, 'notes.md', '新资源');
      expect(engine.readManagedSkillLibraryFile(skill.id, 'notes.md'), '新资源');
      expect(
        db.select('SELECT name,description,md5 FROM o_skillList WHERE id=?',
            [skill.id]).single,
        before,
      );

      engine.saveManagedSkillLibraryFile(skill.id, 'SKILL.md', '''---
name: camera_guide
description: 新说明
---
新正文
''');
      expect(
        engine
            .assistantSkills()
            .singleWhere((item) => item.id == skill.id)
            .description,
        '新说明',
      );
    });

    test('资源读写拒绝路径逃逸、链接和不存在的 Markdown', () {
      final skill = importPackage('camera_guide');
      final root = File(engine.managedAssistantSkillPath(skill.id)).parent;
      final outside = File(p.join(dir.path, 'outside.md'))
        ..writeAsStringSync('外部');
      Link(p.join(root.path, 'escape.md')).createSync(outside.path);

      for (final path in [
        '../outside.md',
        '/tmp/outside.md',
        'new.md',
        'escape.md'
      ]) {
        expect(
          () => engine.saveManagedSkillLibraryFile(skill.id, path, 'x'),
          throwsA(isA<EngineException>()),
        );
        expect(
          () => engine.readManagedSkillLibraryFile(skill.id, path),
          throwsA(isA<EngineException>()),
        );
      }
    });
  });
}
