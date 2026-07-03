import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/agent.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/events.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/novel.dart';
import 'package:dramaflow/src/engine/novel_parse.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late _Gateway gateway;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-agent-');
    db = openEngineDb(':memory:');
    gateway = _Gateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 10),
    );
    db.execute(
        "INSERT INTO o_prompt (name,type,data,useData) VALUES "
        "('eventExtraction','eventExtraction','事件系统词',NULL)");
    engine.installNovelEventPipeline();
    engine.installScriptPipeline();
    engine.installStoryboardPipeline();
    engine.queue.start();
    projectId = engine.addProject(projectType: 'novel', name: 'Agent测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('消息持久化：往返读取+清空记忆', () async {
    expect(engine.agentMessages(projectId), isEmpty);
    gateway.turns = [const AgentTurnResult.text('你好，我可以帮你推进制作流程。')];
    await engine.sendAgentMessage(projectId, '你好', autoMode: false);

    final msgs = engine.agentMessages(projectId);
    expect(msgs, hasLength(2));
    expect(msgs[0].role, agentRoleUser);
    expect(msgs[0].content, '你好');
    expect(msgs[1].role, agentRoleAssistant);
    expect(msgs[1].content, '你好，我可以帮你推进制作流程。');

    engine.clearAgentMemory(projectId);
    expect(engine.agentMessages(projectId), isEmpty);
  });

  test('manual 模式：一次工具调用后停止，等待用户下一句', () async {
    final novelId = engine
        .addNovels(projectId, const [
          ChapterItem(index: 1, reel: '正文卷', chapter: '一', chapterData: 'x'),
        ])
        .single;
    gateway.turns = [
      AgentTurnResult.tool('generate_events', {
        'novelIds': [novelId]
      }),
    ];
    await engine.sendAgentMessage(projectId, '帮我生成事件', autoMode: false);

    final msgs = engine.agentMessages(projectId);
    expect(msgs, hasLength(2)); // user + tool（manual 模式工具调用后即停）
    expect(msgs.last.role, agentRoleTool);
    expect(msgs.last.toolName, 'generate_events');
    expect(msgs.last.content, contains('1 个章节'));
    expect(gateway.callCount, 1, reason: 'manual 模式只调用一次 LLM');

    final tasks = db.select("SELECT taskClass FROM o_tasks");
    expect(tasks.map((t) => t['taskClass']), contains('event_generation'));
  });

  test('auto 模式：连续工具调用直到模型回复纯文本', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '一', content: 'x');
    gateway.turns = [
      AgentTurnResult.tool('get_status', const {}),
      const AgentTurnResult.text('已经查看完进度，暂无更多章节需要处理。'),
    ];
    await engine.sendAgentMessage(projectId, '看看现在进度', autoMode: true);

    expect(engine.scripts(projectId).single.id, scriptId);
    final msgs = engine.agentMessages(projectId);
    expect(msgs.map((m) => m.role),
        [agentRoleUser, agentRoleTool, agentRoleAssistant]);
    expect(msgs[1].content, contains('剧本 1 个'));
    expect(gateway.callCount, 2);
  });

  test('auto 模式在安全上限内停止（防止无限工具调用循环）', () async {
    gateway.turns = List.generate(
        10, (_) => const AgentTurnResult.tool('get_status', {}));
    await engine.sendAgentMessage(projectId, '一直做', autoMode: true);
    expect(gateway.callCount, 5, reason: '_maxAutoTurns=5 上限生效');
  });

  test('generate_events 不传 novelIds 时默认处理全部未完成章节', () async {
    engine.addNovels(projectId, const [
      ChapterItem(index: 1, reel: '正文卷', chapter: '一', chapterData: 'x'),
      ChapterItem(index: 2, reel: '正文卷', chapter: '二', chapterData: 'y'),
    ]);
    gateway.turns = [const AgentTurnResult.tool('generate_events', {})];
    await engine.sendAgentMessage(projectId, '生成事件', autoMode: false);
    expect(engine.agentMessages(projectId).last.content, contains('2 个章节'));
  });

  test('generate_events 传显式空数组时仍按默认处理未完成章节（真实模型常见写法）', () async {
    engine.addNovels(projectId, const [
      ChapterItem(index: 1, reel: '正文卷', chapter: '一', chapterData: 'x'),
    ]);
    gateway.turns = [
      AgentTurnResult.tool('generate_events', const {'novelIds': <int>[]}),
    ];
    await engine.sendAgentMessage(projectId, '帮我把这一章的事件生成一下', autoMode: false);
    expect(engine.agentMessages(projectId).last.content, contains('1 个章节'));
  });

  test('工具执行失败时返回中文可见错误摘要而非崩溃', () async {
    gateway.turns = [
      AgentTurnResult.tool('generate_storyboards', const {}), // 缺 scriptId
    ];
    await engine.sendAgentMessage(projectId, '生成分镜', autoMode: false);
    expect(engine.agentMessages(projectId).last.content, contains('缺少'));
  });

  test('LLM 调用失败时追加带错误码的助手消息', () async {
    gateway.shouldThrow = true;
    await engine.sendAgentMessage(projectId, '你好', autoMode: false);
    expect(engine.agentMessages(projectId).last.content, contains('errLlmFormat'));
  });

  test('Agent 执行模式默认 manual 且持久化到 o_setting', () {
    // 默认（未写入）为 manual → false
    expect(engine.agentUseMode(), isFalse);
    engine.setAgentUseMode(true);
    expect(engine.agentUseMode(), isTrue);
    expect(
      db.select("SELECT value FROM o_setting WHERE key='agent.useMode'").single[
          'value'],
      'auto',
    );
    engine.setAgentUseMode(false);
    expect(engine.agentUseMode(), isFalse);
    expect(
      db.select("SELECT value FROM o_setting WHERE key='agent.useMode'").single[
          'value'],
      'manual',
    );
  });
}

class _Gateway implements ProviderGateway {
  List<AgentTurnResult> turns = const [];
  int callCount = 0;
  bool shouldThrow = false;

  @override
  Future<AgentTurnResult> generateAgentTurn(
    String system,
    List<Map<String, String>> messages,
    List<AgentToolDef> tools, {
    required String stage,
    CancelToken? cancelToken,
  }) async {
    if (shouldThrow) throw Exception('boom');
    final r = turns[callCount];
    callCount++;
    return r;
  }

  @override
  Future<TextResult> generateText(String system, String user,
          {required String stage, CancelToken? cancelToken}) async =>
      const TextResult('');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
