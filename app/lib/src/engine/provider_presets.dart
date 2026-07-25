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
  final String protocol; // openai_compatible | anthropic | volcengine
  final bool compatMode;
  final bool desktopOnly;
  final bool acceptanceVerified; // 仅当 Task 7 验收表有证据行才可 true
  final String sourceUrl;
  final String verifiedAt; // YYYY-MM-DD
  /// 不含密钥的供应商专属默认字段。固定协议只声明实际需要的字段，
  /// 引擎会和通用 name/protocol/baseUrl 一起持久化。
  final Map<String, String> inputDefaults;
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
    this.inputDefaults = const {},
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
    protocol: 'anthropic',
    sourceUrl: 'https://platform.claude.com/docs/en/about-claude/models/overview',
    verifiedAt:
        '2026-07-25', // WebFetch models/overview 核实：Claude API ID 列逐行照抄。补入此前缺失的当前旗舰 claude-opus-5 与最强档 claude-fable-5；legacy 折叠区的 opus-4-7/4-6、sonnet-4-6 一并补入（仍在架）。claude-mythos-5 为邀请制不自助开通，不预置；claude-opus-4-1 已标 deprecated（2026-08-05 退役），不预置
    models: [
      PresetModel('claude-opus-5', 'text'),
      PresetModel('claude-sonnet-5', 'text'),
      PresetModel('claude-fable-5', 'text'),
      PresetModel('claude-haiku-4-5', 'text'),
      PresetModel('claude-opus-4-8', 'text'),
      PresetModel('claude-opus-4-7', 'text'),
      PresetModel('claude-opus-4-6', 'text'),
      PresetModel('claude-sonnet-4-6', 'text'),
    ],
  ),
  const ProviderPreset(
    id: 'gemini',
    name: 'Gemini (Google)',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    keyUrl: 'https://aistudio.google.com/apikey',
    compatMode: true,
    sourceUrl: 'https://ai.google.dev/gemini-api/docs/models',
    verifiedAt:
        '2026-07-25', // WebFetch 官方 models 页核实并扩充文本档。生图档（gemini-3.1-flash-image / gemini-3-pro-image / gemini-2.5-flash-image）走 generateContent 而非 OpenAI /images/generations，兼容层能否直出图未验证——按 spec §4「不通则不预置」暂不入列；veo-3.x 视频档本引擎无对应协议，同样不预置
    models: [
      PresetModel('gemini-3.6-flash', 'text'),
      PresetModel('gemini-3.5-flash', 'text'),
      PresetModel('gemini-3.5-flash-lite', 'text'),
      PresetModel('gemini-3.1-pro-preview', 'text'),
      PresetModel('gemini-3.1-flash-lite', 'text'),
      PresetModel('gemini-3-flash-preview', 'text'),
      PresetModel('gemini-2.5-pro', 'text'),
      PresetModel('gemini-2.5-flash', 'text'),
      PresetModel('gemini-2.5-flash-lite', 'text'),
    ],
  ),
  const ProviderPreset(
    id: 'xai',
    name: 'Grok (xAI)',
    baseUrl: 'https://api.x.ai/v1',
    keyUrl: 'https://console.x.ai',
    compatMode: true,
    sourceUrl: 'https://docs.x.ai/docs/models',
    verifiedAt:
        '2026-07-25', // WebFetch docs.x.ai/docs/models 重新核实：官方目录已不止 grok-4.5，文本档六项照抄；生图档走 /v1/images/generations（OpenAI 同构）故一并预置；grok-imagine-video 视频档本引擎无对应协议，不预置
    models: [
      PresetModel('grok-4.5', 'text'),
      PresetModel('grok-4.3', 'text'),
      PresetModel('grok-4.20-0309-reasoning', 'text'),
      PresetModel('grok-4.20-0309-non-reasoning', 'text'),
      PresetModel('grok-4.20-multi-agent-0309', 'text'),
      PresetModel('grok-build-0.1', 'text'),
      PresetModel('grok-imagine-image', 'image'),
      PresetModel('grok-imagine-image-quality', 'image'),
    ],
  ),
  const ProviderPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    keyUrl: 'https://openrouter.ai/settings/keys',
    sourceUrl: 'https://openrouter.ai/models',
    verifiedAt:
        '2026-07-25', // 页面为 JS 渲染 WebFetch 抓不到列表，仍走公开 GET /api/v1/models 真实调用核实并按家族扩充。上一版预置的 openai/gpt-5.1 与 google/gemini-3.1-pro-preview 本次已不在返回里，剔除；带 ~ 前缀的 latest 别名（~anthropic/claude-fable-latest 等）非稳定 id，不预置
    models: [
      PresetModel('anthropic/claude-opus-5', 'text'),
      PresetModel('anthropic/claude-sonnet-5', 'text'),
      PresetModel('anthropic/claude-fable-5', 'text'),
      PresetModel('anthropic/claude-opus-4.8', 'text'),
      PresetModel('openai/gpt-5.6-sol', 'text'),
      PresetModel('openai/gpt-5.6-terra', 'text'),
      PresetModel('openai/gpt-5.6-luna', 'text'),
      PresetModel('google/gemini-3.6-flash', 'text'),
      PresetModel('google/gemini-3.5-flash', 'text'),
      PresetModel('x-ai/grok-4.5', 'text'),
      PresetModel('moonshotai/kimi-k3', 'text'),
      PresetModel('z-ai/glm-5.2', 'text'),
      PresetModel('qwen/qwen3.7-max', 'text'),
      PresetModel('minimax/minimax-m3', 'text'),
    ],
  ),
  const ProviderPreset(
    id: 'siliconflow',
    name: '硅基流动 SiliconFlow',
    baseUrl: 'https://api.siliconflow.cn/v1',
    keyUrl: 'https://cloud.siliconflow.cn/account/ak',
    sourceUrl:
        'https://docs.siliconflow.cn/cn/api-reference/models/get-model-list',
    verifiedAt:
        '2026-07-18', // API 文档页无具体型号示例，改用各模型详情页核实：DeepSeek-V3.2、Kwai-Kolors/Kolors 原样确认；Qwen3-Max 在硅基流动不存在（该家只托管开源权重，Max 是阿里云自有闭源档，仅 dashscope 有），改用其开源旗舰 Qwen/Qwen3.5-397B-A17B
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
    verifiedAt:
        '2026-07-25', // 重新 WebFetch 官方定价页核实：deepseek-v4-flash / deepseek-v4-pro 仍为仅有的两个在架型号（各 1M 上下文，v4-pro 为强推理档）；deepseek-chat / deepseek-reasoner 的 2026-07-24 停用日已过，确认下线，不预置
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
    sourceUrl: 'https://platform.kimi.com/docs/api/chat',
    verifiedAt:
        '2026-07-25', // WebFetch platform.moonshot.cn/docs/api/chat（301 跳新域名 platform.kimi.com）核实 chat 接口现役目录并照抄扩充；kimi-latest（2026-01-28 停用）、kimi-k2 系列（2026-05-25 停用）确认已下线，不预置
    models: [
      PresetModel('kimi-k3', 'text'),
      PresetModel('kimi-k2.7-code', 'text'),
      PresetModel('kimi-k2.7-code-highspeed', 'text'),
      PresetModel('kimi-k2.6', 'text'),
      PresetModel('kimi-k2.5', 'text'),
      PresetModel('moonshot-v1-auto', 'text'),
      PresetModel('moonshot-v1-8k', 'text'),
      PresetModel('moonshot-v1-32k', 'text'),
      PresetModel('moonshot-v1-128k', 'text'),
    ],
  ),
  const ProviderPreset(
    id: 'zhipu',
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    keyUrl: 'https://open.bigmodel.cn/usercenter/apikeys',
    sourceUrl: 'https://docs.bigmodel.cn/cn/guide/start/model-overview',
    verifiedAt:
        '2026-07-25', // WebFetch 官方 model-overview 核实并照抄扩充文本/视觉/生图三档。cogvideox-3、vidu-q1/vidu-2、cogvideox-flash 视频档本引擎无对应协议，不预置；glm-tts / glm-tts-clone 是否走 OpenAI /audio/speech 未验证，按「不通则不预置」暂缓；embedding/rerank/asr 非本应用用途
    models: [
      PresetModel('glm-5.2', 'text'),
      PresetModel('glm-5.1', 'text'),
      PresetModel('glm-5', 'text'),
      PresetModel('glm-5-turbo', 'text'),
      PresetModel('glm-4.7', 'text'),
      PresetModel('glm-4.7-flash', 'text'),
      PresetModel('glm-4.7-flashx', 'text'),
      PresetModel('glm-4.6', 'text'),
      PresetModel('glm-4.5-air', 'text'),
      PresetModel('glm-4.5-airx', 'text'),
      PresetModel('glm-4.5-flash', 'text'),
      PresetModel('glm-4-long', 'text'),
      PresetModel('glm-5v-turbo', 'text'),
      PresetModel('glm-4.6v', 'text'),
      PresetModel('glm-4.6v-flash', 'text'),
      PresetModel('glm-image', 'image'),
      PresetModel('cogview-4', 'image'),
      PresetModel('cogview-3-flash', 'image'),
    ],
  ),
  const ProviderPreset(
    id: 'dashscope',
    name: '通义 Qwen',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    keyUrl: 'https://bailian.console.aliyun.com/?apiKey=1',
    sourceUrl: 'https://www.alibabacloud.com/help/en/model-studio/models',
    verifiedAt:
        '2026-07-25', // help.aliyun.com 仍被 WebFetch 域名策略拦截，继续用 alibabacloud.com 镜像页核实并扩充。该页明确写出：生图档（wan2.7-image-pro、qwen-image-2.0-pro）与视频档走独立端点、不在 OpenAI 兼容接口内 —— 与既有「不通则不预置」结论一致，故本次仍只预置文本档
    models: [
      PresetModel('qwen3.7-max', 'text'),
      PresetModel('qwen3.7-plus', 'text'),
      PresetModel('qwen3.6-flash', 'text'),
      PresetModel('qwen3.5-omni-plus', 'text'),
      PresetModel('qwen-plus', 'text'),
    ],
  ),
  ProviderPreset(
    id: 'volcengine',
    name: '火山豆包',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    keyUrl: 'https://console.volcengine.com/ark',
    protocol: 'volcengine',
    sourceUrl: 'https://www.volcengine.com/docs/82379',
    verifiedAt:
        '2026-07-18', // 以仓库 engine.dart 既有种子为真值（非 WebFetch 核实，见计划"已核实的代码事实"）
    models: [
      const PresetModel('doubao-seed-1-6-250615', 'text'),
      const PresetModel('doubao-seedream-4-0-250828', 'image'),
      PresetModel('doubao-seedance-2-0-mini-260615', 'video',
          capabilities: seedanceMiniCapabilities()),
    ],
  ),
  const ProviderPreset(
    id: 'ima2',
    name: 'ima2 / Codex OAuth',
    baseUrl: 'http://127.0.0.1:10531/v1',
    keyUrl: 'https://github.com/lidge-jun/ima2-gen',
    protocol: 'ima2',
    sourceUrl: 'https://github.com/lidge-jun/ima2-gen',
    verifiedAt: '2026-07-19',
    inputDefaults: {
      'chatBaseUrl': 'http://127.0.0.1:10531/v1',
      'imageBaseUrl': 'http://127.0.0.1:3333',
      'imageQuality': 'low',
      'imageSize': '1024x1024',
      'imageTimeoutMs': '960000',
    },
    models: [
      PresetModel('gpt-5.5', 'text', label: 'GPT-5.5 (Codex OAuth)'),
      PresetModel('gpt-5.4', 'text', label: 'GPT-5.4 (Codex OAuth)'),
      PresetModel('gpt-5.4-mini', 'text', label: 'GPT-5.4 Mini (Codex OAuth)'),
      PresetModel('gpt-image-2-gpt-5.5', 'image',
          label: 'GPT Image 2 / GPT-5.5'),
      PresetModel('gpt-image-2-gpt-5.4', 'image',
          label: 'GPT Image 2 / GPT-5.4'),
      PresetModel('gpt-image-2-gpt-5.4-mini', 'image',
          label: 'GPT Image 2 / GPT-5.4 Mini'),
    ],
  ),
  const ProviderPreset(
    id: 'azt',
    name: 'azt (本地 Codex OAuth)',
    baseUrl: 'http://127.0.0.1:8787/v1',
    keyUrl: 'http://127.0.0.1:8787',
    desktopOnly: true,
    acceptanceVerified:
        true, // 证据：本会话早前真实 e2e/smoke，非 Task 7 新验证——文本/图片服务冒烟见 .superpowers/sdd/progress.md「P0 Task 4」与 docs/parity/p0-provider-preflight.md「## azt 服务冒烟」（gpt-5.5 文本2.2s、gpt-image-2 1024x1024 图片26.7s，摘录 /tmp/p0-azt-smoke.txt）；gpt-5.6-luna 真实文本生成见 progress.md「QA真实全链路修复(storyboard boolean parser)」「QA全链路最终结果」全链路验证；Task 7 仅将此既有证据转录为正式验收记录
    sourceUrl: 'http://127.0.0.1:8787/v1/models',
    verifiedAt: '2026-07-19', // 本机 GET /v1/models 核实文本目录；图片另有独立冒烟证据
    models: [
      PresetModel('gpt-5.6-sol', 'text'),
      PresetModel('gpt-5.6-terra', 'text'),
      PresetModel('gpt-5.6-luna', 'text'),
      PresetModel('gpt-5.5', 'text'),
      PresetModel('gpt-5.3-codex-spark', 'text'),
      PresetModel('gpt-image-2', 'image'),
    ],
  ),
];
