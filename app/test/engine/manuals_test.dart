import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/engine/media.dart';
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
    dir = Directory.systemTemp.createTempSync('dramaflow-manuals-');
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

  Map<String, String> visualData() =>
      {for (final k in visualManualKeys) k: '$k 内容'};

  test('保存→读取往返：md 落盘、封面落盘、meta 名称', () {
    final png = base64Encode([137, 80, 78, 71]);
    engine.saveVisualManual(
      name: '国风水墨',
      imageBytesBase64: [png],
      data: visualData(),
    );
    final packs = engine.visualManuals();
    expect(packs, hasLength(1));
    final pack = packs.single;
    expect(pack.name, '国风水墨');
    expect(pack.data['art_character'], 'art_character 内容');
    expect(pack.images, hasLength(1));
    expect(
      File(p.join(dir.path, 'skills', 'art_skills', pack.pack, 'art_prompt',
              'art_character.md'))
          .existsSync(),
      isTrue,
      reason: 'art_* 落 art_prompt 子目录',
    );
    expect(
      File(p.join(dir.path, 'skills', 'art_skills', pack.pack,
              'driector_skills', 'director_storyboard.md'))
          .existsSync(),
      isTrue,
      reason: 'director_* 落 driector_skills 子目录（保留 ToonFlow 原拼写）',
    );
  });

  test('编辑改名不动目录；keepImages 控制封面保留', () {
    final png = base64Encode([1, 2, 3]);
    engine.saveVisualManual(
        name: 'A', imageBytesBase64: [png, png], data: visualData());
    var pack = engine.visualManuals().single;
    expect(pack.images, hasLength(2));

    engine.saveVisualManual(
      name: 'A 改名',
      pack: pack.pack,
      overwriteExisting: true,
      keepImages: [pack.images.first],
      data: visualData(),
    );
    final updated = engine.visualManuals().single;
    expect(updated.pack, pack.pack);
    expect(updated.name, 'A 改名');
    expect(updated.images, hasLength(1));
  });

  test('pack 是稳定目录 ID，重复新建不覆盖已有内容', () {
    engine.saveVisualManual(
      name: '第一版',
      pack: 'custom_visual',
      data: visualData(),
    );

    expect(
      () => engine.saveVisualManual(
        name: '第二版',
        pack: 'custom_visual',
        data: visualData(),
      ),
      throwsA(
        isA<EngineException>()
            .having((error) => error.errKey, 'errKey', 'errManualExists'),
      ),
    );

    final saved = engine.visualManuals().single;
    expect(saved.pack, 'custom_visual');
    expect(saved.name, '第一版');
  });

  test('空稳定目录 ID 继续从名称派生目录', () {
    engine.saveVisualManual(
      name: '国风水墨',
      pack: '   ',
      data: visualData(),
    );

    expect(engine.visualManuals().single.pack, sanitizePackName('国风水墨'));
  });

  test('只有明确覆盖时才会写入既有稳定目录', () {
    engine.saveVisualManual(
      name: '第一版',
      pack: 'custom_visual',
      data: visualData(),
    );

    engine.saveVisualManual(
      name: '编辑后的版本',
      pack: 'custom_visual',
      overwriteExisting: true,
      data: visualData(),
    );

    expect(engine.visualManuals().single.name, '编辑后的版本');
  });

  test('导演手册独立命名空间与键集校验', () {
    engine.saveDirectorManual(
      name: '快节奏',
      data: {for (final k in directorManualKeys) k: '$k 值'},
    );
    expect(engine.directorManuals().single.name, '快节奏');
    expect(engine.visualManuals(), isEmpty);

    expect(
      () => engine.saveDirectorManual(name: 'x', data: {'art_prop': 'y'}),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errManualInvalid)),
    );
  });

  test('导演手册按稳定目录 ID 拒绝重复新建', () {
    final data = {for (final key in directorManualKeys) key: '$key 内容'};
    engine.saveDirectorManual(
      name: '第一版导演手册',
      pack: 'custom_director',
      data: data,
    );

    expect(
      () => engine.saveDirectorManual(
        name: '第二版导演手册',
        pack: 'custom_director',
        data: data,
      ),
      throwsA(
        isA<EngineException>()
            .having((error) => error.errKey, 'errKey', 'errManualExists'),
      ),
    );
    expect(engine.directorManuals().single.name, '第一版导演手册');
  });

  test('默认手册在没有 meta 时使用 README 首行作为显示名', () {
    final visualDir = Directory(p.join(
      dir.path,
      'skills',
      'art_skills',
      'default_visual',
    ))
      ..createSync(recursive: true);
    File(p.join(visualDir.path, 'README.md'))
        .writeAsStringSync('# --国风新潮--\n后续说明');

    final directorDir = Directory(p.join(
      dir.path,
      'skills',
      'story_skills',
      'default_director',
    ))
      ..createSync(recursive: true);
    File(p.join(directorDir.path, 'README.md'))
        .writeAsStringSync('# --历史史诗--\n后续说明');

    expect(engine.visualManuals().single.name, '# 国风新潮');
    expect(engine.directorManuals().single.name, '# 历史史诗');
  });

  test('删除清目录', () {
    engine.saveVisualManual(name: 'B', data: visualData());
    final pack = engine.visualManuals().single.pack;
    engine.deleteVisualManual(pack);
    expect(engine.visualManuals(), isEmpty);
    expect(
      Directory(p.join(dir.path, 'skills', 'art_skills', pack)).existsSync(),
      isFalse,
    );
  });
}
