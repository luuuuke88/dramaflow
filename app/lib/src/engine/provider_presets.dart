/// 供应商预设目录（spec §3-4），同时是 azt/volcengine 种子的单一事实来源
/// （engine.dart `_seedDefaults` 从这里构建，防漂移测试锁定）。
/// 内容独立编写；模型 ID 经 sourceUrl 核实后方可入列（verifiedAt 为核实日）。
/// 不得从 ToonFlow data/vendor/*.ts 复制任何代码或文案（许可证红线）。
library;

import 'video_request.dart';

class PresetModel {
  final String modelId;
  final String label;
  final String kind; // text | image | video | tts
  final Map<String, Object?> capabilities;

  const PresetModel(this.modelId, this.kind,
      {String? label, this.capabilities = const {}})
      : label = label ?? modelId;
}

class ProviderPreset {
  final String id;
  final String name;
  final String baseUrl;
  final String keyUrl;
  final String protocol; // openai_compatible | volcengine
  final bool compatMode;
  final bool desktopOnly;
  final bool acceptanceVerified; // 仅当 Task 7 验收表有证据行才可 true
  final String sourceUrl;
  final String verifiedAt; // YYYY-MM-DD
  final List<PresetModel> models;

  const ProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.keyUrl,
    this.protocol = 'openai_compatible',
    this.compatMode = false,
    this.desktopOnly = false,
    this.acceptanceVerified = false,
    required this.sourceUrl,
    required this.verifiedAt,
    required this.models,
  });
}

ProviderPreset? providerPresetById(String id) {
  for (final p in kProviderPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// modelId -> kind，供 /models 候选自动归类（spec §5 第 5 条）。
Map<String, String> presetModelKinds(String presetId) {
  final p = providerPresetById(presetId);
  if (p == null) return const {};
  return {for (final m in p.models) m.modelId: m.kind};
}

/// Seedance Mini 能力集：从 engine.dart `_legacySeedanceMiniCapabilities` 迁来的
/// 唯一定义（engine 的种子与 `_seedSeedanceVideoProfiles` 迁移均引用此处）。
Map<String, Object?> seedanceMiniCapabilities() => {
      'durations': [for (var i = 4; i <= 15; i++) i],
      'resolutions': ['480p', '720p'],
      'video': {
        'modes': [VideoMode.firstFrame.wireValue],
        'references': const {},
        'durations': [for (var i = 4; i <= 15; i++) i],
        'resolutions': ['480p', '720p'],
        'ratios': ['16:9', '9:16'],
        'audio': 'none',
        'promptTemplates': const {},
      },
    };

final kProviderPresets = <ProviderPreset>[
  const ProviderPreset(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    keyUrl: 'https://platform.openai.com/api-keys',
    sourceUrl: 'https://developers.openai.com/api/docs/models',
    verifiedAt: '2026-07-18', // WebFetch 核实：gpt-5.6 三档+gpt-image-2 均在列，原样确认
    models: [
      PresetModel('gpt-5.6-sol', 'text'),
      PresetModel('gpt-5.6-terra', 'text'),
      PresetModel('gpt-5.6-luna', 'text'),
      PresetModel('gpt-image-2', 'image'),
    ],
  ),
  const ProviderPreset(
    id: 'anthropic',
    name: 'Claude (Anthropic)',
    baseUrl: 'https://api.anthropic.com/v1',
    keyUrl: 'https://console.anthropic.com/settings/keys',
    compatMode: true,
    sourceUrl:
        'https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions',
    verifiedAt: '2026-07-18', // WebFetch 核实：sonnet-5/opus-4-8/haiku-4-5（官方别名）均在列，原样确认
    models: [
      PresetModel('claude-sonnet-5', 'text'),
      PresetModel('claude-opus-4-8', 'text'),
      PresetModel('claude-haiku-4-5', 'text'),
    ],
  ),
  const ProviderPreset(
    id: 'gemini',
    name: 'Gemini (Google)',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    keyUrl: 'https://aistudio.google.com/apikey',
    compatMode: true,
    sourceUrl: 'https://ai.google.dev/gemini-api/docs/openai',
    verifiedAt: '2026-07-18', // WebFetch+WebSearch 核实：无 gemini-3-pro，改用 gemini-3.1-pro-preview（当前唯一 Gemini 3 代 Pro 档，无 GA 非 preview 变体）
    models: [
      PresetModel('gemini-3.5-flash', 'text'),
      PresetModel('gemini-3.1-pro-preview', 'text'),
    ],
  ),
  const ProviderPreset(
    id: 'xai',
    name: 'Grok (xAI)',
    baseUrl: 'https://api.x.ai/v1',
    keyUrl: 'https://console.x.ai',
    compatMode: true,
    sourceUrl: 'https://docs.x.ai/developers/models',
    verifiedAt: '2026-07-18', // WebFetch 核实：grok-4.5/grok-4.3 均在定价表在列，原样确认
    models: [
      PresetModel('grok-4.5', 'text'),
      PresetModel('grok-4.3', 'text'),
    ],
  ),
  const ProviderPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    keyUrl: 'https://openrouter.ai/settings/keys',
    sourceUrl: 'https://openrouter.ai/models',
    verifiedAt: '2026-07-18', // 页面为 JS 渲染 WebFetch 抓不到列表，改用公开 GET /api/v1/models 真实调用核实（344 个模型）：anthropic/claude-sonnet-5、openai/gpt-5.1 命中；google/gemini-3-pro 不存在，改 google/gemini-3.1-pro-preview
    models: [
      PresetModel('anthropic/claude-sonnet-5', 'text'),
      PresetModel('google/gemini-3.1-pro-preview', 'text'),
      PresetModel('openai/gpt-5.1', 'text'),
    ],
  ),
  const ProviderPreset(
    id: 'siliconflow',
    name: '硅基流动 SiliconFlow',
    baseUrl: 'https://api.siliconflow.cn/v1',
    keyUrl: 'https://cloud.siliconflow.cn/account/ak',
    sourceUrl:
        'https://docs.siliconflow.cn/cn/api-reference/models/get-model-list',
    verifiedAt: '2026-07-18', // API 文档页无具体型号示例，改用各模型详情页核实：DeepSeek-V3.2、Kwai-Kolors/Kolors 原样确认；Qwen3-Max 在硅基流动不存在（该家只托管开源权重，Max 是阿里云自有闭源档，仅 dashscope 有），改用其开源旗舰 Qwen/Qwen3.5-397B-A17B
    models: [
      PresetModel('deepseek-ai/DeepSeek-V3.2', 'text'),
      PresetModel('Qwen/Qwen3.5-397B-A17B', 'text'),
      PresetModel('Kwai-Kolors/Kolors', 'image'),
    ],
  ),
  const ProviderPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    keyUrl: 'https://platform.deepseek.com/api_keys',
    sourceUrl: 'https://api-docs.deepseek.com',
    verifiedAt: '2026-07-19', // 独立复核（任务评审要求：不参考 ToonFlow 任何文件，仅从 api-docs.deepseek.com 官方域名重新 WebFetch 正文+定价页+WebSearch 交叉核实）：deepseek-chat/deepseek-reasoner 仍将于 2026-07-24 15:59 UTC 停用（原样确认，剩5天）；deepseek-v4-flash/deepseek-v4-pro 经官方定价页确认为两个独立在架型号、非同一模型别名（v4-pro 1.6T/49B 激活参数强推理档，定价约为 v4-flash 284B/13B 激活参数档的3倍），原样保留
    models: [
      PresetModel('deepseek-v4-flash', 'text'),
      PresetModel('deepseek-v4-pro', 'text'),
    ],
  ),
  const ProviderPreset(
    id: 'moonshot',
    name: 'Kimi (Moonshot)',
    baseUrl: 'https://api.moonshot.cn/v1',
    keyUrl: 'https://platform.moonshot.cn/console/api-keys',
    sourceUrl: 'https://platform.moonshot.cn/docs',
    verifiedAt: '2026-07-19', // 独立复核（任务评审要求：不参考 ToonFlow 任何文件，仅从 platform.moonshot.cn/docs 重新 WebFetch，再次确认跳转至新域名 platform.kimi.com/docs+WebSearch 交叉核实）：kimi-k3（2.8万亿参数旗舰，2026-07-16 刚发布，官方文档原样在列）与 kimi-k2.6（通用次档，256K上下文，官方文档原样在列）均确认现役；kimi-latest（2026-01-28停用）、kimi-k2 系列（2026-05-25停用）交叉核实确认已下线，原样保留
    models: [
      PresetModel('kimi-k3', 'text'),
      PresetModel('kimi-k2.6', 'text'),
    ],
  ),
  const ProviderPreset(
    id: 'zhipu',
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    keyUrl: 'https://open.bigmodel.cn/usercenter/apikeys',
    sourceUrl: 'https://docs.bigmodel.cn',
    verifiedAt: '2026-07-18', // WebFetch+WebSearch 核实：glm-4.6 仍在列但已非旗舰，改用当前旗舰 glm-5.2（2026-06 发布，API id 经二次搜索交叉确认）；cogview-4 原样确认仍在架
    models: [
      PresetModel('glm-5.2', 'text'),
      PresetModel('cogview-4', 'image'),
    ],
  ),
  const ProviderPreset(
    id: 'dashscope',
    name: '通义 Qwen',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    keyUrl: 'https://bailian.console.aliyun.com/?apiKey=1',
    sourceUrl: 'https://help.aliyun.com/zh/model-studio/models',
    verifiedAt: '2026-07-18', // help.aliyun.com 被 WebFetch 域名策略拦截，改用 alibabacloud.com 镜像页+WebSearch 交叉核实：qwen3-max 已被 qwen3.7-max 取代（当前旗舰），qwen-plus（评测/兼容层长青别名）原样确认仍在架
    models: [
      PresetModel('qwen3.7-max', 'text'),
      PresetModel('qwen-plus', 'text'),
      // 图片是否过兼容层：spec §4 要求实施时验证，不通则不预置（Task 7 验收项）
    ],
  ),
  ProviderPreset(
    id: 'volcengine',
    name: '火山豆包',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    keyUrl: 'https://console.volcengine.com/ark',
    protocol: 'volcengine',
    sourceUrl: 'https://www.volcengine.com/docs/82379',
    verifiedAt: '2026-07-18', // 以仓库 engine.dart 既有种子为真值（非 WebFetch 核实，见计划"已核实的代码事实"）
    models: [
      const PresetModel('doubao-seed-1-6-250615', 'text'),
      const PresetModel('doubao-seedream-4-0-250828', 'image'),
      PresetModel('doubao-seedance-2-0-mini-260615', 'video',
          capabilities: seedanceMiniCapabilities()),
    ],
  ),
  const ProviderPreset(
    id: 'azt',
    name: 'azt (本地 Codex OAuth)',
    baseUrl: 'http://127.0.0.1:8787/v1',
    keyUrl: 'http://127.0.0.1:8787',
    desktopOnly: true,
    acceptanceVerified: true, // 证据：本会话早前真实 e2e/smoke，非 Task 7 新验证——文本/图片服务冒烟见 .superpowers/sdd/progress.md「P0 Task 4」与 docs/parity/p0-provider-preflight.md「## azt 服务冒烟」（gpt-5.5 文本2.2s、gpt-image-2 1024x1024 图片26.7s，摘录 /tmp/p0-azt-smoke.txt）；gpt-5.6-luna 真实文本生成见 progress.md「QA真实全链路修复(storyboard boolean parser)」「QA全链路最终结果」全链路验证；Task 7 仅将此既有证据转录为正式验收记录
    sourceUrl: 'http://127.0.0.1:8787/v1/models',
    verifiedAt: '2026-07-18', // 以仓库 engine.dart 既有种子为真值（本地 loopback 代理，非公网可核实来源）
    models: [
      PresetModel('gpt-5.5', 'text'),
      PresetModel('gpt-5.4', 'text'),
      PresetModel('gpt-5.4-mini', 'text'),
      PresetModel('gpt-image-2', 'image'),
    ],
  ),
];
