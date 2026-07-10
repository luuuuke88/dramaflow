import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dramaflow/src/bootstrap/bootstrap_io.dart';
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
}

ArchiveFile _file(String path, String content) {
  final bytes = Uint8List.fromList(utf8.encode(content));
  return ArchiveFile(path, bytes.length, bytes);
}
