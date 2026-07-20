import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dramaflow/src/bootstrap/bootstrap_io.dart';
import 'package:dramaflow/src/bootstrap/startup_failure_app.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _ZipBundle extends CachingAssetBundle {
  final ByteData zip;

  _ZipBundle(List<int> bytes)
      : zip = ByteData.sublistView(Uint8List.fromList(bytes));

  @override
  Future<ByteData> load(String key) async => zip;
}

void main() {
  test('启动装配器公开可测的数据目录边界', () {
    final source =
        File('lib/src/bootstrap/bootstrap_io.dart').readAsStringSync();

    expect(source, contains('Future<Widget> buildDramaFlowApp({'));
    expect(source, contains('String? dataDirectory'));
    expect(source,
        contains('StartupFailure(cause: error, dataDirectory: dataDir)'));
  });

  test('真实本地目录创建失败会保留失败目录供启动页展示', () async {
    final dir = Directory.systemTemp.createTempSync('dramaflow-startup-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final blocker = File(p.join(dir.path, 'not-a-directory'))
      ..writeAsStringSync('block');
    final emptyZip = _ZipBundle(ZipEncoder().encode(Archive()));
    final target = p.join(blocker.path, 'dramaflow');

    await expectLater(
      buildDramaFlowApp(dataDirectory: target, bundle: emptyZip),
      throwsA(
        isA<StartupFailure>().having(
          (failure) => failure.dataDirectory,
          'dataDirectory',
          target,
        ),
      ),
    );
  });

  test('默认手册按文件补齐，不覆盖用户已有包或编辑', () async {
    final dir = Directory.systemTemp.createTempSync('dramaflow-skill-seed-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final customReadme = File(
      p.join(dir.path, 'skills', 'art_skills', 'custom', 'README.md'),
    )..createSync(recursive: true);
    customReadme.writeAsStringSync('用户自定义');

    final archive = Archive()
      ..addFile(_file('skills/art_skills/default/meta.json', '{"name":"默认视觉"}'))
      ..addFile(_file('skills/art_skills/default/README.md', '默认视觉内容'))
      ..addFile(_file(
          'skills/story_skills/default_director/meta.json', '{"name":"默认导演"}'))
      ..addFile(
          _file('skills/story_skills/default_director/README.md', '默认导演内容'));
    final encoded = ZipEncoder().encode(archive);
    final bundle = _ZipBundle(encoded);

    await seedBundledDefaultSkills(dir.path, bundle: bundle);

    expect(customReadme.readAsStringSync(), '用户自定义');
    final defaultReadme = File(
      p.join(dir.path, 'skills', 'art_skills', 'default', 'README.md'),
    );
    expect(defaultReadme.readAsStringSync(), '默认视觉内容');
    expect(
      File(p.join(dir.path, 'skills', 'story_skills', 'default_director',
              'README.md'))
          .readAsStringSync(),
      '默认导演内容',
    );

    defaultReadme.writeAsStringSync('用户编辑默认包');
    await seedBundledDefaultSkills(dir.path, bundle: bundle);
    expect(defaultReadme.readAsStringSync(), '用户编辑默认包');
  });

  test('默认模型提示词按文件补齐，不覆盖用户编辑', () async {
    final dir = Directory.systemTemp.createTempSync('dramaflow-prompt-seed-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final archive = Archive()
      ..addFile(_file(
        'model_prompts/video/seedance2Multi-parameterMode.md',
        'Seedance default template',
      ));
    final bundle = _ZipBundle(ZipEncoder().encode(archive));
    final custom = File(p.join(
      dir.path,
      'model_prompts',
      'video',
      'custom.md',
    ));
    custom.createSync(recursive: true);
    custom.writeAsStringSync('custom template');

    await seedBundledModelPrompts(dir.path, bundle: bundle);

    final target = File(p.join(
      dir.path,
      'model_prompts',
      'video',
      'seedance2Multi-parameterMode.md',
    ));
    expect(custom.readAsStringSync(), 'custom template');
    expect(target.readAsStringSync(), 'Seedance default template');

    target.writeAsStringSync('user edited template');
    await seedBundledModelPrompts(dir.path, bundle: bundle);
    expect(target.readAsStringSync(), 'user edited template');
  });
}

ArchiveFile _file(String path, String content) {
  final bytes = Uint8List.fromList(utf8.encode(content));
  return ArchiveFile(path, bytes.length, bytes);
}
