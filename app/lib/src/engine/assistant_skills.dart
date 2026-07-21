// 助手技能（v0.4 spec §4 瘦身版）：Markdown 技能查看/编辑/开关 + 12 个内置动作的
// 启用开关，纯提示词注入、无执行语义（custom-js 执行随 spec §2 砍除，此处不列出
// custom-js-agent 类型行）。DB type 值与旧行一致：'builtin-agent'/'markdown-agent'。
// 被砍不搬：ToonFlow 子代理提示词包播种（script_agent_decision 等 13 个 seed）、
// 逐阶段归属映射、AgentSkillActivation XML 格式化。
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'assistant_actions.dart';
import 'assistant_skill_library.dart';
import 'engine.dart';
import 'errors.dart';

const assistantToolSkillType = 'builtin-agent';
const markdownAssistantSkillType = managedMarkdownAssistantSkillType;

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

/// 提供给 Agent 的技能目录项。刻意不带 Markdown 正文或资源路径，避免每轮请求
/// 预先泄露全部技能上下文；正文只能经 activate_skill 的受限路径取得。
class AssistantSkillCatalogEntry {
  final String id;
  final String name;
  final String description;

  const AssistantSkillCatalogEntry({
    required this.id,
    required this.name,
    required this.description,
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
        [
          action.name,
          action.name,
          action.description,
          1,
          assistantToolSkillType,
          now,
          now,
          '',
          '',
          ''
        ],
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
    final managed = importMarkdownAssistantSkill(filePath);
    if (!enabled) updateAssistantSkill(managed.id, enabled: false);
    return assistantSkills().singleWhere((s) => s.id == managed.id);
  }

  /// 仅公开当前启用 Markdown 技能的元数据，供 Agent 选择后再按需激活。
  List<AssistantSkillCatalogEntry> assistantSkillCatalog() => [
        for (final skill in assistantSkills())
          if (skill.type == markdownAssistantSkillType && skill.enabled)
            AssistantSkillCatalogEntry(
              id: skill.id,
              name: skill.name,
              description: skill.description,
            ),
      ];

  /// 返回某个项目、某个 Agent 家族当前已激活的稳定技能 ID 集合。
  Set<String> activatedAssistantSkillIds(
    int projectId, {
    required String family,
  }) {
    final row = db.select(
      'SELECT data FROM o_agentWorkData '
      'WHERE projectId=? AND episodesId IS NULL AND key=?',
      [projectId, _assistantSkillActivationKey(family)],
    ).firstOrNull;
    if (row == null) return <String>{};
    try {
      final decoded = jsonDecode(row['data'] as String? ?? '[]');
      if (decoded is! List) return <String>{};
      return {
        for (final value in decoded)
          if (value is String && value.isNotEmpty) value,
      };
    } on FormatException {
      return <String>{};
    }
  }

  /// 激活一个启用的托管 Markdown 技能，并返回正文与可读取的资源名。
  String activateAssistantSkill(
    int projectId, {
    required String family,
    required String skillName,
  }) {
    final skill = _enabledMarkdownSkill(skillName);
    final parsed = parseAssistantSkillMarkdown(
      readManagedAssistantSkill(skill.id),
      fallbackName: skill.id,
    );
    final resources = _managedSkillResourcePaths(skill.id);
    final active = activatedAssistantSkillIds(projectId, family: family)
      ..add(skill.id);
    _saveActivatedAssistantSkillIds(projectId, family: family, ids: active);

    final resourcesText = resources.isEmpty ? '无' : resources.join('、');
    return '已激活技能「${skill.name}」。\n\n${parsed.body}\n\n可读取资源：$resourcesText';
  }

  /// 只允许读取当前项目、当前 Agent 家族已经激活的托管技能资源。
  String readActivatedAssistantSkillFile(
    int projectId, {
    required String family,
    required String skillName,
    required String relativePath,
  }) {
    final skill = _enabledMarkdownSkill(skillName);
    if (!activatedAssistantSkillIds(projectId, family: family)
        .contains(skill.id)) {
      throw const EngineException(errLlmFormat, {'reason': 'skillMissing'});
    }
    return _readManagedSkillResource(skill.id, relativePath);
  }

  void clearActivatedAssistantSkills(
    int projectId, {
    required String family,
  }) {
    db.execute(
      'DELETE FROM o_agentWorkData WHERE projectId=? '
      'AND episodesId IS NULL AND key=?',
      [projectId, _assistantSkillActivationKey(family)],
    );
  }

  /// 读取 markdown 技能自身目录内的资源文件（路径穿越防护）。
  String readAssistantSkillFile(String id, String relativePath) {
    return _readManagedSkillResource(id, relativePath);
  }

  /// 启用的 markdown 技能正文（注入系统提示词）；文件缺失的技能跳过（尽力而为）。
  List<String> assistantSkillContexts() {
    final contexts = <String>[];
    for (final skill in assistantSkills()) {
      if (skill.type != markdownAssistantSkillType || !skill.enabled) continue;
      try {
        final parsed = parseAssistantSkillMarkdown(
          readManagedAssistantSkill(skill.id),
          fallbackName: skill.id,
        );
        if (parsed.body.isEmpty) continue;
        contexts.add('【技能：${skill.name}】\n${parsed.body}');
      } on EngineException {
        continue; // 技能文件被移动/删除时静默跳过，不阻断对话
      }
    }
    return contexts;
  }

  AssistantSkill _enabledMarkdownSkill(String skillName) {
    final normalized = skillName.trim();
    final matches = [
      for (final skill in assistantSkills())
        if (skill.type == markdownAssistantSkillType &&
            skill.enabled &&
            (skill.id == normalized || skill.name == normalized))
          skill,
    ];
    if (matches.length != 1) {
      throw const EngineException(errLlmFormat, {'reason': 'skillMissing'});
    }
    return matches.single;
  }

  void _saveActivatedAssistantSkillIds(
    int projectId, {
    required String family,
    required Set<String> ids,
  }) {
    final key = _assistantSkillActivationKey(family);
    final data = jsonEncode(ids.toList()..sort());
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = db.select(
      'SELECT id FROM o_agentWorkData '
      'WHERE projectId=? AND episodesId IS NULL AND key=?',
      [projectId, key],
    ).firstOrNull;
    if (row == null) {
      db.execute(
        'INSERT INTO o_agentWorkData (projectId,key,data,createTime,updateTime) '
        'VALUES (?,?,?,?,?)',
        [projectId, key, data, now, now],
      );
      return;
    }
    db.execute(
      'UPDATE o_agentWorkData SET data=?,updateTime=? WHERE id=?',
      [data, now, row['id']],
    );
  }

  List<String> _managedSkillResourcePaths(String id) {
    final root = File(managedAssistantSkillPath(id)).parent
        .resolveSymbolicLinksSync();
    final resources = <String>[];
    for (final entity
        in Directory(root).listSync(recursive: true, followLinks: false)) {
      if (entity is! File ||
          FileSystemEntity.typeSync(entity.path, followLinks: false) !=
              FileSystemEntityType.file) {
        continue;
      }
      final resolved = entity.resolveSymbolicLinksSync();
      if (!p.isWithin(root, resolved)) continue;
      final relative = p.relative(resolved, from: root).replaceAll('\\', '/');
      if (relative.toLowerCase() != 'skill.md') resources.add(relative);
    }
    resources.sort();
    return resources;
  }

  String _readManagedSkillResource(String id, String relativePath) {
    final root = File(managedAssistantSkillPath(id)).parent
        .resolveSymbolicLinksSync();
    final safe = _normalizeSkillRelativePath(relativePath);
    final target = p.normalize(p.absolute(root, safe));
    if (target == root || !p.isWithin(root, target)) {
      throw const EngineException(errLlmFormat, {'reason': 'skillPathUnsafe'});
    }
    if (FileSystemEntity.typeSync(target, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const EngineException(errLlmFormat, {'reason': 'skillMissing'});
    }
    final resolved = File(target).resolveSymbolicLinksSync();
    if (!p.isWithin(root, resolved)) {
      throw const EngineException(errLlmFormat, {'reason': 'skillPathUnsafe'});
    }
    return File(resolved).readAsStringSync();
  }
}

String _assistantSkillActivationKey(String family) =>
    'assistantSkillActivation:${family.trim()}';

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
