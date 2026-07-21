import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'engine.dart';
import 'errors.dart';

const managedMarkdownAssistantSkillType = 'markdown-agent';

class ManagedAssistantSkill {
  final String id;
  final String name;
  final String description;
  final String path;

  const ManagedAssistantSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.path,
  });
}

class AssistantSkillScanIssue {
  final String id;
  final String path;
  final String reason;

  const AssistantSkillScanIssue({
    required this.id,
    required this.path,
    required this.reason,
  });
}

class AssistantSkillScanResult {
  final List<ManagedAssistantSkill> added;
  final List<ManagedAssistantSkill> updated;
  final List<AssistantSkillScanIssue> missing;
  final List<AssistantSkillScanIssue> invalid;

  const AssistantSkillScanResult({
    required this.added,
    required this.updated,
    required this.missing,
    required this.invalid,
  });
}

class ParsedAssistantSkillMarkdown {
  final String id;
  final String name;
  final String description;
  final String body;

  const ParsedAssistantSkillMarkdown({
    required this.id,
    required this.name,
    required this.description,
    required this.body,
  });
}

extension AssistantSkillLibraryApi on Engine {
  /// 应用自有技能根。媒体根和技能根同属于同一个运行数据目录。
  String assistantSkillLibraryRoot() {
    final root = p.normalize(p.join(p.dirname(media.rootDir), 'skills'));
    final directory = Directory(root)..createSync(recursive: true);
    return directory.resolveSymbolicLinksSync();
  }

  /// 将用户经系统文件选择器明确选中的 Markdown 复制进应用技能工作区。
  ///
  /// 源文件允许在工作区外；持久化路径永远由技能 ID 派生，不能由源路径控制。
  ManagedAssistantSkill importMarkdownAssistantSkill(String sourcePath) {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw EngineException(
          errLlmFormat, {'reason': 'skillFileMissing:$sourcePath'});
    }
    final markdown = source.readAsStringSync();
    final parsed = parseAssistantSkillMarkdown(
      markdown,
      fallbackName: _fallbackSkillName(source.path),
    );
    final root =
        Directory(assistantSkillLibraryRoot()).resolveSymbolicLinksSync();
    final targetDir = Directory(p.join(root, parsed.id));
    if (targetDir.existsSync()) {
      final resolved = targetDir.resolveSymbolicLinksSync();
      if (!p.isWithin(root, resolved)) {
        throw const EngineException(
            errLlmFormat, {'reason': 'skillPathUnsafe'});
      }
    } else {
      targetDir.createSync(recursive: true);
    }
    final target = File(p.join(targetDir.path, 'SKILL.md'));
    if (FileSystemEntity.typeSync(target.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const EngineException(errLlmFormat, {'reason': 'skillPathUnsafe'});
    }
    final sourceResolved = source.resolveSymbolicLinksSync();
    final targetDirResolved = targetDir.resolveSymbolicLinksSync();
    final sourceAlreadyManaged = p.isWithin(targetDirResolved, sourceResolved);
    if (!sourceAlreadyManaged) {
      _clearDirectory(targetDir);
      if (p.basename(source.path).toLowerCase() == 'skill.md') {
        _copySkillDirectory(source.parent, targetDir);
      }
    }
    final createdAt = db.select('SELECT createTime FROM o_skillList WHERE id=?',
        [parsed.id]).firstOrNull?['createTime'] as int?;
    final state = db.select('SELECT state FROM o_skillList WHERE id=?',
        [parsed.id]).firstOrNull?['state'] as int?;
    final now = DateTime.now().millisecondsSinceEpoch;
    final digest = md5.convert(utf8.encode(markdown)).toString();
    target.writeAsStringSync(markdown);
    db.execute(
      'INSERT OR REPLACE INTO o_skillList '
      '(id,name,description,state,type,createTime,updateTime,path,md5,embedding) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        parsed.id,
        parsed.name,
        parsed.description,
        state ?? 1,
        managedMarkdownAssistantSkillType,
        createdAt ?? now,
        now,
        target.path,
        digest,
        '',
      ],
    );
    return ManagedAssistantSkill(
      id: parsed.id,
      name: parsed.name,
      description: parsed.description,
      path: target.path,
    );
  }

  String readManagedAssistantSkill(String id) {
    return File(managedAssistantSkillPath(id)).readAsStringSync();
  }

  String managedAssistantSkillPath(String id) {
    final row = db.select(
      'SELECT path FROM o_skillList WHERE id=? AND type=?',
      [id, managedMarkdownAssistantSkillType],
    ).firstOrNull;
    if (row == null) {
      throw const EngineException(errLlmFormat, {'reason': 'skillMissing'});
    }
    return _managedFile(row['path'] as String?).path;
  }

  void saveManagedAssistantSkill(String id, String markdown) {
    final row = db.select(
      'SELECT path FROM o_skillList WHERE id=? AND type=?',
      [id, managedMarkdownAssistantSkillType],
    ).firstOrNull;
    if (row == null) {
      throw const EngineException(errLlmFormat, {'reason': 'skillMissing'});
    }
    final file = _managedFile(row['path'] as String?);
    final parsed = parseAssistantSkillMarkdown(
      markdown,
      fallbackName: _fallbackSkillName(file.path),
    );
    if (parsed.id != id) {
      throw const EngineException(errLlmFormat, {'reason': 'skillIdImmutable'});
    }
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    temporary.writeAsStringSync(markdown);
    temporary.renameSync(file.path);
    db.execute(
      'UPDATE o_skillList SET name=?,description=?,md5=?,updateTime=? WHERE id=?',
      [
        parsed.name,
        parsed.description,
        md5.convert(utf8.encode(markdown)).toString(),
        DateTime.now().millisecondsSinceEpoch,
        id,
      ],
    );
  }

  /// 将应用技能根中的 Markdown 文件与 o_skillList 对账，不删除任何用户记录。
  AssistantSkillScanResult scanMarkdownAssistantSkills() {
    final rootPath =
        Directory(assistantSkillLibraryRoot()).resolveSymbolicLinksSync();
    final root = Directory(rootPath);
    final rows = db.select(
      'SELECT id,name,description,state,createTime,path,md5 FROM o_skillList WHERE type=?',
      [managedMarkdownAssistantSkillType],
    );
    final existing = <String, Map<String, Object?>>{
      for (final row in rows) row['id'] as String: row,
    };
    final added = <ManagedAssistantSkill>[];
    final updated = <ManagedAssistantSkill>[];
    final missing = <AssistantSkillScanIssue>[];
    final invalid = <AssistantSkillScanIssue>[];
    final seen = <String>{};
    final observedPaths = <String>{};

    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      // 每个托管包只有 SKILL.md 是技能入口；同包的其它 Markdown 属于可按需读取
      // 的资源，不能在扫描后被误注册并注入 Agent 上下文。
      if (entity is! File ||
          p.basename(entity.path).toLowerCase() != 'skill.md') {
        continue;
      }
      final resolved = entity.resolveSymbolicLinksSync();
      if (!p.isWithin(rootPath, resolved)) continue;
      observedPaths.add(resolved);
      final markdown = entity.readAsStringSync();
      ParsedAssistantSkillMarkdown parsed;
      try {
        parsed = parseAssistantSkillMarkdown(
          markdown,
          fallbackName: _fallbackSkillName(resolved),
        );
      } on EngineException catch (error) {
        invalid.add(AssistantSkillScanIssue(
          id: '',
          path: resolved,
          reason: error.errParams['reason']?.toString() ?? 'skillInvalid',
        ));
        continue;
      }
      if (!seen.add(parsed.id)) {
        invalid.add(AssistantSkillScanIssue(
          id: parsed.id,
          path: resolved,
          reason: 'skillIdDuplicate',
        ));
        continue;
      }
      final digest = md5.convert(utf8.encode(markdown)).toString();
      final previous = existing[parsed.id];
      final skill = ManagedAssistantSkill(
        id: parsed.id,
        name: parsed.name,
        description: parsed.description,
        path: resolved,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      if (previous == null) {
        db.execute(
          'INSERT INTO o_skillList '
          '(id,name,description,state,type,createTime,updateTime,path,md5,embedding) '
          'VALUES (?,?,?,?,?,?,?,?,?,?)',
          [
            skill.id,
            skill.name,
            skill.description,
            1,
            managedMarkdownAssistantSkillType,
            now,
            now,
            skill.path,
            digest,
            '',
          ],
        );
        added.add(skill);
        continue;
      }
      if (previous['md5'] != digest ||
          previous['name'] != skill.name ||
          previous['description'] != skill.description ||
          previous['path'] != skill.path) {
        db.execute(
          'UPDATE o_skillList SET name=?,description=?,path=?,md5=?,updateTime=? '
          'WHERE id=?',
          [skill.name, skill.description, skill.path, digest, now, skill.id],
        );
        updated.add(skill);
      }
    }

    for (final entry in existing.entries) {
      final storedPath = entry.value['path'] as String? ?? '';
      final observed = _canonicalExistingFilePath(storedPath);
      if (!seen.contains(entry.key) && !observedPaths.contains(observed)) {
        missing.add(AssistantSkillScanIssue(
          id: entry.key,
          path: storedPath,
          reason: 'skillFileMissing',
        ));
      }
    }
    return AssistantSkillScanResult(
      added: added,
      updated: updated,
      missing: missing,
      invalid: invalid,
    );
  }

  File _managedFile(String? storedPath) {
    if (storedPath == null || storedPath.isEmpty || !p.isAbsolute(storedPath)) {
      throw const EngineException(errLlmFormat, {'reason': 'skillPathUnsafe'});
    }
    final root =
        Directory(assistantSkillLibraryRoot()).resolveSymbolicLinksSync();
    final file = File(p.normalize(storedPath));
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const EngineException(errLlmFormat, {'reason': 'skillMissing'});
    }
    final resolved = file.resolveSymbolicLinksSync();
    if (!p.isWithin(root, resolved)) {
      throw const EngineException(errLlmFormat, {'reason': 'skillPathUnsafe'});
    }
    return File(resolved);
  }
}

String? _canonicalExistingFilePath(String path) {
  if (path.isEmpty) return null;
  try {
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
}

void _clearDirectory(Directory directory) {
  for (final child in directory.listSync(followLinks: false)) {
    child.deleteSync(recursive: child is Directory);
  }
}

void _copySkillDirectory(Directory source, Directory destination) {
  for (final child in source.listSync(followLinks: false)) {
    final name = p.basename(child.path);
    final target = p.join(destination.path, name);
    if (child is File) {
      child.copySync(target);
    } else if (child is Directory) {
      final childTarget = Directory(target)..createSync(recursive: true);
      _copySkillDirectory(child, childTarget);
    }
  }
}

ParsedAssistantSkillMarkdown parseAssistantSkillFile(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw EngineException(
        errLlmFormat, {'reason': 'skillFileMissing:$filePath'});
  }
  return parseAssistantSkillMarkdown(
    file.readAsStringSync(),
    fallbackName: _fallbackSkillName(file.path),
  );
}

ParsedAssistantSkillMarkdown parseAssistantSkillMarkdown(
  String markdown, {
  required String fallbackName,
}) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  var frontmatter = <String, String>{};
  var bodyStart = 0;
  if (lines.isNotEmpty && lines.first.trim() == '---') {
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        frontmatter = _parseSkillFrontmatter(lines.sublist(1, i));
        bodyStart = i + 1;
        break;
      }
    }
  }
  final rawName = (frontmatter['name'] ?? fallbackName).trim();
  final id = _normalizeAssistantSkillId(rawName);
  return ParsedAssistantSkillMarkdown(
    id: id,
    name: rawName.isEmpty ? id : rawName,
    description: (frontmatter['description'] ?? '').trim(),
    body: lines.sublist(bodyStart).join('\n').trim(),
  );
}

String _fallbackSkillName(String filePath) {
  final file = File(filePath);
  return p.basename(file.path).toLowerCase() == 'skill.md'
      ? p.basename(file.parent.path)
      : p.basenameWithoutExtension(file.path);
}

String _normalizeAssistantSkillId(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$').hasMatch(normalized)) {
    throw const EngineException(errLlmFormat, {'reason': 'skillIdInvalid'});
  }
  return normalized;
}

Map<String, String> _parseSkillFrontmatter(List<String> lines) {
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
                (m) => '${m.group(1)} ${m.group(2)}',
              )
              .trim()
          : joined;
      continue;
    }
    values[key] = rawValue.replaceFirstMapped(
      RegExp(r'''^(['"])([\s\S]*)\1$'''),
      (m) => m.group(2)!,
    );
  }
  return values;
}
