// Agent 体系（P5，瘦身版，见 docs/reference 与 spec §4 决策）：
// ToonFlow 的真实 Agent 是多层 Claude 子代理编排 + 向量 RAG 记忆，体量巨大且与本项目
// "显式流水线可见可恢复"的核心设计相悖。DramaFlow 按 spec 既定决策做单层 AgentRunner：
// 工具调用 1:1 映射到已有真实流水线动作（事件/资产/分镜/图片/视频/配音），每次调用都走
// 现有 o_tasks 队列，绝不出现"对话框说做了但任务表查无此事"。
// 记忆：短期消息历史存 o_agentWorkData.data（key='agentChat'，project 级）；
// 长期记忆以本地 note 形式存 memories 表，并用轻量词面检索注入 Agent 上下文。
// 这不是 ToonFlow 完整向量 RAG，但保留本地可编辑、可检索、可替换的接口边界。
// 执行模式对应 ToonFlow 的 auto/manual：manual 每轮只执行一个工具调用后等待用户确认；
// auto 在安全轮次上限内连续执行工具链。
import 'dart:convert';

import 'package:dio/dio.dart';

import 'audio_bind.dart';
import 'compose_episode.dart';
import 'engine.dart';
import 'errors.dart';
import 'events.dart';
import 'novel.dart';
import 'providers/openai_text.dart' show AgentToolDef, AgentTurnResult;
import 'scripts.dart';
import 'storyboard.dart';
import 'video_track.dart';

const agentRoleUser = 'user';
const agentRoleAssistant = 'assistant';
const agentRoleTool = 'tool';

const _maxAutoTurns = 5;
const _agentMemoryRole = 'agent';
const _agentMemoryType = 'note';

class AgentMessage {
  final String role;
  final String content;
  final String? toolName;
  final int createdAt;
  const AgentMessage({
    required this.role,
    required this.content,
    this.toolName,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() =>
      {'role': role, 'content': content, 'toolName': toolName, 'at': createdAt};

  factory AgentMessage.fromJson(Map<String, dynamic> j) => AgentMessage(
        role: j['role'] as String? ?? agentRoleAssistant,
        content: j['content'] as String? ?? '',
        toolName: j['toolName'] as String?,
        createdAt: (j['at'] as num?)?.toInt() ?? 0,
      );
}

class AgentSkill {
  final String id;
  final String name;
  final String description;
  final bool enabled;
  final String type;
  const AgentSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
    required this.type,
  });
}

class AgentDeployment {
  final String key;
  final String name;
  final String vendorId;
  final String modelName;
  final int maxOutputTokens;
  final int temperature;
  final bool disabled;
  const AgentDeployment({
    required this.key,
    required this.name,
    required this.vendorId,
    required this.modelName,
    required this.maxOutputTokens,
    required this.temperature,
    required this.disabled,
  });
}

class AgentMemoryRecord {
  final String id;
  final String name;
  final String content;
  final int createdAt;
  final String embedding;
  const AgentMemoryRecord({
    required this.id,
    required this.name,
    required this.content,
    required this.createdAt,
    required this.embedding,
  });

  factory AgentMemoryRecord.fromRow(Map<String, Object?> row) =>
      AgentMemoryRecord(
        id: row['id'] as String,
        name: row['name'] as String? ?? '',
        content: row['content'] as String? ?? '',
        createdAt: row['createTime'] as int? ?? 0,
        embedding: row['embedding'] as String? ?? '',
      );

  AgentMemoryRecord withEmbedding(String value) => AgentMemoryRecord(
        id: id,
        name: name,
        content: content,
        createdAt: createdAt,
        embedding: value,
      );
}

const _agentSkillType = 'builtin-agent';
const _agentDeploymentType = 'agent-stage';
const _agentDeploymentKeys = [
  'script_gen',
  'event_extract',
  'asset_extract',
  'storyboard_gen',
  'video_prompt_gen',
];

final _tools = <AgentToolDef>[
  const AgentToolDef(
    name: 'get_status',
    description: '查看项目当前进度（章节/事件/剧本/资产/分镜/配音各阶段完成情况），'
        '不产生任何改动，用于决定下一步该做什么。',
    schema: {'type': 'object', 'properties': {}},
  ),
  AgentToolDef(
    name: 'generate_events',
    description: '为章节生成事件摘要。不传 novelIds 时对全部尚未成功生成事件的章节执行。',
    schema: const {
      'type': 'object',
      'properties': {
        'novelIds': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
      },
    },
  ),
  AgentToolDef(
    name: 'extract_assets',
    description: '从剧本提取角色/道具/场景资产。不传 scriptIds 时对全部尚未成功提取的剧本执行。',
    schema: const {
      'type': 'object',
      'properties': {
        'scriptIds': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
      },
    },
  ),
  AgentToolDef(
    name: 'generate_storyboards',
    description: '为指定剧本生成分镜列表（画面提示词/运镜描述）。',
    schema: const {
      'type': 'object',
      'properties': {
        'scriptId': {'type': 'integer'},
      },
      'required': ['scriptId'],
    },
  ),
  AgentToolDef(
    name: 'generate_shot_images',
    description: '为指定剧本的分镜生成首帧图。不传 storyboardIds 时对该剧本全部分镜执行。',
    schema: const {
      'type': 'object',
      'properties': {
        'scriptId': {'type': 'integer'},
        'storyboardIds': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
      },
      'required': ['scriptId'],
    },
  ),
  AgentToolDef(
    name: 'generate_videos',
    description: '为指定剧本的分镜生成视频（需已有首帧图）。不传 storyboardIds 时对该剧本'
        '全部已有首帧图的分镜执行。',
    schema: const {
      'type': 'object',
      'properties': {
        'scriptId': {'type': 'integer'},
        'storyboardIds': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
      },
      'required': ['scriptId'],
    },
  ),
  const AgentToolDef(
    name: 'bind_audio',
    description: '为角色资产自动匹配配音。不传 roleIds 时对全部尚未绑定配音的角色执行。',
    schema: {
      'type': 'object',
      'properties': {
        'roleIds': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
      },
    },
  ),
  AgentToolDef(
    name: 'compose_episode',
    description: '合成整集成片（要求每个分镜都已选定视频）。',
    schema: const {
      'type': 'object',
      'properties': {
        'scriptId': {'type': 'integer'},
      },
      'required': ['scriptId'],
    },
  ),
];

extension AgentApi on Engine {
  String _agentMemoryIsolationKey(int projectId) => 'project:$projectId';

  List<AgentToolDef> get agentTools {
    final skills = agentSkills();
    return [
      for (final skill in skills)
        if (skill.enabled)
          AgentToolDef(
            name: skill.id,
            description: skill.description.isEmpty
                ? _defaultTool(skill.id)?.description ?? ''
                : skill.description,
            schema: _defaultTool(skill.id)?.schema ?? const {},
          ),
    ];
  }

  AgentToolDef? _defaultTool(String id) {
    for (final tool in _tools) {
      if (tool.name == id) return tool;
    }
    return null;
  }

  void _ensureAgentSkillsSeeded() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final tool in _tools) {
      final exists =
          db.select('SELECT id FROM o_skillList WHERE id=?', [tool.name]);
      if (exists.isNotEmpty) continue;
      db.execute(
        'INSERT INTO o_skillList '
        '(id,name,description,state,type,createTime,updateTime,path,md5,embedding) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          tool.name,
          tool.name,
          tool.description,
          1,
          _agentSkillType,
          now,
          now,
          '',
          '',
          '',
        ],
      );
    }
  }

  List<AgentSkill> agentSkills() {
    _ensureAgentSkillsSeeded();
    final rows = db.select(
      'SELECT id,name,description,state,type FROM o_skillList '
      'WHERE type=? ORDER BY createTime ASC, id ASC',
      [_agentSkillType],
    );
    return [
      for (final row in rows)
        AgentSkill(
          id: row['id'] as String,
          name: (row['name'] as String?)?.isNotEmpty == true
              ? row['name'] as String
              : row['id'] as String,
          description: row['description'] as String? ?? '',
          enabled: (row['state'] as int? ?? 1) != 0,
          type: row['type'] as String? ?? _agentSkillType,
        ),
    ];
  }

  void updateAgentSkill(
    String id, {
    String? description,
    bool? enabled,
  }) {
    _ensureAgentSkillsSeeded();
    final row = db.select(
      'SELECT id,description,state FROM o_skillList WHERE id=? AND type=?',
      [id, _agentSkillType],
    ).firstOrNull;
    if (row == null) {
      throw EngineException(errLlmFormat, {'reason': '技能不存在'});
    }
    db.execute(
      'UPDATE o_skillList SET description=?, state=?, updateTime=? '
      'WHERE id=? AND type=?',
      [
        description ?? row['description'] as String? ?? '',
        enabled == null ? row['state'] as int? ?? 1 : (enabled ? 1 : 0),
        DateTime.now().millisecondsSinceEpoch,
        id,
        _agentSkillType,
      ],
    );
  }

  void _ensureAgentDeploymentsSeeded() {
    for (final key in _agentDeploymentKeys) {
      final exists =
          db.select('SELECT id FROM o_agentDeploy WHERE key=? LIMIT 1', [key]);
      if (exists.isNotEmpty) continue;
      final binding = db.select('SELECT value FROM o_setting WHERE key=?',
          ['binding.$key']).firstOrNull?['value'] as String?;
      final split = _splitBinding(binding);
      db.execute(
        'INSERT INTO o_agentDeploy '
        '(key,name,desc,type,vendorId,modelName,model,disabled,maxOutputTokens,temperature) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          key,
          key,
          '',
          _agentDeploymentType,
          split.$1,
          split.$2,
          split.$1.isEmpty || split.$2.isEmpty ? '' : '${split.$1}:${split.$2}',
          0,
          8000,
          70,
        ],
      );
    }
  }

  List<AgentDeployment> agentDeployments() {
    _ensureAgentDeploymentsSeeded();
    return [
      for (final row in db.select(
        'SELECT key,name,vendorId,modelName,disabled,maxOutputTokens,temperature '
        'FROM o_agentDeploy WHERE key IN (${List.filled(_agentDeploymentKeys.length, '?').join(',')}) '
        'ORDER BY CASE key '
        "WHEN 'script_gen' THEN 0 "
        "WHEN 'event_extract' THEN 1 "
        "WHEN 'asset_extract' THEN 2 "
        "WHEN 'storyboard_gen' THEN 3 "
        "WHEN 'video_prompt_gen' THEN 4 ELSE 99 END",
        _agentDeploymentKeys,
      ))
        AgentDeployment(
          key: row['key'] as String,
          name: row['name'] as String? ?? row['key'] as String,
          vendorId: row['vendorId'] as String? ?? '',
          modelName: row['modelName'] as String? ?? '',
          maxOutputTokens: row['maxOutputTokens'] as int? ?? 8000,
          temperature: row['temperature'] as int? ?? 70,
          disabled: _truthy(row['disabled']),
        ),
    ];
  }

  void updateAgentDeployment(
    String key, {
    String? vendorId,
    String? modelName,
    int? maxOutputTokens,
    int? temperature,
    bool? disabled,
  }) {
    if (!_agentDeploymentKeys.contains(key)) {
      throw EngineException(errModelMissing, {'stage': key});
    }
    _ensureAgentDeploymentsSeeded();
    final row = db
        .select('SELECT * FROM o_agentDeploy WHERE key=? LIMIT 1', [key]).first;
    final nextVendor = vendorId ?? row['vendorId'] as String? ?? '';
    final nextModel = modelName ?? row['modelName'] as String? ?? '';
    if (nextVendor.isNotEmpty || nextModel.isNotEmpty) {
      final kind = _modelKind(nextVendor, nextModel);
      if (kind != 'text') {
        throw EngineException(errModelMissing, {
          'stage': key,
          'requiredKind': 'text',
          'actualKind': kind,
        });
      }
    }
    final nextMaxTokens =
        (maxOutputTokens ?? row['maxOutputTokens'] as int? ?? 8000)
            .clamp(256, 64000)
            .toInt();
    final nextTemperature =
        (temperature ?? row['temperature'] as int? ?? 70).clamp(0, 200).toInt();
    db.execute(
      'UPDATE o_agentDeploy SET vendorId=?, modelName=?, model=?, disabled=?, '
      'maxOutputTokens=?, temperature=? WHERE key=?',
      [
        nextVendor,
        nextModel,
        nextVendor.isEmpty || nextModel.isEmpty ? '' : '$nextVendor:$nextModel',
        disabled == null ? row['disabled'] as int? ?? 0 : (disabled ? 1 : 0),
        nextMaxTokens,
        nextTemperature,
        key,
      ],
    );
  }

  (String, String) _splitBinding(String? value) {
    if (value == null) return ('', '');
    final sep = value.indexOf(':');
    if (sep <= 0 || sep == value.length - 1) return ('', '');
    return (value.substring(0, sep), value.substring(sep + 1));
  }

  String _modelKind(String providerId, String modelName) {
    final rows = db.select(
      'SELECT models FROM o_vendorConfig WHERE id=? AND COALESCE(enable,1)=1',
      [providerId],
    );
    if (rows.isEmpty) {
      throw EngineException(errProviderMissing, {'providerId': providerId});
    }
    final decoded = jsonDecode(rows.first['models'] as String? ?? '[]');
    if (decoded is List) {
      for (final item in decoded.whereType<Map>()) {
        final candidate = Map<String, dynamic>.from(item);
        if (candidate['modelId'] == modelName &&
            (candidate['enabled'] == null ||
                candidate['enabled'] == true ||
                candidate['enabled'] == 1 ||
                candidate['enabled'] == '1')) {
          return candidate['kind'] as String? ?? '';
        }
      }
    }
    throw EngineException(errModelMissing, {'modelId': modelName});
  }

  bool _truthy(Object? value) =>
      value == true || value == 1 || value == '1' || value == 'true';

  List<AgentMessage> agentMessages(int projectId) {
    final row = db.select(
      "SELECT data FROM o_agentWorkData WHERE projectId=? AND episodesId IS NULL AND key='agentChat'",
      [projectId],
    ).firstOrNull;
    if (row == null) return const [];
    try {
      final decoded = jsonDecode(row['data'] as String) as List;
      return decoded
          .map((m) => AgentMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void _saveAgentMessages(int projectId, List<AgentMessage> messages) {
    final json = jsonEncode([for (final m in messages) m.toJson()]);
    final exists = db.select(
      "SELECT id FROM o_agentWorkData WHERE projectId=? AND episodesId IS NULL AND key='agentChat'",
      [projectId],
    ).firstOrNull;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (exists == null) {
      db.execute(
        'INSERT INTO o_agentWorkData (projectId,key,data,createTime,updateTime) '
        "VALUES (?,'agentChat',?,?,?)",
        [projectId, json, now, now],
      );
    } else {
      db.execute(
        'UPDATE o_agentWorkData SET data=?, updateTime=? WHERE id=?',
        [json, now, exists['id']],
      );
    }
  }

  void clearAgentMemory(int projectId) {
    db.execute(
      "DELETE FROM o_agentWorkData WHERE projectId=? AND episodesId IS NULL AND key='agentChat'",
      [projectId],
    );
  }

  List<AgentMemoryRecord> agentLongTermMemories(int projectId) {
    final rows = db.select(
      'SELECT id,name,content,createTime,embedding FROM memories '
      'WHERE isolationKey=? AND role=? AND type=? '
      'ORDER BY createTime DESC, id DESC',
      [_agentMemoryIsolationKey(projectId), _agentMemoryRole, _agentMemoryType],
    );
    return [for (final row in rows) AgentMemoryRecord.fromRow(row)];
  }

  String saveAgentMemory(
    int projectId, {
    String? id,
    required String name,
    required String content,
  }) {
    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty) {
      throw EngineException(errLlmFormat, {'reason': '记忆内容不能为空'});
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final memoryId = id ?? 'agent_mem_${DateTime.now().microsecondsSinceEpoch}';
    final existing = db.select(
      'SELECT createTime FROM memories WHERE id=? AND isolationKey=?',
      [memoryId, _agentMemoryIsolationKey(projectId)],
    ).firstOrNull;
    db.execute(
      'INSERT OR REPLACE INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        memoryId,
        name.trim().isEmpty ? '长期记忆' : name.trim(),
        trimmedContent,
        existing?['createTime'] as int? ?? now,
        _memoryEmbeddingJson(name, trimmedContent),
        _agentMemoryIsolationKey(projectId),
        '[]',
        _agentMemoryRole,
        0,
        _agentMemoryType,
      ],
    );
    return memoryId;
  }

  void deleteAgentMemory(int projectId, String id) {
    db.execute(
      'DELETE FROM memories WHERE id=? AND isolationKey=? AND role=? AND type=?',
      [
        id,
        _agentMemoryIsolationKey(projectId),
        _agentMemoryRole,
        _agentMemoryType
      ],
    );
  }

  List<AgentMemoryRecord> searchAgentMemories(
    int projectId,
    String query, {
    int limit = 5,
  }) {
    final records = agentLongTermMemories(projectId);
    final normalizedQuery = _normalizeMemoryText(query);
    final tokens = _memorySearchTokens(normalizedQuery);
    final queryEmbedding = _memoryEmbeddingFromText(normalizedQuery);
    final scored = <(int, AgentMemoryRecord)>[];
    for (var record in records) {
      record = _ensureMemoryEmbedding(projectId, record);
      final score =
          _memoryScore(record, normalizedQuery, tokens, queryEmbedding);
      if (score > 0) scored.add((score, record));
    }
    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      if (byScore != 0) return byScore;
      return b.$2.createdAt.compareTo(a.$2.createdAt);
    });
    return [for (final item in scored.take(limit)) item.$2];
  }

  String _normalizeMemoryText(String text) =>
      text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Set<String> _memorySearchTokens(String query) {
    if (query.isEmpty) return const {};
    final tokens = <String>{};
    for (final part in query.split(' ')) {
      if (part.isNotEmpty) tokens.add(part);
    }
    final compact = query.replaceAll(' ', '');
    if (compact.length <= 12 && compact.isNotEmpty) tokens.add(compact);
    for (var i = 0; i < compact.length - 1; i++) {
      tokens.add(compact.substring(i, i + 2));
    }
    return tokens;
  }

  String _memoryEmbeddingJson(String name, String content) => jsonEncode(
      _memoryEmbeddingFromText(_normalizeMemoryText('$name $content')));

  Map<String, int> _memoryEmbeddingFromText(String text) {
    final tokens = _memorySearchTokens(text);
    final embedding = <String, int>{};
    for (final token in tokens) {
      if (token.length <= 1) continue;
      embedding[token] = (embedding[token] ?? 0) + 1;
    }
    return Map.fromEntries(
        embedding.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  AgentMemoryRecord _ensureMemoryEmbedding(
    int projectId,
    AgentMemoryRecord record,
  ) {
    if (record.embedding.trim().isNotEmpty) return record;
    final embedding = _memoryEmbeddingJson(record.name, record.content);
    db.execute(
      'UPDATE memories SET embedding=? WHERE id=? AND isolationKey=?',
      [embedding, record.id, _agentMemoryIsolationKey(projectId)],
    );
    return record.withEmbedding(embedding);
  }

  Map<String, int> _decodeMemoryEmbedding(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is num)
            entry.key as String: (entry.value as num).toInt(),
      };
    } catch (_) {
      return const {};
    }
  }

  int _embeddingScore(Map<String, int> query, Map<String, int> memory) {
    var score = 0;
    for (final entry in query.entries) {
      final value = memory[entry.key];
      if (value == null) continue;
      score += entry.value < value ? entry.value : value;
    }
    return score;
  }

  int _memoryScore(
    AgentMemoryRecord record,
    String query,
    Set<String> tokens,
    Map<String, int> queryEmbedding,
  ) {
    if (query.isEmpty) return 1;
    final haystack = _normalizeMemoryText('${record.name}\n${record.content}');
    var score = haystack.contains(query) ? 100 : 0;
    for (final token in tokens) {
      if (token.length <= 1) continue;
      if (haystack.contains(token)) score += 10;
    }
    score += _embeddingScore(
      queryEmbedding,
      _decodeMemoryEmbedding(record.embedding),
    );
    return score;
  }

  String _agentSystemPrompt(List<AgentMemoryRecord> memories) {
    const base = '你是短剧创作助手。你可以调用工具推进项目的制作流程'
        '（事件提取→提取资产→生成分镜→生成首帧图→生成视频→配音绑定→合成）。'
        '每次只做用户明确要求或明显下一步需要的动作，不要臆造不存在的 id。'
        '如果不确定该做什么，先调用 get_status 查看进度。';
    if (memories.isEmpty) return base;
    final lines = [
      '',
      '',
      '长期记忆：',
      for (final memory in memories) '- ${memory.name}: ${memory.content}',
    ];
    return '$base${lines.join('\n')}';
  }

  /// Agent 执行模式（auto/manual）持久化。config 由别处拥有，此处直接写 o_setting
  /// 键 agent.useMode（'auto'/'manual'），与 ToonFlow 的 auto/manual 语义一致。
  bool agentUseMode() {
    final row = db
        .select("SELECT value FROM o_setting WHERE key='agent.useMode'")
        .firstOrNull;
    return (row?['value'] as String?) == 'auto';
  }

  void setAgentUseMode(bool autoMode) {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.useMode', autoMode ? 'auto' : 'manual'],
    );
  }

  /// 发送一条用户消息并驱动 Agent 执行（工具调用全部落 o_tasks，可见可恢复）。
  /// manual 模式每轮只执行一个工具调用；auto 模式在安全上限内连续执行工具链。
  Future<void> sendAgentMessage(
    int projectId,
    String text, {
    required bool autoMode,
  }) async {
    final messages = List<AgentMessage>.from(agentMessages(projectId));
    final now = DateTime.now().millisecondsSinceEpoch;
    messages
        .add(AgentMessage(role: agentRoleUser, content: text, createdAt: now));
    _saveAgentMessages(projectId, messages);

    final system = _agentSystemPrompt(searchAgentMemories(projectId, text));

    for (var turn = 0; turn < (autoMode ? _maxAutoTurns : 1); turn++) {
      final history = [
        for (final m in messages)
          {
            'role': m.role == agentRoleTool ? 'assistant' : m.role,
            'content': m.role == agentRoleTool
                ? '（工具 ${m.toolName} 执行结果：${m.content}）'
                : m.content,
          },
      ];
      AgentTurnResult result;
      try {
        final tools = agentTools;
        result = await gateway.generateAgentTurn(
          system,
          history,
          tools,
          stage: 'script_gen',
        );
      } catch (e) {
        final ex = e is EngineException
            ? e
            : (e is DioException
                ? EngineException(errNetwork, {'message': e.message})
                : EngineException(errLlmFormat, {'message': '$e'}));
        messages.add(AgentMessage(
            role: agentRoleAssistant,
            content: '（出错：${ex.errKey}）',
            createdAt: DateTime.now().millisecondsSinceEpoch));
        _saveAgentMessages(projectId, messages);
        return;
      }

      if (!result.isToolCall) {
        messages.add(AgentMessage(
            role: agentRoleAssistant,
            content: result.text ?? '',
            createdAt: DateTime.now().millisecondsSinceEpoch));
        _saveAgentMessages(projectId, messages);
        return;
      }

      final summary = await _runTool(
          projectId, result.toolName!, result.toolArgs ?? const {});
      messages.add(AgentMessage(
        role: agentRoleTool,
        content: summary,
        toolName: result.toolName,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _saveAgentMessages(projectId, messages);
    }
  }

  /// 模型经常用显式空数组表达"不指定具体 id，按默认全部执行"，
  /// 与"未传该字段"语义相同：都应回退到调用方给出的默认集合。
  List<int>? _intList(Map<String, dynamic> args, String key) {
    final raw = args[key];
    if (raw is! List || raw.isEmpty) return null;
    return raw.map((e) => (e as num).toInt()).toList();
  }

  Future<String> _runTool(
      int projectId, String name, Map<String, dynamic> args) async {
    try {
      switch (name) {
        case 'get_status':
          return _statusSummary(projectId);
        case 'generate_events':
          final ids = _intList(args, 'novelIds') ??
              novels(projectId, limit: 100000)
                  .data
                  .where((n) => n.eventState != 1)
                  .map((n) => n.id)
                  .toList();
          if (ids.isEmpty) return '没有需要生成事件的章节。';
          final taskId = generateEvents(projectId, ids);
          return '已提交事件生成任务（任务 #$taskId），涉及 ${ids.length} 个章节。';
        case 'extract_assets':
          final ids = _intList(args, 'scriptIds') ??
              scripts(projectId)
                  .where((s) => s.extractState != 1)
                  .map((s) => s.id)
                  .toList();
          if (ids.isEmpty) return '没有需要提取资产的剧本。';
          final taskId = extractAssets(ids, projectId);
          return '已提交资产提取任务（任务 #$taskId），涉及 ${ids.length} 个剧本。';
        case 'generate_storyboards':
          final scriptId = (args['scriptId'] as num?)?.toInt();
          if (scriptId == null) return '缺少 scriptId 参数。';
          final taskId = generateStoryboards(projectId, scriptId);
          return '已提交分镜生成任务（任务 #$taskId）。';
        case 'generate_shot_images':
          final scriptId = (args['scriptId'] as num?)?.toInt();
          if (scriptId == null) return '缺少 scriptId 参数。';
          final ids = _intList(args, 'storyboardIds') ??
              storyboards(scriptId).map((s) => s.id).toList();
          if (ids.isEmpty) return '该剧本暂无分镜。';
          final taskId =
              batchGenerateStoryboardImages(projectId, ids, compulsory: true);
          return '已提交首帧图生成任务（任务 #$taskId），涉及 ${ids.length} 个分镜。';
        case 'generate_videos':
          final scriptId = (args['scriptId'] as num?)?.toInt();
          if (scriptId == null) return '缺少 scriptId 参数。';
          final ids = _intList(args, 'storyboardIds') ??
              storyboards(scriptId)
                  .where((s) => s.filePath != null)
                  .map((s) => s.id)
                  .toList();
          if (ids.isEmpty) return '该剧本没有已生成首帧图的分镜。';
          final taskId = batchGenerateVideos(projectId, ids);
          return '已提交视频生成任务（任务 #$taskId），涉及 ${ids.length} 个分镜。';
        case 'bind_audio':
          final ids = _intList(args, 'roleIds') ??
              roleAudioBindings(projectId)
                  .where((r) => r.audioAssetId == null)
                  .map((r) => r.roleId)
                  .toList();
          if (ids.isEmpty) return '所有角色都已绑定配音，或项目内没有角色资产。';
          final taskId = batchBindAudio(projectId, ids);
          return '已提交配音匹配任务（任务 #$taskId），涉及 ${ids.length} 个角色。';
        case 'compose_episode':
          final scriptId = (args['scriptId'] as num?)?.toInt();
          if (scriptId == null) return '缺少 scriptId 参数。';
          final result = await composeEpisode(projectId, scriptId);
          return '合成成功：${result.outputRelPath}'
              '${result.durationSec != null ? '（时长 ${result.durationSec!.toStringAsFixed(1)}s）' : ''}。';
        default:
          return '未知工具：$name';
      }
    } catch (e) {
      final ex = e is EngineException
          ? e
          : EngineException(errLlmFormat, {'message': '$e'});
      return '执行失败：${ex.errKey}';
    }
  }

  String _statusSummary(int projectId) {
    final chapters = novels(projectId, limit: 100000).data;
    final chapterDone = chapters.where((c) => c.eventState == 1).length;
    final eventTotal = events(projectId, limit: 1).total;
    final scriptRows = scripts(projectId);
    final scriptDone = scriptRows.where((s) => s.extractState == 1).length;
    final storyboardCount = db.select(
      'SELECT COUNT(*) n FROM o_storyboard WHERE scriptId IN '
      '(SELECT id FROM o_script WHERE projectId=?)',
      [projectId],
    ).first['n'] as int;
    final storyboardImageDone = db.select(
      "SELECT COUNT(*) n FROM o_storyboard WHERE state=? AND scriptId IN "
      '(SELECT id FROM o_script WHERE projectId=?)',
      [sbDone, projectId],
    ).first['n'] as int;
    final roles = roleAudioBindings(projectId);
    final roleBound = roles.where((r) => r.audioAssetId != null).length;
    return '章节 ${chapters.length} 个（事件已生成 $chapterDone 个，共 $eventTotal 条事件）；'
        '剧本 ${scriptRows.length} 个（资产已提取 $scriptDone 个）；'
        '分镜 $storyboardCount 个（首帧图已生成 $storyboardImageDone 个）；'
        '角色 ${roles.length} 个（已绑定配音 $roleBound 个）。';
  }
}
