class AgentStageDefinition {
  final String key;
  final String name;
  final String family;
  final String role;
  final String fallbackStage;
  final int sortOrder;
  final int defaultMaxOutputTokens;
  final int defaultTemperature;

  const AgentStageDefinition({
    required this.key,
    required this.name,
    required this.family,
    required this.role,
    required this.fallbackStage,
    required this.sortOrder,
    this.defaultMaxOutputTokens = 8000,
    this.defaultTemperature = 70,
  });
}

const agentStageDefinitions = <AgentStageDefinition>[
  AgentStageDefinition(
    key: 'scriptAgent',
    name: '剧本 Agent',
    family: 'scriptAgent',
    role: 'decision',
    fallbackStage: 'script_gen',
    sortOrder: 0,
  ),
  AgentStageDefinition(
    key: 'scriptAgent:decisionAgent',
    name: '剧本决策 Agent',
    family: 'scriptAgent',
    role: 'decision',
    fallbackStage: 'script_gen',
    sortOrder: 1,
  ),
  AgentStageDefinition(
    key: 'scriptAgent:storySkeletonAgent',
    name: '故事骨架 Agent',
    family: 'scriptAgent',
    role: 'execution',
    fallbackStage: 'script_gen',
    sortOrder: 2,
  ),
  AgentStageDefinition(
    key: 'scriptAgent:adaptationStrategyAgent',
    name: '改编策略 Agent',
    family: 'scriptAgent',
    role: 'execution',
    fallbackStage: 'script_gen',
    sortOrder: 3,
  ),
  AgentStageDefinition(
    key: 'scriptAgent:scriptAgent',
    name: '剧本执行 Agent',
    family: 'scriptAgent',
    role: 'execution',
    fallbackStage: 'script_gen',
    sortOrder: 4,
  ),
  AgentStageDefinition(
    key: 'scriptAgent:supervisionAgent',
    name: '剧本监督 Agent',
    family: 'scriptAgent',
    role: 'supervision',
    fallbackStage: 'script_gen',
    sortOrder: 5,
  ),
  AgentStageDefinition(
    key: 'productionAgent',
    name: '生产 Agent',
    family: 'productionAgent',
    role: 'decision',
    fallbackStage: 'storyboard_gen',
    sortOrder: 20,
  ),
  AgentStageDefinition(
    key: 'productionAgent:decisionAgent',
    name: '生产决策 Agent',
    family: 'productionAgent',
    role: 'decision',
    fallbackStage: 'storyboard_gen',
    sortOrder: 21,
  ),
  AgentStageDefinition(
    key: 'productionAgent:deriveAssetsAgent',
    name: '资产推导 Agent',
    family: 'productionAgent',
    role: 'execution',
    fallbackStage: 'asset_extract',
    sortOrder: 22,
  ),
  AgentStageDefinition(
    key: 'productionAgent:generateAssetsAgent',
    name: '资产生成 Agent',
    family: 'productionAgent',
    role: 'execution',
    fallbackStage: 'asset_extract',
    sortOrder: 23,
  ),
  AgentStageDefinition(
    key: 'productionAgent:directorPlanAgent',
    name: '导演规划 Agent',
    family: 'productionAgent',
    role: 'execution',
    fallbackStage: 'storyboard_gen',
    sortOrder: 24,
  ),
  AgentStageDefinition(
    key: 'productionAgent:storyboardGenAgent',
    name: '分镜生成 Agent',
    family: 'productionAgent',
    role: 'execution',
    fallbackStage: 'storyboard_gen',
    sortOrder: 25,
  ),
  AgentStageDefinition(
    key: 'productionAgent:storyboardPanelAgent',
    name: '分镜画面 Agent',
    family: 'productionAgent',
    role: 'execution',
    fallbackStage: 'storyboard_gen',
    sortOrder: 26,
  ),
  AgentStageDefinition(
    key: 'productionAgent:storyboardTableAgent',
    name: '分镜表 Agent',
    family: 'productionAgent',
    role: 'execution',
    fallbackStage: 'storyboard_gen',
    sortOrder: 27,
  ),
  AgentStageDefinition(
    key: 'productionAgent:supervisionAgent',
    name: '生产监督 Agent',
    family: 'productionAgent',
    role: 'supervision',
    fallbackStage: 'storyboard_gen',
    sortOrder: 28,
  ),
  AgentStageDefinition(
    key: 'script_gen',
    name: '剧本生成',
    family: 'pipeline',
    role: 'pipeline',
    fallbackStage: 'script_gen',
    sortOrder: 100,
  ),
  AgentStageDefinition(
    key: 'event_extract',
    name: '事件提取',
    family: 'pipeline',
    role: 'pipeline',
    fallbackStage: 'event_extract',
    sortOrder: 101,
  ),
  AgentStageDefinition(
    key: 'asset_extract',
    name: '资产提取',
    family: 'pipeline',
    role: 'pipeline',
    fallbackStage: 'asset_extract',
    sortOrder: 102,
  ),
  AgentStageDefinition(
    key: 'storyboard_gen',
    name: '分镜生成',
    family: 'pipeline',
    role: 'pipeline',
    fallbackStage: 'storyboard_gen',
    sortOrder: 103,
  ),
  AgentStageDefinition(
    key: 'video_prompt_gen',
    name: '视频提示词',
    family: 'pipeline',
    role: 'pipeline',
    fallbackStage: 'video_prompt_gen',
    sortOrder: 104,
  ),
];

final agentStageDefinitionByKey = {
  for (final definition in agentStageDefinitions) definition.key: definition,
};

final agentStageKeys = [
  for (final definition in agentStageDefinitions) definition.key,
];

AgentStageDefinition? agentStageDefinition(String key) =>
    agentStageDefinitionByKey[key];

String agentStageFallback(String key) =>
    agentStageDefinitionByKey[key]?.fallbackStage ?? key;

int agentStageSortOrder(String key) =>
    agentStageDefinitionByKey[key]?.sortOrder ?? 9999;
