// 助手技能（v0.4 spec §4 瘦身版）：Markdown 技能查看/编辑/开关 + 12 个内置动作的
// 启用开关，纯提示词注入、无执行语义（custom-js 执行随 spec §2 砍除，此处不列出
// custom-js-agent 类型行）。DB type 值与旧行一致：'builtin-agent'/'markdown-agent'。
// 被砍不搬：ToonFlow 子代理提示词包播种（script_agent_decision 等 13 个 seed）、
// 逐阶段归属映射、AgentSkillActivation XML 格式化。
import 'dart:io';

import 'package:path/path.dart' as p;

import 'assistant_actions.dart';
import 'engine.dart';
import 'errors.dart';

const assistantToolSkillType = 'builtin-agent';
const markdownAssistantSkillType = 'markdown-agent';

class AssistantSkill {
  final String id;
  final String name;
  final String description;
  final bool enabled;
  final String type;
  final String path;
  const AssistantSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
    required this.type,
    this.path = '',
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

extension AssistantSkillsApi on Engine {
  void _ensureAssistantSkillsSeeded() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final action in assistantActions()) {
      final exists =
          db.select('SELECT id FROM o_skillList WHERE id=?', [action.name]);
      if (exists.isNotEmpty) continue;
      db.execute(
        'INSERT INTO o_skillList '
        '(id,name,description,state,type,createTime,updateTime,path,md5,embedding) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [action.name, action.name, action.description, 1,
         assistantToolSkillType, now, now, '', '', ''],
      );
    }
  }

  List<AssistantSkill> assistantSkills() {
    _ensureAssistantSkillsSeeded();
    final rows = db.select(
      'SELECT id,name,description,state,type,path FROM o_skillList '
      'WHERE type IN (?,?) ORDER BY createTime ASC, id ASC',
      [assistantToolSkillType, markdownAssistantSkillType],
    );
    return [
      for (final row in rows)
        AssistantSkill(
          id: row['id'] as String,
          name: (row['name'] as String?)?.isNotEmpty == true
              ? row['name'] as String
              : row['id'] as String,
          description: row['description'] as String? ?? '',
          enabled: (row['state'] as int? ?? 1) != 0,
          type: row['type'] as String? ?? assistantToolSkillType,
          path: row['path'] as String? ?? '',
        ),
    ];
  }

  void updateAssistantSkill(String id, {String? description, bool? enabled}) {
    _ensureAssistantSkillsSeeded();
    final row = db.select(
      'SELECT id,description,state,type FROM o_skillList '
      'WHERE id=? AND type IN (?,?)',
      [id, assistantToolSkillType, markdownAssistantSkillType],
    ).firstOrNull;
    if (row == null) {
      throw const EngineException(errLlmFormat, {'reason': 'skillMissing'});
    }
    db.execute(
      'UPDATE o_skillList SET description=?, state=?, updateTime=? WHERE id=?',
      [
        description ?? row['description'] as String? ?? '',
        enabled == null ? row['state'] as int? ?? 1 : (enabled ? 1 : 0),
        DateTime.now().millisecondsSinceEpoch,
        id,
      ],
    );
  }

  /// 启用状态过滤后的动作名集合（供对话循环筛选暴露给 LLM 的工具面）。
  Set<String> enabledAssistantActionNames() {
    final disabled = <String>{
      for (final s in assistantSkills())
        if (s.type == assistantToolSkillType && !s.enabled) s.id,
    };
    return {
      for (final a in assistantActions())
        if (!disabled.contains(a.name)) a.name,
    };
  }

  AssistantSkill saveMarkdownAssistantSkill({
    required String filePath,
    bool enabled = true,
  }) {
    final parsed = parseAssistantSkillFile(filePath);
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_skillList '
      '(id,name,description,state,type,createTime,updateTime,path,md5,embedding) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        parsed.id,
        parsed.name,
        parsed.description,
        enabled ? 1 : 0,
        markdownAssistantSkillType,
        db.select('SELECT createTime FROM o_skillList WHERE id=?',
                [parsed.id]).firstOrNull?['createTime'] as int? ??
            now,
        now,
        filePath,
        '',
        '',
      ],
    );
    return assistantSkills().singleWhere((s) => s.id == parsed.id);
  }

  /// 读取 markdown 技能自身目录内的资源文件（路径穿越防护）。
  String readAssistantSkillFile(String id, String relativePath) {
    final row = db.select(
      'SELECT path FROM o_skillList WHERE id=? AND type=?',
      [id, markdownAssistantSkillType],
    ).firstOrNull;
    final skillPath = row?['path'] as String? ?? '';
    if (skillPath.isEmpty) {
      throw const EngineException(errLlmFormat, {'reason': 'skillMissing'});
    }
    final root = p.normalize(p.absolute(File(skillPath).parent.path));
    final safe = _normalizeSkillRelativePath(relativePath);
    final target = p.normalize(p.absolute(root, safe));
    if (target != root && !p.isWithin(root, target)) {
      throw const EngineException(errLlmFormat, {'reason': 'skillPathUnsafe'});
    }
    final file = File(target);
    if (!file.existsSync()) {
      throw const EngineException(errLlmFormat, {'reason': 'skillMissing'});
    }
    return file.readAsStringSync();
  }

  /// 启用的 markdown 技能正文（注入系统提示词）；文件缺失的技能跳过（尽力而为）。
  List<String> assistantSkillContexts() {
    final contexts = <String>[];
    for (final skill in assistantSkills()) {
      if (skill.type != markdownAssistantSkillType || !skill.enabled) continue;
      try {
        final parsed = parseAssistantSkillFile(skill.path);
        if (parsed.body.isEmpty) continue;
        contexts.add('【技能：${skill.name}】\n${parsed.body}');
      } on EngineException {
        continue; // 技能文件被移动/删除时静默跳过，不阻断对话
      }
    }
    return contexts;
  }
}

ParsedAssistantSkillMarkdown parseAssistantSkillFile(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw EngineException(errLlmFormat, {'reason': 'skillFileMissing:$filePath'});
  }
  final fallback = p.basename(file.path).toLowerCase() == 'skill.md'
      ? p.basenameWithoutExtension(file.parent.path)
      : p.basenameWithoutExtension(file.path);
  return parseAssistantSkillMarkdown(file.readAsStringSync(),
      fallbackName: fallback);
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
  final description = (frontmatter['description'] ?? '').trim();
  final body = lines.sublist(bodyStart).join('\n').trim();
  return ParsedAssistantSkillMarkdown(
    id: id,
    name: rawName.isEmpty ? id : rawName,
    description: description,
    body: body,
  );
}

String _normalizeAssistantSkillId(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$').hasMatch(normalized)) {
    throw const EngineException(errLlmFormat, {'reason': 'skillIdInvalid'});
  }
  return normalized;
}

String _normalizeSkillRelativePath(String value) {
  final trimmed = value.trim().replaceAll('\\', '/');
  if (trimmed.isEmpty || p.isAbsolute(trimmed)) {
    throw const EngineException(errLlmFormat, {'reason': 'skillPathUnsafe'});
  }
  final normalized = p.posix.normalize(trimmed);
  if (normalized == '.' || normalized == '..' || normalized.startsWith('../')) {
    throw const EngineException(errLlmFormat, {'reason': 'skillPathUnsafe'});
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

