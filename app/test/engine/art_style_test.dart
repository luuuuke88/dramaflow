import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/src/engine/art_style.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
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
    dir = Directory.systemTemp.createTempSync('dramaflow-artstyle-');
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

  test('新增画风：落盘封面/label 同 name/列表倒序', () {
    final id = engine.addArtStyle(
      name: '2D 动漫',
      prompt: '(画风：2D动漫风格,2d animation style)',
      base64Image: base64Encode(const [1, 2, 3, 4]),
    );
    engine.addArtStyle(name: '照片写实', prompt: 'photorealistic');

    final list = engine.artStyles();
    expect(list.length, 2);
    // 倒序：最新的在前
    expect(list.first.name, '照片写实');
    final anime = list.firstWhere((s) => s.id == id);
    expect(anime.label, '2D 动漫', reason: 'label 应与 name 一致');
    expect(anime.prompt, '(画风：2D动漫风格,2d animation style)');
    expect(anime.fileUrl, isNotNull);
    // 封面文件真实落盘
    expect(File(engine.mediaAbsPath(anime.fileUrl!)).existsSync(), isTrue);
    expect(anime.fileUrl, startsWith('artStyle/'));
  });

  test('新增画风：空名称抛错', () {
    expect(
      () => engine.addArtStyle(name: '   ', prompt: 'x'),
      throwsA(isA<EngineException>()),
    );
  });

  test('编辑画风：仅给新封面才替换旧封面，label 跟随 name', () {
    final id = engine.addArtStyle(
      name: '国风水墨',
      prompt: 'ink',
      base64Image: base64Encode(const [9, 9, 9]),
    );
    final before = engine.artStyles().single;
    final oldCover = engine.mediaAbsPath(before.fileUrl!);
    expect(File(oldCover).existsSync(), isTrue);

    // 不给封面：保留旧封面，改名+提示词
    engine.editArtStyle(id, name: '国风水墨2', prompt: 'ink wash');
    var updated = engine.artStyles().single;
    expect(updated.name, '国风水墨2');
    expect(updated.label, '国风水墨2');
    expect(updated.prompt, 'ink wash');
    expect(updated.fileUrl, before.fileUrl, reason: '未给新封面应保留旧封面');
    expect(File(oldCover).existsSync(), isTrue);

    // 给新封面：旧封面被删，新封面落盘
    engine.editArtStyle(id,
        name: '国风水墨2',
        prompt: 'ink wash',
        base64Image: base64Encode(const [7, 7]));
    updated = engine.artStyles().single;
    expect(updated.fileUrl, isNot(before.fileUrl));
    expect(File(oldCover).existsSync(), isFalse, reason: '旧封面应被删除');
    expect(File(engine.mediaAbsPath(updated.fileUrl!)).existsSync(), isTrue);
  });

  test('编辑不存在的画风抛错', () {
    expect(
      () => engine.editArtStyle(999, name: 'x', prompt: 'y'),
      throwsA(isA<EngineException>()),
    );
  });

  test('删除画风：连同封面文件', () {
    final id = engine.addArtStyle(
        name: '删我', prompt: 'x', base64Image: base64Encode(const [5]));
    final rel = engine.artStyles().single.fileUrl!;
    final abs = engine.mediaAbsPath(rel);
    expect(File(abs).existsSync(), isTrue);

    engine.deleteArtStyle(id);
    expect(engine.artStyles(), isEmpty);
    expect(File(abs).existsSync(), isFalse);
    // 删除不存在的 id 不抛错
    engine.deleteArtStyle(999);
  });
}
