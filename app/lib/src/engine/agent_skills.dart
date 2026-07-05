import 'dart:io';

import 'package:path/path.dart' as p;

import 'errors.dart';

const markdownAgentSkillType = 'markdown-agent';

class ParsedAgentSkillMarkdown {
  final String id;
  final String name;
  final String description;
  final String body;

  const ParsedAgentSkillMarkdown({
    required this.id,
    required this.name,
    required this.description,
    required this.body,
  });
}

class AgentSkillActivation {
  final String id;
  final String name;
  final String description;
  final String content;
  final String filePath;
  final List<String> resourceFiles;

  const AgentSkillActivation({
    required this.id,
    required this.name,
    required this.description,
    required this.content,
    required this.filePath,
    this.resourceFiles = const [],
  });
}

ParsedAgentSkillMarkdown parseAgentSkillFile(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw EngineException(errLlmFormat, {'reason': '技能文件不存在：$filePath'});
  }
  final fallback = p.basenameWithoutExtension(file.parent.path);
  return parseAgentSkillMarkdown(file.readAsStringSync(),
      fallbackName: fallback);
}

ParsedAgentSkillMarkdown parseAgentSkillMarkdown(
  String markdown, {
  required String fallbackName,
}) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  var frontmatter = <String, String>{};
  var bodyStart = 0;
  if (lines.isNotEmpty && lines.first.trim() == '---') {
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        frontmatter = _parseFrontmatter(lines.sublist(1, i));
        bodyStart = i + 1;
        break;
      }
    }
  }
  final rawName = (frontmatter['name'] ?? fallbackName).trim();
  final id = normalizeAgentSkillId(rawName);
  final description = (frontmatter['description'] ?? '').trim();
  final body = lines.sublist(bodyStart).join('\n').trim();
  return ParsedAgentSkillMarkdown(
    id: id,
    name: rawName.isEmpty ? id : rawName,
    description: description,
    body: body,
  );
}

String normalizeAgentSkillId(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(normalized)) {
    throw EngineException(errLlmFormat, {'reason': '技能 name 只能包含字母、数字和下划线'});
  }
  return normalized;
}

String readAgentSkillFileUnderRoot(String skillFilePath, String relativePath) {
  final trimmed = relativePath.trim();
  if (trimmed.isEmpty || p.isAbsolute(trimmed)) {
    throw const EngineException(errLlmFormat, {'reason': '技能文件路径不安全'});
  }
  final root = p.normalize(p.absolute(File(skillFilePath).parent.path));
  final target = p.normalize(p.absolute(root, trimmed));
  if (target != root && !p.isWithin(root, target)) {
    throw const EngineException(errLlmFormat, {'reason': '技能文件路径不安全'});
  }
  final file = File(target);
  if (!file.existsSync()) {
    throw EngineException(errLlmFormat, {'reason': '技能文件不存在：$relativePath'});
  }
  return file.readAsStringSync();
}

List<String> listAgentSkillResourceFiles(String skillFilePath) {
  final root = p.normalize(p.absolute(File(skillFilePath).parent.path));
  final mainFile = p.normalize(p.absolute(skillFilePath));
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];

  final files = <String>[];
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final filePath = p.normalize(p.absolute(entity.path));
    if (filePath == mainFile || !p.isWithin(root, filePath)) continue;
    if (p.extension(filePath).toLowerCase() != '.md') continue;
    files.add(p.relative(filePath, from: root).replaceAll('\\', '/'));
  }
  files.sort();
  return files;
}

Map<String, String> _parseFrontmatter(List<String> lines) {
  final values = <String, String>{};
  for (final line in lines) {
    final sep = line.indexOf(':');
    if (sep <= 0) continue;
    final key = line.substring(0, sep).trim();
    final value = line.substring(sep + 1).trim();
    if (key.isNotEmpty) values[key] = value;
  }
  return values;
}
