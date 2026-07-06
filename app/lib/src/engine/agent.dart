// Agent 体系正在按 ToonFlow 的 scriptAgent / productionAgent 分层形态推进。
// 当前文件保留旧 UI/API 入口，并逐步把 stage registry、记忆、技能和 orchestrator
// 拆到独立纯 Dart 模块。所有会生成媒体或改业务表的动作仍走现有 engine API 与 o_tasks。
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'agent_memory.dart';
import 'agent_orchestrator.dart';
import 'agent_skills.dart';
import 'agent_stage_registry.dart';
import 'assets.dart';
import 'audio_bind.dart';
import 'compose_episode.dart';
import 'engine.dart';
import 'errors.dart';
import 'events.dart';
import 'novel.dart';
import 'providers/openai_text.dart' show AgentToolDef, AgentTurnResult;
import 'scripts.dart';
import 'storyboard.dart';
import 'storyboard_table.dart';
import 'video_track.dart';

export 'agent_skills.dart' show AgentSkillActivation;

const agentRoleUser = 'user';
const agentRoleAssistant = 'assistant';
const agentRoleTool = 'tool';

const _maxAutoTurns = 5;
const _maxConsecutiveAutoToolCalls = 3;
const _agentMemoryRole = 'agent';
const _agentMemoryType = 'note';
const _agentDecisionMemoryRole = 'assistant:decision';
const _scriptAgentFamily = 'scriptAgent';
const _productionAgentFamily = 'productionAgent';
const agentFamilyScript = _scriptAgentFamily;
const agentFamilyProduction = _productionAgentFamily;

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
  final Map<String, dynamic> schema;
  final String script;
  const AgentSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
    required this.type,
    this.schema = const {},
    this.script = '',
  });
}

class _MarkdownSkillResources {
  final List<String> workspaceDirs;
  final List<String> attachedSkillDirs;

  const _MarkdownSkillResources({
    this.workspaceDirs = const [],
    this.attachedSkillDirs = const [],
  });
}

class AgentDeployment {
  final String key;
  final String name;
  final String family;
  final String role;
  final String fallbackStage;
  final String vendorId;
  final String modelName;
  final int maxOutputTokens;
  final int temperature;
  final bool disabled;
  const AgentDeployment({
    required this.key,
    required this.name,
    required this.family,
    required this.role,
    required this.fallbackStage,
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
  final List<String> relatedMessageIds;
  final int? score;
  final List<String> matchedTokens;
  const AgentMemoryRecord({
    required this.id,
    required this.name,
    required this.content,
    required this.createdAt,
    required this.embedding,
    this.relatedMessageIds = const [],
    this.score,
    this.matchedTokens = const [],
  });

  factory AgentMemoryRecord.fromRow(Map<String, Object?> row) =>
      AgentMemoryRecord(
        id: row['id'] as String,
        name: row['name'] as String? ?? '',
        content: row['content'] as String? ?? '',
        createdAt: row['createTime'] as int? ?? 0,
        embedding: row['embedding'] as String? ?? '',
        relatedMessageIds: _decodeAgentMemoryIdList(row['relatedMessageIds']),
      );

  factory AgentMemoryRecord.fromEntry(AgentMemoryEntry entry) =>
      AgentMemoryRecord(
        id: entry.id,
        name: entry.name,
        content: entry.content,
        createdAt: entry.createdAt,
        embedding: entry.embedding,
        relatedMessageIds: entry.relatedMessageIds,
        score: entry.score,
        matchedTokens: entry.matchedTokens,
      );

  AgentMemoryRecord copyWith({
    String? embedding,
    int? score,
    List<String>? matchedTokens,
  }) =>
      AgentMemoryRecord(
        id: id,
        name: name,
        content: content,
        createdAt: createdAt,
        embedding: embedding ?? this.embedding,
        relatedMessageIds: relatedMessageIds,
        score: score ?? this.score,
        matchedTokens: matchedTokens ?? this.matchedTokens,
      );

  AgentMemoryRecord withEmbedding(String value) => copyWith(embedding: value);
}

List<String> _decodeAgentMemoryIdList(Object? value) {
  if (value is! String || value.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(value);
    if (decoded is List) {
      return [
        for (final item in decoded)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ];
    }
  } catch (_) {
    return const [];
  }
  return const [];
}

const _agentSkillType = 'builtin-agent';
const _customAgentSkillType = 'custom-js-agent';
const _markdownAgentSkillType = markdownAgentSkillType;
const _customJsConsoleMethods = {'log', 'info', 'warn', 'error', 'debug'};
const _customJsSetMethods = {
  'has',
  'add',
  'delete',
  'clear',
  'keys',
  'values',
  'entries',
  'forEach',
};
const _agentDeploymentType = 'agent-stage';
const _agentToolAuditRoles = {agentRoleTool};
const _agentToolAuditRoleSuffixes = {':tool'};

final _tools = <AgentToolDef>[
  const AgentToolDef(
    name: 'deepRetrieve',
    description: '按关键词深度召回 Agent 历史摘要，并展开相关原始对话消息。'
        '用于找回较早的角色设定、剧情约束、制作决策。'
        '结果会同时返回 memories 文本列表和 records 结构化来源。',
    schema: {
      'type': 'object',
      'properties': {
        'keyword': {'type': 'string'},
        'query': {
          'type': 'string',
          'description': 'keyword 的语义化别名，适合模型按“查询内容”组织参数。',
        },
        'question': {
          'type': 'string',
          'description': 'keyword 的自然语言别名，适合“继续/下一步/回想”场景。',
        },
        'text': {
          'type': 'string',
          'description': 'keyword 的文本别名。',
        },
        'prompt': {
          'type': 'string',
          'description': 'keyword 的提示词别名。',
        },
        'limit': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。限制返回的原始记忆条数，默认使用全局 RAG 配置。',
        },
        'topK': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。limit 的常见 RAG 别名，限制返回的记忆条数。',
        },
        'top_k': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。topK 的 snake_case 别名。',
        },
        'maxResults': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。limit 的自然语言别名，限制返回结果数。',
        },
        'max_results': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。maxResults 的 snake_case 别名。',
        },
        'k': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。topK 的简写别名。',
        },
        'role': {
          'type': 'string',
          'description': '可选。只返回指定 role 的记忆，例如 user 或 assistant:supervision。',
        },
        'roles': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。只返回这些 role 的记忆。',
        },
        'excludeRole': {
          'type': 'string',
          'description': '可选。排除指定 role 的记忆，例如 assistant:decision:tool。',
        },
        'excludeRoles': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。排除这些 role 的记忆，用于避开工具审计噪声。',
        },
        'excludeRoleSuffix': {
          'type': 'string',
          'description': '可选。排除 role 以该后缀结尾的记忆，例如 :tool。',
        },
        'excludeRoleSuffixes': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。排除 role 以这些后缀结尾的记忆，用于避开多阶段工具审计噪声。',
        },
        'type': {
          'type': 'string',
          'enum': ['message', 'summary', 'note'],
          'description': '可选。只返回指定类型的记忆：message 原始对话，summary 摘要，note 长期记忆。',
        },
        'types': {
          'type': 'array',
          'items': {
            'type': 'string',
            'enum': ['message', 'summary', 'note'],
          },
          'description': '可选。只返回这些类型的记忆。',
        },
        'scope': {
          'type': 'string',
          'enum': ['conversation', 'summary', 'long_term', 'all'],
          'description':
              '可选。按记忆层级召回：conversation 对话记忆，summary 摘要，long_term 长期记忆，all 全部。',
        },
        'scopes': {
          'type': 'array',
          'items': {
            'type': 'string',
            'enum': ['conversation', 'summary', 'long_term', 'all'],
          },
          'description': '可选。按多个记忆层级召回。',
        },
        'excludeIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。排除这些已读 memory id，避免重复返回同一条记忆。',
        },
        'excludeMemoryIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。excludeIds 的语义化别名。',
        },
      },
    },
  ),
  const AgentToolDef(
    name: 'activate_skill',
    description: '激活一个 Markdown 技能，把技能正文加载到当前 Agent 上下文中。',
    schema: {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'skill': {
          'type': 'string',
          'description': 'name 的自然别名，适合模型按“技能”组织参数。',
        },
        'skillName': {
          'type': 'string',
          'description': 'name 的驼峰别名。',
        },
        'skillId': {
          'type': 'string',
          'description': 'name 的技能 id 别名。',
        },
        'skill_name': {
          'type': 'string',
          'description': 'name 的 snake_case 别名。',
        },
      },
    },
  ),
  const AgentToolDef(
    name: 'read_skill_file',
    description: '读取已安装 Markdown 技能目录内的补充文件。只能读取该技能目录下的相对路径。'
        '如果当前只激活了一个技能，可只传 filePath；激活多个技能时请同时传 name。',
    schema: {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'skill': {
          'type': 'string',
          'description': 'name 的自然别名，适合模型按“技能”组织参数。',
        },
        'skillName': {
          'type': 'string',
          'description': 'name 的驼峰别名。',
        },
        'skillId': {
          'type': 'string',
          'description': 'name 的技能 id 别名。',
        },
        'skill_name': {
          'type': 'string',
          'description': 'name 的 snake_case 别名。',
        },
        'filePath': {
          'type': 'string',
          'description': '资源文件的相对路径，来自 activate_skill 返回的 skill_resources',
        },
        'path': {
          'type': 'string',
          'description': '兼容旧调用的 filePath 别名。',
        },
        'file': {
          'type': 'string',
          'description': 'filePath 的自然别名，适合模型按“文件”组织参数。',
        },
        'filename': {
          'type': 'string',
          'description': 'filePath 的文件名别名。',
        },
        'relativePath': {
          'type': 'string',
          'description': 'filePath 的相对路径别名。',
        },
      },
    },
  ),
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

Map<String, dynamic> _skillSchema(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
  } catch (_) {
    return const {};
  }
}

Object? _customJsMutableValue(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        '${entry.key}': _customJsMutableValue(entry.value),
    };
  }
  if (value is Iterable && value is! String) {
    return [for (final item in value) _customJsMutableValue(item)];
  }
  return value;
}

// 受限 JS-like 解释器：只开放 projectId/args 和少量纯表达式，避免自定义技能触达系统资源。
class _CustomAgentSkillRuntime {
  final Map<String, Object?> _scope;
  final math.Random _random = math.Random();

  _CustomAgentSkillRuntime({
    required int projectId,
    required Map<String, dynamic> args,
  }) : _scope = {
          'projectId': projectId,
          'args': _customJsMutableValue(args),
          'Array': const _CustomJsBuiltin('Array'),
          'Boolean': const _CustomJsBuiltin('Boolean'),
          'console': const _CustomJsBuiltin('console'),
          'Date': const _CustomJsBuiltin('Date'),
          'Error': const _CustomJsBuiltin('Error'),
          'JSON': const _CustomJsBuiltin('JSON'),
          'Map': const _CustomJsBuiltin('Map'),
          'Math': const _CustomJsBuiltin('Math'),
          'Number': const _CustomJsBuiltin('Number'),
          'Object': const _CustomJsBuiltin('Object'),
          'RegExp': const _CustomJsBuiltin('RegExp'),
          'String': const _CustomJsBuiltin('String'),
          'isFinite': const _CustomJsBuiltin('isFinite'),
          'isNaN': const _CustomJsBuiltin('isNaN'),
          'parseFloat': const _CustomJsBuiltin('parseFloat'),
          'parseInt': const _CustomJsBuiltin('parseInt'),
        };

  String run(String script) {
    final result = _runStatements(script);
    if (result is _CustomJsReturnValue) {
      return _stringifyReturn(result.value);
    }
    if (result != null) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_control_flow',
      });
    }
    throw EngineException(errLlmFormat, {'reason': 'custom_skill_return'});
  }

  _CustomJsStatementResult? _runStatements(String script) {
    for (final statement in _splitStatements(script)) {
      final trimmed = statement.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed == 'break') return const _CustomJsBreakValue();
      if (trimmed == 'continue') return const _CustomJsContinueValue();
      if (_startsWithWord(trimmed, 0, 'throw')) {
        final expression = _trimTrailingSemicolon(
          trimmed.substring('throw'.length).trim(),
        );
        if (expression.isEmpty) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_throw',
          });
        }
        final error = _evaluate(expression);
        throw error ??
            EngineException(errLlmFormat, {
              'reason': 'custom_skill_throw_null',
            });
      }
      final function = _readFunctionDeclaration(trimmed);
      if (function != null) {
        _scope[function.name] = function;
        continue;
      }
      final tryStatement = _readTryStatement(trimmed);
      if (tryStatement != null) {
        try {
          final result = _runStatements(tryStatement.body);
          if (result != null) return result;
        } catch (error) {
          final bindings = tryStatement.errorName == null
              ? <String, Object?>{}
              : <String, Object?>{
                  tryStatement.errorName!: _customJsErrorObject(error),
                };
          final result = _withScopeBindings(
            bindings,
            () => _runStatements(tryStatement.catchBody),
          );
          if (result != null) return result;
        }
        continue;
      }
      final ifStatement = _readIfStatement(trimmed);
      if (ifStatement != null) {
        final branch = _isTruthy(_evaluate(ifStatement.condition))
            ? ifStatement.whenTrue
            : ifStatement.whenFalse;
        if (branch == null) continue;
        final result = _runStatements(branch);
        if (result != null) return result;
        continue;
      }
      final switchStatement = _readSwitchStatement(trimmed);
      if (switchStatement != null) {
        final result = _runSwitchStatement(switchStatement);
        if (result != null) return result;
        continue;
      }
      final whileStatement = _readWhileStatement(trimmed);
      if (whileStatement != null) {
        var guard = 0;
        while (_isTruthy(_evaluate(whileStatement.condition))) {
          guard++;
          if (guard > 10000) {
            throw EngineException(errLlmFormat, {
              'reason': 'custom_skill_while_guard',
            });
          }
          final result = _runStatements(whileStatement.body);
          if (result is _CustomJsReturnValue) return result;
          if (result is _CustomJsBreakValue) break;
          if (result is _CustomJsContinueValue) continue;
          if (result != null) return result;
        }
        continue;
      }
      final forOfStatement = _readForOfStatement(trimmed);
      if (forOfStatement != null) {
        final iterable = _forOfIterable(
          _evaluate(forOfStatement.iterable),
          forOfStatement.iterable,
        );
        for (final item in iterable) {
          final bindings = <String, Object?>{};
          _bindCallbackParam(
            forOfStatement.itemPattern,
            item,
            bindings,
            'forOf',
          );
          final result = _withScopeBindings(
            bindings,
            () => _runStatements(forOfStatement.body),
          );
          if (result is _CustomJsReturnValue) return result;
          if (result is _CustomJsBreakValue) break;
          if (result is _CustomJsContinueValue) continue;
          if (result != null) return result;
        }
        continue;
      }
      final forInStatement = _readForInStatement(trimmed);
      if (forInStatement != null) {
        final keys = _forInKeys(
          _evaluate(forInStatement.objectExpression),
          forInStatement.objectExpression,
        );
        var guard = 0;
        for (final key in keys) {
          guard++;
          if (guard > 10000) {
            throw EngineException(errLlmFormat, {
              'reason': 'custom_skill_for_in_guard',
            });
          }
          final bindings = <String, Object?>{};
          _bindCallbackParam(
            forInStatement.keyPattern,
            key,
            bindings,
            'forIn',
          );
          final result = _withScopeBindings(
            bindings,
            () => _runStatements(forInStatement.body),
          );
          if (result is _CustomJsReturnValue) return result;
          if (result is _CustomJsBreakValue) break;
          if (result is _CustomJsContinueValue) continue;
          if (result != null) return result;
        }
        continue;
      }
      final forStatement = _readForStatement(trimmed);
      if (forStatement != null) {
        _runForInitializer(forStatement.initializer);
        var guard = 0;
        while (forStatement.condition.isEmpty ||
            _isTruthy(_evaluate(forStatement.condition))) {
          guard++;
          if (guard > 10000) {
            throw EngineException(errLlmFormat, {
              'reason': 'custom_skill_for_guard',
            });
          }
          final result = _runStatements(forStatement.body);
          if (result is _CustomJsReturnValue) return result;
          if (result is _CustomJsBreakValue) break;
          _runForUpdate(forStatement.update);
          if (result is _CustomJsContinueValue) continue;
          if (result != null) return result;
        }
        continue;
      }
      final destructuredDeclaration = RegExp(
        r'^(?:const|let|var)\s+([\[{][\s\S]+[\]}])\s*=\s*([\s\S]+)$',
      ).firstMatch(trimmed);
      if (destructuredDeclaration != null) {
        final bindings = <String, Object?>{};
        _bindCallbackParam(
          destructuredDeclaration.group(1)!,
          _evaluate(destructuredDeclaration.group(2)!),
          bindings,
          'declaration',
        );
        for (final entry in bindings.entries) {
          _scope[entry.key] = entry.value;
        }
        continue;
      }
      final declaration = RegExp(
        r'^(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([\s\S]+)$',
      ).firstMatch(trimmed);
      if (declaration != null) {
        _scope[declaration.group(1)!] = _evaluate(declaration.group(2)!);
        continue;
      }
      if (_runVariableUpdate(trimmed)) continue;
      if (_runMemberUpdate(trimmed)) continue;
      if (_runMemberLogicalAssignment(trimmed)) continue;
      if (_runMemberAssignment(trimmed)) continue;
      final assignment = RegExp(
        r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([\s\S]+)$',
      ).firstMatch(trimmed);
      if (assignment != null) {
        final name = assignment.group(1)!;
        if (!_scope.containsKey(name)) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_unknown_variable',
            'expression': name,
          });
        }
        _scope[name] = _evaluate(assignment.group(2)!);
        continue;
      }
      if (trimmed == 'return') return const _CustomJsReturnValue(null);
      if (trimmed.startsWith('return ')) {
        final result = _evaluate(trimmed.substring('return '.length));
        return _CustomJsReturnValue(result);
      }
      _evaluate(trimmed);
      continue;
    }
    return null;
  }

  _CustomJsIfStatement? _readIfStatement(String statement) {
    final source = _trimTrailingSemicolon(statement.trim());
    if (!source.startsWith('if')) return null;
    var index = 2;
    if (index < source.length &&
        source[index].trim().isNotEmpty &&
        source[index] != '(') {
      return null;
    }
    index = _skipWhitespace(source, index);
    if (index >= source.length || source[index] != '(') return null;
    final condition = _readBalanced(source, index, '(', ')');
    index = _skipWhitespace(source, condition.end);
    if (index >= source.length || source[index] != '{') return null;
    final whenTrue = _readBalanced(source, index, '{', '}');
    index = _skipWhitespace(source, whenTrue.end);
    String? whenFalse;
    if (_startsWithWord(source, index, 'else')) {
      index = _skipWhitespace(source, index + 'else'.length);
      if (index < source.length && source[index] == '{') {
        final elseBlock = _readBalanced(source, index, '{', '}');
        whenFalse = elseBlock.text;
        index = _skipWhitespace(source, elseBlock.end);
      } else if (_startsWithWord(source, index, 'if')) {
        whenFalse = source.substring(index).trim();
        index = source.length;
      } else {
        return null;
      }
    }
    if (_trimTrailingSemicolon(source.substring(index)).trim().isNotEmpty) {
      return null;
    }
    return _CustomJsIfStatement(
      condition: condition.text,
      whenTrue: whenTrue.text,
      whenFalse: whenFalse,
    );
  }

  _CustomJsTryStatement? _readTryStatement(String statement) {
    final source = _trimTrailingSemicolon(statement.trim());
    if (!_startsWithWord(source, 0, 'try')) return null;
    var index = _skipWhitespace(source, 'try'.length);
    if (index >= source.length || source[index] != '{') return null;
    final body = _readBalanced(source, index, '{', '}');
    index = _skipWhitespace(source, body.end);
    if (!_startsWithWord(source, index, 'catch')) return null;
    index = _skipWhitespace(source, index + 'catch'.length);
    String? errorName;
    if (index < source.length && source[index] == '(') {
      final rawParam = _readBalanced(source, index, '(', ')');
      final param = rawParam.text.trim();
      if (param.isNotEmpty) {
        final identifier = _readIdentifier(param, 0);
        if (identifier == null || identifier.end != param.length) {
          return null;
        }
        errorName = param;
      }
      index = _skipWhitespace(source, rawParam.end);
    }
    if (index >= source.length || source[index] != '{') return null;
    final catchBody = _readBalanced(source, index, '{', '}');
    index = _skipWhitespace(source, catchBody.end);
    if (_trimTrailingSemicolon(source.substring(index)).trim().isNotEmpty) {
      return null;
    }
    return _CustomJsTryStatement(
      body: body.text,
      errorName: errorName,
      catchBody: catchBody.text,
    );
  }

  _CustomJsStatementResult? _runSwitchStatement(
    _CustomJsSwitchStatement statement,
  ) {
    final value = _evaluate(statement.expression);
    var startIndex = -1;
    var defaultIndex = -1;
    for (var i = 0; i < statement.clauses.length; i++) {
      final clause = statement.clauses[i];
      if (clause.matchExpression == null) {
        defaultIndex = i;
        continue;
      }
      if (_compareValues(value, _evaluate(clause.matchExpression!), '===')) {
        startIndex = i;
        break;
      }
    }
    if (startIndex < 0) startIndex = defaultIndex;
    if (startIndex < 0) return null;
    for (var i = startIndex; i < statement.clauses.length; i++) {
      final result = _runStatements(statement.clauses[i].body);
      if (result is _CustomJsBreakValue) return null;
      if (result != null) return result;
    }
    return null;
  }

  _CustomJsSwitchStatement? _readSwitchStatement(String statement) {
    final source = _trimTrailingSemicolon(statement.trim());
    if (!_startsWithWord(source, 0, 'switch')) return null;
    var index = _skipWhitespace(source, 'switch'.length);
    if (index >= source.length || source[index] != '(') return null;
    final expression = _readBalanced(source, index, '(', ')');
    index = _skipWhitespace(source, expression.end);
    if (index >= source.length || source[index] != '{') return null;
    final body = _readBalanced(source, index, '{', '}');
    index = _skipWhitespace(source, body.end);
    if (_trimTrailingSemicolon(source.substring(index)).trim().isNotEmpty) {
      return null;
    }
    return _CustomJsSwitchStatement(
      expression: expression.text,
      clauses: _readSwitchClauses(body.text),
    );
  }

  List<_CustomJsSwitchClause> _readSwitchClauses(String body) {
    final first = _readNextSwitchLabel(body, 0);
    if (first == null) {
      if (body.trim().isNotEmpty) {
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_switch',
        });
      }
      return const [];
    }
    if (body.substring(0, first.start).trim().isNotEmpty) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_switch',
      });
    }
    final clauses = <_CustomJsSwitchClause>[];
    _CustomJsSwitchLabel? label = first;
    while (label != null) {
      final next = _readNextSwitchLabel(body, label.bodyStart);
      clauses.add(
        _CustomJsSwitchClause(
          matchExpression: label.matchExpression,
          body: body.substring(label.bodyStart, next?.start ?? body.length),
        ),
      );
      label = next;
    }
    return clauses;
  }

  _CustomJsSwitchLabel? _readNextSwitchLabel(String source, int start) {
    var quote = '';
    var escaped = false;
    var paren = 0;
    var bracket = 0;
    var brace = 0;
    for (var i = start; i < source.length; i++) {
      final char = source[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (quote.isNotEmpty) {
        if (char == quote) quote = '';
        continue;
      }
      final regexLiteral = _readRegexLiteral(
        source,
        i,
        requireStartContext: true,
      );
      if (regexLiteral != null) {
        i = regexLiteral.end - 1;
        continue;
      }
      if (char == '"' || char == "'" || char == '`') {
        quote = char;
        continue;
      }
      if (char == '(') paren++;
      if (char == ')') paren--;
      if (char == '[') bracket++;
      if (char == ']') bracket--;
      if (char == '{') brace++;
      if (char == '}') brace--;
      if (paren != 0 || bracket != 0 || brace != 0) continue;
      if (_startsWithWord(source, i, 'case')) {
        final expressionStart = _skipWhitespace(source, i + 'case'.length);
        final colon = _findSwitchCaseColon(source, expressionStart);
        if (colon < 0) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_switch_case',
          });
        }
        final expression = source.substring(expressionStart, colon).trim();
        if (expression.isEmpty) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_switch_case',
          });
        }
        return _CustomJsSwitchLabel(
          matchExpression: expression,
          start: i,
          bodyStart: colon + 1,
        );
      }
      if (_startsWithWord(source, i, 'default')) {
        final colon = _findSwitchCaseColon(
          source,
          _skipWhitespace(source, i + 'default'.length),
        );
        if (colon < 0) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_switch_default',
          });
        }
        final beforeColon =
            source.substring(i + 'default'.length, colon).trim();
        if (beforeColon.isNotEmpty) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_switch_default',
          });
        }
        return _CustomJsSwitchLabel(
          matchExpression: null,
          start: i,
          bodyStart: colon + 1,
        );
      }
    }
    return null;
  }

  int _findSwitchCaseColon(String source, int start) {
    var quote = '';
    var escaped = false;
    var paren = 0;
    var bracket = 0;
    var brace = 0;
    var ternaryDepth = 0;
    for (var i = start; i < source.length; i++) {
      final char = source[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (quote.isNotEmpty) {
        if (char == quote) quote = '';
        continue;
      }
      final regexLiteral = _readRegexLiteral(
        source,
        i,
        requireStartContext: true,
      );
      if (regexLiteral != null) {
        i = regexLiteral.end - 1;
        continue;
      }
      if (char == '"' || char == "'" || char == '`') {
        quote = char;
        continue;
      }
      if (char == '(') paren++;
      if (char == ')') paren--;
      if (char == '[') bracket++;
      if (char == ']') bracket--;
      if (char == '{') brace++;
      if (char == '}') brace--;
      if (paren != 0 || bracket != 0 || brace != 0) continue;
      if (char == '?') {
        ternaryDepth++;
        continue;
      }
      if (char == ':') {
        if (ternaryDepth > 0) {
          ternaryDepth--;
          continue;
        }
        return i;
      }
    }
    return -1;
  }

  _CustomJsFunction? _readFunctionDeclaration(String statement) {
    final source = _trimTrailingSemicolon(statement.trim());
    if (!_startsWithWord(source, 0, 'function')) return null;
    var index = _skipWhitespace(source, 'function'.length);
    final name = _readIdentifier(source, index);
    if (name == null) return null;
    index = _skipWhitespace(source, name.end);
    if (index >= source.length || source[index] != '(') return null;
    final rawParams = _readBalanced(source, index, '(', ')');
    final params = _readFunctionParams(rawParams.text, name.text);
    index = _skipWhitespace(source, rawParams.end);
    if (index >= source.length || source[index] != '{') return null;
    final body = _readBalanced(source, index, '{', '}');
    index = _skipWhitespace(source, body.end);
    if (_trimTrailingSemicolon(source.substring(index)).trim().isNotEmpty) {
      return null;
    }
    return _CustomJsFunction(
      name: name.text,
      params: params,
      body: body.text,
    );
  }

  _CustomJsFunction? _readFunctionExpression(
    String expression,
    String fallbackName,
  ) {
    final source = _trimTrailingSemicolon(expression.trim());
    if (!_startsWithWord(source, 0, 'function')) return null;
    var index = _skipWhitespace(source, 'function'.length);
    var functionName = fallbackName;
    final name = _readIdentifier(source, index);
    if (name != null) {
      functionName = name.text;
      index = _skipWhitespace(source, name.end);
    }
    if (index >= source.length || source[index] != '(') return null;
    final rawParams = _readBalanced(source, index, '(', ')');
    final params = _readFunctionParams(rawParams.text, functionName);
    index = _skipWhitespace(source, rawParams.end);
    if (index >= source.length || source[index] != '{') return null;
    final body = _readBalanced(source, index, '{', '}');
    index = _skipWhitespace(source, body.end);
    if (_trimTrailingSemicolon(source.substring(index)).trim().isNotEmpty) {
      return null;
    }
    return _CustomJsFunction(
      name: functionName,
      params: params,
      body: body.text,
    );
  }

  _CustomJsWhileStatement? _readWhileStatement(String statement) {
    final source = _trimTrailingSemicolon(statement.trim());
    if (!source.startsWith('while')) return null;
    var index = 5;
    if (index < source.length &&
        source[index].trim().isNotEmpty &&
        source[index] != '(') {
      return null;
    }
    index = _skipWhitespace(source, index);
    if (index >= source.length || source[index] != '(') return null;
    final condition = _readBalanced(source, index, '(', ')');
    index = _skipWhitespace(source, condition.end);
    if (index >= source.length || source[index] != '{') return null;
    final body = _readBalanced(source, index, '{', '}');
    index = _skipWhitespace(source, body.end);
    if (_trimTrailingSemicolon(source.substring(index)).trim().isNotEmpty) {
      return null;
    }
    return _CustomJsWhileStatement(
      condition: condition.text,
      body: body.text,
    );
  }

  _CustomJsForOfStatement? _readForOfStatement(String statement) {
    final source = _trimTrailingSemicolon(statement.trim());
    if (!source.startsWith('for')) return null;
    var index = 3;
    if (index < source.length &&
        source[index].trim().isNotEmpty &&
        source[index] != '(') {
      return null;
    }
    index = _skipWhitespace(source, index);
    if (index >= source.length || source[index] != '(') return null;
    final header = _readBalanced(source, index, '(', ')');
    final match = RegExp(
      r'^(?:(?:const|let|var)\s+)?([\s\S]+?)\s+of\s+([\s\S]+)$',
    ).firstMatch(header.text.trim());
    if (match == null) return null;
    index = _skipWhitespace(source, header.end);
    if (index >= source.length || source[index] != '{') return null;
    final body = _readBalanced(source, index, '{', '}');
    index = _skipWhitespace(source, body.end);
    if (_trimTrailingSemicolon(source.substring(index)).trim().isNotEmpty) {
      return null;
    }
    return _CustomJsForOfStatement(
      itemPattern: match.group(1)!.trim(),
      iterable: match.group(2)!.trim(),
      body: body.text,
    );
  }

  Iterable<Object?> _forOfIterable(Object? value, String expression) {
    if (value is _CustomJsMap) return _customJsMapEntries(value);
    if (value is Iterable && value is! String) return value;
    throw EngineException(errLlmFormat, {
      'reason': 'custom_skill_for_of',
      'expression': expression,
    });
  }

  _CustomJsForInStatement? _readForInStatement(String statement) {
    final source = _trimTrailingSemicolon(statement.trim());
    if (!source.startsWith('for')) return null;
    var index = 3;
    if (index < source.length &&
        source[index].trim().isNotEmpty &&
        source[index] != '(') {
      return null;
    }
    index = _skipWhitespace(source, index);
    if (index >= source.length || source[index] != '(') return null;
    final header = _readBalanced(source, index, '(', ')');
    final match = RegExp(
      r'^(?:(?:const|let|var)\s+)?([\s\S]+?)\s+in\s+([\s\S]+)$',
    ).firstMatch(header.text.trim());
    if (match == null) return null;
    index = _skipWhitespace(source, header.end);
    if (index >= source.length || source[index] != '{') return null;
    final body = _readBalanced(source, index, '{', '}');
    index = _skipWhitespace(source, body.end);
    if (_trimTrailingSemicolon(source.substring(index)).trim().isNotEmpty) {
      return null;
    }
    return _CustomJsForInStatement(
      keyPattern: match.group(1)!.trim(),
      objectExpression: match.group(2)!.trim(),
      body: body.text,
    );
  }

  _CustomJsForStatement? _readForStatement(String statement) {
    final source = _trimTrailingSemicolon(statement.trim());
    if (!source.startsWith('for')) return null;
    var index = 3;
    if (index < source.length &&
        source[index].trim().isNotEmpty &&
        source[index] != '(') {
      return null;
    }
    index = _skipWhitespace(source, index);
    if (index >= source.length || source[index] != '(') return null;
    final header = _readBalanced(source, index, '(', ')');
    if (RegExp(r'\s+of\s+').hasMatch(header.text)) return null;
    final parts = _splitTopLevel(header.text, ';');
    if (parts.length != 3) return null;
    index = _skipWhitespace(source, header.end);
    if (index >= source.length || source[index] != '{') return null;
    final body = _readBalanced(source, index, '{', '}');
    index = _skipWhitespace(source, body.end);
    if (_trimTrailingSemicolon(source.substring(index)).trim().isNotEmpty) {
      return null;
    }
    return _CustomJsForStatement(
      initializer: parts[0].trim(),
      condition: parts[1].trim(),
      update: parts[2].trim(),
      body: body.text,
    );
  }

  void _runForInitializer(String statement) {
    final trimmed = statement.trim();
    if (trimmed.isEmpty) return;
    final result = _runStatements(trimmed);
    if (result != null) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_for_initializer',
      });
    }
  }

  void _runForUpdate(String statement) {
    final trimmed = statement.trim();
    if (trimmed.isEmpty) return;
    if (_runVariableUpdate(trimmed)) return;
    final result = _runStatements(trimmed);
    if (result != null) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_for_update',
      });
    }
  }

  bool _runVariableUpdate(String statement) {
    final source = _trimTrailingSemicolon(statement.trim());
    final postfix = RegExp(
      r'^([A-Za-z_][A-Za-z0-9_]*)\s*(\+\+|--)$',
    ).firstMatch(source);
    if (postfix != null) {
      _updateNumericVariable(
        postfix.group(1)!,
        postfix.group(2)! == '++' ? 1 : -1,
      );
      return true;
    }
    final prefix = RegExp(
      r'^(\+\+|--)\s*([A-Za-z_][A-Za-z0-9_]*)$',
    ).firstMatch(source);
    if (prefix != null) {
      _updateNumericVariable(
        prefix.group(2)!,
        prefix.group(1)! == '++' ? 1 : -1,
      );
      return true;
    }
    final logical = RegExp(
      r'^([A-Za-z_][A-Za-z0-9_]*)\s*(\|\||&&|\?\?)=\s*([\s\S]+)$',
    ).firstMatch(source);
    if (logical != null) {
      final name = logical.group(1)!;
      if (!_scope.containsKey(name)) {
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_unknown_variable',
          'expression': name,
        });
      }
      final current = _scope[name];
      final operator = logical.group(2)!;
      final shouldWrite = switch (operator) {
        '||' => !_isTruthy(current),
        '&&' => _isTruthy(current),
        '??' => current == null,
        _ => false,
      };
      if (shouldWrite) {
        _scope[name] = _evaluate(logical.group(3)!);
      }
      return true;
    }
    final compound = RegExp(
      r'^([A-Za-z_][A-Za-z0-9_]*)\s*([+-])=\s*([\s\S]+)$',
    ).firstMatch(source);
    if (compound != null) {
      final delta = _toNum(_evaluate(compound.group(3)!));
      _updateNumericVariable(
        compound.group(1)!,
        compound.group(2)! == '+' ? delta : -delta,
      );
      return true;
    }
    return false;
  }

  bool _runMemberAssignment(String statement) {
    final source = _trimTrailingSemicolon(statement.trim());
    final equals = _findTopLevelDefaultEquals(source);
    if (equals < 0) return false;
    final left = source.substring(0, equals).trim();
    final right = source.substring(equals + 1).trim();
    if (left.isEmpty || right.isEmpty) return false;
    final identifier = _readIdentifier(left, 0);
    if (identifier != null && identifier.end == left.length) return false;
    final target = _readAssignmentTarget(left);
    if (target == null) return false;
    _writeAssignmentTarget(target, _evaluate(right));
    return true;
  }

  bool _runMemberUpdate(String statement) {
    final source = _trimTrailingSemicolon(statement.trim());
    if (source.endsWith('++') || source.endsWith('--')) {
      final delta = source.endsWith('++') ? 1 : -1;
      final left = source.substring(0, source.length - 2).trim();
      final target = _readAssignmentTarget(left);
      if (target == null) return false;
      _updateNumericMember(target, delta);
      return true;
    }
    if (source.startsWith('++') || source.startsWith('--')) {
      final delta = source.startsWith('++') ? 1 : -1;
      final left = source.substring(2).trim();
      final target = _readAssignmentTarget(left);
      if (target == null) return false;
      _updateNumericMember(target, delta);
      return true;
    }
    final equals = _findTopLevelDefaultEquals(source);
    if (equals <= 0) return false;
    final operator = source[equals - 1];
    if (operator != '+' && operator != '-') return false;
    final left = source.substring(0, equals - 1).trim();
    final right = source.substring(equals + 1).trim();
    if (left.isEmpty || right.isEmpty) return false;
    final target = _readAssignmentTarget(left);
    if (target == null) return false;
    final delta = _toNum(_evaluate(right));
    _updateNumericMember(target, operator == '+' ? delta : -delta);
    return true;
  }

  bool _runMemberLogicalAssignment(String statement) {
    final source = _trimTrailingSemicolon(statement.trim());
    final equals = _findTopLevelDefaultEquals(source);
    if (equals < 2) return false;
    final operator = source.substring(equals - 2, equals);
    if (operator != '||' && operator != '&&' && operator != '??') {
      return false;
    }
    final left = source.substring(0, equals - 2).trim();
    final right = source.substring(equals + 1).trim();
    if (left.isEmpty || right.isEmpty) return false;
    final target = _readAssignmentTarget(left);
    if (target == null) return false;
    final current = _readAssignmentTargetValue(target);
    final shouldWrite = switch (operator) {
      '||' => !_isTruthy(current),
      '&&' => _isTruthy(current),
      '??' => current == null,
      _ => false,
    };
    if (shouldWrite) {
      _writeAssignmentTarget(target, _evaluate(right));
    }
    return true;
  }

  _CustomJsAssignmentTarget? _readAssignmentTarget(String expression) {
    final source = expression.trim();
    final first = _readIdentifier(source, 0);
    if (first == null) return null;
    if (!_scope.containsKey(first.text)) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_unknown_variable',
        'expression': first.text,
      });
    }
    var value = _scope[first.text];
    var index = first.end;
    while (true) {
      index = _skipWhitespace(source, index);
      if (index >= source.length) break;
      if (source.startsWith('?.', index)) {
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_assignment_target',
          'expression': expression,
        });
      }
      Object? key;
      if (source[index] == '.') {
        final prop = _readIdentifier(source, index + 1);
        if (prop == null) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_property',
            'expression': expression,
          });
        }
        key = prop.text;
        index = prop.end;
      } else if (source[index] == '[') {
        final item = _readBalanced(source, index, '[', ']');
        key = _evaluate(item.text);
        index = item.end;
      } else {
        return null;
      }
      final next = _skipWhitespace(source, index);
      if (next >= source.length) {
        return _CustomJsAssignmentTarget(container: value, key: key);
      }
      value = _readIndexOrProperty(value, key);
      index = next;
    }
    return null;
  }

  Object? _readIndexOrProperty(Object? value, Object? key) {
    if (value is List && (key is num || int.tryParse('$key') != null)) {
      return _readIndex(value, key is num ? key : int.parse('$key'));
    }
    if (key is String) return _readProperty(value, key);
    return _readIndex(value, key);
  }

  Object? _readAssignmentTargetValue(_CustomJsAssignmentTarget target) {
    final container = target.container;
    final key = target.key;
    if (container is Map) return container['$key'];
    if (container is List) {
      final index = _assignmentListIndex(key);
      if (index >= 0 && index < container.length) return container[index];
      return null;
    }
    throw EngineException(errLlmFormat, {
      'reason': 'custom_skill_assignment_target',
      'key': '$key',
    });
  }

  void _writeAssignmentTarget(
    _CustomJsAssignmentTarget target,
    Object? value,
  ) {
    final container = target.container;
    final key = target.key;
    if (container is Map) {
      container['$key'] = value;
      return;
    }
    if (container is List) {
      final index = _assignmentListIndex(key);
      while (container.length <= index) {
        container.add(null);
      }
      container[index] = value;
      return;
    }
    throw EngineException(errLlmFormat, {
      'reason': 'custom_skill_assignment_target',
      'key': '$key',
    });
  }

  bool _deleteAssignmentTarget(_CustomJsAssignmentTarget target) {
    final container = target.container;
    final key = target.key;
    if (container is Map) {
      container.remove(key);
      container.remove('$key');
      return true;
    }
    if (container is List) {
      final index = _assignmentListIndex(key);
      if (index >= 0 && index < container.length) {
        container[index] = null;
      }
      return true;
    }
    throw EngineException(errLlmFormat, {
      'reason': 'custom_skill_delete',
      'key': '$key',
    });
  }

  int _assignmentListIndex(Object? key) {
    final index = key is num ? key.toInt() : int.tryParse('${key ?? ''}');
    if (index == null || index < 0) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_assignment_index',
        'key': '$key',
      });
    }
    return index;
  }

  void _updateNumericMember(_CustomJsAssignmentTarget target, num delta) {
    final current = _toNum(_readAssignmentTargetValue(target));
    final next = current + delta;
    _writeAssignmentTarget(
      target,
      next == next.truncateToDouble() ? next.toInt() : next,
    );
  }

  void _updateNumericVariable(String name, num delta) {
    if (!_scope.containsKey(name)) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_unknown_variable',
        'expression': name,
      });
    }
    final current = _scope[name];
    if (current is! num) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_number',
        'value': current,
      });
    }
    final next = current + delta;
    _scope[name] = next == next.truncateToDouble() ? next.toInt() : next;
  }

  Object? _evaluate(String expression) {
    final expr = _trimTrailingSemicolon(expression.trim());
    if (expr.isEmpty) return '';
    final grouped = _unwrapOuterParens(expr);
    if (grouped != null) return _evaluate(grouped);
    final groupedChain = _readGroupedValueChain(expr);
    if (groupedChain != null) {
      return _evaluateValueChain(
        _evaluate(groupedChain.text),
        expr,
        groupedChain.end,
      );
    }
    final newExpression = _evaluateNewExpression(expr);
    if (newExpression != null) return newExpression;
    final deleteExpression = _evaluateDeleteExpression(expr);
    if (deleteExpression != null) return deleteExpression;
    final functionExpression = _readFunctionExpression(expr, 'anonymous');
    if (functionExpression != null) return functionExpression;
    final inOperator = _readTopLevelInOperator(expr);
    if (inOperator != null) {
      return _hasProperty(
        _evaluate(inOperator.right),
        _evaluate(inOperator.left),
      );
    }
    if (expr.startsWith('`') && expr.endsWith('`') && expr.length >= 2) {
      return _evaluateTemplate(expr.substring(1, expr.length - 1));
    }
    final quotedLiteral = _readQuotedLiteral(expr, 0);
    if (quotedLiteral != null && quotedLiteral.end < expr.length) {
      return _evaluateValueChain(
        _unquote(quotedLiteral.text),
        expr,
        quotedLiteral.end,
      );
    }
    if (_isQuoted(expr)) return _unquote(expr);
    final regexLiteral = _readRegexLiteral(expr, 0);
    if (regexLiteral != null) {
      final value = _customJsRegExp(regexLiteral.pattern, regexLiteral.flags);
      if (regexLiteral.end == expr.length) return value;
      return _evaluateValueChain(value, expr, regexLiteral.end);
    }
    final arrayLiteral = _literalInner(expr, '[', ']');
    if (arrayLiteral != null) return _evaluateArrayLiteral(arrayLiteral);
    if (expr.startsWith('[')) {
      final array = _readBalanced(expr, 0, '[', ']');
      if (array.end < expr.length) {
        return _evaluateValueChain(
          _evaluateArrayLiteral(array.text),
          expr,
          array.end,
        );
      }
    }
    final objectLiteral = _literalInner(expr, '{', '}');
    if (objectLiteral != null) return _evaluateObjectLiteral(objectLiteral);
    if (expr == 'true') return true;
    if (expr == 'false') return false;
    if (expr == 'null' || expr == 'undefined') return null;
    final intValue = int.tryParse(expr);
    if (intValue != null) return intValue;
    final doubleValue = double.tryParse(expr);
    if (doubleValue != null) return doubleValue;

    final ternary = _readTopLevelTernary(expr);
    if (ternary != null) {
      return _evaluate(_isTruthy(_evaluate(ternary.condition))
          ? ternary.whenTrue
          : ternary.whenFalse);
    }

    final nullishParts = _splitTopLevelOperator(expr, '??');
    if (nullishParts.length > 1) {
      Object? last;
      for (final part in nullishParts) {
        last = _evaluate(part);
        if (last != null) return last;
      }
      return last;
    }

    final orParts = _splitTopLevelOperator(expr, '||');
    if (orParts.length > 1) {
      Object? last;
      for (final part in orParts) {
        last = _evaluate(part);
        if (_isTruthy(last)) return last;
      }
      return last;
    }

    final andParts = _splitTopLevelOperator(expr, '&&');
    if (andParts.length > 1) {
      Object? last;
      for (final part in andParts) {
        last = _evaluate(part);
        if (!_isTruthy(last)) return last;
      }
      return last;
    }

    final comparison = _readTopLevelComparison(expr);
    if (comparison != null) {
      return _compareValues(
        _evaluate(comparison.left),
        _evaluate(comparison.right),
        comparison.operator,
      );
    }

    if (expr.startsWith('!')) {
      var count = 0;
      while (count < expr.length && expr[count] == '!') {
        count++;
      }
      final value = _evaluate(expr.substring(count));
      final truthy = _isTruthy(value);
      return count.isOdd ? !truthy : truthy;
    }

    final additive = _readTopLevelAdditive(expr);
    if (additive != null) {
      final values = [for (final part in additive.parts) _evaluate(part)];
      if (additive.operators.every((operator) => operator == '+')) {
        if (values.every((value) => value is num)) {
          return values.cast<num>().fold<num>(0, (sum, value) => sum + value);
        }
        return values.map(_stringifyInterpolation).join();
      }
      if (values.any((value) => value is! num)) {
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_arithmetic',
          'expression': expr,
        });
      }
      var result = values.first as num;
      for (var i = 0; i < additive.operators.length; i++) {
        final value = values[i + 1] as num;
        result = additive.operators[i] == '+' ? result + value : result - value;
      }
      return result;
    }

    final multiplicative = _readTopLevelMultiplicative(expr);
    if (multiplicative != null) {
      final values = [
        for (final part in multiplicative.parts) _evaluate(part),
      ];
      if (values.any((value) => value is! num)) {
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_arithmetic',
          'expression': expr,
        });
      }
      var result = values.first as num;
      for (var i = 0; i < multiplicative.operators.length; i++) {
        final value = values[i + 1] as num;
        result = switch (multiplicative.operators[i]) {
          '*' => result * value,
          '/' => result / value,
          '%' => result % value,
          _ => result,
        };
      }
      return result;
    }

    return _evaluateChain(expr);
  }

  Object? _evaluateChain(String expression) {
    var index = 0;
    final first = _readIdentifier(expression, index);
    if (first == null) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_expression',
        'expression': expression,
      });
    }
    index = first.end;
    if (!_scope.containsKey(first.text)) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_unknown_variable',
        'expression': first.text,
      });
    }
    final value = _scope[first.text];

    return _evaluateValueChain(value, expression, index);
  }

  Object? _evaluateValueChain(
    Object? initialValue,
    String expression,
    int index,
  ) {
    var value = initialValue;
    while (index < expression.length) {
      final char = expression[index];
      if (char == '(') {
        final call = _readBalanced(expression, index, '(', ')');
        final args = _splitTopLevel(call.text, ',')
            .where((part) => part.trim().isNotEmpty)
            .map((part) => part.trim())
            .toList();
        value = _callFunction(value, 'anonymous', args);
        index = call.end;
        continue;
      }
      if (expression.startsWith('?.[', index)) {
        if (value == null) return null;
        final item = _readBalanced(expression, index + 2, '[', ']');
        final key = _evaluate(item.text);
        value = _readIndex(value, key);
        index = item.end;
        continue;
      }
      if (expression.startsWith('?.', index)) {
        if (value == null) return null;
        final prop = _readIdentifier(expression, index + 2);
        if (prop == null) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_property',
            'expression': expression,
          });
        }
        index = prop.end;
        if (index < expression.length && expression[index] == '(') {
          final call = _readBalanced(expression, index, '(', ')');
          final args = _splitTopLevel(call.text, ',')
              .where((part) => part.trim().isNotEmpty)
              .map((part) => part.trim())
              .toList();
          value = _callMethod(value, prop.text, args);
          index = call.end;
        } else {
          value = _readProperty(value, prop.text);
        }
        continue;
      }
      if (char == '.') {
        final prop = _readIdentifier(expression, index + 1);
        if (prop == null) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_property',
            'expression': expression,
          });
        }
        index = prop.end;
        if (index < expression.length && expression[index] == '(') {
          final call = _readBalanced(expression, index, '(', ')');
          final args = _splitTopLevel(call.text, ',')
              .where((part) => part.trim().isNotEmpty)
              .map((part) => part.trim())
              .toList();
          value = _callMethod(value, prop.text, args);
          index = call.end;
        } else {
          value = _readProperty(value, prop.text);
        }
        continue;
      }
      if (char == '[') {
        final item = _readBalanced(expression, index, '[', ']');
        final key = _evaluate(item.text);
        value = _readIndex(value, key);
        index = item.end;
        continue;
      }
      if (char.trim().isEmpty) {
        index++;
        continue;
      }
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_expression',
        'expression': expression,
      });
    }
    return value;
  }

  Object? _evaluateNewExpression(String expression) {
    if (!_startsWithWord(expression, 0, 'new')) return null;
    var index = _skipWhitespace(expression, 'new'.length);
    final name = _readIdentifier(expression, index);
    if (name == null) return null;
    index = _skipWhitespace(expression, name.end);
    if (index >= expression.length || expression[index] != '(') return null;
    final call = _readBalanced(expression, index, '(', ')');
    index = _skipWhitespace(expression, call.end);
    final args = _splitTopLevel(call.text, ',')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.trim())
        .toList();
    final value = switch (name.text) {
      'Set' => _newSet(args),
      'Date' => _newDate(args),
      'Map' => _newMap(args),
      'Array' => _newArray(args),
      'RegExp' => _newRegExp(args),
      'Error' => _newError(args),
      _ => throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_constructor',
          'constructor': name.text,
        }),
    };
    if (index == expression.length) return value;
    return _evaluateValueChain(value, expression, index);
  }

  Object? _evaluateDeleteExpression(String expression) {
    if (!_startsWithWord(expression, 0, 'delete')) return null;
    final targetExpression = expression.substring('delete'.length).trim();
    if (targetExpression.isEmpty) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_delete',
      });
    }
    final target = _readAssignmentTarget(targetExpression);
    if (target == null) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_delete',
        'expression': expression,
      });
    }
    return _deleteAssignmentTarget(target);
  }

  List<Object?> _evaluateArrayLiteral(String source) {
    final result = <Object?>[];
    for (final item in _splitTopLevel(source, ',')) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('...')) {
        final spread = _evaluate(trimmed.substring(3).trim());
        if (spread is _CustomJsMap) {
          result.addAll(_customJsMapEntries(spread));
          continue;
        }
        if (spread is! Iterable) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_array_spread',
            'expression': trimmed,
          });
        }
        result.addAll(spread);
        continue;
      }
      result.add(_evaluate(trimmed));
    }
    return result;
  }

  Map<String, Object?> _evaluateObjectLiteral(String source) {
    final result = <String, Object?>{};
    for (final item in _splitTopLevel(source, ',')) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('...')) {
        final spread = _evaluate(trimmed.substring(3).trim());
        if (spread is! Map) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_object_spread',
            'expression': trimmed,
          });
        }
        for (final entry in spread.entries) {
          result['${entry.key}'] = entry.value;
        }
        continue;
      }
      final colon = _findTopLevelColon(trimmed);
      if (colon < 0) {
        final shorthand = _readIdentifier(trimmed, 0);
        if (shorthand == null || shorthand.end != trimmed.length) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_object_literal',
            'expression': trimmed,
          });
        }
        result[shorthand.text] = _evaluate(shorthand.text);
        continue;
      }
      final rawKey = trimmed.substring(0, colon).trim();
      final valueExpr = trimmed.substring(colon + 1).trim();
      if (rawKey.isEmpty || valueExpr.isEmpty) {
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_object_literal',
          'expression': trimmed,
        });
      }
      result[_evaluateObjectLiteralKey(rawKey)] = _evaluate(valueExpr);
    }
    return result;
  }

  String _evaluateObjectLiteralKey(String rawKey) {
    final computed = _literalInner(rawKey.trim(), '[', ']');
    if (computed != null) {
      return _stringifyPropertyKey(_evaluate(computed));
    }
    return _objectLiteralKey(rawKey);
  }

  Object? _callMethod(Object? value, String method, List<String> args) {
    if (value is _CustomJsBuiltin) {
      return _callBuiltinMethod(value.name, method, args);
    }
    if (value is _CustomJsDate) {
      return _callDateInstanceMethod(value, method, args);
    }
    if (value is _CustomJsMap) {
      return _callMapInstanceMethod(value, method, args);
    }
    if (value is _CustomJsRegExp) {
      return _callRegExpInstanceMethod(value, method, args);
    }
    if (value is Set && _customJsSetMethods.contains(method)) {
      return _callSetInstanceMethod(value, method, args);
    }
    switch (method) {
      case 'trim':
        _expectNoArgs(method, args);
        return '${value ?? ''}'.trim();
      case 'trimStart':
      case 'trimLeft':
        _expectNoArgs(method, args);
        return '${value ?? ''}'.trimLeft();
      case 'trimEnd':
      case 'trimRight':
        _expectNoArgs(method, args);
        return '${value ?? ''}'.trimRight();
      case 'toUpperCase':
        _expectNoArgs(method, args);
        return '${value ?? ''}'.toUpperCase();
      case 'toLowerCase':
        _expectNoArgs(method, args);
        return '${value ?? ''}'.toLowerCase();
      case 'toString':
        if (args.length > 1) _badMethodArgs(method);
        if (args.length == 1) {
          if (value is! num) _badMethodArgs(method);
          return _numberToRadixString(value, _toInt(_evaluate(args.single)));
        }
        return '${value ?? ''}';
      case 'toFixed':
        return _numberToFixed(value, args);
      case 'localeCompare':
        if (args.isEmpty || args.length > 3) _badMethodArgs(method);
        return '${value ?? ''}'.compareTo(
          _stringifyInterpolation(_evaluate(args.first)),
        );
      case 'split':
        if (args.length > 1) _badMethodArgs(method);
        final text = '${value ?? ''}';
        if (args.isEmpty) return [text];
        final separator = _stringifyInterpolation(_evaluate(args.single));
        return separator.isEmpty ? text.split('') : text.split(separator);
      case 'replace':
        if (args.length != 2) _badMethodArgs(method);
        final text = '${value ?? ''}';
        final matcher = _evaluate(args.first);
        return _replaceString(text, matcher, args[1]);
      case 'replaceAll':
        if (args.length != 2) _badMethodArgs(method);
        final text = '${value ?? ''}';
        final matcher = _evaluate(args.first);
        return _replaceAllString(text, matcher, args[1]);
      case 'indexOf':
        if (args.isEmpty || args.length > 2) _badMethodArgs(method);
        if (value is Iterable && value is! String) {
          return _arrayIndexOf(
            value.toList(),
            _evaluate(args.first),
            args.length == 2 ? _toInt(_evaluate(args[1])) : 0,
          );
        }
        final text = '${value ?? ''}';
        final needle = _stringifyInterpolation(_evaluate(args.first));
        final start = args.length == 2
            ? _normalizeSearchStart(_toInt(_evaluate(args[1])), text.length)
            : 0;
        return text.indexOf(needle, start);
      case 'lastIndexOf':
        if (args.isEmpty || args.length > 2) _badMethodArgs(method);
        if (value is Iterable && value is! String) {
          final items = value.toList();
          return _arrayLastIndexOf(
            items,
            _evaluate(args.first),
            args.length == 2 ? _toInt(_evaluate(args[1])) : items.length - 1,
          );
        }
        final text = '${value ?? ''}';
        final needle = _stringifyInterpolation(_evaluate(args.first));
        final start = args.length == 2
            ? _normalizeLastSearchStart(_toInt(_evaluate(args[1])), text.length)
            : text.length;
        if (start < 0) return needle.isEmpty ? 0 : -1;
        return text.lastIndexOf(needle, start);
      case 'substring':
        if (args.isEmpty || args.length > 2) _badMethodArgs(method);
        final text = '${value ?? ''}';
        var start = _normalizeSubstringIndex(
          _toInt(_evaluate(args.first)),
          text.length,
        );
        var end = args.length == 2
            ? _normalizeSubstringIndex(_toInt(_evaluate(args[1])), text.length)
            : text.length;
        if (start > end) {
          final swapped = start;
          start = end;
          end = swapped;
        }
        return text.substring(start, end);
      case 'charAt':
        if (args.length > 1) _badMethodArgs(method);
        final text = '${value ?? ''}';
        final index = args.isEmpty ? 0 : _toInt(_evaluate(args.single));
        if (index < 0 || index >= text.length) return '';
        return text[index];
      case 'startsWith':
        if (args.isEmpty || args.length > 2) _badMethodArgs(method);
        final text = '${value ?? ''}';
        final start = args.length == 2
            ? _normalizeSearchStart(_toInt(_evaluate(args[1])), text.length)
            : 0;
        return text.startsWith(
          _stringifyInterpolation(_evaluate(args.first)),
          start,
        );
      case 'endsWith':
        if (args.isEmpty || args.length > 2) _badMethodArgs(method);
        final text = '${value ?? ''}';
        final end = args.length == 2
            ? _normalizeSearchStart(_toInt(_evaluate(args[1])), text.length)
            : text.length;
        return text.substring(0, end).endsWith(
              _stringifyInterpolation(_evaluate(args.first)),
            );
      case 'padStart':
      case 'padEnd':
        return _padString(
          '${value ?? ''}',
          method: method,
          args: args,
        );
      case 'repeat':
        return _repeatString(
          '${value ?? ''}',
          method: method,
          args: args,
        );
      case 'includes':
        if (args.isEmpty || args.length > 2) _badMethodArgs(method);
        final needle = _evaluate(args.first);
        if (value is Iterable && value is! String) {
          final items = value is List ? value : value.toList();
          final start = args.length == 2
              ? _normalizeSliceIndex(_toInt(_evaluate(args[1])), items.length)
              : 0;
          return items
              .skip(start)
              .any((item) => _compareValues(item, needle, '==='));
        }
        final text = '${value ?? ''}';
        final start = args.length == 2
            ? _normalizeSearchStart(_toInt(_evaluate(args[1])), text.length)
            : 0;
        return text.indexOf('${needle ?? ''}', start) >= 0;
      case 'hasOwnProperty':
        if (args.length != 1) _badMethodArgs(method);
        return _hasOwnProperty(value, _evaluate(args.single));
      case 'match':
        if (args.length != 1) _badMethodArgs(method);
        return _matchString('${value ?? ''}', _evaluate(args.single));
      case 'matchAll':
        if (args.length != 1) _badMethodArgs(method);
        return _matchAllString('${value ?? ''}', _evaluate(args.single));
      case 'has':
        if (args.length != 1 || value is! Set) _badMethodArgs(method);
        final needle = _evaluate(args.single);
        return value.any((item) => _compareValues(item, needle, '==='));
      case 'add':
        if (args.length != 1 || value is! Set) _badMethodArgs(method);
        value.add(_evaluate(args.single));
        return value;
      case 'delete':
        if (args.length != 1 || value is! Set) _badMethodArgs(method);
        final needle = _evaluate(args.single);
        final currentLength = value.length;
        value.removeWhere((item) => _compareValues(item, needle, '==='));
        return value.length != currentLength;
      case 'clear':
        if (args.isNotEmpty || value is! Set) _badMethodArgs(method);
        value.clear();
        return null;
      case 'push':
        if (value is! List) _badMethodArgs(method);
        value.addAll(_evaluateCallArguments(args));
        return value.length;
      case 'pop':
        if (args.isNotEmpty || value is! List) _badMethodArgs(method);
        return value.isEmpty ? null : value.removeLast();
      case 'shift':
        if (args.isNotEmpty || value is! List) _badMethodArgs(method);
        return value.isEmpty ? null : value.removeAt(0);
      case 'unshift':
        if (value is! List) _badMethodArgs(method);
        value.insertAll(0, _evaluateCallArguments(args));
        return value.length;
      case 'splice':
        if (args.isEmpty || value is! List) _badMethodArgs(method);
        return _spliceList(value, args);
      case 'fill':
        if (args.isEmpty || args.length > 3 || value is! List) {
          _badMethodArgs(method);
        }
        return _fillList(value, args);
      case 'concat':
        if (value is! Iterable || value is String) _badMethodArgs(method);
        final combined = <Object?>[...value];
        for (final item in _evaluateCallArguments(args)) {
          if (item is Iterable && item is! String) {
            combined.addAll(item);
          } else {
            combined.add(item);
          }
        }
        return combined;
      case 'at':
        if (args.length != 1) _badMethodArgs(method);
        final rawIndex = _toInt(_evaluate(args.single));
        if (value is String) {
          final index = _normalizeAtIndex(rawIndex, value.length);
          return index == null ? null : value[index];
        }
        if (value is! Iterable) _badMethodArgs(method);
        final items = value.toList();
        final index = _normalizeAtIndex(rawIndex, items.length);
        return index == null ? null : items[index];
      case 'map':
        if (args.length != 1 || value is! Iterable) _badMethodArgs(method);
        final items = value is List ? value : value.toList();
        final mapped = <Object?>[];
        var index = 0;
        for (final item in items) {
          mapped.add(_evaluateCallback(
            method,
            args.single,
            item,
            index,
            source: items,
          ));
          index++;
        }
        return mapped;
      case 'flatMap':
        if (args.length != 1 || value is! Iterable) _badMethodArgs(method);
        final items = value is List ? value : value.toList();
        final mapped = <Object?>[];
        var index = 0;
        for (final item in items) {
          final result = _evaluateCallback(
            method,
            args.single,
            item,
            index,
            source: items,
          );
          if (result is Iterable && result is! String) {
            mapped.addAll(result);
          } else {
            mapped.add(result);
          }
          index++;
        }
        return mapped;
      case 'flat':
        if (args.length > 1 || value is! Iterable || value is String) {
          _badMethodArgs(method);
        }
        final depth = args.isEmpty ? 1 : _toInt(_evaluate(args.single));
        final flattened = <Object?>[];
        _flattenInto(flattened, value, depth < 0 ? 0 : depth);
        return flattened;
      case 'filter':
        if (args.length != 1 || value is! Iterable) _badMethodArgs(method);
        final items = value is List ? value : value.toList();
        final filtered = <Object?>[];
        var index = 0;
        for (final item in items) {
          final keep = _evaluateCallback(
            method,
            args.single,
            item,
            index,
            source: items,
          );
          if (_isTruthy(keep)) filtered.add(item);
          index++;
        }
        return filtered;
      case 'forEach':
        if (args.length != 1 || value is! Iterable) _badMethodArgs(method);
        final items = value is List ? value : value.toList();
        var index = 0;
        for (final item in items) {
          _evaluateCallback(
            method,
            args.single,
            item,
            index,
            source: items,
          );
          index++;
        }
        return null;
      case 'find':
        if (args.length != 1 || value is! Iterable) _badMethodArgs(method);
        final items = value is List ? value : value.toList();
        var index = 0;
        for (final item in items) {
          final matched = _evaluateCallback(
            method,
            args.single,
            item,
            index,
            source: items,
          );
          if (_isTruthy(matched)) return item;
          index++;
        }
        return null;
      case 'findIndex':
        if (args.length != 1 || value is! Iterable) _badMethodArgs(method);
        final items = value is List ? value : value.toList();
        var index = 0;
        for (final item in items) {
          final matched = _evaluateCallback(
            method,
            args.single,
            item,
            index,
            source: items,
          );
          if (_isTruthy(matched)) return index;
          index++;
        }
        return -1;
      case 'some':
        if (args.length != 1 || value is! Iterable) _badMethodArgs(method);
        final items = value is List ? value : value.toList();
        var index = 0;
        for (final item in items) {
          final matched = _evaluateCallback(
            method,
            args.single,
            item,
            index,
            source: items,
          );
          if (_isTruthy(matched)) return true;
          index++;
        }
        return false;
      case 'every':
        if (args.length != 1 || value is! Iterable) _badMethodArgs(method);
        final items = value is List ? value : value.toList();
        var index = 0;
        for (final item in items) {
          final matched = _evaluateCallback(
            method,
            args.single,
            item,
            index,
            source: items,
          );
          if (!_isTruthy(matched)) return false;
          index++;
        }
        return true;
      case 'reduce':
        if (args.isEmpty || args.length > 2 || value is! Iterable) {
          _badMethodArgs(method);
        }
        final items = value.toList();
        if (args.length == 1 && items.isEmpty) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_reduce_empty',
          });
        }
        Object? accumulator = args.length == 2 ? _evaluate(args[1]) : items[0];
        var index = args.length == 2 ? 0 : 1;
        for (final item in items.skip(index)) {
          accumulator = _evaluateReduceCallback(
            method,
            args.first,
            accumulator,
            item,
            index,
            items,
          );
          index++;
        }
        return accumulator;
      case 'sort':
        if (args.length > 1 || value is! Iterable) _badMethodArgs(method);
        final sorted = value is List ? value : value.toList();
        sorted.sort(
          (a, b) => args.isEmpty
              ? _stringifyInterpolation(a).compareTo(_stringifyInterpolation(b))
              : _evaluateSortComparator(method, args.single, a, b),
        );
        return sorted;
      case 'reverse':
        if (args.isNotEmpty || value is! Iterable || value is String) {
          _badMethodArgs(method);
        }
        if (value is List) {
          final reversed = value.reversed.toList();
          value.setAll(0, reversed);
          return value;
        }
        return value.toList().reversed.toList();
      case 'slice':
        if (args.length > 2) _badMethodArgs(method);
        if (value is String) {
          final start = args.isEmpty ? 0 : _toInt(_evaluate(args.first));
          final rawEnd =
              args.length < 2 ? value.length : _toInt(_evaluate(args[1]));
          final normalizedStart = _normalizeSliceIndex(start, value.length);
          final normalizedEnd = _normalizeSliceIndex(rawEnd, value.length);
          final end =
              normalizedEnd < normalizedStart ? normalizedStart : normalizedEnd;
          return value.substring(normalizedStart, end);
        }
        if (value is! Iterable) _badMethodArgs(method);
        final items = value.toList();
        final start = args.isEmpty ? 0 : _toInt(_evaluate(args.first));
        final rawEnd =
            args.length < 2 ? items.length : _toInt(_evaluate(args[1]));
        final normalizedStart = _normalizeSliceIndex(start, items.length);
        final normalizedEnd = _normalizeSliceIndex(rawEnd, items.length);
        final end =
            normalizedEnd < normalizedStart ? normalizedStart : normalizedEnd;
        return items.sublist(normalizedStart, end);
      case 'join':
        if (args.length > 1 || value is! Iterable) _badMethodArgs(method);
        final separator = args.isEmpty
            ? ','
            : _stringifyInterpolation(_evaluate(args.single));
        return value.map(_stringifyInterpolation).join(separator);
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_method',
          'method': method,
        });
    }
  }

  List<Object?> _spliceList(List value, List<String> args) {
    final values = _evaluateCallArguments(args);
    final start = _normalizeSpliceStart(_toInt(values.first), value.length);
    final deleteCount = values.length < 2
        ? value.length - start
        : _toInt(values[1]).clamp(0, value.length - start).toInt();
    final removed = value.sublist(start, start + deleteCount);
    value
      ..removeRange(start, start + deleteCount)
      ..insertAll(start, values.skip(2));
    return removed;
  }

  List _fillList(List value, List<String> args) {
    final fillValue = _evaluate(args.first);
    final start = args.length >= 2
        ? _normalizeSliceIndex(_toInt(_evaluate(args[1])), value.length)
        : 0;
    final end = args.length >= 3
        ? _normalizeSliceIndex(_toInt(_evaluate(args[2])), value.length)
        : value.length;
    for (var index = start; index < end; index++) {
      value[index] = fillValue;
    }
    return value;
  }

  String _padString(
    String value, {
    required String method,
    required List<String> args,
  }) {
    if (args.isEmpty || args.length > 2) _badMethodArgs(method);
    final targetLength = _toInt(_evaluate(args.first));
    if (targetLength <= value.length) return value;
    final padSource =
        args.length == 2 ? _stringifyInterpolation(_evaluate(args[1])) : ' ';
    if (padSource.isEmpty) return value;
    final needed = targetLength - value.length;
    final buffer = StringBuffer();
    while (buffer.length < needed) {
      buffer.write(padSource);
    }
    final padding = buffer.toString().substring(0, needed);
    return method == 'padEnd' ? '$value$padding' : '$padding$value';
  }

  String _repeatString(
    String value, {
    required String method,
    required List<String> args,
  }) {
    if (args.length != 1) _badMethodArgs(method);
    final count = _toInt(_evaluate(args.single));
    if (count < 0 || count > 10000) _badMethodArgs(method);
    if (count == 0 || value.isEmpty) return '';
    final buffer = StringBuffer();
    for (var index = 0; index < count; index++) {
      buffer.write(value);
    }
    return buffer.toString();
  }

  String _numberToFixed(Object? value, List<String> args) {
    if (args.length > 1 || value is! num) _badMethodArgs('toFixed');
    final fractionDigits = args.isEmpty ? 0 : _toInt(_evaluate(args.single));
    if (fractionDigits < 0 || fractionDigits > 100) _badMethodArgs('toFixed');
    if (value.isNaN) return 'NaN';
    if (value.isInfinite) return value.isNegative ? '-Infinity' : 'Infinity';
    return value.toStringAsFixed(fractionDigits);
  }

  String _numberToRadixString(num value, int radix) {
    if (radix < 2 || radix > 36) _badMethodArgs('toString');
    if (value.isNaN) return 'NaN';
    if (value.isInfinite) return value.isNegative ? '-Infinity' : 'Infinity';
    const digits = '0123456789abcdefghijklmnopqrstuvwxyz';
    final negative = value < 0;
    var absolute = value.abs();
    final integerPart = absolute.floor();
    var text = integerPart.toRadixString(radix);
    var fraction = absolute - integerPart;
    if (fraction > 0) {
      final buffer = StringBuffer('$text.');
      var guard = 0;
      while (fraction > 0 && guard < 16) {
        fraction *= radix;
        final digit = fraction.floor();
        buffer.write(digits[digit]);
        fraction -= digit;
        guard++;
      }
      text = buffer.toString();
    }
    return negative ? '-$text' : text;
  }

  int _arrayIndexOf(List<Object?> items, Object? needle, int fromIndex) {
    final start = _normalizeSliceIndex(fromIndex, items.length);
    for (var index = start; index < items.length; index++) {
      if (_compareValues(items[index], needle, '===')) return index;
    }
    return -1;
  }

  int _arrayLastIndexOf(List<Object?> items, Object? needle, int fromIndex) {
    final start = _normalizeArrayLastSearchStart(fromIndex, items.length);
    if (start < 0) return -1;
    for (var index = start; index >= 0; index--) {
      if (_compareValues(items[index], needle, '===')) return index;
    }
    return -1;
  }

  List<String> _forInKeys(Object? value, String expression) {
    if (value is Map) {
      return [for (final key in value.keys) '$key'];
    }
    if (value is Iterable && value is! String) {
      return [
        for (var index = 0; index < value.length; index++) '$index',
      ];
    }
    throw EngineException(errLlmFormat, {
      'reason': 'custom_skill_for_in',
      'expression': expression,
    });
  }

  void _flattenInto(List<Object?> target, Iterable source, int depth) {
    for (final item in source) {
      if (depth > 0 && item is Iterable && item is! String) {
        _flattenInto(target, item, depth - 1);
      } else {
        target.add(item);
      }
    }
  }

  Object? _matchString(String text, Object? matcher) {
    if (matcher is _CustomJsRegExp) {
      final matches = matcher.regExp.allMatches(text).toList();
      if (matches.isEmpty) return null;
      if (matcher.global) {
        return [for (final match in matches) match.group(0) ?? ''];
      }
      final match = matches.first;
      return [
        for (var i = 0; i <= match.groupCount; i++) match.group(i),
      ];
    }
    final needle = _stringifyInterpolation(matcher);
    if (needle.isEmpty) return [''];
    return text.contains(needle) ? [needle] : null;
  }

  List<List<Object?>> _matchAllString(String text, Object? matcher) {
    if (matcher is _CustomJsRegExp) {
      return [
        for (final match in matcher.regExp.allMatches(text))
          [
            for (var index = 0; index <= match.groupCount; index++)
              match.group(index),
          ],
      ];
    }
    final needle = _stringifyInterpolation(matcher);
    if (needle.isEmpty) return const [];
    final matches = <List<Object?>>[];
    var start = 0;
    while (start <= text.length) {
      final index = text.indexOf(needle, start);
      if (index < 0) break;
      matches.add([needle]);
      start = index + needle.length;
    }
    return matches;
  }

  String _replaceString(
    String text,
    Object? matcher,
    String replacementExpression,
  ) {
    if (matcher is _CustomJsRegExp) {
      return matcher.global
          ? text.replaceAllMapped(
              matcher.regExp,
              (match) => _regexReplacementValue(
                text,
                match,
                replacementExpression,
              ),
            )
          : text.replaceFirstMapped(
              matcher.regExp,
              (match) => _regexReplacementValue(
                text,
                match,
                replacementExpression,
              ),
            );
    }
    final replacement = _stringifyInterpolation(
      _evaluate(replacementExpression),
    );
    final from = _stringifyInterpolation(matcher);
    return from.isEmpty
        ? '$replacement$text'
        : text.replaceFirst(from, replacement);
  }

  String _replaceAllString(
    String text,
    Object? matcher,
    String replacementExpression,
  ) {
    if (matcher is _CustomJsRegExp) {
      return text.replaceAllMapped(
        matcher.regExp,
        (match) => _regexReplacementValue(
          text,
          match,
          replacementExpression,
        ),
      );
    }
    final replacement = _stringifyInterpolation(
      _evaluate(replacementExpression),
    );
    final from = _stringifyInterpolation(matcher);
    if (from.isEmpty) {
      return '$replacement${text.split('').join(replacement)}$replacement';
    }
    return text.replaceAll(from, replacement);
  }

  String _regexReplacementValue(
    String source,
    Match match,
    String replacementExpression,
  ) {
    final values = <Object?>[
      match.group(0),
      for (var index = 1; index <= match.groupCount; index++)
        match.group(index),
      match.start,
      source,
    ];
    final arrow = _findTopLevelArrow(replacementExpression);
    if (arrow >= 0) {
      final params = _parseCallbackParams(
        replacementExpression.substring(0, arrow),
        'replace',
      );
      final body = replacementExpression.substring(arrow + 2).trim();
      return _stringifyInterpolation(
        _withScopeBindings(
          _bindCallbackParams(params, values, 'replace'),
          () => _evaluateCallbackBody('replace', body),
        ),
      );
    }
    final replacement = _evaluate(replacementExpression);
    if (replacement is _CustomJsFunction) {
      return _stringifyInterpolation(
        _callCustomFunctionWithValues(replacement, values),
      );
    }
    return _jsRegexReplacement(
      match,
      _stringifyInterpolation(replacement),
    );
  }

  String _jsRegexReplacement(Match match, String replacement) {
    final buffer = StringBuffer();
    for (var index = 0; index < replacement.length; index++) {
      final char = replacement[index];
      if (char != r'$' || index + 1 >= replacement.length) {
        buffer.write(char);
        continue;
      }
      final next = replacement[index + 1];
      final firstDigit = int.tryParse(next);
      if (firstDigit != null && firstDigit > 0) {
        final secondIndex = index + 2;
        final secondDigit = secondIndex < replacement.length
            ? int.tryParse(replacement[secondIndex])
            : null;
        if (secondDigit != null) {
          final twoDigit = firstDigit * 10 + secondDigit;
          if (twoDigit <= match.groupCount) {
            buffer.write(match.group(twoDigit) ?? '');
            index += 2;
            continue;
          }
        }
        if (firstDigit <= match.groupCount) {
          buffer.write(match.group(firstDigit) ?? '');
          index++;
          continue;
        }
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  Object? _callFunction(Object? value, String name, List<String> args) {
    if (value is _CustomJsBuiltin) {
      return _callBuiltinFunction(value.name, args);
    }
    if (value is _CustomJsFunction) {
      return _callCustomFunction(value, args);
    }
    throw EngineException(errLlmFormat, {
      'reason': 'custom_skill_function',
      'function': name,
    });
  }

  Object? _callCustomFunction(_CustomJsFunction function, List<String> args) {
    return _callCustomFunctionWithValues(
        function, _evaluateCallArguments(args));
  }

  List<Object?> _evaluateCallArguments(List<String> args) {
    final values = <Object?>[];
    for (final arg in args) {
      final trimmed = arg.trim();
      if (trimmed.startsWith('...')) {
        final spreadValue = _evaluate(trimmed.substring(3).trim());
        if (spreadValue is String) {
          values.addAll(spreadValue.split(''));
        } else if (spreadValue is Iterable) {
          values.addAll(spreadValue);
        } else {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_spread_argument',
          });
        }
      } else {
        values.add(_evaluate(arg));
      }
    }
    return values;
  }

  Object? _callCustomFunctionWithValues(
    _CustomJsFunction function,
    List<Object?> values,
  ) {
    final bindings = <String, Object?>{};
    for (var i = 0; i < function.params.length; i++) {
      _bindCallbackParam(
        function.params[i],
        i < values.length ? values[i] : null,
        bindings,
        function.name,
      );
    }
    return _withScopeBindings(bindings, () {
      final result = _runStatements(function.body);
      if (result is _CustomJsReturnValue) return result.value;
      if (result == null) return null;
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_function_control_flow',
        'function': function.name,
      });
    });
  }

  Object? _callBuiltinFunction(String objectName, List<String> args) {
    final values = _evaluateCallArguments(args);
    switch (objectName) {
      case 'Boolean':
        if (values.length > 1) _badMethodArgs(objectName);
        if (values.isEmpty) return false;
        return _isTruthy(values.single);
      case 'Number':
        if (values.length > 1) _badMethodArgs(objectName);
        if (values.isEmpty) return 0;
        return _toNum(values.single);
      case 'String':
        if (values.length > 1) _badMethodArgs(objectName);
        if (values.isEmpty) return '';
        return _stringifyInterpolation(values.single);
      case 'Array':
        return _arrayConstructor(values);
      case 'RegExp':
        return _regExpFromValues(values);
      case 'Error':
        if (values.length > 1) _badMethodArgs(objectName);
        return _CustomJsError(
          values.isEmpty ? '' : _stringifyInterpolation(values.single),
        );
      case 'parseFloat':
        if (values.length != 1) _badMethodArgs(objectName);
        return _parseNumericPrefix(values.single, integer: false);
      case 'parseInt':
        if (values.isEmpty || values.length > 2) _badMethodArgs(objectName);
        final radix = values.length == 1 ? 10 : _toInt(values[1]);
        return _parseNumericPrefix(
          values.first,
          integer: true,
          radix: radix,
        );
      case 'isFinite':
        if (values.length != 1) _badMethodArgs(objectName);
        return _isFiniteNumber(values.single, coerce: true);
      case 'isNaN':
        if (values.length != 1) _badMethodArgs(objectName);
        return _isNaNNumber(values.single, coerce: true);
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_builtin_function',
          'object': objectName,
        });
    }
  }

  Object? _callBuiltinCallback(
    _CustomJsBuiltin function,
    List<Object?> values,
  ) {
    switch (function.name) {
      case 'Boolean':
        return _isTruthy(values.isEmpty ? null : values.first);
      default:
        _badMethodArgs(function.name);
    }
  }

  Object? _callBuiltinMethod(
    String objectName,
    String method,
    List<String> args,
  ) {
    switch (objectName) {
      case 'Array':
        if (method == 'isArray') {
          if (args.length != 1) _badMethodArgs(method);
          return _evaluate(args.single) is List;
        }
        if (method == 'from') return _arrayFrom(args);
        break;
      case 'console':
        if (_customJsConsoleMethods.contains(method)) {
          _evaluateCallArguments(args);
          return null;
        }
        break;
      case 'JSON':
        return _callJsonMethod(method, args);
      case 'Date':
        return _callDateStaticMethod(method, args);
      case 'Math':
        return _callMathMethod(method, args);
      case 'Number':
        return _callNumberMethod(method, args);
      case 'Object':
        return _callObjectMethod(method, args);
    }
    throw EngineException(errLlmFormat, {
      'reason': 'custom_skill_builtin_method',
      'object': objectName,
      'method': method,
    });
  }

  List<Object?> _arrayFrom(List<String> args) {
    if (args.isEmpty || args.length > 2) _badMethodArgs('from');
    final source = _evaluate(args.first);
    final values = <Object?>[];
    if (source is String) {
      values.addAll(source.split(''));
    } else if (source is _CustomJsMap) {
      values.addAll(_customJsMapEntries(source));
    } else if (source is Iterable) {
      values.addAll(source);
    } else if (source is Map) {
      final length = _arrayLikeLength(source);
      for (var index = 0; index < length; index++) {
        values
            .add(source.containsKey(index) ? source[index] : source['$index']);
      }
    } else {
      _badMethodArgs('from');
    }
    if (args.length == 1) return values;
    return [
      for (var index = 0; index < values.length; index++)
        _evaluateCallback(
          'from',
          args[1],
          values[index],
          index,
          source: values,
        ),
    ];
  }

  Set<Object?> _newSet(List<String> args) {
    if (args.length > 1) _badMethodArgs('Set');
    if (args.isEmpty) return <Object?>{};
    final source = _evaluate(args.single);
    if (source == null) return <Object?>{};
    if (source is String) return <Object?>{...source.split('')};
    if (source is Iterable) return <Object?>{...source};
    throw EngineException(errLlmFormat, {
      'reason': 'custom_skill_set_constructor',
    });
  }

  List<Object?> _newArray(List<String> args) =>
      _arrayConstructor(_evaluateCallArguments(args));

  List<Object?> _arrayConstructor(List<Object?> values) {
    if (values.length == 1 && values.single is num) {
      final length = (values.single as num).toInt();
      if (length < 0 || length > 10000) {
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_array_constructor',
        });
      }
      return List<Object?>.filled(length, null);
    }
    return List<Object?>.from(values);
  }

  _CustomJsDate _newDate(List<String> args) {
    if (args.length > 1) _badMethodArgs('Date');
    if (args.isEmpty) return _CustomJsDate(DateTime.now().toUtc());
    return _CustomJsDate(_toDateTime(_evaluate(args.single)));
  }

  _CustomJsMap _newMap(List<String> args) {
    if (args.length > 1) _badMethodArgs('Map');
    final result = _CustomJsMap(<Object?, Object?>{});
    if (args.isEmpty) return result;
    final source = _evaluate(args.single);
    if (source == null) return result;
    if (source is _CustomJsMap) {
      result.values.addAll(source.values);
      return result;
    }
    if (source is Map) {
      for (final entry in source.entries) {
        result.values[entry.key] = entry.value;
      }
      return result;
    }
    if (source is Iterable && source is! String) {
      for (final item in source) {
        final pair = item is Iterable ? item.toList() : null;
        if (pair == null || pair.length < 2) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_map_constructor',
          });
        }
        result.values[pair[0]] = pair[1];
      }
      return result;
    }
    throw EngineException(errLlmFormat, {
      'reason': 'custom_skill_map_constructor',
    });
  }

  _CustomJsError _newError(List<String> args) {
    if (args.length > 1) _badMethodArgs('Error');
    return _CustomJsError(
      args.isEmpty ? '' : _stringifyInterpolation(_evaluate(args.single)),
    );
  }

  _CustomJsRegExp _newRegExp(List<String> args) =>
      _regExpFromValues(_evaluateCallArguments(args));

  _CustomJsRegExp _regExpFromValues(List<Object?> values) {
    if (values.length > 2) _badMethodArgs('RegExp');
    if (values.length == 1 && values.single is _CustomJsRegExp) {
      return values.single as _CustomJsRegExp;
    }
    final pattern = values.isEmpty ? '' : _stringifyInterpolation(values.first);
    final flags = values.length == 2 ? _stringifyInterpolation(values[1]) : '';
    return _customJsRegExp(pattern, flags);
  }

  _CustomJsRegExp _customJsRegExp(String pattern, String flags) {
    final unsupported = flags
        .split('')
        .where((flag) => flag.isNotEmpty && !'gimsu'.contains(flag))
        .toList();
    if (unsupported.isNotEmpty) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_regexp_flags',
        'flags': flags,
      });
    }
    return _CustomJsRegExp(
      RegExp(
        pattern,
        caseSensitive: !flags.contains('i'),
        multiLine: flags.contains('m'),
        dotAll: flags.contains('s'),
      ),
      global: flags.contains('g'),
    );
  }

  int _arrayLikeLength(Map<Object?, Object?> source) {
    final raw = source['length'];
    if (raw == null) return 0;
    final length = _toInt(raw);
    if (length <= 0) return 0;
    if (length > 10000) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_array_from_guard',
      });
    }
    return length;
  }

  Object? _callJsonMethod(String method, List<String> args) {
    switch (method) {
      case 'parse':
        if (args.length != 1) _badMethodArgs(method);
        final source = _stringifyInterpolation(_evaluate(args.single));
        try {
          return jsonDecode(source);
        } catch (_) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_json_parse',
          });
        }
      case 'stringify':
        return _jsonStringify(args);
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_builtin_method',
          'object': 'JSON',
          'method': method,
        });
    }
  }

  String _jsonStringify(List<String> args) {
    if (args.isEmpty || args.length > 3) _badMethodArgs('stringify');
    final values = _evaluateCallArguments(args);
    if (values.length >= 2 && values[1] != null) {
      _badMethodArgs('stringify');
    }
    final indent = values.length >= 3 ? _jsonStringifyIndent(values[2]) : null;
    if (indent == null || indent.isEmpty) return jsonEncode(values.first);
    return JsonEncoder.withIndent(indent).convert(values.first);
  }

  String? _jsonStringifyIndent(Object? value) {
    if (value == null) return null;
    if (value is num) {
      final count = value.toInt().clamp(0, 10).toInt();
      return count <= 0 ? null : ' ' * count;
    }
    final text = _stringifyInterpolation(value);
    if (text.isEmpty) return null;
    return text.length > 10 ? text.substring(0, 10) : text;
  }

  Object? _callDateStaticMethod(String method, List<String> args) {
    switch (method) {
      case 'now':
        _expectNoArgs(method, args);
        return DateTime.now().millisecondsSinceEpoch;
      case 'parse':
        if (args.length != 1) _badMethodArgs(method);
        return _toDateTime(_evaluate(args.single)).millisecondsSinceEpoch;
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_builtin_method',
          'object': 'Date',
          'method': method,
        });
    }
  }

  Object? _callDateInstanceMethod(
    _CustomJsDate value,
    String method,
    List<String> args,
  ) {
    switch (method) {
      case 'getTime':
      case 'valueOf':
        _expectNoArgs(method, args);
        return value.value.millisecondsSinceEpoch;
      case 'toISOString':
      case 'toJSON':
      case 'toString':
        _expectNoArgs(method, args);
        return value.value.toUtc().toIso8601String();
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_method',
          'method': method,
        });
    }
  }

  Object? _callSetInstanceMethod(
    Set value,
    String method,
    List<String> args,
  ) {
    switch (method) {
      case 'has':
        if (args.length != 1) _badMethodArgs(method);
        final needle = _evaluate(args.single);
        return value.any((item) => _compareValues(item, needle, '==='));
      case 'add':
        if (args.length != 1) _badMethodArgs(method);
        value.add(_evaluate(args.single));
        return value;
      case 'delete':
        if (args.length != 1) _badMethodArgs(method);
        final needle = _evaluate(args.single);
        final currentLength = value.length;
        value.removeWhere((item) => _compareValues(item, needle, '==='));
        return value.length != currentLength;
      case 'clear':
        _expectNoArgs(method, args);
        value.clear();
        return null;
      case 'keys':
      case 'values':
        _expectNoArgs(method, args);
        return [for (final item in value) item];
      case 'entries':
        _expectNoArgs(method, args);
        return [
          for (final item in value) [item, item],
        ];
      case 'forEach':
        if (args.length != 1) _badMethodArgs(method);
        for (final item in value) {
          _evaluateCallback(method, args.single, item, item, source: value);
        }
        return null;
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_method',
          'method': method,
        });
    }
  }

  Object? _callMapInstanceMethod(
    _CustomJsMap value,
    String method,
    List<String> args,
  ) {
    switch (method) {
      case 'get':
        if (args.length != 1) _badMethodArgs(method);
        final key = _customJsMapKey(value, _evaluate(args.single));
        return key == null ? null : value.values[key];
      case 'set':
        if (args.length != 2) _badMethodArgs(method);
        value.values[_evaluate(args.first)] = _evaluate(args[1]);
        return value;
      case 'has':
        if (args.length != 1) _badMethodArgs(method);
        return _customJsMapKey(value, _evaluate(args.single)) != null;
      case 'delete':
        if (args.length != 1) _badMethodArgs(method);
        final key = _customJsMapKey(value, _evaluate(args.single));
        if (key == null) return false;
        value.values.remove(key);
        return true;
      case 'clear':
        _expectNoArgs(method, args);
        value.values.clear();
        return null;
      case 'keys':
        _expectNoArgs(method, args);
        return _customJsMapKeys(value);
      case 'values':
        _expectNoArgs(method, args);
        return _customJsMapValues(value);
      case 'entries':
        _expectNoArgs(method, args);
        return _customJsMapEntries(value);
      case 'forEach':
        if (args.length != 1) _badMethodArgs(method);
        for (final entry in value.values.entries) {
          _evaluateCallback(
            method,
            args.single,
            entry.value,
            entry.key,
            source: value,
          );
        }
        return null;
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_method',
          'method': method,
        });
    }
  }

  Object? _customJsMapKey(_CustomJsMap value, Object? key) {
    for (final existing in value.values.keys) {
      if (_compareValues(existing, key, '===')) return existing;
    }
    return null;
  }

  List<Object?> _customJsMapKeys(_CustomJsMap value) =>
      [for (final entry in value.values.entries) entry.key];

  List<Object?> _customJsMapValues(_CustomJsMap value) =>
      [for (final entry in value.values.entries) entry.value];

  List<List<Object?>> _customJsMapEntries(_CustomJsMap value) => [
        for (final entry in value.values.entries) [entry.key, entry.value],
      ];

  Object? _callRegExpInstanceMethod(
    _CustomJsRegExp value,
    String method,
    List<String> args,
  ) {
    switch (method) {
      case 'test':
        if (args.length != 1) _badMethodArgs(method);
        return value.regExp.hasMatch(_stringifyInterpolation(
          _evaluate(args.single),
        ));
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_method',
          'method': method,
        });
    }
  }

  Object? _callMathMethod(String method, List<String> args) {
    final numbers = _forEachArg<num>(args, _toNum);
    switch (method) {
      case 'round':
        if (numbers.length != 1) _badMethodArgs(method);
        return numbers.single.round();
      case 'floor':
        if (numbers.length != 1) _badMethodArgs(method);
        return numbers.single.floor();
      case 'ceil':
        if (numbers.length != 1) _badMethodArgs(method);
        return numbers.single.ceil();
      case 'abs':
        if (numbers.length != 1) _badMethodArgs(method);
        return numbers.single.abs();
      case 'sqrt':
        if (numbers.length != 1) _badMethodArgs(method);
        return math.sqrt(numbers.single);
      case 'random':
        if (numbers.isNotEmpty) _badMethodArgs(method);
        return _random.nextDouble();
      case 'max':
        if (numbers.isEmpty) _badMethodArgs(method);
        return numbers.reduce((a, b) => a > b ? a : b);
      case 'min':
        if (numbers.isEmpty) _badMethodArgs(method);
        return numbers.reduce((a, b) => a < b ? a : b);
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_builtin_method',
          'object': 'Math',
          'method': method,
        });
    }
  }

  Object? _callNumberMethod(String method, List<String> args) {
    final values = _evaluateCallArguments(args);
    switch (method) {
      case 'isFinite':
        if (values.length != 1) _badMethodArgs(method);
        return _isFiniteNumber(values.single, coerce: false);
      case 'isNaN':
        if (values.length != 1) _badMethodArgs(method);
        return _isNaNNumber(values.single, coerce: false);
      case 'parseFloat':
        if (values.length != 1) _badMethodArgs(method);
        return _parseNumericPrefix(values.single, integer: false);
      case 'parseInt':
        if (values.isEmpty || values.length > 2) _badMethodArgs(method);
        final radix = values.length == 1 ? 10 : _toInt(values[1]);
        return _parseNumericPrefix(
          values.first,
          integer: true,
          radix: radix,
        );
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_builtin_method',
          'object': 'Number',
          'method': method,
        });
    }
  }

  Object? _callObjectMethod(String method, List<String> args) {
    switch (method) {
      case 'assign':
        return _objectAssign(args);
      case 'fromEntries':
        return _objectFromEntries(args);
      case 'hasOwn':
        final values = _evaluateCallArguments(args);
        if (values.length != 2) _badMethodArgs(method);
        return _hasOwnProperty(values.first, values[1]);
      case 'keys':
      case 'values':
      case 'entries':
        final values = _evaluateCallArguments(args);
        if (values.length != 1) _badMethodArgs(method);
        final value = values.single;
        if (value is! Map) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_object_builtin',
            'method': method,
          });
        }
        if (method == 'values') {
          return [for (final entry in value.entries) entry.value];
        }
        if (method == 'entries') {
          return [
            for (final entry in value.entries) ['${entry.key}', entry.value],
          ];
        }
        return [for (final key in value.keys) '$key'];
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_builtin_method',
          'object': 'Object',
          'method': method,
        });
    }
  }

  Map _objectAssign(List<String> args) {
    final values = _evaluateCallArguments(args);
    if (values.isEmpty) _badMethodArgs('assign');
    final target = values.first;
    if (target is! Map) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_object_builtin',
        'method': 'assign',
      });
    }
    for (final source in values.skip(1)) {
      if (source == null) continue;
      if (source is! Map) {
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_object_builtin',
          'method': 'assign',
        });
      }
      for (final entry in source.entries) {
        target['${entry.key}'] = entry.value;
      }
    }
    return target;
  }

  Map<String, Object?> _objectFromEntries(List<String> args) {
    final values = _evaluateCallArguments(args);
    if (values.length != 1) _badMethodArgs('fromEntries');
    final source = values.single;
    final entries = source is _CustomJsMap
        ? _customJsMapEntries(source)
        : source is Iterable
            ? source
            : null;
    if (entries == null) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_object_builtin',
        'method': 'fromEntries',
      });
    }
    final result = <String, Object?>{};
    for (final item in entries) {
      final pair = item is Iterable ? item.toList() : null;
      if (pair == null || pair.length < 2) {
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_object_builtin',
          'method': 'fromEntries',
        });
      }
      result['${pair[0]}'] = pair[1];
    }
    return result;
  }

  Object? _evaluateCallback(
    String method,
    String callback,
    Object? item,
    Object? index, {
    Object? source,
  }) {
    final values = source == null ? [item, index] : [item, index, source];
    final arrow = _findTopLevelArrow(callback);
    if (arrow < 0) {
      final function = _evaluate(callback);
      if (function is _CustomJsBuiltin) {
        return _callBuiltinCallback(function, values);
      }
      if (function is _CustomJsFunction) {
        return _callCustomFunctionWithValues(function, values);
      }
      _badMethodArgs(method);
    }
    final params = _parseCallbackParams(callback.substring(0, arrow), method);
    final body = callback.substring(arrow + 2).trim();
    return _withScopeBindings(
      _bindCallbackParams(params, values, method),
      () => _evaluateCallbackBody(method, body),
    );
  }

  Object? _evaluateReduceCallback(
    String method,
    String callback,
    Object? accumulator,
    Object? item,
    int index,
    List<Object?> source,
  ) {
    final values = [accumulator, item, index, source];
    final arrow = _findTopLevelArrow(callback);
    if (arrow < 0) {
      final function = _evaluate(callback);
      if (function is _CustomJsFunction) {
        return _callCustomFunctionWithValues(function, values);
      }
      _badMethodArgs(method);
    }
    final params = _parseCallbackParams(callback.substring(0, arrow), method);
    if (params.length > values.length) _badMethodArgs(method);
    final body = callback.substring(arrow + 2).trim();
    final bindings = _bindCallbackParams(params, values, method);
    return _withScopeBindings(
      bindings,
      () => _evaluateCallbackBody(method, body),
    );
  }

  int _evaluateSortComparator(
    String method,
    String callback,
    Object? left,
    Object? right,
  ) {
    final arrow = _findTopLevelArrow(callback);
    if (arrow < 0) {
      final function = _evaluate(callback);
      if (function is _CustomJsFunction) {
        final result = _callCustomFunctionWithValues(function, [left, right]);
        if (result is num) return result.sign.toInt();
        if (result is bool) return result ? 1 : 0;
        return 0;
      }
      _badMethodArgs(method);
    }
    final params = _parseCallbackParams(callback.substring(0, arrow), method);
    if (params.length != 2) _badMethodArgs(method);
    final body = callback.substring(arrow + 2).trim();
    final result = _withScopeBindings(
      _bindCallbackParams(params, [left, right], method),
      () => _evaluateCallbackBody(method, body),
    );
    if (result is num) return result.sign.toInt();
    if (result is bool) return result ? 1 : 0;
    return 0;
  }

  int _normalizeSliceIndex(int value, int length) {
    final index = value < 0 ? length + value : value;
    return index.clamp(0, length).toInt();
  }

  int? _normalizeAtIndex(int value, int length) {
    final index = value < 0 ? length + value : value;
    if (index < 0 || index >= length) return null;
    return index;
  }

  int _normalizeSpliceStart(int value, int length) {
    if (value < 0) return (length + value).clamp(0, length).toInt();
    return value.clamp(0, length).toInt();
  }

  int _normalizeSearchStart(int value, int length) {
    return value.clamp(0, length).toInt();
  }

  int _normalizeLastSearchStart(int value, int length) {
    if (value < 0) return -1;
    return value.clamp(0, length).toInt();
  }

  int _normalizeArrayLastSearchStart(int value, int length) {
    if (length == 0) return -1;
    if (value < 0) return length + value;
    return value.clamp(0, length - 1).toInt();
  }

  int _normalizeSubstringIndex(int value, int length) {
    if (value < 0) return 0;
    return value.clamp(0, length).toInt();
  }

  int _toInt(Object? value) {
    if (value is num) return value.toInt();
    final parsed = int.tryParse('${value ?? ''}');
    if (parsed != null) return parsed;
    throw EngineException(errLlmFormat, {
      'reason': 'custom_skill_number',
      'value': value,
    });
  }

  num _toNum(Object? value) {
    if (value is num) return value;
    final parsed = num.tryParse('${value ?? ''}');
    if (parsed != null) return parsed;
    throw EngineException(errLlmFormat, {
      'reason': 'custom_skill_number',
      'value': value,
    });
  }

  num _parseNumericPrefix(
    Object? value, {
    required bool integer,
    int radix = 10,
  }) {
    if (value is num) return integer ? value.toInt() : value;
    if (integer && radix != 10) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_number_radix',
        'value': radix,
      });
    }
    final text = '${value ?? ''}'.trimLeft();
    final pattern = integer
        ? RegExp(r'^[+-]?\d+')
        : RegExp(r'^[+-]?(?:(?:\d+\.?\d*)|(?:\.\d+))(?:[eE][+-]?\d+)?');
    final match = pattern.firstMatch(text);
    if (match == null) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_number',
        'value': value,
      });
    }
    final parsed =
        integer ? int.parse(match.group(0)!) : num.parse(match.group(0)!);
    return parsed;
  }

  DateTime _toDateTime(Object? value) {
    if (value is _CustomJsDate) return value.value;
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    final source = '${value ?? ''}'.trim();
    try {
      return DateTime.parse(source).toUtc();
    } catch (_) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_date',
        'value': value,
      });
    }
  }

  List<T> _forEachArg<T>(
    List<String> args,
    T Function(Object? value) convert,
  ) =>
      [for (final arg in _evaluateCallArguments(args)) convert(arg)];

  bool _isTruthy(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    return true;
  }

  bool _hasProperty(Object? value, Object? key) {
    if (value is Map) {
      return value.containsKey(key) || value.containsKey('$key');
    }
    if (value is List) {
      final index = key is num ? key.toInt() : int.tryParse('${key ?? ''}');
      return index != null && index >= 0 && index < value.length;
    }
    if (value is String) {
      final index = key is num ? key.toInt() : int.tryParse('${key ?? ''}');
      return index != null && index >= 0 && index < value.length;
    }
    return false;
  }

  bool _hasOwnProperty(Object? value, Object? key) => _hasProperty(value, key);

  bool _isFiniteNumber(Object? value, {required bool coerce}) {
    final number = coerce ? _coerceNumberPredicateNum(value) : value;
    return number is num && number.isFinite;
  }

  bool _isNaNNumber(Object? value, {required bool coerce}) {
    final number = coerce ? _coerceNumberPredicateNum(value) : value;
    if (coerce && number == null) return true;
    return number is num && number.isNaN;
  }

  num? _coerceNumberPredicateNum(Object? value) {
    if (value == null) return 0;
    if (value is bool) return value ? 1 : 0;
    if (value is num) return value;
    final text = '$value'.trim();
    if (text.isEmpty) return 0;
    return num.tryParse(text);
  }

  Map<String, Object?> _customJsErrorObject(Object error) {
    if (error is _CustomJsError) {
      return {
        'name': error.name,
        'message': error.message,
      };
    }
    if (error is EngineException) {
      return {
        'name': 'EngineException',
        'key': error.errKey,
        'reason': error.errParams['reason'],
        'message': error.message,
      };
    }
    return {
      'name': error.runtimeType.toString(),
      'message': '$error',
    };
  }

  bool _compareValues(Object? left, Object? right, String operator) {
    switch (operator) {
      case '===':
      case '==':
        if (left is num && right is num) return left == right;
        return left == right;
      case '!==':
      case '!=':
        if (left is num && right is num) return left != right;
        return left != right;
      case '>':
      case '>=':
      case '<':
      case '<=':
        final comparison = _compareOrder(left, right);
        if (comparison == null) return false;
        return switch (operator) {
          '>' => comparison > 0,
          '>=' => comparison >= 0,
          '<' => comparison < 0,
          '<=' => comparison <= 0,
          _ => false,
        };
      default:
        return false;
    }
  }

  int? _compareOrder(Object? left, Object? right) {
    if (left is num && right is num) return left.compareTo(right);
    if (left is String && right is String) return left.compareTo(right);
    return null;
  }

  List<String> _parseCallbackParams(String source, String method) {
    var params = source.trim();
    if (params.startsWith('(') && params.endsWith(')')) {
      params = params.substring(1, params.length - 1);
    }
    final names = _splitTopLevel(params, ',')
        .map((param) => param.trim())
        .where((param) => param.isNotEmpty)
        .toList();
    if (names.isEmpty || names.any((name) => !_isValidCallbackParam(name))) {
      _badMethodArgs(method);
    }
    return names;
  }

  List<String> _readFunctionParams(String source, String name) {
    final params = _splitTopLevel(source, ',')
        .map((param) => param.trim())
        .where((param) => param.isNotEmpty)
        .toList();
    if (params.any((param) => !_isValidCallbackParam(param))) {
      _badMethodArgs(name);
    }
    return params;
  }

  Object? _evaluateCallbackBody(String method, String body) {
    final inner = _literalInner(body.trim(), '{', '}');
    if (inner == null) return _evaluate(body);
    final result = _runStatements(inner);
    if (result is _CustomJsReturnValue) return result.value;
    if (result == null) return null;
    throw EngineException(errLlmFormat, {
      'reason': 'custom_skill_callback_block',
      'method': method,
    });
  }

  bool _isValidCallbackParam(String param) {
    final defaultParam = _readParamDefault(param);
    if (defaultParam != null) {
      return _isValidCallbackParam(defaultParam.pattern);
    }
    final validName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    if (validName.hasMatch(param)) return true;
    final arrayDestructured = _arrayDestructureBindings(param);
    if (arrayDestructured != null && arrayDestructured.isNotEmpty) {
      return true;
    }
    final objectDestructured = _objectDestructureBindings(param);
    return objectDestructured != null && objectDestructured.isNotEmpty;
  }

  Map<String, Object?> _bindCallbackParams(
    List<String> params,
    List<Object?> values,
    String method,
  ) {
    if (params.length > values.length) _badMethodArgs(method);
    final bindings = <String, Object?>{};
    for (var i = 0; i < params.length; i++) {
      _bindCallbackParam(params[i], values[i], bindings, method);
    }
    return bindings;
  }

  void _bindCallbackParam(
    String param,
    Object? value,
    Map<String, Object?> bindings,
    String method,
  ) {
    final name = param.trim();
    final defaultParam = _readParamDefault(name);
    if (defaultParam != null) {
      _bindCallbackParam(
        defaultParam.pattern,
        value ?? _evaluate(defaultParam.defaultExpression),
        bindings,
        method,
      );
      return;
    }
    final validName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    if (validName.hasMatch(name)) {
      _bindUniqueCallbackName(bindings, name, value, method);
      return;
    }
    final objectBindings = _objectDestructureBindings(name);
    if (objectBindings != null && objectBindings.isNotEmpty) {
      if (value is! Map) {
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_destructure',
          'param': name,
        });
      }
      final explicitFields = {
        for (final binding in objectBindings)
          if (!binding.isRest) binding.fieldName,
      };
      for (final binding in objectBindings) {
        if (binding.isRest) {
          final rest = <String, Object?>{};
          for (final entry in value.entries) {
            final key = '${entry.key}';
            if (!explicitFields.contains(key)) {
              rest[key] = entry.value;
            }
          }
          _bindUniqueCallbackName(
            bindings,
            binding.bindingName,
            rest,
            method,
          );
          continue;
        }
        var boundValue = value[binding.fieldName];
        if (boundValue == null && binding.defaultExpression != null) {
          boundValue = _evaluate(binding.defaultExpression!);
        }
        _bindUniqueCallbackName(
          bindings,
          binding.bindingName,
          boundValue,
          method,
        );
      }
      return;
    }
    final arrayBindings = _arrayDestructureBindings(name);
    if (arrayBindings == null || arrayBindings.isEmpty) _badMethodArgs(method);
    if (value is! Iterable || value is String) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_destructure',
        'param': name,
      });
    }
    final items = value.toList();
    for (var i = 0; i < arrayBindings.length; i++) {
      final binding = arrayBindings[i];
      if (binding.isRest) {
        _bindUniqueCallbackName(
          bindings,
          binding.bindingName,
          items.sublist(i > items.length ? items.length : i),
          method,
        );
        continue;
      }
      var boundValue = i < items.length ? items[i] : null;
      if (boundValue == null && binding.defaultExpression != null) {
        boundValue = _evaluate(binding.defaultExpression!);
      }
      _bindUniqueCallbackName(
        bindings,
        binding.bindingName,
        boundValue,
        method,
      );
    }
  }

  _CustomJsParamDefault? _readParamDefault(String param) {
    final source = param.trim();
    final equals = _findTopLevelDefaultEquals(source);
    if (equals < 0) return null;
    final pattern = source.substring(0, equals).trim();
    final defaultExpression = source.substring(equals + 1).trim();
    if (pattern.isEmpty || defaultExpression.isEmpty) return null;
    return _CustomJsParamDefault(
      pattern: pattern,
      defaultExpression: defaultExpression,
    );
  }

  void _bindUniqueCallbackName(
    Map<String, Object?> bindings,
    String name,
    Object? value,
    String method,
  ) {
    if (bindings.containsKey(name)) _badMethodArgs(method);
    bindings[name] = value;
  }

  List<_CustomJsArrayDestructureBinding>? _arrayDestructureBindings(
    String param,
  ) {
    final source = param.trim();
    final inner = _literalInner(source, '[', ']');
    if (inner == null) return null;
    final validName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    final items = _splitTopLevel(inner, ',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (items.isEmpty) return null;
    final bindings = <_CustomJsArrayDestructureBinding>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final isRest = item.startsWith('...');
      var bindingName = isRest ? item.substring(3).trim() : item;
      String? defaultExpression;
      if (!isRest) {
        final equals = _findTopLevelDefaultEquals(bindingName);
        if (equals >= 0) {
          defaultExpression = bindingName.substring(equals + 1).trim();
          bindingName = bindingName.substring(0, equals).trim();
        }
      }
      if (!validName.hasMatch(bindingName)) return null;
      if (defaultExpression == '') return null;
      if (isRest &&
          (i != items.length - 1 || bindings.any((item) => item.isRest))) {
        return null;
      }
      bindings.add(_CustomJsArrayDestructureBinding(
        bindingName: bindingName,
        defaultExpression: defaultExpression,
        isRest: isRest,
      ));
    }
    if (bindings.isEmpty) {
      return null;
    }
    return bindings;
  }

  List<_CustomJsObjectDestructureBinding>? _objectDestructureBindings(
    String param,
  ) {
    final source = param.trim();
    final inner = _literalInner(source, '{', '}');
    if (inner == null) return null;
    final bindings = <_CustomJsObjectDestructureBinding>[];
    final items = _splitTopLevel(inner, ',');
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final trimmed = item.trim();
      if (trimmed.isEmpty) continue;
      final binding = _readObjectDestructureBinding(trimmed);
      if (binding == null) return null;
      if (binding.isRest &&
          (i != items.length - 1 || bindings.any((item) => item.isRest))) {
        return null;
      }
      bindings.add(binding);
    }
    return bindings.isEmpty ? null : bindings;
  }

  _CustomJsObjectDestructureBinding? _readObjectDestructureBinding(
    String source,
  ) {
    final validName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    if (source.startsWith('...')) {
      final bindingName = source.substring(3).trim();
      if (!validName.hasMatch(bindingName)) return null;
      return _CustomJsObjectDestructureBinding(
        fieldName: '',
        bindingName: bindingName,
        defaultExpression: null,
        isRest: true,
      );
    }
    final colon = _findTopLevelColon(source);
    final rawFieldName = colon < 0 ? null : source.substring(0, colon).trim();
    var bindingSource =
        (colon < 0 ? source : source.substring(colon + 1)).trim();
    String? defaultExpression;
    final equals = _findTopLevelDefaultEquals(bindingSource);
    if (equals >= 0) {
      defaultExpression = bindingSource.substring(equals + 1).trim();
      bindingSource = bindingSource.substring(0, equals).trim();
    }
    final fieldName = rawFieldName ?? bindingSource;
    final bindingName = colon < 0 ? fieldName : bindingSource;
    if (!validName.hasMatch(fieldName) ||
        !validName.hasMatch(bindingName) ||
        defaultExpression == '') {
      return null;
    }
    return _CustomJsObjectDestructureBinding(
      fieldName: fieldName,
      bindingName: bindingName,
      defaultExpression: defaultExpression,
      isRest: false,
    );
  }

  T _withScopeBindings<T>(
    Map<String, Object?> bindings,
    T Function() evaluate,
  ) {
    final previous = <String, Object?>{};
    final existed = <String, bool>{};
    for (final entry in bindings.entries) {
      existed[entry.key] = _scope.containsKey(entry.key);
      previous[entry.key] = _scope[entry.key];
      _scope[entry.key] = entry.value;
    }
    try {
      return evaluate();
    } finally {
      for (final name in bindings.keys) {
        if (existed[name] == true) {
          _scope[name] = previous[name];
        } else {
          _scope.remove(name);
        }
      }
    }
  }

  Object? _readProperty(Object? value, String property) {
    if (value is Map) return value[property];
    if (property == 'size' && value is Set) return value.length;
    if (property == 'size' && value is _CustomJsMap) return value.values.length;
    if (property == 'length') {
      if (value is String) return value.length;
      if (value is Iterable) return value.length;
      if (value is Map) return value.length;
    }
    throw EngineException(errLlmFormat, {
      'reason': 'custom_skill_property',
      'property': property,
    });
  }

  Object? _readIndex(Object? value, Object? key) {
    if (value is Map) return value['$key'];
    if (value is List && key is num) {
      final index = key.toInt();
      if (index >= 0 && index < value.length) return value[index];
      return null;
    }
    if (value is String && key is num) {
      final index = key.toInt();
      if (index >= 0 && index < value.length) return value[index];
      return null;
    }
    throw EngineException(errLlmFormat, {'reason': 'custom_skill_index'});
  }

  String _evaluateTemplate(String template) {
    final buffer = StringBuffer();
    var index = 0;
    while (index < template.length) {
      final start = template.indexOf(r'${', index);
      if (start < 0) {
        buffer.write(template.substring(index));
        break;
      }
      buffer.write(template.substring(index, start));
      final exprStart = start + 2;
      final end = _findTemplateExpressionEnd(template, exprStart);
      buffer.write(_stringifyInterpolation(
        _evaluate(template.substring(exprStart, end)),
      ));
      index = end + 1;
    }
    return buffer.toString();
  }

  String _stringifyReturn(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    return jsonEncode(value);
  }

  String _stringifyInterpolation(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    return jsonEncode(value);
  }

  String _stringifyPropertyKey(Object? value) {
    if (value == null) return 'null';
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    return jsonEncode(value);
  }
}

class _CustomJsBuiltin {
  final String name;
  const _CustomJsBuiltin(this.name);
}

class _CustomJsDate {
  final DateTime value;
  const _CustomJsDate(this.value);
}

class _CustomJsMap {
  final Map<Object?, Object?> values;
  const _CustomJsMap(this.values);
}

class _CustomJsError {
  final String message;

  const _CustomJsError(this.message);

  String get name => 'Error';
}

class _CustomJsFunction {
  final String name;
  final List<String> params;
  final String body;

  const _CustomJsFunction({
    required this.name,
    required this.params,
    required this.body,
  });
}

class _CustomJsRegExp {
  final RegExp regExp;
  final bool global;

  const _CustomJsRegExp(this.regExp, {required this.global});
}

class _CustomJsAssignmentTarget {
  final Object? container;
  final Object? key;

  const _CustomJsAssignmentTarget({
    required this.container,
    required this.key,
  });
}

abstract class _CustomJsStatementResult {
  const _CustomJsStatementResult();
}

class _CustomJsReturnValue extends _CustomJsStatementResult {
  final Object? value;
  const _CustomJsReturnValue(this.value) : super();
}

class _CustomJsBreakValue extends _CustomJsStatementResult {
  const _CustomJsBreakValue() : super();
}

class _CustomJsContinueValue extends _CustomJsStatementResult {
  const _CustomJsContinueValue() : super();
}

class _CustomJsTryStatement {
  final String body;
  final String? errorName;
  final String catchBody;

  const _CustomJsTryStatement({
    required this.body,
    required this.errorName,
    required this.catchBody,
  });
}

class _CustomJsIfStatement {
  final String condition;
  final String whenTrue;
  final String? whenFalse;

  const _CustomJsIfStatement({
    required this.condition,
    required this.whenTrue,
    required this.whenFalse,
  });
}

class _CustomJsSwitchStatement {
  final String expression;
  final List<_CustomJsSwitchClause> clauses;

  const _CustomJsSwitchStatement({
    required this.expression,
    required this.clauses,
  });
}

class _CustomJsSwitchClause {
  final String? matchExpression;
  final String body;

  const _CustomJsSwitchClause({
    required this.matchExpression,
    required this.body,
  });
}

class _CustomJsSwitchLabel {
  final String? matchExpression;
  final int start;
  final int bodyStart;

  const _CustomJsSwitchLabel({
    required this.matchExpression,
    required this.start,
    required this.bodyStart,
  });
}

class _CustomJsForStatement {
  final String initializer;
  final String condition;
  final String update;
  final String body;

  const _CustomJsForStatement({
    required this.initializer,
    required this.condition,
    required this.update,
    required this.body,
  });
}

class _CustomJsWhileStatement {
  final String condition;
  final String body;

  const _CustomJsWhileStatement({
    required this.condition,
    required this.body,
  });
}

class _CustomJsForOfStatement {
  final String itemPattern;
  final String iterable;
  final String body;

  const _CustomJsForOfStatement({
    required this.itemPattern,
    required this.iterable,
    required this.body,
  });
}

class _CustomJsForInStatement {
  final String keyPattern;
  final String objectExpression;
  final String body;

  const _CustomJsForInStatement({
    required this.keyPattern,
    required this.objectExpression,
    required this.body,
  });
}

class _CustomJsParamDefault {
  final String pattern;
  final String defaultExpression;

  const _CustomJsParamDefault({
    required this.pattern,
    required this.defaultExpression,
  });
}

class _CustomJsObjectDestructureBinding {
  final String fieldName;
  final String bindingName;
  final String? defaultExpression;
  final bool isRest;

  const _CustomJsObjectDestructureBinding({
    required this.fieldName,
    required this.bindingName,
    required this.defaultExpression,
    required this.isRest,
  });
}

class _CustomJsArrayDestructureBinding {
  final String bindingName;
  final String? defaultExpression;
  final bool isRest;

  const _CustomJsArrayDestructureBinding({
    required this.bindingName,
    required this.defaultExpression,
    required this.isRest,
  });
}

class _Token {
  final String text;
  final int end;
  const _Token(this.text, this.end);
}

class _ComparisonToken {
  final String left;
  final String right;
  final String operator;

  const _ComparisonToken({
    required this.left,
    required this.right,
    required this.operator,
  });
}

class _AdditiveToken {
  final List<String> parts;
  final List<String> operators;

  const _AdditiveToken({
    required this.parts,
    required this.operators,
  });
}

class _MultiplicativeToken {
  final List<String> parts;
  final List<String> operators;

  const _MultiplicativeToken({
    required this.parts,
    required this.operators,
  });
}

class _TernaryToken {
  final String condition;
  final String whenTrue;
  final String whenFalse;

  const _TernaryToken({
    required this.condition,
    required this.whenTrue,
    required this.whenFalse,
  });
}

class _RegexLiteralToken {
  final String pattern;
  final String flags;
  final int end;

  const _RegexLiteralToken({
    required this.pattern,
    required this.flags,
    required this.end,
  });
}

List<String> _splitStatements(String script) {
  final statements = <String>[];
  final buffer = StringBuffer();
  var quote = '';
  var escaped = false;
  var paren = 0;
  var bracket = 0;
  var brace = 0;

  for (var i = 0; i < script.length; i++) {
    final char = script[i];
    buffer.write(char);
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      if (char == quote) quote = '';
      continue;
    }
    final regexLiteral = _readRegexLiteral(
      script,
      i,
      requireStartContext: true,
    );
    if (regexLiteral != null) {
      buffer.write(script.substring(i + 1, regexLiteral.end));
      i = regexLiteral.end - 1;
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      quote = char;
      continue;
    }
    if (char == '(') paren++;
    if (char == ')') paren--;
    if (char == '[') bracket++;
    if (char == ']') bracket--;
    if (char == '{') brace++;
    if (char == '}') {
      brace--;
      if (paren == 0 &&
          bracket == 0 &&
          brace == 0 &&
          _isTopLevelBlockStatement(buffer.toString()) &&
          !_nextTopLevelWordIs(script, i + 1, 'else') &&
          !_nextTopLevelWordIs(script, i + 1, 'catch')) {
        statements.add(buffer.toString());
        buffer.clear();
      }
    }
    if (char == ';' && paren == 0 && bracket == 0 && brace == 0) {
      final value = buffer.toString();
      statements.add(value.substring(0, value.length - 1));
      buffer.clear();
    }
  }
  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) statements.add(tail);
  return statements;
}

bool _isTopLevelBlockStatement(String source) {
  final trimmed = source.trimLeft();
  return _startsWithWord(trimmed, 0, 'if') ||
      _startsWithWord(trimmed, 0, 'try') ||
      _startsWithWord(trimmed, 0, 'switch') ||
      _startsWithWord(trimmed, 0, 'function') ||
      _startsWithWord(trimmed, 0, 'while') ||
      _startsWithWord(trimmed, 0, 'for');
}

bool _nextTopLevelWordIs(String source, int index, String word) {
  final next = _skipWhitespace(source, index);
  return _startsWithWord(source, next, word);
}

List<String> _splitTopLevel(String source, String delimiter) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var quote = '';
  var escaped = false;
  var paren = 0;
  var bracket = 0;
  var brace = 0;

  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (escaped) {
      buffer.write(char);
      escaped = false;
      continue;
    }
    if (char == r'\') {
      buffer.write(char);
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      buffer.write(char);
      if (char == quote) quote = '';
      continue;
    }
    final regexLiteral = _readRegexLiteral(
      source,
      i,
      requireStartContext: true,
    );
    if (regexLiteral != null) {
      buffer.write(source.substring(i, regexLiteral.end));
      i = regexLiteral.end - 1;
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      buffer.write(char);
      quote = char;
      continue;
    }
    if (char == '(') paren++;
    if (char == ')') paren--;
    if (char == '[') bracket++;
    if (char == ']') bracket--;
    if (char == '{') brace++;
    if (char == '}') brace--;
    if (char == delimiter && paren == 0 && bracket == 0 && brace == 0) {
      parts.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  parts.add(buffer.toString());
  return parts;
}

_AdditiveToken? _readTopLevelAdditive(String source) {
  final parts = <String>[];
  final operators = <String>[];
  final buffer = StringBuffer();
  var quote = '';
  var escaped = false;
  var paren = 0;
  var bracket = 0;
  var brace = 0;

  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (escaped) {
      buffer.write(char);
      escaped = false;
      continue;
    }
    if (char == r'\') {
      buffer.write(char);
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      buffer.write(char);
      if (char == quote) quote = '';
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      buffer.write(char);
      quote = char;
      continue;
    }
    if (char == '(') paren++;
    if (char == ')') paren--;
    if (char == '[') bracket++;
    if (char == ']') bracket--;
    if (char == '{') brace++;
    if (char == '}') brace--;
    if ((char == '+' || char == '-') &&
        paren == 0 &&
        bracket == 0 &&
        brace == 0 &&
        !_isUnaryAdditive(source, i)) {
      parts.add(buffer.toString());
      operators.add(char);
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  if (operators.isEmpty) return null;
  parts.add(buffer.toString());
  return _AdditiveToken(parts: parts, operators: operators);
}

bool _isUnaryAdditive(String source, int index) {
  var previous = index - 1;
  while (previous >= 0 && source[previous].trim().isEmpty) {
    previous--;
  }
  if (previous < 0) return true;
  return '([{?:,+-*/!<>=&|'.contains(source[previous]);
}

_MultiplicativeToken? _readTopLevelMultiplicative(String source) {
  final parts = <String>[];
  final operators = <String>[];
  final buffer = StringBuffer();
  var quote = '';
  var escaped = false;
  var paren = 0;
  var bracket = 0;
  var brace = 0;

  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (escaped) {
      buffer.write(char);
      escaped = false;
      continue;
    }
    if (char == r'\') {
      buffer.write(char);
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      buffer.write(char);
      if (char == quote) quote = '';
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      buffer.write(char);
      quote = char;
      continue;
    }
    if (char == '(') paren++;
    if (char == ')') paren--;
    if (char == '[') bracket++;
    if (char == ']') bracket--;
    if (char == '{') brace++;
    if (char == '}') brace--;
    if ((char == '*' || char == '/' || char == '%') &&
        paren == 0 &&
        bracket == 0 &&
        brace == 0 &&
        !_isAdjacentSameOperator(source, i, char)) {
      parts.add(buffer.toString());
      operators.add(char);
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  if (operators.isEmpty) return null;
  parts.add(buffer.toString());
  return _MultiplicativeToken(parts: parts, operators: operators);
}

bool _isAdjacentSameOperator(String source, int index, String operator) {
  return (index > 0 && source[index - 1] == operator) ||
      (index + 1 < source.length && source[index + 1] == operator);
}

List<String> _splitTopLevelOperator(String source, String operator) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var quote = '';
  var escaped = false;
  var paren = 0;
  var bracket = 0;
  var brace = 0;

  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (escaped) {
      buffer.write(char);
      escaped = false;
      continue;
    }
    if (char == r'\') {
      buffer.write(char);
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      buffer.write(char);
      if (char == quote) quote = '';
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      buffer.write(char);
      quote = char;
      continue;
    }
    if (char == '(') paren++;
    if (char == ')') paren--;
    if (char == '[') bracket++;
    if (char == ']') bracket--;
    if (char == '{') brace++;
    if (char == '}') brace--;
    if (paren == 0 &&
        bracket == 0 &&
        brace == 0 &&
        source.startsWith(operator, i)) {
      parts.add(buffer.toString());
      buffer.clear();
      i += operator.length - 1;
      continue;
    }
    buffer.write(char);
  }
  parts.add(buffer.toString());
  return parts;
}

_ComparisonToken? _readTopLevelComparison(String source) {
  const operators = ['===', '!==', '>=', '<=', '==', '!=', '>', '<'];
  var quote = '';
  var escaped = false;
  var paren = 0;
  var bracket = 0;
  var brace = 0;

  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      if (char == quote) quote = '';
      continue;
    }
    final regexLiteral = _readRegexLiteral(
      source,
      i,
      requireStartContext: true,
    );
    if (regexLiteral != null) {
      i = regexLiteral.end - 1;
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      quote = char;
      continue;
    }
    if (char == '(') paren++;
    if (char == ')') paren--;
    if (char == '[') bracket++;
    if (char == ']') bracket--;
    if (char == '{') brace++;
    if (char == '}') brace--;
    if (paren != 0 || bracket != 0 || brace != 0) continue;
    for (final operator in operators) {
      if (!source.startsWith(operator, i)) continue;
      return _ComparisonToken(
        left: source.substring(0, i),
        right: source.substring(i + operator.length),
        operator: operator,
      );
    }
  }
  return null;
}

_ComparisonToken? _readTopLevelInOperator(String source) {
  var quote = '';
  var escaped = false;
  var paren = 0;
  var bracket = 0;
  var brace = 0;

  for (var i = 0; i < source.length - 1; i++) {
    final char = source[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      if (char == quote) quote = '';
      continue;
    }
    final regexLiteral = _readRegexLiteral(
      source,
      i,
      requireStartContext: true,
    );
    if (regexLiteral != null) {
      i = regexLiteral.end - 1;
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      quote = char;
      continue;
    }
    if (char == '(') paren++;
    if (char == ')') paren--;
    if (char == '[') bracket++;
    if (char == ']') bracket--;
    if (char == '{') brace++;
    if (char == '}') brace--;
    if (paren != 0 || bracket != 0 || brace != 0) continue;
    if (!_isTopLevelInAt(source, i)) continue;
    final left = source.substring(0, i).trim();
    final right = source.substring(i + 2).trim();
    if (left.isEmpty || right.isEmpty) return null;
    return _ComparisonToken(left: left, right: right, operator: 'in');
  }
  return null;
}

bool _isTopLevelInAt(String source, int index) {
  if (!source.startsWith('in', index)) return false;
  final before = index - 1;
  final after = index + 2;
  if (before >= 0 && _isIdentPart(source.codeUnitAt(before))) return false;
  if (after < source.length && _isIdentPart(source.codeUnitAt(after))) {
    return false;
  }
  return true;
}

_TernaryToken? _readTopLevelTernary(String source) {
  var quote = '';
  var escaped = false;
  var paren = 0;
  var bracket = 0;
  var brace = 0;
  var question = -1;
  var nested = 0;

  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      if (char == quote) quote = '';
      continue;
    }
    final regexLiteral = _readRegexLiteral(
      source,
      i,
      requireStartContext: true,
    );
    if (regexLiteral != null) {
      i = regexLiteral.end - 1;
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      quote = char;
      continue;
    }
    if (char == '(') paren++;
    if (char == ')') paren--;
    if (char == '[') bracket++;
    if (char == ']') bracket--;
    if (char == '{') brace++;
    if (char == '}') brace--;
    if (paren != 0 || bracket != 0 || brace != 0) continue;
    if (char == '?') {
      if (question < 0) {
        question = i;
      } else {
        nested++;
      }
      continue;
    }
    if (char == ':' && question >= 0) {
      if (nested > 0) {
        nested--;
        continue;
      }
      return _TernaryToken(
        condition: source.substring(0, question).trim(),
        whenTrue: source.substring(question + 1, i).trim(),
        whenFalse: source.substring(i + 1).trim(),
      );
    }
  }
  return null;
}

int _findTopLevelColon(String source) {
  var quote = '';
  var escaped = false;
  var paren = 0;
  var bracket = 0;
  var brace = 0;

  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      if (char == quote) quote = '';
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      quote = char;
      continue;
    }
    if (char == '(') paren++;
    if (char == ')') paren--;
    if (char == '[') bracket++;
    if (char == ']') bracket--;
    if (char == '{') brace++;
    if (char == '}') brace--;
    if (char == ':' && paren == 0 && bracket == 0 && brace == 0) return i;
  }
  return -1;
}

int _findTopLevelDefaultEquals(String source) {
  var quote = '';
  var escaped = false;
  var paren = 0;
  var bracket = 0;
  var brace = 0;

  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      if (char == quote) quote = '';
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      quote = char;
      continue;
    }
    if (char == '(') paren++;
    if (char == ')') paren--;
    if (char == '[') bracket++;
    if (char == ']') bracket--;
    if (char == '{') brace++;
    if (char == '}') brace--;
    if (char == '=' &&
        paren == 0 &&
        bracket == 0 &&
        brace == 0 &&
        !_isAdjacentComparisonEquals(source, i)) {
      return i;
    }
  }
  return -1;
}

bool _isAdjacentComparisonEquals(String source, int index) {
  return (index > 0 &&
          (source[index - 1] == '=' ||
              source[index - 1] == '!' ||
              source[index - 1] == '<' ||
              source[index - 1] == '>')) ||
      (index + 1 < source.length &&
          (source[index + 1] == '=' || source[index + 1] == '>'));
}

int _findTopLevelArrow(String source) {
  var quote = '';
  var escaped = false;
  var paren = 0;
  var bracket = 0;
  var brace = 0;

  for (var i = 0; i < source.length - 1; i++) {
    final char = source[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      if (char == quote) quote = '';
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      quote = char;
      continue;
    }
    if (char == '(') paren++;
    if (char == ')') paren--;
    if (char == '[') bracket++;
    if (char == ']') bracket--;
    if (char == '{') brace++;
    if (char == '}') brace--;
    if (char == '=' &&
        source[i + 1] == '>' &&
        paren == 0 &&
        bracket == 0 &&
        brace == 0) {
      return i;
    }
  }
  return -1;
}

_Token? _readIdentifier(String source, int start) {
  if (start >= source.length) return null;
  final first = source.codeUnitAt(start);
  if (!_isIdentStart(first)) return null;
  var end = start + 1;
  while (end < source.length && _isIdentPart(source.codeUnitAt(end))) {
    end++;
  }
  return _Token(source.substring(start, end), end);
}

bool _isIdentStart(int code) =>
    code == 95 || (code >= 65 && code <= 90) || (code >= 97 && code <= 122);

bool _isIdentPart(int code) =>
    _isIdentStart(code) || (code >= 48 && code <= 57);

int _skipWhitespace(String source, int index) {
  var i = index;
  while (i < source.length && source[i].trim().isEmpty) {
    i++;
  }
  return i;
}

bool _startsWithWord(String source, int index, String word) {
  if (!source.startsWith(word, index)) return false;
  final before = index - 1;
  final after = index + word.length;
  if (before >= 0 && _isIdentPart(source.codeUnitAt(before))) return false;
  if (after < source.length && _isIdentPart(source.codeUnitAt(after))) {
    return false;
  }
  return true;
}

_Token _readBalanced(String source, int start, String open, String close) {
  var depth = 0;
  var quote = '';
  var escaped = false;
  for (var i = start; i < source.length; i++) {
    final char = source[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      if (char == quote) quote = '';
      continue;
    }
    final regexLiteral = _readRegexLiteral(
      source,
      i,
      requireStartContext: true,
    );
    if (regexLiteral != null) {
      i = regexLiteral.end - 1;
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      quote = char;
      continue;
    }
    if (char == open) {
      depth++;
      continue;
    }
    if (char == close) {
      depth--;
      if (depth == 0) return _Token(source.substring(start + 1, i), i + 1);
    }
  }
  throw EngineException(errLlmFormat, {'reason': 'custom_skill_balanced'});
}

String _trimTrailingSemicolon(String source) {
  var text = source.trim();
  while (text.endsWith(';')) {
    text = text.substring(0, text.length - 1).trim();
  }
  return text;
}

String? _unwrapOuterParens(String expr) {
  if (!expr.startsWith('(')) return null;
  try {
    final balanced = _readBalanced(expr, 0, '(', ')');
    if (balanced.end != expr.length) return null;
    return balanced.text.trim();
  } catch (_) {
    return null;
  }
}

_Token? _readGroupedValueChain(String expr) {
  if (!expr.startsWith('(')) return null;
  try {
    final balanced = _readBalanced(expr, 0, '(', ')');
    final index = _skipWhitespace(expr, balanced.end);
    if (index >= expr.length) return null;
    if (expr.startsWith('?.', index) ||
        expr[index] == '.' ||
        expr[index] == '[' ||
        expr[index] == '(') {
      return balanced;
    }
  } catch (_) {
    return null;
  }
  return null;
}

bool _isQuoted(String expr) =>
    expr.length >= 2 &&
    ((expr.startsWith("'") && expr.endsWith("'")) ||
        (expr.startsWith('"') && expr.endsWith('"')));

_Token? _readQuotedLiteral(String source, int start) {
  if (start >= source.length) return null;
  final quote = source[start];
  if (quote != "'" && quote != '"') return null;
  var escaped = false;
  for (var i = start + 1; i < source.length; i++) {
    final char = source[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (char == quote) {
      return _Token(source.substring(start, i + 1), i + 1);
    }
  }
  return null;
}

_RegexLiteralToken? _readRegexLiteral(
  String source,
  int start, {
  bool requireStartContext = false,
}) {
  if (start >= source.length || source[start] != '/') return null;
  if (start + 1 >= source.length ||
      source[start + 1] == '/' ||
      source[start + 1] == '*') {
    return null;
  }
  if (requireStartContext && !_canStartRegexLiteral(source, start)) {
    return null;
  }

  var escaped = false;
  var inClass = false;
  for (var i = start + 1; i < source.length; i++) {
    final char = source[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (char == '[') {
      inClass = true;
      continue;
    }
    if (char == ']') {
      inClass = false;
      continue;
    }
    if (char != '/' || inClass) continue;
    var end = i + 1;
    while (end < source.length && _isIdentPart(source.codeUnitAt(end))) {
      end++;
    }
    final flags = source.substring(i + 1, end);
    if (flags.runes
        .any((code) => !'gimsuy'.contains(String.fromCharCode(code)))) {
      return null;
    }
    return _RegexLiteralToken(
      pattern: source.substring(start + 1, i),
      flags: flags,
      end: end,
    );
  }
  return null;
}

bool _canStartRegexLiteral(String source, int start) {
  for (var i = start - 1; i >= 0; i--) {
    final char = source[i];
    if (char.trim().isEmpty) continue;
    return '([{:;,=!?&|+-*'.contains(char);
  }
  return true;
}

String? _literalInner(String expr, String open, String close) {
  if (!expr.startsWith(open)) return null;
  try {
    final balanced = _readBalanced(expr, 0, open, close);
    if (balanced.end != expr.length) return null;
    return balanced.text;
  } catch (_) {
    return null;
  }
}

String _objectLiteralKey(String rawKey) {
  final key = rawKey.trim();
  if (_isQuoted(key)) return _unquote(key);
  final identifier = _readIdentifier(key, 0);
  if (identifier != null && identifier.end == key.length) return key;
  final intKey = int.tryParse(key);
  if (intKey != null) return '$intKey';
  throw EngineException(errLlmFormat, {
    'reason': 'custom_skill_object_key',
    'expression': rawKey,
  });
}

String _unquote(String expr) {
  final body = expr.substring(1, expr.length - 1);
  return body
      .replaceAll(r'\"', '"')
      .replaceAll(r"\'", "'")
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\t', '\t')
      .replaceAll(r'\\', r'\');
}

int _findTemplateExpressionEnd(String source, int start) {
  var depth = 0;
  var quote = '';
  var escaped = false;
  for (var i = start; i < source.length; i++) {
    final char = source[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      if (char == quote) quote = '';
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char == '{') {
      depth++;
      continue;
    }
    if (char == '}') {
      if (depth == 0) return i;
      depth--;
    }
  }
  throw EngineException(errLlmFormat, {'reason': 'custom_skill_template'});
}

void _expectNoArgs(String method, List<Object?> args) {
  if (args.isEmpty) return;
  _badMethodArgs(method);
}

Never _badMethodArgs(String method) {
  throw EngineException(errLlmFormat, {
    'reason': 'custom_skill_method_args',
    'method': method,
  });
}

extension AgentApi on Engine {
  String _agentMemoryIsolationKey(int projectId) => 'project:$projectId';
  String _agentConversationIsolationKey(
    int projectId, {
    String family = _scriptAgentFamily,
  }) =>
      '$family:$projectId';

  AgentMemoryService _agentMemoryService({
    String family = _scriptAgentFamily,
  }) =>
      AgentMemoryService(
        db,
        gateway,
        summaryStage: family == _productionAgentFamily
            ? productionAgentDecisionStage
            : scriptAgentDecisionStage,
        embeddingProvider: _agentMemoryEmbeddingProvider(),
      );

  AgentMemorySettings _readAgentMemorySettings() => AgentMemoryService(
        db,
        gateway,
        summaryStage: scriptAgentDecisionStage,
      ).readSettings();

  AgentMemoryEmbeddingProvider _agentMemoryEmbeddingProvider() {
    final settings = _readAgentMemorySettings();
    final localProvider = TokenAgentMemoryEmbeddingProvider(
      modelOnnxFile: settings.modelOnnxFile,
      modelDtype: settings.modelDtype,
    );
    final row = db
        .select(
          "SELECT value FROM o_setting WHERE key='binding.agent_embedding'",
        )
        .firstOrNull;
    final binding = (row?['value'] as String? ?? '').trim();
    if (binding.isEmpty) return localProvider;
    return GatewayAgentMemoryEmbeddingProvider(
      gateway,
      stage: 'agent_embedding',
      fallback: localProvider,
    );
  }

  List<AgentToolDef> get agentTools {
    return _agentTools();
  }

  List<AgentToolDef> _agentTools({String? stage, int? projectId}) {
    final skills = agentSkills();
    final attributions = stage == null
        ? null
        : _agentToolAttributions(stage, projectId: projectId);
    final attributionMap = attributions == null || attributions.isEmpty
        ? const <String, Set<String>>{}
        : _skillAttributionMap();
    final markdownSkills = _activatableMarkdownSkills(
      skills,
      attributions: attributions,
      attributionMap: attributionMap,
      projectId: projectId,
    );
    final tools = <AgentToolDef>[];
    for (final skill in skills) {
      if (!_shouldExposeAgentTool(
        skill,
        attributions: attributions,
        attributionMap: attributionMap,
      )) {
        continue;
      }
      final tool = _agentToolDef(skill);
      tools.add(
        tool.name == 'activate_skill' || tool.name == 'read_skill_file'
            ? _skillNameEnumToolDef(tool, markdownSkills)
            : tool,
      );
    }
    return tools;
  }

  List<AgentToolDef> _agentToolsForStage(String stage, {int? projectId}) =>
      _agentTools(stage: stage, projectId: projectId);

  List<AgentSkill> _markdownSkillsForStage(String stage, {int? projectId}) {
    final attributions = _agentToolAttributions(stage, projectId: projectId);
    final attributionMap = attributions == null || attributions.isEmpty
        ? const <String, Set<String>>{}
        : _skillAttributionMap();
    return _activatableMarkdownSkills(
      agentSkills(),
      attributions: attributions,
      attributionMap: attributionMap,
      projectId: projectId,
    );
  }

  bool _shouldExposeAgentTool(
    AgentSkill skill, {
    required Set<String>? attributions,
    required Map<String, Set<String>> attributionMap,
  }) {
    if (!skill.enabled || skill.type == _markdownAgentSkillType) {
      return false;
    }
    return _matchesSkillAttribution(
      skill,
      attributions: attributions,
      attributionMap: attributionMap,
    );
  }

  List<AgentSkill> _activatableMarkdownSkills(
    List<AgentSkill> skills, {
    required Set<String>? attributions,
    required Map<String, Set<String>> attributionMap,
    required int? projectId,
  }) {
    return [
      for (final skill in skills)
        if (skill.enabled &&
            skill.type == _markdownAgentSkillType &&
            _matchesProjectMarkdownScope(
              skill,
              attributions: attributions,
              attributionMap: attributionMap,
              projectId: projectId,
            ) &&
            _matchesSkillAttribution(
              skill,
              attributions: attributions,
              attributionMap: attributionMap,
            ))
          skill,
    ];
  }

  bool _matchesProjectMarkdownScope(
    AgentSkill skill, {
    required Set<String>? attributions,
    required Map<String, Set<String>> attributionMap,
    required int? projectId,
  }) {
    if (projectId == null || !_isProjectPackMarkdownSkill(skill)) return true;
    final skillAttributions = attributionMap[skill.id];
    if (skillAttributions == null || skillAttributions.isEmpty) return false;
    final suffix = ':project:$projectId';
    return skillAttributions.any(
      (attribution) =>
          attribution.endsWith(suffix) &&
          (attributions == null || attributions.contains(attribution)),
    );
  }

  bool _isProjectPackMarkdownSkill(AgentSkill skill) {
    final path = skill.script.replaceAll('\\', '/');
    return path.contains('/skills/art_skills/') ||
        path.contains('/skills/story_skills/') ||
        path.contains('/skills/production_skills/');
  }

  bool _matchesSkillAttribution(
    AgentSkill skill, {
    required Set<String>? attributions,
    required Map<String, Set<String>> attributionMap,
  }) {
    if (attributions == null || attributions.isEmpty) return true;
    final skillAttributions = attributionMap[skill.id];
    if (skillAttributions == null || skillAttributions.isEmpty) {
      return true;
    }
    return skillAttributions.any(attributions.contains);
  }

  AgentToolDef _agentToolDef(AgentSkill skill) {
    final defaultTool = _defaultTool(skill.id);
    return AgentToolDef(
      name: skill.id,
      description: skill.description.isEmpty
          ? defaultTool?.description ?? ''
          : skill.description,
      schema: skill.schema.isNotEmpty
          ? skill.schema
          : defaultTool?.schema ?? const {},
    );
  }

  AgentToolDef _skillNameEnumToolDef(
    AgentToolDef tool,
    List<AgentSkill> markdownSkills,
  ) {
    if (markdownSkills.isEmpty) return tool;
    final names = [for (final skill in markdownSkills) skill.name];
    final resources = tool.name == 'read_skill_file'
        ? _markdownSkillResourceFiles(markdownSkills)
        : const <String>[];
    final schema = Map<String, dynamic>.from(tool.schema);
    final properties =
        Map<String, dynamic>.from(schema['properties'] as Map? ?? const {});
    for (final key in ['name', 'skill', 'skillName', 'skillId', 'skill_name']) {
      final fieldSchema =
          Map<String, dynamic>.from(properties[key] as Map? ?? const {});
      fieldSchema['enum'] = names;
      properties[key] = fieldSchema;
    }
    if (resources.isNotEmpty) {
      for (final key in [
        'filePath',
        'path',
        'file',
        'filename',
        'relativePath',
      ]) {
        final fieldSchema =
            Map<String, dynamic>.from(properties[key] as Map? ?? const {});
        fieldSchema['enum'] = resources;
        properties[key] = fieldSchema;
      }
    }
    schema['properties'] = properties;
    final resourceDescription =
        resources.isEmpty ? '' : ' 可读资源：${resources.join('、')}。';
    return AgentToolDef(
      name: tool.name,
      description:
          '${tool.description} 可用技能：${names.join('、')}。$resourceDescription',
      schema: schema,
    );
  }

  List<String> _markdownSkillResourceFiles(List<AgentSkill> markdownSkills) {
    final values = <String>[];
    final seen = <String>{};
    for (final skill in markdownSkills) {
      final row = db.select(
        'SELECT path,md5 FROM o_skillList WHERE id=? AND type=?',
        [skill.id, _markdownAgentSkillType],
      ).firstOrNull;
      if (row == null) continue;
      final resources = _decodeMarkdownSkillResources(row['md5']);
      for (final file in listAgentSkillResourceFiles(
        row['path'] as String? ?? '',
        workspaceDirs: resources.workspaceDirs,
        attachedSkillDirs: resources.attachedSkillDirs,
      )) {
        if (seen.add(file)) values.add(file);
      }
    }
    return values;
  }

  Map<String, Set<String>> _skillAttributionMap() {
    final rows =
        db.select('SELECT skillId,attribution FROM o_skillAttribution');
    final result = <String, Set<String>>{};
    for (final row in rows) {
      final skillId = row['skillId'] as String? ?? '';
      final attribution = row['attribution'] as String? ?? '';
      if (skillId.isEmpty || attribution.isEmpty) continue;
      (result[skillId] ??= <String>{}).add(attribution);
    }
    return result;
  }

  Set<String>? _agentToolAttributions(String stage, {int? projectId}) {
    final exact = switch (stage) {
      'scriptAgent' || 'scriptAgent:decisionAgent' => {'script_agent_decision'},
      'scriptAgent:storySkeletonAgent' => {
          'script_execution_skeleton',
          'script_agent_execution',
        },
      'scriptAgent:adaptationStrategyAgent' => {
          'script_execution_adaptation',
          'script_agent_execution',
        },
      'scriptAgent:scriptAgent' => {
          'script_execution_script',
          'script_agent_execution',
        },
      'scriptAgent:supervisionAgent' => {'script_agent_supervision'},
      'productionAgent' || 'productionAgent:decisionAgent' => {
          'production_agent_decision'
        },
      'productionAgent:deriveAssetsAgent' => {
          'production_execution_derive_assets',
          'production_agent_execution',
        },
      'productionAgent:generateAssetsAgent' => {
          'production_execution_generate_assets',
          'production_agent_execution',
        },
      'productionAgent:directorPlanAgent' => {
          'production_execution_director_plan',
          'production_agent_execution',
        },
      'productionAgent:storyboardGenAgent' => {
          'production_execution_storyboard_gen',
          'production_agent_execution',
        },
      'productionAgent:storyboardPanelAgent' => {
          'production_execution_storyboard_panel',
          'production_agent_execution',
        },
      'productionAgent:storyboardTableAgent' => {
          'production_execution_storyboard_table',
          'production_agent_execution',
        },
      'productionAgent:supervisionAgent' => {'production_agent_supervision'},
      _ => null,
    };
    if (exact != null) {
      return _withProjectSkillAttributions(exact, stage, projectId);
    }

    final definition = agentStageDefinition(stage);
    if (definition == null) return null;
    final family = switch (definition.family) {
      _scriptAgentFamily => 'script_agent',
      _productionAgentFamily => 'production_agent',
      _ => null,
    };
    if (family == null) return null;
    final role = switch (definition.role) {
      'decision' => 'decision',
      'execution' => 'execution',
      'supervision' => 'supervision',
      _ => null,
    };
    if (role == null) return null;
    return _withProjectSkillAttributions({'${family}_$role'}, stage, projectId);
  }

  Set<String> _withProjectSkillAttributions(
    Set<String> attributions,
    String stage,
    int? projectId,
  ) {
    if (projectId == null) return attributions;
    final result = {...attributions};
    if (stage.startsWith('productionAgent:') &&
        attributions.contains('production_agent_execution')) {
      result.add(_projectAgentSkillAttribution(
        'production_agent_execution',
        projectId,
      ));
    }
    if (stage == productionAgentStoryboardPanelStage) {
      result.add(_projectAgentSkillAttribution(
        'production_execution_storyboard_panel',
        projectId,
      ));
    }
    if (stage == productionAgentStoryboardTableStage) {
      result.add(_projectAgentSkillAttribution(
        'production_execution_storyboard_table',
        projectId,
      ));
    }
    return result;
  }

  String _projectAgentSkillAttribution(String attribution, int projectId) =>
      '$attribution:project:$projectId';

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

  List<AgentSkill> _agentSkills({String? attribution}) {
    _ensureAgentSkillsSeeded();
    final allowedTypes = [
      _agentSkillType,
      _customAgentSkillType,
      _markdownAgentSkillType,
    ];
    final rows = attribution == null
        ? db.select(
            'SELECT id,name,description,state,type,path,md5 FROM o_skillList '
            'WHERE type IN (${List.filled(allowedTypes.length, '?').join(',')}) '
            'ORDER BY createTime ASC, id ASC',
            allowedTypes,
          )
        : db.select(
            'SELECT s.id,s.name,s.description,s.state,s.type,s.path,s.md5 '
            'FROM o_skillList s '
            'JOIN o_skillAttribution a ON a.skillId=s.id '
            'WHERE a.attribution=? '
            'AND s.type IN (${List.filled(allowedTypes.length, '?').join(',')}) '
            'ORDER BY s.createTime ASC, s.id ASC',
            [attribution, ...allowedTypes],
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
          script: row['path'] as String? ?? '',
          schema: _skillSchema(row['md5']),
        ),
    ];
  }

  List<AgentSkill> agentSkillsByAttribution(String attribution) =>
      _agentSkills(attribution: attribution);

  List<AgentSkill> agentSkillsForAttribution(String attribution) =>
      _agentSkills(attribution: attribution);

  List<AgentSkill> agentSkills({String? attribution}) =>
      _agentSkills(attribution: attribution);

  void saveCustomAgentSkill({
    required String id,
    required String name,
    required String description,
    required String script,
    Map<String, dynamic> schema = const {},
    bool enabled = true,
    String? attribution,
  }) {
    final normalizedId = id.trim();
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(normalizedId)) {
      throw EngineException(errLlmFormat, {'reason': '技能 id 只能包含字母、数字和下划线'});
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_skillList '
      '(id,name,description,state,type,createTime,updateTime,path,md5,embedding) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        normalizedId,
        name.trim().isEmpty ? normalizedId : name.trim(),
        description.trim(),
        enabled ? 1 : 0,
        _customAgentSkillType,
        db.select('SELECT createTime FROM o_skillList WHERE id=?',
                [normalizedId]).firstOrNull?['createTime'] as int? ??
            now,
        now,
        script,
        jsonEncode(schema),
        '',
      ],
    );
    final trimmedAttribution = attribution?.trim();
    if (trimmedAttribution != null) {
      db.execute(
          'DELETE FROM o_skillAttribution WHERE skillId=?', [normalizedId]);
      if (trimmedAttribution.isNotEmpty) {
        db.execute(
          'INSERT OR REPLACE INTO o_skillAttribution (attribution,skillId) VALUES (?,?)',
          [trimmedAttribution, normalizedId],
        );
      }
    }
  }

  List<AgentSkill> seedToonFlowMarkdownAgentSkills(String skillsRootPath) {
    final seeded = seedToonFlowMarkdownAgentSkillsInDb(db, skillsRootPath);
    return [
      for (final skill in seeded)
        agentSkills().singleWhere((item) => item.id == skill.id),
    ];
  }

  AgentSkill saveMarkdownAgentSkill({
    required String filePath,
    String? attribution,
    bool enabled = true,
    List<String> workspaceDirs = const [],
    List<String> attachedSkillDirs = const [],
  }) {
    final parsed = parseAgentSkillFile(filePath);
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
        _markdownAgentSkillType,
        db.select('SELECT createTime FROM o_skillList WHERE id=?',
                [parsed.id]).firstOrNull?['createTime'] as int? ??
            now,
        now,
        filePath,
        encodeMarkdownSkillResources(
          workspaceDirs: workspaceDirs,
          attachedSkillDirs: attachedSkillDirs,
        ),
        '',
      ],
    );
    final trimmedAttribution = attribution?.trim();
    if (trimmedAttribution != null && trimmedAttribution.isNotEmpty) {
      db.execute(
        'INSERT OR REPLACE INTO o_skillAttribution (attribution,skillId) VALUES (?,?)',
        [trimmedAttribution, parsed.id],
      );
    }
    return agentSkills().singleWhere((skill) => skill.id == parsed.id);
  }

  AgentSkillActivation activateAgentSkill(String name) {
    final row = _markdownSkillRow(name);
    return _activateAgentSkillFromRow(row);
  }

  AgentSkillActivation _activateAgentSkillForContext(
    String name, {
    String? stage,
    required int projectId,
  }) {
    final row = _markdownSkillRowForContext(
      name,
      stage: stage,
      projectId: projectId,
    );
    return _activateAgentSkillFromRow(row);
  }

  AgentSkillActivation _activateAgentSkillFromRow(Map<String, Object?> row) {
    final filePath = row['path'] as String? ?? '';
    final parsed = parseAgentSkillFile(filePath);
    final resources = _decodeMarkdownSkillResources(row['md5']);
    return AgentSkillActivation(
      id: row['id'] as String,
      name: row['name'] as String? ?? parsed.name,
      description: row['description'] as String? ?? parsed.description,
      content: parsed.body,
      filePath: filePath,
      resourceFiles: listAgentSkillResourceFiles(
        filePath,
        workspaceDirs: resources.workspaceDirs,
        attachedSkillDirs: resources.attachedSkillDirs,
      ),
    );
  }

  String readAgentSkillFile(String name, String relativePath) {
    final row = _markdownSkillRow(name);
    return _readAgentSkillFileFromRow(row, relativePath);
  }

  String _readAgentSkillFileForContext(
    String name,
    String relativePath, {
    String? stage,
    required int projectId,
  }) {
    final row = _markdownSkillRowForContext(
      name,
      stage: stage,
      projectId: projectId,
    );
    return _readAgentSkillFileFromRow(row, relativePath);
  }

  String _readAgentSkillFileFromRow(
    Map<String, Object?> row,
    String relativePath,
  ) {
    final resources = _decodeMarkdownSkillResources(row['md5']);
    return readAgentSkillFileUnderRoot(
      row['path'] as String? ?? '',
      relativePath,
      workspaceDirs: resources.workspaceDirs,
      attachedSkillDirs: resources.attachedSkillDirs,
    );
  }

  String _formatActivatedAgentSkill(AgentSkillActivation skill) {
    final buffer = StringBuffer()
      ..writeln('<skill_content name="${_escapeSkillPromptXml(skill.name)}">')
      ..writeln(skill.content.trimRight())
      ..writeln()
      ..writeln('使用 read_skill_file 工具读取资源文件。');
    if (skill.resourceFiles.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('<skill_resources>');
      for (final file in skill.resourceFiles) {
        buffer.writeln('  <file>$file</file>');
      }
      buffer.writeln('</skill_resources>');
    }
    buffer.write('</skill_content>');
    return buffer.toString();
  }

  String _formatReadAgentSkillFile(String content) {
    final buffer = StringBuffer()
      ..writeln('<skill_content>')
      ..writeln(content.trimRight())
      ..writeln()
      ..writeln('可以使用 read_skill_file 工具读取资源文件。')
      ..write('</skill_content>');
    return buffer.toString();
  }

  Map<String, Object?> _markdownSkillRow(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw EngineException(errLlmFormat, {'reason': '技能名称不能为空'});
    }
    final row = db.select(
      'SELECT id,name,description,path,md5 FROM o_skillList '
      'WHERE (id=? OR name=?) AND type=? AND COALESCE(state,1)!=0 LIMIT 1',
      [trimmed, trimmed, _markdownAgentSkillType],
    ).firstOrNull;
    if (row == null) {
      throw EngineException(errLlmFormat, {'reason': 'Markdown 技能不存在或未启用'});
    }
    return row;
  }

  Map<String, Object?> _markdownSkillRowForContext(
    String name, {
    String? stage,
    required int projectId,
  }) {
    if (stage == null || stage.trim().isEmpty) return _markdownSkillRow(name);
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw EngineException(errLlmFormat, {'reason': '技能名称不能为空'});
    }
    final allowed = _markdownSkillsForStage(stage, projectId: projectId)
        .where((skill) => skill.id == trimmed || skill.name == trimmed)
        .map((skill) => skill.id)
        .toList();
    if (allowed.isEmpty) {
      throw EngineException(errLlmFormat, {'reason': 'Markdown 技能不存在或未启用'});
    }
    final placeholders = List.filled(allowed.length, '?').join(',');
    final row = db.select(
      'SELECT id,name,description,path,md5 FROM o_skillList '
      'WHERE id IN ($placeholders) AND type=? AND COALESCE(state,1)!=0 '
      'ORDER BY createTime ASC, id ASC LIMIT 1',
      [...allowed, _markdownAgentSkillType],
    ).firstOrNull;
    if (row == null) {
      throw EngineException(errLlmFormat, {'reason': 'Markdown 技能不存在或未启用'});
    }
    return row;
  }

  _MarkdownSkillResources _decodeMarkdownSkillResources(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) {
      return const _MarkdownSkillResources();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const _MarkdownSkillResources();
      return _MarkdownSkillResources(
        workspaceDirs: _stringList(decoded['workspaceDirs']),
        attachedSkillDirs: _stringList(decoded['attachedSkillDirs']),
      );
    } catch (_) {
      return const _MarkdownSkillResources();
    }
  }

  List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is String && item.trim().isNotEmpty)
          item.trim().replaceAll('\\', '/'),
    ];
  }

  void updateAgentSkill(
    String id, {
    String? description,
    bool? enabled,
  }) {
    _ensureAgentSkillsSeeded();
    final row = db.select(
      'SELECT id,description,state,type FROM o_skillList '
      'WHERE id=? AND type IN (?,?,?)',
      [id, _agentSkillType, _customAgentSkillType, _markdownAgentSkillType],
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
        row['type'],
      ],
    );
  }

  void _ensureAgentDeploymentsSeeded() {
    for (final definition in agentStageDefinitions) {
      final exists = db.select(
        'SELECT id FROM o_agentDeploy WHERE key=? LIMIT 1',
        [definition.key],
      );
      if (exists.isNotEmpty) continue;
      final binding = db.select(
        'SELECT value FROM o_setting WHERE key=?',
        ['binding.${definition.fallbackStage}'],
      ).firstOrNull?['value'] as String?;
      final split = _splitBinding(binding);
      db.execute(
        'INSERT INTO o_agentDeploy '
        '(key,name,desc,type,vendorId,modelName,model,disabled,maxOutputTokens,temperature) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          definition.key,
          definition.name,
          '',
          _agentDeploymentType,
          split.$1,
          split.$2,
          split.$1.isEmpty || split.$2.isEmpty ? '' : '${split.$1}:${split.$2}',
          0,
          definition.defaultMaxOutputTokens,
          definition.defaultTemperature,
        ],
      );
    }
  }

  List<AgentDeployment> agentDeployments() {
    _ensureAgentDeploymentsSeeded();
    final rows = db
        .select(
          'SELECT key,name,vendorId,modelName,disabled,maxOutputTokens,temperature '
          'FROM o_agentDeploy WHERE key IN (${List.filled(agentStageKeys.length, '?').join(',')})',
          agentStageKeys,
        )
        .toList()
      ..sort((a, b) => agentStageSortOrder(a['key'] as String)
          .compareTo(agentStageSortOrder(b['key'] as String)));
    return [
      for (final row in rows) _deploymentFromRow(row),
    ];
  }

  AgentDeployment _deploymentFromRow(Map<String, Object?> row) {
    final key = row['key'] as String;
    final definition = agentStageDefinition(key);
    return AgentDeployment(
      key: key,
      name: row['name'] as String? ?? definition?.name ?? key,
      family: definition?.family ?? 'custom',
      role: definition?.role ?? 'custom',
      fallbackStage: definition?.fallbackStage ?? key,
      vendorId: row['vendorId'] as String? ?? '',
      modelName: row['modelName'] as String? ?? '',
      maxOutputTokens: row['maxOutputTokens'] as int? ??
          definition?.defaultMaxOutputTokens ??
          8000,
      temperature:
          row['temperature'] as int? ?? definition?.defaultTemperature ?? 70,
      disabled: _truthy(row['disabled']),
    );
  }

  void updateAgentDeployment(
    String key, {
    String? vendorId,
    String? modelName,
    int? maxOutputTokens,
    int? temperature,
    bool? disabled,
  }) {
    final definition = agentStageDefinition(key);
    if (definition == null) {
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
    final nextMaxTokens = (maxOutputTokens ??
            row['maxOutputTokens'] as int? ??
            definition.defaultMaxOutputTokens)
        .clamp(256, 64000)
        .toInt();
    final nextTemperature = (temperature ??
            row['temperature'] as int? ??
            definition.defaultTemperature)
        .clamp(0, 200)
        .toInt();
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

  String _agentChatKey(String family) => 'agentChat:$family';

  List<AgentMessage> agentMessages(
    int projectId, {
    String family = agentFamilyScript,
  }) {
    final row = db.select(
          'SELECT data FROM o_agentWorkData '
          'WHERE projectId=? AND episodesId IS NULL AND key=?',
          [projectId, _agentChatKey(family)],
        ).firstOrNull ??
        (family == _scriptAgentFamily
            ? db.select(
                'SELECT data FROM o_agentWorkData '
                "WHERE projectId=? AND episodesId IS NULL AND key='agentChat'",
                [projectId],
              ).firstOrNull
            : null);
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

  void _saveAgentMessages(
    int projectId,
    List<AgentMessage> messages, {
    required String family,
  }) {
    final key = _agentChatKey(family);
    final json = jsonEncode([for (final m in messages) m.toJson()]);
    final exists = db.select(
      'SELECT id FROM o_agentWorkData '
      'WHERE projectId=? AND episodesId IS NULL AND key=?',
      [projectId, key],
    ).firstOrNull;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (exists == null) {
      db.execute(
        'INSERT INTO o_agentWorkData (projectId,key,data,createTime,updateTime) '
        'VALUES (?,?,?,?,?)',
        [projectId, key, json, now, now],
      );
    } else {
      db.execute(
        'UPDATE o_agentWorkData SET data=?, updateTime=? WHERE id=?',
        [json, now, exists['id']],
      );
    }
  }

  void clearAgentMemory(int projectId, {String? family}) {
    if (family == null) {
      db.execute(
        'DELETE FROM o_agentWorkData WHERE projectId=? '
        'AND episodesId IS NULL AND (key=? OR key LIKE ?)',
        [projectId, 'agentChat', 'agentChat:%'],
      );
      _clearAgentConversationMemory(projectId, family: _scriptAgentFamily);
      _clearAgentConversationMemory(projectId, family: _productionAgentFamily);
      return;
    }
    db.execute(
      'DELETE FROM o_agentWorkData WHERE projectId=? AND episodesId IS NULL '
      'AND (key=? OR (?=? AND key=?))',
      [
        projectId,
        _agentChatKey(family),
        family,
        _scriptAgentFamily,
        'agentChat',
      ],
    );
    _clearAgentConversationMemory(projectId, family: family);
  }

  void clearAgentMemoryScope(
    int projectId, {
    String? family,
    required String scope,
  }) {
    final trimmedScope = scope.trim();
    final service = _agentMemoryService(
      family: family ?? _scriptAgentFamily,
    );
    if (trimmedScope == agentMemoryTypeNote) {
      service.clear(
        isolationKey: _agentMemoryIsolationKey(projectId),
        scope: agentMemoryTypeNote,
      );
      return;
    }
    final families = family == null
        ? const [_scriptAgentFamily, _productionAgentFamily]
        : [family];
    for (final item in families) {
      service.clear(
        isolationKey: _agentConversationIsolationKey(projectId, family: item),
        scope: trimmedScope,
      );
    }
  }

  void _clearAgentConversationMemory(
    int projectId, {
    required String family,
  }) {
    db.execute(
      'DELETE FROM memories WHERE isolationKey=? AND type IN (?,?)',
      [
        _agentConversationIsolationKey(projectId, family: family),
        agentMemoryTypeMessage,
        agentMemoryTypeSummary,
      ],
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

  List<AgentMemoryRecord> agentMemorySummaries(
    int projectId, {
    String family = _scriptAgentFamily,
  }) {
    final rows = db.select(
      'SELECT id,name,content,createTime,embedding,relatedMessageIds FROM memories '
      'WHERE isolationKey=? AND type=? '
      'ORDER BY createTime DESC, id DESC',
      [
        _agentConversationIsolationKey(projectId, family: family),
        agentMemoryTypeSummary,
      ],
    );
    return [for (final row in rows) AgentMemoryRecord.fromRow(row)];
  }

  List<AgentMemoryRecord> agentMemorySummaryMessages(
    int projectId,
    String summaryId, {
    String family = _scriptAgentFamily,
  }) {
    final isolationKey =
        _agentConversationIsolationKey(projectId, family: family);
    final row = db.select(
      'SELECT relatedMessageIds FROM memories '
      'WHERE isolationKey=? AND id=? AND type=?',
      [isolationKey, summaryId, agentMemoryTypeSummary],
    ).firstOrNull;
    final ids = _decodeAgentMemoryIdList(row?['relatedMessageIds']);
    if (ids.isEmpty) return const [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = db.select(
      'SELECT id,name,content,createTime,embedding,relatedMessageIds FROM memories '
      'WHERE isolationKey=? AND type=? AND id IN ($placeholders) '
      'ORDER BY createTime ASC, id ASC',
      [isolationKey, agentMemoryTypeMessage, ...ids],
    );
    return [for (final item in rows) AgentMemoryRecord.fromRow(item)];
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

  Future<List<AgentMemoryRecord>> searchAgentMemories(
    int projectId,
    String query, {
    int limit = 5,
  }) async {
    final entries = await _agentMemoryService().searchNotes(
      isolationKey: _agentMemoryIsolationKey(projectId),
      query: query,
      limit: limit,
    );
    return [for (final entry in entries) AgentMemoryRecord.fromEntry(entry)];
  }

  String _memoryEmbeddingJson(String name, String content) {
    final settings = _readAgentMemorySettings();
    return TokenAgentMemoryEmbeddingProvider(
      modelOnnxFile: settings.modelOnnxFile,
      modelDtype: settings.modelDtype,
    ).embeddingJson('$name $content');
  }

  String _agentSystemPrompt(
    List<AgentMemoryRecord> memories, {
    AgentMemoryContext? context,
    String? base,
    String? stage,
    int? projectId,
    List<String> activatedSkills = const [],
    List<AgentSkill> availableSkills = const [],
  }) {
    const defaultBase = '你是短剧创作助手。你可以调用工具推进项目的制作流程'
        '（事件提取→提取资产→生成分镜→生成首帧图→生成视频→配音绑定→合成）。'
        '每次只做用户明确要求或明显下一步需要的动作，不要臆造不存在的 id。'
        '如果不确定该做什么，先调用 get_status 查看进度。';
    final stageMainSkill = _stageMainMarkdownSkill(stage, projectId: projectId);
    final promptBase = _formatStageMainSystemPrompt(
      base ?? defaultBase,
      stageMainSkill,
    );
    final lines = <String>[];
    if (availableSkills.isNotEmpty) {
      lines.addAll([
        '',
        '',
        _formatAvailableAgentSkills(availableSkills),
      ]);
    }
    if (activatedSkills.isNotEmpty) {
      lines.addAll([
        '',
        '',
        '已激活 Agent 技能：',
        for (final skill in activatedSkills) '---\n$skill',
      ]);
    }
    if (memories.isNotEmpty) {
      lines.addAll([
        '',
        '',
        '长期记忆：',
        for (final memory in memories) _formatLongTermMemoryNote(memory),
      ]);
    }
    if (context != null && !context.isEmpty) {
      lines.addAll(['', '', 'Agent 记忆上下文：']);
      if (context.relatedMessages.isNotEmpty) {
        lines.add('相关历史记忆：');
        for (final memory in context.relatedMessages) {
          lines.add('  ${_formatAgentMemoryContextEntry('memory', memory)}');
        }
      }
      if (context.summaries.isNotEmpty) {
        lines.add('历史摘要：');
        for (final summary in context.summaries) {
          lines.add('  ${_formatAgentMemoryContextEntry('summary', summary)}');
        }
      }
      if (context.recentMessages.isNotEmpty) {
        lines.add('近期对话：');
        for (final memory in context.recentMessages) {
          lines.add('  ${_formatAgentMemoryContextEntry('recent', memory)}');
        }
      }
    }
    if (lines.isEmpty) return promptBase;
    return '$promptBase${lines.join('\n')}';
  }

  AgentSkillActivation? _stageMainMarkdownSkill(
    String? stage, {
    int? projectId,
  }) {
    final fileName = _stageMainSkillFileName(stage);
    if (fileName == null) return null;
    final attributions = _agentToolAttributions(stage!, projectId: projectId);
    if (attributions == null || attributions.isEmpty) return null;
    final placeholders = List.filled(attributions.length, '?').join(',');
    final rows = db.select(
      'SELECT s.id,s.name,s.description,s.path,s.md5 '
      'FROM o_skillList s '
      'JOIN o_skillAttribution a ON a.skillId=s.id '
      'WHERE a.attribution IN ($placeholders) '
      'AND s.type=? AND COALESCE(s.state,1)!=0 '
      'ORDER BY s.createTime ASC, s.id ASC',
      [...attributions, _markdownAgentSkillType],
    );
    for (final row in rows) {
      final path = row['path'] as String? ?? '';
      if (p.basename(path) == fileName) {
        return _activateAgentSkillFromRow(row);
      }
    }
    return null;
  }

  String? _stageMainSkillFileName(String? stage) {
    switch (stage) {
      case 'scriptAgent':
      case scriptAgentDecisionStage:
        return 'script_agent_decision.md';
      case scriptAgentStorySkeletonStage:
        return 'script_execution_skeleton.md';
      case scriptAgentAdaptationStrategyStage:
        return 'script_execution_adaptation.md';
      case scriptAgentScriptStage:
        return 'script_execution_script.md';
      case scriptAgentSupervisionStage:
        return 'script_agent_supervision.md';
      case 'productionAgent':
      case productionAgentDecisionStage:
        return 'production_agent_decision.md';
      case productionAgentDeriveAssetsStage:
        return 'production_execution_derive_assets.md';
      case productionAgentGenerateAssetsStage:
        return 'production_execution_generate_assets.md';
      case productionAgentDirectorPlanStage:
        return 'production_execution_director_plan.md';
      case productionAgentStoryboardGenStage:
        return 'production_execution_storyboard_gen.md';
      case productionAgentStoryboardPanelStage:
        return 'production_execution_storyboard_panel.md';
      case productionAgentStoryboardTableStage:
        return 'production_execution_storyboard_table.md';
      case productionAgentSupervisionStage:
        return 'production_agent_supervision.md';
      default:
        return null;
    }
  }

  String _formatStageMainSystemPrompt(
    String base,
    AgentSkillActivation? skill,
  ) {
    if (skill == null || skill.content.trim().isEmpty) return base;
    final buffer = StringBuffer(base.trimRight())
      ..writeln()
      ..writeln()
      ..writeln('## ToonFlow stage 主技能')
      ..writeln('<skill_content name="${_escapeSkillPromptXml(skill.name)}">')
      ..writeln(skill.content.trimRight())
      ..write('</skill_content>');
    return buffer.toString();
  }

  String _formatLongTermMemoryNote(AgentMemoryRecord memory) {
    final attrs = <String>[
      'id="${_escapeXmlAttr(memory.id)}"',
      'type="$agentMemoryTypeNote"',
      if (memory.name.isNotEmpty) 'name="${_escapeXmlAttr(memory.name)}"',
      'createTime="${memory.createdAt}"',
      if (memory.relatedMessageIds.isNotEmpty)
        'relatedMessageIds="${_escapeXmlAttr(memory.relatedMessageIds.join(','))}"',
      if (memory.score != null) 'score="${memory.score}"',
      if (memory.matchedTokens.isNotEmpty)
        'matchedTokens="${_escapeXmlAttr(memory.matchedTokens.join(','))}"',
    ];
    return '<note ${attrs.join(' ')}>${_escapeXmlText(memory.content)}</note>';
  }

  String _formatAgentMemoryContextEntry(
    String tag,
    AgentMemoryEntry memory,
  ) {
    final attrs = <String>[
      'id="${_escapeXmlAttr(memory.id)}"',
      'type="${_escapeXmlAttr(memory.type)}"',
      if (memory.role.isNotEmpty) 'role="${_escapeXmlAttr(memory.role)}"',
      if (memory.name.isNotEmpty) 'name="${_escapeXmlAttr(memory.name)}"',
      'createTime="${memory.createdAt}"',
      if (memory.sourceSummaryIds.isNotEmpty)
        'sourceSummaryIds="${_escapeXmlAttr(memory.sourceSummaryIds.join(','))}"',
      if (memory.relatedMessageIds.isNotEmpty)
        'relatedMessageIds="${_escapeXmlAttr(memory.relatedMessageIds.join(','))}"',
      if (memory.score != null) 'score="${memory.score}"',
    ];
    return '<$tag ${attrs.join(' ')}>${_escapeXmlText(memory.content)}</$tag>';
  }

  Set<String> _agentMemoryContextIds(AgentMemoryContext context) => {
        for (final memory in context.relatedMessages)
          if (memory.id.trim().isNotEmpty) memory.id,
        for (final summary in context.summaries)
          if (summary.id.trim().isNotEmpty) summary.id,
        for (final memory in context.recentMessages)
          if (memory.id.trim().isNotEmpty) memory.id,
      };

  String _formatAvailableAgentSkills(List<AgentSkill> skills) {
    final buffer = StringBuffer()
      ..writeln('## Skills')
      ..writeln('当任务与某个技能的描述匹配时，调用 activate_skill 工具并传入技能名称来加载完整指令。')
      ..writeln('加载后遵循技能指令执行任务，需要时调用 read_skill_file 读取资源文件内容。')
      ..writeln()
      ..writeln('<available_skills>');
    for (final skill in skills) {
      buffer
        ..writeln('  <skill>')
        ..writeln('    <name>${_escapeSkillPromptXml(skill.name)}</name>')
        ..writeln(
          '    <description>${_escapeSkillPromptXml(skill.description)}</description>',
        )
        ..writeln('  </skill>');
    }
    buffer.write('</available_skills>');
    return buffer.toString();
  }

  String _escapeSkillPromptXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  List<String> _activatedAgentSkillContexts(List<AgentMessage> messages) {
    final values = <String>[];
    final seen = <String>{};
    for (final message in messages) {
      if (message.role != agentRoleTool ||
          message.toolName != 'activate_skill') {
        continue;
      }
      final content = _normalizeActivatedSkillContext(message.content);
      if (content.isNotEmpty && seen.add(content)) values.add(content);
    }
    return values;
  }

  List<String> _activatedAgentSkillContextsFromHistory(
    List<Map<String, String>> history,
  ) {
    final values = <String>[];
    final seen = <String>{};
    for (final message in history) {
      final content = message['content'] ?? '';
      final xmlContext = _normalizeActivatedSkillContext(content);
      if (xmlContext.isNotEmpty) {
        if (seen.add(xmlContext)) values.add(xmlContext);
        continue;
      }
      final marker = content.indexOf('已激活技能 ');
      if (marker < 0) continue;
      var text = content.substring(marker).trim();
      if (text.endsWith('）')) text = text.substring(0, text.length - 1).trim();
      text = _normalizeActivatedSkillContext(text);
      if (text.isNotEmpty && seen.add(text)) values.add(text);
    }
    return values;
  }

  String _normalizeActivatedSkillContext(String content) {
    final text = content.trim();
    if (text.isEmpty) return '';
    if (text.startsWith('已激活技能 ')) return text;
    return _extractActivatedSkillXml(text);
  }

  String _extractActivatedSkillXml(String text) {
    final start = text.indexOf('<skill_content');
    if (start < 0) return '';
    const closeTag = '</skill_content>';
    final end = text.indexOf(closeTag, start);
    if (end < 0) return '';
    final xml = text.substring(start, end + closeTag.length).trim();
    final openEnd = xml.indexOf('>');
    if (openEnd < 0) return '';
    final opening = xml.substring(0, openEnd + 1);
    if (!RegExp(r'\sname\s*=').hasMatch(opening)) return '';
    return xml;
  }

  String _activatedAgentSkillNameFromContext(String context) {
    final text = context.trim();
    final legacy = RegExp(r'^已激活技能\s+([^：:\n]+)[：:]').firstMatch(text);
    if (legacy != null) return legacy.group(1)?.trim() ?? '';
    final xml =
        RegExp(r'^<skill_content\b[^>]*\bname="([^"]+)"').firstMatch(text);
    if (xml != null) return xml.group(1)?.trim() ?? '';
    return '';
  }

  List<String> _activatedAgentSkillNames(Iterable<String> contexts) {
    final names = <String>[];
    final seen = <String>{};
    for (final context in contexts) {
      final name = _activatedAgentSkillNameFromContext(context);
      if (name.isNotEmpty && seen.add(name)) names.add(name);
    }
    return names;
  }

  List<String> _mergeActivatedAgentSkillContexts(
    Iterable<String> first,
    Iterable<String> second,
  ) {
    final values = <String>[];
    final seen = <String>{};
    for (final item in [...first, ...second]) {
      final normalized = _normalizeActivatedSkillContext(item);
      if (normalized.isNotEmpty && seen.add(normalized)) values.add(normalized);
    }
    return values;
  }

  /// Agent 执行模式（auto/manual）持久化。config 由别处拥有，此处直接写 o_setting
  /// 键 agent.useMode（'auto'/'manual'），与 ToonFlow 的 auto/manual 语义一致。
  bool agentUseMode() {
    final row = db
        .select("SELECT value FROM o_setting WHERE key='agent.useMode'")
        .firstOrNull;
    return (row?['value'] as String?) == 'auto';
  }

  AgentMemorySettings agentMemorySettings() => _readAgentMemorySettings();

  int agentRagLimit() => agentMemorySettings().ragLimit;

  void setAgentMemorySettings({
    int? messagesPerSummary,
    int? summaryMaxLength,
    int? shortTermLimit,
    int? summaryLimit,
    int? ragLimit,
    int? deepRetrieveSummaryLimit,
    bool? rerankEnabled,
    List<String>? modelOnnxFile,
    String? modelDtype,
  }) {
    if (messagesPerSummary != null) {
      _writeAgentIntSettingWithLegacy(
        'agent.memory.messagesPerSummary',
        'messagesPerSummary',
        messagesPerSummary,
        min: 1,
        max: 50,
      );
    }
    if (summaryMaxLength != null) {
      _writeAgentIntSettingWithLegacy(
        'agent.memory.summaryMaxLength',
        'summaryMaxLength',
        summaryMaxLength,
        min: 80,
        max: 4000,
      );
    }
    if (shortTermLimit != null) {
      _writeAgentIntSettingWithLegacy(
        'agent.memory.shortTermLimit',
        'shortTermLimit',
        shortTermLimit,
        min: 0,
        max: 100,
      );
    }
    if (summaryLimit != null) {
      _writeAgentIntSettingWithLegacy(
        'agent.memory.summaryLimit',
        'summaryLimit',
        summaryLimit,
        min: 0,
        max: 100,
      );
    }
    if (ragLimit != null) {
      _writeAgentIntSettingWithLegacy(
        'agent.memory.ragLimit',
        'ragLimit',
        ragLimit,
        min: 0,
        max: 50,
      );
    }
    if (deepRetrieveSummaryLimit != null) {
      _writeAgentIntSettingWithLegacy(
        'agent.memory.deepRetrieveSummaryLimit',
        'deepRetrieveSummaryLimit',
        deepRetrieveSummaryLimit,
        min: 0,
        max: 50,
      );
    }
    if (rerankEnabled != null) {
      _writeAgentBoolSetting(
        'agent.memory.rerankEnabled',
        rerankEnabled,
      );
    }
    if (modelOnnxFile != null) {
      final normalized = [
        for (final part in modelOnnxFile)
          if (part.trim().isNotEmpty) part.trim(),
      ];
      if (normalized.isNotEmpty) {
        _writeAgentStringSettingWithLegacy(
          'agent.memory.modelOnnxFile',
          'modelOnnxFile',
          jsonEncode(normalized),
        );
      }
    }
    if (modelDtype != null && modelDtype.trim().isNotEmpty) {
      _writeAgentStringSettingWithLegacy(
        'agent.memory.modelDtype',
        'modelDtype',
        modelDtype.trim(),
      );
    }
  }

  int _writeAgentIntSetting(
    String key,
    int value, {
    required int min,
    required int max,
  }) {
    final normalized = value.clamp(min, max).toInt();
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      [key, '$normalized'],
    );
    return normalized;
  }

  int _writeAgentIntSettingWithLegacy(
    String key,
    String legacyKey,
    int value, {
    required int min,
    required int max,
  }) {
    final normalized = _writeAgentIntSetting(
      key,
      value,
      min: min,
      max: max,
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      [legacyKey, '$normalized'],
    );
    return normalized;
  }

  void _writeAgentBoolSetting(String key, bool value) {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      [key, value ? '1' : '0'],
    );
  }

  void _writeAgentStringSettingWithLegacy(
    String key,
    String legacyKey,
    String value,
  ) {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      [key, value],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      [legacyKey, value],
    );
  }

  void setAgentRagLimit(int limit) {
    setAgentMemorySettings(ragLimit: limit);
  }

  void setAgentUseMode(bool autoMode) {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.useMode', autoMode ? 'auto' : 'manual'],
    );
  }

  bool agentSupervisionEnabled() {
    final row = db
        .select(
          "SELECT value FROM o_setting WHERE key='agent.supervision.enabled'",
        )
        .firstOrNull;
    final value = (row?['value'] as String? ?? '').trim().toLowerCase();
    return const {'1', 'true', 'yes', 'on', 'auto'}.contains(value);
  }

  void setAgentSupervisionEnabled(bool enabled) {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.supervision.enabled', enabled ? '1' : '0'],
    );
  }

  /// 发送一条用户消息并驱动 Agent 执行（工具调用全部落 o_tasks，可见可恢复）。
  /// manual 模式每轮只执行一个工具调用；auto 模式在安全上限内连续执行工具链。
  Future<void> sendAgentMessage(
    int projectId,
    String text, {
    required bool autoMode,
    String? family,
  }) async {
    final agentFamily = family ?? _agentFamilyForMessage(text);
    final messages = List<AgentMessage>.from(
      agentMessages(projectId, family: agentFamily),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    messages
        .add(AgentMessage(role: agentRoleUser, content: text, createdAt: now));
    _saveAgentMessages(projectId, messages, family: agentFamily);
    final currentUserMemoryId = await _recordAgentMemory(
      projectId,
      family: agentFamily,
      role: agentRoleUser,
      content: text,
    );
    final excludedDeepRetrieveMemoryIds = {
      if (currentUserMemoryId.isNotEmpty) currentUserMemoryId,
    };

    final conversationKey = _agentConversationIsolationKey(
      projectId,
      family: agentFamily,
    );
    final executedToolSignatures = <String>{};
    String? lastAutoToolName;
    var consecutiveAutoToolCalls = 0;

    for (var turn = 0; turn < (autoMode ? _maxAutoTurns : 1); turn++) {
      final memoryService = _agentMemoryService(family: agentFamily);
      final stage = agentFamily == _productionAgentFamily
          ? productionAgentDecisionStage
          : scriptAgentDecisionStage;
      final system = _agentSystemPrompt(
        await searchAgentMemories(projectId, text, limit: _agentRagLimit()),
        context: await memoryService.get(
          isolationKey: conversationKey,
          query: text,
          excludeRelatedIds: excludedDeepRetrieveMemoryIds,
          excludeRoles: _agentToolAuditRoles,
          excludeRoleSuffixes: _agentToolAuditRoleSuffixes,
        ),
        stage: stage,
        projectId: projectId,
        activatedSkills: _activatedAgentSkillContexts(messages),
        availableSkills: _markdownSkillsForStage(stage, projectId: projectId),
      );
      final projectContext =
          _agentDecisionProjectInfo(projectId, agentFamily).trim();
      final history = [
        if (projectContext.isNotEmpty)
          {'role': 'assistant', 'content': projectContext},
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
        final tools = agentFamily == _productionAgentFamily
            ? productionAgentDecisionTools(
                _agentToolsForStage(stage, projectId: projectId),
              )
            : scriptAgentDecisionTools(
                _agentToolsForStage(stage, projectId: projectId),
              );
        result = await gateway.generateAgentTurn(
          system,
          history,
          tools,
          stage: stage,
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
        _saveAgentMessages(projectId, messages, family: agentFamily);
        return;
      }

      if (!result.isToolCall) {
        messages.add(AgentMessage(
            role: agentRoleAssistant,
            content: result.text ?? '',
            createdAt: DateTime.now().millisecondsSinceEpoch));
        _saveAgentMessages(projectId, messages, family: agentFamily);
        await _recordAgentMemory(
          projectId,
          family: agentFamily,
          role: _agentDecisionMemoryRole,
          content: _removeAllXmlTags(result.text ?? ''),
        );
        return;
      }

      final toolName = result.toolName!;
      final toolArgs = result.toolArgs ?? const {};
      if (autoMode) {
        if (lastAutoToolName == toolName) {
          consecutiveAutoToolCalls++;
        } else {
          lastAutoToolName = toolName;
          consecutiveAutoToolCalls = 1;
        }
        if (consecutiveAutoToolCalls > _maxConsecutiveAutoToolCalls) {
          final content = '已停止自动执行：检测到连续调用 $toolName，避免循环执行。';
          messages.add(AgentMessage(
            role: agentRoleAssistant,
            content: content,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));
          _saveAgentMessages(projectId, messages, family: agentFamily);
          await _recordAgentMemory(
            projectId,
            family: agentFamily,
            role: agentRoleAssistant,
            content: content,
          );
          return;
        }
      }
      final toolSignature = _agentToolCallSignature(toolName, toolArgs);
      if (autoMode && !executedToolSignatures.add(toolSignature)) {
        final content = '已停止自动执行：检测到重复工具调用 $toolName，避免循环执行。';
        messages.add(AgentMessage(
          role: agentRoleAssistant,
          content: content,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        _saveAgentMessages(projectId, messages, family: agentFamily);
        await _recordAgentMemory(
          projectId,
          family: agentFamily,
          role: agentRoleAssistant,
          content: content,
        );
        return;
      }

      final supervisionWasEnabled = agentSupervisionEnabled();
      final rejection = await _reviewAgentToolCall(
        projectId,
        family: agentFamily,
        toolName: toolName,
        toolArgs: toolArgs,
        messages: messages,
        excludedMemoryIds: excludedDeepRetrieveMemoryIds,
      );
      if (rejection != null) {
        final content = '监督 Agent 已拦截 $toolName：$rejection';
        messages.add(AgentMessage(
          role: agentRoleAssistant,
          content: content,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        _saveAgentMessages(projectId, messages, family: agentFamily);
        await _recordAgentMemory(
          projectId,
          family: agentFamily,
          role: 'assistant:supervision',
          content: content,
        );
        return;
      }
      final summary = await _runTool(
        projectId,
        toolName,
        toolArgs,
        agentFamily: agentFamily,
        stage: stage,
        activatedSkills: _activatedAgentSkillContexts(messages),
        excludedMemoryIds: excludedDeepRetrieveMemoryIds,
        excludedRoles: _agentToolAuditRoles,
        excludedRoleSuffixes: _agentToolAuditRoleSuffixes,
      );
      if (supervisionWasEnabled) {
        await _recordAgentSummaryMemory(
          projectId,
          family: agentFamily,
          role: 'assistant:supervision',
          name: '监督审计',
          content:
              '监督 Agent 已放行 $toolName。参数：${jsonEncode(toolArgs)}。执行结果：$summary',
        );
      }
      messages.add(AgentMessage(
        role: agentRoleTool,
        content: summary,
        toolName: toolName,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _saveAgentMessages(projectId, messages, family: agentFamily);
      await _recordAgentToolAuditMemory(
        projectId,
        family: agentFamily,
        baseRole: _agentDecisionMemoryRole,
        toolName: toolName,
        content: summary,
      );
      await _recordAgentMemory(
        projectId,
        family: agentFamily,
        role: agentRoleTool,
        content: summary,
      );
    }
  }

  String _agentSupervisionStage(String family) =>
      family == _productionAgentFamily
          ? productionAgentSupervisionStage
          : scriptAgentSupervisionStage;

  String _agentToolCallSignature(String toolName, Map<String, dynamic> args) =>
      '$toolName:${jsonEncode(_normalizeAgentToolArgs(args))}';

  Object? _normalizeAgentToolArgs(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
      return {
        for (final entry in entries)
          '${entry.key}': _normalizeAgentToolArgs(entry.value),
      };
    }
    if (value is Iterable && value is! String) {
      return [for (final item in value) _normalizeAgentToolArgs(item)];
    }
    return value;
  }

  Future<String?> _reviewAgentToolCall(
    int projectId, {
    required String family,
    required String toolName,
    required Map<String, dynamic> toolArgs,
    required List<AgentMessage> messages,
    Set<String> excludedMemoryIds = const {},
  }) async {
    if (!agentSupervisionEnabled()) return null;
    final stage = _agentSupervisionStage(family);
    final baseSystem = family == _productionAgentFamily
        ? '你是短剧制作监督 Agent。请复核决策 Agent 即将执行的工具调用。'
            '只允许输出 APPROVE 或 REJECT: 中文原因。'
        : '你是短剧剧本监督 Agent。请复核决策 Agent 即将执行的工具调用。'
            '只允许输出 APPROVE 或 REJECT: 中文原因。';
    final recent =
        messages.length <= 6 ? messages : messages.sublist(messages.length - 6);
    final reviewQuery = [
      for (final message in recent) message.content,
      toolName,
      jsonEncode(toolArgs),
    ].join('\n');
    final memoryService = _agentMemoryService(family: family);
    final system = _agentSystemPrompt(
      await searchAgentMemories(projectId, reviewQuery,
          limit: _agentRagLimit()),
      context: await memoryService.get(
        isolationKey: _agentConversationIsolationKey(
          projectId,
          family: family,
        ),
        query: reviewQuery,
        excludeRelatedIds: excludedMemoryIds,
        excludeRoles: _agentToolAuditRoles,
        excludeRoleSuffixes: _agentToolAuditRoleSuffixes,
      ),
      base: baseSystem,
      stage: stage,
      projectId: projectId,
      activatedSkills: _activatedAgentSkillContexts(messages),
      availableSkills: _markdownSkillsForStage(stage, projectId: projectId),
    );
    final user = [
      '当前项目状态：',
      _statusSummary(projectId),
      '',
      '近期对话：',
      for (final message in recent)
        '${message.role}${message.toolName == null ? '' : '(${message.toolName})'}: '
            '${message.content}',
      '',
      '候选工具调用：$toolName',
      '候选参数：${jsonEncode(toolArgs)}',
      '',
      '复核规则：',
      '1. 如果参数明显缺失、前置条件不足、用户没有授权批量/高成本动作，请输出 REJECT: 原因。',
      '2. 如果该调用安全且符合用户意图，请输出 APPROVE。',
    ].join('\n');
    try {
      final result = await gateway.generateAgentTurn(
        system,
        [
          {'role': 'user', 'content': user},
        ],
        const [],
        stage: stage,
      );
      if (result.isToolCall) {
        return '监督 Agent 返回了不允许的工具调用：${result.toolName ?? ''}';
      }
      return _agentSupervisionRejection(result.text ?? '');
    } catch (e) {
      final ex = e is EngineException
          ? e
          : (e is DioException
              ? EngineException(errNetwork, {'message': e.message})
              : EngineException(errLlmFormat, {'message': '$e'}));
      return '监督 Agent 调用失败：${ex.errKey}';
    }
  }

  String? _agentSupervisionRejection(String content) {
    final text = content.trim();
    if (text.isEmpty) return '监督 Agent 未返回明确放行结论。';
    final upper = text.toUpperCase();
    if (upper.startsWith('APPROVE') ||
        text.startsWith('同意') ||
        text.startsWith('通过') ||
        text.startsWith('可执行')) {
      return null;
    }
    if (upper.startsWith('REJECT')) {
      final index = text.indexOf(':');
      if (index >= 0 && index + 1 < text.length) {
        return text.substring(index + 1).trim();
      }
      final zhIndex = text.indexOf('：');
      if (zhIndex >= 0 && zhIndex + 1 < text.length) {
        return text.substring(zhIndex + 1).trim();
      }
      return '监督 Agent 拒绝执行。';
    }
    if (text.startsWith('拒绝') || text.startsWith('拦截')) {
      final cleaned =
          text.replaceFirst(RegExp(r'^(拒绝|拦截)\s*[:：]?\s*'), '').trim();
      return cleaned.isEmpty ? '监督 Agent 拒绝执行。' : cleaned;
    }
    return text;
  }

  Future<String> _recordAgentMemory(
    int projectId, {
    required String family,
    required String role,
    required String content,
    String name = '',
  }) async {
    try {
      return await _agentMemoryService(family: family).add(
        isolationKey: _agentConversationIsolationKey(
          projectId,
          family: family,
        ),
        role: role,
        name: name,
        content: content,
      );
    } catch (_) {
      // 记忆写入不能阻断主制作流程；失败仍会在对话历史里保留可见消息。
      return '';
    }
  }

  Future<void> _recordAgentToolAuditMemory(
    int projectId, {
    required String family,
    required String baseRole,
    required String toolName,
    required String content,
  }) async {
    await _recordAgentMemory(
      projectId,
      family: family,
      role: '$baseRole:tool',
      content: '工具 $toolName 执行结果：$content',
    );
  }

  Future<void> _recordAgentSummaryMemory(
    int projectId, {
    required String family,
    required String role,
    required String name,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      db.execute(
        'INSERT INTO memories '
        '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          'agent_sum_${DateTime.now().microsecondsSinceEpoch}',
          name,
          trimmed,
          now,
          embeddingJson(trimmed),
          _agentConversationIsolationKey(projectId, family: family),
          '[]',
          role,
          0,
          agentMemoryTypeSummary,
        ],
      );
    } catch (_) {
      // 审计记忆不能阻断主制作流程；可见结果仍保留在任务/对话中。
    }
  }

  /// 模型经常用显式空数组表达"不指定具体 id，按默认全部执行"，
  /// 与"未传该字段"语义相同：都应回退到调用方给出的默认集合。
  List<int>? _intList(Map<String, dynamic> args, String key) {
    final raw = args[key];
    if (raw is! List || raw.isEmpty) return null;
    return raw.map((e) => (e as num).toInt()).toList();
  }

  int _agentRagLimit() {
    return agentRagLimit();
  }

  String _agentFamilyForMessage(String text) {
    final normalized = text.toLowerCase();
    const scriptKeywords = [
      '事件',
      '剧本',
      '故事骨架',
      '改编',
      '小说',
      '章节',
      'script',
      'skeleton',
      'adaptation',
    ];
    for (final keyword in scriptKeywords) {
      if (normalized.contains(keyword)) return _scriptAgentFamily;
    }
    const productionKeywords = [
      '制作',
      '制作画布',
      '导演',
      '拍摄',
      '分镜',
      '镜头',
      '资产',
      '素材',
      '首帧',
      '生图',
      '图片',
      '视频',
      '工作台',
      'storyboard',
      'production',
      'asset',
      'director',
      'shot',
      'video',
    ];
    for (final keyword in productionKeywords) {
      if (normalized.contains(keyword)) return _productionAgentFamily;
    }
    return _scriptAgentFamily;
  }

  Future<String> _runTool(
    int projectId,
    String name,
    Map<String, dynamic> args, {
    String agentFamily = _scriptAgentFamily,
    String? stage,
    List<String> activatedSkills = const [],
    Set<String> excludedMemoryIds = const {},
    Set<String> excludedRoles = const {},
    Set<String> excludedRoleSuffixes = const {},
  }) async {
    try {
      switch (name) {
        case 'deepRetrieve':
          final keyword = (args['keyword'] ??
                  args['query'] ??
                  args['question'] ??
                  args['text'] ??
                  args['prompt'] ??
                  args['q'] ??
                  '')
              .toString()
              .trim();
          if (keyword.isEmpty) return '缺少 keyword 参数。';
          final roles = _coerceStringSet(
            args['roles'] ?? args['role'] ?? args['memoryRoles'],
          );
          final requestedExcludeRoles = _coerceStringSet(
            args['excludeRoles'] ??
                args['excludeRole'] ??
                args['excludedRoles'] ??
                args['excludeMemoryRoles'] ??
                args['excludedMemoryRoles'],
          );
          final excludeRoles = {
            ...excludedRoles,
            if (requestedExcludeRoles != null) ...requestedExcludeRoles,
          };
          final requestedExcludeRoleSuffixes = _coerceStringSet(
            args['excludeRoleSuffixes'] ??
                args['excludeRoleSuffix'] ??
                args['excludedRoleSuffixes'] ??
                args['excludeMemoryRoleSuffixes'] ??
                args['excludedMemoryRoleSuffixes'],
          );
          final excludeRoleSuffixes = {
            ...excludedRoleSuffixes,
            if (requestedExcludeRoleSuffixes != null)
              ...requestedExcludeRoleSuffixes,
          };
          final types = _deepRetrieveMemoryTypes(args);
          final requestedExcludeIds = _coerceStringSet(
            args['excludeIds'] ??
                args['excludeMemoryIds'] ??
                args['excludedMemoryIds'] ??
                args['excludeId'],
          );
          final excludeIds = {
            ...excludedMemoryIds,
            if (requestedExcludeIds != null) ...requestedExcludeIds,
          };
          final records = await _agentMemoryService(
            family: agentFamily,
          ).deepRetrieve(
            isolationKey: _agentConversationIsolationKey(
              projectId,
              family: agentFamily,
            ),
            keyword: keyword,
            roles: roles,
            excludeRoles: excludeRoles,
            excludeRoleSuffixes: excludeRoleSuffixes,
            types: types,
            excludeIds: excludeIds,
            noteIsolationKey: _agentMemoryIsolationKey(projectId),
          );
          final rawLimit = args['limit'] ??
              args['topK'] ??
              args['top_k'] ??
              args['maxResults'] ??
              args['max_results'] ??
              args['max'] ??
              args['count'] ??
              args['k'];
          final limit = _coerceInt(rawLimit)?.clamp(1, 50).toInt();
          final limitedRecords =
              limit == null ? records : records.take(limit).toList();
          if (limitedRecords.isEmpty) {
            return jsonEncode({
              'found': false,
              'message': '未找到相关记忆',
            });
          }
          return jsonEncode({
            'found': true,
            'memories': [
              for (final record in limitedRecords) record.content,
            ],
            'records': [
              for (final record in limitedRecords)
                {
                  'id': record.id,
                  'type': record.type,
                  'scope': _deepRetrieveRecordScope(record),
                  'name': record.name,
                  'createTime': record.createdAt,
                  'role': record.role,
                  if (record.sourceSummaryIds.isNotEmpty)
                    'sourceSummaryIds': record.sourceSummaryIds,
                  if (record.score != null) 'score': record.score,
                  if (record.matchedTokens.isNotEmpty)
                    'matchedTokens': record.matchedTokens,
                  'content': record.content,
                },
            ],
          });
        case 'activate_skill':
          final skillName = (args['name'] ??
                  args['skill'] ??
                  args['skillName'] ??
                  args['skillId'] ??
                  args['skill_name'] ??
                  '')
              .toString()
              .trim();
          if (skillName.isEmpty) return '缺少 name 参数。';
          final skill = _activateAgentSkillForContext(
            skillName,
            stage: stage,
            projectId: projectId,
          );
          final activeNames = _activatedAgentSkillNames(activatedSkills);
          if (activeNames.contains(skill.name) ||
              activeNames.contains(skill.id)) {
            return '技能 "${skill.name}" 已激活，无需重复加载。';
          }
          return _formatActivatedAgentSkill(skill);
        case 'read_skill_file':
          var skillName = (args['name'] ??
                  args['skill'] ??
                  args['skillName'] ??
                  args['skillId'] ??
                  args['skill_name'] ??
                  '')
              .toString()
              .trim();
          final filePath = (args['filePath'] ??
                  args['path'] ??
                  args['file'] ??
                  args['filename'] ??
                  args['relativePath'] ??
                  '')
              .toString()
              .trim();
          if (skillName.isEmpty) {
            final names = _activatedAgentSkillNames(activatedSkills);
            if (names.length == 1) {
              skillName = names.single;
            } else if (names.isEmpty) {
              return '缺少 name 参数。请先调用 activate_skill，或显式传入 name。';
            } else {
              return '已激活多个技能，请传入 name 参数。';
            }
          }
          if (filePath.isEmpty) return '缺少 filePath 参数。';
          return _formatReadAgentSkillFile(
            _readAgentSkillFileForContext(
              skillName,
              filePath,
              stage: stage,
              projectId: projectId,
            ),
          );
        case 'get_novel_events':
          return _scriptAgentNovelEvents(projectId, args);
        case 'get_planData':
          return _scriptAgentPlanData(projectId, args);
        case 'get_novel_text':
          return _scriptAgentNovelText(projectId, args);
        case 'get_script_content':
          return _scriptAgentScriptContent(projectId, args);
        case 'get_flowData':
          return _productionAgentFlowData(projectId, args);
        case 'add_deriveAsset':
          return _productionAgentAddDeriveAsset(projectId, args);
        case 'del_deriveAsset':
          return _productionAgentDeleteDeriveAsset(projectId, args);
        case 'generate_deriveAsset':
          return _productionAgentGenerateDeriveAsset(projectId, args);
        case 'generate_storyboard':
          return _productionAgentGenerateStoryboard(projectId, args);
        case 'add_flowData_storyboard':
          return _productionAgentAddStoryboard(projectId, args);
        case 'run_sub_agent_storySkeleton':
          return _runScriptAgentSubAgent(
            projectId,
            args,
            stage: scriptAgentStorySkeletonStage,
            label: '故事骨架 Agent',
            xmlTag: scriptAgentStorySkeletonKey,
            workspaceKey: scriptAgentStorySkeletonKey,
            activatedSkills: activatedSkills,
          );
        case 'run_sub_agent_adaptationStrategy':
          return _runScriptAgentSubAgent(
            projectId,
            args,
            stage: scriptAgentAdaptationStrategyStage,
            label: '改编策略 Agent',
            xmlTag: scriptAgentAdaptationStrategyKey,
            workspaceKey: scriptAgentAdaptationStrategyKey,
            activatedSkills: activatedSkills,
          );
        case 'run_sub_agent_script':
          return _runScriptAgentScriptSubAgent(
            projectId,
            args,
            activatedSkills: activatedSkills,
          );
        case 'run_supervision_agent':
          return _runScriptAgentSubAgent(
            projectId,
            args,
            stage: scriptAgentSupervisionStage,
            label: '监督 Agent',
            xmlTag: '',
            workspaceKey: scriptAgentSupervisionKey,
            activatedSkills: activatedSkills,
          );
        case 'run_sub_agent_derive_assets':
          return _runProductionAgentSubAgent(
            projectId,
            args,
            stage: productionAgentDeriveAssetsStage,
            label: '衍生资产 Agent',
            activatedSkills: activatedSkills,
          );
        case 'run_sub_agent_generate_assets':
          return _runProductionAgentSubAgent(
            projectId,
            args,
            stage: productionAgentGenerateAssetsStage,
            label: '资产生图 Agent',
            activatedSkills: activatedSkills,
          );
        case 'run_sub_agent_director_plan':
          return _runProductionAgentSubAgent(
            projectId,
            args,
            stage: productionAgentDirectorPlanStage,
            label: '导演计划 Agent',
            xmlTag: productionScriptPlanKey,
            workspaceKey: productionScriptPlanKey,
            activatedSkills: activatedSkills,
          );
        case 'run_sub_agent_storyboard_gen':
          return _runProductionAgentSubAgent(
            projectId,
            args,
            stage: productionAgentStoryboardGenStage,
            label: '分镜图生成 Agent',
            activatedSkills: activatedSkills,
          );
        case 'run_sub_agent_storyboard_panel':
          return _runProductionStoryboardPanelSubAgent(
            projectId,
            args,
            activatedSkills: activatedSkills,
          );
        case 'run_sub_agent_storyboard_table':
          return _runProductionAgentSubAgent(
            projectId,
            args,
            stage: productionAgentStoryboardTableStage,
            label: '分镜表 Agent',
            xmlTag: productionStoryboardTableKey,
            workspaceKey: productionStoryboardTableKey,
            activatedSkills: activatedSkills,
          );
        case 'run_sub_agent_supervision':
          return _runProductionAgentSubAgent(
            projectId,
            args,
            stage: productionAgentSupervisionStage,
            label: '制作监督 Agent',
            workspaceKey: productionSupervisionKey,
            activatedSkills: activatedSkills,
          );
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
          final custom = db.select(
            'SELECT id,path FROM o_skillList WHERE id=? AND type=? AND COALESCE(state,1)!=0',
            [name, _customAgentSkillType],
          ).firstOrNull;
          if (custom != null) {
            return _runCustomAgentSkill(
              projectId,
              name,
              custom['path'] as String? ?? '',
              args,
            );
          }
          return '未知工具：$name';
      }
    } catch (e) {
      final ex = e is EngineException
          ? e
          : EngineException(errLlmFormat, {'message': '$e'});
      return '执行失败：${ex.errKey}';
    }
  }

  List<int>? _intListAny(Map<String, dynamic> args, List<String> keys) {
    for (final key in keys) {
      final parsed = _coerceIntList(args[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  Object? _argAny(Map<String, dynamic> args, List<String> keys) {
    for (final key in keys) {
      if (args.containsKey(key)) return args[key];
    }
    return null;
  }

  String _stringArgAny(Map<String, dynamic> args, List<String> keys) {
    final raw = _argAny(args, keys);
    if (raw == null) return '';
    return raw.toString().trim();
  }

  List<int>? _coerceIntList(Object? raw) {
    if (raw == null) return null;
    if (raw is Iterable) {
      final values = [
        for (final item in raw)
          if (_coerceInt(item) != null) _coerceInt(item)!,
      ];
      return values.isEmpty ? null : values;
    }
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return null;
      final range = RegExp(r'^(\d+)\s*(?:-|~|至)\s*(\d+)$').firstMatch(text);
      if (range != null) {
        final start = int.parse(range.group(1)!);
        final end = int.parse(range.group(2)!);
        if (start <= end) return [for (var i = start; i <= end; i++) i];
        return [for (var i = start; i >= end; i--) i];
      }
      if (text.contains(RegExp(r'[,，、\s]+'))) {
        final values = [
          for (final part in text.split(RegExp(r'[,，、\s]+')))
            if (_coerceInt(part) != null) _coerceInt(part)!,
        ];
        return values.isEmpty ? null : values;
      }
    }
    final single = _coerceInt(raw);
    return single == null ? null : [single];
  }

  int? _coerceInt(Object? raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  String _agentPromptArg(Map<String, dynamic> args) {
    const keys = [
      'prompt',
      'instruction',
      'task',
      'input',
      'request',
      'message'
    ];
    for (final key in keys) {
      final text = (args[key] ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  Set<String>? _coerceStringSet(Object? raw) {
    final values = <String>{};
    void add(Object? value) {
      if (value is! String) return;
      for (final part in value.split(',')) {
        final trimmed = part.trim();
        if (trimmed.isNotEmpty) values.add(trimmed);
      }
    }

    if (raw is List) {
      for (final item in raw) {
        add(item);
      }
    } else {
      add(raw);
    }
    return values.isEmpty ? null : values;
  }

  Set<String>? _deepRetrieveMemoryTypes(Map<String, dynamic> args) {
    final values = <String>{};
    void addRaw(Object? raw) {
      final items = _coerceStringSet(raw);
      if (items != null) values.addAll(items);
    }

    void addScope(Object? raw) {
      final scopes = _coerceStringSet(raw);
      if (scopes == null) return;
      for (final scope in scopes) {
        switch (scope.trim().toLowerCase()) {
          case 'conversation':
          case 'conversations':
          case 'chat':
          case 'history':
            values
              ..add(agentMemoryTypeMessage)
              ..add(agentMemoryTypeSummary);
            break;
          case 'summary':
          case 'summaries':
            values.add(agentMemoryTypeSummary);
            break;
          case 'long_term':
          case 'long-term':
          case 'longterm':
          case 'note':
          case 'notes':
          case 'project':
            values.add(agentMemoryTypeNote);
            break;
          case 'all':
            values
              ..add(agentMemoryTypeMessage)
              ..add(agentMemoryTypeSummary)
              ..add(agentMemoryTypeNote);
            break;
          default:
            values.add(scope);
        }
      }
    }

    addRaw(args['types'] ??
        args['type'] ??
        args['memoryTypes'] ??
        args['memoryType']);
    addScope(
      args['scopes'] ??
          args['scope'] ??
          args['memoryScopes'] ??
          args['memoryScope'],
    );
    return values.isEmpty ? null : values;
  }

  String _deepRetrieveRecordScope(AgentMemoryEntry record) {
    switch (record.type) {
      case agentMemoryTypeNote:
        return 'long_term';
      case agentMemoryTypeSummary:
        return 'summary';
      default:
        return 'conversation';
    }
  }

  Map<String, dynamic> _scriptAgentWorkspace(int projectId) {
    final row = db.select(
      'SELECT data FROM o_agentWorkData '
      'WHERE projectId=? AND episodesId IS NULL AND key=?',
      [projectId, scriptAgentWorkspaceKey],
    ).firstOrNull;
    if (row == null) {
      final data = normalizeScriptAgentWorkspace(null);
      _saveScriptAgentWorkspace(projectId, data);
      return data;
    }
    try {
      return normalizeScriptAgentWorkspace(
        jsonDecode(row['data'] as String? ?? '{}'),
      );
    } catch (_) {
      return normalizeScriptAgentWorkspace(null);
    }
  }

  void _saveScriptAgentWorkspace(
    int projectId,
    Map<String, dynamic> data,
  ) {
    final json = encodeScriptAgentWorkspace(data);
    final exists = db.select(
      'SELECT id FROM o_agentWorkData '
      'WHERE projectId=? AND episodesId IS NULL AND key=?',
      [projectId, scriptAgentWorkspaceKey],
    ).firstOrNull;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (exists == null) {
      db.execute(
        'INSERT INTO o_agentWorkData (projectId,key,data,createTime,updateTime) '
        'VALUES (?,?,?,?,?)',
        [projectId, scriptAgentWorkspaceKey, json, now, now],
      );
    } else {
      db.execute(
        'UPDATE o_agentWorkData SET data=?, updateTime=? WHERE id=?',
        [json, now, exists['id']],
      );
    }
  }

  String _scriptAgentNovelEvents(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final novelIds = _intListAny(args, const ['novelIds', 'novel_ids']);
    final chapterIndexes = _intListAny(args, const [
      'chapterIndexs',
      'chapterIndexes',
      'chapterIndex',
      'chapterNo',
      'chapterNos',
      'chapter_index',
      'chapter_indexes',
      'chapter_no',
      'chapter_nos',
      'ids',
    ]);
    final chapters = novels(projectId, limit: 100000).data.where((chapter) {
      if (novelIds != null) return novelIds.contains(chapter.id);
      if (chapterIndexes != null) {
        return chapterIndexes.contains(chapter.chapterIndex);
      }
      return true;
    }).toList();
    if (chapters.isEmpty) return '无数据';
    return chapters
        .map((chapter) =>
            '第${chapter.chapterIndex}章，标题:${chapter.chapter ?? ''}，'
            '事件:${(chapter.event ?? '').trim().isEmpty ? '未生成' : chapter.event}')
        .join('\n');
  }

  String _scriptAgentPlanData(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final key = _normalizeScriptAgentPlanDataKey(
      _stringArgAny(args, const [
        'key',
        'name',
        'section',
        'dataKey',
        'flowKey',
        'workspaceKey',
        'data_key',
        'flow_key',
        'workspace_key',
      ]),
    );
    final data = _scriptAgentWorkspace(projectId);
    if (key == 'script') return _scriptAgentScriptContent(projectId, args);
    if (key.isNotEmpty) {
      final value = '${data[key] ?? ''}'.trim();
      return value.isEmpty ? '无数据' : value;
    }
    return jsonEncode({
      ...data,
      'script': [
        for (final script in scripts(projectId))
          {
            'id': script.id,
            'name': script.name ?? '',
            'content': script.content ?? '',
          },
      ],
    });
  }

  String _normalizeScriptAgentPlanDataKey(String key) {
    switch (key.trim()) {
      case 'storySkeleton':
      case 'story_skeleton':
      case 'story-skeleton':
        return scriptAgentStorySkeletonKey;
      case 'adaptationStrategy':
      case 'adaptation_strategy':
      case 'adaptation-strategy':
        return scriptAgentAdaptationStrategyKey;
      case 'script':
      case 'scripts':
      case 'scriptContent':
      case 'script_content':
      case 'script-content':
        return 'script';
      default:
        return key.trim();
    }
  }

  String _scriptAgentNovelText(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final novelIds = _intListAny(args, const ['novelIds', 'novel_ids']);
    final chapterIndexes = _intListAny(args, const [
      'chapterIndex',
      'chapterIndexs',
      'chapterIndexes',
      'chapterNo',
      'chapterNos',
      'chapter_index',
      'chapter_indexes',
      'chapter_no',
      'chapter_nos',
      'ids',
    ]);
    final chapters = novels(projectId, limit: 100000).data.where((chapter) {
      if (novelIds != null) return novelIds.contains(chapter.id);
      if (chapterIndexes != null) {
        return chapterIndexes.contains(chapter.chapterIndex);
      }
      return true;
    }).toList();
    if (chapters.isEmpty) return '无数据';
    return chapters
        .map((chapter) => '第${chapter.chapterIndex}章 ${chapter.chapter ?? ''}\n'
            '${chapter.chapterData ?? ''}')
        .join('\n\n---\n\n');
  }

  String _scriptAgentScriptContent(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final ids = _intListAny(args, const [
      'ids',
      'scriptIds',
      'episodeIds',
      'episodesIds',
      'script_id',
      'episode_id',
      'episodes_id',
      'script_ids',
      'episode_ids',
      'episodes_ids',
    ]);
    final rows = scripts(projectId).where((script) {
      if (ids == null) return true;
      return ids.contains(script.id);
    }).toList();
    if (rows.isEmpty) return '无数据';
    return rows
        .map((script) =>
            '<scriptItem name="${_escapeXmlAttr(script.name ?? '')}">'
            '${_escapeXmlText(script.content ?? '')}</scriptItem>')
        .join('\n');
  }

  Future<String> _runScriptAgentSubAgent(
    int projectId,
    Map<String, dynamic> args, {
    required String stage,
    required String label,
    required String xmlTag,
    required String workspaceKey,
    List<String> activatedSkills = const [],
  }) async {
    final output = await _runScriptAgentText(
      projectId,
      args,
      stage: stage,
      activatedSkills: activatedSkills,
    );
    var content = xmlTag.isEmpty ? '' : extractXmlTagText(output, xmlTag);
    if (content.isEmpty) content = stripXmlTags(output).trim();
    if (content.isEmpty) return '$label 未返回可写入内容。';
    final data = _scriptAgentWorkspace(projectId);
    data[workspaceKey] = content;
    _saveScriptAgentWorkspace(projectId, data);
    return '$label 已写入工作区。';
  }

  Future<String> _runScriptAgentScriptSubAgent(
    int projectId,
    Map<String, dynamic> args, {
    List<String> activatedSkills = const [],
  }) async {
    final output = await _runScriptAgentText(
      projectId,
      args,
      stage: scriptAgentScriptStage,
      activatedSkills: activatedSkills,
    );
    final items = parseScriptAgentScriptItems(output);
    if (items.isEmpty) return '剧本 Agent 未输出 scriptItem。';
    for (final item in items) {
      final exists = db.select(
        'SELECT id FROM o_script WHERE projectId=? AND name=?',
        [projectId, item.name],
      ).firstOrNull;
      if (exists == null) {
        addScript(projectId: projectId, name: item.name, content: item.content);
      } else {
        updateScript(exists['id'] as int, content: item.content);
      }
    }
    return '剧本 Agent 已写入 ${items.length} 个剧本。';
  }

  Future<String> _runScriptAgentText(
    int projectId,
    Map<String, dynamic> args, {
    required String stage,
    List<String> activatedSkills = const [],
  }) async {
    final prompt = _agentPromptArg(args);
    final history = <Map<String, String>>[
      {'role': 'assistant', 'content': _scriptAgentProjectInfo(projectId)},
      {
        'role': 'user',
        'content': prompt.isEmpty ? '请继续执行当前任务。' : prompt,
      },
    ];
    for (var turn = 0; turn < _maxAutoTurns; turn++) {
      final memoryService = _agentMemoryService(family: _scriptAgentFamily);
      final activeSkillContexts = _mergeActivatedAgentSkillContexts(
        activatedSkills,
        _activatedAgentSkillContextsFromHistory(history),
      );
      final memoryContext = await memoryService.get(
        isolationKey: _agentConversationIsolationKey(
          projectId,
          family: _scriptAgentFamily,
        ),
        query: prompt,
        excludeRoles: _agentToolAuditRoles,
        excludeRoleSuffixes: _agentToolAuditRoleSuffixes,
      );
      final system = _agentSystemPrompt(
        await searchAgentMemories(projectId, prompt, limit: _agentRagLimit()),
        context: memoryContext,
        base: _scriptAgentSubAgentSystem(stage),
        stage: stage,
        projectId: projectId,
        activatedSkills: activeSkillContexts,
        availableSkills: _markdownSkillsForStage(stage, projectId: projectId),
      );
      final result = await gateway.generateAgentTurn(
        system,
        history,
        scriptAgentExecutionTools(
            _agentToolsForStage(stage, projectId: projectId)),
        stage: stage,
      );
      if (!result.isToolCall) {
        final text = result.text ?? '';
        await _recordAgentMemory(
          projectId,
          family: _scriptAgentFamily,
          role: _scriptAgentSubAgentMemoryRole(stage),
          name: _scriptAgentSubAgentMemoryName(stage),
          content: stripXmlTags(text).trim(),
        );
        return text;
      }
      final toolName = result.toolName ?? '';
      if (toolName.startsWith('run_sub_agent_') ||
          toolName == 'run_supervision_agent') {
        return '子 Agent 不支持嵌套调用：$toolName';
      }
      final summary = await _runTool(
        projectId,
        toolName,
        result.toolArgs ?? const {},
        agentFamily: _scriptAgentFamily,
        stage: stage,
        activatedSkills: activeSkillContexts,
        excludedMemoryIds: _agentMemoryContextIds(memoryContext),
        excludedRoles: _agentToolAuditRoles,
        excludedRoleSuffixes: _agentToolAuditRoleSuffixes,
      );
      await _recordAgentToolAuditMemory(
        projectId,
        family: _scriptAgentFamily,
        baseRole: _scriptAgentSubAgentMemoryRole(stage),
        toolName: toolName,
        content: summary,
      );
      history.add({
        'role': 'assistant',
        'content': '（工具 $toolName 执行结果：$summary）',
      });
    }
    return '';
  }

  String _agentDecisionProjectInfo(int projectId, String agentFamily) {
    if (agentFamily == _productionAgentFamily) {
      return _productionAgentDecisionProjectInfo(projectId);
    }
    return _scriptAgentProjectInfo(projectId);
  }

  String _removeAllXmlTags(String text) {
    var cleaned = text.replaceAll(
      RegExp(r'<([a-zA-Z][\w-]*)(\s+[^>]*)?>[\s\S]*?</\1>'),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'<([a-zA-Z][\w-]*)(\s+[^>]*)?/>'),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'</?[a-zA-Z][\w-]*(\s+[^>]*)?>'),
      '',
    );
    return cleaned.trim();
  }

  String _scriptAgentProjectInfo(int projectId) {
    final project = db
        .select('SELECT * FROM o_project WHERE id=?', [projectId]).firstOrNull;
    final chapterCount = novels(projectId, limit: 1).total;
    return [
      '## 项目信息',
      '小说名称：${project?['name'] ?? '未知'}',
      '小说类型：${project?['type'] ?? '未知'}',
      '小说简介：${project?['intro'] ?? '无'}',
      '目标改编影视视觉手册|画风：${project?['artStyle'] ?? '无'}',
      '目标改编视频画幅：${project?['videoRatio'] ?? '16:9'}',
      '章节数量：$chapterCount章',
    ].join('\n');
  }

  String _productionAgentDecisionProjectInfo(int projectId) {
    final project = db.select(
      'SELECT imageModel,videoModel,mode FROM o_project WHERE id=?',
      [projectId],
    ).firstOrNull;
    return [
      '项目使用的模型如下：',
      '图像模型：${_modelNameWithoutProvider(project?['imageModel'])}',
      '视频模型：${_modelNameWithoutProvider(project?['videoModel'])}',
      '多参：${_projectModeIsMultiParameter(project?['mode']) ? '是' : '否'}',
    ].join('\n');
  }

  String _modelNameWithoutProvider(Object? raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return '未配置';
    final separator = text.indexOf(':');
    if (separator < 0 || separator == text.length - 1) return text;
    return text.substring(separator + 1);
  }

  bool _projectModeIsMultiParameter(Object? raw) {
    if (raw is List) return true;
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return false;
    try {
      return jsonDecode(text) is List;
    } catch (_) {
      return false;
    }
  }

  String _scriptAgentSubAgentSystem(String stage) {
    switch (stage) {
      case scriptAgentStorySkeletonStage:
        return '你是短剧改编项目的故事骨架搭建 Agent。'
            '可以读取工作区和章节事件，最终必须输出完整 <storySkeleton>故事骨架内容</storySkeleton>。';
      case scriptAgentAdaptationStrategyStage:
        return '你是短剧改编项目的改编策略制定 Agent。'
            '可以读取工作区、故事骨架和章节事件，最终必须输出完整 '
            '<adaptationStrategy>改编策略内容</adaptationStrategy>。';
      case scriptAgentScriptStage:
        return '你是短剧改编项目的剧本编写 Agent。'
            '可以读取工作区、事件、原文和已有剧本。最终必须只输出一个或多个 '
            '<scriptItem name="剧本名称">剧本内容</scriptItem>。';
      case scriptAgentSupervisionStage:
        return '你是短剧改编项目的监督层 Agent。'
            '请独立审核工作区或剧本产物，返回简短、可执行的审核结论。';
      default:
        return '你是短剧改编项目的执行层 Agent。';
    }
  }

  String _scriptAgentSubAgentMemoryRole(String stage) {
    switch (stage) {
      case scriptAgentStorySkeletonStage:
        return 'assistant:execution:storySkeleton';
      case scriptAgentAdaptationStrategyStage:
        return 'assistant:execution:adaptationStrategy';
      case scriptAgentScriptStage:
        return 'assistant:execution:script';
      case scriptAgentSupervisionStage:
        return 'assistant:supervision';
      default:
        return 'assistant:execution';
    }
  }

  String _scriptAgentSubAgentMemoryName(String stage) {
    if (stage == scriptAgentSupervisionStage) return '编辑';
    return '编剧';
  }

  String _escapeXmlText(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  String _escapeXmlAttr(String value) =>
      _escapeXmlText(value).replaceAll('"', '&quot;').replaceAll("'", '&apos;');

  int? _productionScriptId(int projectId, Map<String, dynamic> args) {
    final direct = _coerceInt(args['scriptId'] ??
        args['episodeId'] ??
        args['episodesId'] ??
        args['script_id'] ??
        args['episode_id'] ??
        args['episodes_id']);
    if (direct != null) return direct;
    final fromList = _intListAny(args, const [
      'scriptIds',
      'episodeIds',
      'script_ids',
      'episode_ids',
    ]);
    if (fromList != null && fromList.isNotEmpty) return fromList.first;
    final rows = scripts(projectId);
    return rows.isEmpty ? null : rows.first.id;
  }

  Map<String, dynamic> _productionAgentWorkspace(
    int projectId,
    int scriptId,
  ) {
    final row = db.select(
      'SELECT data FROM o_agentWorkData '
      'WHERE projectId=? AND episodesId=? AND key=?',
      [projectId, scriptId, productionAgentWorkspaceKey],
    ).firstOrNull;
    final data = row == null
        ? normalizeProductionAgentWorkspace(null)
        : (() {
            try {
              return normalizeProductionAgentWorkspace(
                jsonDecode(row['data'] as String? ?? '{}'),
              );
            } catch (_) {
              return normalizeProductionAgentWorkspace(null);
            }
          })();
    data['script'] = db.select('SELECT content FROM o_script WHERE id=?',
            [scriptId]).firstOrNull?['content'] as String? ??
        '';
    data['assets'] = _productionAssetsData(projectId, scriptId);
    data['storyboard'] = _productionStoryboardData(scriptId);
    return data;
  }

  void _saveProductionAgentWorkspace(
    int projectId,
    int scriptId,
    Map<String, dynamic> data,
  ) {
    final json = encodeProductionAgentWorkspace(data);
    final exists = db.select(
      'SELECT id FROM o_agentWorkData '
      'WHERE projectId=? AND episodesId=? AND key=?',
      [projectId, scriptId, productionAgentWorkspaceKey],
    ).firstOrNull;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (exists == null) {
      db.execute(
        'INSERT INTO o_agentWorkData '
        '(projectId,episodesId,key,data,createTime,updateTime) '
        'VALUES (?,?,?,?,?,?)',
        [projectId, scriptId, productionAgentWorkspaceKey, json, now, now],
      );
    } else {
      db.execute(
        'UPDATE o_agentWorkData SET data=?, updateTime=? WHERE id=?',
        [json, now, exists['id']],
      );
    }
  }

  List<Map<String, dynamic>> _productionAssetsData(
    int projectId,
    int scriptId,
  ) {
    final linkedIds = db
        .select(
            'SELECT assetId FROM o_scriptAssets WHERE scriptId=?', [scriptId])
        .map((row) => row['assetId'] as int)
        .toList();
    if (linkedIds.isEmpty) return const [];
    final all = assetsByIds(linkedIds);
    final parentIds =
        all.where((a) => a.assetsId == null).map((a) => a.id).toList();
    if (parentIds.isEmpty) {
      return [
        for (final asset in all)
          {
            'id': asset.id,
            'name': asset.name ?? '',
            'type': asset.type,
            'prompt': asset.prompt ?? '',
            'desc': asset.describe ?? '',
            'derive': const [],
          },
      ];
    }
    final children = db.select(
      'SELECT * FROM o_assets WHERE projectId=? AND assetsId IN '
      '(${List.filled(parentIds.length, '?').join(',')}) ORDER BY id',
      [projectId, ...parentIds],
    );
    final childrenByParent = <int, List<Map<String, dynamic>>>{};
    for (final child in children) {
      childrenByParent.putIfAbsent(child['assetsId'] as int, () => []).add({
        'id': child['id'],
        'assetsId': child['assetsId'],
        'name': child['name'] ?? '',
        'type': child['type'] ?? '',
        'prompt': child['prompt'] ?? '',
        'desc': child['describe'] ?? '',
      });
    }
    return [
      for (final asset in all.where((a) => a.assetsId == null))
        {
          'id': asset.id,
          'name': asset.name ?? '',
          'type': asset.type,
          'prompt': asset.prompt ?? '',
          'desc': asset.describe ?? '',
          'derive': childrenByParent[asset.id] ?? const [],
        },
    ];
  }

  List<Map<String, dynamic>> _productionStoryboardData(int scriptId) => [
        for (final row in storyboards(scriptId))
          {
            'id': row.id,
            'index': row.index,
            'duration': row.duration ?? '',
            'prompt': row.prompt ?? '',
            'associateAssetsIds': row.assetIds,
            'src': row.filePath,
            'state': row.state,
            'videoDesc': row.videoDesc ?? '',
            'shouldGenerateImage': row.shouldGenerateImage,
            'reason': row.reason ?? '',
            'flowId': row.flowId,
          },
      ];

  String _productionAgentFlowData(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final scriptId = _productionScriptId(projectId, args);
    if (scriptId == null) return '缺少 scriptId 参数。';
    final key = _stringArgAny(args, const [
      'key',
      'dataKey',
      'data_key',
      'flowKey',
      'flow_key',
      'section',
      'resource',
    ]);
    final data = _productionAgentWorkspace(projectId, scriptId);
    if (key.isEmpty) return jsonEncode(data);
    final value = data[key];
    if (value == null) return '无数据';
    return value is String
        ? (value.trim().isEmpty ? '无数据' : value)
        : jsonEncode(value);
  }

  String _productionAgentAddDeriveAsset(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final parentId = _coerceInt(_argAny(args, const [
      'assetsId',
      'assetId',
      'parentAssetId',
      'parentAssetsId',
      'asset_id',
      'assets_id',
      'parent_asset_id',
      'parent_assets_id',
    ]));
    if (parentId == null) return '缺少 assetsId 参数。';
    final name = _stringArgAny(args, const [
      'name',
      'assetName',
      'deriveAssetName',
      'childAssetName',
      'asset_name',
      'derive_asset_name',
      'child_asset_name',
    ]);
    if (name.isEmpty) return '缺少 name 参数。';
    final desc = _stringArgAny(args, const [
      'desc',
      'describe',
      'description',
      'assetDesc',
      'assetDescription',
      'asset_desc',
      'asset_description',
    ]);
    final id = _coerceInt(_argAny(args, const [
      'id',
      'deriveAssetId',
      'childAssetId',
      'derive_asset_id',
      'child_asset_id',
    ]));
    final parent = db
        .select('SELECT type FROM o_assets WHERE id=?', [parentId]).firstOrNull;
    if (parent == null) return '关联的资产不存在。';
    final scriptId = _productionScriptId(projectId, args);
    if (id == null) {
      final childId = addAsset(
        projectId: projectId,
        type: parent['type'] as String? ?? 'role',
        name: name,
        describe: desc,
        parentAssetsId: parentId,
      );
      if (scriptId != null) _linkScriptAsset(scriptId, childId);
      return '已新增衍生资产，ID: $childId。';
    }
    updateAsset(id, name: name, describe: desc);
    if (scriptId != null) _linkScriptAsset(scriptId, id);
    return '已更新衍生资产，ID: $id。';
  }

  void _linkScriptAsset(int scriptId, int assetId) {
    final exists = db.select(
      'SELECT assetId FROM o_scriptAssets WHERE scriptId=? AND assetId=?',
      [scriptId, assetId],
    ).firstOrNull;
    if (exists != null) return;
    db.execute(
      'INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
      [scriptId, assetId],
    );
  }

  String _productionAgentDeleteDeriveAsset(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final id = _coerceInt(_argAny(args, const [
      'id',
      'assetId',
      'deriveAssetId',
      'childAssetId',
      'asset_id',
      'derive_asset_id',
      'child_asset_id',
    ]));
    if (id == null) return '缺少 id 参数。';
    deleteAssets([id]);
    return '已删除衍生资产，ID: $id。';
  }

  String _productionAgentGenerateDeriveAsset(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final ids = _intListAny(args, const [
      'ids',
      'assetIds',
      'assetsIds',
      'deriveAssetIds',
      'deriveAssetsIds',
      'asset_ids',
      'assets_ids',
      'derive_asset_ids',
      'derive_assets_ids',
    ]);
    if (ids == null || ids.isEmpty) return '缺少 ids 参数。';
    final items = <({int assetsId, String? refImageBase64})>[
      for (final id in ids) (assetsId: id, refImageBase64: null),
    ];
    final taskId = generateAssetImages(projectId, items, concurrentCount: 1);
    if (taskId == 0) return '没有可生成的衍生资产。';
    return '已提交资产图片生成任务（任务 #$taskId），涉及 ${ids.length} 个资产。';
  }

  String _productionAgentGenerateStoryboard(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final ids = _intListAny(args, const [
      'ids',
      'storyboardIds',
      'shotIds',
      'panelIds',
      'storyboard_ids',
      'shot_ids',
      'panel_ids',
    ]);
    if (ids == null || ids.isEmpty) return '缺少 ids 参数。';
    final taskId = batchGenerateStoryboardImages(
      projectId,
      ids,
      compulsory: true,
      concurrentCount: 1,
    );
    if (taskId == 0) return '没有可生成的分镜。';
    return '已提交分镜首帧图生成任务（任务 #$taskId），涉及 ${ids.length} 个分镜。';
  }

  String _productionAgentAddStoryboard(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final scriptId = _productionScriptId(projectId, args);
    if (scriptId == null) return '缺少 scriptId 参数。';
    final shouldGenerateImage = _argAny(args, const [
      'shouldGenerateImage',
      'generateImage',
      'should_generate_image',
      'generate_image',
    ]);
    final item = ProductionStoryboardItem(
      videoDesc: _stringArgAny(args, const [
        'videoDesc',
        'videoDescription',
        'description',
        'shotDesc',
        'video_desc',
        'video_description',
        'shot_desc',
      ]),
      prompt: _stringArgAny(args, const [
        'prompt',
        'imagePrompt',
        'image_prompt',
      ]),
      track: _stringArgAny(args, const ['track']),
      duration: _stringArgAny(args, const [
        'duration',
        'durationSec',
        'duration_sec',
      ]),
      associateAssetIds: _intListAny(args, const [
            'associateAssetsIds',
            'assetIds',
            'asset_ids',
            'associate_asset_ids',
            'associatedAssetIds',
            'associated_asset_ids',
          ]) ??
          const [],
      shouldGenerateImage: _argBool(
        shouldGenerateImage,
        defaultValue: true,
      ),
    );
    if (item.videoDesc.trim().isEmpty) return '缺少 videoDesc 参数。';
    final id = _addProductionStoryboardItem(projectId, scriptId, item);
    return '已新增分镜，ID: $id。';
  }

  int _addProductionStoryboardItem(
    int projectId,
    int scriptId,
    ProductionStoryboardItem item,
  ) {
    final id = addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: item.prompt,
      videoDesc: item.videoDesc,
      duration: item.duration,
      assetIds: item.associateAssetIds,
    );
    db.execute(
      'UPDATE o_storyboard SET shouldGenerateImage=?, track=? WHERE id=?',
      [item.shouldGenerateImage ? 1 : 0, item.track, id],
    );
    return id;
  }

  Future<String> _runProductionAgentSubAgent(
    int projectId,
    Map<String, dynamic> args, {
    required String stage,
    required String label,
    String? xmlTag,
    String? workspaceKey,
    List<String> activatedSkills = const [],
  }) async {
    final scriptId = _productionScriptId(projectId, args);
    if (scriptId == null) return '缺少 scriptId 参数。';
    final output = await _runProductionAgentText(
      projectId,
      scriptId,
      args,
      stage: stage,
      activatedSkills: activatedSkills,
    );
    if (workspaceKey == null) {
      return '$label 执行完成。';
    }
    var content = xmlTag == null || xmlTag.isEmpty
        ? stripXmlTags(output).trim()
        : extractXmlTagText(output, xmlTag);
    if (content.isEmpty) content = stripXmlTags(output).trim();
    if (content.isEmpty) return '$label 未返回可写入内容。';
    final data = _productionAgentWorkspace(projectId, scriptId);
    data[workspaceKey] = content;
    _saveProductionAgentWorkspace(projectId, scriptId, data);
    if (workspaceKey == productionStoryboardTableKey) {
      saveStoryboardTable(projectId, scriptId, content);
    }
    return '$label 已写入工作区。';
  }

  Future<String> _runProductionStoryboardPanelSubAgent(
    int projectId,
    Map<String, dynamic> args, {
    List<String> activatedSkills = const [],
  }) async {
    final scriptId = _productionScriptId(projectId, args);
    if (scriptId == null) return '缺少 scriptId 参数。';
    final output = await _runProductionAgentText(
      projectId,
      scriptId,
      args,
      stage: productionAgentStoryboardPanelStage,
      activatedSkills: activatedSkills,
    );
    final items = parseProductionStoryboardItems(output);
    if (items.isEmpty) return '分镜面板 Agent 未输出 storyboardItem。';
    for (final item in items) {
      _addProductionStoryboardItem(projectId, scriptId, item);
    }
    final data = _productionAgentWorkspace(projectId, scriptId);
    _saveProductionAgentWorkspace(projectId, scriptId, data);
    return '分镜面板 Agent 已写入 ${items.length} 个分镜。';
  }

  Future<String> _runProductionAgentText(
    int projectId,
    int scriptId,
    Map<String, dynamic> args, {
    required String stage,
    List<String> activatedSkills = const [],
  }) async {
    final prompt = _agentPromptArg(args);
    final history = <Map<String, String>>[
      {
        'role': 'assistant',
        'content': _productionAgentProjectInfo(projectId, scriptId)
      },
      {
        'role': 'user',
        'content': prompt.isEmpty ? '请继续执行当前制作任务。' : prompt,
      },
    ];
    _ensureProjectProductionMarkdownSkills(projectId);
    for (var turn = 0; turn < _maxAutoTurns; turn++) {
      final memoryService = _agentMemoryService(family: _productionAgentFamily);
      final activeSkillContexts = _mergeActivatedAgentSkillContexts(
        activatedSkills,
        _activatedAgentSkillContextsFromHistory(history),
      );
      final memoryContext = await memoryService.get(
        isolationKey: _agentConversationIsolationKey(
          projectId,
          family: _productionAgentFamily,
        ),
        query: prompt,
        excludeRoles: _agentToolAuditRoles,
        excludeRoleSuffixes: _agentToolAuditRoleSuffixes,
      );
      final system = _agentSystemPrompt(
        await searchAgentMemories(projectId, prompt, limit: _agentRagLimit()),
        context: memoryContext,
        base: _productionAgentSubAgentSystem(stage),
        stage: stage,
        projectId: projectId,
        activatedSkills: activeSkillContexts,
        availableSkills: _markdownSkillsForStage(stage, projectId: projectId),
      );
      final result = await gateway.generateAgentTurn(
        system,
        history,
        productionAgentExecutionTools(
          _agentToolsForStage(stage, projectId: projectId),
        ),
        stage: stage,
      );
      if (!result.isToolCall) {
        final text = result.text ?? '';
        await _recordAgentMemory(
          projectId,
          family: _productionAgentFamily,
          role: _productionAgentSubAgentMemoryRole(stage),
          name: _productionAgentSubAgentMemoryName(stage),
          content: stripXmlTags(text).trim(),
        );
        return text;
      }
      final toolName = result.toolName ?? '';
      if (toolName.startsWith('run_sub_agent_')) {
        return '子 Agent 不支持嵌套调用：$toolName';
      }
      final toolArgs = Map<String, dynamic>.from(result.toolArgs ?? const {});
      toolArgs.putIfAbsent('scriptId', () => scriptId);
      final summary = await _runTool(
        projectId,
        toolName,
        toolArgs,
        agentFamily: _productionAgentFamily,
        stage: stage,
        activatedSkills: activeSkillContexts,
        excludedMemoryIds: _agentMemoryContextIds(memoryContext),
        excludedRoles: _agentToolAuditRoles,
        excludedRoleSuffixes: _agentToolAuditRoleSuffixes,
      );
      await _recordAgentToolAuditMemory(
        projectId,
        family: _productionAgentFamily,
        baseRole: _productionAgentSubAgentMemoryRole(stage),
        toolName: toolName,
        content: summary,
      );
      history.add({
        'role': 'assistant',
        'content': '（工具 $toolName 执行结果：$summary）',
      });
    }
    return '';
  }

  String _productionAgentProjectInfo(int projectId, int scriptId) {
    final project = db
        .select('SELECT * FROM o_project WHERE id=?', [projectId]).firstOrNull;
    final script = db.select(
        'SELECT name,content FROM o_script WHERE id=?', [scriptId]).firstOrNull;
    return [
      '## 项目信息',
      '项目名称：${project?['name'] ?? '未知'}',
      '图像模型：${project?['imageModel'] ?? '未配置'}',
      '视频模型：${project?['videoModel'] ?? '未配置'}',
      '多参：${project?['mode'] ?? '未知'}',
      '画幅：${project?['videoRatio'] ?? '16:9'}',
      '当前剧本：${script?['name'] ?? scriptId}',
      '剧本内容：${script?['content'] ?? ''}',
    ].join('\n');
  }

  String _productionAgentSubAgentSystem(String stage) {
    switch (stage) {
      case productionAgentDeriveAssetsStage:
        return '你是短剧制作执行导演，负责分析并写入衍生资产。'
            '需要写资产时调用 add_deriveAsset。';
      case productionAgentGenerateAssetsStage:
        return '你是短剧制作执行导演，负责提交衍生资产图片生成任务。'
            '需要生成图片时调用 generate_deriveAsset。';
      case productionAgentDirectorPlanStage:
        return '你是短剧制作执行导演，负责导演规划。'
            '最终必须输出完整 <scriptPlan>导演规划内容</scriptPlan>。';
      case productionAgentStoryboardGenStage:
        return '你是短剧制作执行导演，负责提交分镜首帧图生成任务。'
            '需要生成分镜图片时调用 generate_storyboard。';
      case productionAgentStoryboardPanelStage:
        return '你是短剧制作执行导演，负责分镜面板写入。'
            '最终必须输出一个或多个 <storyboardItem videoDesc="视频描述" '
            'prompt="图片提示词" track="分组" shouldGenerateImage="true/false" '
            'duration="视频推荐时间" associateAssetsIds="[资产ID]"></storyboardItem>。';
      case productionAgentStoryboardTableStage:
        return '你是短剧制作执行导演，负责分镜表构建。'
            '最终必须输出完整 <storyboardTable>分镜表内容</storyboardTable>。';
      case productionAgentSupervisionStage:
        return '你是短剧制作监督层 Agent。请独立审核制作产物，返回简短、可执行的审核结论。';
      default:
        return '你是短剧制作执行层 Agent。';
    }
  }

  String _productionAgentSubAgentMemoryRole(String stage) {
    if (stage == productionAgentSupervisionStage) {
      return 'assistant:supervision';
    }
    switch (stage) {
      case productionAgentDeriveAssetsStage:
        return 'assistant:execution:deriveAssets';
      case productionAgentGenerateAssetsStage:
        return 'assistant:execution:generateAssets';
      case productionAgentDirectorPlanStage:
        return 'assistant:execution:directorPlan';
      case productionAgentStoryboardGenStage:
        return 'assistant:execution:storyboardGen';
      case productionAgentStoryboardPanelStage:
        return 'assistant:execution:storyboardPanel';
      case productionAgentStoryboardTableStage:
        return 'assistant:execution:storyboardTable';
      default:
        return 'assistant:execution';
    }
  }

  String _productionAgentSubAgentMemoryName(String stage) {
    if (stage == productionAgentSupervisionStage) return '监制';
    return '执行导演';
  }

  void _ensureProjectProductionMarkdownSkills(int projectId) {
    final project = db.select(
      'SELECT artStyle,directorManual FROM o_project WHERE id=?',
      [projectId],
    ).firstOrNull;
    seedProjectProductionMarkdownAgentSkillsInDb(
      db,
      p.join(p.dirname(media.rootDir), 'skills'),
      projectId: projectId,
      artStyle: project?['artStyle'] as String?,
      directorManual: project?['directorManual'] as String?,
    );
  }

  bool _argBool(Object? value, {required bool defaultValue}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty) return defaultValue;
    if (const {'true', '1', 'yes', 'y', '是'}.contains(text)) return true;
    if (const {'false', '0', 'no', 'n', '否'}.contains(text)) return false;
    return defaultValue;
  }

  String _runCustomAgentSkill(
    int projectId,
    String name,
    String script,
    Map<String, dynamic> args,
  ) {
    final result = _evaluateCustomJsReturn(script, projectId, args);
    return result.isEmpty ? '自定义技能 $name 执行完成。' : result;
  }

  String _evaluateCustomJsReturn(
    String script,
    int projectId,
    Map<String, dynamic> args,
  ) {
    return _CustomAgentSkillRuntime(projectId: projectId, args: args)
        .run(script);
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
