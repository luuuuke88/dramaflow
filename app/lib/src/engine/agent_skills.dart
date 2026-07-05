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
  final fallback = p.basename(file.path).toLowerCase() == 'skill.md'
      ? p.basenameWithoutExtension(file.parent.path)
      : p.basenameWithoutExtension(file.path);
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
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$').hasMatch(normalized)) {
    throw EngineException(
      errLlmFormat,
      {'reason': '技能 name 只能包含字母、数字、下划线、连字符和点号'},
    );
  }
  return normalized;
}

String readAgentSkillFileUnderRoot(
  String skillFilePath,
  String relativePath, {
  List<String> workspaceDirs = const [],
  List<String> attachedSkillDirs = const [],
}) {
  final safeRelativePath = _normalizeSkillRelativePath(relativePath);
  final ownRoot = _ownSkillRoot(skillFilePath);
  if (_isDirectoryStyleSkillFile(skillFilePath)) {
    final ownTarget = p.normalize(p.absolute(ownRoot, safeRelativePath));
    if ((ownTarget == ownRoot || p.isWithin(ownRoot, ownTarget)) &&
        File(ownTarget).existsSync()) {
      return File(ownTarget).readAsStringSync();
    }
  }

  final allowed = listAgentSkillResourceFiles(
    skillFilePath,
    workspaceDirs: workspaceDirs,
    attachedSkillDirs: attachedSkillDirs,
  );
  if (!allowed.contains(safeRelativePath)) {
    throw EngineException(
      errLlmFormat,
      {'reason': '技能文件不存在：$relativePath'},
    );
  }

  final root = _skillsRoot(skillFilePath);
  final target = p.normalize(p.absolute(root, safeRelativePath));
  if (target != root && !p.isWithin(root, target)) {
    throw const EngineException(errLlmFormat, {'reason': '技能文件路径不安全'});
  }
  final file = File(target);
  if (!file.existsSync()) {
    throw EngineException(errLlmFormat, {'reason': '技能文件不存在：$relativePath'});
  }
  return file.readAsStringSync();
}

List<String> listAgentSkillResourceFiles(
  String skillFilePath, {
  List<String> workspaceDirs = const [],
  List<String> attachedSkillDirs = const [],
}) {
  final root = _ownSkillRoot(skillFilePath);
  final mainFile = p.normalize(p.absolute(skillFilePath));
  final dir = Directory(root);
  final files = <String>[];
  final seen = <String>{};
  void add(String file) {
    if (seen.add(file)) files.add(file);
  }

  if (_isDirectoryStyleSkillFile(skillFilePath) && dir.existsSync()) {
    final ownFiles = <String>[];
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final filePath = p.normalize(p.absolute(entity.path));
      if (filePath == mainFile || !p.isWithin(root, filePath)) continue;
      if (p.extension(filePath).toLowerCase() != '.md') continue;
      ownFiles.add(p.relative(filePath, from: root).replaceAll('\\', '/'));
    }
    ownFiles.sort();
    for (final file in ownFiles) {
      add(file);
    }
  }

  final skillsRoot = _skillsRoot(skillFilePath);
  for (final dir in workspaceDirs) {
    for (final file in _listMarkdownFilesUnderSkillsRoot(
      skillsRoot,
      dir,
      recursive: false,
    )) {
      add(file);
    }
  }
  for (final dir in attachedSkillDirs) {
    for (final file in _listMarkdownFilesUnderSkillsRoot(
      skillsRoot,
      dir,
      recursive: true,
    )) {
      add(file);
    }
  }
  return files;
}

String _ownSkillRoot(String skillFilePath) =>
    p.normalize(p.absolute(File(skillFilePath).parent.path));

bool _isDirectoryStyleSkillFile(String skillFilePath) =>
    p.basename(skillFilePath).toLowerCase() == 'skill.md';

String _skillsRoot(String skillFilePath) {
  final file = File(skillFilePath);
  final ownRoot = _ownSkillRoot(skillFilePath);
  if (_isDirectoryStyleSkillFile(file.path)) {
    return p.normalize(p.dirname(ownRoot));
  }
  return ownRoot;
}

List<String> _listMarkdownFilesUnderSkillsRoot(
  String skillsRoot,
  String relativeDir, {
  required bool recursive,
}) {
  final safeDir = _normalizeSkillRelativePath(relativeDir);
  final dirPath = p.normalize(p.absolute(skillsRoot, safeDir));
  if (dirPath != skillsRoot && !p.isWithin(skillsRoot, dirPath)) {
    return const [];
  }
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return const [];
  final files = <String>[];
  for (final entity in dir.listSync(recursive: recursive, followLinks: false)) {
    if (entity is! File) continue;
    final filePath = p.normalize(p.absolute(entity.path));
    if (!p.isWithin(skillsRoot, filePath)) continue;
    if (p.extension(filePath).toLowerCase() != '.md') continue;
    files.add(p.relative(filePath, from: skillsRoot).replaceAll('\\', '/'));
  }
  files.sort();
  return files;
}

String _normalizeSkillRelativePath(String value) {
  final trimmed = value.trim().replaceAll('\\', '/');
  if (trimmed.isEmpty || p.isAbsolute(trimmed)) {
    throw const EngineException(errLlmFormat, {'reason': '技能文件路径不安全'});
  }
  final normalized = p.posix.normalize(trimmed);
  if (normalized == '.' || normalized == '..' || normalized.startsWith('../')) {
    throw const EngineException(errLlmFormat, {'reason': '技能文件路径不安全'});
  }
  return normalized;
}

Map<String, String> _parseFrontmatter(List<String> lines) {
  final values = <String, String>{};
  for (var i = 0; i < lines.length;) {
    final line = lines[i];
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      i++;
      continue;
    }
    final match = RegExp(r'^([A-Za-z0-9_-]+)\s*:\s*(.*)$').firstMatch(line);
    if (match == null) {
      i++;
      continue;
    }
    final key = match.group(1)!.trim();
    final rawValue = match.group(2)!.trim();
    i++;
    if (key.isEmpty) continue;
    if (RegExp(r'^[>|][+-]?[0-9]*$').hasMatch(rawValue)) {
      final folded = rawValue.startsWith('>');
      final blockLines = <String>[];
      int? blockIndent;
      while (i < lines.length) {
        final current = lines[i];
        if (current.trim().isEmpty) {
          if (blockIndent != null) blockLines.add('');
          i++;
          continue;
        }
        final currentIndent =
            RegExp(r'^\s*').firstMatch(current)!.group(0)!.length;
        blockIndent ??= currentIndent;
        if (currentIndent < blockIndent) break;
        blockLines.add(current.substring(blockIndent));
        i++;
      }
      final joined = blockLines.join('\n').trim();
      values[key] = folded
          ? joined
              .replaceAll(RegExp(r'\n{2,}'), '\n\n')
              .replaceAllMapped(
                RegExp(r'([^\n])\n([^\n])'),
                (match) => '${match.group(1)} ${match.group(2)}',
              )
              .trim()
          : joined;
      continue;
    }
    values[key] = rawValue.replaceFirstMapped(
      RegExp(r'''^(['"])([\s\S]*)\1$'''),
      (match) => match.group(2)!,
    );
  }
  return values;
}
