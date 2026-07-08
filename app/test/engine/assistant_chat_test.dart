import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/assistant_chat.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/novel.dart';
import 'package:dramaflow/src/engine/novel_parse.dart';
import 'package:dramaflow/src/engine/project_notes.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _Gateway implements ProviderGateway {
  List<AgentTurnResult> turns = const [];
  List<AgentToolDef> lastTools = const [];
  List<List<AgentToolDef>> toolsByCall = const [];
  List<Map<String, String>> lastMessages = const [];
  List<String> stages = const [];
  String lastSystem = '';
  int callCount = 0;

  @override
  Future<AgentTurnResult> generateAgentTurn(
    String system,
    List<Map<String, String>> messages,
    List<AgentToolDef> tools, {
    required String stage,
    CancelToken? cancelToken,
  }) async {
    lastSystem = system;
    lastMessages = [for (final message in messages) Map.of(message)];
    lastTools = List<AgentToolDef>.from(tools);
    toolsByCall = [...toolsByCall, lastTools];
    stages = [...stages, stage];
    final result = turns[callCount];
    callCount++;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Database db;
  late _Gateway gateway;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-assistant-chat-');
    db = openEngineDb(':memory:');
    gateway = _Gateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '助手测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('assistantMessages 持久化用户和助手文本，并暴露启用动作工具面', () async {
    gateway.turns = [const AgentTurnResult.text('我来帮你推进流程。')];

    await engine.sendAssistantMessage(
      projectId,
      '你好',
      family: assistantFamilyScript,
      autoMode: false,
    );

    final messages = engine.assistantMessages(
      projectId,
      family: assistantFamilyScript,
    );
    expect(messages.map((m) => m.role), ['user', 'assistant']);
    expect(messages.last.content, '我来帮你推进流程。');
    expect(gateway.stages.single, 'scriptAgent');
    expect(gateway.lastTools.map((tool) => tool.name), contains('get_status'));
    expect(gateway.lastSystem, contains('短剧制作助手'));
  });

  test('family 由入口传入并互相隔离', () async {
    gateway.turns = [
      const AgentTurnResult.text('剧本侧'),
      const AgentTurnResult.text('制作侧'),
    ];

    await engine.sendAssistantMessage(
      projectId,
      '规划剧本',
      family: assistantFamilyScript,
      autoMode: false,
    );
    await engine.sendAssistantMessage(
      projectId,
      '生成分镜',
      family: assistantFamilyProduction,
      autoMode: false,
    );

    expect(
      engine
          .assistantMessages(projectId, family: assistantFamilyScript)
          .last
          .content,
      '剧本侧',
    );
    expect(
      engine
          .assistantMessages(projectId, family: assistantFamilyProduction)
          .last
          .content,
      '制作侧',
    );
    expect(gateway.stages, ['scriptAgent', 'productionAgent']);
  });

  test('manual 模式只执行一轮工具调用', () async {
    gateway.turns = [
      const AgentTurnResult.tool('get_status', {}),
      const AgentTurnResult.text('不应继续到第二轮'),
    ];

    await engine.sendAssistantMessage(
      projectId,
      '看看进度',
      family: assistantFamilyScript,
      autoMode: false,
    );

    expect(gateway.callCount, 1);
    final messages = engine.assistantMessages(
      projectId,
      family: assistantFamilyScript,
    );
    expect(messages.last.role, 'tool');
    expect(messages.last.toolName, 'get_status');
  });

  test('auto 模式最多连续执行 5 轮', () async {
    gateway.turns = [
      for (var i = 0; i < 6; i++) AgentTurnResult.tool('get_status', {'i': i}),
    ];

    await engine.sendAssistantMessage(
      projectId,
      '自动跑一下',
      family: assistantFamilyScript,
      autoMode: true,
    );

    expect(gateway.callCount, 5);
    final toolMessages = engine
        .assistantMessages(projectId, family: assistantFamilyScript)
        .where((m) => m.role == 'tool')
        .toList();
    expect(toolMessages, hasLength(5));
  });

  test('manual 花钱动作挂起确认，批准后才执行入队', () async {
    engine.addNovels(projectId, const [
      ChapterItem(index: 1, reel: '正文卷', chapter: '一', chapterData: 'x'),
    ]);
    gateway.turns = [const AgentTurnResult.tool('generate_events', {})];

    await engine.sendAssistantMessage(
      projectId,
      '生成事件',
      family: assistantFamilyScript,
      autoMode: false,
    );

    var messages = engine.assistantMessages(
      projectId,
      family: assistantFamilyScript,
    );
    expect(messages.last.role, 'confirm');
    expect(messages.last.toolName, 'generate_events');
    expect(messages.last.confirmStatus, 'pending');
    expect(
      db.select("SELECT id FROM o_tasks WHERE taskClass='event_generation'"),
      isEmpty,
    );

    await engine.confirmPendingAssistantAction(
      projectId,
      family: assistantFamilyScript,
      approve: true,
    );

    messages =
        engine.assistantMessages(projectId, family: assistantFamilyScript);
    expect(messages.where((m) => m.role == 'confirm').single.confirmStatus,
        'approved');
    expect(messages.last.role, 'tool');
    expect(messages.last.toolName, 'generate_events');
    expect(
      db.select("SELECT id FROM o_tasks WHERE taskClass='event_generation'"),
      hasLength(1),
    );
  });

  test('auto 模式下破坏动作仍挂起确认', () async {
    final noteId = engine.saveProjectNote(projectId, name: '设定', content: '寒山');
    gateway.turns = [
      AgentTurnResult.tool('note_delete', {'noteId': noteId}),
    ];

    await engine.sendAssistantMessage(
      projectId,
      '删掉这条笔记',
      family: assistantFamilyProduction,
      autoMode: true,
    );

    final messages = engine.assistantMessages(
      projectId,
      family: assistantFamilyProduction,
    );
    expect(messages.last.role, 'confirm');
    expect(messages.last.toolName, 'note_delete');
    expect(messages.last.confirmStatus, 'pending');
    expect(engine.projectNotes(projectId).map((n) => n.id), contains(noteId));
  });

  test('助手自动模式设置和清空会话可持久化', () {
    expect(engine.assistantAutoMode(), isFalse);
    engine.setAssistantAutoMode(true);
    expect(engine.assistantAutoMode(), isTrue);

    gateway.turns = const [AgentTurnResult.text('x')];
    engine.clearAssistantChat(projectId, family: assistantFamilyScript);
    expect(
      engine.assistantMessages(projectId, family: assistantFamilyScript),
      isEmpty,
    );
  });
}
