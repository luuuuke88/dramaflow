import 'dart:convert';

import 'providers/openai_text.dart' show AgentToolDef;

const scriptAgentDecisionStage = 'scriptAgent:decisionAgent';
const scriptAgentStorySkeletonStage = 'scriptAgent:storySkeletonAgent';
const scriptAgentAdaptationStrategyStage =
    'scriptAgent:adaptationStrategyAgent';
const scriptAgentScriptStage = 'scriptAgent:scriptAgent';
const scriptAgentSupervisionStage = 'scriptAgent:supervisionAgent';
const scriptAgentWorkspaceKey = 'scriptAgent';

const scriptAgentStorySkeletonKey = 'storySkeleton';
const scriptAgentAdaptationStrategyKey = 'adaptationStrategy';
const scriptAgentSupervisionKey = 'supervision';

const scriptAgentWorkspaceDefaults = <String, dynamic>{
  scriptAgentStorySkeletonKey: '',
  scriptAgentAdaptationStrategyKey: '',
};

const productionAgentDecisionStage = 'productionAgent:decisionAgent';
const productionAgentDeriveAssetsStage = 'productionAgent:deriveAssetsAgent';
const productionAgentGenerateAssetsStage =
    'productionAgent:generateAssetsAgent';
const productionAgentDirectorPlanStage = 'productionAgent:directorPlanAgent';
const productionAgentStoryboardGenStage = 'productionAgent:storyboardGenAgent';
const productionAgentStoryboardPanelStage =
    'productionAgent:storyboardPanelAgent';
const productionAgentStoryboardTableStage =
    'productionAgent:storyboardTableAgent';
const productionAgentSupervisionStage = 'productionAgent:supervisionAgent';
const productionAgentWorkspaceKey = 'productionAgent';

const productionScriptPlanKey = 'scriptPlan';
const productionStoryboardTableKey = 'storyboardTable';
const productionSupervisionKey = 'supervision';

const productionAgentWorkspaceDefaults = <String, dynamic>{
  'script': '',
  productionScriptPlanKey: '',
  'assets': <dynamic>[],
  productionStoryboardTableKey: '',
  'storyboard': <dynamic>[],
};

const _scriptAgentReadTools = <AgentToolDef>[
  AgentToolDef(
    name: 'get_novel_events',
    description: '获取指定章节编号的事件摘要，用于故事骨架、改编策略和剧本编写。',
    schema: {
      'type': 'object',
      'properties': {
        'chapterIndexs': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
      },
    },
  ),
  AgentToolDef(
    name: 'get_planData',
    description:
        '获取剧本 Agent 工作区数据，可读取 storySkeleton、adaptationStrategy 或 script。',
    schema: {
      'type': 'object',
      'properties': {
        'key': {
          'type': 'string',
          'enum': ['storySkeleton', 'adaptationStrategy', 'script'],
        },
      },
    },
  ),
  AgentToolDef(
    name: 'get_novel_text',
    description: '获取小说章节原文内容。',
    schema: {
      'type': 'object',
      'properties': {
        'chapterIndex': {'type': 'string'},
      },
    },
  ),
  AgentToolDef(
    name: 'get_script_content',
    description: '获取已有剧本正文，通常用于衔接上一集。',
    schema: {
      'type': 'object',
      'properties': {
        'ids': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
    },
  ),
];

const _productionAgentReadWriteTools = <AgentToolDef>[
  AgentToolDef(
    name: 'get_flowData',
    description:
        '获取制作工作区数据，可读取 script、scriptPlan、assets、storyboardTable、storyboard。',
    schema: {
      'type': 'object',
      'properties': {
        'key': {
          'type': 'string',
          'enum': [
            'script',
            'scriptPlan',
            'assets',
            'storyboardTable',
            'storyboard'
          ],
        },
        'scriptId': {'type': 'integer'},
      },
    },
  ),
  AgentToolDef(
    name: 'add_deriveAsset',
    description: '新增或更新某个父资产的衍生资产。',
    schema: {
      'type': 'object',
      'properties': {
        'assetsId': {'type': 'integer'},
        'id': {
          'type': ['integer', 'null']
        },
        'name': {'type': 'string'},
        'desc': {'type': 'string'},
        'scriptId': {'type': 'integer'},
      },
      'required': ['assetsId', 'name', 'desc'],
    },
  ),
  AgentToolDef(
    name: 'del_deriveAsset',
    description: '删除衍生资产。',
    schema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'integer'},
        'scriptId': {'type': 'integer'},
      },
      'required': ['id'],
    },
  ),
  AgentToolDef(
    name: 'generate_deriveAsset',
    description: '为衍生资产提交图片生成任务。',
    schema: {
      'type': 'object',
      'properties': {
        'ids': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
      },
      'required': ['ids'],
    },
  ),
  AgentToolDef(
    name: 'generate_storyboard',
    description: '为分镜提交首帧图生成任务。',
    schema: {
      'type': 'object',
      'properties': {
        'ids': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
      },
      'required': ['ids'],
    },
  ),
  AgentToolDef(
    name: 'add_flowData_storyboard',
    description: '新增分镜面板项到制作工作区和分镜表。',
    schema: {
      'type': 'object',
      'properties': {
        'scriptId': {'type': 'integer'},
        'videoDesc': {'type': 'string'},
        'prompt': {
          'type': ['string', 'null']
        },
        'track': {'type': 'string'},
        'duration': {'type': 'number'},
        'associateAssetsIds': {
          'type': ['array', 'null'],
          'items': {'type': 'integer'},
        },
        'shouldGenerateImage': {'type': 'string'},
      },
      'required': ['videoDesc'],
    },
  ),
];

const Map<String, dynamic> _subAgentPromptAliasProperties = <String, dynamic>{
  'prompt': {
    'type': 'string',
    'description': '子 Agent 要执行的具体任务。',
  },
  'instruction': {
    'type': 'string',
    'description': 'prompt 的指令别名。',
  },
  'task': {
    'type': 'string',
    'description': 'prompt 的任务别名。',
  },
  'input': {
    'type': 'string',
    'description': 'prompt 的输入别名。',
  },
  'request': {
    'type': 'string',
    'description': 'prompt 的请求别名。',
  },
  'message': {
    'type': 'string',
    'description': 'prompt 的消息别名。',
  },
};

const Map<String, dynamic> _scriptSubAgentToolSchema = <String, dynamic>{
  'type': 'object',
  'properties': _subAgentPromptAliasProperties,
};

const Map<String, dynamic> _productionSubAgentToolSchema = <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{
    ..._subAgentPromptAliasProperties,
    'scriptId': {'type': 'integer'},
  },
};

const _productionAgentSubAgentTools = <AgentToolDef>[
  AgentToolDef(
    name: 'run_sub_agent_derive_assets',
    description: '运行执行导演子 Agent，完成衍生资产分析与写入。',
    schema: _productionSubAgentToolSchema,
  ),
  AgentToolDef(
    name: 'run_sub_agent_generate_assets',
    description: '运行执行导演子 Agent，提交衍生资产图片生成任务。',
    schema: _productionSubAgentToolSchema,
  ),
  AgentToolDef(
    name: 'run_sub_agent_director_plan',
    description: '运行执行导演子 Agent，输出 <scriptPlan> 并写入工作区。',
    schema: _productionSubAgentToolSchema,
  ),
  AgentToolDef(
    name: 'run_sub_agent_storyboard_gen',
    description: '运行执行导演子 Agent，提交分镜首帧图生成任务。',
    schema: _productionSubAgentToolSchema,
  ),
  AgentToolDef(
    name: 'run_sub_agent_storyboard_panel',
    description: '运行执行导演子 Agent，输出 <storyboardItem> 并写入分镜面板。',
    schema: _productionSubAgentToolSchema,
  ),
  AgentToolDef(
    name: 'run_sub_agent_storyboard_table',
    description: '运行执行导演子 Agent，输出 <storyboardTable> 并写入工作区。',
    schema: _productionSubAgentToolSchema,
  ),
  AgentToolDef(
    name: 'run_sub_agent_supervision',
    description: '运行制作监督层子 Agent 并写入制作工作区。',
    schema: _productionSubAgentToolSchema,
  ),
];

const _scriptAgentSubAgentTools = <AgentToolDef>[
  AgentToolDef(
    name: 'run_sub_agent_storySkeleton',
    description: '运行故事骨架执行 Agent，完成后把 <storySkeleton> 写入工作区。',
    schema: _scriptSubAgentToolSchema,
  ),
  AgentToolDef(
    name: 'run_sub_agent_adaptationStrategy',
    description: '运行改编策略执行 Agent，完成后把 <adaptationStrategy> 写入工作区。',
    schema: _scriptSubAgentToolSchema,
  ),
  AgentToolDef(
    name: 'run_sub_agent_script',
    description: '运行剧本编写执行 Agent，完成后把 <scriptItem> 写入剧本表。',
    schema: _scriptSubAgentToolSchema,
  ),
  AgentToolDef(
    name: 'run_supervision_agent',
    description: '运行监督层 Agent，对执行层产物做独立审核并写入工作区。',
    schema: _scriptSubAgentToolSchema,
  ),
];

List<AgentToolDef> scriptAgentDecisionTools(Iterable<AgentToolDef> baseTools) {
  final merged = <AgentToolDef>[];
  final seen = <String>{};
  for (final tool in [
    ...baseTools,
    ..._scriptAgentReadTools,
    ..._scriptAgentSubAgentTools,
  ]) {
    if (seen.add(tool.name)) merged.add(tool);
  }
  return merged;
}

List<AgentToolDef> scriptAgentExecutionTools(Iterable<AgentToolDef> baseTools) {
  final merged = <AgentToolDef>[];
  final seen = <String>{};
  for (final tool in [...baseTools, ..._scriptAgentReadTools]) {
    if (seen.add(tool.name)) merged.add(tool);
  }
  return merged;
}

List<AgentToolDef> productionAgentDecisionTools(
  Iterable<AgentToolDef> baseTools,
) {
  final merged = <AgentToolDef>[];
  final seen = <String>{};
  for (final tool in [
    ...baseTools,
    ..._productionAgentReadWriteTools,
    ..._productionAgentSubAgentTools,
  ]) {
    if (seen.add(tool.name)) merged.add(tool);
  }
  return merged;
}

List<AgentToolDef> productionAgentExecutionTools(
  Iterable<AgentToolDef> baseTools,
) {
  final merged = <AgentToolDef>[];
  final seen = <String>{};
  for (final tool in [...baseTools, ..._productionAgentReadWriteTools]) {
    if (seen.add(tool.name)) merged.add(tool);
  }
  return merged;
}

Map<String, dynamic> normalizeScriptAgentWorkspace(Object? raw) {
  final data = <String, dynamic>{...scriptAgentWorkspaceDefaults};
  if (raw is Map) {
    for (final entry in raw.entries) {
      data['${entry.key}'] = entry.value ?? '';
    }
  }
  data[scriptAgentStorySkeletonKey] =
      '${data[scriptAgentStorySkeletonKey] ?? ''}';
  data[scriptAgentAdaptationStrategyKey] =
      '${data[scriptAgentAdaptationStrategyKey] ?? ''}';
  if (data.containsKey(scriptAgentSupervisionKey)) {
    data[scriptAgentSupervisionKey] =
        '${data[scriptAgentSupervisionKey] ?? ''}';
  }
  return data;
}

String encodeScriptAgentWorkspace(Map<String, dynamic> data) =>
    jsonEncode(normalizeScriptAgentWorkspace(data));

Map<String, dynamic> normalizeProductionAgentWorkspace(Object? raw) {
  final data = <String, dynamic>{...productionAgentWorkspaceDefaults};
  if (raw is Map) {
    for (final entry in raw.entries) {
      data['${entry.key}'] = entry.value ?? '';
    }
  }
  data['script'] = '${data['script'] ?? ''}';
  data[productionScriptPlanKey] = '${data[productionScriptPlanKey] ?? ''}';
  data[productionStoryboardTableKey] =
      '${data[productionStoryboardTableKey] ?? ''}';
  data['assets'] = data['assets'] is List ? data['assets'] : <dynamic>[];
  data['storyboard'] =
      data['storyboard'] is List ? data['storyboard'] : <dynamic>[];
  if (data.containsKey(productionSupervisionKey)) {
    data[productionSupervisionKey] = '${data[productionSupervisionKey] ?? ''}';
  }
  return data;
}

String encodeProductionAgentWorkspace(Map<String, dynamic> data) =>
    jsonEncode(normalizeProductionAgentWorkspace(data));

String extractXmlTagText(String source, String tagName) {
  final tag = RegExp.escape(tagName);
  final match = RegExp(
    '<$tag\\b[^>]*>([\\s\\S]*?)</$tag>',
    caseSensitive: false,
  ).firstMatch(source);
  if (match == null) return '';
  return decodeXmlEntities(stripXmlTags(match.group(1) ?? '').trim());
}

String stripXmlTags(String source) =>
    source.replaceAll(RegExp(r'<[^>]+>'), '').trim();

String decodeXmlEntities(String source) {
  final named = source
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
  return named.replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|\d+);'), (match) {
    final raw = match.group(1)!;
    final code = raw.startsWith('x') || raw.startsWith('X')
        ? int.tryParse(raw.substring(1), radix: 16)
        : int.tryParse(raw);
    if (code == null) return match.group(0)!;
    return String.fromCharCode(code);
  });
}

class ScriptAgentScriptItem {
  final String name;
  final String content;
  const ScriptAgentScriptItem({required this.name, required this.content});
}

List<ScriptAgentScriptItem> parseScriptAgentScriptItems(String source) {
  final items = <ScriptAgentScriptItem>[];
  final matches = RegExp(
    r'<scriptItem\b([^>]*)>([\s\S]*?)</scriptItem>',
    caseSensitive: false,
  ).allMatches(source);

  for (final match in matches) {
    final attrs = match.group(1) ?? '';
    final body = match.group(2) ?? '';
    final name = _attributeValue(attrs, 'name').trim();
    if (name.isEmpty) continue;

    final contentMatch = RegExp(
      r'<content\b[^>]*>([\s\S]*?)</content>',
      caseSensitive: false,
    ).firstMatch(body);
    final rawContent = contentMatch?.group(1) ?? body;
    final content = decodeXmlEntities(stripXmlTags(rawContent).trim());
    if (content.isEmpty) continue;
    items.add(ScriptAgentScriptItem(
      name: decodeXmlEntities(name),
      content: content,
    ));
  }

  return items;
}

class ProductionStoryboardItem {
  final String videoDesc;
  final String prompt;
  final String track;
  final String duration;
  final List<int> associateAssetIds;
  final bool shouldGenerateImage;

  const ProductionStoryboardItem({
    required this.videoDesc,
    required this.prompt,
    required this.track,
    required this.duration,
    required this.associateAssetIds,
    required this.shouldGenerateImage,
  });
}

List<ProductionStoryboardItem> parseProductionStoryboardItems(String source) {
  final items = <ProductionStoryboardItem>[];
  final matches = RegExp(
    r'<storyboardItem\b([^>]*)>([\s\S]*?)</storyboardItem>',
    caseSensitive: false,
  ).allMatches(source);

  for (final match in matches) {
    final attrs = match.group(1) ?? '';
    final body = stripXmlTags(match.group(2) ?? '').trim();
    final videoDesc = decodeXmlEntities(
      (_attributeValue(attrs, 'videoDesc').trim().isEmpty
              ? body
              : _attributeValue(attrs, 'videoDesc'))
          .trim(),
    );
    if (videoDesc.isEmpty) continue;
    final prompt = decodeXmlEntities(_attributeValue(attrs, 'prompt').trim());
    final track = decodeXmlEntities(_attributeValue(attrs, 'track').trim());
    final duration =
        decodeXmlEntities(_attributeValue(attrs, 'duration').trim());
    final shouldGenerateImage = _truthyText(
      _attributeValue(attrs, 'shouldGenerateImage'),
      defaultValue: true,
    );
    final associateAssetIds =
        parseIntListText(_attributeValue(attrs, 'associateAssetsIds'));
    items.add(ProductionStoryboardItem(
      videoDesc: videoDesc,
      prompt: prompt,
      track: track,
      duration: duration,
      associateAssetIds: associateAssetIds,
      shouldGenerateImage: shouldGenerateImage,
    ));
  }

  return items;
}

List<int> parseIntListText(String source) {
  final text = decodeXmlEntities(source).trim();
  if (text.isEmpty) return const [];
  try {
    final decoded = jsonDecode(text);
    if (decoded is List) {
      return [
        for (final item in decoded)
          if (_intFromDynamic(item) != null) _intFromDynamic(item)!,
      ];
    }
  } catch (_) {
    // Fall through to loose numeric extraction for model-produced variants.
  }
  return [
    for (final match in RegExp(r'-?\d+').allMatches(text))
      int.parse(match.group(0)!),
  ];
}

int? _intFromDynamic(Object? raw) {
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}

bool _truthyText(String source, {required bool defaultValue}) {
  final text = source.trim().toLowerCase();
  if (text.isEmpty) return defaultValue;
  if (const {'true', '1', 'yes', 'y', '是'}.contains(text)) return true;
  if (const {'false', '0', 'no', 'n', '否'}.contains(text)) return false;
  return defaultValue;
}

String _attributeValue(String attrs, String name) {
  final escaped = RegExp.escape(name);
  final quoted = RegExp(
    "$escaped\\s*=\\s*([\"'])(.*?)\\1",
    caseSensitive: false,
  ).firstMatch(attrs);
  if (quoted != null) return quoted.group(2) ?? '';
  final bare = RegExp(
    '$escaped\\s*=\\s*([^\\s>]+)',
    caseSensitive: false,
  ).firstMatch(attrs);
  return bare?.group(1) ?? '';
}
