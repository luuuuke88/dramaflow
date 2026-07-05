import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/agent.dart';
import 'package:dramaflow/src/engine/agent_memory.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/events.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/novel.dart';
import 'package:dramaflow/src/engine/novel_parse.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/providers/resolve.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/storyboard_table.dart';
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

    final memoryRows = db.select(
      'SELECT role,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', 'message'],
    );
    expect(memoryRows.map((row) => row['role']),
        [agentRoleUser, 'assistant:decision']);
    expect(memoryRows.last['content'], '你好，我可以帮你推进制作流程。');

    engine.clearAgentMemory(projectId);
    expect(engine.agentMessages(projectId), isEmpty);
  });

  test('清空 Agent 记忆会同步删除对应 family 的 message 和 summary 上下文', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '2'],
    );
    gateway.turns = const [
      AgentTurnResult.text('剧本规划已记录。'),
      AgentTurnResult.text('制作规划已记录。'),
    ];
    gateway.textResults = const [
      TextResult('剧本 Agent 摘要。'),
      TextResult('制作 Agent 摘要。'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '规划前三集',
      autoMode: false,
      family: agentFamilyScript,
    );
    await engine.sendAgentMessage(
      projectId,
      '制作画布：生成导演计划',
      autoMode: false,
      family: agentFamilyProduction,
    );

    int memoryCount(String isolationKey) => db.select(
          'SELECT COUNT(*) AS n FROM memories '
          'WHERE isolationKey=? AND type IN (?,?)',
          [isolationKey, 'message', 'summary'],
        ).single['n'] as int;

    expect(memoryCount('scriptAgent:$projectId'), 3);
    expect(memoryCount('productionAgent:$projectId'), 3);

    engine.clearAgentMemory(projectId, family: agentFamilyScript);

    expect(engine.agentMessages(projectId, family: agentFamilyScript), isEmpty);
    expect(memoryCount('scriptAgent:$projectId'), 0);
    expect(engine.agentMessages(projectId, family: agentFamilyProduction),
        isNotEmpty);
    expect(memoryCount('productionAgent:$projectId'), 3);

    engine.clearAgentMemory(projectId);

    expect(engine.agentMessages(projectId, family: agentFamilyProduction),
        isEmpty);
    expect(memoryCount('productionAgent:$projectId'), 0);
  });

  test('clearAgentMemoryScope 按 scope 清理记忆且保留聊天记录', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    gateway.turns = const [
      AgentTurnResult.text('剧本 Agent 已记录。'),
      AgentTurnResult.text('制作 Agent 已记录。'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '剧本侧消息',
      autoMode: false,
      family: agentFamilyScript,
    );
    await engine.sendAgentMessage(
      projectId,
      '制作侧消息',
      autoMode: false,
      family: agentFamilyProduction,
    );
    engine.saveAgentMemory(
      projectId,
      name: '角色守则',
      content: '李澈必须保持正派。',
    );

    void insertSummary(String isolationKey, String id) {
      db.execute(
        'INSERT INTO memories '
        '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          '摘要',
          '$id 摘要内容',
          DateTime.now().millisecondsSinceEpoch,
          embeddingJson('$id 摘要内容'),
          isolationKey,
          '[]',
          agentRoleAssistant,
          0,
          agentMemoryTypeSummary,
        ],
      );
    }

    insertSummary('scriptAgent:$projectId', 'script_manual_summary');
    insertSummary('productionAgent:$projectId', 'production_manual_summary');

    int count(String isolationKey, String type) => db.select(
          'SELECT COUNT(*) AS n FROM memories WHERE isolationKey=? AND type=?',
          [isolationKey, type],
        ).single['n'] as int;

    engine.clearAgentMemoryScope(
      projectId,
      family: agentFamilyScript,
      scope: agentMemoryTypeSummary,
    );

    expect(
        engine.agentMessages(projectId, family: agentFamilyScript), isNotEmpty);
    expect(count('scriptAgent:$projectId', agentMemoryTypeMessage), 2);
    expect(count('scriptAgent:$projectId', agentMemoryTypeSummary), 0);
    expect(count('productionAgent:$projectId', agentMemoryTypeMessage), 2);
    expect(count('productionAgent:$projectId', agentMemoryTypeSummary), 1);
    expect(engine.agentLongTermMemories(projectId), hasLength(1));

    engine.clearAgentMemoryScope(projectId, scope: agentMemoryTypeNote);

    expect(engine.agentLongTermMemories(projectId), isEmpty);
    expect(count('scriptAgent:$projectId', agentMemoryTypeMessage), 2);
    expect(count('productionAgent:$projectId', agentMemoryTypeMessage), 2);

    engine.clearAgentMemoryScope(
      projectId,
      family: agentFamilyScript,
      scope: agentMemoryScopeAll,
    );

    expect(
        engine.agentMessages(projectId, family: agentFamilyScript), isNotEmpty);
    expect(count('scriptAgent:$projectId', agentMemoryTypeMessage), 0);
    expect(count('productionAgent:$projectId', agentMemoryTypeMessage), 2);
  });

  test('agentMemorySummaries 按 family 返回历史摘要', () {
    void insertMemory({
      required String isolationKey,
      required String id,
      required String content,
      required int createTime,
      required String type,
      String role = agentRoleAssistant,
      String relatedMessageIds = '[]',
    }) {
      db.execute(
        'INSERT INTO memories '
        '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          '摘要',
          content,
          createTime,
          embeddingJson(content),
          isolationKey,
          relatedMessageIds,
          role,
          0,
          type,
        ],
      );
    }

    insertMemory(
      isolationKey: 'scriptAgent:$projectId',
      id: 'script_msg_1',
      content: '用户设定李澈来自寒山。',
      createTime: 1,
      type: agentMemoryTypeMessage,
      role: agentRoleUser,
    );
    insertMemory(
      isolationKey: 'scriptAgent:$projectId',
      id: 'script_msg_2',
      content: '助手确认李澈不能写成反派。',
      createTime: 2,
      type: agentMemoryTypeMessage,
    );
    insertMemory(
      isolationKey: 'scriptAgent:$projectId',
      id: 'script_summary_old',
      content: '旧剧本摘要',
      createTime: 3,
      type: agentMemoryTypeSummary,
    );
    insertMemory(
      isolationKey: 'scriptAgent:$projectId',
      id: 'script_summary_new',
      content: '新剧本摘要',
      createTime: 4,
      type: agentMemoryTypeSummary,
      relatedMessageIds: '["script_msg_1","script_msg_2"]',
    );
    insertMemory(
      isolationKey: 'productionAgent:$projectId',
      id: 'production_summary',
      content: '制作摘要',
      createTime: 5,
      type: agentMemoryTypeSummary,
    );

    final scriptSummaries =
        engine.agentMemorySummaries(projectId, family: agentFamilyScript);
    expect(
      scriptSummaries.map((item) => item.content),
      ['新剧本摘要', '旧剧本摘要'],
    );
    expect(scriptSummaries.first.relatedMessageIds,
        ['script_msg_1', 'script_msg_2']);
    expect(
      engine
          .agentMemorySummaryMessages(
            projectId,
            scriptSummaries.first.id,
            family: agentFamilyScript,
          )
          .map((item) => item.content),
      ['用户设定李澈来自寒山。', '助手确认李澈不能写成反派。'],
    );
    expect(
      engine
          .agentMemorySummaries(projectId, family: agentFamilyProduction)
          .map((item) => item.content),
      ['制作摘要'],
    );
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
    expect(
      engine
          .agentMessages(projectId, family: agentFamilyProduction)
          .last
          .content,
      contains('缺少'),
    );
  });

  test('监督 Agent 放行后才执行决策工具调用', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.supervision.enabled', '1'],
    );
    final novelId = engine.addNovels(projectId, const [
      ChapterItem(index: 1, reel: '正文卷', chapter: '一', chapterData: 'x'),
    ]).single;
    gateway.turns = [
      AgentTurnResult.tool('generate_events', {
        'novelIds': [novelId],
      }),
      const AgentTurnResult.text('APPROVE'),
    ];

    await engine.sendAgentMessage(projectId, '生成事件', autoMode: false);

    expect(gateway.stages,
        ['scriptAgent:decisionAgent', 'scriptAgent:supervisionAgent']);
    expect(gateway.textStages, isEmpty);
    expect(engine.agentMessages(projectId).last.toolName, 'generate_events');
    expect(
      db.select('SELECT taskClass FROM o_tasks').map((row) => row['taskClass']),
      contains('event_generation'),
    );
  });

  test('监督 Agent 可拦截决策工具调用且不提交任务', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.supervision.enabled', '1'],
    );
    db.execute(
      'INSERT INTO o_novel '
      '(projectId,chapterIndex,reel,chapter,chapterData,createTime,eventState) '
      'VALUES (?,?,?,?,?,?,0)',
      [projectId, 1, '正文卷', '一', 'x', DateTime.now().millisecondsSinceEpoch],
    );
    gateway.turns = const [
      AgentTurnResult.tool('generate_events', {}),
      AgentTurnResult.text('REJECT: 先调用 get_status 确认章节状态。'),
    ];

    await engine.sendAgentMessage(projectId, '直接批量生成事件', autoMode: false);

    expect(gateway.stages,
        ['scriptAgent:decisionAgent', 'scriptAgent:supervisionAgent']);
    expect(gateway.textStages, isEmpty);
    expect(db.select('SELECT id FROM o_tasks'), isEmpty);
    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleAssistant);
    expect(msg.content, contains('监督 Agent 已拦截 generate_events'));
    expect(msg.content, contains('先调用 get_status'));
  });

  test('监督 Agent 复核工具调用时注入长期记忆和对话记忆上下文', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.supervision.enabled', '1'],
    );
    engine.saveAgentMemory(
      projectId,
      name: '寒山安全规则',
      content: '寒山线工具调用前必须确认章节范围，不能擅自批量生成全部章节。',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'supervision_msg_user',
        '',
        '用户强调寒山少主李澈必须保持正派。',
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
        'supervision_summary',
        '寒山审核规则',
        '寒山线执行工具前要核对范围，李澈必须保持正派。',
        now + 1,
        embeddingJson('寒山线执行工具前要核对范围，李澈必须保持正派。'),
        'scriptAgent:$projectId',
        jsonEncode(['supervision_msg_user']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    final novelId = engine.addNovels(projectId, const [
      ChapterItem(index: 1, reel: '正文卷', chapter: '一', chapterData: 'x'),
    ]).single;
    gateway.textResults = const [
      TextResult('["supervision_summary"]'),
      TextResult('["supervision_summary"]'),
    ];
    gateway.turns = [
      AgentTurnResult.tool('generate_events', {
        'novelIds': [novelId],
      }),
      const AgentTurnResult.text('APPROVE'),
    ];

    await engine.sendAgentMessage(projectId, '生成寒山第1章事件', autoMode: false);

    expect(gateway.stages,
        ['scriptAgent:decisionAgent', 'scriptAgent:supervisionAgent']);
    expect(gateway.lastSystem, contains('剧本监督 Agent'));
    expect(gateway.lastSystem, contains('长期记忆'));
    expect(gateway.lastSystem, contains('不能擅自批量生成全部章节'));
    expect(gateway.lastSystem, contains('Agent 记忆上下文'));
    expect(gateway.lastSystem, contains('相关历史记忆'));
    expect(gateway.lastSystem, contains('李澈必须保持正派'));
  });

  test('制作监督 Agent 复核工具调用时只注入 production 记忆上下文', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.supervision.enabled', '1'],
    );
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    engine.saveAgentMemory(
      projectId,
      name: '制作审核规则',
      content: '寒山制作视频生成前必须确认首帧存在，禁止无首帧直接生成视频。',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'production_supervision_msg',
        '',
        '用户强调寒山视频生成必须先检查首帧图。',
        now,
        '',
        'productionAgent:$projectId',
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
        'production_supervision_summary',
        '制作审核摘要',
        '寒山视频生成前必须确认首帧图已经存在。',
        now + 1,
        embeddingJson('寒山视频生成前必须确认首帧图已经存在。'),
        'productionAgent:$projectId',
        jsonEncode(['production_supervision_msg']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'script_supervision_private',
        '剧本私有审核摘要',
        '这条剧本监督私有记忆不应进入制作监督 Agent。',
        now + 2,
        embeddingJson('剧本监督私有记忆不应进入制作监督 Agent。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    gateway.textResults = const [
      TextResult('["production_supervision_summary"]'),
      TextResult('["production_supervision_summary"]'),
    ];
    gateway.turns = [
      AgentTurnResult.tool('generate_videos', {'scriptId': scriptId}),
      const AgentTurnResult.text('APPROVE'),
    ];

    await engine.sendAgentMessage(projectId, '制作画布：生成寒山视频', autoMode: false);

    expect(gateway.stages,
        ['productionAgent:decisionAgent', 'productionAgent:supervisionAgent']);
    expect(gateway.lastSystem, contains('制作监督 Agent'));
    expect(gateway.lastSystem, contains('长期记忆'));
    expect(gateway.lastSystem, contains('禁止无首帧直接生成视频'));
    expect(gateway.lastSystem, contains('Agent 记忆上下文'));
    expect(gateway.lastSystem, contains('首帧图已经存在'));
    expect(gateway.lastSystem, isNot(contains('剧本监督私有记忆')));
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

  test('Agent 监督模式默认关闭且持久化到 o_setting', () {
    expect(engine.agentSupervisionEnabled(), isFalse);
    engine.setAgentSupervisionEnabled(true);
    expect(engine.agentSupervisionEnabled(), isTrue);
    expect(
      db
          .select(
            "SELECT value FROM o_setting WHERE key='agent.supervision.enabled'",
          )
          .single['value'],
      '1',
    );
    engine.setAgentSupervisionEnabled(false);
    expect(engine.agentSupervisionEnabled(), isFalse);
    expect(
      db
          .select(
            "SELECT value FROM o_setting WHERE key='agent.supervision.enabled'",
          )
          .single['value'],
      '0',
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

  test('自定义脚本技能：保存时可绑定 Agent 归属', () {
    engine.saveCustomAgentSkill(
      id: 'custom_script_decision_only',
      name: '剧本决策专属技能',
      description: '只在剧本决策 Agent 中显示。',
      script: r'return "ok";',
      attribution: 'script_agent_decision',
    );

    final scriptSkills =
        engine.agentSkills(attribution: 'script_agent_decision');
    final productionSkills =
        engine.agentSkills(attribution: 'production_agent_execution');

    expect(scriptSkills.map((skill) => skill.id),
        contains('custom_script_decision_only'));
    expect(productionSkills.map((skill) => skill.id),
        isNot(contains('custom_script_decision_only')));
  });

  test('自定义脚本技能：支持局部变量和常用 JS 表达式', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_runtime',
      name: '脚本运行时',
      description: '验证自定义技能可以执行更接近 ToonFlow 的脚本片段。',
      script: r'''
const text = args.text.trim().toUpperCase();
const count = args.items.length;
return `项目${projectId}:${text}:${count}:${JSON.stringify(args.items)}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
          'items': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_runtime', const {
        'text': ' 寒山 ',
        'items': ['李澈', '试剑'],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_runtime');
    expect(msg.content, '项目$projectId:寒山:2:["李澈","试剑"]');
  });

  test('自定义脚本技能：支持数组 map 和 join 组合表达式', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_array_runtime',
      name: '数组脚本运行时',
      description: '验证自定义技能可以处理 ToonFlow 常见的数组回调脚本。',
      script: r'''
const names = args.items.map(item => item.name.trim()).join('、');
return `角色：${names}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'items': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_array_runtime', const {
        'items': [
          {'name': ' 李澈 '},
          {'name': '沈微'},
        ],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用数组脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_array_runtime');
    expect(msg.content, '角色：李澈、沈微');
  });

  test('自定义脚本技能：支持数组 filter map join 链式表达式', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_filter_runtime',
      name: '筛选脚本运行时',
      description: '验证自定义技能可以筛选资产列表并生成 Agent 可读摘要。',
      script: r'''
const roles = args.assets
  .filter(asset => asset.type.includes('role'))
  .map(asset => asset.name.trim())
  .join('、');
return `角色资产：${roles}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'type': {'type': 'string'},
                'name': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_filter_runtime', const {
        'assets': [
          {'type': 'role.main', 'name': ' 李澈 '},
          {'type': 'scene', 'name': '寒山宗门'},
          {'type': 'role.support', 'name': '沈微'},
        ],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用筛选脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_filter_runtime');
    expect(msg.content, '角色资产：李澈、沈微');
  });

  test('自定义脚本技能：支持比较和逻辑表达式筛选数组', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_logic_runtime',
      name: '逻辑脚本运行时',
      description: '验证自定义技能可以用比较和逻辑表达式筛选生产资产。',
      script: r'''
const roles = args.assets
  .filter(asset => asset.type === 'role' && asset.enabled !== false)
  .map(asset => asset.name.trim())
  .join('、');
return `可用角色：${roles}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'type': {'type': 'string'},
                'name': {'type': 'string'},
                'enabled': {'type': 'boolean'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_logic_runtime', const {
        'assets': [
          {'type': 'role', 'name': ' 李澈 ', 'enabled': true},
          {'type': 'role', 'name': '弃用角色', 'enabled': false},
          {'type': 'scene', 'name': '寒山宗门', 'enabled': true},
          {'type': 'role', 'name': '沈微'},
        ],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用逻辑脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_logic_runtime');
    expect(msg.content, '可用角色：李澈、沈微');
  });

  test('自定义脚本技能：支持数字比较和回调 index 参数', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_numeric_runtime',
      name: '数字脚本运行时',
      description: '验证自定义技能可以用数字比较筛选分镜。',
      script: r'''
const shots = args.shots
  .filter((shot, index) => shot.duration >= 3 && index < 3)
  .map(shot => shot.name.trim())
  .join('、');
return `长镜头：${shots}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'shots': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'duration': {'type': 'number'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_numeric_runtime', const {
        'shots': [
          {'name': ' 开场远景 ', 'duration': 2},
          {'name': '李澈救人', 'duration': 3},
          {'name': '沈微回望', 'duration': 4},
          {'name': '远山收束', 'duration': 5},
        ],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用数字脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_numeric_runtime');
    expect(msg.content, '长镜头：李澈救人、沈微回望');
  });

  test('自定义脚本技能：支持乘除取模计算镜头时长', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_multiplicative_runtime',
      name: '乘除取模脚本运行时',
      description: '验证自定义技能兼容模型常写的秒转毫秒、平均时长和节奏点计算。',
      script: r'''
const totalMs = args.shots
  .reduce((sum, shot) => sum + shot.duration * 1000, 0);
const average = totalMs / args.shots.length;
const evenShots = args.shots
  .filter((shot, index) => index % 2 === 0)
  .map(shot => shot.name.trim())
  .join('、');
return JSON.stringify({
  totalMs: totalMs,
  average: average,
  evenShots: evenShots,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'shots': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'duration': {'type': 'number'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_multiplicative_runtime', const {
        'shots': [
          {'name': ' 开场 ', 'duration': 1.5},
          {'name': '追击', 'duration': 2},
          {'name': ' 回望 ', 'duration': 2.5},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用乘除取模脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_multiplicative_runtime');
    expect(jsonDecode(msg.content), {
      'totalMs': 6000,
      'average': 2000,
      'evenShots': '开场、回望',
    });
  });

  test('自定义脚本技能：支持 Object Array Math 静态工具', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_static_helpers_runtime',
      name: '静态工具脚本运行时',
      description: '验证自定义技能兼容模型常写的 Object.entries、Array.isArray 和 Math.round。',
      script: r'''
const groupSummary = Object.entries(args.groups)
  .filter(entry => Array.isArray(entry[1]))
  .map(entry => `${entry[0]}:${entry[1].map(item => item.name.trim()).join('/')}`)
  .join('、');
const keys = Object.keys(args.groups).join('|');
const valuesCount = Object.values(args.groups)
  .filter(value => Array.isArray(value))
  .reduce((sum, value) => sum + value.length, 0);
const average = Math.round(args.shots
  .reduce((sum, shot) => sum + shot.duration, 0) / args.shots.length * 10) / 10;
return JSON.stringify({
  keys: keys,
  groupSummary: groupSummary,
  valuesCount: valuesCount,
  average: average,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'groups': {'type': 'object'},
          'shots': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'duration': {'type': 'number'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_static_helpers_runtime', const {
        'groups': {
          'role': [
            {'name': ' 李澈 '},
            {'name': '沈微'},
          ],
          'scene': [
            {'name': ' 寒山宗门 '},
          ],
          'meta': {'ignored': true},
        },
        'shots': [
          {'duration': 1.2},
          {'duration': 2.4},
          {'duration': 2.5},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用静态工具脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_static_helpers_runtime');
    expect(jsonDecode(msg.content), {
      'keys': 'role|scene|meta',
      'groupSummary': 'role:李澈/沈微、scene:寒山宗门',
      'valuesCount': 3,
      'average': 2,
    });
  });

  test('自定义脚本技能：支持回调数组解构处理 Object.entries', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_destructure_runtime',
      name: '解构脚本运行时',
      description: '验证自定义技能兼容模型常写的 ([key, value]) => ... 回调参数。',
      script: r'''
const groupSummary = Object.entries(args.groups)
  .filter(([type, items]) => Array.isArray(items) && type !== 'meta')
  .map(([type, items], index) => `${index + 1}.${type}:${items.map(item => item.name.trim()).join('/')}`)
  .join('、');
const totalRefs = Object.entries(args.groups)
  .reduce((sum, [type, items]) => sum + (Array.isArray(items) ? items.length : 0), 0);
return JSON.stringify({
  groupSummary: groupSummary,
  totalRefs: totalRefs,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'groups': {'type': 'object'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_destructure_runtime', const {
        'groups': {
          'role': [
            {'name': ' 李澈 '},
            {'name': '沈微'},
          ],
          'scene': [
            {'name': ' 寒山宗门 '},
          ],
          'meta': {'ignored': true},
        },
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用解构脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_destructure_runtime');
    expect(jsonDecode(msg.content), {
      'groupSummary': '1.role:李澈/沈微、2.scene:寒山宗门',
      'totalRefs': 3,
    });
  });

  test('自定义脚本技能：支持块状箭头回调 return', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_block_callback_runtime',
      name: '块状回调脚本运行时',
      description: '验证自定义技能兼容模型常写的 item => { return ...; } 回调。',
      script: r'''
const labels = args.assets
  .filter(asset => {
    return asset.enabled !== false;
  })
  .sort((a, b) => {
    return b.priority - a.priority;
  })
  .map((asset, index) => {
    return {
      order: index + 1,
      name: asset.name.trim(),
      label: `${asset.type}:${asset.name.trim()}`,
    };
  });
return JSON.stringify(labels);
''',
      schema: const {
        'type': 'object',
        'properties': {
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'type': {'type': 'string'},
                'name': {'type': 'string'},
                'priority': {'type': 'number'},
                'enabled': {'type': 'boolean'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_block_callback_runtime', const {
        'assets': [
          {
            'type': 'role',
            'name': ' 李澈 ',
            'priority': 30,
            'enabled': true,
          },
          {
            'type': 'tool',
            'name': '弃用道具',
            'priority': 90,
            'enabled': false,
          },
          {
            'type': 'scene',
            'name': ' 寒山宗门 ',
            'priority': 50,
            'enabled': true,
          },
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用块状回调脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_block_callback_runtime');
    expect(jsonDecode(msg.content), [
      {
        'order': 1,
        'name': '寒山宗门',
        'label': 'scene:寒山宗门',
      },
      {
        'order': 2,
        'name': '李澈',
        'label': 'role:李澈',
      },
    ]);
  });

  test('自定义脚本技能：支持括号分组逻辑表达式', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_group_runtime',
      name: '分组脚本运行时',
      description: '验证自定义技能可以用括号组合复杂筛选条件。',
      script: r'''
const names = args.assets
  .filter(asset => (asset.type === 'role' || asset.type === 'scene') && asset.enabled !== false)
  .map(asset => asset.name.trim())
  .join('、');
return `可用资产：${names}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'type': {'type': 'string'},
                'name': {'type': 'string'},
                'enabled': {'type': 'boolean'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_group_runtime', const {
        'assets': [
          {'type': 'role', 'name': ' 李澈 ', 'enabled': true},
          {'type': 'scene', 'name': '寒山宗门', 'enabled': true},
          {'type': 'tool', 'name': '灵剑', 'enabled': true},
          {'type': 'role', 'name': '弃用角色', 'enabled': false},
        ],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用分组脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_group_runtime');
    expect(msg.content, '可用资产：李澈、寒山宗门');
  });

  test('自定义脚本技能：支持三元表达式映射资产标签', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_ternary_runtime',
      name: '三元脚本运行时',
      description: '验证自定义技能可以用三元表达式处理缺省字段和标签。',
      script: r'''
const labels = args.assets
  .map(asset => `${asset.name.trim()}(${asset.type === 'role' ? '角色' : asset.type === 'scene' ? '场景' : '其他'})`)
  .join('、');
return `资产标签：${labels}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'type': {'type': 'string'},
                'name': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_ternary_runtime', const {
        'assets': [
          {'type': 'role', 'name': ' 李澈 '},
          {'type': 'scene', 'name': '寒山宗门'},
          {'type': 'tool', 'name': '灵剑'},
        ],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用三元脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_ternary_runtime');
    expect(msg.content, '资产标签：李澈(角色)、寒山宗门(场景)、灵剑(其他)');
  });

  test('自定义脚本技能：支持对象和数组字面量返回结构化 JSON', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_literal_runtime',
      name: '结构化脚本运行时',
      description: '验证自定义技能可以构造 ToonFlow 常见的分镜/资产 JSON 结构。',
      script: r'''
const shots = args.storyboards.map((shot, index) => ({
  order: index + 1,
  name: shot.name.trim(),
  prompt: `${shot.desc.trim()}｜${shot.duration >= 3 ? '长镜头' : '短镜头'}`,
}));
return JSON.stringify({
  projectId: projectId,
  shots: shots,
  tags: ['storyboard', args.mode],
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'mode': {'type': 'string'},
          'storyboards': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'desc': {'type': 'string'},
                'duration': {'type': 'number'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_literal_runtime', const {
        'mode': '短剧',
        'storyboards': [
          {'name': ' 开场 ', 'desc': '寒山雪夜', 'duration': 2},
          {'name': ' 对峙 ', 'desc': '李澈拔剑', 'duration': 4},
        ],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用结构化脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_literal_runtime');
    final decoded = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(decoded['projectId'], projectId);
    expect(decoded['tags'], ['storyboard', '短剧']);
    expect(decoded['shots'], [
      {
        'order': 1,
        'name': '开场',
        'prompt': '寒山雪夜｜短镜头',
      },
      {
        'order': 2,
        'name': '对峙',
        'prompt': '李澈拔剑｜长镜头',
      },
    ]);
  });

  test('自定义脚本技能：短路表达式返回 JS 风格操作数', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_short_circuit_runtime',
      name: '短路脚本运行时',
      description: '验证自定义技能兼容模型常写的 args.assets || [] fallback。',
      script: r'''
const assets = args.assets || [];
const mode = args.mode && args.mode.trim();
const names = assets
  .map(asset => asset.name || '未命名')
  .join('、');
return JSON.stringify({
  mode: mode,
  names: names,
  missing: args.missing || '默认值',
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'mode': {'type': 'string'},
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_short_circuit_runtime', const {
        'mode': ' 短剧 ',
        'assets': [
          {'name': '李澈'},
          <String, Object?>{},
          {'name': '沈微'},
        ],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用短路脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_short_circuit_runtime');
    expect(jsonDecode(msg.content), {
      'mode': '短剧',
      'names': '李澈、未命名、沈微',
      'missing': '默认值',
    });
  });

  test('自定义脚本技能：支持可选链和空值合并 fallback', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_optional_runtime',
      name: '可选链脚本运行时',
      description: '验证自定义技能兼容模型常写的 ?. 和 ?? 防空写法。',
      script: r'''
const names = args.assets
  ?.map(asset => asset.name?.trim() ?? '未命名')
  .join('、') ?? '无资产';
const firstTag = args.assets?.[0]?.tags?.[0] ?? '无标签';
return JSON.stringify({
  names: names,
  firstTag: firstTag,
  missing: args.missing?.trim() ?? '默认值',
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'tags': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_optional_runtime', const {
        'assets': [
          {
            'name': ' 李澈 ',
            'tags': ['主角'],
          },
          <String, Object?>{},
          {'name': '沈微'},
        ],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用可选链脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_optional_runtime');
    expect(jsonDecode(msg.content), {
      'names': '李澈、未命名、沈微',
      'firstTag': '主角',
      'missing': '默认值',
    });
  });

  test('自定义脚本技能：支持对象和数组展开语法整理资产', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_spread_runtime',
      name: '展开脚本运行时',
      description: '验证自定义技能兼容模型常写的 ...asset 和数组展开写法。',
      script: r'''
const normalized = args.assets.map(asset => ({
  ...asset,
  name: asset.name?.trim() ?? '未命名',
  tags: [...(asset.tags ?? []), '短剧'],
}));
return JSON.stringify(normalized);
''',
      schema: const {
        'type': 'object',
        'properties': {
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'type': {'type': 'string'},
                'name': {'type': 'string'},
                'tags': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_spread_runtime', const {
        'assets': [
          {
            'type': 'role',
            'name': ' 李澈 ',
            'tags': ['主角'],
          },
          {
            'type': 'scene',
          },
        ],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用展开脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_spread_runtime');
    expect(jsonDecode(msg.content), [
      {
        'type': 'role',
        'name': '李澈',
        'tags': ['主角', '短剧'],
      },
      {
        'type': 'scene',
        'name': '未命名',
        'tags': ['短剧'],
      },
    ]);
  });

  test('自定义脚本技能：支持一元逻辑表达式筛选资产', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_unary_runtime',
      name: '一元逻辑脚本运行时',
      description: '验证自定义技能兼容模型常写的 !asset.disabled 和 !!value。',
      script: r'''
const names = args.assets
  .filter(asset => !asset.disabled && !!asset.name?.trim())
  .map(asset => asset.name.trim())
  .join('、');
return JSON.stringify({
  names: names,
  hasDraft: !!args.draft,
  empty: !args.assets.length,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'draft': {'type': 'string'},
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'disabled': {'type': 'boolean'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_unary_runtime', const {
        'draft': '有草稿',
        'assets': [
          {'name': ' 李澈 ', 'disabled': false},
          {'name': '弃用角色', 'disabled': true},
          {'name': '   ', 'disabled': false},
          {'name': '沈微'},
        ],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用一元逻辑脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_unary_runtime');
    expect(jsonDecode(msg.content), {
      'names': '李澈、沈微',
      'hasDraft': true,
      'empty': false,
    });
  });

  test('自定义脚本技能：支持 if else 控制流提前返回', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_if_else_runtime',
      name: '分支脚本运行时',
      description: '验证自定义技能兼容模型常写的 if/else 分支返回。',
      script: r'''
if (args.assets.length === 0) {
  return '缺少资产';
} else {
  return `已收到 ${args.assets.length} 个资产`;
}
''',
      schema: const {
        'type': 'object',
        'properties': {
          'assets': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_if_else_runtime', const {
        'assets': [
          {'name': '李澈'},
          {'name': '寒山宗门'},
        ],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用分支脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_if_else_runtime');
    expect(msg.content, '已收到 2 个资产');
  });

  test('自定义脚本技能：支持 for of 遍历分镜并累计结果', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_for_of_runtime',
      name: '循环脚本运行时',
      description: '验证自定义技能兼容模型常写的 for...of 分镜遍历。',
      script: r'''
let totalDuration = 0;
let names = [];
for (const shot of args.storyboards) {
  if (!shot.videoDesc?.trim()) {
    return `第 ${shot.index} 镜缺少描述`;
  }
  totalDuration = totalDuration + shot.duration;
  names = [...names, `${shot.index}.${shot.videoDesc.trim()}`];
}
return JSON.stringify({
  totalDuration,
  names: names.join('、'),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'storyboards': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'index': {'type': 'number'},
                'videoDesc': {'type': 'string'},
                'duration': {'type': 'number'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_for_of_runtime', const {
        'storyboards': [
          {'index': 1, 'videoDesc': ' 雪夜山门 ', 'duration': 3},
          {'index': 2, 'videoDesc': '李澈拔剑', 'duration': 4},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用循环脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_for_of_runtime');
    expect(jsonDecode(msg.content), {
      'totalDuration': 7,
      'names': '1.雪夜山门、2.李澈拔剑',
    });
  });

  test('自定义脚本技能：支持传统 for 循环与 break continue', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_for_runtime',
      name: '计数循环脚本运行时',
      description: '验证自定义技能兼容模型常写的 for/i++/break/continue。',
      script: r'''
let selected = [];
let totalDuration = 0;
for (let i = 0; i < args.storyboards.length; i++) {
  const shot = args.storyboards[i];
  if (shot.disabled) {
    continue;
  }
  if (selected.length >= args.limit) {
    break;
  }
  totalDuration = totalDuration + shot.duration;
  selected = [...selected, `${i + 1}.${shot.videoDesc.trim()}`];
}
return JSON.stringify({
  totalDuration,
  selected: selected.join('、'),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'limit': {'type': 'number'},
          'storyboards': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'videoDesc': {'type': 'string'},
                'duration': {'type': 'number'},
                'disabled': {'type': 'boolean'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_for_runtime', const {
        'limit': 2,
        'storyboards': [
          {'videoDesc': ' 雪夜山门 ', 'duration': 3},
          {'videoDesc': '废弃镜头', 'duration': 10, 'disabled': true},
          {'videoDesc': '李澈拔剑', 'duration': 4},
          {'videoDesc': '掌门入场', 'duration': 8},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用计数循环脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_for_runtime');
    expect(jsonDecode(msg.content), {
      'totalDuration': 7,
      'selected': '1.雪夜山门、3.李澈拔剑',
    });
  });

  test('自定义脚本技能：支持数组 push 裸方法调用收集结果', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_push_runtime',
      name: '数组追加脚本运行时',
      description: '验证自定义技能兼容模型常写的 selected.push(...) 语句。',
      script: r'''
const selected = [];
for (const shot of args.storyboards) {
  if (!shot.videoDesc?.trim()) {
    continue;
  }
  selected.push({
    index: shot.index,
    desc: shot.videoDesc.trim(),
  });
}
return JSON.stringify({
  count: selected.length,
  names: selected.map(shot => `${shot.index}.${shot.desc}`).join('、'),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'storyboards': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'index': {'type': 'number'},
                'videoDesc': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_push_runtime', const {
        'storyboards': [
          {'index': 1, 'videoDesc': ' 雪夜山门 '},
          {'index': 2, 'videoDesc': ''},
          {'index': 3, 'videoDesc': '李澈拔剑'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用数组追加脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_push_runtime');
    expect(jsonDecode(msg.content), {
      'count': 2,
      'names': '1.雪夜山门、3.李澈拔剑',
    });
  });

  test('自定义脚本技能：支持 forEach 块状回调累计结果', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_foreach_runtime',
      name: 'forEach 累计脚本运行时',
      description: '验证自定义技能兼容模型常写的 forEach + push 块状回调。',
      script: r'''
const selected = [];
args.storyboards.forEach((shot, index) => {
  if (shot.disabled || !shot.videoDesc?.trim()) {
    return;
  }
  selected.push(`${index + 1}.${shot.videoDesc.trim()}:${shot.duration ?? 1}s`);
});
return `可生成分镜：${selected.join('、')}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'storyboards': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'videoDesc': {'type': 'string'},
                'duration': {'type': 'number'},
                'disabled': {'type': 'boolean'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_foreach_runtime', const {
        'storyboards': [
          {'videoDesc': ' 雪夜山门 ', 'duration': 3},
          {'videoDesc': '跳过镜头', 'duration': 2, 'disabled': true},
          {'videoDesc': '李澈拔剑'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 forEach 累计脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_foreach_runtime');
    expect(msg.content, '可生成分镜：1.雪夜山门:3s、3.李澈拔剑:1s');
  });

  test('自定义脚本技能：支持复合赋值和自增累计分镜指标', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_compound_runtime',
      name: '复合赋值脚本运行时',
      description: '验证自定义技能兼容模型常写的 total += x 和 count++ 累计语句。',
      script: r'''
let total = 0;
let usable = 0;
args.storyboards.forEach(shot => {
  if (shot.disabled || !shot.videoDesc?.trim()) {
    return;
  }
  total += shot.duration ?? 1;
  usable++;
});
return JSON.stringify({
  total,
  usable,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'storyboards': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'videoDesc': {'type': 'string'},
                'duration': {'type': 'number'},
                'disabled': {'type': 'boolean'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_compound_runtime', const {
        'storyboards': [
          {'videoDesc': ' 雪夜山门 ', 'duration': 3},
          {'videoDesc': '跳过镜头', 'duration': 8, 'disabled': true},
          {'videoDesc': '李澈拔剑'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用复合赋值脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_compound_runtime');
    expect(msg.content, '{"total":4,"usable":2}');
  });

  test('自定义脚本技能：支持顶层对象解构声明读取 args', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_top_object_destructure_runtime',
      name: '顶层对象解构脚本运行时',
      description: '验证自定义技能兼容模型常写的 const { field = x } = args 声明。',
      script: r'''
const { storyboards = [], projectName: name = '未命名项目' } = args;
const titles = storyboards
  .filter(({ videoDesc }) => !!videoDesc?.trim())
  .map(({ videoDesc }, index) => `${index + 1}.${videoDesc.trim()}`)
  .join('、');
return `${name}:${storyboards.length}:${titles}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'projectName': {'type': 'string'},
          'storyboards': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'videoDesc': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool(
          'custom_script_top_object_destructure_runtime', const {
        'storyboards': [
          {'videoDesc': ' 雪夜山门 '},
          {'videoDesc': ''},
          {'videoDesc': '李澈拔剑'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用顶层对象解构脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_top_object_destructure_runtime');
    expect(msg.content, '未命名项目:3:1.雪夜山门、2.李澈拔剑');
  });

  test('自定义脚本技能：支持对象解构回调参数整理分镜', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_object_destructure_runtime',
      name: '对象解构脚本运行时',
      description: '验证自定义技能兼容模型常写的 ({ field }) => ... 参数。',
      script: r'''
const names = args.storyboards
  .filter(({ videoDesc }) => !!videoDesc?.trim())
  .map(({ index, videoDesc, duration }) =>
    `${index}.${videoDesc.trim()}:${duration}s`)
  .join('、');
return `可用分镜：${names}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'storyboards': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'index': {'type': 'number'},
                'videoDesc': {'type': 'string'},
                'duration': {'type': 'number'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_object_destructure_runtime', const {
        'storyboards': [
          {'index': 1, 'videoDesc': ' 雪夜山门 ', 'duration': 3},
          {'index': 2, 'videoDesc': '', 'duration': 2},
          {'index': 3, 'videoDesc': '李澈拔剑', 'duration': 4},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用对象解构脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_object_destructure_runtime');
    expect(msg.content, '可用分镜：1.雪夜山门:3s、3.李澈拔剑:4s');
  });

  test('自定义脚本技能：支持对象解构别名和默认值', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_object_alias_runtime',
      name: '对象解构别名脚本运行时',
      description: '验证自定义技能兼容模型常写的 ({ field: alias, value = x })。',
      script: r'''
const names = args.storyboards
  .map(({ index: shotIndex, videoDesc: desc, duration = 1 }) =>
    `${shotIndex}.${desc.trim()}:${duration}s`)
  .join('、');
return `分镜摘要：${names}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'storyboards': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'index': {'type': 'number'},
                'videoDesc': {'type': 'string'},
                'duration': {'type': 'number'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_object_alias_runtime', const {
        'storyboards': [
          {'index': 1, 'videoDesc': ' 雪夜山门 ', 'duration': 3},
          {'index': 2, 'videoDesc': '李澈拔剑'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用对象解构别名脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_object_alias_runtime');
    expect(msg.content, '分镜摘要：1.雪夜山门:3s、2.李澈拔剑:1s');
  });

  test('自定义脚本技能：支持 sort 和 slice 选择重点资产', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_sort_slice_runtime',
      name: '排序截断脚本运行时',
      description: '验证自定义技能兼容模型常写的 sort/slice 资产优先级处理。',
      script: r'''
const topRoles = args.assets
  .filter(asset => asset.type === 'role')
  .sort((a, b) => b.priority - a.priority)
  .slice(0, 2)
  .map((asset, index) => `${index + 1}.${asset.name.trim()}:${asset.priority}`)
  .join('、');
return `重点角色：${topRoles}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'type': {'type': 'string'},
                'name': {'type': 'string'},
                'priority': {'type': 'number'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_sort_slice_runtime', const {
        'assets': [
          {'type': 'role', 'name': ' 李澈 ', 'priority': 30},
          {'type': 'scene', 'name': '寒山宗门', 'priority': 90},
          {'type': 'role', 'name': '沈微', 'priority': 50},
          {'type': 'role', 'name': '掌门', 'priority': 10},
        ],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用排序截断脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_sort_slice_runtime');
    expect(msg.content, '重点角色：1.沈微:50、2.李澈:30');
  });

  test('自定义脚本技能：支持 find some every 检查资产完整度', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_find_some_every_runtime',
      name: '查找检查脚本运行时',
      description: '验证自定义技能兼容模型常写的 find/some/every 资产检查。',
      script: r'''
const mainRole = args.assets
  .find(asset => asset.type === 'role' && asset.main === true)
  ?.name?.trim() ?? '无主角';
const hasScene = args.assets.some(asset => asset.type === 'scene');
const allNamed = args.assets.every(asset => !!asset.name?.trim());
return JSON.stringify({
  mainRole: mainRole,
  hasScene: hasScene,
  allNamed: allNamed,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'type': {'type': 'string'},
                'name': {'type': 'string'},
                'main': {'type': 'boolean'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_find_some_every_runtime', const {
        'assets': [
          {'type': 'role', 'name': ' 李澈 ', 'main': true},
          {'type': 'scene', 'name': '寒山宗门'},
          {'type': 'tool', 'name': ''},
        ],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用查找检查脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_find_some_every_runtime');
    expect(jsonDecode(msg.content), {
      'mainRole': '李澈',
      'hasScene': true,
      'allNamed': false,
    });
  });

  test('自定义脚本技能：支持 reduce 汇总分镜时长和资产名称', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_reduce_runtime',
      name: '归并脚本运行时',
      description: '验证自定义技能兼容模型常写的 reduce 汇总逻辑。',
      script: r'''
const totalDuration = args.shots
  .reduce((sum, shot) => sum + shot.duration, 0);
const names = args.assets
  .reduce((list, asset) => [...list, asset.name.trim()], [])
  .join('、');
return JSON.stringify({
  totalDuration: totalDuration,
  names: names,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'shots': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'duration': {'type': 'number'},
              },
            },
          },
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_reduce_runtime', const {
        'shots': [
          {'duration': 2},
          {'duration': 3},
          {'duration': 4},
        ],
        'assets': [
          {'name': ' 李澈 '},
          {'name': '沈微'},
        ],
      }),
    ];

    await engine.sendAgentMessage(projectId, '调用归并脚本运行时技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_reduce_runtime');
    expect(jsonDecode(msg.content), {
      'totalDuration': 9,
      'names': '李澈、沈微',
    });
  });

  test('自定义脚本技能：支持 flatMap 展开嵌套分镜参考图', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_flat_map_runtime',
      name: '嵌套分镜展开脚本运行时',
      description: '验证自定义技能兼容模型常写的 flatMap 嵌套资产展开逻辑。',
      script: r'''
const refs = args.storyboards
  .flatMap((shot, shotIndex) => shot.references.map((ref) => ({
    shot: shotIndex + 1,
    name: ref.name.trim(),
  })))
  .map(ref => `${ref.shot}.${ref.name}`)
  .join('、');
return `参考图：${refs}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'storyboards': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'references': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'name': {'type': 'string'},
                    },
                  },
                },
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_flat_map_runtime', const {
        'storyboards': [
          {
            'references': [
              {'name': ' 李澈正脸 '},
              {'name': '寒山宗门'},
            ],
          },
          {
            'references': [
              {'name': ' 沈微侧脸 '},
            ],
          },
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用嵌套分镜展开脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_flat_map_runtime');
    expect(msg.content, '参考图：1.李澈正脸、1.寒山宗门、2.沈微侧脸');
  });

  test('SkillRuntime parses Markdown frontmatter and filters by attribution',
      () {
    final skillFile = _writeSkillFixture(
      dir,
      id: 'style_polisher',
      body: '''
请保持短剧文风克制，不要滥用旁白。

## 规则

- 角色台词要短。
''',
    );

    final skill = engine.saveMarkdownAgentSkill(
      filePath: skillFile.path,
      attribution: 'script_agent_decision',
    );

    expect(skill.id, 'style_polisher');
    expect(skill.name, 'style_polisher');
    expect(skill.description, '短剧文风润色技能');
    expect(skill.type, 'markdown-agent');

    final filtered = engine.agentSkills(attribution: 'script_agent_decision');
    expect(filtered.map((item) => item.id), contains('style_polisher'));
    expect(
      engine.agentSkills(attribution: 'production_agent_execution'),
      isNot(contains(predicate<AgentSkill>((s) => s.id == 'style_polisher'))),
    );
  });

  test('SkillRuntime activate_skill returns Markdown body for Agent context',
      () {
    final skillFile = _writeSkillFixture(
      dir,
      id: 'style_polisher',
      body: '''
请保持短剧文风克制，不要滥用旁白。

## 规则

- 角色台词要短。
''',
    );
    engine.saveMarkdownAgentSkill(
      filePath: skillFile.path,
      attribution: 'script_agent_decision',
    );

    final activated = engine.activateAgentSkill('style_polisher');

    expect(activated.id, 'style_polisher');
    expect(activated.description, '短剧文风润色技能');
    expect(activated.content, contains('角色台词要短'));
    expect(activated.content, isNot(contains('---')));
  });

  test('SkillRuntime activate_skill lists bundled Markdown resources',
      () async {
    final skillFile = _writeSkillFixture(
      dir,
      id: 'style_polisher',
      body: '技能正文：短剧台词要短。',
      extraFiles: {
        'references/rules.md': '规则：每句台词不超过二十字。',
        'references/tone.md': '语气：克制。',
      },
    );
    engine.saveMarkdownAgentSkill(filePath: skillFile.path);

    final activated = engine.activateAgentSkill('style_polisher');
    expect(activated.resourceFiles, [
      'references/rules.md',
      'references/tone.md',
    ]);

    gateway.turns = [
      AgentTurnResult.tool('activate_skill', const {'name': 'style_polisher'}),
    ];
    await engine.sendAgentMessage(projectId, '激活文风技能', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    expect(msg.toolName, 'activate_skill');
    expect(msg.content, startsWith('<skill_content name="style_polisher">'));
    expect(msg.content, contains('使用 read_skill_file 工具读取资源文件。'));
    expect(msg.content, contains('<skill_resources>'));
    expect(msg.content, contains('<file>references/rules.md</file>'));
    expect(msg.content, contains('<file>references/tone.md</file>'));
    expect(msg.content, contains('</skill_resources>'));
    expect(msg.content, endsWith('</skill_content>'));
  });

  test('SkillRuntime read_skill_file reads only files under skill root', () {
    final skillFile = _writeSkillFixture(
      dir,
      id: 'style_polisher',
      body: '正文技能内容',
      extraFiles: {
        'references/rules.md': '规则：不能把李澈写成反派。',
      },
    );
    engine.saveMarkdownAgentSkill(filePath: skillFile.path);

    expect(
      engine.readAgentSkillFile('style_polisher', 'references/rules.md'),
      '规则：不能把李澈写成反派。',
    );
    expect(
      () => engine.readAgentSkillFile('style_polisher', '../secret.md'),
      throwsA(isA<EngineException>()),
    );
  });

  test('SkillRuntime exposes activate_skill and read_skill_file as Agent tools',
      () async {
    final skillFile = _writeSkillFixture(
      dir,
      id: 'style_polisher',
      body: '技能正文：短剧台词要短。',
      extraFiles: {
        'references/rules.md': '规则：每句台词不超过二十字。',
      },
    );
    engine.saveMarkdownAgentSkill(filePath: skillFile.path);

    gateway.turns = [
      AgentTurnResult.tool('activate_skill', const {'name': 'style_polisher'}),
    ];
    await engine.sendAgentMessage(projectId, '激活文风技能', autoMode: false);

    expect(gateway.lastTools.map((tool) => tool.name),
        containsAll(['activate_skill', 'read_skill_file']));
    final readSkillTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'read_skill_file');
    final readSkillProperties =
        Map<String, dynamic>.from(readSkillTool.schema['properties'] as Map);
    expect(readSkillTool.schema['required'], ['filePath']);
    expect(readSkillProperties, contains('filePath'));
    var msg = engine.agentMessages(projectId).last;
    expect(msg.toolName, 'activate_skill');
    expect(msg.content, contains('技能正文：短剧台词要短'));

    gateway.turns = [
      AgentTurnResult.tool('read_skill_file', const {
        'filePath': 'references/rules.md',
      }),
    ];
    await engine.sendAgentMessage(projectId, '读取技能规则', autoMode: false);

    msg = engine.agentMessages(projectId).last;
    expect(msg.toolName, 'read_skill_file');
    expect(msg.content, startsWith('<skill_content>'));
    expect(msg.content, contains('规则：每句台词不超过二十字。'));
    expect(msg.content, contains('可以使用 read_skill_file 工具读取资源文件。'));
    expect(msg.content, endsWith('</skill_content>'));
  });

  test('SkillRuntime read_skill_file reports missing filePath parameter',
      () async {
    final skillFile = _writeSkillFixture(
      dir,
      id: 'style_polisher',
      body: '技能正文。',
    );
    engine.saveMarkdownAgentSkill(filePath: skillFile.path);

    gateway.turns = [
      AgentTurnResult.tool('activate_skill', const {'name': 'style_polisher'}),
      AgentTurnResult.tool('read_skill_file', const {}),
    ];
    await engine.sendAgentMessage(projectId, '激活后误读资源', autoMode: true);

    final msg = engine
        .agentMessages(projectId)
        .lastWhere((message) => message.toolName == 'read_skill_file');
    expect(msg.toolName, 'read_skill_file');
    expect(msg.content, '缺少 filePath 参数。');
  });

  test('SkillRuntime activate_skill schema lists stage-visible Markdown skills',
      () async {
    final scriptSkillFile = _writeSkillFixture(
      dir,
      id: 'style_polisher',
      body: '剧本技能正文。',
    );
    final productionSkillFile = _writeSkillFixture(
      dir,
      id: 'director_checker',
      body: '制作技能正文。',
    );
    engine.saveMarkdownAgentSkill(
      filePath: scriptSkillFile.path,
      attribution: 'script_agent_decision',
    );
    engine.saveMarkdownAgentSkill(
      filePath: productionSkillFile.path,
      attribution: 'production_agent_decision',
    );

    gateway.turns = [const AgentTurnResult.text('剧本规划已记录。')];
    await engine.sendAgentMessage(
      projectId,
      '规划前三集',
      autoMode: false,
      family: agentFamilyScript,
    );

    var activateTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'activate_skill');
    var nameSchema = Map<String, dynamic>.from(
      Map<String, dynamic>.from(
          activateTool.schema['properties'] as Map)['name'] as Map,
    );
    expect(activateTool.description, contains('style_polisher'));
    expect(activateTool.description, isNot(contains('director_checker')));
    expect(nameSchema['enum'], ['style_polisher']);

    gateway.turns = [const AgentTurnResult.text('制作规划已记录。')];
    await engine.sendAgentMessage(
      projectId,
      '制作导演计划',
      autoMode: false,
      family: agentFamilyProduction,
    );

    activateTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'activate_skill');
    nameSchema = Map<String, dynamic>.from(
      Map<String, dynamic>.from(
          activateTool.schema['properties'] as Map)['name'] as Map,
    );
    expect(activateTool.description, contains('director_checker'));
    expect(activateTool.description, isNot(contains('style_polisher')));
    expect(nameSchema['enum'], ['director_checker']);
  });

  test('SkillRuntime lists stage-visible Markdown skills in system prompt',
      () async {
    final scriptSkillFile = _writeSkillFixture(
      dir,
      id: 'style_polisher',
      body: '剧本技能正文。',
    );
    final productionSkillFile = _writeSkillFixture(
      dir,
      id: 'director_checker',
      body: '制作技能正文。',
    );
    engine.saveMarkdownAgentSkill(
      filePath: scriptSkillFile.path,
      attribution: 'script_agent_decision',
    );
    engine.saveMarkdownAgentSkill(
      filePath: productionSkillFile.path,
      attribution: 'production_agent_decision',
    );

    gateway.turns = [const AgentTurnResult.text('剧本规划已记录。')];
    await engine.sendAgentMessage(
      projectId,
      '规划前三集',
      autoMode: false,
      family: agentFamilyScript,
    );

    expect(gateway.lastSystem, contains('## Skills'));
    expect(gateway.lastSystem, contains('<available_skills>'));
    expect(gateway.lastSystem, contains('<name>style_polisher</name>'));
    expect(
      gateway.lastSystem,
      contains('<description>短剧文风润色技能</description>'),
    );
    expect(gateway.lastSystem, contains('</available_skills>'));
    expect(gateway.lastSystem, isNot(contains('director_checker')));

    gateway.turns = [const AgentTurnResult.text('制作规划已记录。')];
    await engine.sendAgentMessage(
      projectId,
      '制作导演计划',
      autoMode: false,
      family: agentFamilyProduction,
    );

    expect(gateway.lastSystem, contains('## Skills'));
    expect(gateway.lastSystem, contains('<available_skills>'));
    expect(gateway.lastSystem, contains('<name>director_checker</name>'));
    expect(gateway.lastSystem, isNot(contains('style_polisher')));
  });

  test('SkillRuntime skips repeated activate_skill content injection',
      () async {
    final skillFile = _writeSkillFixture(
      dir,
      id: 'style_polisher',
      body: '技能正文：短剧台词要短。',
      extraFiles: {
        'references/rules.md': '规则：每句台词不超过二十字。',
      },
    );
    engine.saveMarkdownAgentSkill(filePath: skillFile.path);

    gateway.turns = [
      AgentTurnResult.tool('activate_skill', const {'name': 'style_polisher'}),
    ];
    await engine.sendAgentMessage(projectId, '激活文风技能', autoMode: false);

    final first = engine.agentMessages(projectId).last;
    expect(first.toolName, 'activate_skill');
    expect(first.content, startsWith('<skill_content name="style_polisher">'));
    expect(first.content, contains('技能正文：短剧台词要短。'));
    expect(first.content, contains('<file>references/rules.md</file>'));

    gateway.turns = [
      AgentTurnResult.tool('activate_skill', const {'name': 'style_polisher'}),
    ];
    await engine.sendAgentMessage(projectId, '再次激活文风技能', autoMode: false);

    final second = engine.agentMessages(projectId).last;
    expect(second.toolName, 'activate_skill');
    expect(second.content, '技能 "style_polisher" 已激活，无需重复加载。');
    expect(second.content, isNot(contains('技能正文：短剧台词要短。')));
    expect(second.content, isNot(contains('<skill_resources>')));

    gateway.turns = [
      AgentTurnResult.tool('read_skill_file', const {
        'path': 'references/rules.md',
      }),
    ];
    await engine.sendAgentMessage(projectId, '读取技能规则', autoMode: false);

    final read = engine.agentMessages(projectId).last;
    expect(read.toolName, 'read_skill_file');
    expect(read.content, contains('规则：每句台词不超过二十字。'));
    expect(read.content, startsWith('<skill_content>'));
  });

  test('SkillRuntime 激活后会注入后续 Agent system prompt', () async {
    final skillFile = _writeSkillFixture(
      dir,
      id: 'style_polisher',
      body: '''
技能正文：短剧台词必须克制，每句尽量少于二十字。

## 检查点

- 删除空泛旁白。
- 保留人物冲突。
''',
    );
    engine.saveMarkdownAgentSkill(
      filePath: skillFile.path,
      attribution: 'script_agent_decision',
    );

    gateway.turns = [
      AgentTurnResult.tool('activate_skill', const {'name': 'style_polisher'}),
      const AgentTurnResult.text('已按技能继续处理。'),
    ];

    await engine.sendAgentMessage(projectId, '激活技能后继续润色剧本', autoMode: true);

    expect(gateway.stages, [
      'scriptAgent:decisionAgent',
      'scriptAgent:decisionAgent',
    ]);
    expect(gateway.lastSystem, contains('已激活 Agent 技能'));
    expect(gateway.lastSystem, contains('style_polisher'));
    expect(gateway.lastSystem, contains('短剧台词必须克制'));
    expect(gateway.lastSystem, contains('删除空泛旁白'));
  });

  test('SkillRuntime 激活技能会传递给后续子 Agent system prompt', () async {
    final skillFile = _writeSkillFixture(
      dir,
      id: 'story_skeleton_style',
      body: '''
技能正文：故事骨架必须按短剧前三秒强冲突组织。

## 输出规则

- 第一集先给强钩子。
- 每集结尾保留悬念。
''',
    );
    engine.saveMarkdownAgentSkill(
      filePath: skillFile.path,
      attribution: 'script_agent_decision',
    );

    gateway.turns = [
      AgentTurnResult.tool(
        'activate_skill',
        const {'name': 'story_skeleton_style'},
      ),
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'prompt': '搭建前三集故事骨架'},
      ),
      const AgentTurnResult.text('<storySkeleton>前三集强冲突骨架</storySkeleton>'),
      const AgentTurnResult.text('故事骨架已完成。'),
    ];

    await engine.sendAgentMessage(projectId, '激活骨架技能并生成故事骨架', autoMode: true);

    expect(gateway.stages, [
      'scriptAgent:decisionAgent',
      'scriptAgent:decisionAgent',
      'scriptAgent:storySkeletonAgent',
      'scriptAgent:decisionAgent',
    ]);
    final subAgentSystem = gateway.systems[2];
    expect(subAgentSystem, contains('故事骨架搭建 Agent'));
    expect(subAgentSystem, contains('已激活 Agent 技能'));
    expect(subAgentSystem, contains('story_skeleton_style'));
    expect(subAgentSystem, contains('前三秒强冲突'));
    expect(subAgentSystem, contains('每集结尾保留悬念'));
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
        [agentRoleUser, 'assistant:decision']);
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
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], isA<List>());
    expect(payload['memories'], contains('用户强调寒山少主李澈外冷内热。'));
    expect(payload['memories'], contains('助手确认后续剧本不能把李澈写成反派。'));
  });

  test('Agent 记忆：deepRetrieve 工具支持 limit 限制返回条数', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    void insertMessage(String id, String content, int offset) {
      db.execute(
        'INSERT INTO memories '
        '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          '',
          content,
          now + offset,
          embeddingJson(content),
          'scriptAgent:$projectId',
          '[]',
          offset.isEven ? agentRoleUser : agentRoleAssistant,
          0,
          'message',
        ],
      );
    }

    insertMessage('limit_msg_old', '旧设定：李澈来自寒山。', 0);
    insertMessage('limit_msg_mid', '中间设定：李澈剑法克制。', 1);
    insertMessage('limit_msg_new', '最新补充：李澈必须救下沈微。', 2);

    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'keyword': '李澈',
        'limit': 1,
      }),
    ];

    await engine.sendAgentMessage(projectId, '只找一条李澈相关记忆', autoMode: false);

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    expect((deepRetrieveTool.schema['properties'] as Map), contains('limit'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], isA<List>());
    expect(payload['memories'], hasLength(1));
    expect((payload['memories'] as List).single, contains('李澈'));
  });

  test('AgentMemoryService deepRetrieve 先由 LLM 判别 summary 再展开原始 message',
      () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    void insertMessage(String id, String content, int offset) {
      db.execute(
        'INSERT INTO memories '
        '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          '',
          content,
          now + offset,
          '',
          'scriptAgent:$projectId',
          '[]',
          offset.isEven ? agentRoleUser : agentRoleAssistant,
          1,
          'message',
        ],
      );
    }

    insertMessage('msg_relevant_1', '用户强调寒山少主李澈必须保持正派。', 0);
    insertMessage('msg_relevant_2', '助手确认李澈不能被写成反派。', 1);
    insertMessage('msg_noise_1', '用户提到寒山宗门夜色适合做远景。', 2);
    insertMessage('msg_noise_2', '助手确认只把它作为场景气氛。', 3);
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'summary_relevant',
        '李澈角色设定',
        '寒山少主李澈是正派角色，不能反派化。',
        now + 4,
        embeddingJson('寒山少主李澈是正派角色，不能反派化。'),
        'scriptAgent:$projectId',
        jsonEncode(['msg_relevant_1', 'msg_relevant_2']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'summary_noise',
        '寒山场景气氛',
        '寒山宗门夜色适合作为远景气氛。',
        now + 5,
        embeddingJson('寒山宗门夜色适合作为远景气氛。'),
        'scriptAgent:$projectId',
        jsonEncode(['msg_noise_1', 'msg_noise_2']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    gateway.textResults = const [
      TextResult('["summary_relevant"]'),
    ];

    final records = await service.deepRetrieve(
      isolationKey: 'scriptAgent:$projectId',
      keyword: '寒山李澈是否能反派化',
    );

    expect(
        records.map((item) => item.id), ['msg_relevant_1', 'msg_relevant_2']);
    expect(gateway.textCallCount, 1);
  });

  test('AgentMemoryService deepRetrieve 合并 summary 展开和直接原始命中', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    void insertMessage(
      String id,
      String content,
      int offset, {
      required int summarized,
    }) {
      db.execute(
        'INSERT INTO memories '
        '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          '',
          content,
          now + offset,
          embeddingJson(content),
          'scriptAgent:$projectId',
          '[]',
          offset.isEven ? agentRoleUser : agentRoleAssistant,
          summarized,
          'message',
        ],
      );
    }

    insertMessage('msg_summary_1', '用户强调李澈是寒山少主，必须保持正派。', 0, summarized: 1);
    insertMessage('msg_summary_2', '助手确认李澈不能被写成反派。', 1, summarized: 1);
    insertMessage('msg_recent_direct', '用户刚补充：李澈救下沈微这一幕也必须保留。', 2,
        summarized: 0);
    insertMessage('msg_noise_direct', '用户提到宗门远景可以多一点云雾。', 3, summarized: 0);
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'summary_lizhe',
        '李澈角色设定',
        '李澈是寒山少主，必须保持正派，不能反派化。',
        now + 4,
        embeddingJson('李澈是寒山少主，必须保持正派，不能反派化。'),
        'scriptAgent:$projectId',
        jsonEncode(['msg_summary_1', 'msg_summary_2']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    gateway.textResults = const [
      TextResult('["summary_lizhe"]'),
    ];

    final records = await service.deepRetrieve(
      isolationKey: 'scriptAgent:$projectId',
      keyword: '李澈正派救下沈微',
    );

    expect(records.map((item) => item.id),
        ['msg_summary_1', 'msg_summary_2', 'msg_recent_direct']);
    expect(gateway.textCallCount, 1);
  });

  test('AgentMemoryService deepRetrieve 无 summary 时直接检索原始 message', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    void insertMessage(String id, String content, int offset) {
      db.execute(
        'INSERT INTO memories '
        '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          '',
          content,
          now + offset,
          embeddingJson(content),
          'scriptAgent:$projectId',
          '[]',
          offset.isEven ? agentRoleUser : agentRoleAssistant,
          0,
          'message',
        ],
      );
    }

    insertMessage('msg_direct_relevant', '用户强调李澈必须保持正派，不能被写成反派。', 0);
    insertMessage('msg_direct_noise', '用户提到寒山宗门夜色适合做远景。', 1);

    final records = await service.deepRetrieve(
      isolationKey: 'scriptAgent:$projectId',
      keyword: '李澈正派设定',
    );

    expect(records.map((item) => item.id), ['msg_direct_relevant']);
    expect(gateway.textCallCount, 0);
  });

  test('AgentMemoryService clear 按 scope 清空 message summary note', () {
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    const isolationKey = 'scriptAgent:scope-clear';
    const otherIsolationKey = 'productionAgent:scope-clear';

    void insertMemory(String id, String key, String type) {
      db.execute(
        'INSERT INTO memories '
        '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          id,
          '$type 内容',
          1000 + id.length,
          embeddingJson('$type 内容'),
          key,
          '[]',
          'assistant',
          0,
          type,
        ],
      );
    }

    insertMemory('scope_msg', isolationKey, agentMemoryTypeMessage);
    insertMemory('scope_sum', isolationKey, agentMemoryTypeSummary);
    insertMemory('scope_note', isolationKey, agentMemoryTypeNote);
    insertMemory('other_msg', otherIsolationKey, agentMemoryTypeMessage);

    List<String> typesFor(String key) => [
          for (final row in db.select(
            'SELECT type FROM memories WHERE isolationKey=? ORDER BY type ASC',
            [key],
          ))
            row['type'] as String,
        ];

    service.clear(isolationKey: isolationKey, scope: agentMemoryTypeMessage);

    expect(
        typesFor(isolationKey), [agentMemoryTypeNote, agentMemoryTypeSummary]);
    expect(typesFor(otherIsolationKey), [agentMemoryTypeMessage]);

    service.clear(isolationKey: isolationKey, scope: agentMemoryTypeSummary);

    expect(typesFor(isolationKey), [agentMemoryTypeNote]);
    expect(typesFor(otherIsolationKey), [agentMemoryTypeMessage]);

    service.clear(isolationKey: isolationKey, scope: 'all');

    expect(typesFor(isolationKey), isEmpty);
    expect(typesFor(otherIsolationKey), [agentMemoryTypeMessage]);
  });

  test('AgentMemoryService get 普通 RAG 直接检索 message 而不展开 summary', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'rag_noise_msg',
        '',
        '这条原始消息只讨论宗门夜色和远景气氛。',
        now,
        embeddingJson('这条原始消息只讨论宗门夜色和远景气氛。'),
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
        'rag_relevant_msg',
        '',
        '用户明确要求李澈保持正派，不能被写成反派。',
        now + 1,
        embeddingJson('用户明确要求李澈保持正派，不能被写成反派。'),
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
        'rag_summary_mentions_keyword',
        '李澈摘要',
        '李澈正派关键词出现在摘要里，但该摘要关联的是噪声原文。',
        now + 2,
        embeddingJson('李澈正派关键词出现在摘要里，但该摘要关联的是噪声原文。'),
        'scriptAgent:$projectId',
        jsonEncode(['rag_noise_msg']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );

    final context = await service.get(
      isolationKey: 'scriptAgent:$projectId',
      query: '李澈正派',
    );

    expect(
        context.relatedMessages.map((item) => item.id), ['rag_relevant_msg']);
    expect(gateway.textCallCount, 0);
  });

  test('AgentMemoryService get 可开启模型重排过滤相关 message', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.rerankEnabled', '1'],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'rag_noise_msg',
        '',
        '画面里有李澈正派匾额道具，和角色立场无关。',
        now,
        embeddingJson('画面里有李澈正派匾额道具，和角色立场无关。'),
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
        'rag_relevant_msg',
        '',
        '用户明确要求李澈保持正派，不能被写成反派。',
        now + 1,
        embeddingJson('用户明确要求李澈保持正派，不能被写成反派。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        1,
        'message',
      ],
    );
    gateway.textResults = const [TextResult('["rag_relevant_msg"]')];

    final context = await service.get(
      isolationKey: 'scriptAgent:$projectId',
      query: '李澈正派',
    );

    expect(
        context.relatedMessages.map((item) => item.id), ['rag_relevant_msg']);
    expect(gateway.textCallCount, 1);
    expect(gateway.textStages, ['scriptAgent:decisionAgent']);
  });

  test('AgentMemoryService get 返回相关记忆、历史摘要和未摘要近期对话', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '2'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.summaryLimit', '2'],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'ctx_msg_1',
        '',
        '用户要求寒山少主李澈不要被写成反派。',
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
        'ctx_msg_2',
        '',
        '助手确认李澈外冷内热，后续保持正派。',
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
        'ctx_summary',
        '寒山线摘要',
        '寒山少主李澈是正派角色，外冷内热。',
        now + 2,
        embeddingJson('寒山少主李澈是正派角色，外冷内热。'),
        'scriptAgent:$projectId',
        jsonEncode(['ctx_msg_1', 'ctx_msg_2']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'ctx_summary_mid',
        '入山线摘要一',
        '入山试炼前半段已经推进到山门。',
        now + 6,
        embeddingJson('入山试炼前半段已经推进到山门。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'ctx_summary_new',
        '入山线摘要二',
        '入山试炼后半段需要写出宗门压迫感。',
        now + 7,
        embeddingJson('入山试炼后半段需要写出宗门压迫感。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'ctx_msg_3',
        '',
        '用户补充下一集要写入山试炼。',
        now + 3,
        '',
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        0,
        'message',
      ],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'ctx_msg_4',
        '',
        '助手确认下一集聚焦入山试炼。',
        now + 4,
        '',
        'scriptAgent:$projectId',
        '[]',
        agentRoleAssistant,
        0,
        'message',
      ],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'ctx_msg_5',
        '',
        '这条已经进入更新摘要，不应再作为短期对话重复注入。',
        now + 5,
        '',
        'scriptAgent:$projectId',
        '[]',
        agentRoleAssistant,
        1,
        'message',
      ],
    );

    final context = await service.get(
      isolationKey: 'scriptAgent:$projectId',
      query: '寒山李澈',
    );

    expect(context.relatedMessages.map((item) => item.id),
        ['ctx_msg_1', 'ctx_msg_2']);
    expect(context.summaries.map((item) => item.id),
        ['ctx_summary_mid', 'ctx_summary_new']);
    expect(context.recentMessages.map((item) => item.id),
        ['ctx_msg_3', 'ctx_msg_4']);
  });

  test('Agent turn system prompt 注入 Memory.get 摘要和近期对话上下文', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'prompt_msg_1',
        '',
        '用户强调寒山少主李澈不能写成反派。',
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
        'prompt_msg_2',
        '',
        '助手确认：李澈保持正派，外冷内热。',
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
        'prompt_summary',
        '寒山线摘要',
        '寒山少主李澈是正派角色，不能反派化。',
        now + 2,
        embeddingJson('寒山少主李澈是正派角色，不能反派化。'),
        'scriptAgent:$projectId',
        jsonEncode(['prompt_msg_1', 'prompt_msg_2']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    gateway.turns = [const AgentTurnResult.text('收到，我会沿用寒山设定。')];

    await engine.sendAgentMessage(projectId, '继续写寒山李澈入山', autoMode: false);

    expect(gateway.lastSystem, contains('相关历史记忆'));
    expect(gateway.lastSystem, contains('历史摘要'));
    expect(gateway.lastSystem, contains('近期对话'));
    expect(gateway.lastSystem, contains('寒山少主李澈不能写成反派'));
    expect(gateway.lastSystem, contains('寒山少主李澈是正派角色'));
    expect(gateway.lastSystem, contains('继续写寒山李澈入山'));
  });

  test('productionAgent 对话记忆使用独立 isolationKey 和摘要阶段', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '2'],
    );
    gateway.turns = [const AgentTurnResult.text('制作决策已记录。')];
    gateway.textResults = const [
      TextResult('制作 Agent 记住分镜和视频生成策略。'),
    ];

    await engine.sendAgentMessage(projectId, '制作画布：下一步生成分镜首帧', autoMode: false);

    final productionMessages = db.select(
      'SELECT role,content,summarized FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['productionAgent:$projectId', 'message'],
    );
    expect(productionMessages, hasLength(2));
    expect(productionMessages.map((row) => row['role']),
        [agentRoleUser, 'assistant:decision']);
    expect(productionMessages.map((row) => row['summarized']), [1, 1]);

    final scriptMessages = db.select(
      'SELECT id FROM memories WHERE isolationKey=? AND type=?',
      ['scriptAgent:$projectId', 'message'],
    );
    expect(scriptMessages, isEmpty);

    final summary = db.select(
      'SELECT content FROM memories WHERE isolationKey=? AND type=?',
      ['productionAgent:$projectId', 'summary'],
    ).single;
    expect(summary['content'], '制作 Agent 记住分镜和视频生成策略。');
    expect(gateway.textStages, ['productionAgent:decisionAgent']);
  });

  test('productionAgent 决策历史不混入 scriptAgent 对话', () async {
    gateway.turns = const [
      AgentTurnResult.text('剧本规划已记录。'),
      AgentTurnResult.text('制作规划已记录。'),
    ];

    await engine.sendAgentMessage(projectId, '规划前三集', autoMode: false);
    await engine.sendAgentMessage(projectId, '制作画布：生成导演计划', autoMode: false);

    expect(gateway.stages,
        ['scriptAgent:decisionAgent', 'productionAgent:decisionAgent']);
    expect(gateway.lastMessages.map((item) => item['content']),
        isNot(contains('规划前三集')));
    expect(gateway.lastMessages.map((item) => item['content']),
        isNot(contains('剧本规划已记录。')));
    expect(gateway.lastMessages.map((item) => item['content']),
        contains('制作画布：生成导演计划'));
  });

  test(
      'ScriptAgentOrchestrator uses decision stage and exposes script subagent tools',
      () async {
    gateway.turns = [const AgentTurnResult.text('收到')];

    await engine.sendAgentMessage(projectId, '规划前三集', autoMode: false);

    expect(gateway.stages, ['scriptAgent:decisionAgent']);
    expect(
      gateway.toolNamesByCall.single,
      containsAll([
        'get_novel_events',
        'get_planData',
        'get_novel_text',
        'get_script_content',
        'run_sub_agent_storySkeleton',
        'run_sub_agent_adaptationStrategy',
        'run_sub_agent_script',
        'run_supervision_agent',
      ]),
    );
  });

  test(
      'ScriptAgent subagents receive long-term and conversation memory context',
      () async {
    engine.saveAgentMemory(
      projectId,
      name: '寒山画风',
      content: '寒山相关镜头保持冷白色调，不能写成暖色宫廷风。',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'script_sub_msg_user',
        '',
        '用户强调寒山少主李澈必须保持正派。',
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
        'script_sub_summary',
        '李澈角色设定',
        '寒山少主李澈是正派角色，不能反派化。',
        now + 1,
        embeddingJson('寒山少主李澈是正派角色，不能反派化。'),
        'scriptAgent:$projectId',
        jsonEncode(['script_sub_msg_user']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    gateway.textResults = const [
      TextResult('["script_sub_summary"]'),
      TextResult('["script_sub_summary"]'),
    ];
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'prompt': '搭建寒山篇前三集骨架'},
      ),
      const AgentTurnResult.text('<storySkeleton>寒山篇三集骨架</storySkeleton>'),
    ];

    await engine.sendAgentMessage(projectId, '先做寒山故事骨架', autoMode: false);

    expect(gateway.stages, [
      'scriptAgent:decisionAgent',
      'scriptAgent:storySkeletonAgent',
    ]);
    expect(gateway.lastSystem, contains('故事骨架搭建 Agent'));
    expect(gateway.lastSystem, contains('长期记忆'));
    expect(gateway.lastSystem, contains('冷白色调'));
    expect(gateway.lastSystem, contains('Agent 记忆上下文'));
    expect(gateway.lastSystem, contains('相关历史记忆'));
    expect(gateway.lastSystem, contains('李澈必须保持正派'));
    expect(gateway.lastSystem, contains('历史摘要'));
    expect(gateway.lastSystem, contains('李澈是正派角色'));
  });

  test('ScriptAgent 子 Agent 输出按 ToonFlow memoryKey 写入记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'prompt': '搭建寒山篇前三集骨架'},
      ),
      const AgentTurnResult.text('<storySkeleton>寒山篇三集骨架</storySkeleton>'),
    ];

    await engine.sendAgentMessage(projectId, '先做寒山故事骨架', autoMode: false);

    final rows = db.select(
      'SELECT role,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', 'message'],
    );

    expect(rows.map((row) => row['role']),
        contains('assistant:execution:storySkeleton'));
    final subAgentMemory = rows.singleWhere(
      (row) => row['role'] == 'assistant:execution:storySkeleton',
    );
    expect(subAgentMemory['content'], '寒山篇三集骨架');
  });

  test('Agent tool list honors custom skill attribution by decision stage',
      () async {
    engine.saveCustomAgentSkill(
      id: 'script_decision_custom',
      name: '剧本决策技能',
      description: '只给剧本决策 Agent 使用。',
      script: r'return "script";',
    );
    engine.saveCustomAgentSkill(
      id: 'production_decision_custom',
      name: '制作决策技能',
      description: '只给制作决策 Agent 使用。',
      script: r'return "production";',
    );
    db.execute(
      'INSERT INTO o_skillAttribution (attribution,skillId) VALUES (?,?)',
      ['script_agent_decision', 'script_decision_custom'],
    );
    db.execute(
      'INSERT INTO o_skillAttribution (attribution,skillId) VALUES (?,?)',
      ['production_agent_decision', 'production_decision_custom'],
    );
    gateway.turns = const [
      AgentTurnResult.text('剧本规划已记录。'),
      AgentTurnResult.text('制作规划已记录。'),
    ];

    await engine.sendAgentMessage(projectId, '规划前三集', autoMode: false);
    await engine.sendAgentMessage(projectId, '制作画布：生成导演计划', autoMode: false);

    expect(gateway.stages,
        ['scriptAgent:decisionAgent', 'productionAgent:decisionAgent']);
    expect(gateway.toolNamesByCall.first, contains('script_decision_custom'));
    expect(gateway.toolNamesByCall.first,
        isNot(contains('production_decision_custom')));
    expect(
        gateway.toolNamesByCall.last, contains('production_decision_custom'));
    expect(gateway.toolNamesByCall.last,
        isNot(contains('script_decision_custom')));
  });

  test('Agent tool list honors custom skill attribution by execution stage',
      () async {
    engine.saveCustomAgentSkill(
      id: 'script_execution_custom',
      name: '剧本执行技能',
      description: '只给剧本执行 Agent 使用。',
      script: r'return "script";',
    );
    engine.saveCustomAgentSkill(
      id: 'production_execution_custom',
      name: '制作执行技能',
      description: '只给制作执行 Agent 使用。',
      script: r'return "production";',
    );
    db.execute(
      'INSERT INTO o_skillAttribution (attribution,skillId) VALUES (?,?)',
      ['script_agent_execution', 'script_execution_custom'],
    );
    db.execute(
      'INSERT INTO o_skillAttribution (attribution,skillId) VALUES (?,?)',
      ['production_agent_execution', 'production_execution_custom'],
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'prompt': '搭建寒山篇前三集骨架'},
      ),
      const AgentTurnResult.text('<storySkeleton>寒山篇三集骨架</storySkeleton>'),
    ];

    await engine.sendAgentMessage(projectId, '先做故事骨架', autoMode: false);

    expect(gateway.stages, [
      'scriptAgent:decisionAgent',
      'scriptAgent:storySkeletonAgent',
    ]);
    expect(gateway.toolNamesByCall.last, contains('script_execution_custom'));
    expect(gateway.toolNamesByCall.last,
        isNot(contains('production_execution_custom')));

    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '做第一集导演计划', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<scriptPlan>第一集冷色调快节奏</scriptPlan>'),
    ];

    await engine.sendAgentMessage(projectId, '制作导演计划', autoMode: false);

    expect(gateway.stages, [
      'productionAgent:decisionAgent',
      'productionAgent:directorPlanAgent',
    ]);
    expect(
        gateway.toolNamesByCall.last, contains('production_execution_custom'));
    expect(gateway.toolNamesByCall.last,
        isNot(contains('script_execution_custom')));
  });

  test(
      'ScriptAgentOrchestrator runs planning subagents and stores scriptAgent workspace data',
      () async {
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'prompt': '搭建寒山篇前三集骨架'},
      ),
      const AgentTurnResult.text('<storySkeleton>寒山篇三集骨架</storySkeleton>'),
    ];

    await engine.sendAgentMessage(projectId, '先做故事骨架', autoMode: false);

    expect(gateway.stages, [
      'scriptAgent:decisionAgent',
      'scriptAgent:storySkeletonAgent',
    ]);
    var data = _scriptAgentWorkData(db, projectId);
    expect(data['storySkeleton'], '寒山篇三集骨架');
    expect(data['adaptationStrategy'], '');
    expect(engine.agentMessages(projectId).last.content,
        contains('故事骨架 Agent 已写入工作区'));

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_adaptationStrategy',
        const {'prompt': '给寒山篇设计短剧改编策略'},
      ),
      const AgentTurnResult.text(
        '<adaptationStrategy>前三集强化退婚冲突</adaptationStrategy>',
      ),
    ];

    await engine.sendAgentMessage(projectId, '继续做改编策略', autoMode: false);

    expect(gateway.stages, [
      'scriptAgent:decisionAgent',
      'scriptAgent:adaptationStrategyAgent',
    ]);
    data = _scriptAgentWorkData(db, projectId);
    expect(data['storySkeleton'], '寒山篇三集骨架');
    expect(data['adaptationStrategy'], '前三集强化退婚冲突');

    gateway.turns = [
      AgentTurnResult.tool(
        'run_supervision_agent',
        const {'prompt': '检查前三集是否连续'},
      ),
      const AgentTurnResult.text('监督结论：节奏成立。'),
    ];

    await engine.sendAgentMessage(projectId, '监督一下', autoMode: false);

    data = _scriptAgentWorkData(db, projectId);
    expect(data['supervision'], contains('节奏成立'));
  });

  test('ScriptAgentOrchestrator parses script subagent XML into scripts',
      () async {
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_script',
        const {'prompt': '写第一集'},
      ),
      const AgentTurnResult.text(
        '<scriptItem name="第一集"><content>李澈入山。</content></scriptItem>'
        '<scriptItem name="第二集">寒山试剑。</scriptItem>',
      ),
    ];

    await engine.sendAgentMessage(projectId, '生成剧本正文', autoMode: false);

    expect(gateway.stages, [
      'scriptAgent:decisionAgent',
      'scriptAgent:scriptAgent',
    ]);
    final rows = engine.scripts(projectId);
    expect(rows.map((row) => row.name), ['第一集', '第二集']);
    expect(rows[0].content, '李澈入山。');
    expect(rows[1].content, '寒山试剑。');
    expect(engine.agentMessages(projectId).last.content,
        contains('剧本 Agent 已写入 2 个剧本'));
  });

  test(
      'ProductionAgentOrchestrator uses decision stage and exposes production subagent tools',
      () async {
    gateway.turns = [const AgentTurnResult.text('收到')];

    await engine.sendAgentMessage(projectId, '制作画布：生成导演计划和分镜面板',
        autoMode: false);

    expect(gateway.stages, ['productionAgent:decisionAgent']);
    expect(
      gateway.toolNamesByCall.single,
      containsAll([
        'get_flowData',
        'add_deriveAsset',
        'generate_deriveAsset',
        'generate_storyboard',
        'add_flowData_storyboard',
        'run_sub_agent_derive_assets',
        'run_sub_agent_generate_assets',
        'run_sub_agent_director_plan',
        'run_sub_agent_storyboard_gen',
        'run_sub_agent_storyboard_panel',
        'run_sub_agent_storyboard_table',
        'run_sub_agent_supervision',
      ]),
    );
  });

  test(
      'ProductionAgent subagents receive production memory context without script leakage',
      () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    engine.saveAgentMemory(
      projectId,
      name: '制作镜头规则',
      content: '寒山制作镜头保持低机位跟拍，首帧避免暖色宫廷布景。',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'production_sub_msg_user',
        '',
        '用户要求导演计划保留低机位跟拍和冷白山门。',
        now,
        '',
        'productionAgent:$projectId',
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
        'production_sub_summary',
        '导演计划要求',
        '寒山制作需要低机位跟拍，并保持冷白山门视觉。',
        now + 1,
        embeddingJson('寒山制作需要低机位跟拍，并保持冷白山门视觉。'),
        'productionAgent:$projectId',
        jsonEncode(['production_sub_msg_user']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'script_private_summary',
        '剧本私有设定',
        '这条剧本私有记忆不应进入制作子 Agent。',
        now + 2,
        embeddingJson('剧本私有记忆不应进入制作子 Agent。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    gateway.textResults = const [
      TextResult('["production_sub_summary"]'),
      TextResult('["production_sub_summary"]'),
    ];
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '做寒山第一集导演计划', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<scriptPlan>低机位跟拍寒山山门</scriptPlan>'),
    ];

    await engine.sendAgentMessage(projectId, '制作画布：做寒山导演计划', autoMode: false);

    expect(gateway.stages, [
      'productionAgent:decisionAgent',
      'productionAgent:directorPlanAgent',
    ]);
    expect(gateway.lastSystem, contains('负责导演规划'));
    expect(gateway.lastSystem, contains('长期记忆'));
    expect(gateway.lastSystem, contains('低机位跟拍'));
    expect(gateway.lastSystem, contains('Agent 记忆上下文'));
    expect(gateway.lastSystem, contains('相关历史记忆'));
    expect(gateway.lastSystem, contains('冷白山门'));
    expect(gateway.lastSystem, isNot(contains('剧本私有记忆')));
  });

  test('ProductionAgent 子 Agent 输出按 ToonFlow memoryKey 写入记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '寒山开场');
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '做寒山导演计划', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<scriptPlan>低机位跟拍寒山山门</scriptPlan>'),
    ];

    await engine.sendAgentMessage(projectId, '制作画布：做寒山导演计划', autoMode: false);

    final rows = db.select(
      'SELECT role,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['productionAgent:$projectId', 'message'],
    );

    expect(rows.map((row) => row['role']), contains('assistant:execution'));
    final subAgentMemory = rows.singleWhere(
      (row) => row['role'] == 'assistant:execution',
    );
    expect(subAgentMemory['content'], '低机位跟拍寒山山门');
  });

  test(
      'ProductionAgentOrchestrator writes director plan storyboard table and storyboard panel',
      () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '做第一集导演计划', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<scriptPlan>第一集冷色调快节奏</scriptPlan>'),
    ];

    await engine.sendAgentMessage(projectId, '制作导演计划', autoMode: false);

    expect(gateway.stages, [
      'productionAgent:decisionAgent',
      'productionAgent:directorPlanAgent',
    ]);
    var flowData = _productionAgentWorkData(db, projectId, scriptId);
    expect(flowData['scriptPlan'], '第一集冷色调快节奏');

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_table',
        {'prompt': '做第一集分镜表', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<storyboardTable>|镜头|内容|</storyboardTable>'),
    ];

    await engine.sendAgentMessage(projectId, '制作分镜表', autoMode: false);

    flowData = _productionAgentWorkData(db, projectId, scriptId);
    expect(flowData['storyboardTable'], '|镜头|内容|');
    expect(engine.storyboardTable(projectId, scriptId), '|镜头|内容|');

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_panel',
        {'prompt': '写第一集分镜面板', 'scriptId': scriptId},
      ),
      AgentTurnResult.text(
        "<storyboardItem videoDesc='李澈踏入寒山宗门' "
        "prompt='冷色调，少年入山，远景' track='主线' "
        "shouldGenerateImage='false' duration='3.5' "
        "associateAssetsIds='[$roleId]'></storyboardItem>",
      ),
    ];

    await engine.sendAgentMessage(projectId, '写分镜面板', autoMode: false);

    final rows = engine.storyboards(scriptId);
    expect(rows, hasLength(1));
    expect(rows.single.videoDesc, '李澈踏入寒山宗门');
    expect(rows.single.prompt, '冷色调，少年入山，远景');
    expect(rows.single.duration, '3.5');
    expect(rows.single.track, '主线');
    expect(rows.single.shouldGenerateImage, 0);
    expect(rows.single.assetIds, [roleId]);
  });

  test(
      'ProductionAgentOrchestrator runs asset and storyboard execution tools from subagents',
      () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final parentAssetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, parentAssetId]);

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_derive_assets',
        {'prompt': '衍生战损造型', 'scriptId': scriptId},
      ),
      AgentTurnResult.tool(
        'add_deriveAsset',
        {
          'assetsId': parentAssetId,
          'id': null,
          'name': '李澈战损造型',
          'desc': '衣甲破损，脸侧有血痕',
          'scriptId': scriptId,
        },
      ),
      const AgentTurnResult.text('衍生资产完成'),
    ];

    await engine.sendAgentMessage(projectId, '生产衍生资产', autoMode: false);

    final child = db.select(
      'SELECT * FROM o_assets WHERE assetsId=? AND name=?',
      [parentAssetId, '李澈战损造型'],
    ).single;
    final childId = child['id'] as int;
    expect(child['describe'], '衣甲破损，脸侧有血痕');
    expect(
      db.select('SELECT assetId FROM o_scriptAssets WHERE scriptId=?',
          [scriptId]).map((row) => row['assetId']),
      contains(childId),
    );

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_generate_assets',
        {'prompt': '生成衍生资产图片', 'scriptId': scriptId},
      ),
      AgentTurnResult.tool('generate_deriveAsset', {
        'ids': [childId],
      }),
      const AgentTurnResult.text('开始生成'),
    ];

    await engine.sendAgentMessage(projectId, '生成衍生资产图片', autoMode: false);

    expect(
      db.select('SELECT taskClass FROM o_tasks').map((row) => row['taskClass']),
      contains('asset_image_generation'),
    );

    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '寒山宗门远景',
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_gen',
        {'prompt': '生成分镜首帧', 'scriptId': scriptId},
      ),
      AgentTurnResult.tool('generate_storyboard', {
        'ids': [storyboardId],
      }),
      const AgentTurnResult.text('开始生成'),
    ];

    await engine.sendAgentMessage(projectId, '生成分镜首帧图', autoMode: false);

    expect(
      db.select('SELECT taskClass FROM o_tasks').map((row) => row['taskClass']),
      contains('storyboard_image_generation'),
    );

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_supervision',
        {'prompt': '审核制作结果', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('监督结论：制作链路通过。'),
    ];

    await engine.sendAgentMessage(projectId, '监督制作结果', autoMode: false);

    final flowData = _productionAgentWorkData(db, projectId, scriptId);
    expect(flowData['supervision'], contains('制作链路通过'));
  });
}

Map<String, dynamic> _scriptAgentWorkData(Database db, int projectId) {
  final row = db.select(
    "SELECT data FROM o_agentWorkData WHERE projectId=? AND episodesId IS NULL AND key='scriptAgent'",
    [projectId],
  ).single;
  return Map<String, dynamic>.from(jsonDecode(row['data'] as String) as Map);
}

Map<String, dynamic> _productionAgentWorkData(
  Database db,
  int projectId,
  int scriptId,
) {
  final row = db.select(
    "SELECT data FROM o_agentWorkData WHERE projectId=? AND episodesId=? AND key='productionAgent'",
    [projectId, scriptId],
  ).single;
  return Map<String, dynamic>.from(jsonDecode(row['data'] as String) as Map);
}

File _writeSkillFixture(
  Directory dir, {
  required String id,
  required String body,
  Map<String, String> extraFiles = const {},
}) {
  final skillDir = Directory(p.join(dir.path, 'skills', id))
    ..createSync(recursive: true);
  final file = File(p.join(skillDir.path, 'SKILL.md'));
  file.writeAsStringSync('''
---
name: $id
description: 短剧文风润色技能
---

$body
''');
  for (final entry in extraFiles.entries) {
    final extra = File(p.join(skillDir.path, entry.key))
      ..parent.createSync(recursive: true);
    extra.writeAsStringSync(entry.value);
  }
  return file;
}

class _Gateway implements ProviderGateway {
  List<AgentTurnResult> _turns = const [];
  List<TextResult> textResults = const [];
  List<AgentToolDef> lastTools = const [];
  String lastSystem = '';
  List<String> systems = const [];
  List<Map<String, String>> lastMessages = const [];
  List<String> stages = const [];
  List<String> textStages = const [];
  List<List<String>> toolNamesByCall = const [];
  int callCount = 0;
  int textCallCount = 0;
  bool shouldThrow = false;

  set turns(List<AgentTurnResult> value) {
    _turns = value;
    callCount = 0;
    stages = [];
    systems = [];
    textStages = [];
    toolNamesByCall = [];
  }

  List<AgentTurnResult> get turns => _turns;

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
    systems = [...systems, system];
    lastMessages = [for (final message in messages) Map.of(message)];
    stages = [...stages, stage];
    toolNamesByCall = [
      ...toolNamesByCall,
      [for (final tool in tools) tool.name],
    ];
    final r = _turns[callCount];
    callCount++;
    return r;
  }

  @override
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken}) async {
    textStages = [...textStages, stage];
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
