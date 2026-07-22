import 'dart:convert';

import 'assistant_actions.dart';
import 'assistant_skills.dart';
import 'engine.dart';
import 'errors.dart';
import 'pipeline_policy.dart';
import 'providers/gateway.dart' show AgentToolDef;

const assistantRoleUser = 'user';
const assistantRoleAssistant = 'assistant';
const assistantRoleTool = 'tool';
const assistantRoleConfirm = 'confirm';

const assistantFamilyScript = 'script';
const assistantFamilyProduction = 'production';

const _scriptAssistantStage = 'scriptAgent';
const _productionAssistantStage = 'productionAgent';
const _maxAutoTurns = 5;

class AssistantMessage {
  final String role;
  final String content;
  final String? toolName;
  final Map<String, dynamic>? pendingArgs;
  final String? confirmStatus;
  final int createdAt;

  const AssistantMessage({
    required this.role,
    required this.content,
    this.toolName,
    this.pendingArgs,
    this.confirmStatus,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        if (toolName != null) 'toolName': toolName,
        if (pendingArgs != null) 'pendingArgs': pendingArgs,
        if (confirmStatus != null) 'confirmStatus': confirmStatus,
        'at': createdAt,
      };

  factory AssistantMessage.fromJson(Map<String, dynamic> json) {
    final pending = json['pendingArgs'];
    return AssistantMessage(
      role: json['role'] as String? ?? assistantRoleAssistant,
      content: json['content'] as String? ?? '',
      toolName: json['toolName'] as String?,
      pendingArgs: pending is Map ? Map<String, dynamic>.from(pending) : null,
      confirmStatus: json['confirmStatus'] as String?,
      createdAt: (json['at'] as num?)?.toInt() ?? 0,
    );
  }

  AssistantMessage copyWith({
    String? confirmStatus,
  }) =>
      AssistantMessage(
        role: role,
        content: content,
        toolName: toolName,
        pendingArgs: pendingArgs,
        confirmStatus: confirmStatus ?? this.confirmStatus,
        createdAt: createdAt,
      );
}

extension AssistantChatApi on Engine {
  List<AssistantMessage> assistantMessages(
    int projectId, {
    required String family,
  }) {
    final row = db.select(
      'SELECT data FROM o_agentWorkData '
      'WHERE projectId=? AND episodesId IS NULL AND key=?',
      [projectId, _assistantChatKey(family)],
    ).firstOrNull;
    if (row == null) return const [];
    try {
      final decoded = jsonDecode(row['data'] as String) as List;
      return [
        for (final item in decoded.whereType<Map>())
          AssistantMessage.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> sendAssistantMessage(
    int projectId,
    String text, {
    required String family,
    required bool autoMode,
  }) async {
    final messages = List<AssistantMessage>.from(
      assistantMessages(projectId, family: family),
    )..add(AssistantMessage(
        role: assistantRoleUser,
        content: text,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
    _saveAssistantMessages(projectId, family, messages);
    await _driveAssistantLoop(
      projectId,
      family: family,
      messages: messages,
      autoMode: autoMode,
      // 手动模式给 2 轮预算：如果第一轮 AI 只是调用只读的 get_status 打探情况
      // （不需要确认，也没有实际推进任何东西），还能再决定一次真正要做的事；
      // 但凡跑了一个会产生实际改动的动作，下面的 return 条件仍然只放行一步。
      remainingTurns: autoMode ? _maxAutoTurns : 2,
    );
  }

  Future<void> confirmPendingAssistantAction(
    int projectId, {
    required String family,
    required bool approve,
  }) async {
    final messages = List<AssistantMessage>.from(
      assistantMessages(projectId, family: family),
    );
    final index = messages.lastIndexWhere(
        (m) => m.role == assistantRoleConfirm && m.confirmStatus == 'pending');
    if (index < 0) return;
    final pending = messages[index];
    messages[index] = pending.copyWith(
      confirmStatus: approve ? 'approved' : 'rejected',
    );
    _saveAssistantMessages(projectId, family, messages);
    if (!approve) return;

    final payload = pending.pendingArgs ?? const {};
    final toolName = pending.toolName ?? payload['toolName'] as String?;
    if (toolName == null || toolName.isEmpty) return;
    final argsValue = payload['args'];
    final args = argsValue is Map
        ? Map<String, dynamic>.from(argsValue)
        : <String, dynamic>{};
    final autoMode = payload['autoMode'] == true;
    final remainingTurns = (payload['remainingTurns'] as num?)?.toInt() ?? 0;
    final ran = await _runAssistantActionAndAppend(
      projectId,
      family: family,
      messages: messages,
      toolName: toolName,
      args: args,
      addMoneyNotice: false,
    );
    if (ran && autoMode && remainingTurns > 0) {
      await _driveAssistantLoop(
        projectId,
        family: family,
        messages: messages,
        autoMode: true,
        remainingTurns: remainingTurns,
      );
    }
  }

  void clearAssistantChat(int projectId, {required String family}) {
    db.execute(
      'DELETE FROM o_agentWorkData WHERE projectId=? '
      'AND episodesId IS NULL AND key=?',
      [projectId, _assistantChatKey(family)],
    );
  }

  bool assistantAutoMode() {
    final row = db
        .select("SELECT value FROM o_setting WHERE key='assistant.useMode'")
        .firstOrNull;
    return row?['value'] == 'auto';
  }

  void setAssistantAutoMode(bool value) {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['assistant.useMode', value ? 'auto' : 'manual'],
    );
  }

  Future<void> _driveAssistantLoop(
    int projectId, {
    required String family,
    required List<AssistantMessage> messages,
    required bool autoMode,
    required int remainingTurns,
  }) async {
    for (var turn = 0; turn < remainingTurns; turn++) {
      final stage = _assistantStage(family);
      final result = await _nextAssistantTurn(
        family: family,
        stage: stage,
        messages: messages,
      );
      if (!result.isToolCall) {
        messages.add(AssistantMessage(
          role: assistantRoleAssistant,
          content: result.text ?? '',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        _saveAssistantMessages(projectId, family, messages);
        return;
      }

      final action = _assistantActionByName(result.toolName!);
      if (action == null) {
        messages.add(AssistantMessage(
          role: assistantRoleAssistant,
          content: _errorContent(const EngineException(
            errLlmFormat,
            {'reason': 'unknownAssistantAction'},
          )),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        _saveAssistantMessages(projectId, family, messages);
        return;
      }
      final args = normalizeActionArgs(
        result.toolArgs ?? const {},
        action.schema,
      );
      final verdict = checkAction(
        config,
        taskClass: action.taskClass,
        destructiveKey: action.destructive ? action.name : null,
        autoMode: autoMode,
      );
      if (verdict != PolicyVerdict.allow) {
        messages.add(AssistantMessage(
          role: assistantRoleConfirm,
          content: jsonEncode({
            'policy': verdict.name,
            'tool': action.name,
          }),
          toolName: action.name,
          pendingArgs: {
            'toolName': action.name,
            'args': args,
            'autoMode': autoMode,
            'remainingTurns': remainingTurns - turn - 1,
          },
          confirmStatus: 'pending',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        _saveAssistantMessages(projectId, family, messages);
        return;
      }

      final ran = await _runAssistantActionAndAppend(
        projectId,
        family: family,
        messages: messages,
        toolName: action.name,
        args: args,
        addMoneyNotice: autoMode && action.costsMoney,
      );
      final isStatusProbe = action.name == 'get_status';
      if (!ran || !(autoMode || isStatusProbe)) return;
    }
  }

  Future<dynamic> _nextAssistantTurn({
    required String family,
    required String stage,
    required List<AssistantMessage> messages,
  }) async {
    try {
      return await gateway.generateAgentTurn(
        _assistantSystemPrompt(family),
        _assistantHistory(messages),
        _assistantToolDefs(),
        stage: stage,
      );
    } catch (e) {
      final ex = e is EngineException
          ? e
          : EngineException(errLlmFormat, {'message': '$e'});
      messages.add(AssistantMessage(
        role: assistantRoleAssistant,
        content: _errorContent(ex),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      return const _AssistantStop();
    }
  }

  Future<bool> _runAssistantActionAndAppend(
    int projectId, {
    required String family,
    required List<AssistantMessage> messages,
    required String toolName,
    required Map<String, dynamic> args,
    required bool addMoneyNotice,
  }) async {
    if (addMoneyNotice) {
      messages.add(AssistantMessage(
        role: assistantRoleAssistant,
        content: jsonEncode({
          'infoKey': 'assistantMoneyNotice',
          'tool': toolName,
        }),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }
    try {
      final summary = await runAssistantAction(this, projectId, toolName, args);
      messages.add(AssistantMessage(
        role: assistantRoleTool,
        content: summary,
        toolName: toolName,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _saveAssistantMessages(projectId, family, messages);
      return true;
    } catch (e) {
      final ex = e is EngineException
          ? e
          : EngineException(errLlmFormat, {'message': '$e'});
      messages.add(AssistantMessage(
        role: assistantRoleAssistant,
        content: _errorContent(ex),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _saveAssistantMessages(projectId, family, messages);
      return false;
    }
  }

  void _saveAssistantMessages(
    int projectId,
    String family,
    List<AssistantMessage> messages,
  ) {
    final key = _assistantChatKey(family);
    final data = jsonEncode([for (final message in messages) message.toJson()]);
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = db.select(
      'SELECT id FROM o_agentWorkData '
      'WHERE projectId=? AND episodesId IS NULL AND key=?',
      [projectId, key],
    ).firstOrNull;
    if (row == null) {
      db.execute(
        'INSERT INTO o_agentWorkData (projectId,key,data,createTime,updateTime) '
        'VALUES (?,?,?,?,?)',
        [projectId, key, data, now, now],
      );
    } else {
      db.execute(
        'UPDATE o_agentWorkData SET data=?, updateTime=? WHERE id=?',
        [data, now, row['id']],
      );
    }
  }

  String _assistantSystemPrompt(String family) {
    final lines = <String>[
      '你是短剧制作助手，只能帮助推进当前 DramaFlow/ToonFlow 风格短剧流水线。',
      '不要执行脚本代码，不要输出 ES 查询 DSL，不要发明未注册工具。',
      if (family == assistantFamilyProduction)
        '当前入口是制作画布，优先处理分镜、首帧、视频、配音、合成。'
      else
        '当前入口是剧本助手，优先处理章节事件、剧本和资产提取。',
      '可用工具必须按 schema 调用；不确定时先调用 get_status。',
      ...assistantSkillContexts(),
    ];
    return lines.join('\n\n');
  }

  List<AgentToolDef> _assistantToolDefs() {
    final enabled = enabledAssistantActionNames();
    return [
      for (final action in assistantActions())
        if (enabled.contains(action.name))
          AgentToolDef(
            name: action.name,
            description: action.description,
            schema: {
              'type': 'object',
              'properties': action.schema,
            },
          ),
    ];
  }
}

String _assistantChatKey(String family) => 'assistantChat:$family';

String _assistantStage(String family) => family == assistantFamilyProduction
    ? _productionAssistantStage
    : _scriptAssistantStage;

AssistantAction? _assistantActionByName(String name) {
  for (final action in assistantActions()) {
    if (action.name == name) return action;
  }
  return null;
}

List<Map<String, String>> _assistantHistory(List<AssistantMessage> messages) =>
    [
      for (final message in messages)
        {
          'role': message.role == assistantRoleUser ? 'user' : 'assistant',
          'content': switch (message.role) {
            assistantRoleTool =>
              '（工具 ${message.toolName ?? ''} 执行结果：${message.content}）',
            assistantRoleConfirm =>
              '（等待用户确认工具 ${message.toolName ?? ''}：${message.confirmStatus ?? 'pending'}）',
            _ => message.content,
          },
        },
    ];

String _errorContent(EngineException ex) => jsonEncode({
      'errKey': ex.errKey,
      if (ex.errParams.isNotEmpty) 'params': ex.errParams,
    });

class _AssistantStop {
  const _AssistantStop();

  bool get isToolCall => false;

  String? get text => null;
}
