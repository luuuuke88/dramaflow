// 助手阶段注册表（v0.4 瘦身版）：只保留两个家族基座。
// 旧版 20 个定义中的 15 个多层子代理阶段随 spec §2 砍除；DB 键值保持兼容
// （'scriptAgent'/'productionAgent' 与旧 o_agentDeploy 行同键）。
class AssistantStageDefinition {
  final String key;
  final String name;
  final String fallbackStage;
  final int sortOrder;
  final int defaultMaxOutputTokens;
  final int defaultTemperature;

  const AssistantStageDefinition({
    required this.key,
    required this.name,
    required this.fallbackStage,
    required this.sortOrder,
    this.defaultMaxOutputTokens = 8000,
    this.defaultTemperature = 70,
  });
}

const assistantStageDefinitions = <AssistantStageDefinition>[
  AssistantStageDefinition(
    key: 'scriptAgent',
    name: '剧本助手',
    fallbackStage: 'script_gen',
    sortOrder: 0,
  ),
  AssistantStageDefinition(
    key: 'productionAgent',
    name: '制作助手',
    fallbackStage: 'storyboard_gen',
    sortOrder: 1,
  ),
];

final assistantStageDefinitionByKey = {
  for (final d in assistantStageDefinitions) d.key: d,
};

final assistantStageKeys = [
  for (final d in assistantStageDefinitions) d.key,
];

AssistantStageDefinition? assistantStageDefinition(String key) =>
    assistantStageDefinitionByKey[key];

String assistantStageFallback(String key) =>
    assistantStageDefinitionByKey[key]?.fallbackStage ?? key;
