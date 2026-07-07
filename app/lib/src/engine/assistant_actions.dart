// 助手动作注册表（v0.4 spec §4）：只做"名字→既有流水线方法"的映射与参数归一化，
// 自身零业务逻辑。每个动作声明 {costsMoney, destructive, taskClass}，供确认闸
// （pipeline_policy）与对话循环（assistant_chat）做统一判定。
// 描述文案面向 LLM（工具说明），与 UI l10n 无关，保持中文。
import 'audio_bind.dart';
import 'compose_episode.dart';
import 'engine.dart';
import 'events.dart';
import 'novel.dart';
import 'project_notes.dart';
import 'scripts.dart';
import 'storyboard.dart';
import 'video_track.dart';

class AssistantAction {
  final String name;
  final String description;
  final Map<String, dynamic> schema;
  final bool costsMoney;
  final bool destructive;

  /// 花钱动作对应的队列 taskClass（pipeline_policy.actionPolicyByTaskClass 的键）；
  /// 非队列动作为 null。
  final String? taskClass;

  const AssistantAction({
    required this.name,
    required this.description,
    required this.schema,
    this.costsMoney = false,
    this.destructive = false,
    this.taskClass,
  });
}

const _idArraySchema = <String, dynamic>{'type': 'array'};

List<AssistantAction> assistantActions() => const [
      AssistantAction(
        name: 'get_status',
        description: '查看项目当前进度（章节/事件/剧本/分镜/配音各阶段完成情况），不产生任何改动。',
        schema: {},
      ),
      AssistantAction(
        name: 'generate_events',
        description: '为章节生成事件摘要。不传 novelIds 时对全部尚未成功生成事件的章节执行。',
        schema: {'novelIds': _idArraySchema},
        costsMoney: true,
        taskClass: 'event_generation',
      ),
      AssistantAction(
        name: 'extract_assets',
        description: '从剧本提取角色/道具/场景资产。不传 scriptIds 时对全部尚未成功提取的剧本执行。',
        schema: {'scriptIds': _idArraySchema},
        costsMoney: true,
        taskClass: 'asset_extraction',
      ),
      AssistantAction(
        name: 'generate_storyboards',
        description: '为指定剧本生成分镜列表（画面提示词/运镜描述）。',
        schema: {'scriptId': {'type': 'integer'}},
        costsMoney: true,
        taskClass: 'storyboard_generate',
      ),
      AssistantAction(
        name: 'generate_shot_images',
        description: '为指定剧本的分镜生成首帧图。不传 storyboardIds 时对该剧本全部分镜执行。',
        schema: {
          'scriptId': {'type': 'integer'},
          'storyboardIds': _idArraySchema,
        },
        costsMoney: true,
        taskClass: 'storyboard_image_generation',
      ),
      AssistantAction(
        name: 'generate_videos',
        description: '为指定剧本的分镜生成视频（需已有首帧图）。不传 storyboardIds 时对全部已有首帧图的分镜执行。',
        schema: {
          'scriptId': {'type': 'integer'},
          'storyboardIds': _idArraySchema,
        },
        costsMoney: true,
        taskClass: 'video_generation',
      ),
      AssistantAction(
        name: 'bind_audio',
        description: '为角色资产自动匹配配音。不传 roleIds 时对全部尚未绑定配音的角色执行。',
        schema: {'roleIds': _idArraySchema},
        costsMoney: true,
        taskClass: 'audio_bind',
      ),
      AssistantAction(
        name: 'compose_episode',
        description: '本地合成整集成片（要求每个分镜都已选定视频），不调用付费供应商。',
        schema: {'scriptId': {'type': 'integer'}},
      ),
      AssistantAction(
        name: 'write_script',
        description: '覆写指定剧本的名称或正文（危险操作：会覆盖既有内容）。',
        schema: {
          'scriptId': {'type': 'integer'},
          'name': {'type': 'string'},
          'content': {'type': 'string'},
        },
        destructive: true,
      ),
      AssistantAction(
        name: 'note_save',
        description: '保存一条项目笔记（人物设定/场景/模型配置等长期信息）。',
        schema: {
          'name': {'type': 'string'},
          'content': {'type': 'string'},
        },
      ),
      AssistantAction(
        name: 'note_search',
        description: '按关键词检索项目笔记，返回最相关的几条。',
        schema: {'query': {'type': 'string'}},
      ),
      AssistantAction(
        name: 'note_delete',
        description: '删除一条项目笔记（危险操作：不可恢复）。',
        schema: {'noteId': {'type': 'string'}},
        destructive: true,
      ),
    ];

/// 中文别名 → 规范键（小表，≤30 行；扩充须走 spec 变更）。
const _chineseArgAliases = <String, String>{
  '剧本id': 'scriptId',
  '剧本ids': 'scriptIds',
  '章节id': 'novelId',
  '章节ids': 'novelIds',
  '分镜id': 'storyboardId',
  '分镜ids': 'storyboardIds',
  '角色id': 'roleId',
  '角色ids': 'roleIds',
  '名称': 'name',
  '内容': 'content',
  '关键词': 'query',
  '笔记id': 'noteId',
};

String _snakeToCamel(String s) => s.replaceAllMapped(
    RegExp(r'_([a-z0-9])'), (m) => m.group(1)!.toUpperCase());

/// 通用参数归一化：对 schema 每个期望键依次尝试
/// 精确命中 → snake_case 变体 → 单/复数变体 → 中文别名；
/// 显式空数组视同未传；未知键丢弃；值类型原样保留。
Map<String, dynamic> normalizeActionArgs(
  Map<String, dynamic> raw,
  Map<String, dynamic> schema,
) {
  // 先把 raw 的键统一成规范形（camel 化 + 中文别名翻译），保留原值。
  final canonical = <String, dynamic>{};
  raw.forEach((k, v) {
    final lower = k.trim();
    final aliased = _chineseArgAliases[lower.toLowerCase()] ??
        _chineseArgAliases[lower] ??
        _snakeToCamel(lower);
    canonical[aliased] = v;
  });
  final out = <String, dynamic>{};
  for (final expected in schema.keys) {
    dynamic value;
    if (canonical.containsKey(expected)) {
      value = canonical[expected];
    } else if (expected.endsWith('s') &&
        canonical.containsKey(expected.substring(0, expected.length - 1))) {
      value = canonical[expected.substring(0, expected.length - 1)];
    } else if (canonical.containsKey('${expected}s')) {
      value = canonical['${expected}s'];
    }
    if (value == null) continue;
    if (value is List && value.isEmpty) continue; // 空数组=未传
    out[expected] = value;
  }
  return out;
}

List<int>? _intList(dynamic value) {
  if (value == null) return null;
  if (value is num) return [value.toInt()];
  if (value is List) {
    final list = value.whereType<num>().map((e) => e.toInt()).toList();
    return list.isEmpty ? null : list;
  }
  return null;
}

int? _intOf(dynamic value) => value is num ? value.toInt() : null;

/// 分发：全部转调既有引擎方法，返回给对话流的中文执行摘要。
/// 错误一律抛 EngineException（由 assistant_chat 存 errKey、UI 层本地化渲染）。
Future<String> runAssistantAction(
  Engine engine,
  int projectId,
  String name,
  Map<String, dynamic> args,
) async {
  switch (name) {
    case 'get_status':
      return _statusSummary(engine, projectId);
    case 'generate_events':
      final ids = _intList(args['novelIds']) ??
          engine
              .novels(projectId, limit: 100000)
              .data
              .where((n) => n.eventState != 1)
              .map((n) => n.id)
              .toList();
      if (ids.isEmpty) return '没有需要生成事件的章节。';
      final taskId = engine.generateEvents(projectId, ids);
      return '已提交事件生成任务（任务 #$taskId），涉及 ${ids.length} 个章节。';
    case 'extract_assets':
      final ids = _intList(args['scriptIds']) ??
          engine
              .scripts(projectId)
              .where((s) => s.extractState != 1)
              .map((s) => s.id)
              .toList();
      if (ids.isEmpty) return '没有需要提取资产的剧本。';
      final taskId = engine.extractAssets(ids, projectId);
      return '已提交资产提取任务（任务 #$taskId），涉及 ${ids.length} 个剧本。';
    case 'generate_storyboards':
      final scriptId = _intOf(args['scriptId']);
      if (scriptId == null) return '缺少 scriptId 参数。';
      final taskId = engine.generateStoryboards(projectId, scriptId);
      return '已提交分镜生成任务（任务 #$taskId）。';
    case 'generate_shot_images':
      final scriptId = _intOf(args['scriptId']);
      if (scriptId == null) return '缺少 scriptId 参数。';
      final ids = _intList(args['storyboardIds']) ??
          engine.storyboards(scriptId).map((s) => s.id).toList();
      if (ids.isEmpty) return '该剧本暂无分镜。';
      final taskId = engine.batchGenerateStoryboardImages(projectId, ids,
          compulsory: true);
      return '已提交首帧图生成任务（任务 #$taskId），涉及 ${ids.length} 个分镜。';
    case 'generate_videos':
      final scriptId = _intOf(args['scriptId']);
      if (scriptId == null) return '缺少 scriptId 参数。';
      final ids = _intList(args['storyboardIds']) ??
          engine
              .storyboards(scriptId)
              .where((s) => s.filePath != null)
              .map((s) => s.id)
              .toList();
      if (ids.isEmpty) return '该剧本没有已生成首帧图的分镜。';
      final taskId = engine.batchGenerateVideos(projectId, ids);
      return '已提交视频生成任务（任务 #$taskId），涉及 ${ids.length} 个分镜。';
    case 'bind_audio':
      final ids = _intList(args['roleIds']) ??
          engine
              .roleAudioBindings(projectId)
              .where((r) => r.audioAssetId == null)
              .map((r) => r.roleId)
              .toList();
      if (ids.isEmpty) return '所有角色都已绑定配音，或项目内没有角色资产。';
      final taskId = engine.batchBindAudio(projectId, ids);
      return '已提交配音匹配任务（任务 #$taskId），涉及 ${ids.length} 个角色。';
    case 'compose_episode':
      final scriptId = _intOf(args['scriptId']);
      if (scriptId == null) return '缺少 scriptId 参数。';
      final result = await engine.composeEpisode(projectId, scriptId);
      final duration = result.durationSec;
      return '合成成功：${result.outputRelPath}'
          '${duration != null ? '（时长 ${duration.toStringAsFixed(1)}s）' : ''}。';
    case 'write_script':
      final scriptId = _intOf(args['scriptId']);
      if (scriptId == null) return '缺少 scriptId 参数。';
      engine.updateScript(scriptId,
          name: args['name'] as String?, content: args['content'] as String?);
      return '剧本 #$scriptId 已更新。';
    case 'note_save':
      final noteName = (args['name'] as String?)?.trim() ?? '';
      final content = (args['content'] as String?)?.trim() ?? '';
      if (content.isEmpty) return '笔记内容不能为空。';
      engine.saveProjectNote(projectId,
          name: noteName.isEmpty ? '未命名' : noteName, content: content);
      return '笔记已保存：${noteName.isEmpty ? '未命名' : noteName}。';
    case 'note_search':
      final query = (args['query'] as String?)?.trim() ?? '';
      if (query.isEmpty) return '缺少检索关键词。';
      final hits = engine.searchProjectNotes(projectId, query);
      if (hits.isEmpty) return '没有匹配「$query」的笔记。';
      return [
        for (final n in hits) '【${n.name}】${n.content}',
      ].join('\n');
    case 'note_delete':
      final noteId = (args['noteId'] as String?)?.trim() ?? '';
      if (noteId.isEmpty) return '缺少 noteId 参数。';
      engine.deleteProjectNote(projectId, noteId);
      return '笔记已删除。';
    default:
      return '未知动作：$name';
  }
}

String _statusSummary(Engine engine, int projectId) {
  final chapters = engine.novels(projectId, limit: 100000).data;
  final chapterDone = chapters.where((c) => c.eventState == 1).length;
  final scriptRows = engine.scripts(projectId);
  final scriptDone = scriptRows.where((s) => s.extractState == 1).length;
  var storyboardCount = 0;
  var storyboardImageDone = 0;
  for (final s in scriptRows) {
    final sbs = engine.storyboards(s.id);
    storyboardCount += sbs.length;
    storyboardImageDone += sbs.where((b) => b.state == sbDone).length;
  }
  final roles = engine.roleAudioBindings(projectId);
  final roleBound = roles.where((r) => r.audioAssetId != null).length;
  return '章节 ${chapters.length} 个（事件已生成 $chapterDone 个）；'
      '剧本 ${scriptRows.length} 个（资产已提取 $scriptDone 个）；'
      '分镜 $storyboardCount 个（首帧图已生成 $storyboardImageDone 个）；'
      '角色 ${roles.length} 个（已绑定配音 $roleBound 个）。';
}
