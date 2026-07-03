// Agent 体系（P5，瘦身版，见 docs/reference 与 spec §4 决策）：
// ToonFlow 的真实 Agent 是多层 Claude 子代理编排 + 向量 RAG 记忆，体量巨大且与本项目
// "显式流水线可见可恢复"的核心设计相悖。DramaFlow 按 spec 既定决策做单层 AgentRunner：
// 工具调用 1:1 映射到已有真实流水线动作（事件/资产/分镜/图片/视频/配音），每次调用都走
// 现有 o_tasks 队列，绝不出现"对话框说做了但任务表查无此事"。
// 记忆：仅短期消息历史（存 o_agentWorkData.data，key='agentChat'，project 级，非向量 RAG，
// 已文档化的范围简化）。执行模式对应 ToonFlow 的 auto/manual：manual 每轮只执行一个工具
// 调用后等待用户确认；auto 在安全轮次上限内连续执行工具链。
import 'dart:convert';

import 'package:dio/dio.dart';

import 'audio_bind.dart';
import 'compose_episode.dart';
import 'engine.dart';
import 'errors.dart';
import 'events.dart';
import 'novel.dart';
import 'providers/openai_text.dart' show AgentToolDef, AgentTurnResult;
import 'scripts.dart';
import 'storyboard.dart';
import 'video_track.dart';

const agentRoleUser = 'user';
const agentRoleAssistant = 'assistant';
const agentRoleTool = 'tool';

const _maxAutoTurns = 5;

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

final _tools = <AgentToolDef>[
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
      },
      'required': ['scriptId'],
    },
  ),
  AgentToolDef(
    name: 'generate_shot_images',
    description: '为指定剧本的分镜生成首帧图。不传 storyboardIds 时对该剧本全部分镜执行。',
    schema: const {
      'type': 'object',
      'properties': {
        'scriptId': {'type': 'integer'},
        'storyboardIds': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
      },
      'required': ['scriptId'],
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
        'storyboardIds': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
      },
      'required': ['scriptId'],
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
      },
      'required': ['scriptId'],
    },
  ),
];

extension AgentApi on Engine {
  List<AgentToolDef> get agentTools => _tools;

  List<AgentMessage> agentMessages(int projectId) {
    final row = db
        .select(
          "SELECT data FROM o_agentWorkData WHERE projectId=? AND episodesId IS NULL AND key='agentChat'",
          [projectId],
        )
        .firstOrNull;
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

  void _saveAgentMessages(int projectId, List<AgentMessage> messages) {
    final json = jsonEncode([for (final m in messages) m.toJson()]);
    final exists = db
        .select(
          "SELECT id FROM o_agentWorkData WHERE projectId=? AND episodesId IS NULL AND key='agentChat'",
          [projectId],
        )
        .firstOrNull;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (exists == null) {
      db.execute(
        'INSERT INTO o_agentWorkData (projectId,key,data,createTime,updateTime) '
        "VALUES (?,'agentChat',?,?,?)",
        [projectId, json, now, now],
      );
    } else {
      db.execute(
        'UPDATE o_agentWorkData SET data=?, updateTime=? WHERE id=?',
        [json, now, exists['id']],
      );
    }
  }

  void clearAgentMemory(int projectId) {
    db.execute(
      "DELETE FROM o_agentWorkData WHERE projectId=? AND episodesId IS NULL AND key='agentChat'",
      [projectId],
    );
  }

  /// Agent 执行模式（auto/manual）持久化。config 由别处拥有，此处直接写 o_setting
  /// 键 agent.useMode（'auto'/'manual'），与 ToonFlow 的 auto/manual 语义一致。
  bool agentUseMode() {
    final row = db
        .select("SELECT value FROM o_setting WHERE key='agent.useMode'")
        .firstOrNull;
    return (row?['value'] as String?) == 'auto';
  }

  void setAgentUseMode(bool autoMode) {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.useMode', autoMode ? 'auto' : 'manual'],
    );
  }

  /// 发送一条用户消息并驱动 Agent 执行（工具调用全部落 o_tasks，可见可恢复）。
  /// manual 模式每轮只执行一个工具调用；auto 模式在安全上限内连续执行工具链。
  Future<void> sendAgentMessage(
    int projectId,
    String text, {
    required bool autoMode,
  }) async {
    final messages = List<AgentMessage>.from(agentMessages(projectId));
    final now = DateTime.now().millisecondsSinceEpoch;
    messages.add(AgentMessage(role: agentRoleUser, content: text, createdAt: now));
    _saveAgentMessages(projectId, messages);

    const system = '你是短剧创作助手。你可以调用工具推进项目的制作流程'
        '（事件提取→提取资产→生成分镜→生成首帧图→生成视频→配音绑定→合成）。'
        '每次只做用户明确要求或明显下一步需要的动作，不要臆造不存在的 id。'
        '如果不确定该做什么，先调用 get_status 查看进度。';

    for (var turn = 0; turn < (autoMode ? _maxAutoTurns : 1); turn++) {
      final history = [
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
        result = await gateway.generateAgentTurn(
          system,
          history,
          _tools,
          stage: 'script_gen',
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
        _saveAgentMessages(projectId, messages);
        return;
      }

      if (!result.isToolCall) {
        messages.add(AgentMessage(
            role: agentRoleAssistant,
            content: result.text ?? '',
            createdAt: DateTime.now().millisecondsSinceEpoch));
        _saveAgentMessages(projectId, messages);
        return;
      }

      final summary =
          await _runTool(projectId, result.toolName!, result.toolArgs ?? const {});
      messages.add(AgentMessage(
        role: agentRoleTool,
        content: summary,
        toolName: result.toolName,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _saveAgentMessages(projectId, messages);
    }
  }

  /// 模型经常用显式空数组表达"不指定具体 id，按默认全部执行"，
  /// 与"未传该字段"语义相同：都应回退到调用方给出的默认集合。
  List<int>? _intList(Map<String, dynamic> args, String key) {
    final raw = args[key];
    if (raw is! List || raw.isEmpty) return null;
    return raw.map((e) => (e as num).toInt()).toList();
  }

  Future<String> _runTool(
      int projectId, String name, Map<String, dynamic> args) async {
    try {
      switch (name) {
        case 'get_status':
          return _statusSummary(projectId);
        case 'generate_events':
          final ids = _intList(args, 'novelIds') ??
              novels(projectId, limit: 100000)
                  .data
                  .where((n) => n.eventState != 1)
                  .map((n) => n.id)
                  .toList();
          if (ids.isEmpty) return '没有需要生成事件的章节。';
          final taskId = generateEvents(projectId, ids);
          return '已提交事件生成任务（任务 #$taskId），涉及 ${ids.length} 个章节。';
        case 'extract_assets':
          final ids = _intList(args, 'scriptIds') ??
              scripts(projectId)
                  .where((s) => s.extractState != 1)
                  .map((s) => s.id)
                  .toList();
          if (ids.isEmpty) return '没有需要提取资产的剧本。';
          final taskId = extractAssets(ids, projectId);
          return '已提交资产提取任务（任务 #$taskId），涉及 ${ids.length} 个剧本。';
        case 'generate_storyboards':
          final scriptId = (args['scriptId'] as num?)?.toInt();
          if (scriptId == null) return '缺少 scriptId 参数。';
          final taskId = generateStoryboards(projectId, scriptId);
          return '已提交分镜生成任务（任务 #$taskId）。';
        case 'generate_shot_images':
          final scriptId = (args['scriptId'] as num?)?.toInt();
          if (scriptId == null) return '缺少 scriptId 参数。';
          final ids = _intList(args, 'storyboardIds') ??
              storyboards(scriptId).map((s) => s.id).toList();
          if (ids.isEmpty) return '该剧本暂无分镜。';
          final taskId =
              batchGenerateStoryboardImages(projectId, ids, compulsory: true);
          return '已提交首帧图生成任务（任务 #$taskId），涉及 ${ids.length} 个分镜。';
        case 'generate_videos':
          final scriptId = (args['scriptId'] as num?)?.toInt();
          if (scriptId == null) return '缺少 scriptId 参数。';
          final ids = _intList(args, 'storyboardIds') ??
              storyboards(scriptId)
                  .where((s) => s.filePath != null)
                  .map((s) => s.id)
                  .toList();
          if (ids.isEmpty) return '该剧本没有已生成首帧图的分镜。';
          final taskId = batchGenerateVideos(projectId, ids);
          return '已提交视频生成任务（任务 #$taskId），涉及 ${ids.length} 个分镜。';
        case 'bind_audio':
          final ids = _intList(args, 'roleIds') ??
              roleAudioBindings(projectId)
                  .where((r) => r.audioAssetId == null)
                  .map((r) => r.roleId)
                  .toList();
          if (ids.isEmpty) return '所有角色都已绑定配音，或项目内没有角色资产。';
          final taskId = batchBindAudio(projectId, ids);
          return '已提交配音匹配任务（任务 #$taskId），涉及 ${ids.length} 个角色。';
        case 'compose_episode':
          final scriptId = (args['scriptId'] as num?)?.toInt();
          if (scriptId == null) return '缺少 scriptId 参数。';
          final result = await composeEpisode(projectId, scriptId);
          return '合成成功：${result.outputRelPath}'
              '${result.durationSec != null ? '（时长 ${result.durationSec!.toStringAsFixed(1)}s）' : ''}。';
        default:
          return '未知工具：$name';
      }
    } catch (e) {
      final ex = e is EngineException
          ? e
          : EngineException(errLlmFormat, {'message': '$e'});
      return '执行失败：${ex.errKey}';
    }
  }

  String _statusSummary(int projectId) {
    final chapters = novels(projectId, limit: 100000).data;
    final chapterDone = chapters.where((c) => c.eventState == 1).length;
    final eventTotal = events(projectId, limit: 1).total;
    final scriptRows = scripts(projectId);
    final scriptDone = scriptRows.where((s) => s.extractState == 1).length;
    final storyboardCount = db
        .select(
          'SELECT COUNT(*) n FROM o_storyboard WHERE scriptId IN '
          '(SELECT id FROM o_script WHERE projectId=?)',
          [projectId],
        )
        .first['n'] as int;
    final storyboardImageDone = db
        .select(
          "SELECT COUNT(*) n FROM o_storyboard WHERE state=? AND scriptId IN "
          '(SELECT id FROM o_script WHERE projectId=?)',
          [sbDone, projectId],
        )
        .first['n'] as int;
    final roles = roleAudioBindings(projectId);
    final roleBound = roles.where((r) => r.audioAssetId != null).length;
    return '章节 ${chapters.length} 个（事件已生成 $chapterDone 个，共 $eventTotal 条事件）；'
        '剧本 ${scriptRows.length} 个（资产已提取 $scriptDone 个）；'
        '分镜 $storyboardCount 个（首帧图已生成 $storyboardImageDone 个）；'
        '角色 ${roles.length} 个（已绑定配音 $roleBound 个）。';
  }
}
