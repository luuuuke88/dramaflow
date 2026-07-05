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

const _scriptAgentSubAgentTools = <AgentToolDef>[
  AgentToolDef(
    name: 'run_sub_agent_storySkeleton',
    description: '运行故事骨架执行 Agent，完成后把 <storySkeleton> 写入工作区。',
    schema: {
      'type': 'object',
      'properties': {
        'prompt': {'type': 'string'},
      },
      'required': ['prompt'],
    },
  ),
  AgentToolDef(
    name: 'run_sub_agent_adaptationStrategy',
    description: '运行改编策略执行 Agent，完成后把 <adaptationStrategy> 写入工作区。',
    schema: {
      'type': 'object',
      'properties': {
        'prompt': {'type': 'string'},
      },
      'required': ['prompt'],
    },
  ),
  AgentToolDef(
    name: 'run_sub_agent_script',
    description: '运行剧本编写执行 Agent，完成后把 <scriptItem> 写入剧本表。',
    schema: {
      'type': 'object',
      'properties': {
        'prompt': {'type': 'string'},
      },
      'required': ['prompt'],
    },
  ),
  AgentToolDef(
    name: 'run_supervision_agent',
    description: '运行监督层 Agent，对执行层产物做独立审核并写入工作区。',
    schema: {
      'type': 'object',
      'properties': {
        'prompt': {'type': 'string'},
      },
      'required': ['prompt'],
    },
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
