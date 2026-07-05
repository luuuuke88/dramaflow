import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'errors.dart';

const markdownAgentSkillType = 'markdown-agent';

class ToonFlowMarkdownSkillSeed {
  final String fileName;
  final String attribution;
  final List<String> workspaceDirs;

  const ToonFlowMarkdownSkillSeed({
    required this.fileName,
    required this.attribution,
    this.workspaceDirs = const [],
  });
}

class SeededMarkdownAgentSkill {
  final String id;
  final String name;
  final String description;
  final String path;

  const SeededMarkdownAgentSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.path,
  });
}

const toonFlowMarkdownSkillSeeds = <ToonFlowMarkdownSkillSeed>[
  ToonFlowMarkdownSkillSeed(
    fileName: 'script_agent_decision.md',
    attribution: 'script_agent_decision',
  ),
  ToonFlowMarkdownSkillSeed(
    fileName: 'script_execution_skeleton.md',
    attribution: 'script_execution_skeleton',
  ),
  ToonFlowMarkdownSkillSeed(
    fileName: 'script_execution_adaptation.md',
    attribution: 'script_execution_adaptation',
  ),
  ToonFlowMarkdownSkillSeed(
    fileName: 'script_execution_script.md',
    attribution: 'script_execution_script',
  ),
  ToonFlowMarkdownSkillSeed(
    fileName: 'script_agent_supervision.md',
    attribution: 'script_agent_supervision',
  ),
  ToonFlowMarkdownSkillSeed(
    fileName: 'production_agent_decision.md',
    attribution: 'production_agent_decision',
  ),
  ToonFlowMarkdownSkillSeed(
    fileName: 'production_execution_derive_assets.md',
    attribution: 'production_execution_derive_assets',
  ),
  ToonFlowMarkdownSkillSeed(
    fileName: 'production_execution_generate_assets.md',
    attribution: 'production_execution_generate_assets',
  ),
  ToonFlowMarkdownSkillSeed(
    fileName: 'production_execution_director_plan.md',
    attribution: 'production_execution_director_plan',
  ),
  ToonFlowMarkdownSkillSeed(
    fileName: 'production_execution_storyboard_gen.md',
    attribution: 'production_execution_storyboard_gen',
  ),
  ToonFlowMarkdownSkillSeed(
    fileName: 'production_execution_storyboard_panel.md',
    attribution: 'production_execution_storyboard_panel',
    workspaceDirs: ['production_skills'],
  ),
  ToonFlowMarkdownSkillSeed(
    fileName: 'production_execution_storyboard_table.md',
    attribution: 'production_execution_storyboard_table',
    workspaceDirs: ['production_skills'],
  ),
  ToonFlowMarkdownSkillSeed(
    fileName: 'production_agent_supervision.md',
    attribution: 'production_agent_supervision',
  ),
];

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

List<SeededMarkdownAgentSkill> seedToonFlowMarkdownAgentSkillsInDb(
  Database db,
  String skillsRootPath,
) {
  final root = Directory(skillsRootPath);
  if (!root.existsSync()) return const [];
  final seeded = <SeededMarkdownAgentSkill>[];
  for (final seed in toonFlowMarkdownSkillSeeds) {
    final file = File(p.join(root.path, seed.fileName));
    if (!file.existsSync()) continue;
    seeded.add(_upsertMarkdownAgentSkillInDb(
      db,
      file.path,
      attribution: seed.attribution,
      workspaceDirs: seed.workspaceDirs,
    ));
  }
  return seeded;
}

List<SeededMarkdownAgentSkill> seedProjectProductionMarkdownAgentSkillsInDb(
  Database db,
  String skillsRootPath, {
  required int projectId,
  String? artStyle,
  String? directorManual,
}) {
  final root = Directory(skillsRootPath);
  if (!root.existsSync()) return const [];
  final dirAttributions = <({Directory dir, List<String> attributions})>[];
  final artDir = _manualDirectorSkillsDir(
    root.path,
    'art_skills',
    artStyle,
  );
  if (artDir != null) {
    dirAttributions.add((
      dir: artDir,
      attributions: [
        _projectSkillAttribution('production_agent_execution', projectId),
      ],
    ));
  }
  final storyDir = _manualDirectorSkillsDir(
    root.path,
    'story_skills',
    directorManual,
  );
  if (storyDir != null) {
    dirAttributions.add((
      dir: storyDir,
      attributions: [
        _projectSkillAttribution('production_agent_execution', projectId),
      ],
    ));
  }
  final productionDir = Directory(p.join(root.path, 'production_skills'));
  if (productionDir.existsSync()) {
    dirAttributions.add((
      dir: productionDir,
      attributions: [
        _projectSkillAttribution(
          'production_execution_storyboard_panel',
          projectId,
        ),
        _projectSkillAttribution(
          'production_execution_storyboard_table',
          projectId,
        ),
      ],
    ));
  }

  final seeded = <SeededMarkdownAgentSkill>[];
  final seededPaths = <String>{};
  for (final item in dirAttributions) {
    final files = item.dir
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) => p.extension(file.path).toLowerCase() == '.md')
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final normalized = p.normalize(p.absolute(file.path));
      SeededMarkdownAgentSkill? result;
      for (final attribution in item.attributions) {
        result = _upsertMarkdownAgentSkillInDb(
          db,
          file.path,
          idOverride: _projectMarkdownSkillId(projectId, file.path),
          attribution: attribution,
        );
      }
      if (result != null && seededPaths.add(normalized)) {
        seeded.add(result);
      }
    }
  }
  return seeded;
}

SeededMarkdownAgentSkill _upsertMarkdownAgentSkillInDb(
  Database db,
  String filePath, {
  required String attribution,
  String? idOverride,
  List<String> workspaceDirs = const [],
  List<String> attachedSkillDirs = const [],
}) {
  final parsed = parseAgentSkillFile(filePath);
  final skillId = idOverride ?? parsed.id;
  final existing =
      db.select('SELECT id FROM o_skillList WHERE id=?', [skillId]).firstOrNull;
  final now = DateTime.now().millisecondsSinceEpoch;
  final resources = encodeMarkdownSkillResources(
    workspaceDirs: workspaceDirs,
    attachedSkillDirs: attachedSkillDirs,
  );
  if (existing == null) {
    db.execute(
      'INSERT INTO o_skillList '
      '(id,name,description,state,type,createTime,updateTime,path,md5,embedding) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        skillId,
        parsed.name,
        parsed.description,
        1,
        markdownAgentSkillType,
        now,
        now,
        filePath,
        resources,
        '',
      ],
    );
  } else {
    db.execute(
      'UPDATE o_skillList SET type=?, path=?, md5=?, updateTime=? '
      'WHERE id=?',
      [
        markdownAgentSkillType,
        filePath,
        resources,
        now,
        skillId,
      ],
    );
  }
  db.execute(
    'INSERT OR REPLACE INTO o_skillAttribution (attribution,skillId) '
    'VALUES (?,?)',
    [attribution, skillId],
  );
  return SeededMarkdownAgentSkill(
    id: skillId,
    name: parsed.name,
    description: parsed.description,
    path: filePath,
  );
}

String _projectSkillAttribution(String attribution, int projectId) =>
    '$attribution:project:$projectId';

String _projectMarkdownSkillId(int projectId, String filePath) {
  final parsed = parseAgentSkillFile(filePath);
  return 'project_${projectId}_${parsed.id}';
}

Directory? _manualDirectorSkillsDir(
  String skillsRootPath,
  String kind,
  String? value,
) {
  final name = value?.trim();
  if (name == null || name.isEmpty) return null;
  final root = Directory(p.join(skillsRootPath, kind));
  if (!root.existsSync()) return null;
  final direct = Directory(p.join(root.path, name, 'driector_skills'));
  if (direct.existsSync()) return direct;
  for (final pack in root.listSync(followLinks: false).whereType<Directory>()) {
    final meta = File(p.join(pack.path, 'meta.json'));
    if (!meta.existsSync()) continue;
    try {
      final decoded = jsonDecode(meta.readAsStringSync());
      if (decoded is Map && decoded['name'] == name) {
        final dir = Directory(p.join(pack.path, 'driector_skills'));
        return dir.existsSync() ? dir : null;
      }
    } catch (_) {
      continue;
    }
  }
  return null;
}

String encodeMarkdownSkillResources({
  List<String> workspaceDirs = const [],
  List<String> attachedSkillDirs = const [],
}) {
  if (workspaceDirs.isEmpty && attachedSkillDirs.isEmpty) return '';
  return jsonEncode({
    'workspaceDirs': _normalizedSkillDirs(workspaceDirs),
    'attachedSkillDirs': _normalizedSkillDirs(attachedSkillDirs),
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

List<String> _normalizedSkillDirs(List<String> dirs) => [
      for (final dir in dirs)
        if (dir.trim().isNotEmpty) _normalizeSkillRelativePath(dir),
    ];

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
