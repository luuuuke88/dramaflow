// Agent 体系正在按 ToonFlow 的 scriptAgent / productionAgent 分层形态推进。
// 当前文件保留旧 UI/API 入口，并逐步把 stage registry、记忆、技能和 orchestrator
// 拆到独立纯 Dart 模块。所有会生成媒体或改业务表的动作仍走现有 engine API 与 o_tasks。
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
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
import 'manuals.dart';
import 'novel.dart';
import 'providers/gateway.dart' show ImageUnderstandingGateway;
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
const _maxProductionSubAgentRetries = 2;
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

class _AgentMemoryQueryRequest {
  final String query;
  final Map<String, dynamic> args;
  final int? limit;
  final int priority;
  final int queryPlanIndex;
  final String? reason;
  final bool fallbackWhenPreviousEmpty;
  final String? queryGroup;

  const _AgentMemoryQueryRequest({
    required this.query,
    required this.args,
    required this.queryPlanIndex,
    this.limit,
    this.priority = 0,
    this.reason,
    this.fallbackWhenPreviousEmpty = false,
    this.queryGroup,
  });
}

class _AgentMemoryQueryMatch {
  final String query;
  final int queryPlanIndex;
  final int priority;
  final String? reason;
  final String? group;

  const _AgentMemoryQueryMatch({
    required this.query,
    required this.queryPlanIndex,
    required this.priority,
    this.reason,
    this.group,
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
  final String? relevanceReason;
  final int? score;
  final List<String> matchedTokens;
  const AgentMemoryRecord({
    required this.id,
    required this.name,
    required this.content,
    required this.createdAt,
    required this.embedding,
    this.relatedMessageIds = const [],
    this.relevanceReason,
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
        relevanceReason: entry.relevanceReason,
        score: entry.score,
        matchedTokens: entry.matchedTokens,
      );

  AgentMemoryRecord copyWith({
    String? embedding,
    String? relevanceReason,
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
        relevanceReason: relevanceReason ?? this.relevanceReason,
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
const _customJsTypeofLiteralIdentifiers = {
  'true',
  'false',
  'null',
  'undefined',
};
const _customJsStringInstanceMethods = {
  'trim',
  'trimStart',
  'trimLeft',
  'trimEnd',
  'trimRight',
  'toUpperCase',
  'toLowerCase',
  'toString',
  'localeCompare',
  'split',
  'replace',
  'replaceAll',
  'indexOf',
  'lastIndexOf',
  'substring',
  'charAt',
  'startsWith',
  'endsWith',
  'padStart',
  'padEnd',
  'repeat',
  'includes',
  'match',
  'matchAll',
  'slice',
  'at',
};
const _customJsIterableInstanceMethods = {
  'indexOf',
  'lastIndexOf',
  'includes',
  'concat',
  'at',
  'map',
  'flatMap',
  'flat',
  'filter',
  'forEach',
  'find',
  'findIndex',
  'findLast',
  'findLastIndex',
  'some',
  'every',
  'reduce',
  'reduceRight',
  'sort',
  'toSorted',
  'reverse',
  'toReversed',
  'toSpliced',
  'with',
  'keys',
  'values',
  'entries',
  'slice',
  'join',
};
const _customJsNumberInstanceMethods = {
  'toString',
  'toFixed',
};
const _customJsSetMethods = {
  'has',
  'add',
  'delete',
  'clear',
  'keys',
  'values',
  'entries',
  'forEach',
  'union',
  'intersection',
  'difference',
  'isSubsetOf',
  'isDisjointFrom',
};
const _agentDeploymentType = 'agent-stage';
const _agentToolAuditRoles = {agentRoleTool};
const _agentToolAuditRoleSuffixes = {':tool'};
const _agentMemoryTimeRangeToolSchema = {
  'range': {
    'type': 'object',
    'description':
        '可选。Elasticsearch range 时间过滤；支持 range.createTime.gte/lte/gt/lt。',
  },
  'gte': {
    'type': 'integer',
    'description': 'range.createTime 的大于等于下界别名，会映射为 createdAfter。',
  },
  'gt': {
    'type': 'integer',
    'description': 'range.createTime 的大于下界别名，会映射为 createdAfter。',
  },
  'lte': {
    'type': 'integer',
    'description': 'range.createTime 的小于等于上界别名，会映射为 createdBefore。',
  },
  'lt': {
    'type': 'integer',
    'description': 'range.createTime 的小于上界别名，会映射为 createdBefore。',
  },
  'createdAfter': {
    'type': 'integer',
    'description': '可选。只返回 createTime 大于等于该毫秒时间戳的记忆。',
  },
  'createdBefore': {
    'type': 'integer',
    'description': '可选。只返回 createTime 小于等于该毫秒时间戳的记忆。',
  },
  'createTimeAfter': {
    'type': 'integer',
    'description': 'createdAfter 的 createTime 语义别名。',
  },
  'createTimeBefore': {
    'type': 'integer',
    'description': 'createdBefore 的 createTime 语义别名。',
  },
  'created_at_after': {
    'type': 'integer',
    'description': 'createdAfter 的 snake_case 别名。',
  },
  'created_at_before': {
    'type': 'integer',
    'description': 'createdBefore 的 snake_case 别名。',
  },
  'since': {
    'type': 'integer',
    'description': 'createdAfter 的自然语言别名，表示从该时间之后开始召回。',
  },
  'until': {
    'type': 'integer',
    'description': 'createdBefore 的自然语言别名，表示召回到该时间为止。',
  },
  'after': {
    'type': 'integer',
    'description': 'since 的简写别名。',
  },
  'before': {
    'type': 'integer',
    'description': 'until 的简写别名。',
  },
  'startTime': {
    'type': 'integer',
    'description': 'createdAfter 的时间范围起点别名。',
  },
  'start_time': {
    'type': 'integer',
    'description': 'startTime 的 snake_case 别名。',
  },
  'endTime': {
    'type': 'integer',
    'description': 'createdBefore 的时间范围终点别名。',
  },
  'end_time': {
    'type': 'integer',
    'description': 'endTime 的 snake_case 别名。',
  },
  'fromTime': {
    'type': 'integer',
    'description': 'startTime 的自然语言别名。',
  },
  'from_time': {
    'type': 'integer',
    'description': 'fromTime 的 snake_case 别名。',
  },
  'toTime': {
    'type': 'integer',
    'description': 'endTime 的自然语言别名。',
  },
  'to_time': {
    'type': 'integer',
    'description': 'toTime 的 snake_case 别名。',
  },
  '开始时间': {
    'type': 'integer',
    'description': 'createdAfter/startTime 的中文别名。',
  },
  '结束时间': {
    'type': 'integer',
    'description': 'createdBefore/endTime 的中文别名。',
  },
  '之后': {
    'type': 'integer',
    'description': 'since/after 的中文别名。',
  },
  '之前': {
    'type': 'integer',
    'description': 'until/before 的中文别名。',
  },
  'recentMs': {
    'type': 'integer',
    'description': '可选。只返回最近 N 毫秒内创建的记忆。',
  },
  'recentMilliseconds': {
    'type': 'integer',
    'description': 'recentMs 的自然语言别名。',
  },
  'recentMillis': {
    'type': 'integer',
    'description': 'recentMs 的常见毫秒别名。',
  },
  'lastMs': {
    'type': 'integer',
    'description': 'recentMs 的 last/within 语义别名。',
  },
  'lastMilliseconds': {
    'type': 'integer',
    'description': 'lastMs 的自然语言别名。',
  },
  'lastMillis': {
    'type': 'integer',
    'description': 'lastMs 的常见毫秒别名。',
  },
  'withinMs': {
    'type': 'integer',
    'description': 'recentMs 的 within 语义别名。',
  },
  'withinMilliseconds': {
    'type': 'integer',
    'description': 'withinMs 的自然语言别名。',
  },
  'withinMillis': {
    'type': 'integer',
    'description': 'withinMs 的常见毫秒别名。',
  },
  'recentSeconds': {
    'type': 'integer',
    'description': '可选。只返回最近 N 秒内创建的记忆。',
  },
  'lastSeconds': {
    'type': 'integer',
    'description': 'recentSeconds 的 last/within 语义别名。',
  },
  'withinSeconds': {
    'type': 'integer',
    'description': 'recentSeconds 的 within 语义别名。',
  },
  'recentMinutes': {
    'type': 'integer',
    'description': '可选。只返回最近 N 分钟内创建的记忆。',
  },
  'lastMinutes': {
    'type': 'integer',
    'description': 'recentMinutes 的 last/within 语义别名。',
  },
  'withinMinutes': {
    'type': 'integer',
    'description': 'recentMinutes 的 within 语义别名。',
  },
  'recentHours': {
    'type': 'integer',
    'description': '可选。只返回最近 N 小时内创建的记忆。',
  },
  'lastHours': {
    'type': 'integer',
    'description': 'recentHours 的 last/within 语义别名。',
  },
  'withinHours': {
    'type': 'integer',
    'description': 'recentHours 的 within 语义别名。',
  },
  'recentDays': {
    'type': 'integer',
    'description': '可选。只返回最近 N 天内创建的记忆。',
  },
  'lastDays': {
    'type': 'integer',
    'description': 'recentDays 的 last/within 语义别名。',
  },
  'withinDays': {
    'type': 'integer',
    'description': 'recentDays 的 within 语义别名。',
  },
  '最近毫秒': {
    'type': 'integer',
    'description': 'recentMs 的中文别名。',
  },
  '最近秒': {
    'type': 'integer',
    'description': 'recentSeconds 的中文别名。',
  },
  '最近分钟': {
    'type': 'integer',
    'description': 'recentMinutes 的中文别名。',
  },
  '最近小时': {
    'type': 'integer',
    'description': 'recentHours 的中文别名。',
  },
  '最近天': {
    'type': 'integer',
    'description': 'recentDays 的中文别名。',
  },
};
const _agentMemorySortToolSchema = {
  'orderBy': {
    'type': 'string',
    'enum': [
      'relevance',
      'score',
      'latest',
      'newest',
      'oldest',
      'chronological',
      'createTime',
    ],
    'description': '可选。控制返回记忆排序：相关性、最新优先或时间正序。',
  },
  'sortBy': {
    'type': 'string',
    'description': 'orderBy 的自然语言别名。',
  },
  'sortOrder': {
    'type': 'string',
    'description': 'orderBy 的排序方向别名，可用 latest/newest/oldest。',
  },
  'order': {
    'type': 'string',
    'description': 'orderBy 的简写别名。',
  },
  'sort': {
    'type': ['array', 'object', 'string'],
    'description':
        '可选。Elasticsearch sort 排序；支持 [{createTime:"desc"}] 或 {created_at:{order:"asc"}}。',
  },
  '排序': {
    'type': 'string',
    'description': 'orderBy 的中文别名，可用相关性、最新、最旧、时间顺序。',
  },
  '排序方式': {
    'type': 'string',
    'description': 'sortBy 的中文别名。',
  },
};
const _agentMemoryOffsetToolSchema = {
  'from': {
    'type': 'integer',
    'minimum': 0,
    'maximum': 200,
    'description': '可选。Elasticsearch 分页偏移；排序和过滤后跳过前 N 条。',
  },
  'offset': {
    'type': 'integer',
    'minimum': 0,
    'maximum': 200,
    'description': 'from 的自然语言别名。',
  },
  'skip': {
    'type': 'integer',
    'minimum': 0,
    'maximum': 200,
    'description': 'from 的跳过数量别名。',
  },
  '跳过数量': {
    'type': 'integer',
    'minimum': 0,
    'maximum': 200,
    'description': 'skip 的中文别名。',
  },
};
const _agentMemoryQueryPlanToolSchema = {
  'queryPlan': {
    'type': ['array', 'object'],
    'items': {
      'type': ['string', 'object'],
    },
    'description':
        '可选。结构化查询计划。可以是数组，也可以是包含 queries/queryList/items/steps 的对象；每项可以是字符串，或包含 query/q/keyword/text/prompt/semanticQuery/vectorQuery/查询/关键词/语义查询/向量查询 的对象；对象可携带 scope/memoryType/记忆范围/role/memoryRoles/记忆角色/excludeIds/excludeRoles/排除角色/视觉参考/minSimilarity/createdAfter/orderBy/limit/size/from/priority/mustInclude/excludeTerms/must/must_not/match/exists/operator 等过滤提示，也可把这些过滤提示包在 filter/post_filter/where/bool/criteria/条件 对象内。',
  },
  'query_plan': {
    'type': ['array', 'object'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'queryPlan 的 snake_case 别名。',
  },
  'retrievalPlan': {
    'type': ['array', 'object'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'queryPlan 的 RAG 检索计划别名。',
  },
  'retrieval_plan': {
    'type': ['array', 'object'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'retrievalPlan 的 snake_case 别名。',
  },
  'searchPlan': {
    'type': ['array', 'object'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'queryPlan 的搜索计划别名。',
  },
  'search_plan': {
    'type': ['array', 'object'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'searchPlan 的 snake_case 别名。',
  },
  'searchQueries': {
    'type': ['array', 'object'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'queryPlan 的查询数组别名。',
  },
  'search_queries': {
    'type': ['array', 'object'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'searchQueries 的 snake_case 别名。',
  },
  'plannedQueries': {
    'type': ['array', 'object'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'queryPlan 的计划查询别名。',
  },
  'planned_queries': {
    'type': ['array', 'object'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'plannedQueries 的 snake_case 别名。',
  },
  '查询计划': {
    'type': ['array', 'object'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'queryPlan 的中文别名。',
  },
  '检索计划': {
    'type': ['array', 'object'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'retrievalPlan 的中文别名。',
  },
  '搜索计划': {
    'type': ['array', 'object'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'searchPlan 的中文别名。',
  },
};
const _agentMemoryIncludeIdToolSchema = {
  'ids': {
    'type': ['object', 'array', 'string'],
    'description': '可选。按 memory record id 精确召回；支持 Elasticsearch ids.values 结构。',
  },
  'includeIds': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': '可选。精确召回这些 memory id，不会把它们当作已读排除。',
  },
  'includeMemoryIds': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'includeIds 的记忆 id 语义别名。',
  },
  'includedMemoryIds': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'includeMemoryIds 的过去式别名。',
  },
  'targetIds': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'includeIds 的目标 id 别名。',
  },
  'targetMemoryIds': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'targetIds 的记忆 id 语义别名。',
  },
  'onlyIds': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'includeIds 的 only/精确回查别名。',
  },
  'onlyMemoryIds': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'onlyIds 的记忆 id 语义别名。',
  },
  'targetRecords': {
    'type': 'array',
    'items': {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
      },
    },
    'description': '可选。精确召回这些 records；与 records/seenRecords 的“排除已读”语义分开。',
  },
  '指定记忆': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'includeIds 的中文别名。',
  },
  '目标记忆': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'targetIds 的中文别名。',
  },
  '只看记忆': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'onlyIds 的中文别名。',
  },
};
const _agentMemoryFilterWrapperKeys = [
  'filter',
  'filters',
  'post_filter',
  'postFilter',
  'where',
  'criteria',
  'constraints',
  'condition',
  'conditions',
  'bool',
  'boolFilter',
  'bool_filter',
  '筛选',
  '过滤',
  '条件',
  '布尔条件',
  '布尔过滤',
  '过滤条件',
  '后置过滤',
  '查询条件',
  '检索条件',
];
const _agentMemoryStructuredDslWrapperKeys = [
  'query',
  '查询',
  'dsl',
  'esQuery',
  'es_query',
  'searchQuery',
  'search_query',
  'boosting',
  'constant_score',
  'constantScore',
  'function_score',
  'functionScore',
  'nested',
];
const _agentMemoryStructuredQueryClauseKeys = [
  'boosting',
  'dis_max',
  'disMax',
  'multi_match',
  'multiMatch',
  'query_string',
  'queryString',
  'simple_query_string',
  'simpleQueryString',
  'combined_fields',
  'combinedFields',
];
const _agentMemoryStructuredVectorClauseKeys = [
  'knn',
  'nearestVector',
  'nearest_vector',
  'vectorSearch',
  'vector_search',
  'semanticVector',
  'semantic_vector',
];
const _agentMemoryHybridRetrieverClauseKeys = [
  'retriever',
  'retrievers',
  'rrf',
  'rank',
  'rankFusion',
  'rank_fusion',
  'hybrid',
  'hybridRetriever',
  'hybrid_retriever',
  'standard',
  'standardRetriever',
  'standard_retriever',
  'subRetrievers',
  'sub_retrievers',
];
const _agentMemoryVectorQueryBuilderKeys = [
  'query_vector_builder',
  'queryVectorBuilder',
  'text_embedding',
  'textEmbedding',
  'embedding',
  'embeddingQueryBuilder',
  'embedding_query_builder',
];
const _agentMemorySemanticQueryToolSchema = {
  'semanticQuery': {
    'type': 'string',
    'description': '可选。语义检索查询文本，适合走 embedding / 向量索引召回。',
  },
  'semantic_query': {
    'type': 'string',
    'description': 'semanticQuery 的 snake_case 别名。',
  },
  'semanticQueries': {
    'type': 'array',
    'items': {'type': 'string'},
    'description': '可选。一次提供多个语义检索查询。',
  },
  'semantic_queries': {
    'type': 'array',
    'items': {'type': 'string'},
    'description': 'semanticQueries 的 snake_case 别名。',
  },
  'vectorQuery': {
    'type': 'string',
    'description': 'semanticQuery 的向量检索语义别名。',
  },
  'vector_query': {
    'type': 'string',
    'description': 'vectorQuery 的 snake_case 别名。',
  },
  'vectorQueries': {
    'type': 'array',
    'items': {'type': 'string'},
    'description': 'semanticQueries 的向量检索语义别名。',
  },
  'vector_queries': {
    'type': 'array',
    'items': {'type': 'string'},
    'description': 'vectorQueries 的 snake_case 别名。',
  },
  '向量查询': {
    'type': 'string',
    'description': 'vectorQuery 的中文别名。',
  },
  '语义查询': {
    'type': 'string',
    'description': 'semanticQuery 的中文别名。',
  },
  '向量查询列表': {
    'type': 'array',
    'items': {'type': 'string'},
    'description': 'vectorQueries 的中文别名。',
  },
  '语义查询列表': {
    'type': 'array',
    'items': {'type': 'string'},
    'description': 'semanticQueries 的中文别名。',
  },
  'knn': {
    'type': 'object',
    'description':
        '可选。Elasticsearch kNN 向量检索子句；会从 query/query_vector_builder 文本派生语义检索，并只接受向量索引命中。',
  },
  'nearestVector': {
    'type': 'object',
    'description': 'knn 的自然语言别名。',
  },
  'nearest_vector': {
    'type': 'object',
    'description': 'nearestVector 的 snake_case 别名。',
  },
  'query_vector_builder': {
    'type': 'object',
    'description': '可选。kNN query_vector_builder 包裹，内部 model_text 会被展开为向量查询文本。',
  },
  'queryVectorBuilder': {
    'type': 'object',
    'description': 'query_vector_builder 的 camelCase 别名。',
  },
  'retriever': {
    'type': 'object',
    'description':
        '可选。Elasticsearch retriever 包装；支持 standard / rrf / knn 等混合检索计划。',
  },
  'retrievers': {
    'type': 'array',
    'items': {'type': 'object'},
    'description': '可选。RRF / hybrid retriever 的子检索器数组。',
  },
  'rrf': {
    'type': 'object',
    'description': '可选。RRF 混合检索包装；内部 retrievers 会被展开为多条记忆查询。',
  },
  'standard': {
    'type': 'object',
    'description': '可选。标准文本检索包装；内部 query/match 会被展开为文本查询与硬过滤词。',
  },
  'rank': {
    'type': 'object',
    'description': '可选。rank / rank fusion 包装；内部 rrf/retrievers 会被递归展开。',
  },
};
const _agentMemoryRerankToolSchema = {
  'rerank': {
    'type': 'boolean',
    'description': '可选。为 true 时，本次记忆检索使用模型重排候选记忆。',
  },
  'rerankEnabled': {
    'type': 'boolean',
    'description': 'rerank 的配置语义别名。',
  },
  'useRerank': {
    'type': 'boolean',
    'description': 'rerank 的自然语言别名。',
  },
  'modelRerank': {
    'type': 'boolean',
    'description': 'rerank 的模型重排语义别名。',
  },
  '模型重排': {
    'type': 'boolean',
    'description': 'rerank 的中文别名。',
  },
  '重排': {
    'type': 'boolean',
    'description': 'rerank 的中文简写别名。',
  },
};
const _agentMemoryQueryCombinationToolSchema = {
  'match': {
    'type': 'string',
    'description': '可选。queryPlan 项内多个查询的组合方式；all/and 表示必须命中同一条记忆。',
  },
  'matchMode': {
    'type': 'string',
    'description': 'match 的自然语言别名。',
  },
  'operator': {
    'type': 'string',
    'description': '可选。queryPlan 项内查询操作符；and 表示同项查询取交集。',
  },
  'mustMatchAll': {
    'type': 'boolean',
    'description': '可选。为 true 时，同一 queryPlan 项里的多个查询必须全部命中。',
  },
  'requireAll': {
    'type': 'boolean',
    'description': 'mustMatchAll 的 require 语义别名。',
  },
  '必须全部命中': {
    'type': 'boolean',
    'description': 'mustMatchAll 的中文别名。',
  },
};
const _agentMemoryQueryFallbackToolSchema = {
  'fallback': {
    'type': 'boolean',
    'description': '可选。为 true 时，该 queryPlan 项只在前序检索没有结果时作为兜底执行。',
  },
  'fallbackOnly': {
    'type': 'boolean',
    'description': 'fallback 的自然语言别名。',
  },
  'whenEmpty': {
    'type': ['boolean', 'string'],
    'description': '可选。为 true 或 empty/no_results 时，该计划项仅在前序无结果时执行。',
  },
  '仅在无结果时使用': {
    'type': 'boolean',
    'description': 'fallback 的中文别名。',
  },
  'group': {
    'type': 'string',
    'description': '可选。检索计划分组；fallback 只查看同组前序结果。',
  },
  'fallbackGroup': {
    'type': 'string',
    'description': 'group 的 fallback 语义别名。',
  },
  '检索分组': {
    'type': 'string',
    'description': 'group 的中文别名。',
  },
};
const _agentMemoryRetrievalSourceToolSchema = {
  'retrievalSource': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': '可选。只接受指定召回来源的记录；vector_index 表示必须来自 o_memoryVector 向量索引。',
  },
  'retrievalSources': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'retrievalSource 的数组别名。',
  },
  'retrieval_source': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'retrievalSource 的 snake_case 别名。',
  },
  'retrieval_sources': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'retrievalSources 的 snake_case 别名。',
  },
  '检索来源': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'retrievalSource 的中文别名，可用 向量索引。',
  },
  '召回来源': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'retrievalSource 的中文语义别名。',
  },
  'onlyVectorIndex': {
    'type': 'boolean',
    'description': '可选。为 true 时只接受 o_memoryVector 向量索引命中的记录。',
  },
  'vectorOnly': {
    'type': 'boolean',
    'description': 'onlyVectorIndex 的简写别名。',
  },
  'requireVectorIndex': {
    'type': 'boolean',
    'description': 'onlyVectorIndex 的 require 语义别名。',
  },
  '只用向量索引': {
    'type': 'boolean',
    'description': 'onlyVectorIndex 的中文别名。',
  },
  '仅向量索引': {
    'type': 'boolean',
    'description': 'onlyVectorIndex 的中文简写别名。',
  },
};
const _agentMemoryContentFilterToolSchema = {
  'bool': {
    'type': 'object',
    'description': '可选。DSL 风格布尔过滤包裹，可包含 must/must_not/filter 等字段。',
  },
  'boolFilter': {
    'type': 'object',
    'description': 'bool 的自然语言别名。',
  },
  'bool_filter': {
    'type': 'object',
    'description': 'boolFilter 的 snake_case 别名。',
  },
  'post_filter': {
    'type': 'object',
    'description': '可选。Elasticsearch post_filter 后置过滤包裹；本地召回按硬过滤处理。',
  },
  'postFilter': {
    'type': 'object',
    'description': 'post_filter 的 camelCase 别名。',
  },
  'exists': {
    'type': ['object', 'array', 'string'],
    'description': '可选。Elasticsearch exists 字段存在过滤；支持 {field:"role"} 或字段名字符串。',
  },
  '布尔条件': {
    'type': 'object',
    'description': 'bool 的中文别名。',
  },
  'boosting': {
    'type': 'object',
    'description':
        '可选。Elasticsearch boosting 查询包裹；positive 会展开为检索条件，negative 会展开为排除条件。',
  },
  'positive': {
    'type': 'object',
    'description': 'boosting 的正向查询子句。',
  },
  'negative': {
    'type': 'object',
    'description': 'boosting 的负向查询子句，会作为排除条件处理。',
  },
  'negative_boost': {
    'type': 'number',
    'description': 'boosting 的负向权重参数；本地召回会忽略权重，仅使用 negative 作为排除条件。',
  },
  'constant_score': {
    'type': 'object',
    'description': '可选。Elasticsearch constant_score 包裹，内部 filter 会被展开为内容过滤。',
  },
  'constantScore': {
    'type': 'object',
    'description': 'constant_score 的 camelCase 别名。',
  },
  'function_score': {
    'type': 'object',
    'description':
        '可选。Elasticsearch function_score 包裹，内部 query/filter 会被展开为检索条件。',
  },
  'functionScore': {
    'type': 'object',
    'description': 'function_score 的 camelCase 别名。',
  },
  'nested': {
    'type': 'object',
    'description': '可选。Elasticsearch nested 包裹，内部 query/filter 会被展开为内容过滤。',
  },
  'dis_max': {
    'type': 'object',
    'description': '可选。Elasticsearch dis_max 查询子句，内部 queries 会被展开为多条检索文本。',
  },
  'disMax': {
    'type': 'object',
    'description': 'dis_max 的 camelCase 别名。',
  },
  'multi_match': {
    'type': 'object',
    'description': '可选。Elasticsearch multi_match 查询子句，内部 query 会被展开为检索文本。',
  },
  'multiMatch': {
    'type': 'object',
    'description': 'multi_match 的 camelCase 别名。',
  },
  'query_string': {
    'type': 'object',
    'description': '可选。Elasticsearch query_string 查询子句，内部 query 会被展开为检索文本。',
  },
  'queryString': {
    'type': 'object',
    'description': 'query_string 的 camelCase 别名。',
  },
  'simple_query_string': {
    'type': 'object',
    'description':
        '可选。Elasticsearch simple_query_string 查询子句，内部 query 会被展开为检索文本。',
  },
  'simpleQueryString': {
    'type': 'object',
    'description': 'simple_query_string 的 camelCase 别名。',
  },
  'filter': {
    'type': ['object', 'array'],
    'items': {
      'type': ['string', 'object'],
    },
    'description':
        '可选。Elasticsearch bool.filter 风格硬过滤，直接的 term/match/match_phrase 子句会作为 mustInclude 条件。',
  },
  'filters': {
    'type': ['object', 'array'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'filter 的复数别名。',
  },
  'should': {
    'type': ['array', 'string'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': '可选。Elasticsearch bool.should 风格候选包含词，默认至少命中 1 个。',
  },
  'shouldInclude': {
    'type': ['array', 'string'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'should 的自然语言别名。',
  },
  'minimum_should_match': {
    'type': ['integer', 'string'],
    'description': '可选。should 候选词的最低命中数量。',
  },
  'minimumShouldMatch': {
    'type': ['integer', 'string'],
    'description': 'minimum_should_match 的 camelCase 别名。',
  },
  'term': {
    'type': ['object', 'array', 'string'],
    'description': '可选。Elasticsearch 风格单词过滤，如 {"term":{"content":"冷白石桥"}}。',
  },
  'terms': {
    'type': ['object', 'array', 'string'],
    'description': 'term 的复数别名，可携带多个字段值或关键词。',
  },
  'prefix': {
    'type': ['object', 'array', 'string'],
    'description': '可选。Elasticsearch prefix 前缀过滤；本地按内容字面片段硬过滤。',
  },
  'wildcard': {
    'type': ['object', 'array', 'string'],
    'description': '可选。Elasticsearch wildcard 通配过滤；* 和 ? 会展开为字面片段检索。',
  },
  'regexp': {
    'type': ['object', 'array', 'string'],
    'description': '可选。Elasticsearch regexp 正则过滤；本地按正则中的字面片段硬过滤。',
  },
  'match_bool_prefix': {
    'type': ['object', 'array', 'string'],
    'description': '可选。Elasticsearch match_bool_prefix 子句，按内容前缀查询语义召回。',
  },
  'matchBoolPrefix': {
    'type': ['object', 'array', 'string'],
    'description': 'match_bool_prefix 的 camelCase 别名。',
  },
  'match_phrase': {
    'type': ['object', 'array', 'string'],
    'description':
        '可选。Elasticsearch 风格短语匹配过滤，如 {"match_phrase":{"content":"蓝火背光"}}。',
  },
  'matchPhrase': {
    'type': ['object', 'array', 'string'],
    'description': 'match_phrase 的 camelCase 别名。',
  },
  'must': {
    'type': ['array', 'string'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'mustInclude 的 DSL 风格别名，也可携带 term/match/match_phrase 对象项。',
  },
  'require': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'mustInclude 的 require 语义别名。',
  },
  'requires': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'require 的复数别名。',
  },
  'mustInclude': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': '可选。返回记忆内容必须同时包含这些关键词。',
  },
  'mustIncludeTerms': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'mustInclude 的自然语言别名。',
  },
  'includeTerms': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'mustInclude 的包含词别名。',
  },
  'requiredTerms': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'mustInclude 的必需词别名。',
  },
  'required': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'requiredTerms 的简写别名。',
  },
  'include': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'includeTerms 的 DSL 风格别名。',
  },
  'includes': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'include 的复数别名。',
  },
  '包含关键词': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'mustInclude 的中文别名。',
  },
  '必须包含': {
    'type': ['array', 'string'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'requiredTerms 的中文别名，也可携带 term/match/match_phrase 对象项。',
  },
  'mustNot': {
    'type': ['array', 'string'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'excludeTerms 的 DSL 风格别名，也可携带 term/match/match_phrase 对象项。',
  },
  'must_not': {
    'type': ['array', 'string'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'mustNot 的 snake_case 别名，也可携带对象项。',
  },
  'not': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'excludeTerms 的否定过滤别名。',
  },
  'excludeTerms': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': '可选。排除内容包含这些关键词的记忆。',
  },
  'exclude': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'excludeTerms 的 DSL 风格别名。',
  },
  'excludes': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'exclude 的复数别名。',
  },
  'excludeKeywords': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'excludeTerms 的关键词别名。',
  },
  'forbiddenTerms': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'excludeTerms 的禁用词别名。',
  },
  'mustNotInclude': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'excludeTerms 的 must-not 语义别名。',
  },
  '排除关键词': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'excludeTerms 的中文别名。',
  },
  '不能包含': {
    'type': ['array', 'string'],
    'items': {
      'type': ['string', 'object'],
    },
    'description': 'mustNotInclude 的中文别名，也可携带 term/match/match_phrase 对象项。',
  },
};

final _tools = <AgentToolDef>[
  const AgentToolDef(
    name: 'memory_add',
    description: '调用 ToonFlow Memory.add 写入 Agent 记忆。'
        '默认写入当前 Agent 家族的普通 message 记忆并参与摘要；显式 long_term/note 时写入项目长期记忆。',
    schema: {
      'type': 'object',
      'properties': {
        'content': {
          'type': 'string',
          'description': '要写入记忆的正文内容。',
        },
        '内容': {
          'type': 'string',
          'description': 'content 的中文别名。',
        },
        '记忆内容': {
          'type': 'string',
          'description': 'content 的中文语义别名。',
        },
        '正文': {
          'type': 'string',
          'description': 'content 的中文正文别名。',
        },
        'text': {
          'type': 'string',
          'description': 'content 的自然语言别名。',
        },
        'memory': {
          'type': 'string',
          'description': 'content 的语义化别名。',
        },
        'note': {
          'type': 'string',
          'description': 'content 的长期记忆别名。',
        },
        'message': {
          'type': 'string',
          'description': 'content 的模型常见消息别名。',
        },
        'prompt': {
          'type': 'string',
          'description': 'content 的提示词别名。',
        },
        'input': {
          'type': 'string',
          'description': 'content 的输入别名。',
        },
        'value': {
          'type': 'string',
          'description': 'content 的值别名。',
        },
        'name': {
          'type': 'string',
          'description': '可选。记忆名称或摘要标签。',
        },
        'title': {
          'type': 'string',
          'description': 'name 的自然语言别名。',
        },
        '标题': {
          'type': 'string',
          'description': 'name 的中文标题别名。',
        },
        '名称': {
          'type': 'string',
          'description': 'name 的中文名称别名。',
        },
        'label': {
          'type': 'string',
          'description': 'name 的标签别名。',
        },
        'memoryName': {
          'type': 'string',
          'description': 'name 的记忆名称别名。',
        },
        '记忆名称': {
          'type': 'string',
          'description': 'memoryName 的中文别名。',
        },
        'memory_name': {
          'type': 'string',
          'description': 'memoryName 的 snake_case 别名。',
        },
        'role': {
          'type': 'string',
          'description': '可选。普通 message 记忆的 role，默认 user。',
        },
        '角色': {
          'type': 'string',
          'description': 'role 的中文别名。',
        },
        'memoryRole': {
          'type': 'string',
          'description': 'role 的记忆角色别名。',
        },
        '记忆角色': {
          'type': 'string',
          'description': 'memoryRole 的中文别名。',
        },
        'memory_role': {
          'type': 'string',
          'description': 'memoryRole 的 snake_case 别名。',
        },
        'authorRole': {
          'type': 'string',
          'description': 'role 的作者角色别名。',
        },
        'author_role': {
          'type': 'string',
          'description': 'authorRole 的 snake_case 别名。',
        },
        'type': {
          'type': 'string',
          'enum': ['message', 'note'],
          'description': '可选。写入 message 普通记忆或 note 长期记忆。',
        },
        '类型': {
          'type': 'string',
          'description': 'type 的中文别名，可用普通记忆或长期记忆。',
        },
        'memoryType': {
          'type': 'string',
          'enum': ['message', 'conversation', 'note', 'long_term'],
          'description': '可选。type/scope 的语义化别名。',
        },
        '记忆类型': {
          'type': 'string',
          'description': 'memoryType 的中文别名，可用普通记忆或长期记忆。',
        },
        'scope': {
          'type': 'string',
          'enum': ['conversation', 'long_term'],
          'description': '可选。conversation 写普通记忆；long_term 写长期记忆。',
        },
        '范围': {
          'type': 'string',
          'description': 'scope 的中文别名，可用对话记忆或长期记忆。',
        },
        'memoryScope': {
          'type': 'string',
          'enum': ['conversation', 'long_term'],
          'description': 'scope 的记忆范围别名。',
        },
        '记忆范围': {
          'type': 'string',
          'description': 'memoryScope 的中文别名，可用对话记忆或长期记忆。',
        },
        'memory_scope': {
          'type': 'string',
          'enum': ['conversation', 'long_term'],
          'description': 'memoryScope 的 snake_case 别名。',
        },
        'createTime': {
          'type': 'integer',
          'description': '可选。普通 message 记忆的创建时间毫秒时间戳。',
        },
        '创建时间': {
          'type': 'integer',
          'description': 'createTime 的中文别名。',
        },
        'create_time': {
          'type': 'integer',
          'description': 'createTime 的 snake_case 别名。',
        },
        'createdAt': {
          'type': 'integer',
          'description': 'createTime 的模型常见别名。',
        },
        'created_at': {
          'type': 'integer',
          'description': 'createdAt 的 snake_case 别名。',
        },
        'timestamp': {
          'type': 'integer',
          'description': 'createTime 的时间戳别名。',
        },
        '时间戳': {
          'type': 'integer',
          'description': 'timestamp 的中文别名。',
        },
        'time': {
          'type': 'integer',
          'description': 'createTime 的简写别名。',
        },
      },
    },
  ),
  const AgentToolDef(
    name: 'memory_update',
    description: '更新一条项目长期记忆。适合修正错误设定、补充角色/场景约束或重写已保存的视觉分析记忆。',
    schema: {
      'type': 'object',
      'properties': {
        'memoryId': {
          'type': 'string',
          'description':
              '要更新的长期记忆 id，通常来自 memory_get/deepRetrieve records[].id。',
        },
        'memory_id': {
          'type': 'string',
          'description': 'memoryId 的 snake_case 别名。',
        },
        'id': {
          'type': 'string',
          'description': 'memoryId 的简写别名。',
        },
        'recordId': {
          'type': 'string',
          'description': 'memoryId 的记录 id 别名。',
        },
        'record_id': {
          'type': 'string',
          'description': 'recordId 的 snake_case 别名。',
        },
        'record': {
          'type': 'object',
          'description':
              '可选。memory_get/deepRetrieve 返回的 records 单项；会从 id/memoryId/noteId 中抽取记忆 id。',
        },
        'records': {
          'type': 'array',
          'items': {'type': 'object'},
          'description':
              '可选。memory_get/deepRetrieve 返回的 records 数组；会使用第一条可识别的记忆 id。',
        },
        'memoryRecord': {
          'type': 'object',
          'description': 'record 的语义化别名。',
        },
        'memoryRecords': {
          'type': 'array',
          'items': {'type': 'object'},
          'description': 'records 的语义化别名。',
        },
        'memory_record': {
          'type': 'object',
          'description': 'memoryRecord 的 snake_case 别名。',
        },
        'memory_records': {
          'type': 'array',
          'items': {'type': 'object'},
          'description': 'memoryRecords 的 snake_case 别名。',
        },
        'noteId': {
          'type': 'string',
          'description': 'memoryId 的长期 note id 别名。',
        },
        'note_id': {
          'type': 'string',
          'description': 'noteId 的 snake_case 别名。',
        },
        '记忆Id': {
          'type': 'string',
          'description': 'memoryId 的中文别名。',
        },
        '记忆ID': {
          'type': 'string',
          'description': 'memoryId 的中文大写别名。',
        },
        'name': {
          'type': 'string',
          'description': '可选。新的记忆名称；不传则保留原名称。',
        },
        'title': {
          'type': 'string',
          'description': 'name 的自然语言别名。',
        },
        'memoryName': {
          'type': 'string',
          'description': 'name 的记忆名称别名。',
        },
        'memory_name': {
          'type': 'string',
          'description': 'memoryName 的 snake_case 别名。',
        },
        '名称': {
          'type': 'string',
          'description': 'name 的中文别名。',
        },
        '记忆名称': {
          'type': 'string',
          'description': 'memoryName 的中文别名。',
        },
        'content': {
          'type': 'string',
          'description': '可选。新的记忆正文；不传则保留原正文。',
        },
        'text': {
          'type': 'string',
          'description': 'content 的自然语言别名。',
        },
        'memory': {
          'type': 'string',
          'description': 'content 的语义化别名。',
        },
        'note': {
          'type': 'string',
          'description': 'content 的长期记忆别名。',
        },
        'message': {
          'type': 'string',
          'description': 'content 的模型常见消息别名。',
        },
        'value': {
          'type': 'string',
          'description': 'content 的值别名。',
        },
        '内容': {
          'type': 'string',
          'description': 'content 的中文别名。',
        },
        '记忆内容': {
          'type': 'string',
          'description': 'content 的中文语义别名。',
        },
        '正文': {
          'type': 'string',
          'description': 'content 的中文正文别名。',
        },
      },
    },
  ),
  const AgentToolDef(
    name: 'memory_delete',
    description: '删除一条项目长期记忆。适合移除错误、过期或重复的长期设定。',
    schema: {
      'type': 'object',
      'properties': {
        'memoryId': {
          'type': 'string',
          'description':
              '要删除的长期记忆 id，通常来自 memory_get/deepRetrieve records[].id。',
        },
        'memory_id': {
          'type': 'string',
          'description': 'memoryId 的 snake_case 别名。',
        },
        'id': {
          'type': 'string',
          'description': 'memoryId 的简写别名。',
        },
        'recordId': {
          'type': 'string',
          'description': 'memoryId 的记录 id 别名。',
        },
        'record_id': {
          'type': 'string',
          'description': 'recordId 的 snake_case 别名。',
        },
        'record': {
          'type': 'object',
          'description':
              '可选。memory_get/deepRetrieve 返回的 records 单项；会从 id/memoryId/noteId 中抽取记忆 id。',
        },
        'records': {
          'type': 'array',
          'items': {'type': 'object'},
          'description':
              '可选。memory_get/deepRetrieve 返回的 records 数组；会使用第一条可识别的记忆 id。',
        },
        'memoryRecord': {
          'type': 'object',
          'description': 'record 的语义化别名。',
        },
        'memoryRecords': {
          'type': 'array',
          'items': {'type': 'object'},
          'description': 'records 的语义化别名。',
        },
        'memory_record': {
          'type': 'object',
          'description': 'memoryRecord 的 snake_case 别名。',
        },
        'memory_records': {
          'type': 'array',
          'items': {'type': 'object'},
          'description': 'memoryRecords 的 snake_case 别名。',
        },
        'noteId': {
          'type': 'string',
          'description': 'memoryId 的长期 note id 别名。',
        },
        'note_id': {
          'type': 'string',
          'description': 'noteId 的 snake_case 别名。',
        },
        '记忆Id': {
          'type': 'string',
          'description': 'memoryId 的中文别名。',
        },
        '记忆ID': {
          'type': 'string',
          'description': 'memoryId 的中文大写别名。',
        },
      },
    },
  ),
  const AgentToolDef(
    name: 'memory_clear',
    description: '调用 ToonFlow Memory.clear 清理指定记忆层。'
        'message/conversation 清当前 Agent 家族的对话与摘要；summary 只清摘要并恢复源消息；'
        'note/long_term 清项目长期记忆；all 清当前 Agent 家族全部对话层记忆。',
    schema: {
      'type': 'object',
      'properties': {
        'scope': {
          'type': 'string',
          'enum': [
            'message',
            'conversation',
            'summary',
            'note',
            'long_term',
            'all',
          ],
          'description': '要清理的记忆范围。',
        },
        '范围': {
          'type': 'string',
          'description': 'scope 的中文别名，可用对话记忆、摘要、长期记忆或全部。',
        },
        'memoryScope': {
          'type': 'string',
          'enum': [
            'message',
            'conversation',
            'summary',
            'note',
            'long_term',
            'all',
          ],
          'description': 'scope 的记忆范围别名。',
        },
        '记忆范围': {
          'type': 'string',
          'description': 'memoryScope 的中文别名。',
        },
        'memory_scope': {
          'type': 'string',
          'enum': [
            'message',
            'conversation',
            'summary',
            'note',
            'long_term',
            'all',
          ],
          'description': 'memoryScope 的 snake_case 别名。',
        },
        'type': {
          'type': 'string',
          'enum': ['message', 'summary', 'note', 'all'],
          'description': 'scope 的类型别名。',
        },
        'memoryType': {
          'type': 'string',
          'enum': [
            'message',
            'conversation',
            'summary',
            'note',
            'long_term',
            'all',
          ],
          'description': 'scope 的记忆类型别名。',
        },
        '记忆类型': {
          'type': 'string',
          'description': 'memoryType 的中文别名。',
        },
      },
    },
  ),
  const AgentToolDef(
    name: 'memory_get',
    description: '调用 ToonFlow Memory.get 普通记忆检索，按查询返回相关原始对话、历史摘要和近期未摘要对话。'
        '适合先快速找当前上下文，不做 deepRetrieve 的 summary 判别展开。',
    schema: {
      'type': 'object',
      'properties': {
        'query': {
          'type': ['string', 'object'],
          'description': '要检索的记忆查询文本；也可传 Elasticsearch 风格 query 对象。',
        },
        '查询': {
          'type': 'string',
          'description': 'query 的中文别名。',
        },
        'question': {
          'type': 'string',
          'description': 'query 的自然语言别名。',
        },
        '问题': {
          'type': 'string',
          'description': 'question 的中文别名。',
        },
        'text': {
          'type': 'string',
          'description': 'query 的文本别名。',
        },
        '文本': {
          'type': 'string',
          'description': 'text 的中文别名。',
        },
        'prompt': {
          'type': 'string',
          'description': 'query 的提示词别名。',
        },
        '提示词': {
          'type': 'string',
          'description': 'prompt 的中文别名。',
        },
        'keyword': {
          'type': 'string',
          'description': 'query 的关键词别名。',
        },
        '关键词': {
          'type': 'string',
          'description': 'keyword 的中文别名。',
        },
        'q': {
          'type': 'string',
          'description': 'query 的简写别名。',
        },
        'queries': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。一次提供多个查询词，工具会合并检索结果并去重。',
        },
        'queryList': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'queries 的自然语言别名。',
        },
        'query_list': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'queryList 的 snake_case 别名。',
        },
        'keywords': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'queries 的关键词列表别名。',
        },
        'keywordList': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'keywords 的自然语言别名。',
        },
        'keyword_list': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'keywordList 的 snake_case 别名。',
        },
        '查询列表': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'queries 的中文别名。',
        },
        '关键词列表': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'keywords 的中文别名。',
        },
        ..._agentMemorySemanticQueryToolSchema,
        ..._agentMemoryRerankToolSchema,
        ..._agentMemoryQueryPlanToolSchema,
        ..._agentMemoryIncludeIdToolSchema,
        ..._agentMemoryQueryCombinationToolSchema,
        ..._agentMemoryQueryFallbackToolSchema,
        ..._agentMemoryContentFilterToolSchema,
        ..._agentMemoryRetrievalSourceToolSchema,
        'limit': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。限制返回的相关原始对话条数，默认使用全局 RAG 配置。',
        },
        'topK': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。limit 的常见 RAG 别名。',
        },
        'top_k': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。topK 的 snake_case 别名。',
        },
        'size': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。limit 的 Elasticsearch 风格别名。',
        },
        ..._agentMemoryOffsetToolSchema,
        'maxResults': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。limit 的自然语言别名。',
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
        'max': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。maxResults 的简写别名。',
        },
        'count': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。返回数量别名。',
        },
        '数量': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': 'count 的中文别名。',
        },
        '条数': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': 'limit 的中文条数别名。',
        },
        '返回数量': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': 'maxResults 的中文别名。',
        },
        'minScore': {
          'type': 'integer',
          'minimum': 1,
          'description': '可选。只返回分数不低于该值的高置信相关对话。',
        },
        'min_score': {
          'type': 'integer',
          'minimum': 1,
          'description': '可选。minScore 的 snake_case 别名。',
        },
        'minimumScore': {
          'type': 'integer',
          'minimum': 1,
          'description': '可选。minScore 的自然语言别名。',
        },
        'minimum_score': {
          'type': 'integer',
          'minimum': 1,
          'description': '可选。minimumScore 的 snake_case 别名。',
        },
        'scoreThreshold': {
          'type': 'integer',
          'minimum': 1,
          'description': '可选。minScore 的自然语言别名。',
        },
        'score_threshold': {
          'type': 'integer',
          'minimum': 1,
          'description': '可选。scoreThreshold 的 snake_case 别名。',
        },
        'threshold': {
          'type': 'integer',
          'minimum': 1,
          'description': '可选。scoreThreshold 的简写别名。',
        },
        'minSimilarity': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': '可选。相似度阈值别名，0.8 等价于 minScore=80。',
        },
        'min_similarity': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': '可选。minSimilarity 的 snake_case 别名。',
        },
        'minimumSimilarity': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': '可选。minSimilarity 的自然语言别名。',
        },
        'minimum_similarity': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': '可选。minimumSimilarity 的 snake_case 别名。',
        },
        'similarityThreshold': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': '可选。相似度阈值别名，0.8 等价于 minScore=80。',
        },
        'similarity_threshold': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': '可选。similarityThreshold 的 snake_case 别名。',
        },
        '相似度': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': 'minSimilarity 的中文别名。',
        },
        '最低相似度': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': 'minimumSimilarity 的中文别名。',
        },
        '相似度阈值': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': 'similarityThreshold 的中文别名。',
        },
        '最低分': {
          'type': 'integer',
          'minimum': 1,
          'description': 'minScore 的中文别名。',
        },
        '分数阈值': {
          'type': 'integer',
          'minimum': 1,
          'description': 'scoreThreshold 的中文别名。',
        },
        ..._agentMemoryTimeRangeToolSchema,
        ..._agentMemorySortToolSchema,
        'role': {
          'type': 'string',
          'description':
              '可选。只返回指定 role 的记忆，例如 user 或 assistant:execution:script。',
        },
        '角色': {
          'type': 'string',
          'description': 'role 的中文别名。',
        },
        'roles': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。只返回这些 role 的普通 RAG 上下文。',
        },
        'memoryRoles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'roles 的记忆角色别名。',
        },
        '记忆角色': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'memoryRoles 的中文别名。',
        },
        'memory_roles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'memoryRoles 的 snake_case 别名。',
        },
        'type': {
          'type': 'string',
          'enum': ['message', 'summary', 'note'],
          'description': '可选。只返回指定类型的记忆：message 原始对话，summary 摘要，note 长期记忆。',
        },
        '类型': {
          'type': 'string',
          'description': 'type 的中文别名，可用普通记忆、摘要或长期记忆。',
        },
        'types': {
          'type': 'array',
          'items': {
            'type': 'string',
            'enum': ['message', 'summary', 'note'],
          },
          'description': '可选。只返回这些类型的记忆。',
        },
        'memoryType': {
          'type': 'string',
          'enum': [
            'message',
            'summary',
            'note',
            'conversation',
            'long_term',
            'all'
          ],
          'description':
              '可选。type/scope 的语义化别名，可用 conversation、long_term 或 all 表示记忆层级。',
        },
        '记忆类型': {
          'type': 'string',
          'description': 'memoryType 的中文别名。',
        },
        'memoryTypes': {
          'type': 'array',
          'items': {
            'type': 'string',
            'enum': [
              'message',
              'summary',
              'note',
              'conversation',
              'long_term',
              'all',
            ],
          },
          'description': '可选。memoryType 的数组形式。',
        },
        'scope': {
          'type': 'string',
          'enum': ['conversation', 'summary', 'long_term', 'all'],
          'description':
              '可选。按记忆层级召回：conversation 对话记忆，summary 摘要，long_term 长期记忆，all 全部。',
        },
        '范围': {
          'type': 'string',
          'description': 'scope 的中文别名，可用对话记忆、摘要、长期记忆或全部。',
        },
        'scopes': {
          'type': 'array',
          'items': {
            'type': 'string',
            'enum': ['conversation', 'summary', 'long_term', 'all'],
          },
          'description': '可选。按多个记忆层级召回。',
        },
        'memoryScope': {
          'type': 'string',
          'enum': ['conversation', 'summary', 'long_term', 'all'],
          'description': 'scope 的记忆范围别名。',
        },
        '记忆范围': {
          'type': 'string',
          'description': 'memoryScope 的中文别名。',
        },
        'memory_scope': {
          'type': 'string',
          'enum': ['conversation', 'summary', 'long_term', 'all'],
          'description': 'memoryScope 的 snake_case 别名。',
        },
        'includeVisualReferences': {
          'type': 'boolean',
          'description': '可选。为 true 时额外召回项目长期记忆中的视觉参考/画风参考 note。',
        },
        'visualReferences': {
          'type': 'boolean',
          'description': 'includeVisualReferences 的自然语言别名。',
        },
        'include_visual_references': {
          'type': 'boolean',
          'description': 'includeVisualReferences 的 snake_case 别名。',
        },
        'visual_references': {
          'type': 'boolean',
          'description': 'visualReferences 的 snake_case 别名。',
        },
        'includeStyleReferences': {
          'type': 'boolean',
          'description': 'includeVisualReferences 的画风语义别名。',
        },
        'styleReferences': {
          'type': 'boolean',
          'description': 'visualReferences 的画风语义别名。',
        },
        '包含视觉参考': {
          'type': 'boolean',
          'description': 'includeVisualReferences 的中文别名。',
        },
        '视觉参考': {
          'type': 'boolean',
          'description': 'visualReferences 的中文别名。',
        },
        '包含画风参考': {
          'type': 'boolean',
          'description': 'includeStyleReferences 的中文别名。',
        },
        '画风参考': {
          'type': 'boolean',
          'description': 'styleReferences 的中文别名。',
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
        '排除角色': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeRoles 的中文别名。',
        },
        '排除记忆角色': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeMemoryRoles 的中文别名。',
        },
        'excludedRoles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeRoles 的过去式别名。',
        },
        'excluded_roles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludedRoles 的 snake_case 别名。',
        },
        'excludeMemoryRoles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeRoles 的记忆角色别名。',
        },
        'exclude_memory_roles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeMemoryRoles 的 snake_case 别名。',
        },
        'excludedMemoryRoles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeMemoryRoles 的过去式别名。',
        },
        'excluded_memory_roles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludedMemoryRoles 的 snake_case 别名。',
        },
        'excludeRoleSuffix': {
          'type': 'string',
          'description': '可选。排除 role 以该后缀结尾的记忆，例如 :tool。',
        },
        'excludeRoleSuffixes': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。排除 role 以这些后缀结尾的记忆。',
        },
        '排除角色后缀': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeRoleSuffixes 的中文别名。',
        },
        'excludeIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。排除这些已读 memory id，避免重复返回同一条记忆。',
        },
        '排除记忆': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeMemoryIds 的中文别名。',
        },
        '排除记忆Ids': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeMemoryIds 的中文 id 别名。',
        },
        'excludeMemoryIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。excludeIds 的语义化别名。',
        },
        'excludeId': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeIds 的单数别名。',
        },
        'seenMemoryIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。已读过的 memory id 列表，等价于 excludeIds。',
        },
        '已读记忆': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'seenMemoryIds 的中文别名。',
        },
        '已读记忆Ids': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'seenMemoryIds 的中文 id 别名。',
        },
        'seenIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。seenMemoryIds 的简写别名。',
        },
        'memoryIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。模型常用的已读 memory id 别名，等价于 excludeIds。',
        },
        'readMemoryIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。已读取 memory id 别名，等价于 excludeIds。',
        },
        'readIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。readMemoryIds 的简写别名。',
        },
        'previousMemoryIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。上一轮已读 memory id 列表，等价于 excludeIds。',
        },
        'records': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
          },
          'description':
              '可选。上一轮 memory_get/deepRetrieve 返回的 records，可原样传回以排除已读记忆。',
        },
        'seenRecords': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
          },
          'description': '可选。已读 records，等价于从 records 中提取 id 后加入 excludeIds。',
        },
        'readRecords': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
          },
          'description': '可选。已读取 records，等价于 seenRecords。',
        },
        '已读记录': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
          },
          'description': 'seenRecords 的中文别名。',
        },
        '排除记录': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
          },
          'description': 'excludeRecords 的中文别名。',
        },
        'previousRecords': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
          },
          'description': '可选。上一轮已读 records，等价于 seenRecords。',
        },
      },
    },
  ),
  const AgentToolDef(
    name: 'deepRetrieve',
    description: '按关键词深度召回 Agent 历史摘要，并展开相关原始对话消息。'
        '用于找回较早的角色设定、剧情约束、制作决策。'
        '结果会同时返回 memories 文本列表和 records 结构化来源。',
    schema: {
      'type': 'object',
      'properties': {
        'keyword': {'type': 'string'},
        '关键词': {
          'type': 'string',
          'description': 'keyword 的中文别名。',
        },
        'query': {
          'type': ['string', 'object'],
          'description':
              'keyword 的语义化别名，适合模型按“查询内容”组织参数；也可传 Elasticsearch 风格 query 对象。',
        },
        '查询': {
          'type': 'string',
          'description': 'query 的中文别名。',
        },
        'question': {
          'type': 'string',
          'description': 'keyword 的自然语言别名，适合“继续/下一步/回想”场景。',
        },
        '问题': {
          'type': 'string',
          'description': 'question 的中文别名。',
        },
        'text': {
          'type': 'string',
          'description': 'keyword 的文本别名。',
        },
        '文本': {
          'type': 'string',
          'description': 'text 的中文别名。',
        },
        'prompt': {
          'type': 'string',
          'description': 'keyword 的提示词别名。',
        },
        '提示词': {
          'type': 'string',
          'description': 'prompt 的中文别名。',
        },
        'q': {
          'type': 'string',
          'description': 'keyword 的简写别名。',
        },
        'queries': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。多查询列表，会按顺序召回并合并去重。',
        },
        'queryList': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'queries 的自然语言别名。',
        },
        'query_list': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'queryList 的 snake_case 别名。',
        },
        'keywords': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'queries 的关键词列表别名。',
        },
        'keywordList': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'keywords 的自然语言别名。',
        },
        'keyword_list': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'keywordList 的 snake_case 别名。',
        },
        '查询列表': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'queries 的中文别名。',
        },
        '关键词列表': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'keywords 的中文别名。',
        },
        ..._agentMemorySemanticQueryToolSchema,
        ..._agentMemoryRerankToolSchema,
        ..._agentMemoryQueryPlanToolSchema,
        ..._agentMemoryIncludeIdToolSchema,
        ..._agentMemoryQueryCombinationToolSchema,
        ..._agentMemoryQueryFallbackToolSchema,
        ..._agentMemoryContentFilterToolSchema,
        ..._agentMemoryRetrievalSourceToolSchema,
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
        'size': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。limit 的 Elasticsearch 风格别名，限制返回结果数。',
        },
        ..._agentMemoryOffsetToolSchema,
        'minScore': {
          'type': 'integer',
          'minimum': 1,
          'description': '可选。只返回分数不低于该值的高置信记忆。',
        },
        'min_score': {
          'type': 'integer',
          'minimum': 1,
          'description': '可选。minScore 的 snake_case 别名。',
        },
        'minimumScore': {
          'type': 'integer',
          'minimum': 1,
          'description': '可选。minScore 的自然语言别名。',
        },
        'minimum_score': {
          'type': 'integer',
          'minimum': 1,
          'description': '可选。minimumScore 的 snake_case 别名。',
        },
        'scoreThreshold': {
          'type': 'integer',
          'minimum': 1,
          'description': '可选。minScore 的自然语言别名，用于过滤弱相关记忆。',
        },
        'score_threshold': {
          'type': 'integer',
          'minimum': 1,
          'description': '可选。scoreThreshold 的 snake_case 别名。',
        },
        'threshold': {
          'type': 'integer',
          'minimum': 1,
          'description': '可选。scoreThreshold 的简写别名。',
        },
        'minSimilarity': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': '可选。相似度阈值别名，0.8 等价于 minScore=80。',
        },
        'min_similarity': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': '可选。minSimilarity 的 snake_case 别名。',
        },
        'minimumSimilarity': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': '可选。minSimilarity 的自然语言别名。',
        },
        'minimum_similarity': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': '可选。minimumSimilarity 的 snake_case 别名。',
        },
        'similarityThreshold': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': '可选。相似度阈值别名，0.8 等价于 minScore=80。',
        },
        'similarity_threshold': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': '可选。similarityThreshold 的 snake_case 别名。',
        },
        '相似度': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': 'minSimilarity 的中文别名。',
        },
        '最低相似度': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': 'minimumSimilarity 的中文别名。',
        },
        '相似度阈值': {
          'type': ['number', 'string'],
          'minimum': 0,
          'maximum': 1,
          'description': 'similarityThreshold 的中文别名。',
        },
        '最低分': {
          'type': 'integer',
          'minimum': 1,
          'description': 'minScore 的中文别名。',
        },
        '分数阈值': {
          'type': 'integer',
          'minimum': 1,
          'description': 'scoreThreshold 的中文别名。',
        },
        ..._agentMemoryTimeRangeToolSchema,
        ..._agentMemorySortToolSchema,
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
        'max': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。maxResults 的简写别名。',
        },
        'count': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '可选。返回数量别名。',
        },
        '数量': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': 'count 的中文别名。',
        },
        '条数': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': 'limit 的中文条数别名。',
        },
        '返回数量': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': 'maxResults 的中文别名。',
        },
        'role': {
          'type': 'string',
          'description': '可选。只返回指定 role 的记忆，例如 user 或 assistant:supervision。',
        },
        '角色': {
          'type': 'string',
          'description': 'role 的中文别名。',
        },
        'roles': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。只返回这些 role 的记忆。',
        },
        'memoryRoles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'roles 的记忆角色别名。',
        },
        '记忆角色': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'memoryRoles 的中文别名。',
        },
        'memory_roles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'memoryRoles 的 snake_case 别名。',
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
        '排除角色': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeRoles 的中文别名。',
        },
        '排除记忆角色': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeMemoryRoles 的中文别名。',
        },
        'excludedRoles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeRoles 的过去式别名。',
        },
        'excluded_roles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludedRoles 的 snake_case 别名。',
        },
        'excludeMemoryRoles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeRoles 的记忆角色别名。',
        },
        'exclude_memory_roles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeMemoryRoles 的 snake_case 别名。',
        },
        'excludedMemoryRoles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeMemoryRoles 的过去式别名。',
        },
        'excluded_memory_roles': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludedMemoryRoles 的 snake_case 别名。',
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
        '排除角色后缀': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeRoleSuffixes 的中文别名。',
        },
        'type': {
          'type': 'string',
          'enum': ['message', 'summary', 'note'],
          'description': '可选。只返回指定类型的记忆：message 原始对话，summary 摘要，note 长期记忆。',
        },
        '类型': {
          'type': 'string',
          'description': 'type 的中文别名，可用普通记忆、摘要或长期记忆。',
        },
        'types': {
          'type': 'array',
          'items': {
            'type': 'string',
            'enum': ['message', 'summary', 'note'],
          },
          'description': '可选。只返回这些类型的记忆。',
        },
        'memoryType': {
          'type': 'string',
          'enum': [
            'message',
            'summary',
            'note',
            'conversation',
            'long_term',
            'all'
          ],
          'description':
              '可选。type/scope 的语义化别名，可用 conversation、long_term 或 all 表示记忆层级。',
        },
        '记忆类型': {
          'type': 'string',
          'description': 'memoryType 的中文别名。',
        },
        'memoryTypes': {
          'type': 'array',
          'items': {
            'type': 'string',
            'enum': [
              'message',
              'summary',
              'note',
              'conversation',
              'long_term',
              'all',
            ],
          },
          'description': '可选。memoryType 的数组形式。',
        },
        'scope': {
          'type': 'string',
          'enum': ['conversation', 'summary', 'long_term', 'all'],
          'description':
              '可选。按记忆层级召回：conversation 对话记忆，summary 摘要，long_term 长期记忆，all 全部。',
        },
        '范围': {
          'type': 'string',
          'description': 'scope 的中文别名，可用对话记忆、摘要、长期记忆或全部。',
        },
        'scopes': {
          'type': 'array',
          'items': {
            'type': 'string',
            'enum': ['conversation', 'summary', 'long_term', 'all'],
          },
          'description': '可选。按多个记忆层级召回。',
        },
        'memoryScope': {
          'type': 'string',
          'enum': ['conversation', 'summary', 'long_term', 'all'],
          'description': 'scope 的记忆范围别名。',
        },
        '记忆范围': {
          'type': 'string',
          'description': 'memoryScope 的中文别名。',
        },
        'memory_scope': {
          'type': 'string',
          'enum': ['conversation', 'summary', 'long_term', 'all'],
          'description': 'memoryScope 的 snake_case 别名。',
        },
        'includeVisualReferences': {
          'type': 'boolean',
          'description': '可选。为 true 时额外召回项目长期记忆中的视觉参考/画风参考 note。',
        },
        'visualReferences': {
          'type': 'boolean',
          'description': 'includeVisualReferences 的自然语言别名。',
        },
        'include_visual_references': {
          'type': 'boolean',
          'description': 'includeVisualReferences 的 snake_case 别名。',
        },
        'visual_references': {
          'type': 'boolean',
          'description': 'visualReferences 的 snake_case 别名。',
        },
        'includeStyleReferences': {
          'type': 'boolean',
          'description': 'includeVisualReferences 的画风语义别名。',
        },
        'styleReferences': {
          'type': 'boolean',
          'description': 'visualReferences 的画风语义别名。',
        },
        '包含视觉参考': {
          'type': 'boolean',
          'description': 'includeVisualReferences 的中文别名。',
        },
        '视觉参考': {
          'type': 'boolean',
          'description': 'visualReferences 的中文别名。',
        },
        '包含画风参考': {
          'type': 'boolean',
          'description': 'includeStyleReferences 的中文别名。',
        },
        '画风参考': {
          'type': 'boolean',
          'description': 'styleReferences 的中文别名。',
        },
        'excludeIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。排除这些已读 memory id，避免重复返回同一条记忆。',
        },
        '排除记忆': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeMemoryIds 的中文别名。',
        },
        '排除记忆Ids': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeMemoryIds 的中文 id 别名。',
        },
        'excludeMemoryIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。excludeIds 的语义化别名。',
        },
        'excludeId': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'excludeIds 的单数别名。',
        },
        'seenMemoryIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。已读过的 memory id 列表，等价于 excludeIds。',
        },
        '已读记忆': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'seenMemoryIds 的中文别名。',
        },
        '已读记忆Ids': {
          'type': ['array', 'string'],
          'items': {'type': 'string'},
          'description': 'seenMemoryIds 的中文 id 别名。',
        },
        'seenIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。seenMemoryIds 的简写别名。',
        },
        'memoryIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。模型常用的已读 memory id 别名，等价于 excludeIds。',
        },
        'readMemoryIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。已读取 memory id 别名，等价于 excludeIds。',
        },
        'readIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。readMemoryIds 的简写别名。',
        },
        'previousMemoryIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选。上一轮已读 memory id 列表，等价于 excludeIds。',
        },
        'records': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
          },
          'description': '可选。上一轮 deepRetrieve 返回的 records，可原样传回以排除已读记忆。',
        },
        'seenRecords': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
          },
          'description': '可选。已读 records，等价于从 records 中提取 id 后加入 excludeIds。',
        },
        'readRecords': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
          },
          'description': '可选。已读取 records，等价于 seenRecords。',
        },
        '已读记录': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
          },
          'description': 'seenRecords 的中文别名。',
        },
        '排除记录': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
          },
          'description': 'excludeRecords 的中文别名。',
        },
        'previousRecords': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
          },
          'description': '可选。上一轮已读 records，等价于 seenRecords。',
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
        'novel_ids': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'novelIds 的 snake_case 别名，也兼容逗号分隔字符串。',
        },
        'chapterIds': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'novelIds 的章节语义别名。',
        },
        'chapter_ids': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'chapterIds 的 snake_case 别名。',
        },
        'chapterNo': {
          'type': 'integer',
          'description': '按导入顺序的自然章节号，例如 1 表示第一章。',
        },
        'chapterNos': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'chapterNo 的数组形式。',
        },
        'chapterIndex': {
          'type': 'integer',
          'description': 'chapterNo 的 ToonFlow 章节索引别名。',
        },
        'chapterIndexes': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'chapterIndex 的数组形式。',
        },
        'chapter_no': {
          'type': 'integer',
          'description': 'chapterNo 的 snake_case 别名。',
        },
        'chapter_nos': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'chapterNos 的 snake_case 别名。',
        },
        'chapterName': {
          'type': 'string',
          'description': '按章节名称精确匹配。',
        },
        'chapterNames': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'chapterName 的数组形式，也兼容逗号分隔字符串。',
        },
        'chapterTitle': {
          'type': 'string',
          'description': 'chapterName 的标题语义别名。',
        },
        'chapterTitles': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'chapterTitle 的数组形式。',
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
        'script_ids': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'scriptIds 的 snake_case 别名，也兼容逗号分隔字符串。',
        },
        'episodeIds': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'scriptIds 的集数语义别名。',
        },
        'episode_ids': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'episodeIds 的 snake_case 别名。',
        },
        'episodeNo': {
          'type': 'integer',
          'description': '按剧本列表顺序的自然集号，例如 2 表示第二集。',
        },
        'episodeNos': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'episodeNo 的数组形式。',
        },
        'scriptNo': {
          'type': 'integer',
          'description': 'episodeNo 的剧本语义别名。',
        },
        'scriptNos': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'scriptNo 的数组形式。',
        },
        'scriptName': {
          'type': 'string',
          'description': '按剧本名称精确匹配。',
        },
        'scriptNames': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'scriptName 的数组形式，也兼容逗号分隔字符串。',
        },
        'episodeName': {
          'type': 'string',
          'description': 'scriptName 的集数语义别名。',
        },
        'episodeNames': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'episodeName 的数组形式。',
        },
        'scriptTitle': {
          'type': 'string',
          'description': 'scriptName 的标题语义别名。',
        },
        'episodeTitle': {
          'type': 'string',
          'description': 'episodeName 的标题语义别名。',
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
        'script_id': {
          'type': 'integer',
          'description': 'scriptId 的 snake_case 别名。',
        },
        'episodeId': {
          'type': 'integer',
          'description': 'scriptId 的集数语义别名。',
        },
        'episode_id': {
          'type': 'integer',
          'description': 'episodeId 的 snake_case 别名。',
        },
        'episodeNo': {
          'type': 'integer',
          'description': '按剧本列表顺序的自然集号，例如 2 表示第二集。',
        },
        'scriptNo': {
          'type': 'integer',
          'description': 'episodeNo 的剧本语义别名。',
        },
        'scriptName': {
          'type': 'string',
          'description': '按剧本名称精确匹配。',
        },
        'episodeName': {
          'type': 'string',
          'description': 'scriptName 的集数语义别名。',
        },
        'scriptTitle': {
          'type': 'string',
          'description': 'scriptName 的标题语义别名。',
        },
        'episodeTitle': {
          'type': 'string',
          'description': 'episodeName 的标题语义别名。',
        },
      },
    },
  ),
  AgentToolDef(
    name: 'generate_shot_images',
    description: '为指定剧本的分镜生成首帧图。不传 storyboardIds 时对该剧本全部分镜执行。',
    schema: const {
      'type': 'object',
      'properties': {
        'scriptId': {'type': 'integer'},
        'script_id': {
          'type': 'integer',
          'description': 'scriptId 的 snake_case 别名。',
        },
        'episodeId': {
          'type': 'integer',
          'description': 'scriptId 的集数语义别名。',
        },
        'episode_id': {
          'type': 'integer',
          'description': 'episodeId 的 snake_case 别名。',
        },
        'episodeNo': {
          'type': 'integer',
          'description': '按剧本列表顺序的自然集号，例如 2 表示第二集。',
        },
        'scriptNo': {
          'type': 'integer',
          'description': 'episodeNo 的剧本语义别名。',
        },
        'scriptName': {
          'type': 'string',
          'description': '按剧本名称精确匹配。',
        },
        'episodeName': {
          'type': 'string',
          'description': 'scriptName 的集数语义别名。',
        },
        'scriptTitle': {
          'type': 'string',
          'description': 'scriptName 的标题语义别名。',
        },
        'episodeTitle': {
          'type': 'string',
          'description': 'episodeName 的标题语义别名。',
        },
        'storyboardIds': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
        'storyboard_ids': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'storyboardIds 的 snake_case 别名，也兼容逗号分隔字符串。',
        },
        'shotIds': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'storyboardIds 的镜头语义别名。',
        },
        'shot_ids': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'shotIds 的 snake_case 别名。',
        },
        'shotNo': {
          'type': 'integer',
          'description': '按当前剧本分镜顺序的自然镜头号，例如 2 表示第二镜。',
        },
        'shotNos': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'shotNo 的数组形式。',
        },
        'storyboardNo': {
          'type': 'integer',
          'description': 'shotNo 的分镜语义别名。',
        },
        'storyboardNos': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'storyboardNo 的数组形式。',
        },
        'storyboardIndex': {
          'type': 'integer',
          'description': 'shotNo 的索引语义别名，按分镜顺序匹配。',
        },
        'storyboardIndexes': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'storyboardIndex 的数组形式。',
        },
      },
    },
  ),
  AgentToolDef(
    name: 'analyze_reference_image',
    description: '用多模态文本模型分析本地参考图，提炼画风、角色外观、场景构图或可复用生图关键词。'
        '可传 imagePath/imageRelPath，或用 assetName/assetId/imageId/storyboardId 定位项目内图片；'
        '复数字段可一次分析多张参考图。',
    schema: const {
      'type': 'object',
      'properties': {
        'prompt': {
          'type': 'string',
          'description': '希望视觉模型回答的问题，例如“提炼角色外观和画风关键词”。',
        },
        'question': {
          'type': 'string',
          'description': 'prompt 的自然别名。',
        },
        'query': {
          'type': 'string',
          'description': 'prompt 的查询语义别名。',
        },
        '问题': {
          'type': 'string',
          'description': 'prompt 的中文别名。',
        },
        '提示词': {
          'type': 'string',
          'description': 'prompt 的中文别名。',
        },
        'remember': {
          'type': 'boolean',
          'description': '可选。为 true 时，将视觉分析结果保存为项目长期记忆。',
        },
        'saveMemory': {
          'type': 'boolean',
          'description': 'remember 的自然语言别名。',
        },
        'save_memory': {
          'type': 'boolean',
          'description': 'saveMemory 的 snake_case 别名。',
        },
        '记住': {
          'type': 'boolean',
          'description': 'remember 的中文别名。',
        },
        '保存记忆': {
          'type': 'boolean',
          'description': 'remember 的中文别名。',
        },
        '写入记忆': {
          'type': 'boolean',
          'description': 'remember 的中文别名。',
        },
        'memoryName': {
          'type': 'string',
          'description': '可选。保存长期记忆时使用的名称。',
        },
        'memory_name': {
          'type': 'string',
          'description': 'memoryName 的 snake_case 别名。',
        },
        '记忆名称': {
          'type': 'string',
          'description': 'memoryName 的中文别名。',
        },
        'title': {
          'type': 'string',
          'description': 'memoryName 的标题语义别名。',
        },
        '标题': {
          'type': 'string',
          'description': 'memoryName 的中文标题别名。',
        },
        'scriptId': {
          'type': 'integer',
          'description': '可选。当前剧本 id，用于解析 A001 这类 ToonFlow 资产引用。',
        },
        'script_id': {
          'type': 'integer',
          'description': 'scriptId 的 snake_case 别名。',
        },
        'imagePath': {
          'type': 'string',
          'description': '本地图片绝对路径。',
        },
        'imagePaths': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '本地图片绝对路径列表，用于一次分析多张参考图。',
        },
        'imageRelPath': {
          'type': 'string',
          'description': '媒体库相对路径。',
        },
        'imageRelPaths': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '媒体库相对路径列表，用于一次分析多张参考图。',
        },
        'filePath': {
          'type': 'string',
          'description': 'imagePath/imageRelPath 的常见别名。',
        },
        'filePaths': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'imagePaths/imageRelPaths 的常见列表别名。',
        },
        'assetId': {
          'type': 'integer',
          'description': '项目资产 id，使用该资产当前选中的参考图。',
        },
        'assetIds': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': '项目资产 id 列表，用于一次分析多张资产参考图。',
        },
        'assetName': {
          'type': 'string',
          'description': '按项目资产名称精确匹配，使用该资产当前选中的参考图。',
        },
        'assetNames': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '项目资产名称列表，用于一次分析多张资产参考图。',
        },
        'assetRef': {
          'type': 'string',
          'description': 'ToonFlow 资产引用，例如 A001；传 scriptId 时按当前剧本资产表解析。',
        },
        'assetRefs': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'ToonFlow 资产引用列表，例如 ["A001","A002"]。',
        },
        'projectArtStyle': {
          'type': 'boolean',
          'description': '为 true 时，分析当前项目 artStyle 对应的视觉手册或画风封面图。',
        },
        'project_art_style': {
          'type': 'boolean',
          'description': 'projectArtStyle 的 snake_case 别名。',
        },
        'useProjectArtStyle': {
          'type': 'boolean',
          'description': 'projectArtStyle 的自然语言别名。',
        },
        'use_project_art_style': {
          'type': 'boolean',
          'description': 'useProjectArtStyle 的 snake_case 别名。',
        },
        '项目画风': {
          'type': 'boolean',
          'description': 'projectArtStyle 的中文别名。',
        },
        '当前画风': {
          'type': 'boolean',
          'description': 'projectArtStyle 的中文别名。',
        },
        'artStyleName': {
          'type': 'string',
          'description': '按视觉手册名或画风库名称匹配封面图。',
        },
        'art_style_name': {
          'type': 'string',
          'description': 'artStyleName 的 snake_case 别名。',
        },
        'artStyleNames': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'artStyleName 的数组形式。',
        },
        'art_style_names': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'artStyleNames 的 snake_case 别名。',
        },
        'visualManualName': {
          'type': 'string',
          'description': '按视觉手册名称匹配封面图。',
        },
        'visual_manual_name': {
          'type': 'string',
          'description': 'visualManualName 的 snake_case 别名。',
        },
        'visualManualNames': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'visualManualName 的数组形式。',
        },
        'visual_manual_names': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'visualManualNames 的 snake_case 别名。',
        },
        'visualManual': {
          'type': 'string',
          'description': 'visualManualName 的常见别名。',
        },
        'visualManuals': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'visualManualNames 的常见别名。',
        },
        'styleName': {
          'type': 'string',
          'description': 'artStyleName 的自然语言别名。',
        },
        'style_name': {
          'type': 'string',
          'description': 'styleName 的 snake_case 别名。',
        },
        'styleNames': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'styleName 的数组形式。',
        },
        'style_names': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'styleNames 的 snake_case 别名。',
        },
        'artStyle': {
          'type': 'string',
          'description': 'artStyleName 的常见别名。',
        },
        'artStyles': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'artStyleNames 的常见别名。',
        },
        '画风': {
          'type': 'string',
          'description': 'artStyleName/styleName 的中文别名。',
        },
        '画风名称': {
          'type': 'string',
          'description': 'artStyleName/styleName 的中文别名。',
        },
        '视觉手册': {
          'type': 'string',
          'description': 'visualManualName 的中文别名。',
        },
        '视觉手册名称': {
          'type': 'string',
          'description': 'visualManualName 的中文别名。',
        },
        'imageId': {
          'type': 'integer',
          'description': 'o_image 图片 id。',
        },
        'imageIds': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'o_image 图片 id 列表。',
        },
        'storyboardId': {
          'type': 'integer',
          'description': '分镜 id，使用分镜首帧图。',
        },
        'storyboardIds': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': '分镜 id 列表，逐个使用分镜首帧图。',
        },
        'shotNo': {
          'type': 'integer',
          'description': '按当前剧本分镜顺序的自然镜头号，例如 2 表示第二镜。',
        },
        'shotNos': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'shotNo 的数组形式。',
        },
        'storyboardNo': {
          'type': 'integer',
          'description': 'shotNo 的分镜语义别名。',
        },
        'storyboardNos': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'storyboardNo 的数组形式。',
        },
        'storyboardIndex': {
          'type': 'integer',
          'description': 'shotNo 的索引语义别名，按分镜顺序匹配。',
        },
        'storyboardIndexes': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'storyboardIndex 的数组形式。',
        },
      },
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
        'script_id': {
          'type': 'integer',
          'description': 'scriptId 的 snake_case 别名。',
        },
        'episodeId': {
          'type': 'integer',
          'description': 'scriptId 的集数语义别名。',
        },
        'episode_id': {
          'type': 'integer',
          'description': 'episodeId 的 snake_case 别名。',
        },
        'episodeNo': {
          'type': 'integer',
          'description': '按剧本列表顺序的自然集号，例如 2 表示第二集。',
        },
        'scriptNo': {
          'type': 'integer',
          'description': 'episodeNo 的剧本语义别名。',
        },
        'scriptName': {
          'type': 'string',
          'description': '按剧本名称精确匹配。',
        },
        'episodeName': {
          'type': 'string',
          'description': 'scriptName 的集数语义别名。',
        },
        'scriptTitle': {
          'type': 'string',
          'description': 'scriptName 的标题语义别名。',
        },
        'episodeTitle': {
          'type': 'string',
          'description': 'episodeName 的标题语义别名。',
        },
        'storyboardIds': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
        'storyboard_ids': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'storyboardIds 的 snake_case 别名，也兼容逗号分隔字符串。',
        },
        'shotIds': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'storyboardIds 的镜头语义别名。',
        },
        'shot_ids': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'shotIds 的 snake_case 别名。',
        },
        'shotNo': {
          'type': 'integer',
          'description': '按当前剧本分镜顺序的自然镜头号，例如 2 表示第二镜。',
        },
        'shotNos': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'shotNo 的数组形式。',
        },
        'storyboardNo': {
          'type': 'integer',
          'description': 'shotNo 的分镜语义别名。',
        },
        'storyboardNos': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'storyboardNo 的数组形式。',
        },
        'storyboardIndex': {
          'type': 'integer',
          'description': 'shotNo 的索引语义别名，按分镜顺序匹配。',
        },
        'storyboardIndexes': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'storyboardIndex 的数组形式。',
        },
      },
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
        'role_ids': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'roleIds 的 snake_case 别名，也兼容逗号分隔字符串。',
        },
        'assetIds': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'roleIds 的资产语义别名。',
        },
        'asset_ids': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'assetIds 的 snake_case 别名。',
        },
        'roleNo': {
          'type': 'integer',
          'description': '按角色列表顺序的自然角色号，例如 2 表示第二个角色。',
        },
        'roleNos': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'roleNo 的数组形式。',
        },
        'roleIndex': {
          'type': 'integer',
          'description': 'roleNo 的索引语义别名，按角色列表顺序匹配。',
        },
        'roleIndexes': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'roleIndex 的数组形式。',
        },
        'assetNo': {
          'type': 'integer',
          'description': 'roleNo 的资产语义别名。',
        },
        'assetNos': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'assetNo 的数组形式。',
        },
        'roleName': {
          'type': 'string',
          'description': '按角色名称精确匹配。',
        },
        'roleNames': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'roleName 的数组形式，也兼容逗号分隔字符串。',
        },
        'assetName': {
          'type': 'string',
          'description': 'roleName 的资产语义别名。',
        },
        'assetNames': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'assetName 的数组形式。',
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
        'script_id': {
          'type': 'integer',
          'description': 'scriptId 的 snake_case 别名。',
        },
        'episodeId': {
          'type': 'integer',
          'description': 'scriptId 的集数语义别名。',
        },
        'episode_id': {
          'type': 'integer',
          'description': 'episodeId 的 snake_case 别名。',
        },
        'episodeNo': {
          'type': 'integer',
          'description': '按剧本列表顺序的自然集号，例如 2 表示第二集。',
        },
        'scriptNo': {
          'type': 'integer',
          'description': 'episodeNo 的剧本语义别名。',
        },
        'scriptName': {
          'type': 'string',
          'description': '按剧本名称精确匹配。',
        },
        'episodeName': {
          'type': 'string',
          'description': 'scriptName 的集数语义别名。',
        },
        'scriptTitle': {
          'type': 'string',
          'description': 'scriptName 的标题语义别名。',
        },
        'episodeTitle': {
          'type': 'string',
          'description': 'episodeName 的标题语义别名。',
        },
      },
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
          'Function': const _CustomJsBuiltin('Function'),
          'JSON': const _CustomJsBuiltin('JSON'),
          'Map': const _CustomJsBuiltin('Map'),
          'Math': const _CustomJsBuiltin('Math'),
          'Number': const _CustomJsBuiltin('Number'),
          'Object': const _CustomJsBuiltin('Object'),
          'Promise': const _CustomJsBuiltin('Promise'),
          'RegExp': const _CustomJsBuiltin('RegExp'),
          'Set': const _CustomJsBuiltin('Set'),
          'String': const _CustomJsBuiltin('String'),
          'isFinite': const _CustomJsBuiltin('isFinite'),
          'isNaN': const _CustomJsBuiltin('isNaN'),
          'parseFloat': const _CustomJsBuiltin('parseFloat'),
          'parseInt': const _CustomJsBuiltin('parseInt'),
          'structuredClone': const _CustomJsBuiltin('structuredClone'),
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
        _CustomJsStatementResult? pendingResult;
        Object? pendingError;
        var hasPendingError = false;
        try {
          pendingResult = _runStatements(tryStatement.body);
        } catch (error) {
          final catchBody = tryStatement.catchBody;
          if (catchBody == null) {
            pendingError = error;
            hasPendingError = true;
          } else {
            final bindings = tryStatement.errorName == null
                ? <String, Object?>{}
                : <String, Object?>{
                    tryStatement.errorName!: _customJsCatchValue(error),
                  };
            pendingResult = _withScopeBindings(
              bindings,
              () => _runStatements(catchBody),
            );
          }
        }
        final finallyBody = tryStatement.finallyBody;
        if (finallyBody != null) {
          final finallyResult = _runStatements(finallyBody);
          if (finallyResult != null) return finallyResult;
        }
        if (hasPendingError) {
          throw pendingError!;
        }
        if (pendingResult != null) return pendingResult;
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
    if (index >= source.length) return null;
    late final String whenTrue;
    if (source[index] == '{') {
      final trueBlock = _readBalanced(source, index, '{', '}');
      whenTrue = trueBlock.text;
      index = _skipWhitespace(source, trueBlock.end);
    } else {
      whenTrue = source.substring(index).trim();
      index = source.length;
    }
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
      whenTrue: whenTrue,
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
    String? errorName;
    String? catchBody;
    if (_startsWithWord(source, index, 'catch')) {
      index = _skipWhitespace(source, index + 'catch'.length);
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
      final rawCatchBody = _readBalanced(source, index, '{', '}');
      catchBody = rawCatchBody.text;
      index = _skipWhitespace(source, rawCatchBody.end);
    }
    String? finallyBody;
    if (_startsWithWord(source, index, 'finally')) {
      index = _skipWhitespace(source, index + 'finally'.length);
      if (index >= source.length || source[index] != '{') return null;
      final rawFinallyBody = _readBalanced(source, index, '{', '}');
      finallyBody = rawFinallyBody.text;
      index = _skipWhitespace(source, rawFinallyBody.end);
    }
    if (catchBody == null && finallyBody == null) return null;
    if (_trimTrailingSemicolon(source.substring(index)).trim().isNotEmpty) {
      return null;
    }
    return _CustomJsTryStatement(
      body: body.text,
      errorName: errorName,
      catchBody: catchBody,
      finallyBody: finallyBody,
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
    final functionStart = _readFunctionKeywordStart(source);
    if (functionStart == null) return null;
    var index = _skipWhitespace(source, functionStart + 'function'.length);
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
    final functionStart = _readFunctionKeywordStart(source);
    if (functionStart == null) return null;
    var index = _skipWhitespace(source, functionStart + 'function'.length);
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

  _CustomJsFunction? _readArrowFunctionExpression(
    String expression,
    String fallbackName,
  ) {
    final source = _trimTrailingSemicolon(expression.trim());
    final arrow = _findTopLevelArrow(source);
    if (arrow < 0) return null;
    final paramsSource = source.substring(0, arrow).trim();
    final bodySource = source.substring(arrow + 2).trim();
    if (paramsSource.isEmpty || bodySource.isEmpty) return null;
    final params = _parseCallbackParams(paramsSource, fallbackName);
    final blockBody = _literalInner(bodySource, '{', '}');
    return _CustomJsFunction(
      name: fallbackName,
      params: params,
      body: blockBody ?? 'return $bodySource',
    );
  }

  int? _readFunctionKeywordStart(String source) {
    if (_startsWithWord(source, 0, 'function')) return 0;
    if (!_startsWithWord(source, 0, 'async')) return null;
    final index = _skipWhitespace(source, 'async'.length);
    return _startsWithWord(source, index, 'function') ? index : null;
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
    if (container is _CustomJsRegExp && key == 'lastIndex') {
      return container.lastIndex;
    }
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
    if (container is _CustomJsRegExp && key == 'lastIndex') {
      container.lastIndex = _regExpLastIndex(value);
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
    if (_startsWithWord(expr, 0, 'await')) {
      final awaited = expr.substring('await'.length).trim();
      if (awaited.isEmpty) {
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_await',
        });
      }
      return _unwrapPromiseValue(_evaluate(awaited));
    }
    final grouped = _unwrapOuterParens(expr);
    if (grouped != null) return _evaluate(grouped);
    final assignmentExpression = _evaluateAssignmentExpression(expr);
    if (assignmentExpression is! _CustomJsNoAssignment) {
      return assignmentExpression;
    }
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
    final arrowFunctionExpression =
        _readArrowFunctionExpression(expr, 'anonymous');
    if (arrowFunctionExpression != null) return arrowFunctionExpression;
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
    if (expr == 'NaN') return double.nan;
    if (expr == 'Infinity' || expr == '+Infinity') return double.infinity;
    if (expr == '-Infinity') return double.negativeInfinity;
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

    final instanceOf = _readTopLevelInstanceofOperator(expr);
    if (instanceOf != null) {
      return _customJsInstanceOf(
        _evaluate(instanceOf.left),
        _evaluate(instanceOf.right),
      );
    }

    final typeofExpression = _evaluateTypeofExpression(expr);
    if (typeofExpression != null) return typeofExpression;

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

  String? _evaluateTypeofExpression(String expression) {
    if (!_startsWithWord(expression, 0, 'typeof')) return null;
    final operand = expression.substring('typeof'.length).trim();
    if (operand.isEmpty) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_typeof',
      });
    }
    final identifier = _readIdentifier(operand, 0);
    if (identifier != null &&
        identifier.end == operand.length &&
        !_customJsTypeofLiteralIdentifiers.contains(identifier.text) &&
        !_scope.containsKey(identifier.text)) {
      return 'undefined';
    }
    return _customJsTypeOf(_evaluate(operand));
  }

  String _customJsTypeOf(Object? value) {
    if (value == null) return 'object';
    if (value is bool) return 'boolean';
    if (value is num) return 'number';
    if (value is String) return 'string';
    if (value is _CustomJsFunction || value is _CustomJsBuiltin) {
      return 'function';
    }
    return 'object';
  }

  String _objectPrototypeToString(Object? value) {
    var tag = 'Object';
    if (value == null) {
      tag = 'Null';
    } else if (value is bool) {
      tag = 'Boolean';
    } else if (value is num) {
      tag = 'Number';
    } else if (value is String) {
      tag = 'String';
    } else if (value is List) {
      tag = 'Array';
    } else if (value is _CustomJsDate) {
      tag = 'Date';
    } else if (value is _CustomJsMap) {
      tag = 'Map';
    } else if (value is Set) {
      tag = 'Set';
    } else if (value is _CustomJsRegExp) {
      tag = 'RegExp';
    } else if (value is _CustomJsError) {
      tag = 'Error';
    } else if (value is _CustomJsFunction || value is _CustomJsBuiltin) {
      tag = 'Function';
    }
    return '[object $tag]';
  }

  bool _customJsInstanceOf(Object? value, Object? constructor) {
    if (constructor is! _CustomJsBuiltin) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_instanceof',
      });
    }
    return switch (constructor.name) {
      'Array' => value is List,
      'Date' => value is _CustomJsDate,
      'Map' => value is _CustomJsMap,
      'Set' => value is Set,
      'RegExp' => value is _CustomJsRegExp,
      'Error' => value is _CustomJsError,
      'Function' => value is _CustomJsFunction || value is _CustomJsBuiltin,
      'Object' => value != null &&
          (value is Map ||
              value is List ||
              value is Set ||
              value is _CustomJsDate ||
              value is _CustomJsMap ||
              value is _CustomJsRegExp ||
              value is _CustomJsError ||
              value is _CustomJsFunction ||
              value is _CustomJsBuiltin),
      'String' || 'Number' || 'Boolean' => false,
      _ => throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_instanceof_constructor',
          'constructor': constructor.name,
        }),
    };
  }

  Object? _evaluateAssignmentExpression(String expression) {
    final equals = _findTopLevelDefaultEquals(expression);
    if (equals < 0) return const _CustomJsNoAssignment();
    final left = expression.substring(0, equals).trim();
    final right = expression.substring(equals + 1).trim();
    if (left.isEmpty || right.isEmpty) return const _CustomJsNoAssignment();
    final identifier = _readIdentifier(left, 0);
    if (identifier != null && identifier.end == left.length) {
      if (!_scope.containsKey(identifier.text)) {
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_unknown_variable',
          'expression': identifier.text,
        });
      }
      final value = _evaluate(right);
      _scope[identifier.text] = value;
      return value;
    }
    final target = _readAssignmentTarget(left);
    if (target == null) return const _CustomJsNoAssignment();
    final value = _evaluate(right);
    _writeAssignmentTarget(target, value);
    return value;
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
      if (expression.startsWith('?.(', index)) {
        if (value == null) return null;
        final call = _readBalanced(expression, index + 2, '(', ')');
        final args = _splitTopLevel(call.text, ',')
            .where((part) => part.trim().isNotEmpty)
            .map((part) => part.trim())
            .toList();
        value = _callFunction(value, 'anonymous', args);
        index = call.end;
        continue;
      }
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
        if (expression.startsWith('?.(', index)) {
          final call = _readBalanced(expression, index + 2, '(', ')');
          final args = _splitTopLevel(call.text, ',')
              .where((part) => part.trim().isNotEmpty)
              .map((part) => part.trim())
              .toList();
          value = _callOptionalMethodOrProperty(value, prop.text, args);
          index = call.end;
          continue;
        }
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
        if (expression.startsWith('?.(', index)) {
          final call = _readBalanced(expression, index + 2, '(', ')');
          final args = _splitTopLevel(call.text, ',')
              .where((part) => part.trim().isNotEmpty)
              .map((part) => part.trim())
              .toList();
          value = _callOptionalMethodOrProperty(value, prop.text, args);
          index = call.end;
          continue;
        }
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
    if (value is _CustomJsFunction &&
        (method == 'call' || method == 'apply' || method == 'bind')) {
      return _callCustomFunctionMethod(value, method, args);
    }
    if (value is _CustomJsBuiltin) {
      return _callBuiltinMethod(value.name, method, args);
    }
    if (value is _CustomJsDate) {
      return _callDateInstanceMethod(value, method, args);
    }
    if (value is _CustomJsMap) {
      return _callMapInstanceMethod(value, method, args);
    }
    if (value is _CustomJsPromiseValue) {
      return _callPromiseInstanceMethod(value, method, args);
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
        if (args.length > 2) _badMethodArgs(method);
        final text = '${value ?? ''}';
        if (args.isEmpty) return [text];
        final pieces = _splitString(text, _evaluate(args.first));
        if (args.length == 1) return pieces;
        final limit = _toInt(_evaluate(args[1]));
        if (limit <= 0) return const <String>[];
        return pieces.length <= limit ? pieces : pieces.sublist(0, limit);
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
        final depth = args.isEmpty ? 1 : _flatDepth(_evaluate(args.single));
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
      case 'findLast':
        if (args.length != 1 || value is! Iterable) _badMethodArgs(method);
        final items = value is List ? value : value.toList();
        for (var index = items.length - 1; index >= 0; index--) {
          final item = items[index];
          final matched = _evaluateCallback(
            method,
            args.single,
            item,
            index,
            source: items,
          );
          if (_isTruthy(matched)) return item;
        }
        return null;
      case 'findLastIndex':
        if (args.length != 1 || value is! Iterable) _badMethodArgs(method);
        final items = value is List ? value : value.toList();
        for (var index = items.length - 1; index >= 0; index--) {
          final matched = _evaluateCallback(
            method,
            args.single,
            items[index],
            index,
            source: items,
          );
          if (_isTruthy(matched)) return index;
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
      case 'reduceRight':
        if (args.isEmpty || args.length > 2 || value is! Iterable) {
          _badMethodArgs(method);
        }
        final items = value.toList();
        if (args.length == 1 && items.isEmpty) {
          throw EngineException(errLlmFormat, {
            'reason': 'custom_skill_reduce_right_empty',
          });
        }
        Object? accumulator =
            args.length == 2 ? _evaluate(args[1]) : items.last;
        final startIndex =
            args.length == 2 ? items.length - 1 : items.length - 2;
        for (var index = startIndex; index >= 0; index--) {
          accumulator = _evaluateReduceCallback(
            method,
            args.first,
            accumulator,
            items[index],
            index,
            items,
          );
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
      case 'toSorted':
        if (args.length > 1 || value is! Iterable || value is String) {
          _badMethodArgs(method);
        }
        final sorted = value.toList();
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
      case 'toReversed':
        if (args.isNotEmpty || value is! Iterable || value is String) {
          _badMethodArgs(method);
        }
        return value.toList().reversed.toList();
      case 'toSpliced':
        if (args.isEmpty || value is! Iterable || value is String) {
          _badMethodArgs(method);
        }
        final copied = value.toList();
        _spliceList(copied, args);
        return copied;
      case 'with':
        if (args.length != 2 || value is! Iterable || value is String) {
          _badMethodArgs(method);
        }
        final copied = value.toList();
        final index = _normalizeAtIndex(
          _toInt(_evaluate(args.first)),
          copied.length,
        );
        if (index == null) _badMethodArgs(method);
        copied[index] = _evaluate(args[1]);
        return copied;
      case 'keys':
      case 'values':
      case 'entries':
        if (args.isNotEmpty || value is! Iterable || value is String) {
          _badMethodArgs(method);
        }
        return _arrayIteratorValues(value.toList(), method);
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

  Object? _callOptionalMethodOrProperty(
    Object? value,
    String method,
    List<String> args,
  ) {
    if (_hasCustomJsInstanceMethod(value, method)) {
      return _callMethod(value, method, args);
    }
    final propertyValue = _readOptionalProperty(value, method);
    if (propertyValue == null) return null;
    return _callFunction(propertyValue, method, args);
  }

  bool _hasCustomJsInstanceMethod(Object? value, String method) {
    if (value is String) return _customJsStringInstanceMethods.contains(method);
    if (value is num) return _customJsNumberInstanceMethods.contains(method);
    if (value is Set) {
      return _customJsSetMethods.contains(method) ||
          _customJsIterableInstanceMethods.contains(method);
    }
    if (value is Iterable) {
      return _customJsIterableInstanceMethods.contains(method);
    }
    return false;
  }

  Object? _readOptionalProperty(Object? value, String property) {
    try {
      return _readProperty(value, property);
    } on EngineException catch (error) {
      if (error.errKey == errLlmFormat &&
          error.errParams['reason'] == 'custom_skill_property') {
        return null;
      }
      rethrow;
    }
  }

  List<Object?> _arrayIteratorValues(List<Object?> items, String method) {
    if (method == 'values') return List<Object?>.from(items);
    if (method == 'entries') {
      return [
        for (var index = 0; index < items.length; index++) [index, items[index]]
      ];
    }
    return [for (var index = 0; index < items.length; index++) index];
  }

  List<String> _splitString(String text, Object? separator) {
    if (separator is _CustomJsRegExp) return text.split(separator.regExp);
    final value = _stringifyInterpolation(separator);
    return value.isEmpty ? text.split('') : text.split(value);
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

  int _flatDepth(Object? value) {
    final depth = value is num ? value : _toNum(value);
    if (depth.isNaN || depth <= 0) return 0;
    if (depth.isInfinite) return 10000;
    return depth.toInt();
  }

  Object? _matchString(String text, Object? matcher) {
    if (matcher is _CustomJsRegExp) {
      final matches = matcher.regExp.allMatches(text).toList();
      if (matches.isEmpty) return null;
      if (matcher.global) {
        return [for (final match in matches) match.group(0) ?? ''];
      }
      final match = matches.first;
      return _customJsMatch(text, match);
    }
    final needle = _stringifyInterpolation(matcher);
    if (needle.isEmpty) return [''];
    final index = text.indexOf(needle);
    return index >= 0
        ? _CustomJsMatch([needle], index: index, input: text, groups: null)
        : null;
  }

  List<List<Object?>> _matchAllString(String text, Object? matcher) {
    if (matcher is _CustomJsRegExp) {
      return [
        for (final match in matcher.regExp.allMatches(text))
          _customJsMatch(text, match),
      ];
    }
    final needle = _stringifyInterpolation(matcher);
    if (needle.isEmpty) return const [];
    final matches = <List<Object?>>[];
    var start = 0;
    while (start <= text.length) {
      final index = text.indexOf(needle, start);
      if (index < 0) break;
      matches.add(
        _CustomJsMatch([needle], index: index, input: text, groups: null),
      );
      start = index + needle.length;
    }
    return matches;
  }

  _CustomJsMatch _customJsMatch(String input, RegExpMatch match) =>
      _CustomJsMatch(
        [
          for (var index = 0; index <= match.groupCount; index++)
            match.group(index)
        ],
        index: match.start,
        input: input,
        groups: _customJsMatchGroups(match),
      );

  Map<String, Object?>? _customJsMatchGroups(RegExpMatch match) {
    final groups = <String, Object?>{
      for (final name in match.groupNames) name: match.namedGroup(name),
    };
    return groups.isEmpty ? null : groups;
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
    final namedGroups =
        match is RegExpMatch ? _customJsMatchGroups(match) : null;
    final values = <Object?>[
      match.group(0),
      for (var index = 1; index <= match.groupCount; index++)
        match.group(index),
      match.start,
      source,
      if (namedGroups != null) namedGroups,
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
      if (next == '<' && match is RegExpMatch) {
        final end = replacement.indexOf('>', index + 2);
        if (end > index + 2) {
          final name = replacement.substring(index + 2, end);
          if (match.groupNames.contains(name)) {
            buffer.write(match.namedGroup(name) ?? '');
            index = end;
            continue;
          }
        }
      }
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

  Object? _callCustomFunctionMethod(
    _CustomJsFunction function,
    String method,
    List<String> args,
  ) {
    final values = _evaluateCallArguments(args);
    switch (method) {
      case 'call':
        return _callCustomFunctionWithValues(
          function,
          values.length <= 1 ? const <Object?>[] : values.sublist(1),
        );
      case 'apply':
        if (values.length > 2) _badMethodArgs(method);
        if (values.length < 2 || values[1] == null) {
          return _callCustomFunctionWithValues(function, const <Object?>[]);
        }
        final argumentList = values[1];
        if (argumentList is! Iterable || argumentList is String) {
          _badMethodArgs(method);
        }
        return _callCustomFunctionWithValues(
          function,
          List<Object?>.from(argumentList),
        );
      case 'bind':
        return _CustomJsFunction(
          name: function.name,
          params: function.params,
          body: function.body,
          boundValues: values.length <= 1
              ? function.boundValues
              : List<Object?>.unmodifiable([
                  ...function.boundValues,
                  ...values.skip(1),
                ]),
        );
      default:
        _badMethodArgs(method);
    }
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
    final callValues = function.boundValues.isEmpty
        ? values
        : <Object?>[...function.boundValues, ...values];
    final bindings = <String, Object?>{};
    for (var i = 0; i < function.params.length; i++) {
      _bindCallbackParam(
        function.params[i],
        i < callValues.length ? callValues[i] : null,
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
      case 'structuredClone':
        if (values.length != 1) _badMethodArgs(objectName);
        return _structuredClone(values.single);
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

  Object? _structuredClone(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': _structuredClone(entry.value),
      };
    }
    if (value is _CustomJsMap) {
      return _CustomJsMap(<Object?, Object?>{
        for (final entry in value.values.entries)
          _structuredClone(entry.key): _structuredClone(entry.value),
      });
    }
    if (value is Set) {
      return <Object?>{for (final item in value) _structuredClone(item)};
    }
    if (value is Iterable && value is! String) {
      return [for (final item in value) _structuredClone(item)];
    }
    if (value is _CustomJsDate) {
      return _CustomJsDate(value.value);
    }
    if (value is _CustomJsError) {
      return _CustomJsError(value.message);
    }
    return value;
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
    if (objectName == 'Object.prototype.hasOwnProperty' && method == 'call') {
      final values = _evaluateCallArguments(args);
      if (values.length != 2) _badMethodArgs(method);
      return _hasOwnProperty(values.first, values[1]);
    }
    if (objectName == 'Object.prototype.toString' && method == 'call') {
      final values = _evaluateCallArguments(args);
      if (values.length != 1) _badMethodArgs(method);
      return _objectPrototypeToString(values.single);
    }
    switch (objectName) {
      case 'Array':
        if (method == 'isArray') {
          if (args.length != 1) _badMethodArgs(method);
          return _evaluate(args.single) is List;
        }
        if (method == 'from') return _arrayFrom(args);
        if (method == 'of') return _evaluateCallArguments(args);
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
      case 'Map':
        if (method == 'groupBy') return _mapGroupBy(args);
        break;
      case 'Object':
        return _callObjectMethod(method, args);
      case 'Promise':
        return _callPromiseMethod(method, args);
    }
    throw EngineException(errLlmFormat, {
      'reason': 'custom_skill_builtin_method',
      'object': objectName,
      'method': method,
    });
  }

  Object? _callPromiseMethod(String method, List<String> args) {
    switch (method) {
      case 'all':
        if (args.length != 1) _badMethodArgs(method);
        final values = <Object?>[];
        for (final value in _promiseIterableValues(args.single, method)) {
          if (value is _CustomJsPromiseValue && value.rejected) {
            return _CustomJsPromiseValue.rejected(value.reason);
          }
          values.add(_unwrapPromiseValue(value));
        }
        return _CustomJsPromiseValue(values);
      case 'allSettled':
        if (args.length != 1) _badMethodArgs(method);
        return _CustomJsPromiseValue([
          for (final value in _promiseIterableValues(args.single, method))
            _settledPromiseRecord(value),
        ]);
      case 'any':
        if (args.length != 1) _badMethodArgs(method);
        final errors = <Object?>[];
        for (final value in _promiseIterableValues(args.single, method)) {
          if (value is _CustomJsPromiseValue && value.rejected) {
            errors.add(_customJsCatchValue(value.reason));
            continue;
          }
          return value is _CustomJsPromiseValue
              ? value
              : _CustomJsPromiseValue(value);
        }
        return _CustomJsPromiseValue.rejected(
          _CustomJsAggregateError(errors),
        );
      case 'race':
        if (args.length != 1) _badMethodArgs(method);
        final values = _promiseIterableValues(args.single, method);
        if (values.isEmpty) return const _CustomJsPromiseValue(null);
        final first = values.first;
        return first is _CustomJsPromiseValue
            ? first
            : _CustomJsPromiseValue(first);
      case 'resolve':
        if (args.length > 1) _badMethodArgs(method);
        return _CustomJsPromiseValue(
          args.isEmpty ? null : _unwrapPromiseValue(_evaluate(args.single)),
        );
      case 'reject':
        if (args.length > 1) _badMethodArgs(method);
        return _CustomJsPromiseValue.rejected(
          args.isEmpty ? null : _evaluate(args.single),
        );
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_promise_method',
          'method': method,
        });
    }
  }

  Map<String, Object?> _settledPromiseRecord(Object? value) {
    if (value is _CustomJsPromiseValue && value.rejected) {
      return {
        'status': 'rejected',
        'reason': _customJsCatchValue(value.reason),
      };
    }
    return {
      'status': 'fulfilled',
      'value': _unwrapPromiseValue(value),
    };
  }

  Object? _callPromiseInstanceMethod(
    _CustomJsPromiseValue promise,
    String method,
    List<String> args,
  ) {
    switch (method) {
      case 'then':
        if (args.isEmpty || args.length > 2) _badMethodArgs(method);
        if (promise.rejected) return promise;
        return _CustomJsPromiseValue(
          _unwrapPromiseValue(
            _evaluateCallback(method, args.first, promise.value, 0),
          ),
        );
      case 'catch':
        if (args.length != 1) _badMethodArgs(method);
        if (!promise.rejected) return promise;
        return _CustomJsPromiseValue(
          _unwrapPromiseValue(
            _evaluateCallback(
              method,
              args.first,
              _customJsCatchValue(promise.reason),
              0,
            ),
          ),
        );
      case 'finally':
        if (args.length != 1) _badMethodArgs(method);
        _unwrapPromiseValue(_evaluateCallback(method, args.first, null, 0));
        return promise;
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_promise_instance_method',
          'method': method,
        });
    }
  }

  List<Object?> _promiseIterableValues(String expression, String method) {
    final value = _evaluate(expression);
    if (value is String) return value.split('');
    if (value is _CustomJsMap) return _customJsMapEntries(value);
    if (value is Iterable) return value.toList();
    _badMethodArgs(method);
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
    if (source is _CustomJsMap) {
      return <Object?>{..._customJsMapEntries(source)};
    }
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
    if (args.isEmpty) return _CustomJsDate(DateTime.now().toUtc());
    if (args.length > 1) {
      return _CustomJsDate(_dateTimeFromDateParts(args));
    }
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
      case 'UTC':
        if (args.isEmpty || args.length > 7) _badMethodArgs(method);
        return _dateTimeFromDateParts(args).millisecondsSinceEpoch;
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
    final utc = value.value.toUtc();
    switch (method) {
      case 'getTime':
      case 'valueOf':
        _expectNoArgs(method, args);
        return value.value.millisecondsSinceEpoch;
      case 'getFullYear':
      case 'getUTCFullYear':
        _expectNoArgs(method, args);
        return utc.year;
      case 'getMonth':
      case 'getUTCMonth':
        _expectNoArgs(method, args);
        return utc.month - 1;
      case 'getDate':
      case 'getUTCDate':
        _expectNoArgs(method, args);
        return utc.day;
      case 'getDay':
      case 'getUTCDay':
        _expectNoArgs(method, args);
        return utc.weekday % 7;
      case 'getHours':
      case 'getUTCHours':
        _expectNoArgs(method, args);
        return utc.hour;
      case 'getMinutes':
      case 'getUTCMinutes':
        _expectNoArgs(method, args);
        return utc.minute;
      case 'getSeconds':
      case 'getUTCSeconds':
        _expectNoArgs(method, args);
        return utc.second;
      case 'setDate':
      case 'setUTCDate':
        if (args.length != 1) _badMethodArgs(method);
        value.value = DateTime.utc(
          utc.year,
          utc.month,
          _toInt(_evaluate(args.single)),
          utc.hour,
          utc.minute,
          utc.second,
          utc.millisecond,
          utc.microsecond,
        );
        return value.value.millisecondsSinceEpoch;
      case 'setHours':
      case 'setUTCHours':
        if (args.isEmpty || args.length > 4) _badMethodArgs(method);
        final values = _evaluateCallArguments(args).map(_toInt).toList();
        value.value = DateTime.utc(
          utc.year,
          utc.month,
          utc.day,
          values[0],
          values.length > 1 ? values[1] : utc.minute,
          values.length > 2 ? values[2] : utc.second,
          values.length > 3 ? values[3] : utc.millisecond,
          utc.microsecond,
        );
        return value.value.millisecondsSinceEpoch;
      case 'toISOString':
      case 'toJSON':
      case 'toString':
        _expectNoArgs(method, args);
        return utc.toIso8601String();
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_method',
          'method': method,
        });
    }
  }

  DateTime _dateTimeFromDateParts(List<String> args) {
    final values = _evaluateCallArguments(args).map(_toInt).toList();
    if (values.isEmpty || values.length > 7) _badMethodArgs('Date');
    final year =
        values[0] >= 0 && values[0] <= 99 ? values[0] + 1900 : values[0];
    return DateTime.utc(
      year,
      values.length > 1 ? values[1] + 1 : 1,
      values.length > 2 ? values[2] : 1,
      values.length > 3 ? values[3] : 0,
      values.length > 4 ? values[4] : 0,
      values.length > 5 ? values[5] : 0,
      values.length > 6 ? values[6] : 0,
    );
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
      case 'union':
        final other = _setOperationItems(args, method);
        return {
          for (final item in value) item,
          for (final item in other)
            if (!_setContains(value, item)) item,
        };
      case 'intersection':
        final other = _setOperationItems(args, method);
        return {
          for (final item in value)
            if (_setContains(other, item)) item,
        };
      case 'difference':
        final other = _setOperationItems(args, method);
        return {
          for (final item in value)
            if (!_setContains(other, item)) item,
        };
      case 'isSubsetOf':
        final other = _setOperationItems(args, method);
        return value.every((item) => _setContains(other, item));
      case 'isDisjointFrom':
        final other = _setOperationItems(args, method);
        return value.every((item) => !_setContains(other, item));
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_method',
          'method': method,
        });
    }
  }

  Set<Object?> _setOperationItems(List<String> args, String method) {
    if (args.length != 1) _badMethodArgs(method);
    final other = _evaluate(args.single);
    if (other is Set) return other.cast<Object?>();
    if (other is Iterable && other is! String) return other.toSet();
    throw EngineException(errLlmFormat, {
      'reason': 'custom_skill_set_method',
      'method': method,
    });
  }

  bool _setContains(Iterable source, Object? needle) =>
      source.any((item) => _compareValues(item, needle, '==='));

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
      case 'exec':
        if (args.length != 1) _badMethodArgs(method);
        final text = _stringifyInterpolation(_evaluate(args.single));
        final match = value.global
            ? _nextGlobalRegExpMatch(value, text)
            : value.regExp.firstMatch(text);
        if (match == null) return null;
        return _customJsMatch(text, match);
      case 'test':
        if (args.length != 1) _badMethodArgs(method);
        final text = _stringifyInterpolation(_evaluate(args.single));
        if (value.global) return _nextGlobalRegExpMatch(value, text) != null;
        return value.regExp.hasMatch(text);
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_method',
          'method': method,
        });
    }
  }

  RegExpMatch? _nextGlobalRegExpMatch(_CustomJsRegExp value, String text) {
    if (value.lastIndex < 0 || value.lastIndex > text.length) {
      value.lastIndex = 0;
      return null;
    }
    final matches = value.regExp.allMatches(text, value.lastIndex).iterator;
    if (!matches.moveNext()) {
      value.lastIndex = 0;
      return null;
    }
    final match = matches.current;
    value.lastIndex = match.end;
    return match;
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
      case 'isInteger':
        if (values.length != 1) _badMethodArgs(method);
        return _isIntegerNumber(values.single);
      case 'isSafeInteger':
        if (values.length != 1) _badMethodArgs(method);
        return _isSafeIntegerNumber(values.single);
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
      case 'groupBy':
        return _objectGroupBy(args);
      case 'hasOwn':
        final values = _evaluateCallArguments(args);
        if (values.length != 2) _badMethodArgs(method);
        return _hasOwnProperty(values.first, values[1]);
      case 'keys':
      case 'values':
      case 'entries':
        final values = _evaluateCallArguments(args);
        if (values.length != 1) _badMethodArgs(method);
        return _objectEnumerable(values.single, method);
      default:
        throw EngineException(errLlmFormat, {
          'reason': 'custom_skill_builtin_method',
          'object': 'Object',
          'method': method,
        });
    }
  }

  List<Object?> _objectEnumerable(Object? value, String method) {
    final entries = <(String, Object?)>[];
    if (value is Map) {
      entries.addAll([
        for (final entry in value.entries) ('${entry.key}', entry.value),
      ]);
    } else if (value is List) {
      entries.addAll([
        for (var index = 0; index < value.length; index++)
          ('$index', value[index]),
      ]);
    } else if (value is String) {
      final chars = value.split('');
      entries.addAll([
        for (var index = 0; index < chars.length; index++)
          ('$index', chars[index]),
      ]);
    } else {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_object_builtin',
        'method': method,
      });
    }
    if (method == 'values') return [for (final entry in entries) entry.$2];
    if (method == 'entries') {
      return [
        for (final entry in entries) [entry.$1, entry.$2],
      ];
    }
    return [for (final entry in entries) entry.$1];
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

  Map<String, Object?> _objectGroupBy(List<String> args) {
    if (args.length != 2) _badMethodArgs('groupBy');
    final items = _groupBySourceItems(args.first, 'groupBy');
    final result = <String, Object?>{};
    for (var index = 0; index < items.length; index++) {
      final key = _stringifyPropertyKey(_evaluateCallback(
        'groupBy',
        args[1],
        items[index],
        index,
        source: items,
      ));
      (result.putIfAbsent(key, () => <Object?>[]) as List<Object?>)
          .add(items[index]);
    }
    return result;
  }

  _CustomJsMap _mapGroupBy(List<String> args) {
    if (args.length != 2) _badMethodArgs('groupBy');
    final items = _groupBySourceItems(args.first, 'groupBy');
    final result = _CustomJsMap(<Object?, Object?>{});
    for (var index = 0; index < items.length; index++) {
      final key = _evaluateCallback(
        'groupBy',
        args[1],
        items[index],
        index,
        source: items,
      );
      final existingKey = _customJsMapKey(result, key) ?? key;
      (result.values.putIfAbsent(existingKey, () => <Object?>[])
              as List<Object?>)
          .add(items[index]);
    }
    return result;
  }

  List<Object?> _groupBySourceItems(String sourceExpression, String method) {
    final source = _evaluate(sourceExpression);
    if (source is String) return source.split('');
    if (source is _CustomJsMap) return _customJsMapEntries(source);
    if (source is Iterable) return source.toList();
    _badMethodArgs(method);
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

  bool _isIntegerNumber(Object? value) {
    if (value is! num || !value.isFinite) return false;
    return value.truncateToDouble() == value;
  }

  bool _isSafeIntegerNumber(Object? value) {
    const maxSafeInteger = 9007199254740991;
    return _isIntegerNumber(value) && (value as num).abs() <= maxSafeInteger;
  }

  num? _coerceNumberPredicateNum(Object? value) {
    if (value == null) return 0;
    if (value is bool) return value ? 1 : 0;
    if (value is num) return value;
    final text = '$value'.trim();
    if (text.isEmpty) return 0;
    return num.tryParse(text);
  }

  Object? _customJsCatchValue(Object? error) {
    if (error == null) {
      return {
        'name': 'Error',
        'message': '',
      };
    }
    if (error is _CustomJsError) {
      return error;
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
    if (_startsWithWord(params, 0, 'async')) {
      params = params.substring('async'.length).trim();
    }
    if (params.startsWith('(') && params.endsWith(')')) {
      params = params.substring(1, params.length - 1);
    }
    final names = _splitTopLevel(params, ',')
        .map((param) => param.trim())
        .where((param) => param.isNotEmpty)
        .toList();
    if (names.any((name) => !_isValidCallbackParam(name))) {
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
        if (binding.nestedPattern != null) {
          _bindCallbackParam(
            binding.nestedPattern!,
            boundValue,
            bindings,
            method,
          );
          continue;
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
      if (binding.nestedPattern != null) {
        _bindCallbackParam(
          binding.nestedPattern!,
          boundValue,
          bindings,
          method,
        );
        continue;
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
      String? nestedPattern;
      if (!isRest &&
          (bindingName.startsWith('{') || bindingName.startsWith('['))) {
        final hasNestedObject = bindingName.startsWith('{') &&
            (_objectDestructureBindings(bindingName)?.isNotEmpty ?? false);
        final hasNestedArray = bindingName.startsWith('[') &&
            (_arrayDestructureBindings(bindingName)?.isNotEmpty ?? false);
        if (!hasNestedObject && !hasNestedArray) return null;
        nestedPattern = bindingName;
        bindingName = '';
      }
      if (nestedPattern == null && !validName.hasMatch(bindingName)) {
        return null;
      }
      if (defaultExpression == '') return null;
      if (isRest &&
          (i != items.length - 1 || bindings.any((item) => item.isRest))) {
        return null;
      }
      bindings.add(_CustomJsArrayDestructureBinding(
        bindingName: bindingName,
        defaultExpression: defaultExpression,
        nestedPattern: nestedPattern,
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
        nestedPattern: null,
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
    if (colon >= 0 &&
        (bindingSource.startsWith('{') || bindingSource.startsWith('['))) {
      final hasNestedObject = bindingSource.startsWith('{') &&
          (_objectDestructureBindings(bindingSource)?.isNotEmpty ?? false);
      final hasNestedArray = bindingSource.startsWith('[') &&
          (_arrayDestructureBindings(bindingSource)?.isNotEmpty ?? false);
      if (!validName.hasMatch(fieldName) ||
          (!hasNestedObject && !hasNestedArray) ||
          defaultExpression == '') {
        return null;
      }
      return _CustomJsObjectDestructureBinding(
        fieldName: fieldName,
        bindingName: '',
        defaultExpression: defaultExpression,
        nestedPattern: bindingSource,
        isRest: false,
      );
    }
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
      nestedPattern: null,
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

  Object? _unwrapPromiseValue(Object? value) {
    if (value is! _CustomJsPromiseValue) return value;
    if (value.rejected) _throwPromiseRejection(value.reason);
    return value.value;
  }

  Never _throwPromiseRejection(Object? reason) {
    if (reason == null) {
      throw EngineException(errLlmFormat, {
        'reason': 'custom_skill_promise_rejection',
      });
    }
    throw reason;
  }

  Object? _readProperty(Object? value, String property) {
    if (value is _CustomJsBuiltin &&
        value.name == 'Object' &&
        property == 'prototype') {
      return const _CustomJsBuiltin('Object.prototype');
    }
    if (value is _CustomJsBuiltin &&
        value.name == 'Object.prototype' &&
        property == 'hasOwnProperty') {
      return const _CustomJsBuiltin('Object.prototype.hasOwnProperty');
    }
    if (value is _CustomJsBuiltin &&
        value.name == 'Object.prototype' &&
        property == 'toString') {
      return const _CustomJsBuiltin('Object.prototype.toString');
    }
    if (value is Map) return value[property];
    if (value is _CustomJsMatch) {
      if (property == 'index') return value.index;
      if (property == 'input') return value.input;
      if (property == 'groups') return value.groups;
    }
    if (value is _CustomJsRegExp && property == 'lastIndex') {
      return value.lastIndex;
    }
    if (property == 'size' && value is Set) return value.length;
    if (property == 'size' && value is _CustomJsMap) return value.values.length;
    if (value is _CustomJsError) {
      if (property == 'name') return value.name;
      if (property == 'message') return value.message;
      if (value is _CustomJsAggregateError && property == 'errors') {
        return value.errors;
      }
    }
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
    value = _unwrapPromiseValue(value);
    if (value == null) return '';
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    return jsonEncode(value);
  }

  String _stringifyInterpolation(Object? value) {
    value = _unwrapPromiseValue(value);
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

  int _regExpLastIndex(Object? value) {
    final numeric = _toNum(value);
    if (!numeric.isFinite || numeric <= 0) return 0;
    return numeric.toInt();
  }
}

class _CustomJsNoAssignment {
  const _CustomJsNoAssignment();
}

class _CustomJsMatch extends ListBase<Object?> {
  final List<Object?> _groups;
  final int index;
  final String input;
  final Map<String, Object?>? groups;

  _CustomJsMatch(
    List<Object?> items, {
    required this.index,
    required this.input,
    required this.groups,
  }) : _groups = items;

  @override
  int get length => _groups.length;

  @override
  set length(int length) {
    _groups.length = length;
  }

  @override
  Object? operator [](int index) => _groups[index];

  @override
  void operator []=(int index, Object? value) {
    _groups[index] = value;
  }
}

class _CustomJsBuiltin {
  final String name;
  const _CustomJsBuiltin(this.name);
}

class _CustomJsDate {
  DateTime value;
  _CustomJsDate(this.value);
}

class _CustomJsMap {
  final Map<Object?, Object?> values;
  const _CustomJsMap(this.values);
}

class _CustomJsPromiseValue {
  final Object? value;
  final Object? reason;
  final bool rejected;

  const _CustomJsPromiseValue(this.value)
      : reason = null,
        rejected = false;

  const _CustomJsPromiseValue.rejected(this.reason)
      : value = null,
        rejected = true;
}

class _CustomJsError {
  final String message;

  const _CustomJsError(this.message);

  String get name => 'Error';
}

class _CustomJsAggregateError extends _CustomJsError {
  final List<Object?> errors;

  const _CustomJsAggregateError(this.errors)
      : super('All promises were rejected');

  @override
  String get name => 'AggregateError';
}

class _CustomJsFunction {
  final String name;
  final List<String> params;
  final String body;
  final List<Object?> boundValues;

  const _CustomJsFunction({
    required this.name,
    required this.params,
    required this.body,
    this.boundValues = const <Object?>[],
  });
}

class _CustomJsRegExp {
  final RegExp regExp;
  final bool global;
  int lastIndex = 0;

  _CustomJsRegExp(this.regExp, {required this.global});
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
  final String? catchBody;
  final String? finallyBody;

  const _CustomJsTryStatement({
    required this.body,
    required this.errorName,
    required this.catchBody,
    required this.finallyBody,
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
  final String? nestedPattern;
  final bool isRest;

  const _CustomJsObjectDestructureBinding({
    required this.fieldName,
    required this.bindingName,
    required this.defaultExpression,
    required this.nestedPattern,
    required this.isRest,
  });
}

class _CustomJsArrayDestructureBinding {
  final String bindingName;
  final String? defaultExpression;
  final String? nestedPattern;
  final bool isRest;

  const _CustomJsArrayDestructureBinding({
    required this.bindingName,
    required this.defaultExpression,
    required this.nestedPattern,
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
          !_nextTopLevelWordIs(script, i + 1, 'catch') &&
          !_nextTopLevelWordIs(script, i + 1, 'finally')) {
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
      (_startsWithWord(trimmed, 0, 'async') &&
          _startsWithWord(
            trimmed,
            _skipWhitespace(trimmed, 'async'.length),
            'function',
          )) ||
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

_ComparisonToken? _readTopLevelInstanceofOperator(String source) {
  const operator = 'instanceof';
  var quote = '';
  var escaped = false;
  var paren = 0;
  var bracket = 0;
  var brace = 0;

  for (var i = 0; i < source.length - operator.length + 1; i++) {
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
    if (!_isTopLevelWordAt(source, i, operator)) continue;
    final left = source.substring(0, i).trim();
    final right = source.substring(i + operator.length).trim();
    if (left.isEmpty || right.isEmpty) return null;
    return _ComparisonToken(
      left: left,
      right: right,
      operator: operator,
    );
  }
  return null;
}

bool _isTopLevelInAt(String source, int index) {
  return _isTopLevelWordAt(source, index, 'in');
}

bool _isTopLevelWordAt(String source, int index, String word) {
  if (!source.startsWith(word, index)) return false;
  final before = index - 1;
  final after = index + word.length;
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

  Future<List<AgentMemoryRecord>> _agentPromptLongTermMemories(
    int projectId,
    String query, {
    required String family,
    required int limit,
  }) async {
    final matched = await searchAgentMemories(projectId, query, limit: limit);
    if (family != _productionAgentFamily || limit <= 0) return matched;
    final visual = _productionVisualReferenceMemories(
      projectId,
      excludeIds: {for (final memory in matched) memory.id},
      limit: math.max(1, math.min(2, limit)),
    );
    return visual.isEmpty ? matched : [...matched, ...visual];
  }

  List<AgentMemoryRecord> _productionVisualReferenceMemories(
    int projectId, {
    Set<String> excludeIds = const {},
    int limit = 2,
  }) {
    if (limit <= 0) return const [];
    const patterns = [
      '%视觉参考%',
      '%参考图%',
      '%画风%',
      '%风格%',
      '%visual%',
      '%style%',
    ];
    final clauses =
        List.filled(patterns.length, '(name LIKE ? OR content LIKE ?)')
            .join(' OR ');
    final args = <Object?>[
      _agentMemoryIsolationKey(projectId),
      _agentMemoryRole,
      _agentMemoryType,
      for (final pattern in patterns) ...[pattern, pattern],
      limit + excludeIds.length,
    ];
    final rows = db.select(
      'SELECT id,name,content,createTime,embedding,relatedMessageIds '
      'FROM memories '
      'WHERE isolationKey=? AND role=? AND type=? AND ($clauses) '
      'ORDER BY createTime DESC, id DESC LIMIT ?',
      args,
    );
    final result = <AgentMemoryRecord>[];
    for (final row in rows) {
      final record = AgentMemoryRecord.fromRow(row);
      if (excludeIds.contains(record.id)) continue;
      result.add(record);
      if (result.length >= limit) break;
    }
    return result;
  }

  List<AgentMemoryEntry> _visualReferenceMemoryEntries(
    int projectId, {
    Set<String> excludeIds = const {},
    int limit = 2,
  }) =>
      [
        for (final record in _productionVisualReferenceMemories(
          projectId,
          excludeIds: excludeIds,
          limit: limit,
        ))
          AgentMemoryEntry(
            id: record.id,
            name: record.name,
            content: record.content,
            createdAt: record.createdAt,
            embedding: record.embedding,
            role: _agentMemoryRole,
            type: agentMemoryTypeNote,
            relatedMessageIds: record.relatedMessageIds,
            score: record.score,
            matchedTokens: record.matchedTokens,
          ),
      ];

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
    final relevanceReason = memory.relevanceReason?.trim();
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
      if (relevanceReason != null && relevanceReason.isNotEmpty)
        'relevanceReason="${_escapeXmlAttr(relevanceReason)}"',
    ];
    return '<note ${attrs.join(' ')}>${_escapeXmlText(memory.content)}</note>';
  }

  String _formatAgentMemoryContextEntry(
    String tag,
    AgentMemoryEntry memory,
  ) {
    final relevanceReason = memory.relevanceReason?.trim();
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
      if (memory.matchedTokens.isNotEmpty)
        'matchedTokens="${_escapeXmlAttr(memory.matchedTokens.join(','))}"',
      if (relevanceReason != null && relevanceReason.isNotEmpty)
        'relevanceReason="${_escapeXmlAttr(relevanceReason)}"',
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
    int? minScore,
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
    if (minScore != null) {
      _writeAgentIntSettingWithLegacy(
        'agent.memory.minScore',
        'minScore',
        minScore,
        min: 0,
        max: agentMemoryMaxScoreThreshold,
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
    final productionSubAgentFailureCounts = <String, int>{};
    String? lastAutoToolName;
    var consecutiveAutoToolCalls = 0;

    for (var turn = 0; turn < (autoMode ? _maxAutoTurns : 1); turn++) {
      final memoryService = _agentMemoryService(family: agentFamily);
      final stage = agentFamily == _productionAgentFamily
          ? productionAgentDecisionStage
          : scriptAgentDecisionStage;
      final system = _agentSystemPrompt(
        await _agentPromptLongTermMemories(
          projectId,
          text,
          family: agentFamily,
          limit: _agentRagLimit(),
        ),
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
      if (_shouldStopAfterScriptSubAgentFailure(
        agentFamily: agentFamily,
        toolName: toolName,
        summary: summary,
      )) {
        final content = '子 Agent 执行失败：$summary 当前阶段已停止，请调整后重试。';
        messages.add(AgentMessage(
          role: agentRoleAssistant,
          content: content,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        _saveAgentMessages(projectId, messages, family: agentFamily);
        await _recordAgentMemory(
          projectId,
          family: agentFamily,
          role: _agentDecisionMemoryRole,
          content: content,
        );
        return;
      }
      if (_isProductionAgentSubAgentTool(toolName)) {
        if (_isProductionAgentSubAgentFailure(
          agentFamily: agentFamily,
          toolName: toolName,
          summary: summary,
        )) {
          final failureCount =
              (productionSubAgentFailureCounts[toolName] ?? 0) + 1;
          productionSubAgentFailureCounts[toolName] = failureCount;
          if (failureCount > _maxProductionSubAgentRetries) {
            final content = '生产子 Agent 执行失败：$summary '
                '已达到最多重试 $_maxProductionSubAgentRetries 次，当前阶段已停止，请调整后重试。';
            messages.add(AgentMessage(
              role: agentRoleAssistant,
              content: content,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ));
            _saveAgentMessages(projectId, messages, family: agentFamily);
            await _recordAgentMemory(
              projectId,
              family: agentFamily,
              role: _agentDecisionMemoryRole,
              content: content,
            );
            return;
          }
        } else {
          productionSubAgentFailureCounts.remove(toolName);
        }
      }
      if (autoMode &&
          _isSupervisionSubAgentTool(toolName) &&
          !_isAgentSubAgentFailureSummary(summary)) {
        final content = '监督结果已返回，请确认审核报告后再继续下一步。';
        messages.add(AgentMessage(
          role: agentRoleAssistant,
          content: content,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        _saveAgentMessages(projectId, messages, family: agentFamily);
        await _recordAgentMemory(
          projectId,
          family: agentFamily,
          role: _agentDecisionMemoryRole,
          content: content,
        );
        return;
      }
    }
  }

  bool _shouldStopAfterScriptSubAgentFailure({
    required String agentFamily,
    required String toolName,
    required String summary,
  }) {
    if (agentFamily != _scriptAgentFamily) return false;
    if (!_isScriptAgentSubAgentTool(toolName)) return false;
    return _isAgentSubAgentFailureSummary(summary);
  }

  bool _isProductionAgentSubAgentFailure({
    required String agentFamily,
    required String toolName,
    required String summary,
  }) {
    if (agentFamily != _productionAgentFamily) return false;
    if (!_isProductionAgentSubAgentTool(toolName)) return false;
    return _isAgentSubAgentFailureSummary(summary);
  }

  bool _isScriptAgentSubAgentTool(String toolName) =>
      toolName.startsWith('run_sub_agent_') ||
      toolName == 'run_supervision_agent';

  bool _isProductionAgentSubAgentTool(String toolName) =>
      toolName.startsWith('run_sub_agent_');

  bool _isSupervisionSubAgentTool(String toolName) =>
      toolName == 'run_supervision_agent' ||
      toolName == 'run_sub_agent_supervision';

  bool _isAgentSubAgentFailureSummary(String summary) {
    final text = summary.trim();
    if (text.isEmpty) return true;
    return text.contains('未返回可写入内容') ||
        text.contains('未输出 scriptItem') ||
        text.contains('未输出 storyboardItem') ||
        text.contains('缺少 scriptId 参数') ||
        text.contains('不支持嵌套调用') ||
        text.startsWith('执行失败') ||
        text.contains('执行失败：') ||
        text.contains('异常中断');
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
      await _agentPromptLongTermMemories(
        projectId,
        reviewQuery,
        family: family,
        limit: _agentRagLimit(),
      ),
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
        text.startsWith('可执行') ||
        text.startsWith('可以执行') ||
        text.startsWith('允许执行') ||
        text.startsWith('放行') ||
        text.startsWith('批准')) {
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
    final zhRejection = RegExp(
      r'^(拒绝|拦截|不允许执行|不可以执行|不能执行|不可执行|禁止执行|'
      r'驳回|不要执行|请勿执行|不通过)\s*[:：]?\s*',
    );
    if (zhRejection.hasMatch(text)) {
      final cleaned = text.replaceFirst(zhRejection, '').trim();
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
        case 'memory_add':
          final content = (args['content'] ??
                  args['内容'] ??
                  args['记忆内容'] ??
                  args['正文'] ??
                  args['text'] ??
                  args['memory'] ??
                  args['note'] ??
                  args['value'] ??
                  args['message'] ??
                  args['prompt'] ??
                  args['input'] ??
                  '')
              .toString()
              .trim();
          if (content.isEmpty) return '缺少 content 参数。';
          final memoryName = (args['name'] ??
                  args['title'] ??
                  args['标题'] ??
                  args['名称'] ??
                  args['label'] ??
                  args['memoryName'] ??
                  args['记忆名称'] ??
                  args['memory_name'] ??
                  '')
              .toString()
              .trim();
          final defaultRole = _memoryAddDefaultRole(agentFamily, stage);
          final role = (args['role'] ??
                  args['角色'] ??
                  args['memoryRole'] ??
                  args['记忆角色'] ??
                  args['memory_role'] ??
                  args['authorRole'] ??
                  args['author_role'] ??
                  defaultRole)
              .toString()
              .trim();
          final normalizedRole = role.isEmpty ? defaultRole : role;
          final addType = _memoryAddType(args);
          if (addType == null) {
            return 'memory_add 只支持一次写入 conversation/message 或 long_term/note。';
          }
          if (addType == agentMemoryTypeNote) {
            final id = saveAgentMemory(
              projectId,
              name: memoryName.isEmpty ? '长期记忆' : memoryName,
              content: content,
            );
            return jsonEncode({
              'saved': true,
              'id': id,
              'type': agentMemoryTypeNote,
              'scope': 'long_term',
              'name': memoryName.isEmpty ? '长期记忆' : memoryName,
              'role': _agentMemoryRole,
              'content': content,
            });
          }
          final createTime = _coerceInt(
            args['createTime'] ??
                args['创建时间'] ??
                args['create_time'] ??
                args['createdAt'] ??
                args['created_at'] ??
                args['timestamp'] ??
                args['时间戳'] ??
                args['time'],
          );
          final id = await _agentMemoryService(
            family: agentFamily,
          ).add(
            isolationKey: _agentConversationIsolationKey(
              projectId,
              family: agentFamily,
            ),
            role: normalizedRole,
            name: memoryName,
            content: content,
            createTime: createTime,
          );
          return jsonEncode({
            'saved': id.isNotEmpty,
            'id': id,
            'type': agentMemoryTypeMessage,
            'scope': 'conversation',
            'name': memoryName,
            'role': normalizedRole,
            'content': content,
          });
        case 'memory_update':
          final memoryId = _agentMemoryIdArg(args);
          if (memoryId.isEmpty) return 'memory_update 需要 memoryId 参数。';
          final existing = _agentLongTermMemoryRow(projectId, memoryId);
          if (existing == null) {
            return jsonEncode({
              'updated': false,
              'id': memoryId,
              'type': agentMemoryTypeNote,
              'scope': 'long_term',
              'message': '未找到长期记忆',
            });
          }
          final requestedName = _agentMemoryNameArg(args);
          final requestedContent = _agentMemoryContentArg(args);
          if (requestedName.isEmpty && requestedContent.isEmpty) {
            return 'memory_update 需要 content 或 name 参数。';
          }
          final nextName = requestedName.isEmpty
              ? existing['name'] as String
              : requestedName;
          final nextContent = requestedContent.isEmpty
              ? existing['content'] as String
              : requestedContent;
          final updatedId = saveAgentMemory(
            projectId,
            id: memoryId,
            name: nextName,
            content: nextContent,
          );
          return jsonEncode({
            'updated': true,
            'id': updatedId,
            'type': agentMemoryTypeNote,
            'scope': 'long_term',
            'name': nextName,
            'role': _agentMemoryRole,
            'content': nextContent,
          });
        case 'memory_delete':
          final memoryId = _agentMemoryIdArg(args);
          if (memoryId.isEmpty) return 'memory_delete 需要 memoryId 参数。';
          final existing = _agentLongTermMemoryRow(projectId, memoryId);
          if (existing == null) {
            return jsonEncode({
              'deleted': false,
              'id': memoryId,
              'type': agentMemoryTypeNote,
              'scope': 'long_term',
              'message': '未找到长期记忆',
            });
          }
          deleteAgentMemory(projectId, memoryId);
          return jsonEncode({
            'deleted': true,
            'id': memoryId,
            'type': agentMemoryTypeNote,
            'scope': 'long_term',
            'name': existing['name'] as String,
            'content': existing['content'] as String,
          });
        case 'memory_clear':
          final scope = _memoryClearScope(args);
          if (scope == null) {
            return 'memory_clear 需要 scope，且只支持 message/conversation、summary、note/long_term 或 all。';
          }
          final service = _agentMemoryService(family: agentFamily);
          if (scope == agentMemoryTypeNote) {
            service.clear(
              isolationKey: _agentMemoryIsolationKey(projectId),
              scope: agentMemoryTypeNote,
            );
            return jsonEncode({
              'cleared': true,
              'scope': agentMemoryTypeNote,
              'target': 'long_term',
              'family': agentFamily,
            });
          }
          service.clear(
            isolationKey: _agentConversationIsolationKey(
              projectId,
              family: agentFamily,
            ),
            scope: scope,
          );
          return jsonEncode({
            'cleared': true,
            'scope': scope,
            'target': 'conversation',
            'family': agentFamily,
          });
        case 'memory_get':
          final queryRequests = _deepRetrieveQueryRequests(args);
          final queries = _agentMemoryRequestQueries(queryRequests);
          final includeVisualReferences =
              _shouldIncludeVisualReferenceMemories(args);
          final baseIncludeIds = _agentMemoryIncludeIds(args);
          if (queryRequests.isEmpty &&
              !includeVisualReferences &&
              baseIncludeIds.isEmpty) {
            return '缺少 query 参数。';
          }
          final baseExcludeIds =
              _agentMemoryExcludeIds(args, excludedMemoryIds);
          final sortMode = _agentMemoryDirectSortMode(args) ?? 'relevance';
          final limit = _agentMemoryDirectLimit(args);
          final offset = _agentMemoryDirectOffset(args);
          final memoryService = _agentMemoryService(family: agentFamily);
          final relatedMessageRecords = <AgentMemoryEntry>[];
          final summaryRecords = <AgentMemoryEntry>[];
          final recentMessageRecords = <AgentMemoryEntry>[];
          final noteRecords = <AgentMemoryEntry>[];
          final recordPriorities = <String, int>{};
          final recordQueryMatches = <String, _AgentMemoryQueryMatch>{};
          final hitQueryGroups = <String>{};
          var hasMessageRequests = false;
          var hasSummaryRequests = false;
          if (baseIncludeIds.isNotEmpty) {
            final roles = _agentMemoryRoles(args);
            final requestedExcludeRoles = _agentMemoryExcludeRoles(args);
            final excludeRoles = {
              ...excludedRoles,
              if (requestedExcludeRoles != null) ...requestedExcludeRoles,
            };
            final requestedExcludeRoleSuffixes =
                _agentMemoryExcludeRoleSuffixes(args);
            final excludeRoleSuffixes = {
              ...excludedRoleSuffixes,
              if (requestedExcludeRoleSuffixes != null)
                ...requestedExcludeRoleSuffixes,
            };
            final exactRecords = _filterAgentMemoryEntriesByContent(
              _agentMemoryRecordsByIds(
                projectId,
                baseIncludeIds,
                family: agentFamily,
                roles: roles,
                types: _deepRetrieveMemoryTypes(args),
                excludeIds: baseExcludeIds,
                excludeRoles: excludeRoles,
                excludeRoleSuffixes: excludeRoleSuffixes,
                timeRange: _agentMemoryTimeRange(args),
              ),
              args,
            );
            for (final record in exactRecords) {
              switch (record.type) {
                case agentMemoryTypeSummary:
                  summaryRecords.add(record);
                  hasSummaryRequests = true;
                  break;
                case agentMemoryTypeNote:
                  noteRecords.add(record);
                  break;
                default:
                  relatedMessageRecords.add(record);
                  hasMessageRequests = true;
                  break;
              }
            }
          }
          for (final request in queryRequests) {
            if (request.fallbackWhenPreviousEmpty &&
                _agentMemoryFallbackHasPriorHit(
                  request,
                  hitQueryGroups,
                  hasAnyRecords: _hasAgentMemoryToolRecords(
                    relatedMessageRecords,
                    summaryRecords,
                    recentMessageRecords,
                    noteRecords,
                  ),
                )) {
              continue;
            }
            final requestArgs = request.args;
            void mergeRecordQueryMatch(AgentMemoryEntry record) {
              recordPriorities[record.id] = math.max(
                recordPriorities[record.id] ?? request.priority,
                request.priority,
              );
              _mergeAgentMemoryQueryMatch(recordQueryMatches, record, request);
              final group = request.queryGroup;
              if (group != null) hitQueryGroups.add(group);
            }

            final roles = _agentMemoryRoles(requestArgs);
            final requestedExcludeRoles = _agentMemoryExcludeRoles(requestArgs);
            final excludeRoles = {
              ...excludedRoles,
              if (requestedExcludeRoles != null) ...requestedExcludeRoles,
            };
            final requestedExcludeRoleSuffixes =
                _agentMemoryExcludeRoleSuffixes(requestArgs);
            final excludeRoleSuffixes = {
              ...excludedRoleSuffixes,
              if (requestedExcludeRoleSuffixes != null)
                ...requestedExcludeRoleSuffixes,
            };
            final types = _deepRetrieveMemoryTypes(requestArgs);
            final minScore = _agentMemoryMinScore(requestArgs);
            final timeRange = _agentMemoryTimeRange(requestArgs);
            final rerankEnabled = _agentMemoryRerankEnabled(requestArgs);
            final requestSortMode = _agentMemorySortMode(requestArgs);
            final requestLimit = request.limit;
            final requestOffset = _agentMemoryDirectOffset(requestArgs);
            final requestIncludeVisualReferences =
                _shouldIncludeVisualReferenceMemories(requestArgs);
            final includeMessages =
                types == null || types.contains(agentMemoryTypeMessage);
            final includeSummaries =
                types == null || types.contains(agentMemoryTypeSummary);
            final includeNotes = types?.contains(agentMemoryTypeNote) == true;
            hasMessageRequests = hasMessageRequests || includeMessages;
            hasSummaryRequests = hasSummaryRequests || includeSummaries;
            final excludeIds =
                _agentMemoryExcludeIds(requestArgs, excludedMemoryIds);
            final queryExcludeIds = {...excludeIds};
            final context = includeMessages || includeSummaries
                ? await memoryService.get(
                    isolationKey: _agentConversationIsolationKey(
                      projectId,
                      family: agentFamily,
                    ),
                    query: request.query,
                    roles: roles,
                    excludeRelatedIds: queryExcludeIds,
                    excludeRoles: excludeRoles,
                    excludeRoleSuffixes: excludeRoleSuffixes,
                    minScore: minScore,
                    timeRange: timeRange,
                    excludeIdsFromContext: true,
                    rerankEnabled: rerankEnabled,
                  )
                : const AgentMemoryContext();
            if (includeMessages) {
              final limitedRelatedMessages = _limitAgentMemoryEntries(
                _filterAgentMemoryEntriesByContent(
                  context.relatedMessages,
                  requestArgs,
                ),
                requestSortMode,
                requestLimit,
                offset: requestOffset,
              );
              relatedMessageRecords.addAll(limitedRelatedMessages);
              for (final record in limitedRelatedMessages) {
                mergeRecordQueryMatch(record);
              }
              final limitedRecentMessages = _limitAgentMemoryEntries(
                _filterAgentMemoryEntriesByContent(
                  context.recentMessages,
                  requestArgs,
                ),
                requestSortMode,
                requestLimit,
                offset: requestOffset,
              );
              recentMessageRecords.addAll(limitedRecentMessages);
              for (final record in limitedRecentMessages) {
                mergeRecordQueryMatch(record);
              }
            }
            if (includeSummaries) {
              final limitedSummaries = _limitAgentMemoryEntries(
                _filterAgentMemoryEntriesByContent(
                  context.summaries,
                  requestArgs,
                ),
                requestSortMode,
                requestLimit,
                offset: requestOffset,
              );
              summaryRecords.addAll(limitedSummaries);
              for (final record in limitedSummaries) {
                mergeRecordQueryMatch(record);
              }
            }
            if (includeNotes) {
              final noteExcludeIds = {
                ...queryExcludeIds,
                for (final record in context.relatedMessages) record.id,
                for (final record in context.summaries) record.id,
                for (final record in context.recentMessages) record.id,
              };
              final requestNotes = await memoryService.deepRetrieve(
                isolationKey: _agentConversationIsolationKey(
                  projectId,
                  family: agentFamily,
                ),
                keyword: request.query,
                roles: roles,
                excludeRoles: excludeRoles,
                excludeRoleSuffixes: excludeRoleSuffixes,
                types: const {agentMemoryTypeNote},
                excludeIds: noteExcludeIds,
                minScore: minScore,
                timeRange: timeRange,
                rerankEnabled: rerankEnabled,
                noteIsolationKey: _agentMemoryIsolationKey(projectId),
              );
              final limitedNotes = _limitAgentMemoryEntries(
                _filterAgentMemoryEntriesByContent(
                  requestNotes,
                  requestArgs,
                ),
                requestSortMode,
                requestLimit,
                offset: requestOffset,
              );
              noteRecords.addAll(limitedNotes);
              for (final record in limitedNotes) {
                mergeRecordQueryMatch(record);
              }
            }
            if (requestIncludeVisualReferences) {
              final visualRecords = _filterAgentMemoryEntriesByContent(
                _visualReferenceMemoryEntries(
                  projectId,
                  excludeIds: {
                    ...queryExcludeIds,
                    for (final record in context.relatedMessages) record.id,
                    for (final record in context.summaries) record.id,
                    for (final record in context.recentMessages) record.id,
                    for (final record in noteRecords) record.id,
                  },
                  limit:
                      requestLimit ?? _agentMemoryDirectLimit(requestArgs) ?? 2,
                ),
                requestArgs,
              );
              noteRecords.addAll(visualRecords);
              for (final record in visualRecords) {
                mergeRecordQueryMatch(record);
              }
            }
          }
          if (queryRequests.isEmpty && includeVisualReferences) {
            noteRecords.addAll(
              _filterAgentMemoryEntriesByContent(
                _visualReferenceMemoryEntries(
                  projectId,
                  excludeIds: {
                    ...baseExcludeIds,
                    for (final record in relatedMessageRecords) record.id,
                    for (final record in summaryRecords) record.id,
                    for (final record in recentMessageRecords) record.id,
                    for (final record in noteRecords) record.id,
                  },
                  limit: limit ?? 2,
                ),
                args,
              ),
            );
          }
          final dedupedRelatedMessages = _sortAgentMemoryEntriesByPriority(
            _dedupeAgentMemoryEntries(relatedMessageRecords),
            sortMode,
            recordPriorities,
          );
          final relatedMessages = hasMessageRequests
              ? _sliceAgentMemoryEntries(dedupedRelatedMessages, limit, offset)
              : const <AgentMemoryEntry>[];
          final dedupedSummaries = _sortAgentMemoryEntriesByPriority(
            _dedupeAgentMemoryEntries(summaryRecords),
            sortMode,
            recordPriorities,
          );
          final summaries = hasSummaryRequests
              ? _sliceAgentMemoryEntries(dedupedSummaries, limit, offset)
              : const <AgentMemoryEntry>[];
          final dedupedRecentMessages = _sortAgentMemoryEntriesByPriority(
            _dedupeAgentMemoryEntries(recentMessageRecords),
            sortMode,
            recordPriorities,
          );
          final recentMessages = hasMessageRequests
              ? _sliceAgentMemoryEntries(dedupedRecentMessages, limit, offset)
              : const <AgentMemoryEntry>[];
          final dedupedNotes = _sortAgentMemoryEntriesByPriority(
            _dedupeAgentMemoryEntries(noteRecords),
            sortMode,
            recordPriorities,
          );
          final notes = _sliceAgentMemoryEntries(dedupedNotes, limit, offset);
          if (relatedMessages.isEmpty &&
              summaries.isEmpty &&
              recentMessages.isEmpty &&
              notes.isEmpty) {
            return jsonEncode({
              'found': false,
              'queries': queries,
              'memories': [],
              'summaries': [],
              'recent': [],
              'notes': [],
              'records': [],
              'message': '未找到相关记忆',
            });
          }
          return jsonEncode({
            'found': true,
            'queries': queries,
            'memories': [
              for (final record in relatedMessages) record.content,
            ],
            'summaries': [
              for (final record in summaries) record.content,
            ],
            'recent': [
              for (final record in recentMessages) record.content,
            ],
            'notes': [
              for (final record in notes) record.content,
            ],
            'records': [
              for (final record in _dedupeAgentMemoryEntries([
                ...relatedMessages,
                ...summaries,
                ...recentMessages,
                ...notes,
              ]))
                _agentMemoryRecordPayload(
                  record,
                  priority: recordPriorities[record.id],
                  queryMatch: recordQueryMatches[record.id],
                ),
            ],
          });
        case 'deepRetrieve':
          final queryRequests = _deepRetrieveQueryRequests(args);
          final queries = _agentMemoryRequestQueries(queryRequests);
          final includeVisualReferences =
              _shouldIncludeVisualReferenceMemories(args);
          final baseIncludeIds = _agentMemoryIncludeIds(args);
          if (queryRequests.isEmpty &&
              !includeVisualReferences &&
              baseIncludeIds.isEmpty) {
            return '缺少 keyword 参数。';
          }
          final baseExcludeIds =
              _agentMemoryExcludeIds(args, excludedMemoryIds);
          final sortMode = _agentMemoryDirectSortMode(args) ?? 'relevance';
          final limit = _agentMemoryDirectLimit(args);
          final offset = _agentMemoryDirectOffset(args);
          final memoryService = _agentMemoryService(family: agentFamily);
          final records = <AgentMemoryEntry>[];
          final recordPriorities = <String, int>{};
          final recordQueryMatches = <String, _AgentMemoryQueryMatch>{};
          final hitQueryGroups = <String>{};
          if (baseIncludeIds.isNotEmpty) {
            final roles = _agentMemoryRoles(args);
            final requestedExcludeRoles = _agentMemoryExcludeRoles(args);
            final excludeRoles = {
              ...excludedRoles,
              if (requestedExcludeRoles != null) ...requestedExcludeRoles,
            };
            final requestedExcludeRoleSuffixes =
                _agentMemoryExcludeRoleSuffixes(args);
            final excludeRoleSuffixes = {
              ...excludedRoleSuffixes,
              if (requestedExcludeRoleSuffixes != null)
                ...requestedExcludeRoleSuffixes,
            };
            records.addAll(
              _filterAgentMemoryEntriesByContent(
                _agentMemoryRecordsByIds(
                  projectId,
                  baseIncludeIds,
                  family: agentFamily,
                  roles: roles,
                  types: _deepRetrieveMemoryTypes(args),
                  excludeIds: baseExcludeIds,
                  excludeRoles: excludeRoles,
                  excludeRoleSuffixes: excludeRoleSuffixes,
                  timeRange: _agentMemoryTimeRange(args),
                ),
                args,
              ),
            );
          }
          for (final request in queryRequests) {
            if (request.fallbackWhenPreviousEmpty &&
                _agentMemoryFallbackHasPriorHit(
                  request,
                  hitQueryGroups,
                  hasAnyRecords: records.isNotEmpty,
                )) {
              continue;
            }
            final requestArgs = request.args;
            final roles = _agentMemoryRoles(requestArgs);
            final requestedExcludeRoles = _agentMemoryExcludeRoles(requestArgs);
            final excludeRoles = {
              ...excludedRoles,
              if (requestedExcludeRoles != null) ...requestedExcludeRoles,
            };
            final requestedExcludeRoleSuffixes =
                _agentMemoryExcludeRoleSuffixes(requestArgs);
            final excludeRoleSuffixes = {
              ...excludedRoleSuffixes,
              if (requestedExcludeRoleSuffixes != null)
                ...requestedExcludeRoleSuffixes,
            };
            final types = _deepRetrieveMemoryTypes(requestArgs);
            final minScore = _agentMemoryMinScore(requestArgs);
            final timeRange = _agentMemoryTimeRange(requestArgs);
            final rerankEnabled = _agentMemoryRerankEnabled(requestArgs);
            final requestSortMode = _agentMemorySortMode(requestArgs);
            final requestLimit = request.limit;
            final requestOffset = _agentMemoryDirectOffset(requestArgs);
            final requestIncludeVisualReferences =
                _shouldIncludeVisualReferenceMemories(requestArgs);
            final excludeIds =
                _agentMemoryExcludeIds(requestArgs, excludedMemoryIds);
            final queryExcludeIds = {...excludeIds};
            void mergeRecordQueryMatch(AgentMemoryEntry record) {
              recordPriorities[record.id] = math.max(
                recordPriorities[record.id] ?? request.priority,
                request.priority,
              );
              _mergeAgentMemoryQueryMatch(recordQueryMatches, record, request);
              final group = request.queryGroup;
              if (group != null) hitQueryGroups.add(group);
            }

            final requestRecords = await memoryService.deepRetrieve(
              isolationKey: _agentConversationIsolationKey(
                projectId,
                family: agentFamily,
              ),
              keyword: request.query,
              roles: roles,
              excludeRoles: excludeRoles,
              excludeRoleSuffixes: excludeRoleSuffixes,
              types: types,
              excludeIds: queryExcludeIds,
              minScore: minScore,
              timeRange: timeRange,
              rerankEnabled: rerankEnabled,
              noteIsolationKey: _agentMemoryIsolationKey(projectId),
            );
            final limitedRequestRecords = _limitAgentMemoryEntries(
              _filterAgentMemoryEntriesByContent(
                requestRecords,
                requestArgs,
              ),
              requestSortMode,
              requestLimit,
              offset: requestOffset,
            );
            records.addAll(limitedRequestRecords);
            for (final record in limitedRequestRecords) {
              mergeRecordQueryMatch(record);
            }
            if (requestIncludeVisualReferences) {
              final visualRecords = _filterAgentMemoryEntriesByContent(
                _visualReferenceMemoryEntries(
                  projectId,
                  excludeIds: {
                    ...queryExcludeIds,
                    for (final record in records) record.id,
                  },
                  limit:
                      requestLimit ?? _agentMemoryDirectLimit(requestArgs) ?? 2,
                ),
                requestArgs,
              );
              records.addAll(visualRecords);
              for (final record in visualRecords) {
                mergeRecordQueryMatch(record);
              }
            }
          }
          if (queryRequests.isEmpty && includeVisualReferences) {
            final visualRecords = _filterAgentMemoryEntriesByContent(
              _visualReferenceMemoryEntries(
                projectId,
                excludeIds: {
                  ...baseExcludeIds,
                  for (final record in records) record.id,
                },
                limit: limit ?? 2,
              ),
              args,
            );
            records.addAll(visualRecords);
          }
          final mergedRecords = _sortAgentMemoryEntriesByPriority(
            _dedupeAgentMemoryEntries(records),
            sortMode,
            recordPriorities,
          );
          final limitedRecords =
              _sliceAgentMemoryEntries(mergedRecords, limit, offset);
          if (limitedRecords.isEmpty) {
            return jsonEncode({
              'found': false,
              'queries': queries,
              'memories': [],
              'records': [],
              'message': '未找到相关记忆',
            });
          }
          return jsonEncode({
            'found': true,
            'queries': queries,
            'memories': [
              for (final record in limitedRecords) record.content,
            ],
            'records': [
              for (final record in limitedRecords)
                _agentMemoryRecordPayload(
                  record,
                  priority: recordPriorities[record.id],
                  queryMatch: recordQueryMatches[record.id],
                ),
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
          final selectedIds = _agentNovelIdsArg(projectId, args);
          final ids = selectedIds ??
              novels(projectId, limit: 100000)
                  .data
                  .where((n) => n.eventState != 1)
                  .map((n) => n.id)
                  .toList();
          if (ids.isEmpty) {
            return selectedIds == null ? '没有需要生成事件的章节。' : '未找到匹配章节。';
          }
          final taskId = generateEvents(projectId, ids);
          return '已提交事件生成任务（任务 #$taskId），涉及 ${ids.length} 个章节。';
        case 'extract_assets':
          final ids = _agentScriptIdsArg(projectId, args) ??
              scripts(projectId)
                  .where((s) => s.extractState != 1)
                  .map((s) => s.id)
                  .toList();
          if (ids.isEmpty) return '没有需要提取资产的剧本。';
          final taskId = extractAssets(ids, projectId);
          return '已提交资产提取任务（任务 #$taskId），涉及 ${ids.length} 个剧本。';
        case 'generate_storyboards':
          final scriptId = _agentScriptIdArg(projectId, args);
          if (scriptId == null) return '缺少 scriptId 参数。';
          final taskId = generateStoryboards(projectId, scriptId);
          return '已提交分镜生成任务（任务 #$taskId）。';
        case 'generate_shot_images':
          final scriptId = _agentScriptIdArg(projectId, args);
          if (scriptId == null) return '缺少 scriptId 参数。';
          final selectedIds = _agentStoryboardIdsArg(scriptId, args);
          final ids =
              selectedIds ?? storyboards(scriptId).map((s) => s.id).toList();
          if (ids.isEmpty) {
            return selectedIds == null ? '该剧本暂无分镜。' : '未找到匹配分镜。';
          }
          final taskId =
              batchGenerateStoryboardImages(projectId, ids, compulsory: true);
          return '已提交首帧图生成任务（任务 #$taskId），涉及 ${ids.length} 个分镜。';
        case 'analyze_reference_image':
          return _agentAnalyzeReferenceImage(projectId, args);
        case 'generate_videos':
          final scriptId = _agentScriptIdArg(projectId, args);
          if (scriptId == null) return '缺少 scriptId 参数。';
          final selectedIds = _agentStoryboardIdsArg(scriptId, args);
          final ids = selectedIds ??
              storyboards(scriptId)
                  .where((s) => s.filePath != null)
                  .map((s) => s.id)
                  .toList();
          if (ids.isEmpty) {
            return selectedIds == null ? '该剧本没有已生成首帧图的分镜。' : '未找到匹配分镜。';
          }
          final taskId = batchGenerateVideos(projectId, ids);
          return '已提交视频生成任务（任务 #$taskId），涉及 ${ids.length} 个分镜。';
        case 'bind_audio':
          final selectedIds = _agentRoleIdsArg(projectId, args);
          final ids = selectedIds ??
              roleAudioBindings(projectId)
                  .where((r) => r.audioAssetId == null)
                  .map((r) => r.roleId)
                  .toList();
          if (ids.isEmpty) {
            return selectedIds == null ? '所有角色都已绑定配音，或项目内没有角色资产。' : '未找到匹配角色。';
          }
          final taskId = batchBindAudio(projectId, ids);
          return '已提交配音匹配任务（任务 #$taskId），涉及 ${ids.length} 个角色。';
        case 'compose_episode':
          final scriptId = _agentScriptIdArg(projectId, args);
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

  List<int>? _agentNovelIdsArg(int projectId, Map<String, dynamic> args) {
    final direct = _intListAny(args, const [
      'novelIds',
      'novel_ids',
      'novelId',
      'novel_id',
      'chapterIds',
      'chapter_ids',
      'chapterId',
      'chapter_id',
    ]);
    if (direct != null) return direct;
    final chapterNumbers = _intListAny(args, const [
      'chapterIndexs',
      'chapterIndexes',
      'chapterIndex',
      'chapterNo',
      'chapterNos',
      'chapter_index',
      'chapter_indexes',
      'chapter_no',
      'chapter_nos',
    ]);
    final rows = novels(projectId, limit: 100000).data;
    if (chapterNumbers != null) {
      final wanted = chapterNumbers.toSet();
      return [
        for (final chapter in rows)
          if (wanted.contains(chapter.chapterIndex)) chapter.id,
      ];
    }

    final chapterNames = _stringListAny(args, const [
      'chapterName',
      'chapterNames',
      'chapterTitle',
      'chapterTitles',
      'chapter_name',
      'chapter_names',
      'chapter_title',
      'chapter_titles',
    ]);
    if (chapterNames == null) return null;
    final wanted = chapterNames.map((name) => name.trim()).toSet();
    return [
      for (final chapter in rows)
        if (wanted.contains((chapter.chapter ?? '').trim())) chapter.id,
    ];
  }

  List<int>? _agentScriptIdsArg(int projectId, Map<String, dynamic> args) {
    final direct = _intListAny(args, const [
      'scriptIds',
      'script_ids',
      'scriptId',
      'script_id',
      'episodeIds',
      'episode_ids',
      'episodeId',
      'episode_id',
      'episodesIds',
      'episodes_ids',
      'episodesId',
      'episodes_id',
    ]);
    if (direct != null) return direct;
    final episodeNumbers = _intListAny(args, const [
      'episodeNo',
      'episodeNos',
      'scriptNo',
      'scriptNos',
      'episodeIndex',
      'episodeIndexes',
      'scriptIndex',
      'scriptIndexes',
      'episode_no',
      'episode_nos',
      'script_no',
      'script_nos',
      'episode_index',
      'episode_indexes',
      'script_index',
      'script_indexes',
    ]);
    final rows = scripts(projectId);
    if (episodeNumbers != null) {
      final ids = <int>[];
      for (final number in episodeNumbers) {
        final index = number - 1;
        if (index >= 0 && index < rows.length) ids.add(rows[index].id);
      }
      return ids;
    }

    final scriptNames = _stringListAny(args, const [
      'scriptName',
      'scriptNames',
      'episodeName',
      'episodeNames',
      'scriptTitle',
      'scriptTitles',
      'episodeTitle',
      'episodeTitles',
      'script_name',
      'script_names',
      'episode_name',
      'episode_names',
      'script_title',
      'script_titles',
      'episode_title',
      'episode_titles',
    ]);
    if (scriptNames == null) return null;
    final wanted = scriptNames.map((name) => name.trim()).toSet();
    return [
      for (final row in rows)
        if (wanted.contains((row.name ?? '').trim())) row.id,
    ];
  }

  List<int>? _agentStoryboardIdsArg(int scriptId, Map<String, dynamic> args) {
    final direct = _intListAny(args, const [
      'storyboardIds',
      'storyboard_ids',
      'storyboardId',
      'storyboard_id',
      'shotIds',
      'shot_ids',
      'shotId',
      'shot_id',
    ]);
    if (direct != null) return direct;
    final shotNumbers = _intListAny(args, const [
      'shotNo',
      'shotNos',
      'shotIndex',
      'shotIndexes',
      'storyboardNo',
      'storyboardNos',
      'storyboardIndex',
      'storyboardIndexes',
      'shot_no',
      'shot_nos',
      'shot_index',
      'shot_indexes',
      'storyboard_no',
      'storyboard_nos',
      'storyboard_index',
      'storyboard_indexes',
    ]);
    if (shotNumbers == null) return null;
    final rows = storyboards(scriptId);
    final ids = <int>[];
    for (final number in shotNumbers) {
      final index = number - 1;
      if (index >= 0 && index < rows.length) ids.add(rows[index].id);
    }
    return ids;
  }

  List<int>? _agentRoleIdsArg(int projectId, Map<String, dynamic> args) {
    final direct = _intListAny(args, const [
      'roleIds',
      'role_ids',
      'roleId',
      'role_id',
      'assetIds',
      'asset_ids',
      'assetId',
      'asset_id',
    ]);
    if (direct != null) return direct;

    final roleNumbers = _intListAny(args, const [
      'roleNo',
      'roleNos',
      'roleIndex',
      'roleIndexes',
      'assetNo',
      'assetNos',
      'role_no',
      'role_nos',
      'role_index',
      'role_indexes',
      'asset_no',
      'asset_nos',
    ]);
    final rows = roleAudioBindings(projectId);
    if (roleNumbers != null) {
      final ids = <int>[];
      for (final number in roleNumbers) {
        final index = number - 1;
        if (index >= 0 && index < rows.length) ids.add(rows[index].roleId);
      }
      return ids;
    }

    final roleNames = _stringListAny(args, const [
      'roleName',
      'roleNames',
      'assetName',
      'assetNames',
      'role_name',
      'role_names',
      'asset_name',
      'asset_names',
    ]);
    if (roleNames == null) return null;
    final wanted = roleNames.map((name) => name.trim()).toSet();
    return [
      for (final row in rows)
        if (wanted.contains((row.roleName ?? '').trim())) row.roleId,
    ];
  }

  Future<String> _agentAnalyzeReferenceImage(
    int projectId,
    Map<String, dynamic> args,
  ) async {
    final baseGateway = gateway;
    if (baseGateway is! ImageUnderstandingGateway) {
      return '当前网关不支持图片理解。';
    }
    final vision = baseGateway as ImageUnderstandingGateway;
    final resolvedImages = _agentReferenceImageArgs(projectId, args);
    if (resolvedImages.isEmpty) {
      return '缺少可分析的参考图。请传入 imagePath、imageRelPath、assetName、assetId、imageId、storyboardId 或对应复数字段。';
    }
    final prompt = _stringArgAny(args, const [
      'prompt',
      'question',
      'query',
      '问题',
      '提示词',
    ]);
    final promptText =
        prompt.isEmpty ? '请提炼这张参考图的画风、主体特征、构图、色彩和可复用生图关键词。' : prompt;
    final analyses = <Map<String, String>>[];
    for (final image in resolvedImages) {
      final result = await vision.analyzeImage(
        promptText,
        image.path,
        stage: 'agent_vision',
      );
      analyses.add({
        'source': image.source,
        'analysis': result.content,
      });
    }
    if (analyses.length == 1) {
      final payload = <String, dynamic>{
        'analysis': analyses.single['analysis'],
        'source': analyses.single['source'],
      };
      _maybeRememberImageAnalysis(projectId, args, payload, analyses);
      return jsonEncode(payload);
    }
    final payload = <String, dynamic>{
      'analysis': analyses
          .map((item) => '${item['source']}: ${item['analysis']}')
          .join('\n\n'),
      'sources': [
        for (final item in analyses) item['source'],
      ],
      'analyses': analyses,
    };
    _maybeRememberImageAnalysis(projectId, args, payload, analyses);
    return jsonEncode(payload);
  }

  void _maybeRememberImageAnalysis(
    int projectId,
    Map<String, dynamic> args,
    Map<String, dynamic> payload,
    List<Map<String, String>> analyses,
  ) {
    final shouldRemember = _coerceBool(args['remember'] ??
            args['saveMemory'] ??
            args['save_memory'] ??
            args['记住'] ??
            args['保存记忆'] ??
            args['写入记忆']) ??
        false;
    if (!shouldRemember) return;
    final name = _stringArgAny(args, const [
      'memoryName',
      'memory_name',
      '记忆名称',
      'title',
      '标题',
    ]);
    final memoryName = name.isEmpty ? '视觉参考分析' : name;
    final content = [
      '视觉参考分析：$memoryName',
      for (final item in analyses) ...[
        '来源：${item['source']}',
        item['analysis'] ?? '',
      ],
    ].where((line) => line.trim().isNotEmpty).join('\n');
    final id = saveAgentMemory(
      projectId,
      name: memoryName,
      content: content,
    );
    payload['memory'] = {
      'saved': true,
      'id': id,
      'type': agentMemoryTypeNote,
      'scope': 'long_term',
      'name': memoryName,
    };
  }

  List<({String path, String source})> _agentReferenceImageArgs(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final resolved = <({String path, String source})>[];
    final seen = <String>{};

    void add(({String path, String source})? image) {
      if (image == null) return;
      final key = '${image.source}\n${image.path}';
      if (seen.add(key)) resolved.add(image);
    }

    for (final path in _stringListAny(args, const [
          'imagePaths',
          'image_paths',
          'paths',
          'filePaths',
          'file_paths',
          '图片路径列表',
          '文件路径列表',
        ]) ??
        const <String>[]) {
      add(_agentReferenceImageArg(projectId, {'imagePath': path}));
    }
    for (final relPath in _stringListAny(args, const [
          'imageRelPaths',
          'image_rel_paths',
          'relPaths',
          'rel_paths',
          'mediaPaths',
          'media_paths',
          '媒体路径列表',
        ]) ??
        const <String>[]) {
      add(_agentReferenceImageArg(projectId, {'imageRelPath': relPath}));
    }
    for (final imageId in _intListAny(args, const [
          'imageIds',
          'image_ids',
          '图片Ids',
          '图片IDs',
        ]) ??
        const <int>[]) {
      add(_agentReferenceImageArg(projectId, {'imageId': imageId}));
    }
    for (final assetId in _intListAny(args, const [
          'assetIds',
          'asset_ids',
          'assetsIds',
          'assets_ids',
          '素材Ids',
          '素材IDs',
        ]) ??
        const <int>[]) {
      add(_agentReferenceImageArg(projectId, {'assetId': assetId}));
    }
    for (final assetName in _stringListAny(args, const [
          'assetNames',
          'asset_names',
          'names',
          '素材名称列表',
          '角色名列表',
          '资产名称列表',
        ]) ??
        const <String>[]) {
      add(_agentReferenceImageArg(projectId, {'assetName': assetName}));
    }
    final scriptId = _productionScriptId(projectId, args);
    for (final assetRef in _stringListAny(args, const [
          'assetRef',
          'assetRefs',
          'asset_ref',
          'asset_refs',
          'assetCode',
          'assetCodes',
          'asset_code',
          'asset_codes',
          '资产引用',
          '资产引用列表',
        ]) ??
        const <String>[]) {
      final ids = _productionAssetIdsFromRefs(
        projectId,
        [assetRef],
        scriptId: scriptId,
      );
      for (final id in ids) {
        add(_agentAssetImagePath(id));
      }
    }
    for (final styleName in _agentReferenceStyleNames(projectId, args)) {
      for (final image in _agentStyleReferenceImages(styleName)) {
        add(image);
      }
    }
    for (final storyboardId in _intListAny(args, const [
          'storyboardIds',
          'storyboard_ids',
          'shotIds',
          'shot_ids',
          '分镜Ids',
          '分镜IDs',
        ]) ??
        const <int>[]) {
      add(_agentReferenceImageArg(projectId, {'storyboardId': storyboardId}));
    }
    if (scriptId != null) {
      for (final storyboardId
          in _agentStoryboardIdsArg(scriptId, args) ?? const <int>[]) {
        add(_agentReferenceImageArg(projectId, {'storyboardId': storyboardId}));
      }
    }
    add(_agentReferenceImageArg(projectId, args));
    return resolved;
  }

  List<String> _agentReferenceStyleNames(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final names = <String>[];
    final seen = <String>{};

    void addName(String name) {
      final trimmed = name.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) return;
      names.add(trimmed);
    }

    for (final name in _stringListAny(args, const [
          'artStyleName',
          'artStyleNames',
          'art_style_name',
          'art_style_names',
          'styleName',
          'styleNames',
          'style_name',
          'style_names',
          'visualManualName',
          'visualManualNames',
          'visual_manual_name',
          'visual_manual_names',
          'visualManual',
          'visualManuals',
          'visual_manual',
          'visual_manuals',
          'artStyle',
          'artStyles',
          '画风',
          '画风名称',
          '视觉手册',
          '视觉手册名称',
        ]) ??
        const <String>[]) {
      addName(name);
    }

    final shouldUseProjectStyle = _coerceBool(
          args['projectArtStyle'] ??
              args['useProjectArtStyle'] ??
              args['project_art_style'] ??
              args['项目画风'] ??
              args['当前画风'],
        ) ??
        false;
    if (shouldUseProjectStyle) {
      final projectStyle = db
              .select('SELECT artStyle FROM o_project WHERE id=?', [projectId])
              .firstOrNull?['artStyle']
              ?.toString() ??
          '';
      addName(projectStyle);
    }
    return names;
  }

  List<({String path, String source})> _agentStyleReferenceImages(
    String styleName,
  ) {
    final resolved = <({String path, String source})>[];
    for (final pack in visualManuals()) {
      if (pack.name != styleName && pack.pack != styleName) continue;
      for (final imagePath in pack.images) {
        if (File(imagePath).existsSync()) {
          resolved.add((path: imagePath, source: 'visualManual:${pack.name}'));
        }
      }
    }

    final rows = db.select(
      'SELECT name,label,fileUrl FROM o_artStyle WHERE name=? OR label=? '
      'ORDER BY id ASC',
      [styleName, styleName],
    );
    for (final row in rows) {
      final path = _agentMediaImageAbsPath(row['fileUrl']);
      if (path == null) continue;
      final sourceName = (row['name'] as String? ?? styleName).trim();
      resolved.add((
        path: path,
        source: 'artStyle:${sourceName.isEmpty ? styleName : sourceName}',
      ));
    }

    return resolved;
  }

  ({String path, String source})? _agentReferenceImageArg(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final direct = _stringArgAny(args, const [
      'imagePath',
      'filePath',
      'path',
      '图片路径',
      '文件路径',
    ]);
    if (direct.isNotEmpty) {
      final file = File(direct);
      if (file.isAbsolute && file.existsSync()) {
        return (path: file.path, source: 'path:$direct');
      }
      final abs = media.absPath(direct);
      if (File(abs).existsSync()) return (path: abs, source: 'media:$direct');
    }

    final rel = _stringArgAny(args, const [
      'imageRelPath',
      'relPath',
      'mediaPath',
      '媒体路径',
    ]);
    if (rel.isNotEmpty) {
      final abs = media.absPath(rel);
      if (File(abs).existsSync()) return (path: abs, source: 'media:$rel');
    }

    final imageId = _coerceInt(
      args['imageId'] ?? args['image_id'] ?? args['图片Id'] ?? args['图片ID'],
    );
    if (imageId != null) {
      final row = db.select(
          'SELECT filePath FROM o_image WHERE id=?', [imageId]).firstOrNull;
      final path = _agentMediaImageAbsPath(row?['filePath']);
      if (path != null) return (path: path, source: 'image:$imageId');
    }

    final assetId = _coerceInt(
      args['assetId'] ?? args['asset_id'] ?? args['assetsId'] ?? args['素材Id'],
    );
    if (assetId != null) {
      final resolved = _agentAssetImagePath(assetId);
      if (resolved != null) return resolved;
    }

    final assetName = _stringArgAny(args, const [
      'assetName',
      'asset_name',
      'name',
      '素材名称',
      '角色名',
    ]);
    if (assetName.isNotEmpty) {
      final row = db.select(
        'SELECT id FROM o_assets WHERE projectId=? AND name=? '
        'ORDER BY id ASC LIMIT 1',
        [projectId, assetName],
      ).firstOrNull;
      final id = row?['id'] as int?;
      if (id != null) {
        final resolved = _agentAssetImagePath(id, sourceName: assetName);
        if (resolved != null) return resolved;
      }
    }

    final storyboardId = _coerceInt(
      args['storyboardId'] ??
          args['storyboard_id'] ??
          args['shotId'] ??
          args['shot_id'] ??
          args['分镜Id'],
    );
    if (storyboardId != null) {
      final row = db.select('SELECT filePath FROM o_storyboard WHERE id=?',
          [storyboardId]).firstOrNull;
      final path = _agentMediaImageAbsPath(row?['filePath']);
      if (path != null) {
        return (path: path, source: 'storyboard:$storyboardId');
      }
    }
    return null;
  }

  ({String path, String source})? _agentAssetImagePath(
    int assetId, {
    String? sourceName,
  }) {
    final rows = db.select(
      'SELECT a.name, i.filePath FROM o_assets a '
      'LEFT JOIN o_image i ON i.id=a.imageId '
      'WHERE a.id=?',
      [assetId],
    );
    if (rows.isEmpty) return null;
    final selected = _agentMediaImageAbsPath(rows.first['filePath']);
    final source = 'asset:${sourceName ?? rows.first['name'] ?? assetId}';
    if (selected != null) return (path: selected, source: source);
    final fallback = db.select(
      'SELECT filePath FROM o_image WHERE assetsId=? AND state=? '
      'ORDER BY id DESC LIMIT 1',
      [assetId, stateDone],
    ).firstOrNull;
    final path = _agentMediaImageAbsPath(fallback?['filePath']);
    return path == null ? null : (path: path, source: source);
  }

  String? _agentMediaImageAbsPath(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    final direct = File(value);
    if (direct.isAbsolute && direct.existsSync()) return direct.path;
    final abs = media.absPath(value);
    return File(abs).existsSync() ? abs : null;
  }

  List<int>? _intListAny(Map<String, dynamic> args, List<String> keys) {
    for (final key in keys) {
      final parsed = _coerceIntList(args[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  List<String>? _stringListAny(Map<String, dynamic> args, List<String> keys) {
    for (final key in keys) {
      final parsed = _coerceStringList(args[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  int? _agentScriptIdArg(int projectId, Map<String, dynamic> args) {
    final ids = _agentScriptIdsArg(projectId, args);
    return ids == null || ids.isEmpty ? null : ids.first;
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

  bool? _coerceBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      switch (raw.trim().toLowerCase()) {
        case 'true':
        case 'yes':
        case 'y':
        case '1':
        case 'on':
        case '是':
        case '记住':
        case '保存':
          return true;
        case 'false':
        case 'no':
        case 'n':
        case '0':
        case 'off':
        case '否':
        case '不保存':
          return false;
      }
    }
    return null;
  }

  List<String>? _coerceStringList(Object? raw) {
    if (raw == null) return null;
    if (raw is Iterable) {
      final values = [
        for (final item in raw)
          if (item.toString().trim().isNotEmpty) item.toString().trim(),
      ];
      return values.isEmpty ? null : values;
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    final parts = text.split(RegExp(r'[,，、;；]+'));
    final values = [
      for (final part in parts)
        if (part.trim().isNotEmpty) part.trim(),
    ];
    return values.isEmpty ? null : values;
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

  Set<String>? _coerceMemoryIdSetAny(
    Map<String, dynamic> args,
    List<String> keys,
  ) {
    final values = <String>{};
    for (final key in keys) {
      final parsed = _coerceMemoryIdSet(args[key]);
      if (parsed != null) values.addAll(parsed);
    }
    return values.isEmpty ? null : values;
  }

  Set<String> _agentMemoryExcludeIds(
    Map<String, dynamic> args,
    Set<String> excludedMemoryIds,
  ) {
    final requestedExcludeIds = _coerceMemoryIdSetAny(args, const [
      'excludeIds',
      'excludeMemoryIds',
      'excludedMemoryIds',
      'excludeId',
      'excludeRecords',
      '排除记忆',
      '排除记忆Ids',
      'memoryIds',
      'seenMemoryIds',
      '已读记忆',
      '已读记忆Ids',
      'seenIds',
      'seenRecords',
      '已读记录',
      'readMemoryIds',
      'readIds',
      'readRecords',
      '排除记录',
      'records',
      'previousMemoryIds',
      'previouslyReadMemoryIds',
      'previouslyReadIds',
      'previousRecords',
      'previouslyReadRecords',
    ]);
    return {
      ...excludedMemoryIds,
      if (requestedExcludeIds != null) ...requestedExcludeIds,
      ..._agentMemoryQueryPlanExcludeIds(args),
    };
  }

  Set<String> _agentMemoryQueryPlanExcludeIds(Map<String, dynamic> args) {
    final values = <String>{};
    for (final raw in _agentMemoryQueryPlanExcludeIdValues(args)) {
      final parsed = _coerceMemoryIdSet(raw);
      if (parsed != null) values.addAll(parsed);
    }
    return values;
  }

  List<Object?> _agentMemoryQueryPlanExcludeIdValues(
    Map<String, dynamic> args,
  ) =>
      _agentMemoryQueryPlanFilterValues(args, const [
        'excludeIds',
        'excludeMemoryIds',
        'excludedMemoryIds',
        'excludeId',
        'excludeRecords',
        '排除记忆',
        '排除记忆Ids',
        'memoryIds',
        'seenMemoryIds',
        '已读记忆',
        '已读记忆Ids',
        'seenIds',
        'seenRecords',
        '已读记录',
        'readMemoryIds',
        'readIds',
        'readRecords',
        '排除记录',
        'records',
        'previousMemoryIds',
        'previouslyReadMemoryIds',
        'previouslyReadIds',
        'previousRecords',
        'previouslyReadRecords',
      ]);

  Set<String> _agentMemoryIncludeIds(Map<String, dynamic> args) {
    final values = <String>{};

    void add(Object? raw) {
      final parsed = _coerceAgentMemoryIncludeIdSet(raw);
      if (parsed != null) values.addAll(parsed);
    }

    for (final key in const [
      'includeIds',
      'includeMemoryIds',
      'includedMemoryIds',
      'targetIds',
      'targetMemoryIds',
      'onlyIds',
      'onlyMemoryIds',
      'targetRecords',
      '指定记忆',
      '目标记忆',
      '只看记忆',
    ]) {
      add(args[key]);
    }
    add(_agentMemoryIdsClauseValues(args['ids']));
    add(_agentMemoryTermsIdClauseValues(args['terms']));
    add(_agentMemoryTermsIdClauseValues(args['term']));
    for (final raw in _agentMemoryQueryPlanIncludeIdValues(args)) {
      add(raw);
    }
    return values;
  }

  Set<String>? _coerceAgentMemoryIncludeIdSet(Object? raw) {
    final values = <String>{};

    void add(Object? value) {
      final parsed = _coerceMemoryIdSet(value);
      if (parsed != null) values.addAll(parsed);
    }

    if (raw is Iterable && raw is! String) {
      for (final item in raw) {
        add(item);
      }
    } else {
      add(raw);
    }
    return values.isEmpty ? null : values;
  }

  List<Object?> _agentMemoryQueryPlanIncludeIdValues(
    Map<String, dynamic> args,
  ) {
    final values = <Object?>[];

    void addValue(Object? raw) {
      if (raw != null) values.add(raw);
    }

    void addNode(Object? raw) {
      if (raw == null) return;
      if (raw is Map) {
        final map = <String, dynamic>{
          for (final entry in raw.entries)
            if (entry.key is String) (entry.key as String): entry.value,
        };
        for (final key in const [
          'includeIds',
          'includeMemoryIds',
          'includedMemoryIds',
          'targetIds',
          'targetMemoryIds',
          'onlyIds',
          'onlyMemoryIds',
          'targetRecords',
          '指定记忆',
          '目标记忆',
          '只看记忆',
        ]) {
          addValue(map[key]);
        }
        addValue(_agentMemoryIdsClauseValues(map['ids']));
        addValue(_agentMemoryTermsIdClauseValues(map['terms']));
        addValue(_agentMemoryTermsIdClauseValues(map['term']));
        for (final key in const [
          'queryPlan',
          'query_plan',
          'retrievalPlan',
          'retrieval_plan',
          'searchPlan',
          'search_plan',
          'searchQueries',
          'search_queries',
          'plannedQueries',
          'planned_queries',
          'queries',
          'queryList',
          'query_list',
          'keywords',
          'keywordList',
          'keyword_list',
          'items',
          'steps',
          '查询计划',
          '检索计划',
          '搜索计划',
          '查询列表',
          '关键词列表',
        ]) {
          addNode(map[key]);
        }
        for (final key in _agentMemoryStructuredQueryClauseKeys) {
          addNode(map[key]);
        }
        for (final key in _agentMemoryStructuredVectorClauseKeys) {
          addNode(map[key]);
        }
        for (final key in _agentMemoryHybridRetrieverClauseKeys) {
          addNode(map[key]);
        }
        for (final key in _agentMemoryVectorQueryBuilderKeys) {
          addNode(map[key]);
        }
        return;
      }
      if (raw is Iterable && raw is! String) {
        for (final item in raw) {
          addNode(item);
        }
      }
    }

    for (final key in const [
      'queryPlan',
      'query_plan',
      'retrievalPlan',
      'retrieval_plan',
      'searchPlan',
      'search_plan',
      'searchQueries',
      'search_queries',
      'plannedQueries',
      'planned_queries',
      '查询计划',
      '检索计划',
      '搜索计划',
    ]) {
      addNode(args[key]);
    }
    return values;
  }

  Object? _agentMemoryIdsClauseValues(Object? raw) {
    if (raw == null) return null;
    if (raw is Map) {
      for (final key in const ['values', 'ids', '_id', 'id']) {
        if (raw.containsKey(key)) return raw[key];
      }
      return null;
    }
    return raw;
  }

  Object? _agentMemoryTermsIdClauseValues(Object? raw) {
    final values = <Object?>[];

    void addTerms(Object? value) {
      if (value == null) return;
      if (value is Map) {
        for (final key in const [
          '_id',
          'id',
          'ids',
          'memoryId',
          'memory_id',
          'messageId',
          'message_id',
          'summaryId',
          'summary_id',
          'noteId',
          'note_id',
        ]) {
          if (value.containsKey(key)) values.add(value[key]);
        }
        return;
      }
      if (value is Iterable && value is! String) {
        for (final item in value) {
          addTerms(item);
        }
      }
    }

    addTerms(raw);
    return values.isEmpty ? null : values;
  }

  Set<String>? _coerceMemoryIdSet(Object? raw) {
    final values = <String>{};
    void add(Object? value) {
      if (value is String) {
        for (final part in value.split(',')) {
          final trimmed = part.trim();
          if (trimmed.isNotEmpty) values.add(trimmed);
        }
        return;
      }
      if (value is List) {
        for (final item in value) {
          add(item);
        }
        return;
      }
      if (value is Map) {
        for (final key in const [
          'id',
          'memoryId',
          'memory_id',
          'messageId',
          'message_id',
          'summaryId',
          'summary_id',
          'noteId',
          'note_id',
        ]) {
          add(value[key]);
        }
      }
    }

    add(raw);
    return values.isEmpty ? null : values;
  }

  List<_AgentMemoryQueryRequest> _deepRetrieveQueryRequests(
    Map<String, dynamic> args,
  ) {
    final requests = <_AgentMemoryQueryRequest>[];
    final baseArgs = _agentMemoryArgsWithoutQueryPlan(args);
    var queryPlanIndex = 0;

    void addRequest(
      String query,
      Map<String, dynamic> requestArgs, {
      int? limit,
      int priority = 0,
      bool fallbackWhenPreviousEmpty = false,
      String? queryGroup,
    }) {
      final trimmed = query.trim();
      if (trimmed.isEmpty) return;
      queryPlanIndex += 1;
      requests.add(
        _AgentMemoryQueryRequest(
          query: trimmed,
          args: {
            ...requestArgs,
            'query': trimmed,
          },
          queryPlanIndex: queryPlanIndex,
          limit: limit,
          priority: priority,
          reason: _agentMemoryQueryReason(requestArgs),
          fallbackWhenPreviousEmpty: fallbackWhenPreviousEmpty,
          queryGroup: queryGroup,
        ),
      );
    }

    void addTextRequests(
      Object? raw,
      Map<String, dynamic> requestArgs, {
      int? limit,
      int priority = 0,
      bool fallbackWhenPreviousEmpty = false,
      String? queryGroup,
    }) {
      final items = _coerceStringList(raw);
      if (items == null) return;
      for (final item in items) {
        addRequest(
          item,
          requestArgs,
          limit: limit,
          priority: priority,
          fallbackWhenPreviousEmpty: fallbackWhenPreviousEmpty,
          queryGroup: queryGroup,
        );
      }
    }

    bool isStructuredPlanValue(Object? raw) {
      if (raw is Map) return true;
      if (raw is Iterable && raw is! String) {
        for (final item in raw) {
          if (isStructuredPlanValue(item)) return true;
        }
      }
      return false;
    }

    void addPlanNode(
      Object? raw,
      Map<String, dynamic> inheritedArgs, {
      int? inheritedLimit,
      int inheritedPriority = 0,
      bool inheritedFallbackWhenPreviousEmpty = false,
      String? inheritedQueryGroup,
    }) {
      if (raw == null) return;
      if (raw is Map) {
        final requestCountBeforeNode = requests.length;
        final map = <String, dynamic>{
          for (final entry in raw.entries)
            if (entry.key is String) (entry.key as String): entry.value,
        };
        var nodeArgs = {
          ...inheritedArgs,
          ..._agentMemoryPlanFilterArgs(map),
        };
        if (_agentMemoryPlanRequiresVectorIndex(map)) {
          nodeArgs = {
            ...nodeArgs,
            'onlyVectorIndex': true,
          };
        }
        final nodeLimit = _agentMemoryDirectLimit(map) ?? inheritedLimit;
        final nodePriority =
            _agentMemoryDirectPriority(map) ?? inheritedPriority;
        final nodeFallbackWhenPreviousEmpty =
            inheritedFallbackWhenPreviousEmpty ||
                _agentMemoryPlanIsFallback(map);
        final nodeQueryGroup =
            _agentMemoryPlanQueryGroup(map) ?? inheritedQueryGroup;
        final allMatchQueries = _agentMemoryPlanAllMatchQueries(map);
        if (allMatchQueries.length > 1) {
          addRequest(
            allMatchQueries.join(' '),
            _agentMemoryArgsWithRequiredContentTerms(
              nodeArgs,
              allMatchQueries,
            ),
            limit: nodeLimit,
            priority: nodePriority,
            fallbackWhenPreviousEmpty: nodeFallbackWhenPreviousEmpty,
            queryGroup: nodeQueryGroup,
          );
          return;
        }
        for (final key in const [
          'query',
          'q',
          'keyword',
          '关键词',
          '查询',
          'question',
          '问题',
          'text',
          '文本',
          'prompt',
          '提示词',
          'queryText',
          'query_text',
          'searchText',
          'search_text',
          'content',
          'value',
          'values',
          'modelText',
          'model_text',
          'modelInput',
          'model_input',
          'semanticQuery',
          'semantic_query',
          'vectorQuery',
          'vector_query',
          'embeddingQuery',
          'embedding_query',
          '向量查询',
          '语义查询',
          '向量检索',
          '语义检索',
          'term',
          'match',
          'prefix',
          'wildcard',
          'regexp',
          'match_bool_prefix',
          'matchBoolPrefix',
          'match_phrase',
          'matchPhrase',
        ]) {
          final value = map[key];
          if (key == 'match' &&
              _agentMemoryMatchValueLooksLikeOperator(value)) {
            continue;
          }
          if (key == 'term' && isStructuredPlanValue(value)) {
            if (_agentMemoryMapHasOnlyNonContentFilterFields(value)) {
              continue;
            }
            addPlanNode(
              value,
              nodeArgs,
              inheritedLimit: nodeLimit,
              inheritedPriority: nodePriority,
              inheritedFallbackWhenPreviousEmpty: nodeFallbackWhenPreviousEmpty,
              inheritedQueryGroup: nodeQueryGroup,
            );
          } else if (key != 'term' && isStructuredPlanValue(value)) {
            addPlanNode(
              value,
              nodeArgs,
              inheritedLimit: nodeLimit,
              inheritedPriority: nodePriority,
              inheritedFallbackWhenPreviousEmpty: nodeFallbackWhenPreviousEmpty,
              inheritedQueryGroup: nodeQueryGroup,
            );
          } else {
            addTextRequests(
              value,
              nodeArgs,
              limit: nodeLimit,
              priority: nodePriority,
              fallbackWhenPreviousEmpty: nodeFallbackWhenPreviousEmpty,
              queryGroup: nodeQueryGroup,
            );
          }
        }
        final childArgs = {
          ...inheritedArgs,
          ..._agentMemoryPlanInheritedFilterArgs(map),
          if (_agentMemoryPlanRequiresVectorIndex(map)) 'onlyVectorIndex': true,
        };
        for (final key in const [
          'queryPlan',
          'query_plan',
          'retrievalPlan',
          'retrieval_plan',
          'searchPlan',
          'search_plan',
          'searchQueries',
          'search_queries',
          'plannedQueries',
          'planned_queries',
          '查询计划',
          '检索计划',
          '搜索计划',
          'queries',
          'queryList',
          'query_list',
          'keywords',
          'keywordList',
          'keyword_list',
          'semanticQueries',
          'semantic_queries',
          'vectorQueries',
          'vector_queries',
          'embeddingQueries',
          'embedding_queries',
          'terms',
          '查询列表',
          '关键词列表',
          '向量查询列表',
          '语义查询列表',
          '问题列表',
          'prompts',
          'items',
          'steps',
        ]) {
          addPlanNode(
            map[key],
            childArgs,
            inheritedLimit: nodeLimit,
            inheritedPriority: nodePriority,
            inheritedFallbackWhenPreviousEmpty: nodeFallbackWhenPreviousEmpty,
            inheritedQueryGroup: nodeQueryGroup,
          );
        }
        for (final key in _agentMemoryStructuredQueryClauseKeys) {
          addPlanNode(
            map[key],
            childArgs,
            inheritedLimit: nodeLimit,
            inheritedPriority: nodePriority,
            inheritedFallbackWhenPreviousEmpty: nodeFallbackWhenPreviousEmpty,
            inheritedQueryGroup: nodeQueryGroup,
          );
        }
        for (final key in _agentMemoryStructuredVectorClauseKeys) {
          addPlanNode(
            map[key],
            childArgs,
            inheritedLimit: nodeLimit,
            inheritedPriority: nodePriority,
            inheritedFallbackWhenPreviousEmpty: nodeFallbackWhenPreviousEmpty,
            inheritedQueryGroup: nodeQueryGroup,
          );
        }
        for (final key in _agentMemoryHybridRetrieverClauseKeys) {
          addPlanNode(
            map[key],
            childArgs,
            inheritedLimit: nodeLimit,
            inheritedPriority: nodePriority,
            inheritedFallbackWhenPreviousEmpty: nodeFallbackWhenPreviousEmpty,
            inheritedQueryGroup: nodeQueryGroup,
          );
        }
        for (final key in _agentMemoryVectorQueryBuilderKeys) {
          addPlanNode(
            map[key],
            childArgs,
            inheritedLimit: nodeLimit,
            inheritedPriority: nodePriority,
            inheritedFallbackWhenPreviousEmpty: nodeFallbackWhenPreviousEmpty,
            inheritedQueryGroup: nodeQueryGroup,
          );
        }
        if (requests.length == requestCountBeforeNode) {
          final derivedQuery = _agentMemoryDerivedFilterQuery(nodeArgs);
          if (derivedQuery.isNotEmpty) {
            addRequest(
              derivedQuery,
              nodeArgs,
              limit: nodeLimit,
              priority: nodePriority,
              fallbackWhenPreviousEmpty: nodeFallbackWhenPreviousEmpty,
              queryGroup: nodeQueryGroup,
            );
          }
        }
        return;
      }
      if (raw is Iterable) {
        for (final item in raw) {
          addPlanNode(
            item,
            inheritedArgs,
            inheritedLimit: inheritedLimit,
            inheritedPriority: inheritedPriority,
            inheritedFallbackWhenPreviousEmpty:
                inheritedFallbackWhenPreviousEmpty,
            inheritedQueryGroup: inheritedQueryGroup,
          );
        }
        return;
      }
      addTextRequests(
        raw,
        inheritedArgs,
        limit: inheritedLimit,
        priority: inheritedPriority,
        fallbackWhenPreviousEmpty: inheritedFallbackWhenPreviousEmpty,
        queryGroup: inheritedQueryGroup,
      );
    }

    final single = _stringArgAny(args, const [
      'keyword',
      '关键词',
      'query',
      '查询',
      'question',
      '问题',
      'text',
      '文本',
      'prompt',
      '提示词',
      'semanticQuery',
      'semantic_query',
      'vectorQuery',
      'vector_query',
      'embeddingQuery',
      'embedding_query',
      '向量查询',
      '语义查询',
      '向量检索',
      '语义检索',
      'q',
    ]);
    final basePriority = _agentMemoryDirectPriority(args) ?? 0;
    final baseFallbackWhenPreviousEmpty = _agentMemoryPlanIsFallback(args);
    final baseQueryGroup = _agentMemoryPlanQueryGroup(args);
    if (single.isNotEmpty) {
      addRequest(
        single,
        baseArgs,
        priority: basePriority,
        fallbackWhenPreviousEmpty: baseFallbackWhenPreviousEmpty,
        queryGroup: baseQueryGroup,
      );
    }
    final directQueries = _stringListAny(args, const [
          'queries',
          'queryList',
          'query_list',
          'keywords',
          'keywordList',
          'keyword_list',
          'semanticQueries',
          'semantic_queries',
          'vectorQueries',
          'vector_queries',
          'embeddingQueries',
          'embedding_queries',
          '查询列表',
          '关键词列表',
          '向量查询列表',
          '语义查询列表',
          '问题列表',
          'prompts',
        ]) ??
        const <String>[];
    if (directQueries.length > 1 && _agentMemoryPlanRequiresAll(args)) {
      addRequest(
        directQueries.join(' '),
        _agentMemoryArgsWithRequiredContentTerms(baseArgs, directQueries),
        priority: basePriority,
        fallbackWhenPreviousEmpty: baseFallbackWhenPreviousEmpty,
        queryGroup: baseQueryGroup,
      );
    } else {
      for (final item in directQueries) {
        addRequest(
          item,
          baseArgs,
          priority: basePriority,
          fallbackWhenPreviousEmpty: baseFallbackWhenPreviousEmpty,
          queryGroup: baseQueryGroup,
        );
      }
    }
    for (final key in const [
      'queryPlan',
      'query_plan',
      'retrievalPlan',
      'retrieval_plan',
      'searchPlan',
      'search_plan',
      'searchQueries',
      'search_queries',
      'plannedQueries',
      'planned_queries',
      '查询计划',
      '检索计划',
      '搜索计划',
    ]) {
      addPlanNode(
        args[key],
        baseArgs,
        inheritedPriority: basePriority,
        inheritedFallbackWhenPreviousEmpty: baseFallbackWhenPreviousEmpty,
        inheritedQueryGroup: baseQueryGroup,
      );
    }
    return requests;
  }

  List<String> _agentMemoryPlanAllMatchQueries(Map<String, dynamic> args) {
    if (!_agentMemoryPlanRequiresAll(args)) return const [];
    final values = <String>[];

    void add(Object? raw) {
      final items = _coerceStringList(raw);
      if (items == null) return;
      for (final item in items) {
        final trimmed = item.trim();
        if (trimmed.isNotEmpty && !values.contains(trimmed)) {
          values.add(trimmed);
        }
      }
    }

    void collect(Object? raw) {
      if (raw == null) return;
      if (raw is Map) {
        for (final key in const [
          'query',
          'q',
          'keyword',
          '关键词',
          '查询',
          'question',
          '问题',
          'text',
          '文本',
          'prompt',
          '提示词',
          'queryText',
          'query_text',
          'searchText',
          'search_text',
          'content',
          'value',
          'values',
          'modelText',
          'model_text',
          'modelInput',
          'model_input',
          'semanticQuery',
          'semantic_query',
          'vectorQuery',
          'vector_query',
          'embeddingQuery',
          'embedding_query',
          '向量查询',
          '语义查询',
          '向量检索',
          '语义检索',
          'term',
          'match',
          'prefix',
          'wildcard',
          'regexp',
          'match_bool_prefix',
          'matchBoolPrefix',
          'match_phrase',
          'matchPhrase',
        ]) {
          if (key == 'match' &&
              _agentMemoryMatchValueLooksLikeOperator(raw[key])) {
            continue;
          }
          add(raw[key]);
        }
        for (final key in const [
          'queries',
          'queryList',
          'query_list',
          'keywords',
          'keywordList',
          'keyword_list',
          'semanticQueries',
          'semantic_queries',
          'vectorQueries',
          'vector_queries',
          'embeddingQueries',
          'embedding_queries',
          'terms',
          '查询列表',
          '关键词列表',
          '向量查询列表',
          '语义查询列表',
          '问题列表',
          'prompts',
          'items',
          'steps',
        ]) {
          collect(raw[key]);
        }
        for (final key in _agentMemoryStructuredQueryClauseKeys) {
          collect(raw[key]);
        }
        for (final key in _agentMemoryStructuredVectorClauseKeys) {
          collect(raw[key]);
        }
        for (final key in _agentMemoryHybridRetrieverClauseKeys) {
          collect(raw[key]);
        }
        for (final key in _agentMemoryVectorQueryBuilderKeys) {
          collect(raw[key]);
        }
        return;
      }
      if (raw is Iterable) {
        for (final item in raw) {
          collect(item);
        }
        return;
      }
      add(raw);
    }

    collect(args);
    return values;
  }

  Map<String, dynamic> _agentMemoryArgsWithRequiredContentTerms(
    Map<String, dynamic> args,
    List<String> requiredTerms,
  ) {
    final terms = <String>[];
    void add(Object? raw) {
      final items = _coerceStringList(raw);
      if (items == null) return;
      for (final item in items) {
        final trimmed = item.trim();
        if (trimmed.isNotEmpty && !terms.contains(trimmed)) {
          terms.add(trimmed);
        }
      }
    }

    add(args['mustInclude']);
    add(args['mustIncludeTerms']);
    add(args['includeTerms']);
    add(args['requiredTerms']);
    add(requiredTerms);
    return {
      ...args,
      'mustInclude': terms,
    };
  }

  String _agentMemoryDerivedFilterQuery(Map<String, dynamic> args) {
    final terms = <String>[];
    void addAll(Iterable<String> values) {
      for (final value in values) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty && !terms.contains(trimmed)) {
          terms.add(trimmed);
        }
      }
    }

    addAll(_agentMemoryRequiredContentTerms(args));
    addAll(_agentMemoryShouldContentTerms(args));
    return terms.join(' ');
  }

  bool _agentMemoryPlanRequiresVectorIndex(Map<String, dynamic> args) {
    for (final key in _agentMemoryStructuredVectorClauseKeys) {
      if (args.containsKey(key) && args[key] != null) return true;
    }
    for (final key in _agentMemoryVectorQueryBuilderKeys) {
      if (args.containsKey(key) && args[key] != null) return true;
    }
    return false;
  }

  bool _agentMemoryPlanRequiresAll(Map<String, dynamic> args) {
    final explicitBool = _coerceBool(args['mustMatchAll'] ??
        args['matchAll'] ??
        args['requireAll'] ??
        args['allQueriesRequired'] ??
        args['allTermsRequired'] ??
        args['必须全部命中'] ??
        args['全部命中'] ??
        args['全部匹配']);
    if (explicitBool == true) return true;
    final raw = args['match'] ??
        args['matchMode'] ??
        args['operator'] ??
        args['mode'] ??
        args['组合方式'] ??
        args['匹配模式'];
    if (raw == null) return false;
    final value = raw.toString().trim().toLowerCase();
    switch (value) {
      case 'all':
      case 'and':
      case 'intersection':
      case 'intersect':
      case 'must_all':
      case 'must-all':
      case 'must all':
      case '全部':
      case '全部命中':
      case '全部匹配':
      case '必须全部命中':
      case '并且':
      case '交集':
        return true;
      default:
        return false;
    }
  }

  bool _agentMemoryMatchValueLooksLikeOperator(Object? raw) {
    if (raw == null || raw is! String) return false;
    switch (raw.trim().toLowerCase()) {
      case 'all':
      case 'and':
      case 'intersection':
      case 'intersect':
      case 'must_all':
      case 'must-all':
      case 'must all':
      case 'any':
      case 'or':
      case 'should':
      case '全部':
      case '全部命中':
      case '全部匹配':
      case '必须全部命中':
      case '任一':
      case '任意':
      case '并且':
      case '或者':
      case '交集':
        return true;
      default:
        return false;
    }
  }

  bool _agentMemoryPlanIsFallback(Map<String, dynamic> args) {
    final explicitRaw = args['fallback'] ??
        args['fallbackOnly'] ??
        args['fallback_only'] ??
        args['useAsFallback'] ??
        args['use_as_fallback'] ??
        args['whenEmpty'] ??
        args['when_empty'] ??
        args['onlyWhenEmpty'] ??
        args['only_when_empty'] ??
        args['ifEmpty'] ??
        args['if_empty'] ??
        args['仅在无结果时使用'] ??
        args['无结果时使用'] ??
        args['兜底'];
    final explicitBool = _coerceBool(explicitRaw);
    if (explicitBool == true) return true;
    if (_isAgentMemoryFallbackCondition(explicitRaw)) return true;
    final raw = args['when'] ?? args['condition'] ?? args['条件'];
    return _isAgentMemoryFallbackCondition(raw);
  }

  bool _isAgentMemoryFallbackCondition(Object? raw) {
    if (raw == null) return false;
    final value = raw.toString().trim().toLowerCase();
    switch (value) {
      case 'empty':
      case 'no_results':
      case 'no-results':
      case 'no results':
      case 'if_empty':
      case 'if-empty':
      case 'if empty':
      case 'fallback':
      case '无结果':
      case '没有结果':
      case '前序无结果':
      case '兜底':
        return true;
      default:
        return false;
    }
  }

  String? _agentMemoryPlanQueryGroup(Map<String, dynamic> args) {
    final raw = args['group'] ??
        args['groupId'] ??
        args['group_id'] ??
        args['queryGroup'] ??
        args['query_group'] ??
        args['fallbackGroup'] ??
        args['fallback_group'] ??
        args['retrievalGroup'] ??
        args['retrieval_group'] ??
        args['topic'] ??
        args['检索分组'] ??
        args['兜底分组'] ??
        args['查询分组'] ??
        args['主题'];
    final value = raw?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  Map<String, dynamic> _agentMemoryArgsWithoutQueryPlan(
    Map<String, dynamic> args,
  ) {
    final copy = _agentMemoryArgsWithFilterWrappers(args);
    for (final key in const [
      'queryPlan',
      'query_plan',
      'retrievalPlan',
      'retrieval_plan',
      'searchPlan',
      'search_plan',
      'searchQueries',
      'search_queries',
      'plannedQueries',
      'planned_queries',
      '查询计划',
      '检索计划',
      '搜索计划',
    ]) {
      copy.remove(key);
    }
    return copy;
  }

  Map<String, dynamic> _agentMemoryPlanFilterArgs(
    Map<String, dynamic> args,
  ) {
    final copy = _agentMemoryArgsWithFilterWrappers(args);
    for (final key in const [
      'queryPlan',
      'query_plan',
      'retrievalPlan',
      'retrieval_plan',
      'searchPlan',
      'search_plan',
      'searchQueries',
      'search_queries',
      'plannedQueries',
      'planned_queries',
      '查询计划',
      '检索计划',
      '搜索计划',
      'queries',
      'queryList',
      'query_list',
      'keywords',
      'keywordList',
      'keyword_list',
      'terms',
      '查询列表',
      '关键词列表',
      '问题列表',
      'prompts',
      'items',
      'steps',
    ]) {
      copy.remove(key);
    }
    for (final key in _agentMemoryHybridRetrieverClauseKeys) {
      copy.remove(key);
    }
    _removeUnsupportedAgentMemoryTypeHints(copy);
    return copy;
  }

  Map<String, dynamic> _agentMemoryArgsWithFilterWrappers(
    Map<String, dynamic> args,
  ) {
    final copy = <String, dynamic>{};
    final filterMustClauses = <Object?>[];
    final excludedClauses = <Object?>[];

    bool isDslContentClause(Object? raw) {
      if (raw is! Map) return false;
      for (final key in const [
        'term',
        'terms',
        'match',
        'prefix',
        'wildcard',
        'regexp',
        'match_bool_prefix',
        'matchBoolPrefix',
        'match_phrase',
        'matchPhrase',
      ]) {
        if (raw.containsKey(key)) return true;
      }
      return false;
    }

    void collectFilterMustClauses(Object? raw) {
      if (raw == null || raw is String) return;
      if (isDslContentClause(raw)) {
        filterMustClauses.add(raw);
        return;
      }
      if (raw is Iterable) {
        for (final item in raw) {
          collectFilterMustClauses(item);
        }
      }
    }

    void appendFilterMustClauses() {
      if (filterMustClauses.isEmpty) return;
      final values = <Object?>[];
      final existing = copy['must'];
      if (existing is Iterable && existing is! String) {
        values.addAll(existing);
      } else if (existing != null) {
        values.add(existing);
      }
      values.addAll(filterMustClauses);
      copy['must'] = values;
    }

    void collectExcludedClauses(Object? raw) {
      if (raw == null) return;
      if (raw is Iterable && raw is! String) {
        for (final item in raw) {
          collectExcludedClauses(item);
        }
        return;
      }
      excludedClauses.add(raw);
    }

    void appendExcludedClauses() {
      if (excludedClauses.isEmpty) return;
      final values = <Object?>[];
      final existing = copy['must_not'];
      if (existing is Iterable && existing is! String) {
        values.addAll(existing);
      } else if (existing != null) {
        values.add(existing);
      }
      values.addAll(excludedClauses);
      copy['must_not'] = values;
    }

    Object? firstByKey(Map<String, dynamic> source, List<String> keys) {
      for (final key in keys) {
        if (source.containsKey(key)) return source[key];
      }
      return null;
    }

    void mergeWrapper(Object? raw) {
      if (raw == null) return;
      if (raw is Map) {
        final nested = <String, dynamic>{
          for (final entry in raw.entries)
            if (entry.key is String) (entry.key as String): entry.value,
        };
        copy.addAll(_agentMemoryArgsWithFilterWrappers(nested));
        return;
      }
      if (raw is Iterable) {
        for (final item in raw) {
          mergeWrapper(item);
        }
      }
    }

    void mergeBoostingWrapper(Object? raw) {
      if (raw == null) return;
      if (raw is Map) {
        final nested = <String, dynamic>{
          for (final entry in raw.entries)
            if (entry.key is String) (entry.key as String): entry.value,
        };
        final positive = firstByKey(nested, const [
          'positive',
          'positiveQuery',
          'positive_query',
          '正向查询',
          '正向',
        ]);
        collectFilterMustClauses(positive);
        mergeWrapper(positive);
        collectExcludedClauses(firstByKey(nested, const [
          'negative',
          'negativeQuery',
          'negative_query',
          '负向查询',
          '负向',
        ]));
        return;
      }
      if (raw is Iterable && raw is! String) {
        for (final item in raw) {
          mergeBoostingWrapper(item);
        }
      }
    }

    bool isStructuredWrapperValue(Object? raw) =>
        raw is Map || (raw is Iterable && raw is! String);

    if (args.containsKey('positive') || args.containsKey('negative')) {
      mergeBoostingWrapper(args);
    }
    for (final key in _agentMemoryFilterWrapperKeys) {
      if (key == 'filter' ||
          key == 'filters' ||
          key == 'post_filter' ||
          key == 'postFilter') {
        collectFilterMustClauses(args[key]);
      }
      mergeWrapper(args[key]);
    }
    for (final key in _agentMemoryStructuredDslWrapperKeys) {
      final value = args[key];
      if (!isStructuredWrapperValue(value)) continue;
      if (key == 'boosting') {
        mergeBoostingWrapper(value);
      } else {
        mergeWrapper(value);
      }
    }
    copy.addAll(args);
    for (final key in _agentMemoryFilterWrapperKeys) {
      copy.remove(key);
    }
    for (final key in _agentMemoryStructuredDslWrapperKeys) {
      if (isStructuredWrapperValue(args[key])) copy.remove(key);
    }
    for (final key in const [
      'positive',
      'positiveQuery',
      'positive_query',
      '正向查询',
      '正向',
      'negative',
      'negativeQuery',
      'negative_query',
      '负向查询',
      '负向',
      'negative_boost',
      'negativeBoost',
    ]) {
      copy.remove(key);
    }
    _mergeAgentMemoryFieldFilterArgs(copy, _agentMemoryFieldFilterArgs(args));
    appendFilterMustClauses();
    appendExcludedClauses();
    return copy;
  }

  Map<String, dynamic> _agentMemoryFieldFilterArgs(
    Map<String, dynamic> args,
  ) {
    final roles = <String>{};
    final excludeRoles = <String>{};
    final types = <String>{};
    final scopes = <String>{};

    void addStrings(Set<String> target, Object? raw) {
      void addCandidate(Object? candidate) {
        final items = _coerceStringSet(candidate);
        if (items != null) target.addAll(items);
      }

      if (raw is Map) {
        for (final key in const [
          'value',
          'values',
          'term',
          'terms',
          'query',
          'q',
          '字段值',
          '值',
        ]) {
          if (raw.containsKey(key)) addCandidate(raw[key]);
        }
        return;
      }
      addCandidate(raw);
    }

    void collectTermFields(Object? raw, {required bool negative}) {
      if (raw == null || raw is String || raw is num || raw is bool) return;
      if (raw is Iterable) {
        for (final item in raw) {
          collectTermFields(item, negative: negative);
        }
        return;
      }
      if (raw is! Map) return;
      for (final entry in raw.entries) {
        final key = entry.key;
        if (key is! String) continue;
        final value = entry.value;
        if (_agentMemoryIsRoleFilterFieldKey(key)) {
          addStrings(negative ? excludeRoles : roles, value);
        } else if (!negative && _agentMemoryIsTypeFilterFieldKey(key)) {
          addStrings(types, value);
        } else if (!negative && _agentMemoryIsScopeFilterFieldKey(key)) {
          addStrings(scopes, value);
        }
      }
    }

    void collect(Object? raw, {bool negative = false}) {
      if (raw == null || raw is String || raw is num || raw is bool) return;
      if (raw is Iterable) {
        for (final item in raw) {
          collect(item, negative: negative);
        }
        return;
      }
      if (raw is! Map) return;
      final map = <String, dynamic>{
        for (final entry in raw.entries)
          if (entry.key is String) (entry.key as String): entry.value,
      };
      collectTermFields(map['term'], negative: negative);
      collectTermFields(map['terms'], negative: negative);
      for (final key in const [
        'queryPlan',
        'query_plan',
        'retrievalPlan',
        'retrieval_plan',
        'searchPlan',
        'search_plan',
        'searchQueries',
        'search_queries',
        'plannedQueries',
        'planned_queries',
        'queries',
        'queryList',
        'query_list',
        'keywords',
        'keywordList',
        'keyword_list',
        '查询计划',
        '检索计划',
        '搜索计划',
        '查询列表',
        '关键词列表',
        '问题列表',
        'prompts',
        'items',
        'steps',
        'query',
        '查询',
        'dsl',
        'esQuery',
        'es_query',
        'searchQuery',
        'search_query',
        'bool',
        'filter',
        'filters',
        'post_filter',
        'postFilter',
        'where',
        'criteria',
        'constraints',
        'condition',
        'conditions',
        'must',
        'should',
        'constant_score',
        'constantScore',
        'function_score',
        'functionScore',
        'nested',
        'positive',
        'positiveQuery',
        'positive_query',
        '正向查询',
        '正向',
      ]) {
        collect(map[key], negative: negative);
      }
      for (final key in const [
        'must_not',
        'mustNot',
        'negative',
        'negativeQuery',
        'negative_query',
        '负向查询',
        '负向',
      ]) {
        collect(map[key], negative: true);
      }
    }

    collect(args);
    return {
      if (roles.isNotEmpty) 'roles': roles.toList(),
      if (excludeRoles.isNotEmpty) 'excludeRoles': excludeRoles.toList(),
      if (types.isNotEmpty) 'types': types.toList(),
      if (scopes.isNotEmpty) 'scopes': scopes.toList(),
    };
  }

  void _mergeAgentMemoryFieldFilterArgs(
    Map<String, dynamic> target,
    Map<String, dynamic> filters,
  ) {
    void merge(String key, List<String> aliases) {
      final values = <String>{};
      void add(Object? raw) {
        final items = _coerceStringSet(raw);
        if (items != null) values.addAll(items);
      }

      for (final alias in aliases) {
        add(target[alias]);
      }
      add(filters[key]);
      if (values.isNotEmpty) target[key] = values.toList();
    }

    merge('roles', const [
      'roles',
      'role',
      '角色',
      'memoryRoles',
      'memoryRole',
      '记忆角色',
      'memory_roles',
      'memory_role',
    ]);
    merge('excludeRoles', const [
      'excludeRoles',
      'excludeRole',
      'excludedRoles',
      'excluded_roles',
      'excludeMemoryRoles',
      'exclude_memory_roles',
      'excludedMemoryRoles',
      'excluded_memory_roles',
      '排除角色',
      '排除记忆角色',
    ]);
    merge('types', const [
      'types',
      'type',
      '类型',
      'memoryTypes',
      'memoryType',
      'memory_types',
      'memory_type',
      '记忆类型',
    ]);
    merge('scopes', const [
      'scopes',
      'scope',
      '范围',
      'memoryScopes',
      'memoryScope',
      'memory_scopes',
      'memory_scope',
      '记忆范围',
    ]);
  }

  String _normalizeAgentMemoryFilterFieldKey(String key) {
    return key.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  }

  bool _agentMemoryIsRoleFilterFieldKey(String key) {
    switch (_normalizeAgentMemoryFilterFieldKey(key)) {
      case 'role':
      case 'roles':
      case 'memoryrole':
      case 'memoryroles':
      case '角色':
      case '记忆角色':
        return true;
      default:
        return false;
    }
  }

  bool _agentMemoryIsTypeFilterFieldKey(String key) {
    switch (_normalizeAgentMemoryFilterFieldKey(key)) {
      case 'type':
      case 'types':
      case 'memorytype':
      case 'memorytypes':
      case '类型':
      case '记忆类型':
        return true;
      default:
        return false;
    }
  }

  bool _agentMemoryIsScopeFilterFieldKey(String key) {
    switch (_normalizeAgentMemoryFilterFieldKey(key)) {
      case 'scope':
      case 'scopes':
      case 'memoryscope':
      case 'memoryscopes':
      case '范围':
      case '记忆范围':
        return true;
      default:
        return false;
    }
  }

  bool _agentMemoryIsNonContentFilterFieldKey(String key) {
    if (_agentMemoryIsRoleFilterFieldKey(key) ||
        _agentMemoryIsTypeFilterFieldKey(key) ||
        _agentMemoryIsScopeFilterFieldKey(key)) {
      return true;
    }
    switch (_normalizeAgentMemoryFilterFieldKey(key)) {
      case 'id':
      case 'ids':
      case 'memoryid':
      case 'memoryids':
      case 'messageid':
      case 'messageids':
      case 'summaryid':
      case 'summaryids':
      case 'noteid':
      case 'noteids':
      case 'recordid':
      case 'recordids':
      case 'createdat':
      case 'createdafter':
      case 'createdbefore':
      case 'createtime':
      case 'createtimeafter':
      case 'createtimebefore':
      case 'timestamp':
      case 'time':
      case 'starttime':
      case 'endtime':
      case 'fromtime':
      case 'totime':
      case 'from':
      case 'offset':
      case 'skip':
      case 'startindex':
      case 'startfrom':
      case 'retrievalsource':
      case 'retrievalsources':
      case 'onlyvectorindex':
      case 'vectoronly':
      case 'requirevectorindex':
      case 'minscore':
      case 'minimumscore':
      case 'scorethreshold':
      case 'minsimilarity':
      case 'minimumsimilarity':
      case 'similaritythreshold':
      case 'orderby':
      case 'sortby':
      case 'sortorder':
      case 'order':
      case '创建时间':
      case '时间':
      case '开始时间':
      case '结束时间':
      case '之后':
      case '之前':
      case '跳过数量':
      case '检索来源':
      case '召回来源':
      case '只用向量索引':
      case '仅向量索引':
      case '最低分':
      case '分数阈值':
      case '相似度':
      case '最低相似度':
      case '相似度阈值':
      case '排序':
      case '排序方式':
        return true;
      default:
        return false;
    }
  }

  bool _agentMemoryMapHasOnlyNonContentFilterFields(Object? raw) {
    if (raw is! Map) return false;
    var hasStringKey = false;
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) continue;
      hasStringKey = true;
      if (!_agentMemoryIsNonContentFilterFieldKey(key)) return false;
    }
    return hasStringKey;
  }

  void _removeUnsupportedAgentMemoryTypeHints(Map<String, dynamic> args) {
    for (final key in const [
      'types',
      'type',
      '类型',
      'memoryTypes',
      'memoryType',
      'memory_types',
      'memory_type',
      '记忆类型',
      'scopes',
      'scope',
      '范围',
      'memoryScopes',
      'memoryScope',
      'memory_scopes',
      'memory_scope',
      '记忆范围',
    ]) {
      if (args.containsKey(key) &&
          !_hasSupportedAgentMemoryTypeHint(args[key])) {
        args.remove(key);
      }
    }
  }

  bool _hasSupportedAgentMemoryTypeHint(Object? raw) {
    final items = _coerceStringSet(raw);
    if (items == null) return false;
    for (final item in items) {
      switch (item.trim().toLowerCase()) {
        case 'message':
        case 'messages':
        case 'chat':
        case '普通记忆':
        case '消息':
        case '聊天':
        case 'conversation':
        case 'conversations':
        case 'history':
        case '对话':
        case '对话记忆':
        case '历史':
        case '短期记忆':
        case 'summary':
        case 'summaries':
        case '摘要':
        case '摘要记忆':
        case '历史摘要':
        case 'long_term':
        case 'long-term':
        case 'longterm':
        case 'note':
        case 'notes':
        case 'project':
        case '长期':
        case '长期记忆':
        case '项目记忆':
        case '设定记忆':
        case 'all':
        case '全部':
        case '所有':
        case '全量':
          return true;
      }
    }
    return false;
  }

  Map<String, dynamic> _agentMemoryPlanInheritedFilterArgs(
    Map<String, dynamic> args,
  ) {
    final copy = _agentMemoryPlanFilterArgs(args);
    for (final key in const [
      'query',
      'q',
      'keyword',
      '关键词',
      '查询',
      'question',
      '问题',
      'text',
      '文本',
      'prompt',
      '提示词',
      'queryText',
      'query_text',
      'searchText',
      'search_text',
      'content',
      'value',
      'values',
      'modelText',
      'model_text',
      'modelInput',
      'model_input',
      'semanticQuery',
      'semantic_query',
      'vectorQuery',
      'vector_query',
      'embeddingQuery',
      'embedding_query',
      '向量查询',
      '语义查询',
      '向量检索',
      '语义检索',
      'term',
      'match',
      'prefix',
      'wildcard',
      'regexp',
      'match_bool_prefix',
      'matchBoolPrefix',
      'match_phrase',
      'matchPhrase',
    ]) {
      copy.remove(key);
    }
    for (final key in _agentMemoryStructuredQueryClauseKeys) {
      copy.remove(key);
    }
    for (final key in _agentMemoryStructuredVectorClauseKeys) {
      copy.remove(key);
    }
    for (final key in _agentMemoryHybridRetrieverClauseKeys) {
      copy.remove(key);
    }
    for (final key in _agentMemoryVectorQueryBuilderKeys) {
      copy.remove(key);
    }
    return copy;
  }

  List<String> _agentMemoryRequestQueries(
    List<_AgentMemoryQueryRequest> requests,
  ) {
    final values = <String>[];
    for (final request in requests) {
      if (!values.contains(request.query)) values.add(request.query);
    }
    return values;
  }

  List<Object?> _agentMemoryQueryPlanMemoryTypeValues(
    Map<String, dynamic> args,
  ) =>
      _agentMemoryQueryPlanFilterValues(args, const [
        'types',
        'type',
        '类型',
        'memoryTypes',
        'memoryType',
        'memory_types',
        'memory_type',
        '记忆类型',
        'scopes',
        'scope',
        '范围',
        'memoryScopes',
        'memoryScope',
        'memory_scopes',
        'memory_scope',
        '记忆范围',
      ]);

  List<Object?> _agentMemoryQueryPlanFilterValues(
    Map<String, dynamic> args,
    Iterable<String> valueKeys,
  ) {
    final values = <Object?>[];
    final keySet = valueKeys.toSet();

    void addValue(Object? raw) {
      if (raw == null) return;
      if (raw is bool) {
        values.add(raw);
        return;
      }
      if (raw is num) {
        values.add(raw);
        return;
      }
      if (raw is String) {
        if (raw.trim().isNotEmpty) values.add(raw);
        return;
      }
      if (raw is Iterable) {
        final strings = <String>[];
        for (final item in raw) {
          if (item is String) {
            final trimmed = item.trim();
            if (trimmed.isNotEmpty) strings.add(trimmed);
          } else {
            addValue(item);
          }
        }
        if (strings.isNotEmpty) values.add(strings);
      }
    }

    void addNode(Object? raw) {
      if (raw == null) return;
      if (raw is Map) {
        for (final key in keySet) {
          addValue(raw[key]);
        }
        for (final key in const [
          'queryPlan',
          'query_plan',
          'retrievalPlan',
          'retrieval_plan',
          'searchPlan',
          'search_plan',
          'searchQueries',
          'search_queries',
          'plannedQueries',
          'planned_queries',
          'queries',
          'queryList',
          'query_list',
          'keywords',
          'keywordList',
          'keyword_list',
          'term',
          'terms',
          '查询计划',
          '检索计划',
          '搜索计划',
          '查询列表',
          '关键词列表',
          '问题列表',
          'prompts',
          'items',
          'steps',
        ]) {
          addNode(raw[key]);
        }
        for (final key in _agentMemoryFilterWrapperKeys) {
          addNode(raw[key]);
        }
        for (final key in _agentMemoryStructuredQueryClauseKeys) {
          addNode(raw[key]);
        }
        for (final key in _agentMemoryStructuredVectorClauseKeys) {
          addNode(raw[key]);
        }
        for (final key in _agentMemoryHybridRetrieverClauseKeys) {
          addNode(raw[key]);
        }
        for (final key in _agentMemoryVectorQueryBuilderKeys) {
          addNode(raw[key]);
        }
        return;
      }
      if (raw is Iterable) {
        for (final item in raw) {
          addNode(item);
        }
      }
    }

    for (final key in const [
      'queryPlan',
      'query_plan',
      'retrievalPlan',
      'retrieval_plan',
      'searchPlan',
      'search_plan',
      'searchQueries',
      'search_queries',
      'plannedQueries',
      'planned_queries',
      '查询计划',
      '检索计划',
      '搜索计划',
    ]) {
      addNode(args[key]);
    }
    return values;
  }

  Set<String>? _agentMemoryRoles(Map<String, dynamic> args) {
    final values = <String>{};
    void add(Object? raw) {
      final items = _coerceStringSet(raw);
      if (items != null) values.addAll(items);
    }

    add(args['roles'] ??
        args['role'] ??
        args['角色'] ??
        args['memoryRoles'] ??
        args['memoryRole'] ??
        args['记忆角色'] ??
        args['memory_roles'] ??
        args['memory_role']);
    for (final value in _agentMemoryQueryPlanRoleValues(args)) {
      add(value);
    }
    return values.isEmpty ? null : values;
  }

  List<Object?> _agentMemoryQueryPlanRoleValues(Map<String, dynamic> args) {
    return _agentMemoryQueryPlanFilterValues(args, const [
      'roles',
      'role',
      '角色',
      'memoryRoles',
      'memoryRole',
      'memory_roles',
      'memory_role',
      '记忆角色',
    ]);
  }

  Set<String>? _agentMemoryExcludeRoles(Map<String, dynamic> args) {
    final values = <String>{};
    void add(Object? raw) {
      final items = _coerceStringSet(raw);
      if (items != null) values.addAll(items);
    }

    add(args['excludeRoles'] ??
        args['excludeRole'] ??
        args['excludedRoles'] ??
        args['excluded_roles'] ??
        args['excludeMemoryRoles'] ??
        args['exclude_memory_roles'] ??
        args['excludedMemoryRoles'] ??
        args['excluded_memory_roles'] ??
        args['排除角色'] ??
        args['排除记忆角色']);
    for (final value in _agentMemoryQueryPlanExcludeRoleValues(args)) {
      add(value);
    }
    return values.isEmpty ? null : values;
  }

  List<Object?> _agentMemoryQueryPlanExcludeRoleValues(
    Map<String, dynamic> args,
  ) =>
      _agentMemoryQueryPlanFilterValues(args, const [
        'excludeRoles',
        'excludeRole',
        'excludedRoles',
        'excluded_roles',
        'excludeMemoryRoles',
        'exclude_memory_roles',
        'excludedMemoryRoles',
        'excluded_memory_roles',
        '排除角色',
        '排除记忆角色',
      ]);

  Set<String>? _agentMemoryExcludeRoleSuffixes(Map<String, dynamic> args) {
    final values = <String>{};
    void add(Object? raw) {
      final items = _coerceStringSet(raw);
      if (items != null) values.addAll(items);
    }

    add(args['excludeRoleSuffixes'] ??
        args['excludeRoleSuffix'] ??
        args['excludedRoleSuffixes'] ??
        args['excludeMemoryRoleSuffixes'] ??
        args['excludedMemoryRoleSuffixes'] ??
        args['排除角色后缀']);
    for (final value in _agentMemoryQueryPlanExcludeRoleSuffixValues(args)) {
      add(value);
    }
    return values.isEmpty ? null : values;
  }

  List<Object?> _agentMemoryQueryPlanExcludeRoleSuffixValues(
    Map<String, dynamic> args,
  ) =>
      _agentMemoryQueryPlanFilterValues(args, const [
        'excludeRoleSuffixes',
        'excludeRoleSuffix',
        'excludedRoleSuffixes',
        'excludeMemoryRoleSuffixes',
        'excludedMemoryRoleSuffixes',
        '排除角色后缀',
      ]);

  List<Object?> _agentMemoryQueryPlanScoreThresholdValues(
    Map<String, dynamic> args,
  ) =>
      _agentMemoryQueryPlanFilterValues(args, const [
        'minScore',
        'min_score',
        'minimumScore',
        'minimum_score',
        'scoreThreshold',
        'score_threshold',
        '最低分',
        '分数阈值',
        'threshold',
        'minSimilarity',
        'min_similarity',
        'minimumSimilarity',
        'minimum_similarity',
        'similarityThreshold',
        'similarity_threshold',
        '相似度',
        '最低相似度',
        '相似度阈值',
      ]);

  bool _shouldIncludeVisualReferenceMemories(Map<String, dynamic> args) {
    final explicit = _coerceBool(args['includeVisualReferences'] ??
        args['visualReferences'] ??
        args['include_visual_references'] ??
        args['visual_references'] ??
        args['includeStyleReferences'] ??
        args['styleReferences'] ??
        args['include_style_references'] ??
        args['style_references'] ??
        args['包含视觉参考'] ??
        args['视觉参考'] ??
        args['包含画风参考'] ??
        args['画风参考']);
    if (explicit != null) return explicit;
    for (final value in _agentMemoryQueryPlanVisualReferenceValues(args)) {
      final include = _coerceBool(value);
      if (include != null) return include;
    }
    return false;
  }

  List<Object?> _agentMemoryQueryPlanVisualReferenceValues(
    Map<String, dynamic> args,
  ) =>
      _agentMemoryQueryPlanFilterValues(args, const [
        'includeVisualReferences',
        'visualReferences',
        'include_visual_references',
        'visual_references',
        'includeStyleReferences',
        'styleReferences',
        'include_style_references',
        'style_references',
        '包含视觉参考',
        '视觉参考',
        '包含画风参考',
        '画风参考',
      ]);

  AgentMemoryTimeRange? _agentMemoryTimeRange(Map<String, dynamic> args) {
    final rangeCreatedAfter = _maxCoercedInt(
      _agentMemoryRangeTimeBoundValues(args, lower: true),
    );
    final explicitCreatedAfter = _maxNullableInt(
      _maxNullableInt(
        _coerceInt(
          args['createdAfter'] ??
              args['createTimeAfter'] ??
              args['created_at_after'] ??
              args['since'] ??
              args['after'] ??
              args['startTime'] ??
              args['start_time'] ??
              args['fromTime'] ??
              args['from_time'] ??
              args['开始时间'] ??
              args['之后'],
        ),
        rangeCreatedAfter,
      ),
      _agentMemoryRelativeCreatedAfter(args),
    );
    final planCreatedAfter = explicitCreatedAfter == null
        ? _maxNullableInt(
            _firstCoercedInt(_agentMemoryQueryPlanCreatedAfterValues(args)),
            _agentMemoryQueryPlanRelativeCreatedAfter(args),
          )
        : null;
    final createdAfter = explicitCreatedAfter ?? planCreatedAfter;
    final rangeCreatedBefore = _minCoercedInt(
      _agentMemoryRangeTimeBoundValues(args, lower: false),
    );
    final explicitCreatedBefore = _minNullableInt(
      _coerceInt(
        args['createdBefore'] ??
            args['createTimeBefore'] ??
            args['created_at_before'] ??
            args['until'] ??
            args['before'] ??
            args['endTime'] ??
            args['end_time'] ??
            args['toTime'] ??
            args['to_time'] ??
            args['结束时间'] ??
            args['之前'],
      ),
      rangeCreatedBefore,
    );
    final planCreatedBefore =
        _firstCoercedInt(_agentMemoryQueryPlanCreatedBeforeValues(args));
    final createdBefore =
        _minNullableInt(explicitCreatedBefore, planCreatedBefore);
    if (createdAfter == null && createdBefore == null) return null;
    return AgentMemoryTimeRange(
      createdAfter: createdAfter,
      createdBefore: createdBefore,
    );
  }

  List<Object?> _agentMemoryQueryPlanCreatedAfterValues(
    Map<String, dynamic> args,
  ) =>
      _agentMemoryQueryPlanFilterValues(args, const [
        'createdAfter',
        'createTimeAfter',
        'created_at_after',
        'since',
        'after',
        'startTime',
        'start_time',
        'fromTime',
        'from_time',
        '开始时间',
        '之后',
      ]);

  List<Object?> _agentMemoryQueryPlanCreatedBeforeValues(
    Map<String, dynamic> args,
  ) =>
      _agentMemoryQueryPlanFilterValues(args, const [
        'createdBefore',
        'createTimeBefore',
        'created_at_before',
        'until',
        'before',
        'endTime',
        'end_time',
        'toTime',
        'to_time',
        '结束时间',
        '之前',
      ]);

  List<Object?> _agentMemoryRangeTimeBoundValues(
    Map<String, dynamic> args, {
    required bool lower,
  }) {
    final values = <Object?>[];

    Object? firstByKey(Map<String, dynamic> source, Iterable<String> keys) {
      for (final key in keys) {
        if (source.containsKey(key)) return source[key];
      }
      return null;
    }

    void addBoundMap(Map<String, dynamic> source) {
      final inclusive = firstByKey(
        source,
        lower
            ? const [
                'gte',
                'from',
                'min',
                'start',
                'createdAfter',
                'createTimeAfter',
                'created_at_after',
                'since',
                'after',
                '开始时间',
                '之后',
              ]
            : const [
                'lte',
                'to',
                'max',
                'end',
                'createdBefore',
                'createTimeBefore',
                'created_at_before',
                'until',
                'before',
                '结束时间',
                '之前',
              ],
      );
      if (inclusive != null) {
        values.add(inclusive);
        return;
      }
      final exclusive = firstByKey(
        source,
        lower ? const ['gt'] : const ['lt'],
      );
      final value = _coerceInt(exclusive);
      if (value != null) values.add(lower ? value + 1 : value - 1);
    }

    void collect(Object? raw) {
      if (raw == null || raw is String || raw is num || raw is bool) return;
      if (raw is Iterable) {
        for (final item in raw) {
          collect(item);
        }
        return;
      }
      if (raw is! Map) return;
      final map = <String, dynamic>{
        for (final entry in raw.entries)
          if (entry.key is String) (entry.key as String): entry.value,
      };
      addBoundMap(map);
      for (final key in const [
        'range',
        '范围',
        'timeRange',
        'time_range',
        '时间范围',
      ]) {
        collect(map[key]);
      }
      for (final key in const [
        'createTime',
        'create_time',
        'createdAt',
        'created_at',
        'timestamp',
        'time',
        '时间',
        '创建时间',
      ]) {
        final value = map[key];
        if (value is Map) {
          addBoundMap({
            for (final entry in value.entries)
              if (entry.key is String) (entry.key as String): entry.value,
          });
        }
      }
    }

    for (final key in const [
      'range',
      '范围',
      'timeRange',
      'time_range',
      '时间范围',
    ]) {
      collect(args[key]);
    }
    return values;
  }

  int? _firstCoercedInt(Iterable<Object?> rawValues) {
    for (final raw in rawValues) {
      final value = _coerceInt(raw);
      if (value != null) return value;
    }
    return null;
  }

  int? _maxCoercedInt(Iterable<Object?> rawValues) {
    int? result;
    for (final raw in rawValues) {
      result = _maxNullableInt(result, _coerceInt(raw));
    }
    return result;
  }

  int? _minCoercedInt(Iterable<Object?> rawValues) {
    int? result;
    for (final raw in rawValues) {
      result = _minNullableInt(result, _coerceInt(raw));
    }
    return result;
  }

  int? _agentMemoryRelativeCreatedAfter(Map<String, dynamic> args) {
    int? valueMs(Object? raw, int multiplier) {
      final value = _coerceInt(raw);
      if (value == null || value <= 0) return null;
      return value * multiplier;
    }

    final recentMs = valueMs(
          args['recentMs'] ??
              args['recentMillis'] ??
              args['recentMilliseconds'] ??
              args['lastMs'] ??
              args['lastMillis'] ??
              args['lastMilliseconds'] ??
              args['withinMs'] ??
              args['withinMillis'] ??
              args['withinMilliseconds'] ??
              args['最近毫秒'],
          1,
        ) ??
        valueMs(
          args['recentSeconds'] ??
              args['lastSeconds'] ??
              args['withinSeconds'] ??
              args['最近秒'],
          const Duration(seconds: 1).inMilliseconds,
        ) ??
        valueMs(
          args['recentMinutes'] ??
              args['lastMinutes'] ??
              args['withinMinutes'] ??
              args['最近分钟'],
          const Duration(minutes: 1).inMilliseconds,
        ) ??
        valueMs(
          args['recentHours'] ??
              args['lastHours'] ??
              args['withinHours'] ??
              args['最近小时'],
          const Duration(hours: 1).inMilliseconds,
        ) ??
        valueMs(
          args['recentDays'] ??
              args['lastDays'] ??
              args['withinDays'] ??
              args['最近天'],
          const Duration(days: 1).inMilliseconds,
        );
    if (recentMs == null) return null;
    return DateTime.now().millisecondsSinceEpoch - recentMs;
  }

  int? _agentMemoryQueryPlanRelativeCreatedAfter(Map<String, dynamic> args) {
    int? valueMs(Iterable<Object?> rawValues, int multiplier) {
      final value = _firstCoercedInt(rawValues);
      if (value == null || value <= 0) return null;
      return value * multiplier;
    }

    final recentMs = valueMs(
          _agentMemoryQueryPlanFilterValues(args, const [
            'recentMs',
            'recentMillis',
            'recentMilliseconds',
            'lastMs',
            'lastMillis',
            'lastMilliseconds',
            'withinMs',
            'withinMillis',
            'withinMilliseconds',
            '最近毫秒',
          ]),
          1,
        ) ??
        valueMs(
          _agentMemoryQueryPlanFilterValues(args, const [
            'recentSeconds',
            'lastSeconds',
            'withinSeconds',
            '最近秒',
          ]),
          const Duration(seconds: 1).inMilliseconds,
        ) ??
        valueMs(
          _agentMemoryQueryPlanFilterValues(args, const [
            'recentMinutes',
            'lastMinutes',
            'withinMinutes',
            '最近分钟',
          ]),
          const Duration(minutes: 1).inMilliseconds,
        ) ??
        valueMs(
          _agentMemoryQueryPlanFilterValues(args, const [
            'recentHours',
            'lastHours',
            'withinHours',
            '最近小时',
          ]),
          const Duration(hours: 1).inMilliseconds,
        ) ??
        valueMs(
          _agentMemoryQueryPlanFilterValues(args, const [
            'recentDays',
            'lastDays',
            'withinDays',
            '最近天',
          ]),
          const Duration(days: 1).inMilliseconds,
        );
    if (recentMs == null) return null;
    return DateTime.now().millisecondsSinceEpoch - recentMs;
  }

  int? _maxNullableInt(int? a, int? b) {
    if (a == null) return b;
    if (b == null) return a;
    return math.max(a, b);
  }

  int? _minNullableInt(int? a, int? b) {
    if (a == null) return b;
    if (b == null) return a;
    return math.min(a, b);
  }

  int? _agentMemoryMinScore(Map<String, dynamic> args) {
    final explicitScore = _coerceAgentMemoryScoreThreshold(
      args['minScore'] ??
          args['min_score'] ??
          args['minimumScore'] ??
          args['minimum_score'] ??
          args['scoreThreshold'] ??
          args['score_threshold'] ??
          args['最低分'] ??
          args['分数阈值'] ??
          args['threshold'],
    );
    if (explicitScore != null) return explicitScore;
    final explicitSimilarity = _coerceAgentMemoryScoreThreshold(
      args['minSimilarity'] ??
          args['min_similarity'] ??
          args['minimumSimilarity'] ??
          args['minimum_similarity'] ??
          args['similarityThreshold'] ??
          args['similarity_threshold'] ??
          args['相似度'] ??
          args['最低相似度'] ??
          args['相似度阈值'],
    );
    if (explicitSimilarity != null) return explicitSimilarity;
    for (final value in _agentMemoryQueryPlanScoreThresholdValues(args)) {
      final threshold = _coerceAgentMemoryScoreThreshold(value);
      if (threshold != null) return threshold;
    }
    return null;
  }

  bool? _agentMemoryRerankEnabled(Map<String, dynamic> args) {
    return _coerceBool(args['rerank'] ??
        args['rerankEnabled'] ??
        args['rerank_enabled'] ??
        args['useRerank'] ??
        args['use_rerank'] ??
        args['modelRerank'] ??
        args['model_rerank'] ??
        args['llmRerank'] ??
        args['llm_rerank'] ??
        args['模型重排'] ??
        args['重排'] ??
        args['启用重排']);
  }

  int? _coerceAgentMemoryScoreThreshold(Object? raw) {
    if (raw == null) return null;
    var isPercent = false;
    num? value;
    if (raw is num) {
      value = raw;
    } else if (raw is String) {
      var text = raw.trim();
      if (text.isEmpty) return null;
      if (text.endsWith('%')) {
        isPercent = true;
        text = text.substring(0, text.length - 1).trim();
      }
      value = num.tryParse(text);
    }
    if (value == null || !value.isFinite || value <= 0) return null;
    if (!isPercent && value <= 1) return (value * 100).round().clamp(1, 100);
    return value.round().clamp(1, 100);
  }

  int? _agentMemoryDirectLimit(Map<String, dynamic> args) {
    final explicitRaw = _agentMemoryDirectLimitRaw(args);
    final explicitLimit = _coerceInt(explicitRaw);
    if (explicitLimit != null) return explicitLimit.clamp(1, 50).toInt();
    return null;
  }

  Object? _agentMemoryDirectLimitRaw(Map<String, dynamic> args) =>
      args['limit'] ??
      args['topK'] ??
      args['top_k'] ??
      args['size'] ??
      args['maxResults'] ??
      args['max_results'] ??
      args['max'] ??
      args['count'] ??
      args['数量'] ??
      args['条数'] ??
      args['返回数量'] ??
      args['k'];

  int _agentMemoryDirectOffset(Map<String, dynamic> args) {
    final value = _coerceInt(args['from'] ??
        args['offset'] ??
        args['skip'] ??
        args['startIndex'] ??
        args['start_index'] ??
        args['startFrom'] ??
        args['start_from'] ??
        args['跳过数量']);
    if (value == null) return 0;
    return value.clamp(0, 200).toInt();
  }

  int? _agentMemoryDirectPriority(Map<String, dynamic> args) {
    final raw = args['priority'] ??
        args['priorities'] ??
        args['weight'] ??
        args['importance'] ??
        args['rankPriority'] ??
        args['优先级'] ??
        args['权重'] ??
        args['重要性'];
    final value = _coerceInt(raw);
    if (value != null) return value.clamp(-100, 100).toInt();
    final text = (raw ?? '').toString().trim().toLowerCase();
    switch (text) {
      case 'critical':
      case 'highest':
      case 'high':
      case 'must':
      case '硬性':
      case '最高':
      case '高':
      case '重要':
        return 10;
      case 'medium':
      case 'normal':
      case '中':
      case '普通':
        return 5;
      case 'low':
      case 'optional':
      case '低':
      case '可选':
        return 1;
      default:
        return null;
    }
  }

  String? _agentMemoryQueryReason(Map<String, dynamic> args) {
    final text = (args['reason'] ??
            args['理由'] ??
            args['原因'] ??
            args['rationale'] ??
            args['purpose'] ??
            args['目标'] ??
            args['intent'] ??
            args['说明'] ??
            args['description'] ??
            '')
        .toString()
        .trim();
    return text.isEmpty ? null : text;
  }

  void _mergeAgentMemoryQueryMatch(
    Map<String, _AgentMemoryQueryMatch> matches,
    AgentMemoryEntry record,
    _AgentMemoryQueryRequest request,
  ) {
    final current = matches[record.id];
    if (current != null && current.priority >= request.priority) return;
    matches[record.id] = _AgentMemoryQueryMatch(
      query: request.query,
      queryPlanIndex: request.queryPlanIndex,
      priority: request.priority,
      reason: request.reason,
      group: request.queryGroup,
    );
  }

  String _agentMemorySortMode(Map<String, dynamic> args) {
    final explicitRaw = args['orderBy'] ??
        args['sortBy'] ??
        args['sortOrder'] ??
        args['order'] ??
        args['排序'] ??
        args['排序方式'];
    final explicitMode = _coerceAgentMemorySortMode(explicitRaw);
    if (explicitMode != null) return explicitMode;
    if (explicitRaw != null && explicitRaw.toString().trim().isNotEmpty) {
      return 'relevance';
    }
    final esSortMode = _coerceAgentMemoryEsSortMode(args['sort']);
    if (esSortMode != null) return esSortMode;
    for (final value in _agentMemoryQueryPlanSortModeValues(args)) {
      final planMode = _coerceAgentMemorySortMode(value);
      if (planMode != null) return planMode;
    }
    return 'relevance';
  }

  String? _agentMemoryDirectSortMode(Map<String, dynamic> args) {
    final explicitRaw = args['orderBy'] ??
        args['sortBy'] ??
        args['sortOrder'] ??
        args['order'] ??
        args['排序'] ??
        args['排序方式'];
    final explicitMode = _coerceAgentMemorySortMode(explicitRaw);
    if (explicitMode != null) return explicitMode;
    if (explicitRaw != null && explicitRaw.toString().trim().isNotEmpty) {
      return 'relevance';
    }
    return _coerceAgentMemoryEsSortMode(args['sort']);
  }

  String? _coerceAgentMemoryEsSortMode(Object? raw) {
    if (raw == null) return null;
    if (raw is String) return _coerceAgentMemorySortMode(raw);
    if (raw is Iterable && raw is! String) {
      for (final item in raw) {
        final mode = _coerceAgentMemoryEsSortMode(item);
        if (mode != null) return mode;
      }
      return null;
    }
    if (raw is! Map) return null;
    final map = <String, dynamic>{
      for (final entry in raw.entries)
        if (entry.key is String) (entry.key as String): entry.value,
    };
    final explicitField =
        (map['field'] ?? map['path'] ?? map['key'] ?? map['字段'] ?? map['字段名'])
            ?.toString()
            .trim();
    if (explicitField != null && explicitField.isNotEmpty) {
      return _coerceAgentMemoryEsSortFieldMode(
        explicitField,
        map['order'] ??
            map['sortOrder'] ??
            map['direction'] ??
            map['dir'] ??
            map['排序方向'],
      );
    }
    for (final entry in map.entries) {
      final mode = _coerceAgentMemoryEsSortFieldMode(
        entry.key,
        entry.value,
      );
      if (mode != null) return mode;
    }
    return null;
  }

  String? _coerceAgentMemoryEsSortFieldMode(String field, Object? rawOrder) {
    final normalizedField = _normalizeAgentMemoryFilterFieldKey(field);
    if (!_agentMemoryIsTimeSortField(normalizedField)) {
      if (_agentMemoryIsRelevanceSortField(normalizedField)) {
        return 'relevance';
      }
      return null;
    }
    final raw = rawOrder is Map
        ? rawOrder['order'] ??
            rawOrder['sortOrder'] ??
            rawOrder['direction'] ??
            rawOrder['dir'] ??
            rawOrder['排序方向']
        : rawOrder;
    return _coerceAgentMemorySortMode(raw);
  }

  bool _agentMemoryIsTimeSortField(String normalizedField) {
    switch (normalizedField) {
      case 'createtime':
      case 'createdat':
      case 'created':
      case 'timestamp':
      case 'time':
      case '时间':
      case '创建时间':
        return true;
      default:
        return false;
    }
  }

  bool _agentMemoryIsRelevanceSortField(String normalizedField) {
    switch (normalizedField) {
      case 'score':
      case '_score':
      case 'relevance':
      case 'rank':
      case 'ranking':
      case '相关性':
      case '分数':
        return true;
      default:
        return false;
    }
  }

  List<Object?> _agentMemoryQueryPlanSortModeValues(
    Map<String, dynamic> args,
  ) =>
      _agentMemoryQueryPlanFilterValues(args, const [
        'orderBy',
        'sortBy',
        'sortOrder',
        'order',
        '排序',
        '排序方式',
      ]);

  String? _coerceAgentMemorySortMode(Object? rawValue) {
    final raw = (rawValue ?? '').toString().trim().toLowerCase();
    switch (raw) {
      case 'oldest':
      case 'oldest_first':
      case 'oldest-first':
      case 'asc':
      case 'ascending':
      case 'chronological':
      case 'create_time_asc':
      case 'createtime_asc':
      case 'time_asc':
      case '最旧':
      case '最早':
      case '时间顺序':
      case '正序':
        return 'oldest';
      case 'latest':
      case 'newest':
      case 'latest_first':
      case 'latest-first':
      case 'newest_first':
      case 'newest-first':
      case 'desc':
      case 'descending':
      case 'recent':
      case 'create_time_desc':
      case 'createtime_desc':
      case 'time_desc':
      case '最新':
      case '最近':
      case '倒序':
        return 'latest';
      case 'relevance':
      case 'relevant':
      case 'score':
      case 'rank':
      case 'ranking':
      case '相关性':
      case '分数':
      case '默认':
        return 'relevance';
      case '':
        return null;
      default:
        return null;
    }
  }

  List<AgentMemoryEntry> _sortAgentMemoryEntries(
    List<AgentMemoryEntry> entries,
    String sortMode,
  ) {
    if (sortMode == 'relevance' || entries.length < 2) return entries;
    final sorted = entries.toList();
    sorted.sort((a, b) {
      final byTime = sortMode == 'oldest'
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  List<AgentMemoryEntry> _limitAgentMemoryEntries(
      List<AgentMemoryEntry> entries, String sortMode, int? limit,
      {int offset = 0}) {
    final sorted = _sortAgentMemoryEntries(entries, sortMode);
    return _sliceAgentMemoryEntries(sorted, limit, offset);
  }

  List<AgentMemoryEntry> _sliceAgentMemoryEntries(
    List<AgentMemoryEntry> entries,
    int? limit,
    int offset,
  ) {
    final skipped = offset <= 0 ? entries : entries.skip(offset);
    return limit == null ? skipped.toList() : skipped.take(limit).toList();
  }

  List<AgentMemoryEntry> _filterAgentMemoryEntriesByContent(
    Iterable<AgentMemoryEntry> entries,
    Map<String, dynamic> args,
  ) {
    final requiredTerms = _agentMemoryRequiredContentTerms(args);
    final shouldTerms = _agentMemoryShouldContentTerms(args);
    final minimumShouldMatch =
        _agentMemoryMinimumShouldMatch(args, shouldTerms.length);
    final excludedTermGroups = _agentMemoryExcludedContentTermGroups(args);
    final existingFields = _agentMemoryRequiredExistingFields(args);
    final contentFiltered = requiredTerms.isEmpty &&
            shouldTerms.isEmpty &&
            excludedTermGroups.isEmpty &&
            existingFields.isEmpty
        ? entries.toList()
        : [
            for (final entry in entries)
              if (_matchesAgentMemoryContentTerms(
                    entry,
                    requiredTerms: requiredTerms,
                    shouldTerms: shouldTerms,
                    minimumShouldMatch: minimumShouldMatch,
                    excludedTermGroups: excludedTermGroups,
                  ) &&
                  _matchesAgentMemoryExistingFields(entry, existingFields))
                entry,
          ];
    return _filterAgentMemoryEntriesByRetrievalSource(contentFiltered, args);
  }

  Set<String> _agentMemoryRequiredExistingFields(Map<String, dynamic> args) {
    final fields = <String>{};

    void addField(Object? raw) {
      if (raw == null || raw is bool || raw is num) return;
      if (raw is String) {
        for (final part in raw.split(RegExp(r'[,，、;；]+'))) {
          final normalized = _normalizeAgentMemoryFilterFieldKey(part);
          if (normalized.isNotEmpty) fields.add(normalized);
        }
        return;
      }
      if (raw is Iterable) {
        for (final item in raw) {
          addField(item);
        }
        return;
      }
      if (raw is Map) {
        var handled = false;
        for (final key in const [
          'field',
          'fields',
          'path',
          'paths',
          'name',
          'names',
          'key',
          'keys',
          '字段',
          '字段名',
          '字段列表',
        ]) {
          if (!raw.containsKey(key)) continue;
          handled = true;
          addField(raw[key]);
        }
        if (!handled && raw.containsKey('exists')) {
          addField(raw['exists']);
        }
      }
    }

    for (final key in const [
      'exists',
      'fieldExists',
      'field_exists',
      'existsField',
      'existsFields',
      'exists_field',
      'exists_fields',
      '字段存在',
      '存在字段',
    ]) {
      addField(args[key]);
    }
    for (final value in _agentMemoryQueryPlanFilterValues(args, const [
      'exists',
      'fieldExists',
      'field_exists',
      'existsField',
      'existsFields',
      'exists_field',
      'exists_fields',
      '字段存在',
      '存在字段',
    ])) {
      addField(value);
    }
    return fields;
  }

  bool _matchesAgentMemoryExistingFields(
    AgentMemoryEntry entry,
    Set<String> fields,
  ) {
    if (fields.isEmpty) return true;
    return fields.every((field) => _agentMemoryEntryHasField(entry, field));
  }

  bool _agentMemoryEntryHasField(AgentMemoryEntry entry, String field) {
    switch (_normalizeAgentMemoryFilterFieldKey(field)) {
      case 'id':
      case 'ids':
      case '_id':
      case 'memoryid':
      case 'memoryids':
      case 'recordid':
      case 'recordids':
      case 'messageid':
      case 'summaryid':
      case 'noteid':
        return entry.id.trim().isNotEmpty;
      case 'name':
      case 'title':
      case 'label':
      case 'memoryname':
      case '标题':
      case '名称':
        return entry.name.trim().isNotEmpty;
      case 'content':
      case 'text':
      case 'body':
      case 'message':
      case 'memory':
      case '正文':
      case '内容':
        return entry.content.trim().isNotEmpty;
      case 'role':
      case 'roles':
      case 'memoryrole':
      case 'memoryroles':
      case 'authorrole':
      case 'authorroles':
      case '角色':
      case '记忆角色':
        return entry.role.trim().isNotEmpty;
      case 'type':
      case 'types':
      case 'memorytype':
      case 'memorytypes':
      case '类型':
      case '记忆类型':
        return entry.type.trim().isNotEmpty;
      case 'scope':
      case 'scopes':
      case 'memoryscope':
      case 'memoryscopes':
      case '范围':
      case '记忆范围':
        return _deepRetrieveRecordScope(entry).trim().isNotEmpty;
      case 'createdat':
      case 'created':
      case 'createtime':
      case 'timestamp':
      case 'time':
      case '创建时间':
      case '时间':
        return entry.createdAt > 0;
      case 'embedding':
      case 'vector':
        return entry.embedding.trim().isNotEmpty ||
            entry.embeddingProvider != null ||
            entry.embeddingModel != null ||
            entry.embeddingDimension != null;
      case 'relatedmessageids':
      case 'relatedmessages':
        return entry.relatedMessageIds.isNotEmpty;
      case 'sourcesummaryids':
      case 'sourcesummaries':
        return entry.sourceSummaryIds.isNotEmpty;
      case 'score':
      case '_score':
      case 'relevancescore':
        return entry.score != null;
      case 'matchedtokens':
      case 'matchedterms':
        return entry.matchedTokens.isNotEmpty;
      case 'retrievalsource':
      case 'retrievalsources':
        return entry.retrievalSource?.trim().isNotEmpty == true;
      case 'relevancereason':
      case 'reason':
        return entry.relevanceReason?.trim().isNotEmpty == true;
      case 'embeddingprovider':
        return entry.embeddingProvider?.trim().isNotEmpty == true;
      case 'embeddingmodel':
        return entry.embeddingModel?.trim().isNotEmpty == true;
      case 'embeddingdimension':
        return entry.embeddingDimension != null;
      default:
        return false;
    }
  }

  List<AgentMemoryEntry> _filterAgentMemoryEntriesByRetrievalSource(
    Iterable<AgentMemoryEntry> entries,
    Map<String, dynamic> args,
  ) {
    final requiredSources = _agentMemoryRequiredRetrievalSources(args);
    if (requiredSources.isEmpty) return entries.toList();
    return [
      for (final entry in entries)
        if (entry.retrievalSource != null &&
            requiredSources.contains(entry.retrievalSource))
          entry,
    ];
  }

  Set<String> _agentMemoryRequiredRetrievalSources(
    Map<String, dynamic> args,
  ) {
    final values = <String>{};

    void add(Object? raw) {
      final items = _coerceStringSet(raw);
      if (items == null) return;
      for (final item in items) {
        final normalized = _normalizeAgentMemoryRetrievalSource(item);
        if (normalized != null) values.add(normalized);
      }
    }

    final onlyVectorIndex = _coerceBool(args['onlyVectorIndex'] ??
        args['vectorOnly'] ??
        args['requireVectorIndex'] ??
        args['only_vector_index'] ??
        args['vector_only'] ??
        args['require_vector_index'] ??
        args['只用向量索引'] ??
        args['仅向量索引']);
    if (onlyVectorIndex == true) values.add('vector_index');
    add(args['retrievalSource'] ??
        args['retrievalSources'] ??
        args['retrieval_source'] ??
        args['retrieval_sources'] ??
        args['检索来源'] ??
        args['召回来源']);
    for (final value in _agentMemoryQueryPlanRetrievalSourceValues(args)) {
      add(value);
    }
    return values;
  }

  String? _normalizeAgentMemoryRetrievalSource(String raw) {
    final value = raw.trim().toLowerCase();
    switch (value) {
      case 'vector_index':
      case 'vector-index':
      case 'vector index':
      case 'indexed_vector':
      case 'indexed-vector':
      case 'indexed vector':
      case 'memory_vector':
      case 'memory-vector':
      case 'memory vector':
      case 'omemoryvector':
      case 'o_memoryvector':
      case 'o_memory_vector':
      case 'indexed':
      case 'vector':
      case '向量索引':
      case '索引':
      case '向量':
        return 'vector_index';
      default:
        return value.isEmpty ? null : value;
    }
  }

  List<Object?> _agentMemoryQueryPlanRetrievalSourceValues(
    Map<String, dynamic> args,
  ) =>
      _agentMemoryQueryPlanFilterValues(args, const [
        'retrievalSource',
        'retrievalSources',
        'retrieval_source',
        'retrieval_sources',
        '检索来源',
        '召回来源',
        'onlyVectorIndex',
        'vectorOnly',
        'requireVectorIndex',
        'only_vector_index',
        'vector_only',
        'require_vector_index',
        '只用向量索引',
        '仅向量索引',
      ]);

  List<String> _agentMemoryRequiredContentTerms(Map<String, dynamic> args) =>
      _agentMemoryContentTerms(args, const [
        'mustInclude',
        'mustIncludeTerms',
        'includeTerms',
        'includeTerm',
        'include',
        'includes',
        'must',
        'prefix',
        'wildcard',
        'regexp',
        'match_bool_prefix',
        'matchBoolPrefix',
        'require',
        'requires',
        'requiredTerms',
        'requiredTerm',
        'required',
        'requiredKeywords',
        'requiredKeyword',
        'requireTerms',
        'requireTerm',
        'contentIncludes',
        'contentInclude',
        '包含关键词',
        '包含词',
        '必须包含',
        '必含词',
      ]);

  List<String> _agentMemoryShouldContentTerms(Map<String, dynamic> args) =>
      _agentMemoryContentTerms(args, const [
        'should',
        'shouldInclude',
        'shouldIncludes',
        'shouldTerms',
        'shouldTerm',
        'shouldKeywords',
        'shouldKeyword',
        'optionalTerms',
        'optionalTerm',
        'candidateTerms',
        'candidateTerm',
        'any',
        'anyOf',
        'anyTerms',
        '任一包含',
        '至少包含',
        '候选词',
        '可选包含',
        '应该包含',
      ]);

  int _agentMemoryMinimumShouldMatch(
    Map<String, dynamic> args,
    int shouldTermCount,
  ) {
    if (shouldTermCount <= 0) return 0;
    final direct = _coerceInt(args['minimumShouldMatch'] ??
        args['minimum_should_match'] ??
        args['minShouldMatch'] ??
        args['min_should_match'] ??
        args['shouldMatchCount'] ??
        args['should_match_count'] ??
        args['最低命中数'] ??
        args['至少命中']);
    final fromPlan = direct ??
        _firstCoercedInt(_agentMemoryQueryPlanMinimumShouldMatchValues(args));
    final value = fromPlan ?? 1;
    return value.clamp(1, shouldTermCount).toInt();
  }

  List<Object?> _agentMemoryQueryPlanMinimumShouldMatchValues(
    Map<String, dynamic> args,
  ) =>
      _agentMemoryQueryPlanFilterValues(args, const [
        'minimumShouldMatch',
        'minimum_should_match',
        'minShouldMatch',
        'min_should_match',
        'shouldMatchCount',
        'should_match_count',
        '最低命中数',
        '至少命中',
      ]);

  List<List<String>> _agentMemoryExcludedContentTermGroups(
    Map<String, dynamic> args,
  ) =>
      _agentMemoryContentTermGroups(args, _agentMemoryExcludedContentKeys);

  static const _agentMemoryExcludedContentKeys = [
    'excludeTerms',
    'excludeTerm',
    'exclude',
    'excludes',
    'excludeKeywords',
    'excludeKeyword',
    'forbiddenTerms',
    'forbiddenTerm',
    'negativeTerms',
    'negativeTerm',
    'mustNot',
    'must_not',
    'mustNotInclude',
    'mustNotContain',
    'not',
    'notTerms',
    'notTerm',
    'contentExcludes',
    'contentExclude',
    'without',
    '排除关键词',
    '排除词',
    '不能包含',
    '不要包含',
    '禁用词',
  ];

  List<String> _agentMemoryContentTerms(
    Map<String, dynamic> args,
    List<String> keys,
  ) {
    final terms = <String>[];
    for (final group in _agentMemoryContentTermGroups(args, keys)) {
      for (final term in group) {
        if (term.isNotEmpty && !terms.contains(term)) terms.add(term);
      }
    }
    return terms;
  }

  List<List<String>> _agentMemoryContentTermGroups(
    Map<String, dynamic> args,
    List<String> keys,
  ) {
    final groups = <List<String>>[];

    void addText(Object? raw) {
      final values = _coerceStringList(raw);
      if (values == null) return;
      for (final value in values) {
        for (final part in value.split(RegExp(r'[,，、;；]+'))) {
          final terms = _agentMemoryContentTermParts(part);
          if (terms.isNotEmpty) groups.add(terms);
        }
      }
    }

    void add(Object? raw) {
      if (raw == null || raw is bool) return;
      if (raw is Map) {
        if (raw.containsKey('exists')) return;
        var handled = false;
        for (final key in const [
          'term',
          'terms',
          'match',
          'prefix',
          'wildcard',
          'regexp',
          'match_bool_prefix',
          'matchBoolPrefix',
          'match_phrase',
          'matchPhrase',
          'value',
          'values',
          'text',
          'content',
          'keyword',
          'keywords',
          'query',
          'q',
          'phrase',
          'phrases',
          '字段值',
          '内容',
          '关键词',
          '短语',
        ]) {
          if (!raw.containsKey(key)) continue;
          handled = true;
          add(raw[key]);
        }
        if (!handled) {
          if (_agentMemoryMapHasOnlyNonContentFilterFields(raw)) return;
          for (final value in raw.values) {
            add(value);
          }
        }
        return;
      }
      if (raw is Iterable && raw is! String) {
        for (final item in raw) {
          add(item);
        }
        return;
      }
      addText(raw);
    }

    for (final key in keys) {
      add(args[key]);
    }
    for (final value in _agentMemoryQueryPlanFilterValues(args, keys)) {
      add(value);
    }
    return groups;
  }

  List<String> _agentMemoryContentTermParts(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    if (!RegExp(r'[*?^$\\.\[\]{}()|+]').hasMatch(trimmed)) {
      return [trimmed];
    }
    final normalized = trimmed
        .replaceAllMapped(RegExp(r'\\([^\s])'), (match) => match.group(1)!)
        .replaceAll(RegExp(r'[*?^$\\.\[\]{}()|+]+'), ' ');
    final parts = [
      for (final part in normalized.split(RegExp(r'\s+')))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    return parts.isEmpty ? [trimmed] : parts;
  }

  bool _matchesAgentMemoryContentTerms(
    AgentMemoryEntry entry, {
    required List<String> requiredTerms,
    required List<String> shouldTerms,
    required int minimumShouldMatch,
    required List<List<String>> excludedTermGroups,
  }) {
    final text = '${entry.name}\n${entry.content}'.toLowerCase();
    bool containsTerm(String term) => text.contains(term.toLowerCase());
    final shouldMatchCount =
        shouldTerms.where((term) => containsTerm(term)).length;
    return requiredTerms.every(containsTerm) &&
        (shouldTerms.isEmpty || shouldMatchCount >= minimumShouldMatch) &&
        !excludedTermGroups
            .any((group) => group.every((term) => containsTerm(term)));
  }

  List<AgentMemoryEntry> _sortAgentMemoryEntriesByPriority(
    List<AgentMemoryEntry> entries,
    String sortMode,
    Map<String, int> priorities,
  ) {
    final sorted = _sortAgentMemoryEntries(entries, sortMode);
    final indexed = [
      for (var index = 0; index < sorted.length; index++) (index, sorted[index])
    ];
    indexed.sort((a, b) {
      final priorityA = priorities[a.$2.id] ?? 0;
      final priorityB = priorities[b.$2.id] ?? 0;
      final byPriority = priorityB.compareTo(priorityA);
      if (byPriority != 0) return byPriority;
      return a.$1.compareTo(b.$1);
    });
    return [for (final item in indexed) item.$2];
  }

  Set<String>? _deepRetrieveMemoryTypes(Map<String, dynamic> args) {
    final values = <String>{};

    void addMemoryType(Object? raw, {bool includeUnknown = true}) {
      final items = _coerceStringSet(raw);
      if (items == null) return;
      for (final item in items) {
        switch (item.trim().toLowerCase()) {
          case 'message':
          case 'messages':
          case 'chat':
          case '普通记忆':
          case '消息':
          case '聊天':
            values.add(agentMemoryTypeMessage);
            break;
          case 'conversation':
          case 'conversations':
          case 'history':
          case '对话':
          case '对话记忆':
          case '历史':
          case '短期记忆':
            values
              ..add(agentMemoryTypeMessage)
              ..add(agentMemoryTypeSummary);
            break;
          case 'summary':
          case 'summaries':
          case '摘要':
          case '摘要记忆':
          case '历史摘要':
            values.add(agentMemoryTypeSummary);
            break;
          case 'long_term':
          case 'long-term':
          case 'longterm':
          case 'note':
          case 'notes':
          case 'project':
          case '长期':
          case '长期记忆':
          case '项目记忆':
          case '设定记忆':
            values.add(agentMemoryTypeNote);
            break;
          case 'all':
          case '全部':
          case '所有':
          case '全量':
            values
              ..add(agentMemoryTypeMessage)
              ..add(agentMemoryTypeSummary)
              ..add(agentMemoryTypeNote);
            break;
          default:
            if (includeUnknown) values.add(item);
        }
      }
    }

    addMemoryType(args['types'] ??
        args['type'] ??
        args['类型'] ??
        args['memoryTypes'] ??
        args['memoryType'] ??
        args['记忆类型']);
    addMemoryType(
      args['scopes'] ??
          args['scope'] ??
          args['范围'] ??
          args['memoryScopes'] ??
          args['memoryScope'] ??
          args['记忆范围'] ??
          args['memory_scopes'] ??
          args['memory_scope'],
    );
    for (final value in _agentMemoryQueryPlanMemoryTypeValues(args)) {
      addMemoryType(value, includeUnknown: false);
    }
    return values.isEmpty ? null : values;
  }

  String? _memoryAddType(Map<String, dynamic> args) {
    final values = <String>{};

    void add(Object? raw) {
      final items = _coerceStringSet(raw);
      if (items == null) return;
      for (final item in items) {
        switch (item.trim().toLowerCase()) {
          case 'message':
          case 'messages':
          case 'conversation':
          case 'conversations':
          case 'chat':
          case 'history':
          case '普通记忆':
          case '消息':
          case '聊天':
          case '对话':
          case '对话记忆':
          case '历史':
          case '短期记忆':
            values.add(agentMemoryTypeMessage);
            break;
          case 'note':
          case 'notes':
          case 'long_term':
          case 'long-term':
          case 'longterm':
          case 'project':
          case '长期':
          case '长期记忆':
          case '项目记忆':
          case '设定记忆':
            values.add(agentMemoryTypeNote);
            break;
          default:
            values.add('__unsupported__');
        }
      }
    }

    add(args['types'] ??
        args['type'] ??
        args['类型'] ??
        args['memoryTypes'] ??
        args['memoryType'] ??
        args['记忆类型']);
    add(
      args['scopes'] ??
          args['scope'] ??
          args['范围'] ??
          args['memoryScopes'] ??
          args['memoryScope'] ??
          args['记忆范围'] ??
          args['memory_scopes'] ??
          args['memory_scope'],
    );
    if (values.isEmpty) return agentMemoryTypeMessage;
    if (values.length != 1 || values.contains('__unsupported__')) return null;
    return values.single;
  }

  String? _memoryClearScope(Map<String, dynamic> args) {
    final values = <String>{};

    void add(Object? raw) {
      final items = _coerceStringSet(raw);
      if (items == null) return;
      for (final item in items) {
        switch (item.trim().toLowerCase()) {
          case 'message':
          case 'messages':
          case 'conversation':
          case 'conversations':
          case 'chat':
          case 'history':
          case '普通记忆':
          case '消息':
          case '聊天':
          case '对话':
          case '对话记忆':
          case '历史':
          case '短期记忆':
            values.add(agentMemoryTypeMessage);
            break;
          case 'summary':
          case 'summaries':
          case '摘要':
          case '摘要记忆':
          case '历史摘要':
            values.add(agentMemoryTypeSummary);
            break;
          case 'note':
          case 'notes':
          case 'long_term':
          case 'long-term':
          case 'longterm':
          case 'project':
          case '长期':
          case '长期记忆':
          case '项目记忆':
          case '设定记忆':
            values.add(agentMemoryTypeNote);
            break;
          case 'all':
          case '全部':
          case '所有':
          case '全量':
            values.add(agentMemoryScopeAll);
            break;
          default:
            values.add('__unsupported__');
        }
      }
    }

    add(args['scope'] ??
        args['范围'] ??
        args['memoryScope'] ??
        args['记忆范围'] ??
        args['memory_scope']);
    add(args['type'] ??
        args['类型'] ??
        args['memoryType'] ??
        args['记忆类型'] ??
        args['memory_type']);
    if (values.isEmpty) return null;
    if (values.length != 1 || values.contains('__unsupported__')) return null;
    return values.single;
  }

  String _agentMemoryIdArg(Map<String, dynamic> args) {
    for (final key in const [
      'memoryId',
      'memory_id',
      'id',
      'recordId',
      'record_id',
      'noteId',
      'note_id',
      '记忆Id',
      '记忆ID',
      '记忆id',
      '记忆编号',
      '记录Id',
      '记录ID',
    ]) {
      final value = (args[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    final recordIds = _coerceMemoryIdSetAny(args, const [
      'record',
      'records',
      'memoryRecord',
      'memoryRecords',
      'memory_record',
      'memory_records',
      'noteRecord',
      'noteRecords',
      'note_record',
      'note_records',
      '记忆记录',
      '记忆记录列表',
      '记录',
      '记录列表',
    ]);
    if (recordIds != null && recordIds.isNotEmpty) return recordIds.first;
    return '';
  }

  String _agentMemoryNameArg(Map<String, dynamic> args) {
    for (final key in const [
      'name',
      'title',
      'label',
      'memoryName',
      'memory_name',
      '名称',
      '标题',
      '记忆名称',
    ]) {
      final value = (args[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _agentMemoryContentArg(Map<String, dynamic> args) {
    for (final key in const [
      'content',
      '内容',
      '记忆内容',
      '正文',
      'text',
      'memory',
      'note',
      'value',
      'message',
      'prompt',
      'input',
    ]) {
      final value = (args[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Map<String, Object?>? _agentLongTermMemoryRow(int projectId, String id) {
    return db.select(
      'SELECT id,name,content,createTime,role,type FROM memories '
      'WHERE id=? AND isolationKey=? AND role=? AND type=?',
      [
        id,
        _agentMemoryIsolationKey(projectId),
        _agentMemoryRole,
        _agentMemoryType,
      ],
    ).firstOrNull;
  }

  List<AgentMemoryEntry> _agentMemoryRecordsByIds(
    int projectId,
    Iterable<String> ids, {
    required String family,
    Set<String>? roles,
    Set<String>? types,
    Set<String> excludeIds = const {},
    Set<String>? excludeRoles,
    Set<String>? excludeRoleSuffixes,
    AgentMemoryTimeRange? timeRange,
  }) {
    final orderedIds = <String>[];
    for (final id in ids) {
      final trimmed = id.trim();
      if (trimmed.isEmpty ||
          excludeIds.contains(trimmed) ||
          orderedIds.contains(trimmed)) {
        continue;
      }
      orderedIds.add(trimmed);
    }
    if (orderedIds.isEmpty) return const [];
    final placeholders = List.filled(orderedIds.length, '?').join(',');
    final rows = db.select(
      'SELECT id,name,content,createTime,embedding,relatedMessageIds,role,type '
      'FROM memories '
      'WHERE id IN ($placeholders) AND isolationKey IN (?,?)',
      [
        ...orderedIds,
        _agentConversationIsolationKey(projectId, family: family),
        _agentMemoryIsolationKey(projectId),
      ],
    );
    final rowsById = <String, Map<String, Object?>>{
      for (final row in rows) row['id'] as String: row,
    };
    final records = <AgentMemoryEntry>[];
    for (final id in orderedIds) {
      final row = rowsById[id];
      if (row == null) continue;
      final record = AgentMemoryEntry.fromRow(row);
      if (!_matchesAgentMemoryExactRecordFilter(
        record,
        roles: roles,
        types: types,
        excludeRoles: excludeRoles,
        excludeRoleSuffixes: excludeRoleSuffixes,
        timeRange: timeRange,
      )) {
        continue;
      }
      records.add(record);
    }
    return records;
  }

  bool _matchesAgentMemoryExactRecordFilter(
    AgentMemoryEntry record, {
    Set<String>? roles,
    Set<String>? types,
    Set<String>? excludeRoles,
    Set<String>? excludeRoleSuffixes,
    AgentMemoryTimeRange? timeRange,
  }) {
    if (roles != null && !roles.contains(record.role)) return false;
    if (types != null && !types.contains(record.type)) return false;
    if (excludeRoles != null && excludeRoles.contains(record.role)) {
      return false;
    }
    if (excludeRoleSuffixes != null) {
      for (final suffix in excludeRoleSuffixes) {
        if (suffix.trim().isNotEmpty && record.role.endsWith(suffix.trim())) {
          return false;
        }
      }
    }
    return timeRange == null || timeRange.contains(record.createdAt);
  }

  String _memoryAddDefaultRole(String agentFamily, String? stage) {
    final currentStage = (stage ?? '').trim();
    if (currentStage.isEmpty ||
        currentStage == scriptAgentDecisionStage ||
        currentStage == productionAgentDecisionStage ||
        currentStage == _scriptAgentFamily ||
        currentStage == _productionAgentFamily) {
      return agentRoleUser;
    }
    if (agentFamily == _productionAgentFamily &&
        currentStage.startsWith('productionAgent:')) {
      return _productionAgentSubAgentMemoryRole(currentStage);
    }
    if (agentFamily == _scriptAgentFamily &&
        currentStage.startsWith('scriptAgent:')) {
      return _scriptAgentSubAgentMemoryRole(currentStage);
    }
    return agentRoleUser;
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

  List<AgentMemoryEntry> _dedupeAgentMemoryEntries(
    Iterable<AgentMemoryEntry> records,
  ) {
    final seen = <String>{};
    final result = <AgentMemoryEntry>[];
    for (final record in records) {
      final id = record.id.trim();
      if (id.isNotEmpty && !seen.add(id)) continue;
      result.add(record);
    }
    return result;
  }

  bool _hasAgentMemoryToolRecords(
    Iterable<AgentMemoryEntry> relatedMessages,
    Iterable<AgentMemoryEntry> summaries,
    Iterable<AgentMemoryEntry> recentMessages,
    Iterable<AgentMemoryEntry> notes,
  ) =>
      relatedMessages.isNotEmpty ||
      summaries.isNotEmpty ||
      recentMessages.isNotEmpty ||
      notes.isNotEmpty;

  bool _agentMemoryFallbackHasPriorHit(
    _AgentMemoryQueryRequest request,
    Set<String> hitQueryGroups, {
    required bool hasAnyRecords,
  }) {
    final group = request.queryGroup;
    if (group == null) return hasAnyRecords;
    return hitQueryGroups.contains(group);
  }

  Map<String, dynamic> _agentMemoryRecordPayload(
    AgentMemoryEntry record, {
    int? priority,
    _AgentMemoryQueryMatch? queryMatch,
  }) =>
      {
        'id': record.id,
        'type': record.type,
        'scope': _deepRetrieveRecordScope(record),
        'name': record.name,
        'createTime': record.createdAt,
        'role': record.role,
        if (priority != null && priority != 0) 'priority': priority,
        if (queryMatch != null) 'matchedQuery': queryMatch.query,
        if (queryMatch != null) 'queryPlanIndex': queryMatch.queryPlanIndex,
        if (queryMatch?.reason != null) 'queryReason': queryMatch!.reason,
        if (queryMatch?.group != null) 'queryGroup': queryMatch!.group,
        if (record.relatedMessageIds.isNotEmpty)
          'relatedMessageIds': record.relatedMessageIds,
        if (record.sourceSummaryIds.isNotEmpty)
          'sourceSummaryIds': record.sourceSummaryIds,
        if (record.sourceSummaryIds.isNotEmpty)
          'sourceSummaries': _agentMemorySourceSummaryPayloads(record),
        if (record.score != null) 'score': record.score,
        if (record.matchedTokens.isNotEmpty)
          'matchedTokens': record.matchedTokens,
        if (record.retrievalSource != null)
          'retrievalSource': record.retrievalSource,
        if (record.relevanceReason != null)
          'relevanceReason': record.relevanceReason,
        if (record.embeddingProvider != null)
          'embeddingProvider': record.embeddingProvider,
        if (record.embeddingModel != null)
          'embeddingModel': record.embeddingModel,
        if (record.embeddingDimension != null)
          'embeddingDimension': record.embeddingDimension,
        'content': record.content,
      };

  List<Map<String, dynamic>> _agentMemorySourceSummaryPayloads(
    AgentMemoryEntry record,
  ) {
    final ids = record.sourceSummaryIds;
    if (ids.isEmpty) return const [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = db.select(
      'SELECT id,name,content,createTime,role,type '
      'FROM memories WHERE id IN ($placeholders) AND type=?',
      [...ids, agentMemoryTypeSummary],
    );
    final rowsById = <String, Map<String, Object?>>{
      for (final row in rows) row['id'] as String: row,
    };
    return [
      for (final id in ids)
        if (rowsById[id] case final row?)
          _agentMemorySourceSummaryPayload(
            id,
            row,
            record.sourceSummaryReasons[id],
          ),
    ];
  }

  Map<String, dynamic> _agentMemorySourceSummaryPayload(
    String id,
    Map<String, Object?> row,
    String? reason,
  ) {
    final normalizedReason = reason?.trim();
    return {
      'id': id,
      'type': row['type'] as String? ?? agentMemoryTypeSummary,
      'name': row['name'] as String? ?? '',
      'createTime': row['createTime'] as int? ?? 0,
      'role': row['role'] as String? ?? '',
      'content': row['content'] as String? ?? '',
      if (normalizedReason != null && normalizedReason.isNotEmpty)
        'reason': normalizedReason,
    };
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
    final chapterNames = _stringListAny(args, const [
      'chapterName',
      'chapterNames',
      'chapterTitle',
      'chapterTitles',
      'chapter_name',
      'chapter_names',
      'chapter_title',
      'chapter_titles',
    ]);
    final wantedChapterNames = chapterNames?.map((name) => name.trim()).toSet();
    final chapters = novels(projectId, limit: 100000).data.where((chapter) {
      if (novelIds != null) return novelIds.contains(chapter.id);
      if (chapterIndexes != null) {
        return chapterIndexes.contains(chapter.chapterIndex);
      }
      if (wantedChapterNames != null) {
        return wantedChapterNames.contains((chapter.chapter ?? '').trim());
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
        'resource',
        'workspace',
        '资源',
        '工作区',
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
    final raw = key.trim();
    switch (raw) {
      case '全部':
      case '所有':
      case '全量':
      case '工作区':
      case '完整工作区':
      case '全部工作区':
        return '';
      case '故事骨架':
      case '故事大纲':
        return scriptAgentStorySkeletonKey;
      case '改编策略':
        return scriptAgentAdaptationStrategyKey;
      case '剧本':
      case '剧本内容':
      case '正文':
        return 'script';
    }
    final normalized = raw
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)}_${match.group(2)}',
        )
        .replaceAll(RegExp(r'[\s-]+'), '_')
        .toLowerCase();
    switch (normalized) {
      case 'all':
      case 'workspace':
      case 'workspace_data':
      case 'workspacedata':
      case 'all_workspace':
      case 'full':
      case 'full_workspace':
      case 'entire_workspace':
      case 'everything':
        return '';
      case 'story_skeleton':
      case 'storyskeleton':
      case 'story_outline':
      case 'storyoutline':
      case 'outline':
      case 'skeleton':
        return scriptAgentStorySkeletonKey;
      case 'adaptation_strategy':
      case 'adaptationstrategy':
      case 'strategy':
        return scriptAgentAdaptationStrategyKey;
      case 'script':
      case 'scripts':
      case 'script_content':
      case 'scriptcontent':
        return 'script';
      default:
        return raw;
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
    final chapterNames = _stringListAny(args, const [
      'chapterName',
      'chapterNames',
      'chapterTitle',
      'chapterTitles',
      'chapter_name',
      'chapter_names',
      'chapter_title',
      'chapter_titles',
    ]);
    final wantedChapterNames = chapterNames?.map((name) => name.trim()).toSet();
    final chapters = novels(projectId, limit: 100000).data.where((chapter) {
      if (novelIds != null) return novelIds.contains(chapter.id);
      if (chapterIndexes != null) {
        return chapterIndexes.contains(chapter.chapterIndex);
      }
      if (wantedChapterNames != null) {
        return wantedChapterNames.contains((chapter.chapter ?? '').trim());
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
    final scriptNames = _stringListAny(args, const [
      'scriptName',
      'scriptNames',
      'episodeName',
      'episodeNames',
      'scriptTitle',
      'scriptTitles',
      'episodeTitle',
      'episodeTitles',
      'script_name',
      'script_names',
      'episode_name',
      'episode_names',
      'script_title',
      'script_titles',
      'episode_title',
      'episode_titles',
    ]);
    final wantedScriptNames = scriptNames?.map((name) => name.trim()).toSet();
    final rows = scripts(projectId).where((script) {
      if (ids != null) return ids.contains(script.id);
      if (wantedScriptNames != null) {
        return wantedScriptNames.contains((script.name ?? '').trim());
      }
      return true;
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
        await _agentPromptLongTermMemories(
          projectId,
          prompt,
          family: _scriptAgentFamily,
          limit: _agentRagLimit(),
        ),
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
    final ids = _agentScriptIdsArg(projectId, args);
    if (ids != null) return ids.isEmpty ? null : ids.first;
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

  List<Map<String, Object?>> _productionAssetRefRows(
    int projectId,
    int? scriptId,
  ) {
    final linkedIds = scriptId == null
        ? const <int>[]
        : db
            .select('SELECT assetId FROM o_scriptAssets WHERE scriptId=?',
                [scriptId])
            .map((row) => row['assetId'] as int)
            .toList();
    if (linkedIds.isNotEmpty) {
      final placeholders = List.filled(linkedIds.length, '?').join(',');
      return [
        for (final row in db.select(
          'SELECT id,name,type,describe FROM o_assets '
          'WHERE projectId=? AND id IN ($placeholders) ORDER BY id',
          [projectId, ...linkedIds],
        ))
          Map<String, Object?>.from(row),
      ];
    }
    return [
      for (final row in db.select(
        'SELECT id,name,type,describe FROM o_assets '
        'WHERE projectId=? ORDER BY id',
        [projectId],
      ))
        Map<String, Object?>.from(row),
    ];
  }

  String _productionAssetRefCode(int index) =>
      'A${(index + 1).toString().padLeft(3, '0')}';

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
    final key = _normalizeProductionAgentFlowDataKey(
      _stringArgAny(args, const [
        'key',
        'dataKey',
        'data_key',
        'flowKey',
        'flow_key',
        'section',
        'resource',
        'workspace',
        '资源',
        '工作区',
      ]),
    );
    final data = _productionAgentWorkspace(projectId, scriptId);
    if (key.isEmpty) return jsonEncode(data);
    final value = data[key];
    if (value == null) return '无数据';
    return value is String
        ? (value.trim().isEmpty ? '无数据' : value)
        : jsonEncode(value);
  }

  String _normalizeProductionAgentFlowDataKey(String key) {
    final raw = key.trim();
    switch (raw) {
      case '全部':
      case '所有':
      case '全量':
      case '工作区':
      case '完整工作区':
      case '全部工作区':
        return '';
      case '剧本':
      case '剧本内容':
      case '正文':
        return 'script';
      case '导演计划':
      case '拍摄计划':
      case '制作计划':
        return productionScriptPlanKey;
      case '资产':
      case '衍生资产':
        return 'assets';
      case '分镜表':
        return productionStoryboardTableKey;
      case '分镜':
      case '分镜面板':
        return 'storyboard';
    }
    final normalized = raw
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)}_${match.group(2)}',
        )
        .replaceAll(RegExp(r'[\s-]+'), '_')
        .toLowerCase();
    switch (normalized) {
      case 'all':
      case 'workspace':
      case 'workspace_data':
      case 'workspacedata':
      case 'all_workspace':
      case 'full':
      case 'full_workspace':
      case 'entire_workspace':
      case 'everything':
        return '';
      case 'script':
      case 'scripts':
      case 'script_content':
      case 'scriptcontent':
        return 'script';
      case 'script_plan':
      case 'scriptplan':
      case 'director_plan':
      case 'directorplan':
      case 'shooting_plan':
      case 'production_plan':
      case 'plan':
        return productionScriptPlanKey;
      case 'asset':
      case 'assets':
      case 'derive_asset':
      case 'derive_assets':
      case 'derived_asset':
      case 'derived_assets':
        return 'assets';
      case 'storyboard_table':
      case 'storyboardtable':
      case 'shot_table':
      case 'shots_table':
        return productionStoryboardTableKey;
      case 'storyboard':
      case 'storyboards':
      case 'storyboard_panel':
      case 'storyboardpanel':
      case 'shot':
      case 'shots':
      case 'panel':
        return 'storyboard';
      default:
        return raw;
    }
  }

  String _productionAgentAddDeriveAsset(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final scriptId = _productionScriptId(projectId, args);
    final parentId = _productionParentAssetIdArg(
      projectId,
      args,
      scriptId: scriptId,
    );
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

  int? _productionParentAssetIdArg(
    int projectId,
    Map<String, dynamic> args, {
    int? scriptId,
  }) {
    final direct = _coerceInt(_argAny(args, const [
      'assetsId',
      'assetId',
      'parentAssetId',
      'parentAssetsId',
      'asset_id',
      'assets_id',
      'parent_asset_id',
      'parent_assets_id',
    ]));
    if (direct != null) return direct;
    final names = _stringListAny(args, const [
      'parentAssetName',
      'parentAssetNames',
      'parentName',
      'parentNames',
      'sourceAssetName',
      'sourceAssetNames',
      'parent_asset_name',
      'parent_asset_names',
      'source_asset_name',
      'source_asset_names',
    ]);
    if (names == null) return null;
    final wanted = names.map((name) => name.trim()).toSet();
    final linkedIds = scriptId == null
        ? null
        : db
            .select('SELECT assetId FROM o_scriptAssets WHERE scriptId=?',
                [scriptId])
            .map((row) => row['assetId'] as int)
            .toSet();
    final rows = db.select(
      'SELECT id,name FROM o_assets '
      'WHERE projectId=? AND assetsId IS NULL ORDER BY id',
      [projectId],
    );
    for (final row in rows) {
      final id = row['id'] as int;
      if (!wanted.contains((row['name'] as String? ?? '').trim())) continue;
      if (linkedIds != null && !linkedIds.contains(id)) continue;
      return id;
    }
    return null;
  }

  String _productionAgentDeleteDeriveAsset(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final ids = _productionDeriveAssetIdsArg(
      projectId,
      args,
      scriptId: _productionScriptId(projectId, args),
    );
    if (ids == null || ids.isEmpty) return '缺少 id 参数。';
    deleteAssets(ids);
    if (ids.length == 1) return '已删除衍生资产，ID: ${ids.single}。';
    return '已删除衍生资产，ID: ${ids.join(', ')}。';
  }

  List<int>? _productionDeriveAssetIdsArg(
    int projectId,
    Map<String, dynamic> args, {
    int? scriptId,
  }) {
    final direct = _intListAny(args, const [
      'id',
      'ids',
      'assetId',
      'assetIds',
      'deriveAssetId',
      'deriveAssetIds',
      'childAssetId',
      'childAssetIds',
      'asset_id',
      'asset_ids',
      'derive_asset_id',
      'derive_asset_ids',
      'child_asset_id',
      'child_asset_ids',
    ]);
    if (direct != null) return direct;

    final names = _stringListAny(args, const [
      'assetName',
      'assetNames',
      'deriveAssetName',
      'deriveAssetNames',
      'childAssetName',
      'childAssetNames',
      'asset_name',
      'asset_names',
      'derive_asset_name',
      'derive_asset_names',
      'child_asset_name',
      'child_asset_names',
    ]);
    if (names == null) return null;
    final wanted = names.map((name) => name.trim()).toSet();
    final linkedIds = scriptId == null
        ? null
        : db
            .select('SELECT assetId FROM o_scriptAssets WHERE scriptId=?',
                [scriptId])
            .map((row) => row['assetId'] as int)
            .toSet();
    return [
      for (final row in db.select(
        'SELECT id,name FROM o_assets '
        'WHERE projectId=? AND assetsId IS NOT NULL ORDER BY id',
        [projectId],
      ))
        if (wanted.contains((row['name'] as String? ?? '').trim()) &&
            (linkedIds == null || linkedIds.contains(row['id'] as int)))
          row['id'] as int,
    ];
  }

  String _productionAgentGenerateDeriveAsset(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final ids = _productionAssetIdsArg(
      projectId,
      args,
      scriptId: _productionScriptId(projectId, args),
    );
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
    final ids = _productionStoryboardIdsArg(projectId, args);
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

  List<int>? _productionAssetIdsArg(
    int projectId,
    Map<String, dynamic> args, {
    int? scriptId,
  }) {
    final direct = _intListAny(args, const [
      'ids',
      'assetIds',
      'assetsIds',
      'deriveAssetIds',
      'deriveAssetsIds',
      'assetId',
      'assetsId',
      'deriveAssetId',
      'deriveAssetsId',
      'asset_ids',
      'assets_ids',
      'derive_asset_ids',
      'derive_assets_ids',
      'asset_id',
      'assets_id',
      'derive_asset_id',
      'derive_assets_id',
    ]);
    if (direct != null) return direct;

    final names = _stringListAny(args, const [
      'assetName',
      'assetNames',
      'deriveAssetName',
      'deriveAssetNames',
      'childAssetName',
      'childAssetNames',
      'roleName',
      'roleNames',
      'sceneName',
      'sceneNames',
      'toolName',
      'toolNames',
      'asset_name',
      'asset_names',
      'derive_asset_name',
      'derive_asset_names',
      'child_asset_name',
      'child_asset_names',
    ]);
    if (names == null) return null;
    final wanted = names.map((name) => name.trim()).toSet();
    final linkedIds = scriptId == null
        ? null
        : db
            .select('SELECT assetId FROM o_scriptAssets WHERE scriptId=?',
                [scriptId])
            .map((row) => row['assetId'] as int)
            .toSet();
    return [
      for (final row in db.select(
        'SELECT id,name FROM o_assets WHERE projectId=? ORDER BY id',
        [projectId],
      ))
        if (wanted.contains((row['name'] as String? ?? '').trim()) &&
            (linkedIds == null || linkedIds.contains(row['id'] as int)))
          row['id'] as int,
    ];
  }

  List<int>? _productionStoryboardIdsArg(
    int projectId,
    Map<String, dynamic> args,
  ) {
    final direct = _intListAny(args, const [
      'ids',
      'storyboardIds',
      'shotIds',
      'panelIds',
      'storyboardId',
      'shotId',
      'panelId',
      'storyboard_ids',
      'shot_ids',
      'panel_ids',
      'storyboard_id',
      'shot_id',
      'panel_id',
    ]);
    if (direct != null) return direct;
    final scriptId = _productionScriptId(projectId, args);
    return scriptId == null ? null : _agentStoryboardIdsArg(scriptId, args);
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
          _productionAssetIdsArg(projectId, args, scriptId: scriptId) ??
          const [],
      associateAssetRefs: _stringListAny(args, const [
            'associateAssetsIds',
            'assetIds',
            'asset_ids',
            'associate_asset_ids',
            'associatedAssetIds',
            'associated_asset_ids',
            'assetName',
            'assetNames',
            'roleName',
            'roleNames',
            'sceneName',
            'sceneNames',
            'toolName',
            'toolNames',
            'asset_name',
            'asset_names',
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
    final assetIds = _productionStoryboardAssetIds(projectId, scriptId, item);
    final id = addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: item.prompt,
      videoDesc: item.videoDesc,
      duration: item.duration,
      assetIds: assetIds,
    );
    db.execute(
      'UPDATE o_storyboard SET shouldGenerateImage=?, track=? WHERE id=?',
      [item.shouldGenerateImage ? 1 : 0, item.track, id],
    );
    return id;
  }

  List<int> _productionStoryboardAssetIds(
    int projectId,
    int scriptId,
    ProductionStoryboardItem item,
  ) {
    final resolved = _productionAssetIdsFromRefs(
      projectId,
      item.associateAssetRefs,
      scriptId: scriptId,
    );
    if (resolved.isNotEmpty) return resolved;
    return item.associateAssetIds;
  }

  List<int> _productionAssetIdsFromRefs(
    int projectId,
    List<String> refs, {
    int? scriptId,
  }) {
    if (refs.isEmpty) return const [];
    final rows = _productionAssetRefRows(projectId, scriptId);
    final byId = {
      for (final row in rows) row['id'] as int: row,
    };
    final byName = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final name = (row['name'] as String? ?? '').trim();
      if (name.isNotEmpty) byName.putIfAbsent(name, () => row);
    }
    final ids = <int>[];
    final seen = <int>{};
    void add(int? id) {
      if (id == null || !byId.containsKey(id) || !seen.add(id)) return;
      ids.add(id);
    }

    for (final ref in refs) {
      final text = ref.trim();
      if (text.isEmpty) continue;
      final code = RegExp(r'^[Aa](\d+)$').firstMatch(text);
      if (code != null) {
        final index = int.parse(code.group(1)!) - 1;
        if (index >= 0 && index < rows.length) {
          add(rows[index]['id'] as int);
        }
        continue;
      }
      final directId = int.tryParse(text);
      if (directId != null) {
        add(directId);
        continue;
      }
      add(byName[text]?['id'] as int?);
    }
    return ids;
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
        await _agentPromptLongTermMemories(
          projectId,
          prompt,
          family: _productionAgentFamily,
          limit: _agentRagLimit(),
        ),
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
      if (_agentScriptIdsArg(projectId, toolArgs) == null) {
        toolArgs.putIfAbsent('scriptId', () => scriptId);
      }
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
    final assetRows = _productionAssetRefRows(projectId, scriptId);
    final assetLines = [
      for (var i = 0; i < assetRows.length; i++)
        '[${_productionAssetRefCode(i)}, '
            '${assetRows[i]['type'] ?? ''}, '
            '${assetRows[i]['name'] ?? ''}]'
            ' id=${assetRows[i]['id']}'
            '${(assetRows[i]['describe'] as String? ?? '').trim().isEmpty ? '' : ' 描述：${assetRows[i]['describe']}'}',
    ];
    return [
      '## 项目信息',
      '项目名称：${project?['name'] ?? '未知'}',
      '图像模型：${project?['imageModel'] ?? '未配置'}',
      '视频模型：${project?['videoModel'] ?? '未配置'}',
      '多参：${project?['mode'] ?? '未知'}',
      '画幅：${project?['videoRatio'] ?? '16:9'}',
      '当前剧本：${script?['name'] ?? scriptId}',
      '剧本内容：${script?['content'] ?? ''}',
      if (assetLines.isNotEmpty) '资产信息：',
      ...assetLines,
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
