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

const Map<String, dynamic> _scriptChapterSelectorAliasProperties =
    <String, dynamic>{
  'novelIds': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': '小说章节数据库 id 列表。',
  },
  'novel_ids': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'novelIds 的 snake_case 别名。',
  },
  'chapterIndexs': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': '章节序号列表，兼容 ToonFlow 旧拼写。',
  },
  'chapterIndexes': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'chapterIndexs 的标准复数别名。',
  },
  'chapterIndex': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': '单个或多个章节序号。',
  },
  'chapterNo': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'chapterIndex 的自然语言别名。',
  },
  'chapterNos': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'chapterNo 的复数别名。',
  },
  'chapter_index': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'chapterIndex 的 snake_case 别名。',
  },
  'chapter_indexes': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'chapterIndexes 的 snake_case 别名。',
  },
  'chapter_no': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'chapterNo 的 snake_case 别名。',
  },
  'chapter_nos': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'chapterNos 的 snake_case 别名。',
  },
  'chapterName': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': '按章节名称精确匹配。',
  },
  'chapterNames': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'chapterName 的复数别名。',
  },
  'chapterTitle': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'chapterName 的标题语义别名。',
  },
  'chapterTitles': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'chapterTitle 的复数别名。',
  },
  'chapter_name': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'chapterName 的 snake_case 别名。',
  },
  'chapter_names': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'chapterNames 的 snake_case 别名。',
  },
  'chapter_title': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'chapterTitle 的 snake_case 别名。',
  },
  'chapter_titles': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'chapterTitles 的 snake_case 别名。',
  },
  'ids': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': '章节序号的通用 id 别名。',
  },
};

const Map<String, dynamic> _scriptContentIdAliasProperties = <String, dynamic>{
  'ids': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': '要读取的剧本 id 列表。',
  },
  'scriptIds': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'ids 的剧本语义别名。',
  },
  'episodeIds': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'scriptIds 的剧集语义别名。',
  },
  'episodesIds': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'episodeIds 的 ToonFlow 旧字段别名。',
  },
  'script_id': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'scriptIds 的 snake_case 单数别名。',
  },
  'episode_id': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'episodeIds 的 snake_case 单数别名。',
  },
  'episodes_id': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'episodesIds 的 snake_case 单数别名。',
  },
  'script_ids': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'scriptIds 的 snake_case 别名。',
  },
  'episode_ids': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'episodeIds 的 snake_case 别名。',
  },
  'episodes_ids': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'episodesIds 的 snake_case 别名。',
  },
  'scriptName': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': '按剧本名称精确匹配。',
  },
  'scriptNames': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'scriptName 的复数别名。',
  },
  'episodeName': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'scriptName 的集数语义别名。',
  },
  'episodeNames': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'episodeName 的复数别名。',
  },
  'scriptTitle': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'scriptName 的标题语义别名。',
  },
  'scriptTitles': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'scriptTitle 的复数别名。',
  },
  'episodeTitle': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'episodeName 的标题语义别名。',
  },
  'episodeTitles': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'episodeTitle 的复数别名。',
  },
  'script_name': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'scriptName 的 snake_case 别名。',
  },
  'script_names': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'scriptNames 的 snake_case 别名。',
  },
  'episode_name': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'episodeName 的 snake_case 别名。',
  },
  'episode_names': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'episodeNames 的 snake_case 别名。',
  },
  'script_title': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'scriptTitle 的 snake_case 别名。',
  },
  'script_titles': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'scriptTitles 的 snake_case 别名。',
  },
  'episode_title': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'episodeTitle 的 snake_case 别名。',
  },
  'episode_titles': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'episodeTitles 的 snake_case 别名。',
  },
};

const List<String> _scriptWorkspaceDataKeyEnum = <String>[
  'storySkeleton',
  'story_skeleton',
  'adaptationStrategy',
  'adaptation_strategy',
  'script',
];

const Map<String, dynamic> _scriptWorkspaceDataKeyAliasProperties =
    <String, dynamic>{
  'key': {
    'type': 'string',
    'enum': _scriptWorkspaceDataKeyEnum,
    'description': '要读取的剧本 Agent 工作区字段。',
  },
  'name': {
    'type': 'string',
    'enum': _scriptWorkspaceDataKeyEnum,
    'description': 'key 的自然语言别名。',
  },
  'section': {
    'type': 'string',
    'enum': _scriptWorkspaceDataKeyEnum,
    'description': 'key 的分区语义别名。',
  },
  'dataKey': {
    'type': 'string',
    'enum': _scriptWorkspaceDataKeyEnum,
    'description': 'key 的 ToonFlow 常见数据键别名。',
  },
  'flowKey': {
    'type': 'string',
    'enum': _scriptWorkspaceDataKeyEnum,
    'description': 'key 的工作流语义别名。',
  },
  'workspaceKey': {
    'type': 'string',
    'enum': _scriptWorkspaceDataKeyEnum,
    'description': 'key 的工作区语义别名。',
  },
  'data_key': {
    'type': 'string',
    'enum': _scriptWorkspaceDataKeyEnum,
    'description': 'dataKey 的 snake_case 别名。',
  },
  'flow_key': {
    'type': 'string',
    'enum': _scriptWorkspaceDataKeyEnum,
    'description': 'flowKey 的 snake_case 别名。',
  },
  'workspace_key': {
    'type': 'string',
    'enum': _scriptWorkspaceDataKeyEnum,
    'description': 'workspaceKey 的 snake_case 别名。',
  },
};

const _scriptAgentReadTools = <AgentToolDef>[
  AgentToolDef(
    name: 'get_novel_events',
    description: '获取指定章节编号的事件摘要，用于故事骨架、改编策略和剧本编写。',
    schema: {
      'type': 'object',
      'properties': _scriptChapterSelectorAliasProperties,
    },
  ),
  AgentToolDef(
    name: 'get_planData',
    description:
        '获取剧本 Agent 工作区数据，可读取 storySkeleton、adaptationStrategy 或 script。',
    schema: {
      'type': 'object',
      'properties': _scriptWorkspaceDataKeyAliasProperties,
    },
  ),
  AgentToolDef(
    name: 'get_novel_text',
    description: '获取小说章节原文内容。',
    schema: {
      'type': 'object',
      'properties': _scriptChapterSelectorAliasProperties,
    },
  ),
  AgentToolDef(
    name: 'get_script_content',
    description: '获取已有剧本正文，通常用于衔接上一集。',
    schema: {
      'type': 'object',
      'properties': _scriptContentIdAliasProperties,
    },
  ),
];

const Map<String, dynamic> _assetImageIdListAliasProperties = <String, dynamic>{
  'ids': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': '要生成图片的衍生资产 id 列表。',
  },
  'assetIds': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'ids 的资产语义别名。',
  },
  'assetsIds': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'assetIds 的 ToonFlow 旧字段别名。',
  },
  'deriveAssetIds': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'ids 的衍生资产语义别名。',
  },
  'deriveAssetsIds': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'deriveAssetIds 的复数字段别名。',
  },
  'asset_ids': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'assetIds 的 snake_case 别名。',
  },
  'assets_ids': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'assetsIds 的 snake_case 别名。',
  },
  'derive_asset_ids': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'deriveAssetIds 的 snake_case 别名。',
  },
  'derive_assets_ids': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'deriveAssetsIds 的 snake_case 别名。',
  },
  'assetName': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': '按资产名称精确匹配。',
  },
  'assetNames': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'assetName 的复数别名。',
  },
  'deriveAssetName': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': '按衍生资产名称精确匹配。',
  },
  'deriveAssetNames': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'deriveAssetName 的复数别名。',
  },
  'childAssetName': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': '按子资产名称精确匹配。',
  },
  'childAssetNames': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'childAssetName 的复数别名。',
  },
  'asset_name': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'assetName 的 snake_case 别名。',
  },
  'asset_names': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'assetNames 的 snake_case 别名。',
  },
  'derive_asset_name': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'deriveAssetName 的 snake_case 别名。',
  },
  'derive_asset_names': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'deriveAssetNames 的 snake_case 别名。',
  },
  'child_asset_name': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'childAssetName 的 snake_case 别名。',
  },
  'child_asset_names': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'childAssetNames 的 snake_case 别名。',
  },
};

const Map<String, dynamic> _storyboardImageIdListAliasProperties =
    <String, dynamic>{
  'ids': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': '要生成首帧图的分镜 id 列表。',
  },
  'storyboardIds': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'ids 的分镜语义别名。',
  },
  'shotIds': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'ids 的镜头语义别名。',
  },
  'panelIds': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'ids 的分镜面板语义别名。',
  },
  'storyboard_ids': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'storyboardIds 的 snake_case 别名。',
  },
  'shot_ids': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'shotIds 的 snake_case 别名。',
  },
  'panel_ids': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'panelIds 的 snake_case 别名。',
  },
  'shotNo': {
    'type': ['integer', 'array', 'string'],
    'items': {'type': 'integer'},
    'description': '按当前剧本分镜顺序选择镜头，例如 2 表示第二镜。',
  },
  'shotNos': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'shotNo 的复数别名。',
  },
  'storyboardNo': {
    'type': ['integer', 'array', 'string'],
    'items': {'type': 'integer'},
    'description': 'shotNo 的分镜语义别名。',
  },
  'storyboardNos': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'storyboardNo 的复数别名。',
  },
  'shot_no': {
    'type': ['integer', 'array', 'string'],
    'items': {'type': 'integer'},
    'description': 'shotNo 的 snake_case 别名。',
  },
  'shot_nos': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'shotNos 的 snake_case 别名。',
  },
  'storyboard_no': {
    'type': ['integer', 'array', 'string'],
    'items': {'type': 'integer'},
    'description': 'storyboardNo 的 snake_case 别名。',
  },
  'storyboard_nos': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'storyboardNos 的 snake_case 别名。',
  },
};

const List<String> _flowDataKeyValues = <String>[
  'script',
  'scriptPlan',
  'assets',
  'storyboardTable',
  'storyboard',
];

const Map<String, dynamic> _productionScriptNaturalSelectorAliasProperties =
    <String, dynamic>{
  'episodeNo': {
    'type': ['integer', 'array', 'string'],
    'items': {'type': 'integer'},
    'description': '按当前剧本列表顺序选择集数，例如 2 表示第二集。',
  },
  'episodeNos': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'episodeNo 的复数别名。',
  },
  'scriptNo': {
    'type': ['integer', 'array', 'string'],
    'items': {'type': 'integer'},
    'description': 'episodeNo 的剧本语义别名。',
  },
  'scriptNos': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'scriptNo 的复数别名。',
  },
  'episode_no': {
    'type': ['integer', 'array', 'string'],
    'items': {'type': 'integer'},
    'description': 'episodeNo 的 snake_case 别名。',
  },
  'episode_nos': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'episodeNos 的 snake_case 别名。',
  },
  'script_no': {
    'type': ['integer', 'array', 'string'],
    'items': {'type': 'integer'},
    'description': 'scriptNo 的 snake_case 别名。',
  },
  'script_nos': {
    'type': ['array', 'integer', 'string'],
    'items': {'type': 'integer'},
    'description': 'scriptNos 的 snake_case 别名。',
  },
  'scriptName': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': '按剧本名称精确匹配。',
  },
  'scriptNames': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'scriptName 的复数别名。',
  },
  'episodeName': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'scriptName 的集数语义别名。',
  },
  'episodeNames': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'episodeName 的复数别名。',
  },
  'scriptTitle': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'scriptName 的标题语义别名。',
  },
  'scriptTitles': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'scriptTitle 的复数别名。',
  },
  'episodeTitle': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'episodeName 的标题语义别名。',
  },
  'episodeTitles': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'episodeTitle 的复数别名。',
  },
  'script_name': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'scriptName 的 snake_case 别名。',
  },
  'script_names': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'scriptNames 的 snake_case 别名。',
  },
  'episode_name': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'episodeName 的 snake_case 别名。',
  },
  'episode_names': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'episodeNames 的 snake_case 别名。',
  },
  'script_title': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'scriptTitle 的 snake_case 别名。',
  },
  'script_titles': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'scriptTitles 的 snake_case 别名。',
  },
  'episode_title': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'episodeTitle 的 snake_case 别名。',
  },
  'episode_titles': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'episodeTitles 的 snake_case 别名。',
  },
};

const Map<String, dynamic> _flowDataReadAliasProperties = <String, dynamic>{
  'key': {
    'type': 'string',
    'enum': _flowDataKeyValues,
    'description': '要读取的制作工作区字段。',
  },
  'dataKey': {
    'type': 'string',
    'enum': _flowDataKeyValues,
    'description': 'key 的数据语义别名。',
  },
  'data_key': {
    'type': 'string',
    'enum': _flowDataKeyValues,
    'description': 'dataKey 的 snake_case 别名。',
  },
  'flowKey': {
    'type': 'string',
    'enum': _flowDataKeyValues,
    'description': 'key 的工作流语义别名。',
  },
  'flow_key': {
    'type': 'string',
    'enum': _flowDataKeyValues,
    'description': 'flowKey 的 snake_case 别名。',
  },
  'section': {
    'type': 'string',
    'enum': _flowDataKeyValues,
    'description': 'key 的工作区分段别名。',
  },
  'resource': {
    'type': 'string',
    'enum': _flowDataKeyValues,
    'description': 'key 的资源语义别名。',
  },
  'scriptId': {'type': 'integer'},
  'episodeId': {
    'type': 'integer',
    'description': 'scriptId 的剧集语义别名。',
  },
  'episodesId': {
    'type': 'integer',
    'description': 'scriptId 的 ToonFlow 旧字段别名。',
  },
  'script_id': {
    'type': 'integer',
    'description': 'scriptId 的 snake_case 别名。',
  },
  'episode_id': {
    'type': 'integer',
    'description': 'episodeId 的 snake_case 别名。',
  },
  'episodes_id': {
    'type': 'integer',
    'description': 'episodesId 的 snake_case 别名。',
  },
  'scriptIds': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': '可选。多个剧本 id；读取时使用第一项。',
  },
  'episodeIds': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'scriptIds 的剧集语义别名。',
  },
  'script_ids': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'scriptIds 的 snake_case 别名。',
  },
  'episode_ids': {
    'type': 'array',
    'items': {'type': 'integer'},
    'description': 'episodeIds 的 snake_case 别名。',
  },
  ..._productionScriptNaturalSelectorAliasProperties,
};

const Map<String, dynamic> _storyboardWriteAliasProperties = <String, dynamic>{
  'scriptId': {'type': 'integer'},
  'episodeId': {
    'type': 'integer',
    'description': 'scriptId 的剧集语义别名。',
  },
  'episodesId': {
    'type': 'integer',
    'description': 'scriptId 的 ToonFlow 旧字段别名。',
  },
  'script_id': {
    'type': 'integer',
    'description': 'scriptId 的 snake_case 别名。',
  },
  'episode_id': {
    'type': 'integer',
    'description': 'episodeId 的 snake_case 别名。',
  },
  'episodes_id': {
    'type': 'integer',
    'description': 'episodesId 的 snake_case 别名。',
  },
  ..._productionScriptNaturalSelectorAliasProperties,
  'videoDesc': {
    'type': 'string',
    'description': '分镜视频描述。',
  },
  'videoDescription': {
    'type': 'string',
    'description': 'videoDesc 的自然语言别名。',
  },
  'description': {
    'type': 'string',
    'description': 'videoDesc 的通用描述别名。',
  },
  'shotDesc': {
    'type': 'string',
    'description': 'videoDesc 的镜头描述别名。',
  },
  'video_desc': {
    'type': 'string',
    'description': 'videoDesc 的 snake_case 别名。',
  },
  'video_description': {
    'type': 'string',
    'description': 'videoDescription 的 snake_case 别名。',
  },
  'shot_desc': {
    'type': 'string',
    'description': 'shotDesc 的 snake_case 别名。',
  },
  'prompt': {
    'type': ['string', 'null'],
    'description': '分镜首帧图片提示词。',
  },
  'imagePrompt': {
    'type': ['string', 'null'],
    'description': 'prompt 的图片语义别名。',
  },
  'image_prompt': {
    'type': ['string', 'null'],
    'description': 'imagePrompt 的 snake_case 别名。',
  },
  'track': {'type': 'string'},
  'duration': {
    'type': ['number', 'string'],
    'description': '分镜时长。',
  },
  'durationSec': {
    'type': ['number', 'string'],
    'description': 'duration 的秒数别名。',
  },
  'duration_sec': {
    'type': ['number', 'string'],
    'description': 'durationSec 的 snake_case 别名。',
  },
  'associateAssetsIds': {
    'type': ['array', 'null'],
    'items': {'type': 'integer'},
    'description': '分镜关联资产 id 列表。',
  },
  'assetIds': {
    'type': ['array', 'null'],
    'items': {'type': 'integer'},
    'description': 'associateAssetsIds 的资产语义别名。',
  },
  'asset_ids': {
    'type': ['array', 'null'],
    'items': {'type': 'integer'},
    'description': 'assetIds 的 snake_case 别名。',
  },
  'assetName': {
    'type': ['string', 'array', 'null'],
    'items': {'type': 'string'},
    'description': '按关联资产名称精确匹配。',
  },
  'assetNames': {
    'type': ['array', 'string', 'null'],
    'items': {'type': 'string'},
    'description': 'assetName 的复数别名。',
  },
  'roleName': {
    'type': ['string', 'array', 'null'],
    'items': {'type': 'string'},
    'description': '按角色资产名称精确匹配。',
  },
  'roleNames': {
    'type': ['array', 'string', 'null'],
    'items': {'type': 'string'},
    'description': 'roleName 的复数别名。',
  },
  'sceneName': {
    'type': ['string', 'array', 'null'],
    'items': {'type': 'string'},
    'description': '按场景资产名称精确匹配。',
  },
  'sceneNames': {
    'type': ['array', 'string', 'null'],
    'items': {'type': 'string'},
    'description': 'sceneName 的复数别名。',
  },
  'toolName': {
    'type': ['string', 'array', 'null'],
    'items': {'type': 'string'},
    'description': '按道具资产名称精确匹配。',
  },
  'toolNames': {
    'type': ['array', 'string', 'null'],
    'items': {'type': 'string'},
    'description': 'toolName 的复数别名。',
  },
  'asset_name': {
    'type': ['string', 'array', 'null'],
    'items': {'type': 'string'},
    'description': 'assetName 的 snake_case 别名。',
  },
  'asset_names': {
    'type': ['array', 'string', 'null'],
    'items': {'type': 'string'},
    'description': 'assetNames 的 snake_case 别名。',
  },
  'associate_asset_ids': {
    'type': ['array', 'null'],
    'items': {'type': 'integer'},
    'description': 'associateAssetsIds 的 snake_case 别名。',
  },
  'associatedAssetIds': {
    'type': ['array', 'null'],
    'items': {'type': 'integer'},
    'description': 'associateAssetsIds 的常见拼写别名。',
  },
  'associated_asset_ids': {
    'type': ['array', 'null'],
    'items': {'type': 'integer'},
    'description': 'associatedAssetIds 的 snake_case 别名。',
  },
  'shouldGenerateImage': {
    'type': ['boolean', 'string', 'number'],
    'description': '是否后续生成首帧图。',
  },
  'generateImage': {
    'type': ['boolean', 'string', 'number'],
    'description': 'shouldGenerateImage 的简写别名。',
  },
  'should_generate_image': {
    'type': ['boolean', 'string', 'number'],
    'description': 'shouldGenerateImage 的 snake_case 别名。',
  },
  'generate_image': {
    'type': ['boolean', 'string', 'number'],
    'description': 'generateImage 的 snake_case 别名。',
  },
};

const Map<String, dynamic> _deriveAssetWriteAliasProperties = <String, dynamic>{
  'assetsId': {
    'type': 'integer',
    'description': '父资产 id。',
  },
  'assetId': {
    'type': 'integer',
    'description': 'assetsId 的单数语义别名。',
  },
  'parentAssetId': {
    'type': 'integer',
    'description': 'assetsId 的父资产语义别名。',
  },
  'parentAssetsId': {
    'type': 'integer',
    'description': 'assetsId 的 ToonFlow 复数字段别名。',
  },
  'asset_id': {
    'type': 'integer',
    'description': 'assetId 的 snake_case 别名。',
  },
  'assets_id': {
    'type': 'integer',
    'description': 'assetsId 的 snake_case 别名。',
  },
  'parent_asset_id': {
    'type': 'integer',
    'description': 'parentAssetId 的 snake_case 别名。',
  },
  'parent_assets_id': {
    'type': 'integer',
    'description': 'parentAssetsId 的 snake_case 别名。',
  },
  'parentAssetName': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': '按父资产名称精确匹配。',
  },
  'parentAssetNames': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'parentAssetName 的复数别名。',
  },
  'parentName': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'parentAssetName 的简写别名。',
  },
  'parentNames': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'parentName 的复数别名。',
  },
  'sourceAssetName': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'parentAssetName 的来源资产语义别名。',
  },
  'sourceAssetNames': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'sourceAssetName 的复数别名。',
  },
  'parent_asset_name': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'parentAssetName 的 snake_case 别名。',
  },
  'parent_asset_names': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'parentAssetNames 的 snake_case 别名。',
  },
  'source_asset_name': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'sourceAssetName 的 snake_case 别名。',
  },
  'source_asset_names': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'sourceAssetNames 的 snake_case 别名。',
  },
  'id': {
    'type': ['integer', 'null'],
    'description': '可选。已有衍生资产 id；为空时新增。',
  },
  'deriveAssetId': {
    'type': ['integer', 'null'],
    'description': 'id 的衍生资产语义别名。',
  },
  'childAssetId': {
    'type': ['integer', 'null'],
    'description': 'id 的子资产语义别名。',
  },
  'derive_asset_id': {
    'type': ['integer', 'null'],
    'description': 'deriveAssetId 的 snake_case 别名。',
  },
  'child_asset_id': {
    'type': ['integer', 'null'],
    'description': 'childAssetId 的 snake_case 别名。',
  },
  'name': {
    'type': 'string',
    'description': '衍生资产名称。',
  },
  'assetName': {
    'type': 'string',
    'description': 'name 的资产语义别名。',
  },
  'deriveAssetName': {
    'type': 'string',
    'description': 'name 的衍生资产语义别名。',
  },
  'childAssetName': {
    'type': 'string',
    'description': 'name 的子资产语义别名。',
  },
  'asset_name': {
    'type': 'string',
    'description': 'assetName 的 snake_case 别名。',
  },
  'derive_asset_name': {
    'type': 'string',
    'description': 'deriveAssetName 的 snake_case 别名。',
  },
  'child_asset_name': {
    'type': 'string',
    'description': 'childAssetName 的 snake_case 别名。',
  },
  'desc': {
    'type': 'string',
    'description': '衍生资产描述。',
  },
  'describe': {
    'type': 'string',
    'description': 'desc 的 ToonFlow 资产描述别名。',
  },
  'description': {
    'type': 'string',
    'description': 'desc 的自然语言别名。',
  },
  'assetDesc': {
    'type': 'string',
    'description': 'desc 的资产描述别名。',
  },
  'assetDescription': {
    'type': 'string',
    'description': 'description 的资产语义别名。',
  },
  'asset_desc': {
    'type': 'string',
    'description': 'assetDesc 的 snake_case 别名。',
  },
  'asset_description': {
    'type': 'string',
    'description': 'assetDescription 的 snake_case 别名。',
  },
  'scriptId': {'type': 'integer'},
  'episodeId': {
    'type': 'integer',
    'description': 'scriptId 的剧集语义别名。',
  },
  'episodesId': {
    'type': 'integer',
    'description': 'scriptId 的 ToonFlow 旧字段别名。',
  },
  'script_id': {
    'type': 'integer',
    'description': 'scriptId 的 snake_case 别名。',
  },
  'episode_id': {
    'type': 'integer',
    'description': 'episodeId 的 snake_case 别名。',
  },
  'episodes_id': {
    'type': 'integer',
    'description': 'episodesId 的 snake_case 别名。',
  },
  ..._productionScriptNaturalSelectorAliasProperties,
};

const Map<String, dynamic> _deriveAssetDeleteIdAliasProperties =
    <String, dynamic>{
  'id': {
    'type': 'integer',
    'description': '要删除的衍生资产 id。',
  },
  'assetId': {
    'type': 'integer',
    'description': 'id 的资产语义别名。',
  },
  'deriveAssetId': {
    'type': 'integer',
    'description': 'id 的衍生资产语义别名。',
  },
  'childAssetId': {
    'type': 'integer',
    'description': 'id 的子资产语义别名。',
  },
  'asset_id': {
    'type': 'integer',
    'description': 'assetId 的 snake_case 别名。',
  },
  'derive_asset_id': {
    'type': 'integer',
    'description': 'deriveAssetId 的 snake_case 别名。',
  },
  'child_asset_id': {
    'type': 'integer',
    'description': 'childAssetId 的 snake_case 别名。',
  },
  'assetName': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': '按衍生资产名称精确匹配。',
  },
  'assetNames': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'assetName 的复数别名。',
  },
  'deriveAssetName': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': '按衍生资产名称精确匹配。',
  },
  'deriveAssetNames': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'deriveAssetName 的复数别名。',
  },
  'childAssetName': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': '按子资产名称精确匹配。',
  },
  'childAssetNames': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'childAssetName 的复数别名。',
  },
  'asset_name': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'assetName 的 snake_case 别名。',
  },
  'asset_names': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'assetNames 的 snake_case 别名。',
  },
  'derive_asset_name': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'deriveAssetName 的 snake_case 别名。',
  },
  'derive_asset_names': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'deriveAssetNames 的 snake_case 别名。',
  },
  'child_asset_name': {
    'type': ['string', 'array'],
    'items': {'type': 'string'},
    'description': 'childAssetName 的 snake_case 别名。',
  },
  'child_asset_names': {
    'type': ['array', 'string'],
    'items': {'type': 'string'},
    'description': 'childAssetNames 的 snake_case 别名。',
  },
  'scriptId': {'type': 'integer'},
  'episodeId': {
    'type': 'integer',
    'description': 'scriptId 的剧集语义别名。',
  },
  'episodesId': {
    'type': 'integer',
    'description': 'scriptId 的 ToonFlow 旧字段别名。',
  },
  'script_id': {
    'type': 'integer',
    'description': 'scriptId 的 snake_case 别名。',
  },
  'episode_id': {
    'type': 'integer',
    'description': 'episodeId 的 snake_case 别名。',
  },
  'episodes_id': {
    'type': 'integer',
    'description': 'episodesId 的 snake_case 别名。',
  },
  ..._productionScriptNaturalSelectorAliasProperties,
};

const _productionAgentReadWriteTools = <AgentToolDef>[
  AgentToolDef(
    name: 'get_flowData',
    description:
        '获取制作工作区数据，可读取 script、scriptPlan、assets、storyboardTable、storyboard。',
    schema: {
      'type': 'object',
      'properties': _flowDataReadAliasProperties,
    },
  ),
  AgentToolDef(
    name: 'add_deriveAsset',
    description: '新增或更新某个父资产的衍生资产。',
    schema: {
      'type': 'object',
      'properties': _deriveAssetWriteAliasProperties,
    },
  ),
  AgentToolDef(
    name: 'del_deriveAsset',
    description: '删除衍生资产。',
    schema: {
      'type': 'object',
      'properties': _deriveAssetDeleteIdAliasProperties,
    },
  ),
  AgentToolDef(
    name: 'generate_deriveAsset',
    description: '为衍生资产提交图片生成任务。',
    schema: {
      'type': 'object',
      'properties': _assetImageIdListAliasProperties,
    },
  ),
  AgentToolDef(
    name: 'generate_storyboard',
    description: '为分镜提交首帧图生成任务。',
    schema: {
      'type': 'object',
      'properties': _storyboardImageIdListAliasProperties,
    },
  ),
  AgentToolDef(
    name: 'add_flowData_storyboard',
    description: '新增分镜面板项到制作工作区和分镜表。',
    schema: {
      'type': 'object',
      'properties': _storyboardWriteAliasProperties,
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
    'scriptId': {
      'type': 'integer',
      'description': '目标剧本 id。',
    },
    'episodeId': {
      'type': 'integer',
      'description': 'scriptId 的 episode 别名。',
    },
    'episodesId': {
      'type': 'integer',
      'description': 'scriptId 的 ToonFlow 旧字段别名。',
    },
    'script_id': {
      'type': 'integer',
      'description': 'scriptId 的 snake_case 别名。',
    },
    'episode_id': {
      'type': 'integer',
      'description': 'episodeId 的 snake_case 别名。',
    },
    'episodes_id': {
      'type': 'integer',
      'description': 'episodesId 的 snake_case 别名。',
    },
    'scriptIds': {
      'type': 'array',
      'items': {'type': 'integer'},
      'description': '可选。多个剧本 id；当前子 Agent 使用第一项作为目标剧本。',
    },
    'episodeIds': {
      'type': 'array',
      'items': {'type': 'integer'},
      'description': 'scriptIds 的 episode 别名。',
    },
    'script_ids': {
      'type': 'array',
      'items': {'type': 'integer'},
      'description': 'scriptIds 的 snake_case 别名。',
    },
    'episode_ids': {
      'type': 'array',
      'items': {'type': 'integer'},
      'description': 'episodeIds 的 snake_case 别名。',
    },
    ..._productionScriptNaturalSelectorAliasProperties,
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
  final List<String> associateAssetRefs;
  final bool shouldGenerateImage;

  const ProductionStoryboardItem({
    required this.videoDesc,
    required this.prompt,
    required this.track,
    required this.duration,
    required this.associateAssetIds,
    this.associateAssetRefs = const [],
    required this.shouldGenerateImage,
  });
}

List<ProductionStoryboardItem> parseProductionStoryboardItems(String source) {
  final items = <ProductionStoryboardItem>[];
  final pairedMatches = RegExp(
    r'<storyboardItem\b([^>]*)>([\s\S]*?)</storyboardItem>',
    caseSensitive: false,
  ).allMatches(source);

  for (final match in pairedMatches) {
    final attrs = match.group(1) ?? '';
    final body = stripXmlTags(match.group(2) ?? '').trim();
    final item = _storyboardItemFromAttrs(attrs, body: body);
    if (item != null) items.add(item);
  }

  final selfClosingMatches = RegExp(
    r'<storyboardItem\b([^>]*)/>',
    caseSensitive: false,
  ).allMatches(source);
  for (final match in selfClosingMatches) {
    final item = _storyboardItemFromAttrs(match.group(1) ?? '');
    if (item != null) items.add(item);
  }

  return items;
}

ProductionStoryboardItem? _storyboardItemFromAttrs(
  String attrs, {
  String body = '',
}) {
  final videoDesc = decodeXmlEntities(
    (_attributeValue(attrs, 'videoDesc').trim().isEmpty
            ? body
            : _attributeValue(attrs, 'videoDesc'))
        .trim(),
  );
  if (videoDesc.isEmpty) return null;
  final prompt = decodeXmlEntities(_attributeValue(attrs, 'prompt').trim());
  final track = decodeXmlEntities(_attributeValue(attrs, 'track').trim());
  final duration = decodeXmlEntities(_attributeValue(attrs, 'duration').trim());
  final shouldGenerateImage = _truthyText(
    _attributeValue(attrs, 'shouldGenerateImage'),
    defaultValue: true,
  );
  return ProductionStoryboardItem(
    videoDesc: videoDesc,
    prompt: prompt,
    track: track,
    duration: duration,
    associateAssetIds: _storyboardAssetIds(attrs),
    associateAssetRefs: _storyboardAssetRefs(attrs),
    shouldGenerateImage: shouldGenerateImage,
  );
}

List<int> _storyboardAssetIds(String attrs) => _dedupeInts([
      for (final key in const [
        'associateAssetsIds',
        'assetIds',
        'asset_ids',
        'associate_asset_ids',
        'associatedAssetIds',
        'associated_asset_ids',
      ])
        ...parseIntListText(_attributeValue(attrs, key)),
    ]);

List<String> _storyboardAssetRefs(String attrs) => _dedupeStrings([
      for (final key in const [
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
      ])
        ...parseStringListText(_attributeValue(attrs, key)),
    ]);

List<String> parseStringListText(String source) {
  final text = decodeXmlEntities(source).trim();
  if (text.isEmpty) return const [];
  try {
    final decoded = jsonDecode(text);
    if (decoded is List) {
      return [
        for (final item in decoded)
          if (item.toString().trim().isNotEmpty) item.toString().trim(),
      ];
    }
    final scalar = decoded.toString().trim();
    return scalar.isEmpty ? const [] : [scalar];
  } catch (_) {
    // Fall through to loose splitting for model-produced variants.
  }
  final unwrapped = text
      .replaceAll(RegExp(r'^\s*\[\s*'), '')
      .replaceAll(RegExp(r'\s*\]\s*$'), '');
  final values = [
    for (final part in unwrapped.split(RegExp(r'[,，、;；\n]+')))
      if (part.trim().isNotEmpty)
        part.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), ''),
  ];
  return _dedupeStrings(values);
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

List<int> _dedupeInts(Iterable<int> values) {
  final seen = <int>{};
  return [
    for (final value in values)
      if (seen.add(value)) value,
  ];
}

List<String> _dedupeStrings(Iterable<String> values) {
  final seen = <String>{};
  return [
    for (final value in values)
      if (value.trim().isNotEmpty && seen.add(value.trim())) value.trim(),
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
