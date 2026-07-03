// 视觉/导演手册文件包（照抄 ToonFlow skills/art_skills、skills/story_skills 布局）：
// <root>/skills/{art_skills|story_skills}/<pack>/
//   meta.json {"name": 显示名}
//   README.md、prefix.md（视觉）
//   art_prompt/<key>.md（art_* 系列）
//   driector_skills/<key>.md（director_* 系列，目录名保留 ToonFlow 原拼写）
//   images/ 封面图
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'engine.dart';
import 'errors.dart';

/// 视觉手册合法键（12 tab，逐字照抄 addVisualManual）。
const visualManualKeys = [
  'README',
  'prefix',
  'art_character',
  'art_character_derivative',
  'art_prop',
  'art_prop_derivative',
  'art_scene',
  'art_scene_derivative',
  'director_storyboard',
  'art_storyboard_video',
  'director_planning_style',
  'director_storyboard_table_style',
];

/// 导演手册合法键（3 tab，逐字照抄 addDirectorManual）。
const directorManualKeys = [
  'README',
  'director_planning_narrative',
  'director_storyboard_table_narrative',
];

class ManualPack {
  final String name; // 显示名（项目 artStyle/directorManual 存的值）
  final String pack; // 目录名
  final List<String> images; // 封面绝对路径
  final Map<String, String> data; // key → md 内容

  const ManualPack({
    required this.name,
    required this.pack,
    required this.images,
    required this.data,
  });
}

String _fileFor(String key) {
  if (key == 'README') return 'README.md';
  if (key == 'prefix') return 'prefix.md';
  if (key.startsWith('director_')) return 'driector_skills/$key.md';
  return 'art_prompt/$key.md';
}

String sanitizePackName(String name) =>
    name.trim().replaceAll(RegExp(r'[/\\:*?"<>|\s]+'), '_');

extension ManualsApi on Engine {
  String get skillsRoot => p.join(p.dirname(media.rootDir), 'skills');

  List<ManualPack> visualManuals() =>
      _list('art_skills', visualManualKeys);
  List<ManualPack> directorManuals() =>
      _list('story_skills', directorManualKeys);

  void saveVisualManual({
    required String name,
    String? pack,
    List<String> imageBytesBase64 = const [],
    List<String> keepImages = const [],
    required Map<String, String> data,
  }) =>
      _save('art_skills', visualManualKeys,
          name: name,
          pack: pack,
          imageBytesBase64: imageBytesBase64,
          keepImages: keepImages,
          data: data);

  void saveDirectorManual({
    required String name,
    String? pack,
    List<String> imageBytesBase64 = const [],
    List<String> keepImages = const [],
    required Map<String, String> data,
  }) =>
      _save('story_skills', directorManualKeys,
          name: name,
          pack: pack,
          imageBytesBase64: imageBytesBase64,
          keepImages: keepImages,
          data: data);

  void deleteVisualManual(String pack) => _delete('art_skills', pack);
  void deleteDirectorManual(String pack) => _delete('story_skills', pack);

  List<ManualPack> _list(String kind, List<String> keys) {
    final dir = Directory(p.join(skillsRoot, kind));
    if (!dir.existsSync()) return const [];
    final packs = <ManualPack>[];
    for (final entry in dir.listSync().whereType<Directory>()) {
      final packName = p.basename(entry.path);
      var display = packName;
      final meta = File(p.join(entry.path, 'meta.json'));
      if (meta.existsSync()) {
        try {
          final decoded = jsonDecode(meta.readAsStringSync());
          if (decoded is Map && decoded['name'] is String) {
            display = decoded['name'] as String;
          }
        } catch (_) {}
      }
      final data = <String, String>{};
      for (final key in keys) {
        final f = File(p.join(entry.path, _fileFor(key)));
        if (f.existsSync()) data[key] = f.readAsStringSync();
      }
      final imagesDir = Directory(p.join(entry.path, 'images'));
      final images = imagesDir.existsSync()
          ? (imagesDir.listSync().whereType<File>().map((f) => f.path).toList()
            ..sort())
          : <String>[];
      packs.add(ManualPack(
          name: display, pack: packName, images: images, data: data));
    }
    packs.sort((a, b) => a.pack.compareTo(b.pack));
    return packs;
  }

  void _save(
    String kind,
    List<String> validKeys, {
    required String name,
    String? pack,
    required List<String> imageBytesBase64,
    required List<String> keepImages,
    required Map<String, String> data,
  }) {
    if (name.trim().isEmpty) {
      throw const EngineException(errManualInvalid, {'reason': 'name'});
    }
    for (final key in data.keys) {
      if (!validKeys.contains(key)) {
        throw EngineException(errManualInvalid, {'reason': 'key', 'key': key});
      }
    }
    final packName =
        (pack == null || pack.isEmpty) ? sanitizePackName(name) : pack;
    if (packName.isEmpty) {
      throw const EngineException(errManualInvalid, {'reason': 'pack'});
    }
    final dir = Directory(p.join(skillsRoot, kind, packName))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'meta.json'))
        .writeAsStringSync(jsonEncode({'name': name.trim()}));
    for (final entry in data.entries) {
      final f = File(p.join(dir.path, _fileFor(entry.key)));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(entry.value);
    }
    // 封面：保留 keepImages 中列出的现存图，删除其余，再追加新上传
    final imagesDir = Directory(p.join(dir.path, 'images'))
      ..createSync(recursive: true);
    for (final f in imagesDir.listSync().whereType<File>()) {
      if (!keepImages.contains(f.path)) f.deleteSync();
    }
    var i = DateTime.now().millisecondsSinceEpoch;
    for (final b64 in imageBytesBase64) {
      try {
        final bytes = base64Decode(b64.contains(',')
            ? b64.substring(b64.indexOf(',') + 1)
            : b64);
        File(p.join(imagesDir.path, 'cover_${i++}.png'))
            .writeAsBytesSync(bytes);
      } catch (_) {
        throw const EngineException(errFileType);
      }
    }
  }

  void _delete(String kind, String pack) {
    final dir = Directory(p.join(skillsRoot, kind, pack));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
