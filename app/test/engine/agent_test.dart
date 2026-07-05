import 'dart:convert';
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
import 'package:dramaflow/src/engine/providers/resolve.dart';
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
    db.execute("INSERT INTO o_prompt (name,type,data,useData) VALUES "
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
    final novelId = engine.addNovels(projectId, const [
      ChapterItem(index: 1, reel: '正文卷', chapter: '一', chapterData: 'x'),
    ]).single;
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
    gateway.turns =
        List.generate(10, (_) => const AgentTurnResult.tool('get_status', {}));
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
    expect(
        engine.agentMessages(projectId).last.content, contains('errLlmFormat'));
  });

  test('Agent 执行模式默认 manual 且持久化到 o_setting', () {
    // 默认（未写入）为 manual → false
    expect(engine.agentUseMode(), isFalse);
    engine.setAgentUseMode(true);
    expect(engine.agentUseMode(), isTrue);
    expect(
      db
          .select("SELECT value FROM o_setting WHERE key='agent.useMode'")
          .single['value'],
      'auto',
    );
    engine.setAgentUseMode(false);
    expect(engine.agentUseMode(), isFalse);
    expect(
      db
          .select("SELECT value FROM o_setting WHERE key='agent.useMode'")
          .single['value'],
      'manual',
    );
  });

  test('技能定义 seed 到 o_skillList，编辑启停后影响传给模型的工具列表', () async {
    final seeded = engine.agentSkills();
    expect(seeded.map((s) => s.id), contains('generate_events'));
    expect(
      db
          .select(
            "SELECT COUNT(*) n FROM o_skillList WHERE type='builtin-agent'",
          )
          .single['n'],
      seeded.length,
    );

    engine.updateAgentSkill(
      'generate_events',
      description: '只为用户指定的章节生成事件摘要。',
      enabled: false,
    );
    final edited = engine
        .agentSkills()
        .singleWhere((skill) => skill.id == 'generate_events');
    expect(edited.description, '只为用户指定的章节生成事件摘要。');
    expect(edited.enabled, isFalse);

    gateway.turns = [const AgentTurnResult.text('收到')];
    await engine.sendAgentMessage(projectId, '列出可用能力', autoMode: false);

    expect(
      gateway.lastTools.map((tool) => tool.name),
      isNot(contains('generate_events')),
    );
    expect(gateway.lastTools.map((tool) => tool.name), contains('get_status'));
  });

  test('自定义脚本技能：暴露为 Agent 工具并执行 return 模板', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_echo',
      name: '自定义回声',
      description: '返回用户传入的 text，验证自定义技能链路。',
      script: r'return `项目${projectId}:${args.text}`;',
      schema: const {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
        },
        'required': ['text'],
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_echo', const {'text': '寒山'})
    ];
    await engine.sendAgentMessage(projectId, '调用自定义技能', autoMode: false);

    expect(gateway.lastTools.map((tool) => tool.name), contains('custom_echo'));
    expect(
      gateway.lastTools
          .singleWhere((tool) => tool.name == 'custom_echo')
          .schema,
      containsPair('required', ['text']),
    );
    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_echo');
    expect(msg.content, '项目$projectId:寒山');
  });

  test(
      'Agent stage registry seeds ToonFlow script/production families without dropping pipeline keys',
      () {
    final keys = engine.agentDeployments().map((item) => item.key).toList();

    expect(
      keys,
      containsAllInOrder([
        'scriptAgent',
        'scriptAgent:decisionAgent',
        'scriptAgent:storySkeletonAgent',
        'scriptAgent:adaptationStrategyAgent',
        'scriptAgent:scriptAgent',
        'scriptAgent:supervisionAgent',
        'productionAgent',
        'productionAgent:decisionAgent',
        'productionAgent:deriveAssetsAgent',
        'productionAgent:generateAssetsAgent',
        'productionAgent:directorPlanAgent',
        'productionAgent:storyboardGenAgent',
        'productionAgent:storyboardPanelAgent',
        'productionAgent:storyboardTableAgent',
        'productionAgent:supervisionAgent',
      ]),
    );
    expect(
      keys,
      containsAll([
        'script_gen',
        'event_extract',
        'asset_extract',
        'storyboard_gen',
        'video_prompt_gen',
      ]),
    );
  });

  test(
      'ToonFlow Agent stage resolves through fallback text binding when deployment row is empty or disabled',
      () async {
    final provider = await engine.createProvider(
      name: 'azt',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );
    await engine.saveProviderModels(provider.id, const [
      {
        'modelId': 'gpt-5.5',
        'label': 'gpt-5.5',
        'kind': 'text',
        'enabled': true,
      },
    ]);
    await engine.setBinding('script_gen', provider.id, 'gpt-5.5');

    final resolved = resolveAgentStage(db, 'scriptAgent:decisionAgent');
    expect(resolved.providerId, provider.id);
    expect(resolved.modelId, 'gpt-5.5');
  });

  test('Agent 部署配置 seed 自阶段绑定，保存后 resolveAgentStage 优先使用部署模型与参数', () async {
    final provider = await engine.createProvider(
      name: 'azt',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );
    await engine.saveProviderModels(provider.id, const [
      {
        'modelId': 'gpt-5.5',
        'label': 'gpt-5.5',
        'kind': 'text',
        'enabled': true,
      },
      {
        'modelId': 'gpt-5.4-mini',
        'label': 'gpt-5.4-mini',
        'kind': 'text',
        'enabled': true,
      },
    ]);
    await engine.setBinding('script_gen', provider.id, 'gpt-5.5');

    final rows = engine.agentDeployments();
    final scriptDeploy =
        rows.singleWhere((deploy) => deploy.key == 'script_gen');
    expect(scriptDeploy.vendorId, 'azt');
    expect(scriptDeploy.modelName, 'gpt-5.5');
    expect(scriptDeploy.maxOutputTokens, 8000);
    expect(scriptDeploy.temperature, 70);
    expect(scriptDeploy.disabled, isFalse);

    engine.updateAgentDeployment(
      'script_gen',
      vendorId: 'azt',
      modelName: 'gpt-5.4-mini',
      maxOutputTokens: 1200,
      temperature: 35,
      disabled: false,
    );

    final resolved = resolveAgentStage(db, 'script_gen');
    expect(resolved.providerId, 'azt');
    expect(resolved.modelId, 'gpt-5.4-mini');
    expect(resolved.maxOutputTokens, 1200);
    expect(resolved.temperature, 35);

    engine.updateAgentDeployment('script_gen', disabled: true);
    final fallback = resolveAgentStage(db, 'script_gen');
    expect(fallback.modelId, 'gpt-5.5');
    expect(fallback.maxOutputTokens, isNull);
  });

  test('长期记忆：保存到 memories，可检索并注入 Agent system prompt', () async {
    final id = engine.saveAgentMemory(
      projectId,
      name: '主角设定',
      content: '寒山少主李澈，外冷内热，不能写成反派。',
    );

    final memories = engine.agentLongTermMemories(projectId);
    expect(memories, hasLength(1));
    expect(memories.single.id, id);
    expect(memories.single.name, '主角设定');
    expect(memories.single.content, contains('寒山少主李澈'));

    final matched = engine.searchAgentMemories(projectId, '寒山');
    expect(matched.map((item) => item.id), [id]);

    gateway.turns = [const AgentTurnResult.text('收到')];
    await engine.sendAgentMessage(projectId, '下一场写寒山少主出场', autoMode: false);

    expect(gateway.lastSystem, contains('长期记忆'));
    expect(gateway.lastSystem, contains('寒山少主李澈'));
  });

  test('长期记忆：ragLimit 设置会限制注入 Agent system prompt 的条数', () async {
    for (var i = 1; i <= 4; i++) {
      engine.saveAgentMemory(
        projectId,
        name: '寒山记忆$i',
        content: '寒山线索$i，全部都应该能被检索到。',
      );
    }
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['ragLimit', '2'],
    );

    gateway.turns = [const AgentTurnResult.text('收到')];
    await engine.sendAgentMessage(projectId, '继续写寒山线索', autoMode: false);

    final injected =
        RegExp(r'^- ', multiLine: true).allMatches(gateway.lastSystem).length;
    expect(injected, 2);
  });

  test('长期记忆：写入本地 embedding，搜索旧记录时自动回填', () {
    final id = engine.saveAgentMemory(
      projectId,
      name: '战力设定',
      content: '李澈是寒山剑修，出手克制，不能滥杀。',
    );
    var row =
        db.select('SELECT embedding FROM memories WHERE id=?', [id]).single;
    expect(row['embedding'], isNot(''));
    expect(row['embedding'], contains('李澈'));

    db.execute('UPDATE memories SET embedding=? WHERE id=?', ['', id]);
    final matched = engine.searchAgentMemories(projectId, '李澈剑修');
    expect(matched.map((item) => item.id), [id]);

    row = db.select('SELECT embedding FROM memories WHERE id=?', [id]).single;
    expect(row['embedding'], isNot(''), reason: '旧记忆检索时应回填本地 embedding');
  });

  test('Agent 记忆：对话写入 memories message 并达到阈值生成 summary', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '2'],
    );
    gateway.turns = [const AgentTurnResult.text('我会记住寒山设定。')];
    gateway.textResults = [
      const TextResult('用户让助手记住寒山设定，助手确认。'),
    ];

    await engine.sendAgentMessage(projectId, '记住：寒山少主李澈不能写成反派',
        autoMode: false);

    final messageRows = db.select(
      'SELECT id,role,content,summarized FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', 'message'],
    );
    expect(messageRows, hasLength(2));
    expect(messageRows.map((row) => row['role']),
        [agentRoleUser, agentRoleAssistant]);
    expect(messageRows.first['content'], contains('寒山少主李澈'));
    expect(messageRows.last['content'], '我会记住寒山设定。');
    expect(messageRows.map((row) => row['summarized']), [1, 1]);

    final summary = db.select(
      'SELECT content,relatedMessageIds FROM memories '
      'WHERE isolationKey=? AND type=?',
      ['scriptAgent:$projectId', 'summary'],
    ).single;
    expect(summary['content'], '用户让助手记住寒山设定，助手确认。');
    expect(jsonDecode(summary['relatedMessageIds'] as String), hasLength(2));
  });

  test('Agent 记忆：deepRetrieve 工具从 summary 展开原始 message', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'msg_user',
        '',
        '用户强调寒山少主李澈外冷内热。',
        now,
        '',
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        1,
        'message',
      ],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'msg_assistant',
        '',
        '助手确认后续剧本不能把李澈写成反派。',
        now + 1,
        '',
        'scriptAgent:$projectId',
        '[]',
        agentRoleAssistant,
        1,
        'message',
      ],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'summary_hanshan',
        '寒山设定摘要',
        '寒山少主李澈外冷内热，不能写成反派。',
        now + 2,
        '',
        'scriptAgent:$projectId',
        jsonEncode(['msg_user', 'msg_assistant']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {'keyword': '寒山'}),
    ];

    await engine.sendAgentMessage(projectId, '找一下寒山相关记忆', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    expect(msg.content, contains('用户强调寒山少主李澈外冷内热'));
    expect(msg.content, contains('不能把李澈写成反派'));
  });
}

class _Gateway implements ProviderGateway {
  List<AgentTurnResult> turns = const [];
  List<TextResult> textResults = const [];
  List<AgentToolDef> lastTools = const [];
  String lastSystem = '';
  List<Map<String, String>> lastMessages = const [];
  int callCount = 0;
  int textCallCount = 0;
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
    lastTools = List<AgentToolDef>.from(tools);
    lastSystem = system;
    lastMessages = [for (final message in messages) Map.of(message)];
    final r = turns[callCount];
    callCount++;
    return r;
  }

  @override
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken}) async {
    if (textCallCount < textResults.length) {
      final result = textResults[textCallCount];
      textCallCount++;
      return result;
    }
    textCallCount++;
    return const TextResult('');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
