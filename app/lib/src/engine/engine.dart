import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

import '../api/models.dart';
import 'assets.dart';
import 'audio_bind.dart' show AudioBindApi;
import 'compose.dart';
import 'credentials.dart';
import 'storyboard.dart' show StoryboardApi;
import 'config.dart';
import 'db.dart';
import 'errors.dart';
import 'events.dart';
import 'media.dart';
import 'providers/gateway.dart';
import 'providers/resolve.dart';
import 'prompts.dart' as prompt_defaults;
import 'queue.dart';
import 'scripts.dart';
import 'video_track.dart' show VideoTrackApi;

class ProjectRow {
  final int id;
  final String? artStyle;
  final int? createTime;
  final String? directorManual;
  final String? imageModel;
  final String? imageQuality;
  final String? intro;
  final String? mode;
  final String? name;
  final String? projectType;
  final String? type;
  final int? userId;
  final String? videoModel;
  final String? videoRatio;

  const ProjectRow({
    required this.id,
    required this.artStyle,
    required this.createTime,
    required this.directorManual,
    required this.imageModel,
    required this.imageQuality,
    required this.intro,
    required this.mode,
    required this.name,
    required this.projectType,
    required this.type,
    required this.userId,
    required this.videoModel,
    required this.videoRatio,
  });

  factory ProjectRow.fromRow(Row row) => ProjectRow(
        id: row['id'] as int,
        artStyle: row['artStyle'] as String?,
        createTime: row['createTime'] as int?,
        directorManual: row['directorManual'] as String?,
        imageModel: row['imageModel'] as String?,
        imageQuality: row['imageQuality'] as String?,
        intro: row['intro'] as String?,
        mode: row['mode'] as String?,
        name: row['name'] as String?,
        projectType: row['projectType'] as String?,
        type: row['type'] as String?,
        userId: row['userId'] as int?,
        videoModel: row['videoModel'] as String?,
        videoRatio: row['videoRatio'] as String?,
      );
}

class ProjectStats {
  final int chapters;
  final int scripts;
  final int assets;
  final int storyboards;

  const ProjectStats({
    this.chapters = 0,
    this.scripts = 0,
    this.assets = 0,
    this.storyboards = 0,
  });
}

class Engine {
  static const version = '0.3.0-task3';
  static const _promptKeyEventExtraction = 'eventExtraction';
  static const _promptKeyScriptGen = 'scriptGen';
  static const _promptKeyScriptAssetExtraction = 'scriptAssetExtraction';
  static const _promptKeyImageSizeDirective = 'image_size_directive';

  static const _toonFlowEventExtractionPrompt = r'''# 事件提取指令

你是小说文本分析助手。用户每次提供一个章节的原文，你提取该章的结构化事件信息。

## ⚠️ 输出约束（最高优先级，违反任何一条即为失败）

1. 你的**完整回复**只有一行，以 `|` 开头、以 `|` 结尾，恰好 7 个字段
2. 回复的**第一个字符**必须是 `|`，**最后一个字符**必须是 `|`
3. `|` 之前不许有任何字符——没有引导语、没有解释、没有"根据……"、没有"以下是……"
4. `|` 之后不许有任何字符——没有总结、没有提取说明、没有改编建议
5. 不输出表头行、分隔线、Markdown 标题、emoji、代码块标记

## 输出格式

```
| 第X章 {章节标题} | {涉及角色} | {核心事件} | {主线关系} | {信息密度} | {预估集长} | {情绪强度} |
```

### 字段规范

| 字段 | 格式要求 | 示例 |
|------|----------|------|
| 章节 | `第X章 {章节标题}` | `第1章 职业危机与许愿` |
| 涉及角色 | 有实际戏份的角色，顿号分隔 | `林逸、白有容` |
| 核心事件 | 30-60字，必须含动作+结果 | `林逸因解密风潮事业崩塌，颓废中许愿触发魔法系统绑定` |
| 主线关系 | **必须**为 `强/中/弱（3-8字理由）` | `强（动机建立+系统激活）` |
| 信息密度 | `高` / `中` / `低` | `高` |
| 预估集长 | **必须**为 `X秒`，禁止用分钟 | `50秒` |
| 情绪强度 | 文字标签，`+` 连接，禁止星级/数字 | `转折+悬疑` |

**主线关系判定**：强＝直接推动主角弧线；中＝补充世界观/人物关系/伏笔；弱＝过渡/气氛。

**预估集长参考**：高密度+高情绪→45-60秒；中→35-45秒；低→25-35秒。

**可用情绪标签**：`冲突`、`恐怖`、`情感`、`转折`、`高潮`、`平铺`、`喜剧`、`悬疑`、`情感崩溃`。

## 输出示例

以下两个示例展示的是**完整回复**——除这一行外没有任何其他内容：

```
| 第1章 职业危机与许愿 | 林逸 | 职业魔术师林逸因解密打假风潮导致事业崩塌，颓废中感慨"如果会魔法就好了"，意外触发神奇魔法系统绑定 | 强（主角动机建立+系统激活） | 高 | 50秒 | 转折+悬疑 |
```
```
| 第12章 山间小憩 | 凌玄、苏晚卿 | 凌玄与苏晚卿在山间歇脚，苏晚卿回忆幼时往事，两人关系略有缓和但未实质推进 | 弱（气氛过渡） | 低 | 25秒 | 平铺+情感 |
```

## 提取规则

- 忠于原文，不推测、不脑补、不加入原文未出现的情节
- 角色使用文中主要称呼，保持一致
- 多条平行事件线时，选对主角影响最大的一条，其余简要带过
- 对话密集章节，关注对话推动了什么结果，而非复述对话内容''';

  static const _toonFlowScriptAssetExtractionPrompt = r'''---
name: universal_agent
description: 专注于从剧本内容中提取所使用的资产（角色、场景、道具）并生成结构化资产列表的助手。
---

# Script Assets Extract

你是一个专业的剧本内容分析助手，专注于从剧本文本中识别和提取所有涉及的资产（角色、场景、道具），并为每项资产生成可供下游制作流程使用的结构化描述和提示词。

## 何时使用

用户提供剧本内容，你需要逐段阅读并提取其中涉及的所有资产（人物角色、场景地点、道具物件），输出为结构化的资产列表。产出的资产描述将用于后续 AI 图片生成和制作流程。

## 与系统的对应关系

- 资产类型：
  - `role` — 角色（对应 `o_assets.type = "role"`）
  - `scene` — 场景（对应 `o_assets.type = "scene"`）
  - `tool` — 道具（对应 `o_assets.type = "tool"`）
- 下游用途：资产提示词生成 → AI 资产图生成 → 分镜制作

## 输出要求

**必须通过调用 `resultTool` 工具返回结果**，禁止以纯文本、Markdown 表格或 JSON 代码块等形式直接输出资产列表。
`resultTool` 的 schema 会对字段类型和枚举值做强校验，调用时请严格按照下方字段定义填写，确保数据结构正确、字段完整、类型匹配。

每个资产对象包含以下字段：

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| `name` | string | 是 | 资产名称，使用剧本中的原始称呼,不做其他多余描述 |
| `desc` | string | 是 | 资产描述，30-80 字的视觉化描述 |
| `prompt` | string | 是 | 生成提示词，英文，用于 AI 图片生成 |
| `type` | enum | 是 | 资产类型：`role` / `scene` / `tool`  |

## 提取规则

### 角色（role）

- 提取剧本中出现的所有有名字的角色
- `desc`：包含性别、外貌特征、服饰风格、体态气质等视觉要素，需在描述开头明确标注角色性别（如"男性，……"或"女性，……"）
- `prompt`：英文提示词，描述角色的外观特征，需以性别词开头（如 `a young man, ...` 或 `a young woman, ...`），适用于 AI 角色图生成
- 同一角色有多个称呼时，取最常用的作为 `name`
- 无名龙套（如"路人甲"、"士兵"）可跳过，除非其造型对剧情有重要视觉意义

### 场景（scene）

- 提取剧本中出现的所有场景/地点
- `desc`：包含空间结构、光照氛围、关键陈设、色调基调等视觉要素
- `prompt`：英文提示词，描述场景的整体视觉风格，适用于 AI 场景图生成
- 同一场景的不同状态（如白天/夜晚）不重复提取，在 `desc` 中注明即可

### 道具（tool）

- 提取剧本中出现的重要道具/物品
- `desc`：包含外观形状、颜色材质、尺寸参考、特殊效果等视觉要素
- `prompt`：英文提示词，描述道具的外观细节，适用于 AI 道具图生成
- 仅提取有独立视觉意义或剧情功能的道具，通用物品可跳过


## 提示词（prompt）生成规范

- 采用逗号分隔的关键词/短语格式
- 优先描述**视觉特征**，避免抽象概念
- 包含风格关键词（如 anime style, manga style 等，根据项目风格决定）
- 角色 prompt 示例：`a young man, sharp eyebrows, black hair, pale skin, wearing a gray Taoist robe, slender build, cold expression`
- 场景 prompt 示例：`dark cave interior, glowing crystals on walls, misty atmosphere, dim blue lighting, stone altar in center`
- 道具 prompt 示例：`ancient jade pendant, oval shape, translucent green, carved dragon pattern, glowing faintly`

## 提取流程

1. 通读剧本全文，识别所有出现的角色、场景、道具
2. 对每个资产生成结构化的 `name`、`desc`、`prompt`、`type`
3. 去重：同一资产不重复提取
4. **必须通过调用 `resultTool` 工具输出完整资产列表**，不要分多次调用：本次新识别的资产放入 `newAssets` 数组，若某资产此前剧本已提取过、本集只是复用，则把它的名称放入 `existingAssetRefs` 数组，一次性提交

## 提取原则

1. **忠于剧本**：所有提取基于剧本中的实际内容，不臆造未出现的资产
2. **视觉优先**：描述和提示词聚焦视觉特征，便于 AI 图片生成
3. **精简实用**：只提取对制作有实际意义的资产，避免过度提取
4. **分类准确**：严格按照 role/scene/tool 分类，不混淆
5. **提示词质量**：英文提示词应具体、可执行，能直接用于 AI 图片生成

## 注意事项

- 资产列表中**不要包含剧本内容本身**，仅提取所使用到的资产
- 角色的随身物品如果有独立剧情功能，应单独作为道具提取
- 场景中的固定陈设不需要单独提取为道具，除非该物件有独立剧情作用''';

  final Database db;
  final MediaStore media;
  final ProviderGateway gateway;
  final EngineConfig config;
  final CredentialStore credentials;
  final VideoComposer composer;
  late final JobQueue queue;

  /// 章节导入完成后的钩子（T6 注入事件自动生成，对应 ToonFlow addNovel 触发 CleanNovel）。
  void Function(int projectId, List<int> novelIds)? onNovelsAdded;

  Engine({
    required this.db,
    required this.media,
    required this.gateway,
    required this.config,
    CredentialStore? credentials,
    VideoComposer? composer,
    Duration queueTick = const Duration(milliseconds: 500),
    TaskRunner? taskRunner,
  })  : credentials = credentials ?? InMemoryCredentialStore(),
        composer = composer ?? const UnsupportedComposer() {
    queue = JobQueue(
      db,
      run: taskRunner ?? _dispatchTask,
      tick: queueTick,
    );
  }

  /// taskClass → 执行器注册表（各业务模块 install 时挂载）。
  final Map<String, TaskRunner> taskRunners = {};

  Future<void> _dispatchTask(TasksRow task, CancelToken token) {
    final runner = taskRunners[task.taskClass];
    if (runner == null) {
      throw EngineException(errTaskUnsupported, {'taskClass': task.taskClass});
    }
    return runner(task, token);
  }

  static Future<Engine> boot({
    required String dataDir,
    required bool isMobile,
    VideoComposer? composer,
    CredentialStore? credentialStore,
  }) async {
    Directory(dataDir).createSync(recursive: true);
    final db = openEngineDb(path.join(dataDir, 'dramaflow.sqlite'));
    final config = EngineConfig(db, isMobile: isMobile);
    _seedDefaults(db, config, isMobile: isMobile);
    _seedBundledModelPromptRows(db, dataDir);
    final credentials = credentialStore ?? SecureCredentialStore();
    await _migrateLegacyProviderCredentials(db, credentials);
    final media = MediaStore(path.join(dataDir, 'media'));
    final engine = Engine(
      db: db,
      media: media,
      gateway: HttpProviderGateway(db, config, media, credentials: credentials),
      config: config,
      credentials: credentials,
      composer: composer,
    );
    engine.installNovelEventPipeline();
    engine.installScriptPipeline();
    engine.installAssetPipeline();
    engine.installStoryboardPipeline();
    engine.installVideoTrackPipeline();
    engine.installAudioBindPipeline();
    engine.queue.recoverOnColdStart();
    engine.queue.start();
    return engine;
  }

  static void _seedDefaults(
    Database db,
    EngineConfig config, {
    required bool isMobile,
  }) {
    if ((db.select('SELECT COUNT(*) n FROM o_vendorConfig').first['n']
            as int) ==
        0) {
      void provider({
        required String id,
        required String name,
        required String protocol,
        required String baseUrl,
        required List<Map<String, Object?>> models,
      }) {
        db.execute(
          'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
          [
            id,
            1,
            jsonEncode({
              'name': name,
              'protocol': protocol,
              'baseUrl': baseUrl,
              'credentialRef': providerCredentialRef(id),
              'createdAt': nowIso(),
            }),
            jsonEncode(models),
          ],
        );
      }

      Map<String, Object?> model(
              String providerId, String modelId, String label, String kind,
              [Map<String, Object?> capabilities = const {}]) =>
          {
            'id': '$providerId:$modelId',
            'providerId': providerId,
            'modelId': modelId,
            'label': label,
            'kind': kind,
            'capabilities': capabilities,
            'enabled': true,
          };

      if (!isMobile) {
        provider(
          id: 'azt',
          name: 'azt',
          protocol: 'openai_compatible',
          baseUrl: 'http://127.0.0.1:8787/v1',
          models: [
            for (final modelId in ['gpt-5.5', 'gpt-5.4', 'gpt-5.4-mini'])
              model('azt', modelId, modelId, 'text'),
            model('azt', 'gpt-image-2', 'gpt-image-2', 'image'),
          ],
        );
      }

      provider(
        id: 'volcengine',
        name: 'volcengine',
        protocol: 'volcengine',
        baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
        models: [
          model('volcengine', 'doubao-seed-1-6-250615',
              'doubao-seed-1-6-250615', 'text'),
          model('volcengine', 'doubao-seedream-4-0-250828',
              'doubao-seedream-4-0-250828', 'image'),
          model(
            'volcengine',
            'doubao-seedance-2-0-mini-260615',
            'doubao-seedance-2-0-mini-260615',
            'video',
            {
              'durations': [for (var i = 4; i <= 15; i++) i],
              'resolutions': ['480p', '720p'],
            },
          ),
        ],
      );
    }

    void binding(String stage, String value) {
      final key = 'binding.$stage';
      final rows = db.select('SELECT value FROM o_setting WHERE key=?', [key]);
      if (rows.isEmpty ||
          ((rows.first['value'] as String?) ?? '').trim().isEmpty) {
        db.execute(
          'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
          [key, value],
        );
      }
    }

    if (isMobile) {
      binding('script_gen', 'volcengine:doubao-seed-1-6-250615');
      binding('event_extract', 'volcengine:doubao-seed-1-6-250615');
      binding('asset_extract', 'volcengine:doubao-seed-1-6-250615');
      binding('storyboard_gen', 'volcengine:doubao-seed-1-6-250615');
      binding('video_prompt_gen', 'volcengine:doubao-seed-1-6-250615');
      binding('asset_image', 'volcengine:doubao-seedream-4-0-250828');
      binding('shot_image', 'volcengine:doubao-seedream-4-0-250828');
      binding('shot_video', 'volcengine:doubao-seedance-2-0-mini-260615');
    } else {
      binding('script_gen', 'azt:gpt-5.5');
      binding('event_extract', 'azt:gpt-5.5');
      binding('asset_extract', 'azt:gpt-5.5');
      binding('storyboard_gen', 'azt:gpt-5.5');
      binding('video_prompt_gen', 'azt:gpt-5.5');
      binding('asset_image', 'azt:gpt-image-2');
      binding('shot_image', 'azt:gpt-image-2');
      binding('shot_video', 'volcengine:doubao-seedance-2-0-mini-260615');
    }

    void prompt({
      required String name,
      required String type,
      required String data,
    }) {
      final rows = db.select('SELECT id FROM o_prompt WHERE name=?', [name]);
      if (rows.isEmpty) {
        db.execute(
          'INSERT INTO o_prompt (name,type,data,useData) VALUES (?,?,?,?)',
          [name, type, data, null],
        );
      }
    }

    prompt(
      name: _promptKeyEventExtraction,
      type: _promptKeyEventExtraction,
      data: _toonFlowEventExtractionPrompt,
    );
    prompt(
      name: _promptKeyScriptGen,
      type: prompt_defaults.promptKeyScriptGenSystem,
      data: prompt_defaults.scriptGenSystem,
    );
    prompt(
      name: _promptKeyScriptAssetExtraction,
      type: _promptKeyScriptAssetExtraction,
      data: _toonFlowScriptAssetExtractionPrompt,
    );
    prompt(
      name: _promptKeyImageSizeDirective,
      type: 'system',
      data: config.str('imageSizeDirective'),
    );
    // 事件分析（ToonFlow 前端有入口但后端缺失，DramaFlow 补齐为可编辑提示词）
    prompt(
      name: 'eventAnalysis',
      type: 'eventAnalysis',
      data: '你是短剧改编分析助手。用户提供若干章节的事件摘要（管道分隔格式），'
          '请逐章分析其改编价值：主线推进、可视化难度、情绪曲线衔接、建议保留或合并。'
          '严格返回 JSON 数组，每元素形如 {"chapterIndex": 数字, "analysis": "分析文本"}，'
          '不要输出 JSON 以外的任何内容。',
    );
    // 分镜生成（照抄 ToonFlow batchAddStoryboardInfo 语义，DramaFlow 补齐为可编辑提示词）
    prompt(
      name: 'storyboard_gen',
      type: 'storyboard_gen',
      data: '你是短剧分镜师。根据剧本内容拆分镜头，每个镜头输出：画面提示词'
          '（prompt，用于 AI 生图，包含构图/景别/光线）、运镜与画面描述'
          '（videoDesc）、预估时长秒数（duration）、所属分轨名称（track，如"主线"）、'
          '涉及的资产名称（assetNames，取剧本中出现的角色/道具/场景原名）。'
          '必须通过调用 resultTool 工具返回结果，禁止输出任何其他文字。',
    );
    prompt(
      name: 'asset_prompt_polish',
      type: 'asset_prompt_polish',
      data: '',
    );
    // 视频提示词生成（照抄 ToonFlow generateVideoPrompt 语义，DramaFlow 补齐为可编辑提示词）
    prompt(
      name: 'video_prompt_gen',
      type: 'video_prompt_gen',
      data: '你是短剧运镜师。根据分镜的画面描述与运镜说明，输出一段适合图生视频'
          '模型的英文动态提示词，需包含镜头运动方式（pan/zoom/dolly/static 等）、'
          '主体动作、节奏与时长感受。只输出提示词本身，不要输出任何解释或标点符号'
          '以外的说明文字。',
    );
    // 角色配音绑定（照抄 ToonFlow cornerScape batchBindAudio 语义）
    prompt(
      name: 'audio_bind',
      type: 'audio_bind',
      data: '你是配音匹配助手。根据角色资产的名称与描述，从候选音频列表中'
          '选出音色气质最匹配的一条。必须通过调用 resultTool 工具返回结果'
          '（每个角色对应一个音频 id），禁止输出任何其他文字。',
    );
  }

  static void _seedBundledModelPromptRows(Database db, String dataDir) {
    const vendorId = 'volcengine';
    const modelId = 'doubao-seedance-2-0-mini-260615';
    const modelPromptPath = 'video/seedance2Multi-parameterMode.md';
    const fileName = 'seedance2Multi-parameterMode.md';
    final source = File(path.join(dataDir, 'model_prompts', modelPromptPath));
    if (!source.existsSync()) return;

    final existing = db.select(
      'SELECT id FROM o_modelPrompt WHERE vendorId=? AND model=? AND path=?',
      [vendorId, modelId, modelPromptPath],
    );
    if (existing.isNotEmpty) return;

    final prompt = source.readAsStringSync();
    if (prompt.trim().isEmpty) return;
    db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      [vendorId, modelId, fileName, modelPromptPath, prompt],
    );
  }

  static Future<void> _migrateLegacyProviderCredentials(
    Database db,
    CredentialStore credentials,
  ) async {
    for (final row in db.select('SELECT id,inputValues FROM o_vendorConfig')) {
      final providerId = row['id'] as String;
      final raw = row['inputValues'] as String? ?? '{}';
      final decoded = jsonDecode(raw);
      final input = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final legacyApiKey = (input.remove('apiKey') ?? '').toString().trim();
      final credentialRef =
          (input['credentialRef'] ?? providerCredentialRef(providerId))
              .toString();
      input['credentialRef'] = credentialRef;
      if (legacyApiKey.isNotEmpty) {
        await credentials.write(credentialRef, legacyApiKey);
      }
      if (providerId == 'azt' &&
          legacyApiKey.isEmpty &&
          (await credentials.read(credentialRef)) == null) {
        await credentials.write(credentialRef, 'local');
      }
      if (legacyApiKey.isNotEmpty || raw != jsonEncode(input)) {
        db.execute(
          'UPDATE o_vendorConfig SET inputValues=? WHERE id=?',
          [jsonEncode(input), providerId],
        );
      }
    }

    const legacySettings = {
      'textApiKey': 'azt',
      'imageApiKey': 'azt',
      'videoApiKey': 'volcengine',
    };
    for (final entry in legacySettings.entries) {
      final row = db.select(
        'SELECT value FROM o_setting WHERE key=?',
        [entry.key],
      ).firstOrNull;
      final legacyApiKey = (row?['value'] as String?)?.trim() ?? '';
      if (legacyApiKey.isEmpty) continue;
      final providerExists = db.select(
        'SELECT id FROM o_vendorConfig WHERE id=?',
        [entry.value],
      ).isNotEmpty;
      if (providerExists) {
        await credentials.write(
          providerCredentialRef(entry.value),
          legacyApiKey,
        );
      }
      db.execute('DELETE FROM o_setting WHERE key=?', [entry.key]);
    }
  }

  void dispose() {
    queue.dispose();
  }

  String mediaAbsPath(String rel) => media.absPath(rel);

  Future<Map<String, dynamic>> health() async => {
        'version': version,
        'providers': {
          for (final stage in ['text', 'image', 'video'])
            stage: _bindingSummary(stage),
        },
      };

  String _bindingSummary(String group) {
    final stage = switch (group) {
      'text' => 'script_gen',
      'image' => 'asset_image',
      'video' => 'shot_video',
      _ => group,
    };
    final rows = db
        .select('SELECT value FROM o_setting WHERE key=?', ['binding.$stage']);
    return rows.isEmpty ? '未配置' : rows.first['value'] as String;
  }

  List<ProjectRow> projects() => db
      .select(
          'SELECT * FROM o_project ORDER BY COALESCE(createTime,0) DESC, id DESC')
      .map(ProjectRow.fromRow)
      .toList();

  Map<int, ProjectStats> projectStats() {
    final values =
        <int, ({int chapters, int scripts, int assets, int storyboards})>{};
    void merge(String table, String field) {
      final rows = db.select(
        'SELECT projectId, COUNT(*) n FROM $table WHERE projectId IS NOT NULL GROUP BY projectId',
      );
      for (final row in rows) {
        final projectId = row['projectId'] as int;
        final count = row['n'] as int;
        final old = values[projectId] ??
            (chapters: 0, scripts: 0, assets: 0, storyboards: 0);
        values[projectId] = switch (field) {
          'chapters' => (
              chapters: count,
              scripts: old.scripts,
              assets: old.assets,
              storyboards: old.storyboards,
            ),
          'scripts' => (
              chapters: old.chapters,
              scripts: count,
              assets: old.assets,
              storyboards: old.storyboards,
            ),
          'assets' => (
              chapters: old.chapters,
              scripts: old.scripts,
              assets: count,
              storyboards: old.storyboards,
            ),
          _ => (
              chapters: old.chapters,
              scripts: old.scripts,
              assets: old.assets,
              storyboards: count,
            ),
        };
      }
    }

    merge('o_novel', 'chapters');
    merge('o_script', 'scripts');
    merge('o_assets', 'assets');
    merge('o_storyboard', 'storyboards');
    return {
      for (final entry in values.entries)
        entry.key: ProjectStats(
          chapters: entry.value.chapters,
          scripts: entry.value.scripts,
          assets: entry.value.assets,
          storyboards: entry.value.storyboards,
        ),
    };
  }

  int addProject({
    required String projectType,
    required String name,
    String? intro,
    String? type,
    String? artStyle,
    String? directorManual,
    String? videoRatio,
    String? imageModel,
    String? videoModel,
    String? imageQuality,
    String? mode,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const EngineException(errLlmFormat, {'reason': '项目名称不能为空'});
    }
    db.execute(
      '''
INSERT INTO o_project (
  projectType,name,intro,type,artStyle,directorManual,videoRatio,
  imageModel,videoModel,imageQuality,mode,createTime
) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
''',
      [
        projectType,
        trimmed,
        intro,
        type,
        artStyle,
        directorManual,
        videoRatio,
        imageModel,
        videoModel,
        imageQuality,
        mode,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    return db.lastInsertRowId;
  }

  void editProject(
    int id, {
    String? projectType,
    String? name,
    String? intro,
    String? type,
    String? artStyle,
    String? directorManual,
    String? videoRatio,
    String? imageModel,
    String? videoModel,
    String? imageQuality,
    String? mode,
  }) {
    _mustProject(id);
    db.execute(
      '''
UPDATE o_project SET
  projectType=COALESCE(?,projectType),
  name=COALESCE(?,name),
  intro=COALESCE(?,intro),
  type=COALESCE(?,type),
  artStyle=COALESCE(?,artStyle),
  directorManual=COALESCE(?,directorManual),
  videoRatio=COALESCE(?,videoRatio),
  imageModel=COALESCE(?,imageModel),
  videoModel=COALESCE(?,videoModel),
  imageQuality=COALESCE(?,imageQuality),
  mode=COALESCE(?,mode)
WHERE id=?
''',
      [
        projectType,
        name?.trim(),
        intro,
        type,
        artStyle,
        directorManual,
        videoRatio,
        imageModel,
        videoModel,
        imageQuality,
        mode,
        id,
      ],
    );
  }

  void deleteProject(int id) {
    _mustProject(id);
    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM o_agentWorkData WHERE projectId=?', [id]);
      db.execute('DELETE FROM o_novel WHERE projectId=?', [id]);
      db.execute(
        'DELETE FROM o_scriptAssets WHERE scriptId IN (SELECT id FROM o_script WHERE projectId=?)',
        [id],
      );
      db.execute('DELETE FROM o_script WHERE projectId=?', [id]);
      db.execute(
        'DELETE FROM o_assets2Storyboard WHERE storyboardId IN (SELECT id FROM o_storyboard WHERE projectId=?)',
        [id],
      );
      db.execute('DELETE FROM o_storyboard WHERE projectId=?', [id]);
      db.execute('UPDATE o_assets SET imageId=NULL WHERE projectId=?', [id]);
      db.execute(
        'DELETE FROM o_image WHERE assetsId IN (SELECT id FROM o_assets WHERE projectId=?)',
        [id],
      );
      db.execute('DELETE FROM o_assets WHERE projectId=?', [id]);
      db.execute('DELETE FROM o_tasks WHERE projectId=?', [id]);
      db.execute('DELETE FROM o_timelineClip WHERE projectId=?', [id]);
      db.execute('DELETE FROM o_videoTrack WHERE projectId=?', [id]);
      db.execute('DELETE FROM o_video WHERE projectId=?', [id]);
      db.execute('DELETE FROM memories WHERE isolationKey LIKE ?', ['$id:%']);
      db.execute(
        'DELETE FROM memories WHERE isolationKey IN (?,?) '
        'OR isolationKey LIKE ? OR isolationKey LIKE ?',
        [
          'scriptAgent:$id',
          'productionAgent:$id',
          'scriptAgent:$id:%',
          'productionAgent:$id:%',
        ],
      );
      db.execute('DELETE FROM o_project WHERE id=?', [id]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    media.deleteProject(id.toString());
    queue.notifyChanged();
  }

  ProjectRow _mustProject(int id) {
    final rows = db.select('SELECT * FROM o_project WHERE id=?', [id]);
    if (rows.isEmpty) {
      throw const EngineException(errLlmFormat, {'reason': '项目不存在'});
    }
    return ProjectRow.fromRow(rows.first);
  }

  Future<List<ProjectRow>> listProjects() async => projects();

  Future<ProjectRow> getProject(int id) async => _mustProject(id);

  Future<ProjectRow> createProject(String name, {String artStyle = ''}) async {
    final id = addProject(
      projectType: 'drama',
      name: name,
      artStyle: artStyle,
    );
    return _mustProject(id);
  }

  Future<void> removeProject(int id) async => deleteProject(id);

  Future<List<TasksRow>> activeJobs() async => db
      .select(
        "SELECT * FROM o_tasks WHERE state IN ('pending','processing') ORDER BY id DESC",
      )
      .map(TasksRow.fromRow)
      .toList();

  Future<List<TasksRow>> projectJobs(int projectId, {int limit = 50}) async =>
      db
          .select(
            'SELECT * FROM o_tasks WHERE projectId=? ORDER BY id DESC LIMIT ?',
            [projectId, limit],
          )
          .map(TasksRow.fromRow)
          .toList();

  Future<int> retryJob(int taskId) async {
    final rows = db.select('SELECT * FROM o_tasks WHERE id=?', [taskId]);
    if (rows.isEmpty) {
      throw const EngineException(errLlmFormat, {'reason': '任务不存在'});
    }
    final task = TasksRow.fromRow(rows.first);
    if (task.state != 'failed') {
      throw const EngineException(errLlmFormat, {'reason': '只有失败的任务可以重试'});
    }
    db.execute(
      "UPDATE o_tasks SET state='pending', reason=NULL, startTime=? WHERE id=?",
      [DateTime.now().millisecondsSinceEpoch, taskId],
    );
    queue.notifyChanged();
    return taskId;
  }

  Future<void> cancelJob(int taskId) async => queue.cancel(taskId);

  Future<AppSettings> getSettings() async =>
      AppSettings.fromJson(config.getAllMasked());

  Future<AppSettings> updateSettings(Map<String, dynamic> patch) async {
    config.update(patch);
    return getSettings();
  }

  Future<String> getThemeMode() async => config.str('themeMode');

  Future<void> setThemeMode(String themeMode) async {
    if (!{'light', 'dark', 'system'}.contains(themeMode)) {
      throw const EngineException(errLlmFormat, {'reason': '主题模式无效'});
    }
    config.update({'themeMode': themeMode});
  }

  Future<String> getAppLocale() async => config.str('app.locale');

  Future<void> setAppLocale(String locale) async {
    if (!{'', 'zh', 'en', 'ja'}.contains(locale)) {
      throw const EngineException(errLlmFormat, {'reason': '语言设置无效'});
    }
    config.update({'app.locale': locale});
  }

  Future<List<ProviderInfo>> listProviders() => Future.wait(
        db
            .select('SELECT * FROM o_vendorConfig ORDER BY id')
            .map(_providerInfo),
      );

  Future<ProviderInfo> _providerInfo(Row row) async {
    final input = _jsonMap(row['inputValues']);
    final providerId = row['id'] as String;
    final credentialRef =
        (input['credentialRef'] ?? providerCredentialRef(providerId))
            .toString();
    return ProviderInfo.fromJson({
      'id': providerId,
      'name': input['name'] ?? providerId,
      'protocol': input['protocol'] ?? 'openai_compatible',
      'baseUrl': input['baseUrl'] ?? '',
      'hasCredential':
          (await credentials.read(credentialRef))?.isNotEmpty == true,
      'enabled': row['enable'] ?? 1,
      'createdAt': input['createdAt'] ?? '',
    });
  }

  Future<ProviderInfo> createProvider({
    required String name,
    required String protocol,
    required String baseUrl,
    required String apiKey,
  }) async {
    final id = _providerId(name);
    final credentialRef = providerCredentialRef(id);
    if (apiKey.trim().isNotEmpty) {
      await credentials.write(credentialRef, apiKey.trim());
    }
    db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        id,
        1,
        jsonEncode({
          'name': name.trim(),
          'protocol': protocol,
          'baseUrl': baseUrl.trim(),
          'credentialRef': credentialRef,
          'createdAt': nowIso(),
        }),
        '[]',
      ],
    );
    return _providerInfo(
      db.select('SELECT * FROM o_vendorConfig WHERE id=?', [id]).first,
    );
  }

  Future<ProviderInfo> updateProvider(
    String id, {
    String? name,
    String? baseUrl,
    String? apiKey,
    bool? enabled,
  }) async {
    final row = _mustProvider(id);
    final input = _jsonMap(row['inputValues']);
    if (name != null) input['name'] = name.trim();
    if (baseUrl != null) input['baseUrl'] = baseUrl.trim();
    input['credentialRef'] ??= providerCredentialRef(id);
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      await credentials.write(input['credentialRef'] as String, apiKey.trim());
    }
    db.execute(
      'UPDATE o_vendorConfig SET enable=COALESCE(?,enable), inputValues=? WHERE id=?',
      [enabled == null ? null : (enabled ? 1 : 0), jsonEncode(input), id],
    );
    return _providerInfo(
      db.select('SELECT * FROM o_vendorConfig WHERE id=?', [id]).first,
    );
  }

  Future<void> deleteProvider(String id) async {
    final bindings = await getBindings();
    if (bindings.values.any((value) => value.startsWith('$id:'))) {
      throw const EngineException(errProviderMissing, {'reason': '供应商正在使用'});
    }
    final input = _jsonMap(_mustProvider(id)['inputValues']);
    final credentialRef =
        (input['credentialRef'] ?? providerCredentialRef(id)).toString();
    await credentials.delete(credentialRef);
    db.execute('DELETE FROM o_vendorConfig WHERE id=?', [id]);
  }

  Future<List<ProviderModelInfo>> listProviderModels(String providerId) async {
    final row = _mustProvider(providerId);
    return _models(row).map(ProviderModelInfo.fromJson).toList();
  }

  Future<void> saveProviderModels(
    String providerId,
    List<Map<String, dynamic>> models,
  ) async {
    _mustProvider(providerId);
    final normalized = [
      for (final model in models) _normalizeModel(providerId, model),
    ];
    db.execute(
      'UPDATE o_vendorConfig SET models=? WHERE id=?',
      [jsonEncode(normalized), providerId],
    );
  }

  Future<int> testProvider(String providerId, String modelId) async {
    final model = (await listProviderModels(providerId)).firstWhere(
      (item) => item.modelId == modelId,
      // 未找到时抛稳定 errKey 而非裸 StateError（否则绕过全局错误码约定，
      // UI 层无法本地化）。
      orElse: () => throw const EngineException(errModelMissing),
    );
    if (gateway is! HttpProviderGateway) {
      throw const EngineException(
          errProviderMissing, {'reason': '当前网关不支持连通测试'});
    }
    final http = gateway as HttpProviderGateway;
    final resolved = await resolveModelById(
      db,
      credentials,
      providerId,
      model.modelId,
    );
    // 分模态测试（照抄 ToonFlow textTest/imageTest/videoTest）：
    switch (model.kind) {
      case 'text':
        return http.testTextModel(resolved);
      case 'image':
        return http.testImageModel(resolved);
      case 'video':
        return http.testVideoModel(resolved);
      default:
        throw const EngineException(errModelMissing, {'reason': '该模态暂不支持连通测试'});
    }
  }

  void _writeSetting(String key, String value) {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      [key, value],
    );
  }

  Future<Map<String, String>> getBindings() async => {
        for (final row in db.select(
          "SELECT key,value FROM o_setting WHERE key LIKE 'binding.%'",
        ))
          (row['key'] as String).substring('binding.'.length):
              row['value'] as String,
      };

  Future<void> setBinding(
    String stage,
    String providerId,
    String modelId,
  ) async {
    final requiredKind = requiredKindForStage(stage);
    final models = await listProviderModels(providerId);
    ProviderModelInfo? model;
    for (final item in models) {
      if (item.modelId == modelId) {
        model = item;
        break;
      }
    }
    if (model == null) {
      throw const EngineException(errModelMissing, {'reason': '模型不存在'});
    }
    if (model.kind != requiredKind) {
      throw EngineException(errModelMissing, {
        'stage': stage,
        'requiredKind': requiredKind,
        'actualKind': model.kind,
      });
    }
    _writeSetting('binding.$stage', '$providerId:$modelId');
  }

  Future<List<Map<String, dynamic>>> listPrompts() async =>
      db.select('SELECT * FROM o_prompt ORDER BY id').map((row) {
        final useData = row['useData'];
        final isOverridden = useData is String && useData.isNotEmpty;
        return {
          'key': row['name'],
          'content': useData ?? row['data'] ?? '',
          'isOverridden': isOverridden,
          'updatedAt': '',
        };
      }).toList();

  Future<String> getPrompt(String type) async {
    final rows = db.select(
      'SELECT useData,data FROM o_prompt WHERE type=? LIMIT 1',
      [type],
    );
    if (rows.isEmpty) {
      throw EngineException(errPromptMissing, {'type': type});
    }
    final useData = rows.first['useData'];
    if (useData is String && useData.isNotEmpty) return useData;
    return rows.first['data'] as String? ?? '';
  }

  Future<String> getPromptForStageModel(String type, String modelStage) async {
    final binding = db.select('SELECT value FROM o_setting WHERE key=? LIMIT 1',
        ['binding.$modelStage']).firstOrNull?['value'] as String?;
    final parts = binding == null ? const <String>[] : binding.split(':');
    if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      final rows = db.select(
        '''
SELECT prompt FROM o_modelPrompt
WHERE vendorId=? AND model=? AND prompt IS NOT NULL AND trim(prompt)<>''
  AND (fileName=? OR path=? OR path LIKE ?)
ORDER BY
  CASE
    WHEN fileName=? THEN 0
    WHEN path=? THEN 1
    WHEN path LIKE ? THEN 2
    ELSE 3
  END,
  id DESC
LIMIT 1
''',
        [
          parts[0],
          parts[1],
          type,
          type,
          '%/$type%',
          type,
          type,
          '%/$type%',
        ],
      );
      if (rows.isNotEmpty) {
        final prompt = rows.first['prompt'] as String?;
        if (prompt != null && prompt.trim().isNotEmpty) return prompt;
      }
    }
    return getPrompt(type);
  }

  Future<List<Map<String, dynamic>>> listModelPrompts() async {
    final providerNames = <String, String>{};
    final modelLabels = <String, String>{};
    final modelKinds = <String, String>{};
    for (final row in db.select('SELECT * FROM o_vendorConfig ORDER BY id')) {
      final providerId = (row['id'] ?? '').toString();
      final input = _jsonMap(row['inputValues']);
      providerNames[providerId] = (input['name'] ?? providerId).toString();
      for (final model in _models(row)) {
        final modelId = (model['modelId'] ?? '').toString();
        if (modelId.isEmpty) continue;
        final key = '$providerId:$modelId';
        modelLabels[key] = (model['label'] ?? modelId).toString();
        modelKinds[key] = (model['kind'] ?? '').toString();
      }
    }
    return [
      for (final row in db.select(
        'SELECT id,vendorId,model,fileName,path,prompt FROM o_modelPrompt '
        'ORDER BY vendorId,model,fileName,path,id',
      ))
        {
          'id': row['id'],
          'vendorId': row['vendorId'],
          'providerName': providerNames[(row['vendorId'] ?? '').toString()] ??
              (row['vendorId'] ?? '').toString(),
          'model': row['model'],
          'modelLabel': modelLabels['${row['vendorId']}:${row['model']}'] ??
              (row['model'] ?? '').toString(),
          'modelKind': modelKinds['${row['vendorId']}:${row['model']}'] ?? '',
          'fileName': row['fileName'],
          'path': row['path'],
          'prompt': row['prompt'] ?? '',
        },
    ];
  }

  Future<void> updateModelPrompt(int id, String content) async {
    final rows = db.select('SELECT id FROM o_modelPrompt WHERE id=?', [id]);
    if (rows.isEmpty) {
      throw const EngineException(errPromptMissing, {'type': 'modelPrompt'});
    }
    db.execute('UPDATE o_modelPrompt SET prompt=? WHERE id=?', [content, id]);
  }

  Future<void> updatePrompt(String key, String content) async {
    final rows = db.select('SELECT id FROM o_prompt WHERE name=?', [key]);
    if (rows.isEmpty) {
      db.execute(
        'INSERT INTO o_prompt (name,type,data,useData) VALUES (?,?,?,?)',
        [key, _promptType(key), _defaultPromptData(key), content],
      );
    } else {
      db.execute('UPDATE o_prompt SET useData=? WHERE name=?', [content, key]);
    }
  }

  Future<void> resetPrompt(String key) async {
    db.execute('UPDATE o_prompt SET useData=NULL WHERE name=?', [key]);
  }

  Future<Map<String, dynamic>> exportConfig() async => {
        'configVersion': 3,
        'providers': [
          for (final provider in await listProviders())
            {
              'id': provider.id,
              'name': provider.name,
              'protocol': provider.protocol,
              'baseUrl': provider.baseUrl,
              'hasCredential': provider.hasCredential,
              'enabled': provider.enabled,
              'models': [
                for (final model in await listProviderModels(provider.id))
                  {
                    'id': model.id,
                    'modelId': model.modelId,
                    'label': model.label,
                    'kind': model.kind,
                    'capabilities': model.capabilities,
                    'enabled': model.enabled,
                  },
              ],
            },
        ],
        'bindings': await getBindings(),
        'prompts': await listPrompts(),
        'modelPrompts': [
          for (final row in db.select(
            'SELECT vendorId,model,fileName,path,prompt FROM o_modelPrompt '
            'ORDER BY id',
          ))
            {
              'vendorId': row['vendorId'],
              'model': row['model'],
              'fileName': row['fileName'],
              'path': row['path'],
              'prompt': row['prompt'],
            },
        ],
      };

  Future<void> importConfig(Map<String, dynamic> data) async {
    final foundVersion = data['configVersion'];
    if (foundVersion != 3) {
      throw EngineException(errConfigVersion, {'found': foundVersion});
    }
    final providers = data['providers'];
    if (providers is List) {
      for (final raw in providers.whereType<Map>()) {
        final id =
            (raw['id'] ?? _providerId('${raw['name'] ?? ''}')).toString();
        final inputValues = {
          'name': (raw['name'] ?? id).toString(),
          'protocol': (raw['protocol'] ?? 'openai_compatible').toString(),
          'baseUrl': (raw['baseUrl'] ?? '').toString(),
          'credentialRef': providerCredentialRef(id),
          'createdAt': nowIso(),
        };
        final apiKey = (raw['apiKey'] ?? '').toString().trim();
        if (apiKey.isNotEmpty) {
          await credentials.write(providerCredentialRef(id), apiKey);
        }
        final models = [
          for (final model
              in (raw['models'] as List? ?? const []).whereType<Map>())
            _normalizeModel(id, Map<String, dynamic>.from(model)),
        ];
        db.execute(
          '''
INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)
ON CONFLICT(id) DO UPDATE SET enable=excluded.enable,inputValues=excluded.inputValues,models=excluded.models
''',
          [
            id,
            _boolish(raw['enabled']) ? 1 : 0,
            jsonEncode(inputValues),
            jsonEncode(models),
          ],
        );
      }
    }
    final bindings = data['bindings'];
    if (bindings is Map) {
      for (final entry in bindings.entries) {
        _writeSetting('binding.${entry.key}', entry.value.toString());
      }
    }
    final prompts = data['prompts'];
    if (prompts is List) {
      for (final prompt in prompts.whereType<Map>()) {
        final key = (prompt['key'] ?? '').toString();
        if (key.isEmpty) continue;
        await updatePrompt(key, (prompt['content'] ?? '').toString());
      }
    }
    final modelPrompts = data['modelPrompts'];
    if (modelPrompts is List) {
      for (final raw in modelPrompts.whereType<Map>()) {
        final vendorId = (raw['vendorId'] ?? '').toString();
        final model = (raw['model'] ?? '').toString();
        final fileName = (raw['fileName'] ?? '').toString();
        final path = (raw['path'] ?? '').toString();
        final prompt = (raw['prompt'] ?? '').toString();
        if (vendorId.isEmpty || model.isEmpty || prompt.trim().isEmpty) {
          continue;
        }
        db.execute(
          'DELETE FROM o_modelPrompt '
          'WHERE vendorId=? AND model=? AND coalesce(fileName,?)=? '
          'AND coalesce(path,?)=?',
          [vendorId, model, '', fileName, '', path],
        );
        db.execute(
          'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
          'VALUES (?,?,?,?,?)',
          [vendorId, model, fileName, path, prompt],
        );
      }
    }
  }

  Row _mustProvider(String id) {
    final rows = db.select('SELECT * FROM o_vendorConfig WHERE id=?', [id]);
    if (rows.isEmpty) {
      throw const EngineException(errProviderMissing);
    }
    return rows.first;
  }

  List<Map<String, dynamic>> _models(Row row) {
    final decoded = _jsonList(row['models']);
    return [
      for (final item in decoded.whereType<Map>())
        Map<String, dynamic>.from(item),
    ];
  }

  Map<String, dynamic> _normalizeModel(
    String providerId,
    Map<String, dynamic> model,
  ) {
    final modelId = (model['modelId'] ?? '').toString().trim();
    if (modelId.isEmpty) {
      throw const EngineException(errModelMissing, {'reason': '模型 ID 不能为空'});
    }
    final kind = (model['kind'] ?? 'text').toString();
    if (!{'text', 'image', 'video', 'tts'}.contains(kind)) {
      throw const EngineException(errModelMissing, {'reason': '模型类型无效'});
    }
    return {
      'id': (model['id'] ?? '$providerId:$modelId').toString(),
      'providerId': providerId,
      'modelId': modelId,
      'label': (model['label'] ?? modelId).toString(),
      'kind': kind,
      'capabilities': model['capabilities'] is Map
          ? Map<String, dynamic>.from(model['capabilities'] as Map)
          : <String, dynamic>{},
      'enabled': _boolish(model['enabled']),
    };
  }

  String _promptType(String key) {
    if (key == _promptKeyImageSizeDirective) return 'system';
    if (key == _promptKeyScriptGen) {
      return prompt_defaults.promptKeyScriptGenSystem;
    }
    return key;
  }

  String _defaultPromptData(String key) {
    return switch (key) {
      _promptKeyEventExtraction => _toonFlowEventExtractionPrompt,
      _promptKeyScriptGen => prompt_defaults.scriptGenSystem,
      _promptKeyScriptAssetExtraction => _toonFlowScriptAssetExtractionPrompt,
      _promptKeyImageSizeDirective => config.str('imageSizeDirective'),
      _ => '',
    };
  }

  Map<String, dynamic> _jsonMap(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }

  List<dynamic> _jsonList(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is List) return decoded;
    }
    return const [];
  }

  bool _boolish(Object? value) =>
      value == null || value == true || value == 1 || value == '1';

  String _providerId(String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty
        ? 'provider-${DateTime.now().microsecondsSinceEpoch}'
        : slug;
  }
}
