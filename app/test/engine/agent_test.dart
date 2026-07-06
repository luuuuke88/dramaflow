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

  test('Agent 记忆：decision Agent 写入前按 ToonFlow 去除 XML 块', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    gateway.turns = [
      const AgentTurnResult.text(
        '<analysis>内部推理不应进入记忆。</analysis>'
        '我会记住寒山设定。<debug />',
      ),
    ];

    await engine.sendAgentMessage(projectId, '记住寒山设定', autoMode: false);

    expect(
      engine.agentMessages(projectId).last.content,
      '<analysis>内部推理不应进入记忆。</analysis>我会记住寒山设定。<debug />',
    );
    final decisionMemory = db.select(
      'SELECT content FROM memories WHERE isolationKey=? AND role=? AND type=?',
      ['scriptAgent:$projectId', 'assistant:decision', 'message'],
    ).single;
    expect(decisionMemory['content'], '我会记住寒山设定。');
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
    gateway.turns = List.generate(
      10,
      (index) => index.isEven
          ? AgentTurnResult.tool('get_status', {'tick': index})
          : AgentTurnResult.tool('deepRetrieve', {'keyword': '寒山$index'}),
    );
    await engine.sendAgentMessage(projectId, '一直做', autoMode: true);
    expect(gateway.callCount, 5, reason: '_maxAutoTurns=5 上限生效');
  });

  test('auto 模式会拦截连续相同工具调用', () async {
    gateway.turns = List.generate(
      6,
      (index) => AgentTurnResult.tool('get_status', {'tick': index}),
    );

    await engine.sendAgentMessage(projectId, '一直刷新状态', autoMode: true);

    final msgs = engine.agentMessages(projectId);
    expect(msgs.where((m) => m.toolName == 'get_status'), hasLength(3));
    expect(msgs.last.role, agentRoleAssistant);
    expect(msgs.last.content, contains('连续调用 get_status'));
    expect(gateway.callCount, 4);
  });

  test('auto 模式会拦截同一轮重复工具调用', () async {
    gateway.turns = const [
      AgentTurnResult.tool('get_status', {}),
      AgentTurnResult.tool('get_status', {}),
      AgentTurnResult.text('不会走到这里'),
    ];

    await engine.sendAgentMessage(projectId, '一直查看状态', autoMode: true);

    final msgs = engine.agentMessages(projectId);
    expect(msgs.where((m) => m.toolName == 'get_status'), hasLength(1));
    expect(msgs.last.role, agentRoleAssistant);
    expect(msgs.last.content, contains('重复工具调用 get_status'));
    expect(gateway.callCount, 2);
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
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
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
    final audit = db.select(
      'SELECT role,content FROM memories WHERE isolationKey=? AND type=? '
      'ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', agentMemoryTypeSummary],
    );
    expect(audit, hasLength(1));
    expect(audit.single['role'], 'assistant:supervision');
    expect(audit.single['content'], contains('监督 Agent 已放行 generate_events'));
    expect(audit.single['content'], contains('已提交事件生成任务'));
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
    final memoryRoles = db.select(
      'SELECT role FROM memories WHERE isolationKey=? AND type=? '
      'ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', agentMemoryTypeMessage],
    ).map((row) => row['role']);
    expect(memoryRoles, contains('assistant:supervision'));
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

  test('监督 Agent 复核上下文默认排除工具审计记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.supervision.enabled', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    void insertMessage({
      required String id,
      required String content,
      required String role,
      required int offset,
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
          role,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      id: 'supervision_tool_noise',
      content: '工具审计噪声：寒山审核 寒山审核 寒山审核 已写入日志。',
      role: 'assistant:decision:tool',
      offset: 0,
    );
    insertMessage(
      id: 'supervision_tool_result_noise',
      content: '工具结果噪声：寒山审核 寒山审核 寒山审核 寒山审核 已写入日志。',
      role: agentRoleTool,
      offset: 1,
    );
    insertMessage(
      id: 'supervision_user_keep',
      content: '用户设定：寒山审核要求生成事件前先核对章节范围。',
      role: agentRoleUser,
      offset: 2,
    );
    gateway.turns = [
      AgentTurnResult.tool('get_status', const {}),
      const AgentTurnResult.text('APPROVE'),
    ];

    await engine.sendAgentMessage(projectId, '寒山审核一下项目进度', autoMode: false);

    expect(gateway.stages,
        ['scriptAgent:decisionAgent', 'scriptAgent:supervisionAgent']);
    expect(gateway.lastSystem, contains('supervision_user_keep'));
    expect(gateway.lastSystem, contains('先核对章节范围'));
    expect(gateway.lastSystem, isNot(contains('supervision_tool_noise')));
    expect(
        gateway.lastSystem, isNot(contains('supervision_tool_result_noise')));
    expect(gateway.lastSystem, isNot(contains('工具审计噪声')));
    expect(gateway.lastSystem, isNot(contains('工具结果噪声')));
    expect(gateway.lastSystem, isNot(contains('寒山审核一下项目进度')));
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

  test('自定义脚本技能：支持数组回调第三参数访问原数组', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_array_callback_source_runtime',
      name: '数组回调原数组脚本运行时',
      description: '验证自定义技能兼容模型常写的 (item, index, all) => ...。',
      script: r'''
const uniqueNames = args.assets
  .filter((asset, index, all) =>
    all.findIndex(candidate => candidate.name.trim() === asset.name.trim()) === index)
  .map((asset, index, all) => `${index + 1}/${all.length}:${asset.name.trim()}`)
  .join('、');
const peerTypes = args.assets
  .filter((asset, index, all) =>
    all.some((candidate, peerIndex) =>
      peerIndex !== index && candidate.type === asset.type))
  .map(asset => asset.type)
  .join(',');
return JSON.stringify({ uniqueNames, peerTypes });
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
      AgentTurnResult.tool(
          'custom_script_array_callback_source_runtime', const {
        'assets': [
          {'type': 'role', 'name': ' 李澈 '},
          {'type': 'role', 'name': '李澈'},
          {'type': 'scene', 'name': '寒山宗门'},
          {'type': 'scene', 'name': '雪谷'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用数组回调原数组脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_array_callback_source_runtime');
    expect(jsonDecode(msg.content), {
      'uniqueNames': '1/3:李澈、2/3:寒山宗门、3/3:雪谷',
      'peerTypes': 'role,role,scene,scene',
    });
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

  test('自定义脚本技能：支持 Math.sqrt 计算画幅尺寸', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_math_sqrt_runtime',
      name: '画幅尺寸脚本运行时',
      description: '验证自定义技能兼容 ToonFlow 常见的 Math.sqrt 比例归一计算。',
      script: r'''
const base = args.base;
const w = args.width;
const h = args.height;
const calcW = Math.min(2048, Math.round(base * Math.sqrt(w / h)));
const calcH = Math.max(512, Math.round(base * Math.sqrt(h / w)));
return JSON.stringify({ calcW, calcH });
''',
      schema: const {
        'type': 'object',
        'properties': {
          'base': {'type': 'number'},
          'width': {'type': 'number'},
          'height': {'type': 'number'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_math_sqrt_runtime', const {
        'base': 1024,
        'width': 16,
        'height': 9,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用画幅尺寸脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_math_sqrt_runtime');
    expect(jsonDecode(msg.content), {
      'calcW': 1365,
      'calcH': 768,
    });
  });

  test('自定义脚本技能：支持 Math.random 和数字 toString 进制', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_math_random_runtime',
      name: '随机编号脚本运行时',
      description:
          '验证自定义技能兼容 ToonFlow 常见的 Math.random().toString(36).slice(2) 写法。',
      script: r'''
const requestId = `toonflow_ima2_${Date.now()}_${Math.random().toString(36).slice(2)}`;
const temperature = 72 + Math.floor(Math.random() * 21) - 10;
const suffix = requestId.slice(requestId.lastIndexOf('_') + 1);
return JSON.stringify({
  hasPrefix: requestId.startsWith('toonflow_ima2_'),
  suffixNotEmpty: suffix.length > 0,
  suffixLooksBase36: /^[0-9a-z.]+$/.test(suffix),
  temperatureInRange: temperature >= 62 && temperature <= 82,
});
''',
      schema: const {
        'type': 'object',
        'properties': {},
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_math_random_runtime', const {}),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用随机编号脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_math_random_runtime');
    expect(jsonDecode(msg.content), {
      'hasPrefix': true,
      'suffixNotEmpty': true,
      'suffixLooksBase36': true,
      'temperatureInRange': true,
    });
  });

  test('自定义脚本技能：支持 Object.hasOwn 和 hasOwnProperty 判断字段存在性', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_has_own_runtime',
      name: '字段存在性脚本运行时',
      description:
          '验证自定义技能兼容模型常写的 Object.hasOwn(...) 和 obj.hasOwnProperty(...)。',
      script: r'''
const rows = args.assets.map((asset, index) => ({
  index: index + 1,
  hasPrompt: Object.hasOwn(asset, 'prompt'),
  hasName: asset.hasOwnProperty('name'),
  missingOptional: !asset.hasOwnProperty('optional'),
}));
return JSON.stringify({
  prompted: rows
    .filter(row => row.hasPrompt && row.hasName)
    .map(row => `${row.index}:${row.hasPrompt}`)
    .join('|'),
  namedCount: rows.filter(row => row.hasName).length,
  secondPromptExists: rows[1].hasPrompt,
  thirdPromptExists: rows[2].hasPrompt,
  allMissingOptional: rows.every(row => row.missingOptional),
});
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
      AgentTurnResult.tool('custom_script_has_own_runtime', const {
        'assets': [
          {'name': '李澈', 'prompt': '寒山剑修'},
          {'name': '沈微', 'prompt': null},
          {'name': '寒山宗门'},
          {'prompt': '无名资产'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用字段存在性脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_has_own_runtime');
    expect(jsonDecode(msg.content), {
      'prompted': '1:true|2:true',
      'namedCount': 3,
      'secondPromptExists': true,
      'thirdPromptExists': false,
      'allMissingOptional': true,
    });
  });

  test('自定义脚本技能：支持 Object.assign 和 Object.fromEntries 整理工具入参', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_object_compose_runtime',
      name: 'Object 组合脚本运行时',
      description: '验证自定义技能兼容模型常写的 Object.assign/Object.fromEntries 入参整理。',
      script: r'''
const defaults = { quality: 'draft', track: 'video' };
const normalizedAssets = Object.fromEntries(
  Object.entries(args.assetsById)
    .filter(([id, asset]) => asset.enabled !== false)
    .map(([id, asset]) => [
      id,
      Object.assign({}, defaults, {
        id,
        type: asset.type,
        name: asset.name.trim(),
        prompt: `${asset.type}:${asset.name.trim()}`,
      }),
    ])
);
const request = Object.assign({}, args.baseRequest, {
  assetCount: Object.keys(normalizedAssets).length,
  assets: normalizedAssets,
});
return JSON.stringify(request);
''',
      schema: const {
        'type': 'object',
        'properties': {
          'baseRequest': {'type': 'object'},
          'assetsById': {'type': 'object'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_object_compose_runtime', const {
        'baseRequest': {
          'stage': 'storyboard-video-prompt',
          'quality': 'preview',
        },
        'assetsById': {
          'A001': {
            'type': 'role',
            'name': ' 李澈 ',
          },
          'A002': {
            'type': 'scene',
            'name': ' 寒山宗门 ',
          },
          'A003': {
            'type': 'tool',
            'name': '废弃道具',
            'enabled': false,
          },
        },
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Object 组合脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_object_compose_runtime');
    expect(jsonDecode(msg.content), {
      'stage': 'storyboard-video-prompt',
      'quality': 'preview',
      'assetCount': 2,
      'assets': {
        'A001': {
          'quality': 'draft',
          'track': 'video',
          'id': 'A001',
          'type': 'role',
          'name': '李澈',
          'prompt': 'role:李澈',
        },
        'A002': {
          'quality': 'draft',
          'track': 'video',
          'id': 'A002',
          'type': 'scene',
          'name': '寒山宗门',
          'prompt': 'scene:寒山宗门',
        },
      },
    });
  });

  test('自定义脚本技能：支持 Object.assign 原地合并目标对象', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_object_assign_mutation_runtime',
      name: '对象合并脚本运行时',
      description:
          '验证自定义技能兼容模型常写的 Object.assign(payload, ...); payload.xxx 语义。',
      script: r'''
const payload = {};
const returned = Object.assign(payload, args.defaults, {
  title: args.title.trim(),
});
Object.assign(payload, {
  duration: args.shots.reduce((sum, shot) => sum + shot.duration, 0),
});
returned.tag = 'ready';
return JSON.stringify({
  sameObject: returned === payload,
  title: payload.title,
  style: payload.style,
  duration: payload.duration,
  tag: payload.tag,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'defaults': {'type': 'object'},
          'title': {'type': 'string'},
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
      AgentTurnResult.tool(
        'custom_script_object_assign_mutation_runtime',
        const {
          'defaults': {'style': '水墨短剧', 'duration': 0},
          'title': '  寒山试剑  ',
          'shots': [
            {'duration': 2},
            {'duration': 3},
            {'duration': 4},
          ],
        },
      ),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用对象合并脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_object_assign_mutation_runtime');
    expect(jsonDecode(msg.content), {
      'sameObject': true,
      'title': '寒山试剑',
      'style': '水墨短剧',
      'duration': 9,
      'tag': 'ready',
    });
  });

  test('自定义脚本技能：支持 Array.from 生成序号和映射列表', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_array_from_runtime',
      name: 'Array.from 脚本运行时',
      description: '验证自定义技能兼容模型常写的 Array.from({ length }, mapper)。',
      script: r'''
const shotLabels = Array.from({ length: args.count }, (_, index) => `镜头${index + 1}`)
  .join('、');
const assetLabels = Array.from(args.assets, (asset, index) =>
  `${index + 1}.${asset.name.trim()}`)
  .join('、');
return JSON.stringify({
  shotLabels,
  assetLabels,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'count': {'type': 'number'},
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
      AgentTurnResult.tool('custom_script_array_from_runtime', const {
        'count': 3,
        'assets': [
          {'name': ' 李澈 '},
          {'name': '寒山宗门'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Array.from 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_array_from_runtime');
    expect(jsonDecode(msg.content), {
      'shotLabels': '镜头1、镜头2、镜头3',
      'assetLabels': '1.李澈、2.寒山宗门',
    });
  });

  test('自定义脚本技能：支持 Array 构造 fill 和字符串 padStart', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_array_fill_pad_runtime',
      name: '数组填充编号脚本运行时',
      description: '验证自定义技能兼容模型常写的 new Array(n).fill(...).map(...) 编号写法。',
      script: r'''
const labels = new Array(args.count)
  .fill(null)
  .map((_, index) => `镜头${String(index + 1).padStart(2, '0')}`)
  .join('、');
const slots = Array(args.refCount)
  .fill('参考图')
  .map((label, index) => `${label}${String(index + 1).padStart(2, '0')}`)
  .join('|');
return JSON.stringify({ labels, slots });
''',
      schema: const {
        'type': 'object',
        'properties': {
          'count': {'type': 'number'},
          'refCount': {'type': 'number'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_array_fill_pad_runtime', const {
        'count': 3,
        'refCount': 2,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用数组填充编号脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_array_fill_pad_runtime');
    expect(jsonDecode(msg.content), {
      'labels': '镜头01、镜头02、镜头03',
      'slots': '参考图01|参考图02',
    });
  });

  test('自定义脚本技能：支持字符串 padEnd 和 repeat', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_string_pad_repeat_runtime',
      name: '字符串补齐重复脚本运行时',
      description: '验证自定义技能兼容模型常写的 padEnd 和 repeat 文本整理。',
      script: r'''
const normalized = args.name.trim().toLowerCase().replaceAll(' ', '-');
const title = args.name.trim().toUpperCase();
const padded = normalized.padEnd(12, '_');
const divider = '='.repeat(3);
return JSON.stringify({ normalized, title, padded, divider });
''',
      schema: const {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_string_pad_repeat_runtime', const {
        'name': '  Li Che  ',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用字符串补齐重复脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_string_pad_repeat_runtime');
    expect(jsonDecode(msg.content), {
      'normalized': 'li-che',
      'title': 'LI CHE',
      'padded': 'li-che______',
      'divider': '===',
    });
  });

  test('自定义脚本技能：支持 concat flat reverse 整理多来源参考图', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_array_compose_runtime',
      name: '数组组合脚本运行时',
      description: '验证自定义技能兼容模型常写的 concat/flat/reverse 参考图整理。',
      script: r'''
const refs = args.roleRefs
  .concat(args.sceneRefs, args.extraRefs)
  .flat()
  .filter(ref => ref.enabled !== false)
  .reverse();
return JSON.stringify({
  orderedIds: refs.map(ref => ref.id).join('>'),
  firstKind: refs[0].kind,
  count: refs.length,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'roleRefs': {'type': 'array'},
          'sceneRefs': {'type': 'array'},
          'extraRefs': {'type': 'array'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_array_compose_runtime', const {
        'roleRefs': [
          {'id': 'R1', 'kind': 'role'},
        ],
        'sceneRefs': [
          {'id': 'S1', 'kind': 'scene'},
        ],
        'extraRefs': [
          [
            {'id': 'T1', 'kind': 'tool', 'enabled': false},
            {'id': 'M1', 'kind': 'mood'},
          ],
          [
            {'id': 'M2', 'kind': 'mood'},
          ],
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用数组组合脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_array_compose_runtime');
    expect(jsonDecode(msg.content), {
      'orderedIds': 'M2>M1>S1>R1',
      'firstKind': 'mood',
      'count': 4,
    });
  });

  test('自定义脚本技能：支持 Array.reverse 原地反转语义', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_reverse_mutation_runtime',
      name: '原地反转脚本运行时',
      description: '验证自定义技能兼容模型常写的 refs.reverse(); refs.map(...) 语义。',
      script: r'''
const refs = args.refs.map(ref => ref.name.trim());
const returned = refs.reverse();
returned.push('补充镜头');
return JSON.stringify({
  sameObject: returned === refs,
  refs: refs.join('>'),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'refs': {
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
      AgentTurnResult.tool('custom_script_reverse_mutation_runtime', const {
        'refs': [
          {'name': ' 李澈正脸 '},
          {'name': '寒山宗门'},
          {'name': ' 沈微侧脸 '},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用原地反转脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_reverse_mutation_runtime');
    expect(jsonDecode(msg.content), {
      'sameObject': true,
      'refs': '沈微侧脸>寒山宗门>李澈正脸>补充镜头',
    });
  });

  test('自定义脚本技能：支持 Set 去重和 has/add/delete', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_set_runtime',
      name: 'Set 脚本运行时',
      description: '验证自定义技能兼容模型常写的 new Set([...]) 去重和成员判断。',
      script: r'''
const unique = new Set(args.assets.map(asset => asset.name.trim()));
const selected = new Set(args.selectedIds);
selected.delete(10);
selected.add(30);
const picked = args.assets
  .filter(asset => selected.has(asset.id))
  .map(asset => asset.name.trim())
  .join('、');
return JSON.stringify({
  uniqueNames: [...unique].join('、'),
  uniqueCount: unique.size,
  picked,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'selectedIds': {
            'type': 'array',
            'items': {'type': 'number'},
          },
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'number'},
                'name': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_set_runtime', const {
        'selectedIds': [10, 20],
        'assets': [
          {'id': 10, 'name': ' 李澈 '},
          {'id': 20, 'name': '沈微'},
          {'id': 30, 'name': ' 李澈 '},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Set 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_set_runtime');
    expect(msg.content, isNot(startsWith('执行失败')));
    expect(jsonDecode(msg.content), {
      'uniqueNames': '李澈、沈微',
      'uniqueCount': 2,
      'picked': '沈微、李澈',
    });
  });

  test('自定义脚本技能：支持 Map 索引和 entries values keys', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_map_runtime',
      name: 'Map 脚本运行时',
      description: '验证自定义技能兼容模型常写的 new Map(Object.entries(...)) 索引。',
      script: r'''
const assetsById = new Map(Object.entries(args.assetsById));
assetsById.delete('A003');
assetsById.set('A004', { type: 'tool', name: ' 灵剑 ' });
const selected = args.selectedIds
  .filter(id => assetsById.has(id))
  .map(id => assetsById.get(id).name.trim())
  .join('、');
return JSON.stringify({
  selected,
  size: assetsById.size,
  keys: Array.from(assetsById.keys()).join('|'),
  values: Array.from(assetsById.values()).map(asset => asset.type).join('|'),
  entries: Array.from(assetsById.entries())
    .map(([id, asset]) => `${id}:${asset.name.trim()}`)
    .join('、'),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'selectedIds': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'assetsById': {'type': 'object'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_map_runtime', const {
        'selectedIds': ['A002', 'A003', 'A004'],
        'assetsById': {
          'A001': {'type': 'role', 'name': ' 李澈 '},
          'A002': {'type': 'scene', 'name': '寒山宗门'},
          'A003': {'type': 'tool', 'name': '废弃道具'},
        },
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Map 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_map_runtime');
    expect(msg.content, isNot(startsWith('执行失败')));
    expect(jsonDecode(msg.content), {
      'selected': '寒山宗门、灵剑',
      'size': 3,
      'keys': 'A001|A002|A004',
      'values': 'role|scene|tool',
      'entries': 'A001:李澈、A002:寒山宗门、A004:灵剑',
    });
  });

  test('自定义脚本技能：支持 Map.forEach 用 value 和 key 聚合', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_map_foreach_runtime',
      name: 'Map forEach 脚本运行时',
      description: '验证自定义技能兼容模型常写的 map.forEach((value, key) => ...)。',
      script: r'''
const assetsById = new Map(Object.entries(args.assetsById));
let labels = [];
let totalDuration = 0;
assetsById.forEach((asset, id) => {
  if (asset.enabled === false) {
    return;
  }
  labels.push(`${id}:${asset.name.trim()}`);
  totalDuration += asset.duration ?? 0;
});
return JSON.stringify({
  labels: labels.join('、'),
  totalDuration,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'assetsById': {'type': 'object'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_map_foreach_runtime', const {
        'assetsById': {
          'A001': {'name': ' 李澈 ', 'duration': 2},
          'A002': {
            'name': '废弃镜头',
            'duration': 99,
            'enabled': false,
          },
          'A003': {'name': '沈微', 'duration': 3},
        },
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Map forEach 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_map_foreach_runtime');
    expect(msg.content, isNot(startsWith('执行失败')));
    expect(jsonDecode(msg.content), {
      'labels': 'A001:李澈、A003:沈微',
      'totalDuration': 5,
    });
  });

  test('自定义脚本技能：支持 Date 时间戳和 ISO 时间格式', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_date_runtime',
      name: 'Date 脚本运行时',
      description: '验证自定义技能兼容模型常写的 Date.parse/new Date 时间标记。',
      script: r'''
const base = Date.parse(args.baseIso);
const items = args.items.map((item, index) => ({
  id: item.id,
  createTime: base + index * 1000,
  createIso: new Date(base + index * 1000).toISOString(),
}));
const startedAt = new Date(args.startedAt);
return JSON.stringify({
  firstIso: items[0].createIso,
  secondTime: items[1].createTime,
  startedTime: startedAt.getTime(),
  startedIso: startedAt.toJSON(),
  nowIsPositive: Date.now() > 0,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'baseIso': {'type': 'string'},
          'startedAt': {'type': 'number'},
          'items': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_date_runtime', const {
        'baseIso': '2026-07-06T00:00:00.000Z',
        'startedAt': 1783296000000,
        'items': [
          {'id': 'shot-1'},
          {'id': 'shot-2'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Date 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_date_runtime');
    expect(msg.content, isNot(startsWith('执行失败')));
    expect(jsonDecode(msg.content), {
      'firstIso': '2026-07-06T00:00:00.000Z',
      'secondTime': 1783296001000,
      'startedTime': 1783296000000,
      'startedIso': '2026-07-06T00:00:00.000Z',
      'nowIsPositive': true,
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

  test('自定义脚本技能：支持数组解构 rest 保留剩余参考项', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_array_rest_runtime',
      name: '数组 rest 解构脚本运行时',
      description: '验证自定义技能兼容模型常写的 [first, ...rest] 参考图整理。',
      script: r'''
const [coverImage, ...referenceImages] = args.images;
const rows = args.rows.map(([type, firstName, ...otherNames]) => ({
  type,
  firstName,
  otherNames: otherNames.join('/'),
  total: otherNames.length + 1,
}));
return JSON.stringify({
  cover: coverImage.name.trim(),
  referenceCount: referenceImages.length,
  referenceNames: referenceImages.map(image => image.name.trim()).join('、'),
  rows,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'images': {
            'type': 'array',
            'items': {'type': 'object'},
          },
          'rows': {
            'type': 'array',
            'items': {'type': 'array'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_array_rest_runtime', const {
        'images': [
          {'name': ' 首帧图 '},
          {'name': ' 角色参考 '},
          {'name': '场景参考'},
        ],
        'rows': [
          ['role', '李澈', '沈微', '师尊'],
          ['scene', '寒山宗门'],
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用数组 rest 解构脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_array_rest_runtime');
    expect(jsonDecode(msg.content), {
      'cover': '首帧图',
      'referenceCount': 2,
      'referenceNames': '角色参考、场景参考',
      'rows': [
        {
          'type': 'role',
          'firstName': '李澈',
          'otherNames': '沈微/师尊',
          'total': 3,
        },
        {
          'type': 'scene',
          'firstName': '寒山宗门',
          'otherNames': '',
          'total': 1,
        },
      ],
    });
  });

  test('自定义脚本技能：支持数组解构默认值兜底缺失字段', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_array_default_runtime',
      name: '数组默认值解构脚本运行时',
      description: '验证自定义技能兼容模型常写的 [first = fallback] 和 ([type, name = x])。',
      script: r'''
const [coverImage = args.fallbackImage, referenceImage = { name: ' 默认参考 ' }, ...remainingImages] = args.images;
const rows = args.rows
  .map(([type, name = '未命名', duration = 1]) => `${type}:${name}:${duration}s`)
  .join('|');
return JSON.stringify({
  cover: coverImage.name.trim(),
  reference: referenceImage.name.trim(),
  remainingCount: remainingImages.length,
  rows,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'fallbackImage': {'type': 'object'},
          'images': {
            'type': 'array',
            'items': {'type': 'object'},
          },
          'rows': {
            'type': 'array',
            'items': {'type': 'array'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_array_default_runtime', const {
        'fallbackImage': {'name': ' 兜底首帧 '},
        'images': [],
        'rows': [
          ['role', '李澈', 3],
          ['scene'],
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用数组默认值解构脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_array_default_runtime');
    expect(jsonDecode(msg.content), {
      'cover': '兜底首帧',
      'reference': '默认参考',
      'remainingCount': 0,
      'rows': 'role:李澈:3s|scene:未命名:1s',
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

  test('自定义脚本技能：支持对象字面量计算属性名', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_computed_object_key_runtime',
      name: '动态对象键脚本运行时',
      description: '验证自定义技能兼容模型常写的 { [type]: value } 动态 payload。',
      script: r'''
const entries = args.assets.map(asset => ({
  [asset.type]: asset.name.trim(),
  [`${asset.type}Id`]: asset.id,
}));
return JSON.stringify(Object.assign({}, ...entries));
''',
      schema: const {
        'type': 'object',
        'properties': {
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'number'},
                'type': {'type': 'string'},
                'name': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_computed_object_key_runtime', const {
        'assets': [
          {'id': 101, 'type': 'role', 'name': ' 李澈 '},
          {'id': 202, 'type': 'scene', 'name': '寒山宗门'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用动态对象键脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_computed_object_key_runtime');
    expect(jsonDecode(msg.content), {
      'role': '李澈',
      'roleId': 101,
      'scene': '寒山宗门',
      'sceneId': 202,
    });
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

  test('自定义脚本技能：支持 while 循环遍历分镜', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_while_runtime',
      name: 'while 循环脚本运行时',
      description: '验证自定义技能兼容模型常写的 while/i++ 分镜遍历。',
      script: r'''
let selected = [];
let totalDuration = 0;
let i = 0;
while (i < args.storyboards.length) {
  const shot = args.storyboards[i];
  i++;
  if (shot.disabled) {
    continue;
  }
  if (selected.length >= args.limit) {
    break;
  }
  totalDuration += shot.duration ?? 1;
  selected.push(`${i}.${shot.videoDesc.trim()}`);
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
      AgentTurnResult.tool('custom_script_while_runtime', const {
        'limit': 2,
        'storyboards': [
          {'videoDesc': ' 雪夜山门 ', 'duration': 3},
          {'videoDesc': '废弃镜头', 'duration': 10, 'disabled': true},
          {'videoDesc': '李澈拔剑'},
          {'videoDesc': '掌门入场', 'duration': 8},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 while 循环脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_while_runtime');
    expect(jsonDecode(msg.content), {
      'totalDuration': 4,
      'selected': '1.雪夜山门、3.李澈拔剑',
    });
  });

  test('自定义脚本技能：支持普通函数声明作为辅助方法', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_function_runtime',
      name: '函数声明脚本运行时',
      description: '验证自定义技能兼容模型常写的 function 辅助方法。',
      script: r'''
function formatShot(shot, index) {
  if (shot.disabled || !shot.videoDesc?.trim()) {
    return null;
  }
  const duration = shot.duration ?? 1;
  return `${index + 1}.${shot.videoDesc.trim()}:${duration}s`;
}

const labels = args.storyboards
  .map((shot, index) => formatShot(shot, index))
  .filter(label => !!label);

return labels.join('、');
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
      AgentTurnResult.tool('custom_script_function_runtime', const {
        'storyboards': [
          {'videoDesc': ' 雪夜山门 ', 'duration': 3},
          {'videoDesc': '', 'duration': 4},
          {'videoDesc': '李澈拔剑'},
          {'videoDesc': '废弃镜头', 'duration': 8, 'disabled': true},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用函数声明脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_function_runtime');
    expect(msg.content, '1.雪夜山门:3s、3.李澈拔剑:1s');
  });

  test('自定义脚本技能：支持函数和回调参数默认值', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_param_default_runtime',
      name: '参数默认值脚本运行时',
      description:
          '验证自定义技能兼容模型常写的 function normalize(asset = {}) 和 map((asset = {}) => ...)。',
      script: r'''
function normalizeAsset(asset = { name: ' 默认资产 ', type: 'unknown' }) {
  return `${asset.type}:${asset.name.trim()}`;
}

const fallbackLabel = normalizeAsset();
const labels = args.assets
  .map((asset = { name: ' 未命名 ', type: 'unknown' }) => normalizeAsset(asset))
  .join('、');

return JSON.stringify({ fallbackLabel, labels });
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
                'type': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_param_default_runtime', const {
        'assets': [
          {'name': ' 李澈 ', 'type': 'role'},
          null,
          {'name': ' 寒山宗门 ', 'type': 'scene'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用参数默认值脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_param_default_runtime');
    expect(jsonDecode(msg.content), {
      'fallbackLabel': 'unknown:默认资产',
      'labels': 'role:李澈、unknown:未命名、scene:寒山宗门',
    });
  });

  test('自定义脚本技能：支持数组方法传入函数声明回调', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_function_callback_runtime',
      name: '函数回调脚本运行时',
      description: '验证自定义技能兼容模型常写的 map(formatShot) 函数引用回调。',
      script: r'''
function formatShot(shot, index) {
  if (shot.disabled || !shot.videoDesc?.trim()) {
    return null;
  }
  return `${index + 1}.${shot.videoDesc.trim()}`;
}

function keepLabel(label) {
  return !!label;
}

const labels = args.storyboards
  .map(formatShot)
  .filter(keepLabel);

return labels.join('、');
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
                'disabled': {'type': 'boolean'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_function_callback_runtime', const {
        'storyboards': [
          {'videoDesc': ' 雪夜山门 '},
          {'videoDesc': '', 'disabled': false},
          {'videoDesc': '废弃镜头', 'disabled': true},
          {'videoDesc': '李澈拔剑'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用函数回调脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_function_callback_runtime');
    expect(msg.content, '1.雪夜山门、4.李澈拔剑');
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

  test('自定义脚本技能：支持 Number 和 String 全局转换', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_global_cast_runtime',
      name: '全局转换脚本运行时',
      description: '验证自定义技能兼容模型常写的 Number(...) 和 String(...) 转换。',
      script: r'''
const { storyboards = [], projectName = '未命名项目' } = args;
let total = 0;
storyboards.forEach(shot => {
  if (!shot.videoDesc?.trim()) {
    return;
  }
  total += Number(shot.duration ?? 1);
});
return `${String(projectName).trim()}:${total}`;
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
                'duration': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_global_cast_runtime', const {
        'projectName': ' 测试短剧 ',
        'storyboards': [
          {'videoDesc': '雪夜山门', 'duration': '3'},
          {'videoDesc': '', 'duration': '99'},
          {'videoDesc': '李澈拔剑'},
          {'videoDesc': '掌门入场', 'duration': '2.5'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用全局转换脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_global_cast_runtime');
    expect(msg.content, '测试短剧:6.5');
  });

  test('自定义脚本技能：支持数字 toFixed 格式化', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_number_to_fixed_runtime',
      name: '数字格式化脚本运行时',
      description: '验证自定义技能兼容模型常写的 Number(value).toFixed(1) 时长格式化。',
      script: r'''
const durations = args.shots.map(shot => Number(shot.duration ?? 1));
const labels = durations
  .map((duration, index) => `${index + 1}.${duration.toFixed(1)}s`)
  .join('、');
const total = durations.reduce((sum, duration) => sum + duration, 0);
return JSON.stringify({
  labels,
  total: total.toFixed(2),
  percent: (Number(args.ratio) * 100).toFixed(),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'ratio': {'type': 'number'},
          'shots': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'duration': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_number_to_fixed_runtime', const {
        'ratio': 0.756,
        'shots': [
          {'duration': '3'},
          {'duration': '2.25'},
          {},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用数字格式化脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_number_to_fixed_runtime');
    expect(jsonDecode(msg.content), {
      'labels': '1.3.0s、2.2.3s、3.1.0s',
      'total': '6.25',
      'percent': '76',
    });
  });

  test('自定义脚本技能：支持 Boolean 全局转换和 filter(Boolean)', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_boolean_filter_runtime',
      name: '布尔转换脚本运行时',
      description: '验证自定义技能兼容模型常写的 Boolean(...) 和 filter(Boolean)。',
      script: r'''
const rawNames = args.assets
  .map(asset => asset.name?.trim())
  .filter(Boolean);
const hasPrompt = Boolean(args.prompt?.trim());
const hasEmpty = Boolean(args.emptyText?.trim());
return JSON.stringify({
  names: rawNames.join('、'),
  hasPrompt,
  hasEmpty,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'prompt': {'type': 'string'},
          'emptyText': {'type': 'string'},
          'assets': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_boolean_filter_runtime', const {
        'prompt': '  分镜提示词  ',
        'emptyText': '   ',
        'assets': [
          {'name': ' 李澈 '},
          {'name': ''},
          {},
          {'name': '寒山宗门'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用布尔转换脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_boolean_filter_runtime');
    expect(jsonDecode(msg.content), {
      'names': '李澈、寒山宗门',
      'hasPrompt': true,
      'hasEmpty': false,
    });
  });

  test('自定义脚本技能：支持 Number.isFinite/Number.isNaN 和全局 isFinite/isNaN', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_number_predicate_runtime',
      name: '数字判定脚本运行时',
      description: '验证自定义技能兼容模型常写的 Number.isFinite/isNaN 和全局 isFinite/isNaN。',
      script: r'''
const durations = args.shots
  .map(shot => parseFloat(shot.duration))
  .filter(value => Number.isFinite(value));
const unsafeNaN = 0 / 0;
const unsafeInfinity = 1 / 0;
return JSON.stringify({
  total: durations.reduce((sum, value) => sum + value, 0),
  numberNaN: Number.isNaN(unsafeNaN),
  globalNaN: isNaN(unsafeNaN),
  numberFiniteInfinity: Number.isFinite(unsafeInfinity),
  globalFiniteInfinity: isFinite(unsafeInfinity),
  globalFiniteString: isFinite('12.5'),
  globalNaNText: isNaN('bad-duration'),
  numberNaNText: Number.isNaN('bad-duration'),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'shots': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_number_predicate_runtime', const {
        'shots': [
          {'duration': '3秒'},
          {'duration': '2.5s'},
          {'duration': '1'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用数字判定脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_number_predicate_runtime');
    expect(jsonDecode(msg.content), {
      'total': 6.5,
      'numberNaN': true,
      'globalNaN': true,
      'numberFiniteInfinity': false,
      'globalFiniteInfinity': false,
      'globalFiniteString': true,
      'globalNaNText': true,
      'numberNaNText': false,
    });
  });

  test('自定义脚本技能：支持 parseFloat 和 parseInt 全局解析', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_parse_runtime',
      name: '全局解析脚本运行时',
      description: '验证自定义技能兼容模型常写的 parseFloat/parseInt 解析带单位数字。',
      script: r'''
const { storyboards = [] } = args;
let totalDuration = 0;
let refCount = 0;
storyboards.forEach(shot => {
  if (!shot.videoDesc?.trim()) {
    return;
  }
  totalDuration += parseFloat(shot.duration ?? '1');
  refCount += parseInt(shot.references ?? '0', 10);
});
return JSON.stringify({
  totalDuration,
  refCount,
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
                'duration': {'type': 'string'},
                'references': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_parse_runtime', const {
        'storyboards': [
          {'videoDesc': '雪夜山门', 'duration': '3秒', 'references': '4 refs'},
          {'videoDesc': '李澈拔剑', 'duration': '2.5s', 'references': '2张'},
          {'videoDesc': '', 'duration': '99s', 'references': '99'},
          {'videoDesc': '掌门入场'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用全局解析脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_parse_runtime');
    expect(msg.content, '{"totalDuration":6.5,"refCount":6}');
  });

  test('自定义脚本技能：支持 Number.parseFloat 和 Number.parseInt 静态解析', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_number_static_parse_runtime',
      name: 'Number 静态解析脚本运行时',
      description: '验证自定义技能兼容模型常写的 Number.parseFloat/Number.parseInt 解析尺寸和时长。',
      script: r'''
const parts = args.size.split('x');
const width = Number.parseInt(parts[0], 10);
const height = Number.parseInt(parts[1], 10);
const duration = Number.parseFloat(args.duration ?? '1');
return JSON.stringify({
  width,
  height,
  duration,
  pixels: width * height,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'size': {'type': 'string'},
          'duration': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_number_static_parse_runtime', const {
        'size': '1280x720',
        'duration': '3.5s',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Number 静态解析脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_number_static_parse_runtime');
    expect(jsonDecode(msg.content), {
      'width': 1280,
      'height': 720,
      'duration': 3.5,
      'pixels': 921600,
    });
  });

  test('自定义脚本技能：支持字符串拆分清洗分镜表', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_string_parse_runtime',
      name: '字符串解析脚本运行时',
      description: '验证自定义技能兼容模型常写的 split/replace/startsWith/endsWith 文本清洗。',
      script: r'''
const shots = args.table
  .split('\n')
  .map(line => line.trim())
  .filter(line => line && !line.startsWith('#') && !line.endsWith('废弃'))
  .map((line, index) => {
    const parts = line.replace('镜头：', '').split('|').map(part => part.trim());
    return {
      index: index + 1,
      title: parts[0],
      duration: parseFloat(parts[1].replace('秒', '')),
      track: parts[2],
    };
  });
return JSON.stringify(shots);
''',
      schema: const {
        'type': 'object',
        'properties': {
          'table': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_string_parse_runtime', const {
        'table': '''
# 分镜表
镜头：雪夜山门 | 3秒 | 首尾帧
镜头：废稿 | 9秒 | 首帧 废弃
镜头：李澈拔剑 | 2.5秒 | 视频参考
''',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用字符串解析脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_string_parse_runtime');
    expect(
      msg.content,
      '[{"index":1,"title":"雪夜山门","duration":3,"track":"首尾帧"},'
      '{"index":2,"title":"李澈拔剑","duration":2.5,"track":"视频参考"}]',
    );
  });

  test('自定义脚本技能：支持字符串和数组搜索位置参数', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_search_position_runtime',
      name: '搜索位置参数脚本运行时',
      description:
          '验证自定义技能兼容模型常写的 includes(value, fromIndex)、startsWith(value, position)、endsWith(value, endPosition)。',
      script: r'''
const text = args.workspace;
const cleaned = args.lines
  .filter(line => !line.startsWith('#', 0) && !line.endsWith('废弃', line.length - 1))
  .join('|');
const ids = args.ids
  .filter(id => args.selectedIds.includes(id, 1))
  .join(',');
return JSON.stringify({
  hasLaterSeedance: text.includes('Seedance', 8),
  hasEarlySeedance: text.includes('Seedance', 0),
  startsAtOffset: text.startsWith('Seedance', 5),
  endsBeforeSuffix: text.endsWith('完成', text.length - 4),
  cleaned,
  ids,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'workspace': {'type': 'string'},
          'lines': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'ids': {
            'type': 'array',
            'items': {'type': 'number'},
          },
          'selectedIds': {
            'type': 'array',
            'items': {'type': 'number'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_search_position_runtime', const {
        'workspace': '开场说明 Seedance 完成；复查 Seedance 完成 ###',
        'lines': ['# 注释', '镜头一有效', '镜头二废弃x'],
        'ids': [1, 2, 3],
        'selectedIds': [1, 3],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用搜索位置参数脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_search_position_runtime');
    expect(jsonDecode(msg.content), {
      'hasLaterSeedance': true,
      'hasEarlySeedance': true,
      'startsAtOffset': true,
      'endsBeforeSuffix': true,
      'cleaned': '镜头一有效',
      'ids': '3',
    });
  });

  test('自定义脚本技能：支持 indexOf substring 和字符串 slice 解析工作区', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_string_index_runtime',
      name: '字符串索引脚本运行时',
      description: '验证自定义技能兼容模型常写的 indexOf/substring/slice 工作区解析。',
      script: r'''
const start = args.workspace.indexOf('<storyboardItem');
const close = args.workspace.indexOf('</storyboardItem>', start);
const block = args.workspace.substring(start, close);
const descStart = block.indexOf('videoDesc="') + 'videoDesc="'.length;
const descEnd = block.indexOf('"', descStart);
const desc = block.substring(descStart, descEnd).trim();
const prefix = args.workspace.slice(0, start).trim();
const lastClose = args.workspace.trim().slice(-17);
return JSON.stringify({
  found: start >= 0,
  desc,
  prefixEndsWithPlan: prefix.endsWith('</scriptPlan>'),
  lastClose,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'workspace': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_string_index_runtime', const {
        'workspace': '''
<scriptPlan>寒山宗门外，雪夜开场。</scriptPlan>
<storyboardItem videoDesc=" 雪夜山门 " duration="3秒"></storyboardItem>
<storyboardItem videoDesc="李澈拔剑" duration="2秒"></storyboardItem>
''',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用字符串索引脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_string_index_runtime');
    expect(
      msg.content,
      '{"found":true,"desc":"雪夜山门",'
      '"prefixEndsWithPlan":true,"lastClose":"</storyboardItem>"}',
    );
  });

  test('自定义脚本技能：支持 lastIndexOf replaceAll trimStart trimEnd 和 charAt 清洗工作区',
      () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_string_cleanup_runtime',
      name: '字符串清洗脚本运行时',
      description:
          '验证自定义技能兼容模型常写的 lastIndexOf/replaceAll/trimStart/trimEnd/charAt 文本清洗。',
      script: r'''
const cleaned = args.workspace.replaceAll('\r\n', '\n').trimEnd();
const lastOpen = cleaned.lastIndexOf('<storyboardItem');
const previousOpen = cleaned.lastIndexOf('<storyboardItem', lastOpen - 1);
const lastClose = cleaned.lastIndexOf('</storyboardItem>');
const previousClose = cleaned.indexOf('</storyboardItem>', previousOpen);
const lastBlock = cleaned.substring(lastOpen, lastClose);
const previousBlock = cleaned.substring(previousOpen, previousClose);
const marker = 'videoDesc="';
const descStart = lastBlock.indexOf(marker) + marker.length;
const descEnd = lastBlock.indexOf('"', descStart);
const previousStart = previousBlock.indexOf(marker) + marker.length;
const previousEnd = previousBlock.indexOf('"', previousStart);
const desc = lastBlock.substring(descStart, descEnd)
  .replaceAll('　', ' ')
  .trimStart()
  .trimEnd();
const previousDesc = previousBlock.substring(previousStart, previousEnd).trim();
return JSON.stringify({
  previousDesc,
  desc,
  tail: cleaned.charAt(cleaned.length - 1),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'workspace': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_string_cleanup_runtime', const {
        'workspace':
            '<storyboardItem videoDesc="雪夜山门" duration="3秒"></storyboardItem>\r\n'
                '<storyboardItem videoDesc="　李澈拔剑　" duration="2秒"></storyboardItem>\r\n'
                '   ',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用字符串清洗脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_string_cleanup_runtime');
    expect(
      msg.content,
      '{"previousDesc":"雪夜山门","desc":"李澈拔剑","tail":">"}',
    );
  });

  test('自定义脚本技能：支持 JSON.parse 读取工作区数据', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_json_parse_runtime',
      name: 'JSON 工作区脚本运行时',
      description: '验证自定义技能兼容模型常写的 JSON.parse 工作区数据读取。',
      script: r'''
const workspace = JSON.parse(args.workspaceJson);
const selected = workspace.storyboards
  .filter(shot => shot.enabled !== false)
  .map((shot, index) => ({
    order: index + 1,
    id: shot.id,
    title: shot.title.trim(),
    duration: parseFloat(shot.duration),
    assetCount: shot.assets.length,
  }));
return JSON.stringify({
  project: workspace.project.name.trim(),
  selected,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'workspaceJson': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_json_parse_runtime', {
        'workspaceJson': jsonEncode({
          'project': {'name': ' 测试短剧 '},
          'storyboards': [
            {
              'id': 's1',
              'title': ' 雪夜山门 ',
              'duration': '3秒',
              'enabled': true,
              'assets': ['A001', 'A010'],
            },
            {
              'id': 's2',
              'title': '废稿',
              'duration': '9秒',
              'enabled': false,
              'assets': ['A999'],
            },
            {
              'id': 's3',
              'title': '李澈拔剑',
              'duration': '2.5s',
              'assets': ['A001'],
            },
          ],
        }),
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 JSON 工作区脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_json_parse_runtime');
    expect(
      msg.content,
      '{"project":"测试短剧","selected":[{"order":1,"id":"s1","title":"雪夜山门",'
      '"duration":3,"assetCount":2},{"order":2,"id":"s3","title":"李澈拔剑",'
      '"duration":2.5,"assetCount":1}]}',
    );
  });

  test('自定义脚本技能：支持 JSON.stringify pretty 输出', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_json_stringify_pretty_runtime',
      name: 'JSON 格式化脚本运行时',
      description: '验证自定义技能兼容模型常写的 JSON.stringify(value, null, 2)。',
      script: r'''
const payload = {
  project: args.name.trim(),
  shots: args.shots.map((shot, index) => ({
    index: index + 1,
    desc: shot.desc.trim(),
    duration: Number(shot.duration ?? 1),
  })),
};
const pretty = JSON.stringify(payload, null, 2);
const tabbed = JSON.stringify(payload.shots, null, '\t');
return JSON.stringify({ pretty, tabbed });
''',
      schema: const {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'shots': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'desc': {'type': 'string'},
                'duration': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool(
        'custom_script_json_stringify_pretty_runtime',
        const {
          'name': ' 测试短剧 ',
          'shots': [
            {'desc': ' 雪夜山门 ', 'duration': '3'},
            {'desc': '李澈拔剑', 'duration': '2.5'},
          ],
        },
      ),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 JSON 格式化脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_json_stringify_pretty_runtime');
    final decoded = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(
      decoded['pretty'],
      '{\n'
      '  "project": "测试短剧",\n'
      '  "shots": [\n'
      '    {\n'
      '      "index": 1,\n'
      '      "desc": "雪夜山门",\n'
      '      "duration": 3\n'
      '    },\n'
      '    {\n'
      '      "index": 2,\n'
      '      "desc": "李澈拔剑",\n'
      '      "duration": 2.5\n'
      '    }\n'
      '  ]\n'
      '}',
    );
    expect(
      decoded['tabbed'],
      '[\n'
      '\t{\n'
      '\t\t"index": 1,\n'
      '\t\t"desc": "雪夜山门",\n'
      '\t\t"duration": 3\n'
      '\t},\n'
      '\t{\n'
      '\t\t"index": 2,\n'
      '\t\t"desc": "李澈拔剑",\n'
      '\t\t"duration": 2.5\n'
      '\t}\n'
      ']',
    );
  });

  test('自定义脚本技能：支持 try catch 兜底 JSON 解析失败', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_try_catch_runtime',
      name: 'try catch 脚本运行时',
      description: '验证自定义技能兼容模型常写的 try/catch 容错解析。',
      script: r'''
try {
  const workspace = JSON.parse(args.workspaceJson);
  return workspace.project.name.trim();
} catch (err) {
  return `工作区 JSON 无法解析，已降级：${err.name}:${err.key}:${err.reason}`;
}
''',
      schema: const {
        'type': 'object',
        'properties': {
          'workspaceJson': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_try_catch_runtime', const {
        'workspaceJson': '{ bad json',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 try catch 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_try_catch_runtime');
    expect(
      msg.content,
      '工作区 JSON 无法解析，已降级：EngineException:errLlmFormat:custom_skill_json_parse',
    );
  });

  test('自定义脚本技能：支持 throw new Error 并在 catch 读取 message', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_throw_error_runtime',
      name: '显式错误脚本运行时',
      description: '验证自定义技能兼容模型常写的 throw new Error(...) 校验写法。',
      script: r'''
function requireField(value, label) {
  if (!value?.trim()) {
    throw new Error(`${label}不能为空`);
  }
  return value.trim();
}

try {
  const title = requireField(args.title, '标题');
  return JSON.stringify({ ok: true, title });
} catch (err) {
  return JSON.stringify({
    ok: false,
    errorName: err.name,
    message: err.message,
  });
}
''',
      schema: const {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_throw_error_runtime', const {
        'title': '   ',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用显式错误脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_throw_error_runtime');
    expect(msg.content, isNot(startsWith('执行失败')));
    expect(jsonDecode(msg.content), {
      'ok': false,
      'errorName': 'Error',
      'message': '标题不能为空',
    });
  });

  test('自定义脚本技能：支持 console 调试调用作为安全空操作', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_console_runtime',
      name: 'console 调试脚本运行时',
      description: '验证自定义技能兼容模型常遗留的 console.log/info/warn/error/debug。',
      script: r'''
console.log('start', args.items.length);
console.info('project', projectId);
const selected = args.items
  .filter(item => {
    console.debug('checking', item.name);
    return item.enabled !== false;
  })
  .map(item => item.name.trim());
if (selected.length === 0) {
  console.warn('empty selected list');
}
console.error('dry-run only');
return JSON.stringify({
  count: selected.length,
  names: selected.join('、'),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'items': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_console_runtime', const {
        'items': [
          {'name': ' 李澈 ', 'enabled': true},
          {'name': '废弃角色', 'enabled': false},
          {'name': '沈微', 'enabled': true},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 console 调试脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_console_runtime');
    expect(msg.content, isNot(startsWith('执行失败')));
    expect(jsonDecode(msg.content), {
      'count': 2,
      'names': '李澈、沈微',
    });
  });

  test('自定义脚本技能：支持正则 match 提取分镜工作区 XML', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_regex_match_runtime',
      name: '正则解析脚本运行时',
      description: '验证自定义技能兼容模型常写的 /.../g 和 match 捕获组解析。',
      script: r'''
const blocks = args.workspace.match(/<storyboardItem\b[^>]*>/g) ?? [];
const shots = blocks.map((block, index) => {
  const desc = block.match(/videoDesc="([^"]+)"/);
  const duration = block.match(/duration="([^"]+)"/);
  return {
    index: index + 1,
    videoDesc: desc[1].trim(),
    duration: parseFloat(duration[1]),
  };
});
return JSON.stringify(shots);
''',
      schema: const {
        'type': 'object',
        'properties': {
          'workspace': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_regex_match_runtime', const {
        'workspace': '''
<scriptPlan>寒山宗门外，雪夜开场。</scriptPlan>
<storyboardItem videoDesc=" 雪夜山门 " duration="3秒" track="首帧"></storyboardItem>
<storyboardItem videoDesc="李澈拔剑" duration="2.5s" track="视频参考"></storyboardItem>
''',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用正则解析脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_regex_match_runtime');
    expect(
      msg.content,
      '[{"index":1,"videoDesc":"雪夜山门","duration":3},'
      '{"index":2,"videoDesc":"李澈拔剑","duration":2.5}]',
    );
  });

  test('自定义脚本技能：支持正则 matchAll 批量提取分镜字段', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_regex_match_all_runtime',
      name: '正则批量解析脚本运行时',
      description: '验证自定义技能兼容模型常写的 [...text.matchAll(/.../g)]。',
      script: r'''
const shots = [...args.workspace.matchAll(/<storyboardItem\b[^>]*videoDesc="([^"]+)"[^>]*duration="([^"]+)"/g)]
  .map((match, index) => ({
    index: index + 1,
    videoDesc: match[1].trim(),
    duration: parseFloat(match[2]),
  }));
return JSON.stringify(shots);
''',
      schema: const {
        'type': 'object',
        'properties': {
          'workspace': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_regex_match_all_runtime', const {
        'workspace': '''
<scriptPlan>寒山宗门外，雪夜开场。</scriptPlan>
<storyboardItem videoDesc=" 雪夜山门 " duration="3秒" track="首帧"></storyboardItem>
<storyboardItem videoDesc="李澈拔剑" duration="2.5s" track="视频参考"></storyboardItem>
''',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用正则批量解析脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_regex_match_all_runtime');
    expect(jsonDecode(msg.content), [
      {'index': 1, 'videoDesc': '雪夜山门', 'duration': 3},
      {'index': 2, 'videoDesc': '李澈拔剑', 'duration': 2.5},
    ]);
  });

  test('自定义脚本技能：支持 RegExp 构造和 test 筛选资产', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_regexp_test_runtime',
      name: '动态正则筛选脚本运行时',
      description: '验证自定义技能兼容模型常写的 new RegExp(...).test(...)。',
      script: r'''
const allowed = new RegExp(args.typePattern, 'i');
const selected = args.assets
  .filter(asset => allowed.test(asset.type) && /^(role|scene)$/i.test(asset.type))
  .map(asset => asset.name.trim())
  .join('、');
const hasVideoPrompt = RegExp(args.promptPattern, 'i').test(args.workspace);
return JSON.stringify({
  selected,
  hasVideoPrompt,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'typePattern': {'type': 'string'},
          'promptPattern': {'type': 'string'},
          'workspace': {'type': 'string'},
          'assets': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_regexp_test_runtime', const {
        'typePattern': 'role|scene',
        'promptPattern': 'videoDesc',
        'workspace': '<storyboardItem videoDesc="雪夜山门"></storyboardItem>',
        'assets': [
          {'type': 'ROLE', 'name': ' 李澈 '},
          {'type': 'scene', 'name': '寒山宗门'},
          {'type': 'tool', 'name': '长剑'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用动态正则筛选脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_regexp_test_runtime');
    expect(jsonDecode(msg.content), {
      'selected': '李澈、寒山宗门',
      'hasVideoPrompt': true,
    });
  });

  test('自定义脚本技能：支持正则 replace 清洗工作区 XML', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_regex_replace_runtime',
      name: '正则清洗脚本运行时',
      description: '验证自定义技能兼容模型常写的 replace(/.../g, x) 文本清洗。',
      script: r'''
const cleaned = args.workspace
  .replace(/<[^>]+>/g, ' ')
  .replace(/\s+/g, ' ')
  .trim();
const firstTagRemoved = args.workspace
  .replace(/<scriptPlan>/, '')
  .startsWith('寒山宗门外');
return JSON.stringify({
  cleaned,
  firstTagRemoved,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'workspace': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_regex_replace_runtime', const {
        'workspace': '''
<scriptPlan>寒山宗门外，雪夜开场。</scriptPlan>
<storyboardItem> 雪夜山门 </storyboardItem>
<storyboardItem>李澈拔剑</storyboardItem>
''',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用正则清洗脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_regex_replace_runtime');
    expect(
      msg.content,
      '{"cleaned":"寒山宗门外，雪夜开场。 雪夜山门 李澈拔剑",'
      '"firstTagRemoved":true}',
    );
  });

  test('自定义脚本技能：支持正则 replace 的 JS 分组替换', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_regex_replace_groups_runtime',
      name: '正则分组替换脚本运行时',
      description: r'验证自定义技能兼容模型常写的 replace(/.../g, "$1") 清洗。',
      script: r'''
const compact = args.workspace
  .replace(/<storyboardItem\b[^>]*videoDesc="([^"]+)"[^>]*duration="([^"]+)"[^>]*><\/storyboardItem>/g, '$1@$2')
  .replace(/\s+/g, ' ')
  .trim();
const wrapped = args.title.replace(/^(.*)$/,'《$1》');
return JSON.stringify({ compact, wrapped });
''',
      schema: const {
        'type': 'object',
        'properties': {
          'workspace': {'type': 'string'},
          'title': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_regex_replace_groups_runtime', const {
        'workspace': '''
<storyboardItem videoDesc="雪夜山门" duration="3秒"></storyboardItem>
<storyboardItem videoDesc="李澈拔剑" duration="2.5s"></storyboardItem>
''',
        'title': '寒山篇',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用正则分组替换脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_regex_replace_groups_runtime');
    expect(jsonDecode(msg.content), {
      'compact': '雪夜山门@3秒 李澈拔剑@2.5s',
      'wrapped': '《寒山篇》',
    });
  });

  test('自定义脚本技能：支持正则 replace 回调重写工作区文本', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_regex_replace_callback_runtime',
      name: '正则回调替换脚本运行时',
      description: '验证自定义技能兼容模型常写的 replace(/.../g, (match, p1) => ...)。',
      script: r'''
const compact = args.workspace
  .replace(/<storyboardItem\b[^>]*videoDesc="([^"]+)"[^>]*duration="([^"]+)"[^>]*><\/storyboardItem>/g,
    (match, desc, duration) => `${desc.trim()}@${parseFloat(duration)}s`)
  .replace(/\s+/g, ' ')
  .trim();
const marked = args.title.replace(/^(.*)$/, (match, title) => `《${title.trim()}》`);
return JSON.stringify({ compact, marked });
''',
      schema: const {
        'type': 'object',
        'properties': {
          'workspace': {'type': 'string'},
          'title': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool(
          'custom_script_regex_replace_callback_runtime', const {
        'workspace': '''
<storyboardItem videoDesc=" 雪夜山门 " duration="3秒"></storyboardItem>
<storyboardItem videoDesc="李澈拔剑" duration="2.5s"></storyboardItem>
''',
        'title': ' 寒山篇 ',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用正则回调替换脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_regex_replace_callback_runtime');
    expect(jsonDecode(msg.content), {
      'compact': '雪夜山门@3s 李澈拔剑@2.5s',
      'marked': '《寒山篇》',
    });
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

  test('自定义脚本技能：支持对象解构 rest 保留剩余 payload', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_object_rest_runtime',
      name: '对象 rest 解构脚本运行时',
      description: '验证自定义技能兼容模型常写的 ({ id, ...payload }) => ...。',
      script: r'''
const { id: primaryId, type: primaryType, ...primaryPayload } = args.primary;
const normalized = args.assets.map(({ id, type, ...payload }) => ({
  id,
  type,
  payload: {
    ...payload,
    name: payload.name.trim(),
    inheritedScene: primaryPayload.scene,
  },
}));
return JSON.stringify({
  primaryId,
  primaryType,
  primaryPayloadKeys: Object.keys(primaryPayload).sort().join('|'),
  normalized,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'primary': {'type': 'object'},
          'assets': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_object_rest_runtime', const {
        'primary': {
          'id': 1,
          'type': 'role',
          'name': ' 李澈 ',
          'scene': '寒山宗门',
          'temporary': true,
        },
        'assets': [
          {
            'id': 101,
            'type': 'role',
            'name': ' 沈微 ',
            'prompt': '白衣剑修',
          },
          {
            'id': 202,
            'type': 'scene',
            'name': ' 山门 ',
            'weather': '雪夜',
          },
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用对象 rest 解构脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_object_rest_runtime');
    expect(jsonDecode(msg.content), {
      'primaryId': 1,
      'primaryType': 'role',
      'primaryPayloadKeys': 'name|scene|temporary',
      'normalized': [
        {
          'id': 101,
          'type': 'role',
          'payload': {
            'name': '沈微',
            'prompt': '白衣剑修',
            'inheritedScene': '寒山宗门',
          },
        },
        {
          'id': 202,
          'type': 'scene',
          'payload': {
            'name': '山门',
            'weather': '雪夜',
            'inheritedScene': '寒山宗门',
          },
        },
      ],
    });
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

  test('自定义脚本技能：支持 localeCompare 按名称排序资产', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_locale_compare_runtime',
      name: '名称排序脚本运行时',
      description: '验证自定义技能兼容模型常写的 name.localeCompare(...) 排序。',
      script: r'''
const ordered = args.assets
  .filter(asset => asset.enabled !== false)
  .sort((a, b) => a.name.trim().localeCompare(b.name.trim()))
  .map((asset, index) => `${index + 1}.${asset.name.trim()}`)
  .join('、');
return `资产顺序：${ordered}`;
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
                'enabled': {'type': 'boolean'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_locale_compare_runtime', const {
        'assets': [
          {'name': ' C-寒山宗门 '},
          {'name': 'A-李澈'},
          {'name': 'D-废稿', 'enabled': false},
          {'name': ' B-沈微 '},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用名称排序脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_locale_compare_runtime');
    expect(msg.content, '资产顺序：1.A-李澈、2.B-沈微、3.C-寒山宗门');
  });

  test('自定义脚本技能：支持 Array.sort 默认字符串排序', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_default_sort_runtime',
      name: '默认排序脚本运行时',
      description: '验证自定义技能兼容模型常写的 names.sort() 默认排序。',
      script: r'''
const names = args.assets.map(asset => asset.name.trim());
const returned = names.sort();
returned.push('尾声');
return JSON.stringify({
  sameObject: returned === names,
  names: names.join('>'),
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
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_default_sort_runtime', const {
        'assets': [
          {'name': ' C-寒山宗门 '},
          {'name': 'A-李澈'},
          {'name': ' B-沈微 '},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用默认排序脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_default_sort_runtime');
    expect(jsonDecode(msg.content), {
      'sameObject': true,
      'names': 'A-李澈>B-沈微>C-寒山宗门>尾声',
    });
  });

  test('自定义脚本技能：支持 Array.sort 原地排序语义', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_sort_mutation_runtime',
      name: '原地排序脚本运行时',
      description: '验证自定义技能兼容模型常写的 assets.sort(...); assets.map(...) 语义。',
      script: r'''
const assets = args.assets;
const returned = assets.sort((a, b) => a.priority - b.priority);
return JSON.stringify({
  assets: assets.map(asset => asset.name.trim()).join('>'),
  returned: returned.map(asset => asset.name.trim()).join('>'),
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
                'priority': {'type': 'number'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_sort_mutation_runtime', const {
        'assets': [
          {'name': ' 李澈 ', 'priority': 30},
          {'name': '寒山宗门', 'priority': 10},
          {'name': '沈微', 'priority': 20},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用原地排序脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_sort_mutation_runtime');
    expect(jsonDecode(msg.content), {
      'assets': '寒山宗门>沈微>李澈',
      'returned': '寒山宗门>沈微>李澈',
    });
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

  test('自定义脚本技能：支持 findIndex 定位首个待处理分镜', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_find_index_runtime',
      name: '分镜定位脚本运行时',
      description: '验证自定义技能兼容模型常写的 findIndex 定位待处理分镜。',
      script: r'''
const draftIndex = args.storyboards.findIndex(
  shot => !shot.prompt?.trim() && !!shot.videoDesc?.trim()
);
const candidate = draftIndex >= 0 ? args.storyboards[draftIndex] : null;
return JSON.stringify({
  draftIndex: draftIndex,
  oneBased: draftIndex + 1,
  desc: candidate?.videoDesc?.trim() ?? '无',
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
                'prompt': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_find_index_runtime', const {
        'storyboards': [
          {'videoDesc': '雪夜山门', 'prompt': '已有提示词'},
          {'videoDesc': ' 李澈拔剑 ', 'prompt': ''},
          {'videoDesc': '', 'prompt': ''},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用分镜定位脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_find_index_runtime');
    expect(jsonDecode(msg.content), {
      'draftIndex': 1,
      'oneBased': 2,
      'desc': '李澈拔剑',
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

  test('自定义脚本技能：支持 reduce 回调 index 和 source 参数', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_reduce_index_source_runtime',
      name: '归并索引脚本运行时',
      description: '验证自定义技能兼容模型常写的 reduce((acc, item, index, array) => ...)。',
      script: r'''
const lines = args.shots.reduce((list, shot, index, all) => [
  ...list,
  `${index + 1}/${all.length}.${shot.videoDesc.trim()}:${shot.duration}s`,
], []);
return JSON.stringify({
  lines: lines.join('、'),
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
                'videoDesc': {'type': 'string'},
                'duration': {'type': 'number'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool(
        'custom_script_reduce_index_source_runtime',
        const {
          'shots': [
            {'videoDesc': ' 雪夜山门 ', 'duration': 2},
            {'videoDesc': '李澈拔剑', 'duration': 3},
            {'videoDesc': '沈微回眸 ', 'duration': 4},
          ],
        },
      ),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用归并索引脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_reduce_index_source_runtime');
    expect(jsonDecode(msg.content), {
      'lines': '1/3.雪夜山门:2s、2/3.李澈拔剑:3s、3/3.沈微回眸:4s',
    });
  });

  test('自定义脚本技能：支持 reduce 省略初始值时使用首项作为累加器', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_reduce_no_initial_runtime',
      name: '无初始值归并脚本运行时',
      description: '验证自定义技能兼容模型常写的 reduce(callback) 写法。',
      script: r'''
const longest = args.durations.reduce((best, value) => value > best ? value : best);
const heroShot = args.shots.reduce((best, shot) =>
  shot.score > best.score ? shot : best
);
return JSON.stringify({
  longest,
  hero: `${heroShot.index}.${heroShot.videoDesc.trim()}`,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'durations': {
            'type': 'array',
            'items': {'type': 'number'},
          },
          'shots': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_reduce_no_initial_runtime', const {
        'durations': [2, 8, 5],
        'shots': [
          {'index': 1, 'videoDesc': ' 李澈入场 ', 'score': 4},
          {'index': 2, 'videoDesc': '沈微拔剑', 'score': 9},
          {'index': 3, 'videoDesc': '群像对峙', 'score': 6},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用无初始值归并脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_reduce_no_initial_runtime');
    expect(msg.content, isNot(startsWith('执行失败')));
    expect(jsonDecode(msg.content), {
      'longest': 8,
      'hero': '2.沈微拔剑',
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

  test('自定义脚本技能：支持数组 includes 按 id 选择资产', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_array_includes_runtime',
      name: '数组包含脚本运行时',
      description: '验证自定义技能兼容模型常写的 selectedIds.includes(asset.id)。',
      script: r'''
const selectedNames = args.assets
  .filter(asset => args.selectedIds.includes(asset.id))
  .map(asset => asset.name.trim())
  .join('、');
const hasMissing = args.selectedIds.includes(999);
return JSON.stringify({
  selectedNames,
  hasMissing,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'selectedIds': {
            'type': 'array',
            'items': {'type': 'number'},
          },
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'number'},
                'name': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_array_includes_runtime', const {
        'selectedIds': [10, 103],
        'assets': [
          {'id': 1, 'name': '误匹配角色'},
          {'id': 10, 'name': ' 李澈 '},
          {'id': 103, 'name': ' 沈微 '},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用数组包含脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_array_includes_runtime');
    expect(jsonDecode(msg.content), {
      'selectedNames': '李澈、沈微',
      'hasMissing': false,
    });
  });

  test('自定义脚本技能：支持数组 indexOf 和 lastIndexOf 搜索', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_array_index_runtime',
      name: '数组索引搜索脚本运行时',
      description:
          '验证自定义技能兼容模型常写的 selectedIds.indexOf(asset.id) 和 list.lastIndexOf(id)。',
      script: r'''
const selectedNames = args.assets
  .filter(asset => args.selectedIds.indexOf(asset.id) >= 0)
  .map(asset => asset.name.trim())
  .join('、');
return JSON.stringify({
  selectedNames,
  firstRole: args.types.indexOf('role'),
  secondRoleFromOne: args.types.indexOf('role', 1),
  missingSceneFromTail: args.types.indexOf('scene', -1),
  lastRole: args.types.lastIndexOf('role'),
  lastRoleBeforeTail: args.types.lastIndexOf('role', 1),
  negativeLastScene: args.types.lastIndexOf('scene', -2),
  missingId: args.selectedIds.indexOf(999),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'selectedIds': {
            'type': 'array',
            'items': {'type': 'number'},
          },
          'types': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'assets': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'number'},
                'name': {'type': 'string'},
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_array_index_runtime', const {
        'selectedIds': [10, 103],
        'types': ['role', 'scene', 'role', 'tool'],
        'assets': [
          {'id': 1, 'name': '误匹配角色'},
          {'id': 10, 'name': ' 李澈 '},
          {'id': 103, 'name': ' 沈微 '},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用数组索引搜索脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_array_index_runtime');
    expect(jsonDecode(msg.content), {
      'selectedNames': '李澈、沈微',
      'firstRole': 0,
      'secondRoleFromOne': 2,
      'missingSceneFromTail': -1,
      'lastRole': 2,
      'lastRoleBeforeTail': 0,
      'negativeLastScene': 1,
      'missingId': -1,
    });
  });

  test('自定义脚本技能：支持函数和方法调用参数 spread', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_call_spread_runtime',
      name: '调用参数展开脚本运行时',
      description: '验证自定义技能兼容模型常写的 Math.max(...list) 和 push(...items)。',
      script: r'''
const durations = args.shots.map(shot => shot.duration);
const names = [];
names.push(...args.assets.map(asset => asset.name.trim()));
return JSON.stringify({
  maxDuration: Math.max(...durations),
  minDuration: Math.min(...durations),
  names: names.join('、'),
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
      AgentTurnResult.tool('custom_script_call_spread_runtime', const {
        'shots': [
          {'duration': 2},
          {'duration': 5},
          {'duration': 3},
        ],
        'assets': [
          {'name': ' 李澈 '},
          {'name': '沈微'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用参数展开脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_call_spread_runtime');
    expect(jsonDecode(msg.content), {
      'maxDuration': 5,
      'minDuration': 2,
      'names': '李澈、沈微',
    });
  });

  test('自定义脚本技能：支持数组队列和插入变更方法', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_array_mutation_runtime',
      name: '数组变更脚本运行时',
      description: '验证自定义技能兼容模型常写的 at/pop/shift/unshift/splice。',
      script: r'''
const queue = args.shots.map(shot => shot.name.trim());
const originalLast = queue.at(-1);
const removedFirst = queue.shift();
const removedLast = queue.pop();
queue.unshift('预告');
const replaced = queue.splice(1, 1, '补拍', '转场');
return JSON.stringify({
  originalLast,
  removedFirst,
  removedLast,
  replaced: replaced.join('、'),
  queue: queue.join('>'),
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
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_array_mutation_runtime', const {
        'shots': [
          {'name': ' 开场 '},
          {'name': '追击'},
          {'name': ' 对峙 '},
          {'name': '收束'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用数组变更脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_array_mutation_runtime');
    expect(jsonDecode(msg.content), {
      'originalLast': '收束',
      'removedFirst': '开场',
      'removedLast': '收束',
      'replaced': '追击',
      'queue': '预告>补拍>转场>对峙',
    });
  });

  test('自定义脚本技能：支持 for in 遍历对象分组', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_for_in_runtime',
      name: '对象分组遍历脚本运行时',
      description: '验证自定义技能兼容模型常写的 for...in 动态读取分组对象。',
      script: r'''
const labels = [];
for (const type in args.groups) {
  const items = args.groups[type];
  if (!Array.isArray(items)) {
    continue;
  }
  labels.push(`${type}:${items.map(item => item.name.trim()).join('/')}`);
}
return labels.join('、');
''',
      schema: const {
        'type': 'object',
        'properties': {
          'groups': {'type': 'object'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_for_in_runtime', const {
        'groups': {
          'role': [
            {'name': ' 李澈 '},
            {'name': '沈微'},
          ],
          'meta': {'version': 1},
          'scene': [
            {'name': '寒山宗门'},
          ],
        },
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用对象分组遍历脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_for_in_runtime');
    expect(msg.content, 'role:李澈/沈微、scene:寒山宗门');
  });

  test('自定义脚本技能：支持 in 操作符检查对象和数组成员', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_in_operator_runtime',
      name: 'in 操作符脚本运行时',
      description: '验证自定义技能兼容模型常写的 if (!(type in grouped)) 分组写法。',
      script: r'''
const grouped = {};
for (const asset of args.assets) {
  const type = asset.type;
  if (!(type in grouped)) {
    grouped[type] = [];
  }
  grouped[type].push(asset.name.trim());
}
return JSON.stringify({
  role: grouped.role.join('/'),
  scene: grouped.scene.join('/'),
  hasRole: 'role' in grouped,
  hasTool: 'tool' in grouped,
  firstAssetExists: 0 in args.assets,
  missingAssetExists: 5 in args.assets,
  firstNameExists: 'name' in args.assets[0],
});
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
      AgentTurnResult.tool('custom_script_in_operator_runtime', const {
        'assets': [
          {'type': 'role', 'name': ' 李澈 '},
          {'type': 'scene', 'name': '寒山宗门'},
          {'type': 'role', 'name': ' 沈微 '},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 in 操作符脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_in_operator_runtime');
    expect(jsonDecode(msg.content), {
      'role': '李澈/沈微',
      'scene': '寒山宗门',
      'hasRole': true,
      'hasTool': false,
      'firstAssetExists': true,
      'missingAssetExists': false,
      'firstNameExists': true,
    });
  });

  test('自定义脚本技能：支持 delete 操作符清理对象字段', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_delete_operator_runtime',
      name: 'delete 操作符脚本运行时',
      description: '验证自定义技能兼容模型常写的 delete payload.debug 清理写法。',
      script: r'''
const payload = Object.assign({}, args.payload);
const removedDebug = delete payload.debug;
const removedMissing = delete payload.missing;
for (const key of args.removeKeys) {
  delete payload[key];
}
payload.assets = args.assets;
delete payload.assets[0].tempPrompt;
delete payload.assets[1].discard;
delete payload.refs[1];
return JSON.stringify({
  removedDebug,
  removedMissing,
  hasDebug: 'debug' in payload,
  hasDraft: 'draft' in payload,
  hasKeep: 'keep' in payload,
  firstHasTemp: 'tempPrompt' in payload.assets[0],
  secondHasDiscard: 'discard' in payload.assets[1],
  refs: payload.refs,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'payload': {'type': 'object'},
          'removeKeys': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'assets': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_delete_operator_runtime', const {
        'payload': {
          'debug': true,
          'draft': 'remove',
          'keep': 'ok',
          'refs': ['A', 'B', 'C'],
        },
        'removeKeys': ['draft'],
        'assets': [
          {'name': '李澈', 'tempPrompt': '草稿'},
          {'name': '寒山宗门', 'discard': true},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 delete 操作符脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_delete_operator_runtime');
    expect(jsonDecode(msg.content), {
      'removedDebug': true,
      'removedMissing': true,
      'hasDebug': false,
      'hasDraft': false,
      'hasKeep': true,
      'firstHasTemp': false,
      'secondHasDiscard': false,
      'refs': ['A', null, 'C'],
    });
  });

  test('自定义脚本技能：支持对象属性和数组索引赋值', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_property_assignment_runtime',
      name: '属性赋值脚本运行时',
      description:
          '验证自定义技能兼容模型常写的 grouped[type] = [] 和 asset.priority = index。',
      script: r'''
const grouped = {};
const ordered = [];
for (const asset of args.assets) {
  const type = asset.type;
  if (!grouped[type]) {
    grouped[type] = [];
  }
  asset.priority = grouped[type].length + 1;
  grouped[type].push(`${asset.priority}.${asset.name.trim()}`);
}
ordered[0] = grouped.role.join('/');
ordered[1] = grouped.scene.join('/');
return JSON.stringify({
  role: ordered[0],
  scene: ordered[1],
  roleCount: grouped.role.length,
});
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
      AgentTurnResult.tool('custom_script_property_assignment_runtime', const {
        'assets': [
          {'type': 'role', 'name': ' 李澈 '},
          {'type': 'scene', 'name': '寒山宗门'},
          {'type': 'role', 'name': ' 沈微 '},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用属性赋值脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_property_assignment_runtime');
    expect(jsonDecode(msg.content), {
      'role': '1.李澈/2.沈微',
      'scene': '1.寒山宗门',
      'roleCount': 2,
    });
  });

  test('自定义脚本技能：支持对象属性和数组索引复合更新', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_member_update_runtime',
      name: '成员更新脚本运行时',
      description:
          '验证自定义技能兼容 stats[type]++、asset.score += n 和 timeline[0] += n。',
      script: r'''
const stats = {};
const timeline = [0, 100];
for (const asset of args.assets) {
  const type = asset.type;
  if (!stats[type]) {
    stats[type] = 0;
  }
  stats[type]++;
  asset.score = 10;
  asset.score += asset.weight;
  asset.score--;
  timeline[0] += asset.duration;
  timeline[1] -= 5;
}
return JSON.stringify({
  roleCount: stats.role,
  sceneCount: stats.scene,
  firstScore: args.assets[0].score,
  totalDuration: timeline[0],
  tail: timeline[1],
});
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
      AgentTurnResult.tool('custom_script_member_update_runtime', const {
        'assets': [
          {'type': 'role', 'duration': 2, 'weight': 4},
          {'type': 'scene', 'duration': 3, 'weight': 1},
          {'type': 'role', 'duration': 5, 'weight': 2},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用成员更新脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_member_update_runtime');
    expect(jsonDecode(msg.content), {
      'roleCount': 2,
      'sceneCount': 1,
      'firstScore': 13,
      'totalDuration': 10,
      'tail': 85,
    });
  });

  test('自定义脚本技能：支持对象属性和数组索引逻辑赋值', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_logical_assignment_runtime',
      name: '逻辑赋值脚本运行时',
      description: '验证自定义技能兼容 grouped[type] ||= [] 和 stats[type] ??= 0。',
      script: r'''
const grouped = {};
const stats = {};
const flags = [true, false];
for (const asset of args.assets) {
  const type = asset.type;
  grouped[type] ||= [];
  stats[type] ??= 0;
  stats[type]++;
  grouped[type].push(asset.name.trim());
}
flags[0] &&= args.allowOverwrite;
flags[1] ||= grouped.scene.length > 0;
stats.role ??= 100;
stats.tool ??= 7;
return JSON.stringify({
  role: grouped.role.join('/'),
  scene: grouped.scene.join('/'),
  roleCount: stats.role,
  toolCount: stats.tool,
  firstFlag: flags[0],
  secondFlag: flags[1],
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'allowOverwrite': {'type': 'boolean'},
          'assets': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_logical_assignment_runtime', const {
        'allowOverwrite': false,
        'assets': [
          {'type': 'role', 'name': ' 李澈 '},
          {'type': 'scene', 'name': '寒山宗门'},
          {'type': 'role', 'name': '沈微'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用逻辑赋值脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_logical_assignment_runtime');
    expect(jsonDecode(msg.content), {
      'role': '李澈/沈微',
      'scene': '寒山宗门',
      'roleCount': 2,
      'toolCount': 7,
      'firstFlag': false,
      'secondFlag': true,
    });
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

  test('SkillRuntime parses ToonFlow-style folded frontmatter and hyphen names',
      () {
    final skillDir = Directory(p.join(dir.path, 'skills', 'story-polisher'))
      ..createSync(recursive: true);
    final skillFile = File(p.join(skillDir.path, 'SKILL.md'))
      ..writeAsStringSync('''
---
name: "story-polisher"
description: >
  短剧故事润色技能，
  负责压缩旁白并强化前三秒钩子。
---

请把故事节奏压到更适合短剧。
''');

    final skill = engine.saveMarkdownAgentSkill(
      filePath: skillFile.path,
      attribution: 'script_agent_execution',
    );

    expect(skill.id, 'story-polisher');
    expect(skill.name, 'story-polisher');
    expect(skill.description, '短剧故事润色技能， 负责压缩旁白并强化前三秒钩子。');

    final activated = engine.activateAgentSkill('story-polisher');
    expect(activated.name, 'story-polisher');
    expect(activated.content, contains('请把故事节奏压到更适合短剧。'));
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

  test('SkillRuntime lists ToonFlow workspace and attached skill resources',
      () {
    final skillFile = _writeSkillFixture(
      dir,
      id: 'director_style',
      body: '主技能：导演规划要先定镜头节奏。',
      extraFiles: {
        'references/local.md': '本技能资源：镜头节奏先急后缓。',
      },
    );
    final workspaceFile = File(p.join(
      dir.path,
      'skills',
      'production_skills',
      'storyboard_table_techniques.md',
    ))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('工作区技法：分镜表要含景别和运镜。');
    final attachedReadme = File(p.join(
      dir.path,
      'skills',
      'story_skills',
      'Xianxia_fantasy',
      'README.md',
    ))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('附加题材：仙侠短剧先给宗门压迫。');
    final attachedNested = File(p.join(
      dir.path,
      'skills',
      'story_skills',
      'Xianxia_fantasy',
      'driector_skills',
      'director_planning_narrative.md',
    ))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('附加叙事：前三秒给强钩子。');

    engine.saveMarkdownAgentSkill(
      filePath: skillFile.path,
      workspaceDirs: const ['production_skills'],
      attachedSkillDirs: const ['story_skills/Xianxia_fantasy'],
    );

    final activated = engine.activateAgentSkill('director_style');
    expect(activated.resourceFiles, [
      'references/local.md',
      'production_skills/storyboard_table_techniques.md',
      'story_skills/Xianxia_fantasy/README.md',
      'story_skills/Xianxia_fantasy/driector_skills/director_planning_narrative.md',
    ]);
    expect(
      engine.readAgentSkillFile('director_style', 'references/local.md'),
      '本技能资源：镜头节奏先急后缓。',
    );
    expect(
      engine.readAgentSkillFile(
        'director_style',
        p
            .relative(workspaceFile.path, from: p.join(dir.path, 'skills'))
            .replaceAll('\\', '/'),
      ),
      '工作区技法：分镜表要含景别和运镜。',
    );
    expect(
      engine.readAgentSkillFile(
        'director_style',
        p
            .relative(attachedReadme.path, from: p.join(dir.path, 'skills'))
            .replaceAll('\\', '/'),
      ),
      '附加题材：仙侠短剧先给宗门压迫。',
    );
    expect(
      engine.readAgentSkillFile(
        'director_style',
        p
            .relative(attachedNested.path, from: p.join(dir.path, 'skills'))
            .replaceAll('\\', '/'),
      ),
      '附加叙事：前三秒给强钩子。',
    );
  });

  test('SkillRuntime seeds ToonFlow root markdown skills with attribution', () {
    final skillsRoot = Directory(p.join(dir.path, 'toonflow-skills'))
      ..createSync(recursive: true);
    File(p.join(skillsRoot.path, 'script_execution_skeleton.md'))
        .writeAsStringSync('''
---
name: script_execution_skeleton.md
description: 故事骨架搭建 Agent
---

# 故事骨架搭建 Agent
请读取事件并输出 <storySkeleton>。
''');
    File(p.join(skillsRoot.path, 'production_execution_storyboard_table.md'))
        .writeAsStringSync('''
---
name: production_execution_storyboard_table.md
description: >-
  分镜表构建 Agent
---

# 分镜表构建
请输出 <storyboardTable>。
''');
    File(p.join(
      skillsRoot.path,
      'production_skills',
      'storyboard_table_techniques.md',
    ))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('分镜表技法：必须包含景别、运镜、时长。');

    final seeded = engine.seedToonFlowMarkdownAgentSkills(skillsRoot.path);

    expect(seeded.map((skill) => skill.id), [
      'script_execution_skeleton.md',
      'production_execution_storyboard_table.md',
    ]);
    expect(
      engine
          .agentSkills(attribution: 'script_execution_skeleton')
          .map((skill) => skill.id),
      contains('script_execution_skeleton.md'),
    );
    expect(
      engine
          .agentSkills(attribution: 'production_execution_storyboard_table')
          .map((skill) => skill.id),
      contains('production_execution_storyboard_table.md'),
    );

    final skeleton = engine.activateAgentSkill('script_execution_skeleton.md');
    expect(skeleton.content, contains('请读取事件并输出'));

    final table =
        engine.activateAgentSkill('production_execution_storyboard_table.md');
    expect(table.description, '分镜表构建 Agent');
    expect(table.resourceFiles,
        contains('production_skills/storyboard_table_techniques.md'));
    expect(
      engine.readAgentSkillFile(
        'production_execution_storyboard_table.md',
        'production_skills/storyboard_table_techniques.md',
      ),
      '分镜表技法：必须包含景别、运镜、时长。',
    );
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
    expect(readSkillTool.schema['required'], isNull);
    expect(readSkillProperties.keys,
        containsAll(['filePath', 'path', 'file', 'filename', 'relativePath']));
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

  test('SkillRuntime 自动注入 ToonFlow stage 主技能正文到 system prompt', () async {
    final skillsRoot = Directory(p.join(dir.path, 'toonflow-main-skills'))
      ..createSync(recursive: true);
    final mainSkillFile =
        File(p.join(skillsRoot.path, 'script_agent_decision.md'));
    mainSkillFile.writeAsStringSync('''
---
name: script_agent_decision
description: ToonFlow 剧本决策主技能
---

ToonFlow 主技能正文：先判断用户意图，再选择是否调用子 Agent。
''');
    final optionalSkill = _writeSkillFixture(
      dir,
      id: 'style_polisher',
      body: '普通可选技能正文：只有 activate_skill 后才应进入上下文。',
    );
    engine.seedToonFlowMarkdownAgentSkills(skillsRoot.path);
    engine.saveMarkdownAgentSkill(
      filePath: optionalSkill.path,
      attribution: 'script_agent_decision',
    );

    gateway.turns = [const AgentTurnResult.text('剧本决策已记录。')];
    await engine.sendAgentMessage(
      projectId,
      '规划前三集',
      autoMode: false,
      family: agentFamilyScript,
    );

    expect(gateway.lastSystem, contains('ToonFlow stage 主技能'));
    expect(gateway.lastSystem, contains('先判断用户意图'));
    expect(gateway.lastSystem, contains('<name>style_polisher</name>'));
    expect(gateway.lastSystem, isNot(contains('普通可选技能正文')));
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

  test('SkillRuntime read_skill_file 支持模型常见文件路径别名', () async {
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
      AgentTurnResult.tool('read_skill_file', const {
        'file': 'references/rules.md',
      }),
    ];

    await engine.sendAgentMessage(projectId, '激活后读取技能规则', autoMode: true);

    final read = engine.agentMessages(projectId).lastWhere(
          (message) => message.toolName == 'read_skill_file',
        );
    expect(read.content, contains('规则：每句台词不超过二十字。'));

    final readSkillFileTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'read_skill_file');
    final properties = readSkillFileTool.schema['properties'] as Map;
    expect(properties, contains('file'));
    expect(properties, contains('filename'));
    expect(properties, contains('relativePath'));
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

  test('SkillRuntime 子 Agent 内部激活后 read_skill_file 继承技能名称', () async {
    final skillFile = _writeSkillFixture(
      dir,
      id: 'story_skeleton_style',
      body: '''
技能正文：故事骨架必须按短剧前三秒强冲突组织。
''',
      extraFiles: {
        'references/beat.md': '节奏：每集结尾必须留钩子。',
      },
    );
    engine.saveMarkdownAgentSkill(
      filePath: skillFile.path,
      attribution: 'script_agent_execution',
    );

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'prompt': '按技能搭建前三集故事骨架'},
      ),
      AgentTurnResult.tool(
        'activate_skill',
        const {'name': 'story_skeleton_style'},
      ),
      AgentTurnResult.tool(
        'read_skill_file',
        const {'filePath': 'references/beat.md'},
      ),
      const AgentTurnResult.text('<storySkeleton>前三集强冲突骨架</storySkeleton>'),
    ];

    await engine.sendAgentMessage(projectId, '先做故事骨架', autoMode: false);

    expect(gateway.stages, [
      'scriptAgent:decisionAgent',
      'scriptAgent:storySkeletonAgent',
      'scriptAgent:storySkeletonAgent',
      'scriptAgent:storySkeletonAgent',
    ]);
    expect(gateway.systems[2], contains('已激活 Agent 技能'));
    expect(gateway.systems[2], contains('story_skeleton_style'));
    expect(
      gateway.lastMessages.map((message) => message['content']).join('\n'),
      contains('节奏：每集结尾必须留钩子。'),
    );
    final data = _scriptAgentWorkData(db, projectId);
    expect(data['storySkeleton'], '前三集强冲突骨架');
  });

  test('SkillRuntime 生产子 Agent 内部激活后 read_skill_file 继承技能名称', () async {
    final skillFile = _writeSkillFixture(
      dir,
      id: 'director_plan_style',
      body: '''
技能正文：导演规划必须先明确镜头节奏。
''',
      extraFiles: {
        'references/lens.md': '镜头：先近景压迫，再横移揭示战场。',
      },
    );
    engine.saveMarkdownAgentSkill(
      filePath: skillFile.path,
      attribution: 'production_agent_execution',
    );
    final scriptId = engine.addScript(
      projectId: projectId,
      name: '第一集',
      content: '李澈在战火中入宗。',
    );

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '按技能做第一集导演规划', 'scriptId': scriptId},
      ),
      AgentTurnResult.tool(
        'activate_skill',
        const {'name': 'director_plan_style'},
      ),
      AgentTurnResult.tool(
        'read_skill_file',
        const {'filePath': 'references/lens.md'},
      ),
      const AgentTurnResult.text('<scriptPlan>冷色近景压迫后横移揭示战场</scriptPlan>'),
    ];

    await engine.sendAgentMessage(projectId, '制作导演计划', autoMode: false);

    expect(gateway.stages, [
      'productionAgent:decisionAgent',
      'productionAgent:directorPlanAgent',
      'productionAgent:directorPlanAgent',
      'productionAgent:directorPlanAgent',
    ]);
    expect(gateway.systems[2], contains('已激活 Agent 技能'));
    expect(gateway.systems[2], contains('director_plan_style'));
    expect(
      gateway.lastMessages.map((message) => message['content']).join('\n'),
      contains('镜头：先近景压迫，再横移揭示战场。'),
    );
    final data = _productionAgentWorkData(db, projectId, scriptId);
    expect(data['scriptPlan'], '冷色近景压迫后横移揭示战场');
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

    final matched = await engine.searchAgentMemories(projectId, '寒山');
    expect(matched.map((item) => item.id), [id]);
    expect(matched.single.score, greaterThan(0));
    expect(matched.single.matchedTokens, contains('寒山'));

    gateway.turns = [const AgentTurnResult.text('收到')];
    await engine.sendAgentMessage(projectId, '下一场写寒山少主出场', autoMode: false);

    expect(gateway.lastSystem, contains('长期记忆'));
    expect(gateway.lastSystem, contains('<note id="$id"'));
    expect(gateway.lastSystem, contains('type="note"'));
    expect(gateway.lastSystem, contains('name="主角设定"'));
    expect(
      gateway.lastSystem,
      contains('createTime="${memories.single.createdAt}"'),
    );
    expect(gateway.lastSystem, contains('score="'));
    expect(gateway.lastSystem, contains('matchedTokens="寒山'));
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

    final injected = RegExp(r'<note ').allMatches(gateway.lastSystem).length;
    expect(injected, 2);
  });

  test('长期记忆：写入本地 embedding，搜索旧记录时自动回填', () async {
    engine.setAgentMemorySettings(
      modelOnnxFile: const ['custom-embedding', 'onnx', 'model_fp32.onnx'],
      modelDtype: 'fp32',
    );
    final id = engine.saveAgentMemory(
      projectId,
      name: '战力设定',
      content: '李澈是寒山剑修，出手克制，不能滥杀。',
    );
    var row =
        db.select('SELECT embedding FROM memories WHERE id=?', [id]).single;
    expect(row['embedding'], isNot(''));
    expect(row['embedding'], contains('李澈'));
    var decoded = jsonDecode(row['embedding'] as String) as Map;
    expect(decoded['__token_embedding_v1'], 1);
    expect(
      decoded['modelOnnxFile'],
      ['custom-embedding', 'onnx', 'model_fp32.onnx'],
    );
    expect(decoded['modelDtype'], 'fp32');
    expect(decoded['embedding'], isA<Map>());

    db.execute('UPDATE memories SET embedding=? WHERE id=?', ['', id]);
    final matched = await engine.searchAgentMemories(projectId, '李澈剑修');
    expect(matched.map((item) => item.id), [id]);

    row = db.select('SELECT embedding FROM memories WHERE id=?', [id]).single;
    expect(row['embedding'], isNot(''), reason: '旧记忆检索时应回填本地 embedding');
    decoded = jsonDecode(row['embedding'] as String) as Map;
    expect(decoded['__token_embedding_v1'], 1);
    expect(decoded['modelDtype'], 'fp32');
  });

  test('长期记忆：搜索可通过绑定 embedding 模型召回语义相关 note', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['binding.agent_embedding', 'fake:embed'],
    );
    final keepId = engine.saveAgentMemory(
      projectId,
      name: 'Mentor Bond',
      content:
          'mentor bond rule: Li Che must protect Shen Wei before entering Hanshan.',
    );
    engine.saveAgentMemory(
      projectId,
      name: 'Market Beat',
      content: 'market comedy beat with no relationship constraint.',
    );
    gateway.embeddingForText = (input) {
      final normalized = input.toLowerCase();
      if (normalized.contains('mentor bond') || input.contains('师承羁绊')) {
        return const [1, 0];
      }
      return const [0, 1];
    };

    final matched = await engine.searchAgentMemories(projectId, '师承羁绊');

    expect(gateway.embeddingInputs, contains('师承羁绊'));
    expect(matched.map((item) => item.id), [keepId]);
    expect(matched.single.content, contains('mentor bond rule'));
    final stored = db.select('SELECT embedding FROM memories WHERE id=?',
        [keepId]).single['embedding'] as String;
    expect(stored, contains('__gateway_embedding_v1'));
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

  test('Agent 记忆：decision Agent 工具调用结果写入审计记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    gateway.turns = [
      AgentTurnResult.tool('get_status', const {}),
    ];

    await engine.sendAgentMessage(projectId, '看一下项目进度', autoMode: false);

    final rows = db.select(
      'SELECT role,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', 'message'],
    );

    final toolAudit = rows.singleWhere(
      (row) => row['role'] == 'assistant:decision:tool',
    );
    expect(toolAudit['content'], contains('工具 get_status 执行结果'));
    expect(toolAudit['content'], contains('章节 0 个'));
  });

  test('Agent 记忆：工具审计记忆默认不参与自动摘要', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '2'],
    );
    gateway.turns = [
      AgentTurnResult.tool('get_status', const {}),
    ];

    await engine.sendAgentMessage(projectId, '看一下寒山项目进度', autoMode: false);

    final rows = db.select(
      'SELECT role,content,summarized FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', 'message'],
    );
    expect(rows.map((row) => row['role']),
        [agentRoleUser, 'assistant:decision:tool', agentRoleTool]);
    expect(rows.map((row) => row['summarized']), [0, 1, 1]);
    expect(rows[1]['content'], contains('工具 get_status 执行结果'));
    expect(rows.last['content'], contains('章节 0 个'));

    final summaries = db.select(
      'SELECT content FROM memories WHERE isolationKey=? AND type=?',
      ['scriptAgent:$projectId', 'summary'],
    );
    expect(summaries, isEmpty);
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

  test('Agent 记忆：deepRetrieve 工具支持 query/question/text 自然别名', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'alias_question_memory',
        '',
        '进度记忆：寒山分镜已经完成，下一步应生成首帧。',
        now,
        embeddingJson('进度记忆：寒山分镜已经完成，下一步应生成首帧。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleAssistant,
        0,
        agentMemoryTypeMessage,
      ],
    );

    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'question': '寒山下一步进度',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '继续下一步',
      autoMode: false,
    );

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = deepRetrieveTool.schema['properties'] as Map;
    expect(properties, contains('query'));
    expect(properties, contains('question'));
    expect(properties, contains('text'));
    expect(properties, contains('prompt'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(
      payload['memories'],
      contains('进度记忆：寒山分镜已经完成，下一步应生成首帧。'),
    );
  });

  test('Agent 记忆：deepRetrieve 工具支持按 role 过滤 summary 展开的原始 message', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'role_filter_user_msg',
        '',
        '用户约束：寒山线里李澈必须保护沈微。',
        now,
        embeddingJson('用户约束：寒山线里李澈必须保护沈微。'),
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
        'role_filter_assistant_msg',
        '',
        '助手确认：寒山线会保留沈微被救下的桥段。',
        now + 1,
        embeddingJson('助手确认：寒山线会保留沈微被救下的桥段。'),
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
        'role_filter_summary',
        '寒山线约束',
        '寒山线里李澈保护沈微，助手已确认桥段保留。',
        now + 2,
        embeddingJson('寒山线里李澈保护沈微，助手已确认桥段保留。'),
        'scriptAgent:$projectId',
        jsonEncode(['role_filter_user_msg', 'role_filter_assistant_msg']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'keyword': '寒山沈微',
        'roles': [agentRoleUser],
      }),
    ];

    await engine.sendAgentMessage(projectId, '按角色过滤历史记忆', autoMode: false);

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    expect((deepRetrieveTool.schema['properties'] as Map), contains('roles'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], ['用户约束：寒山线里李澈必须保护沈微。']);
    final records = payload['records'] as List;
    expect(records, hasLength(1));
    expect((records.single as Map<String, dynamic>)['role'], agentRoleUser);
  });

  test('Agent 记忆：deepRetrieve 工具支持 excludeRoles 排除工具审计噪声', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    void insertMessage({
      required String id,
      required String content,
      required String role,
      required int offset,
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
          role,
          0,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      id: 'exclude_role_tool_noise',
      content: '工具噪声：寒山戒律 寒山戒律 寒山戒律 已写入任务日志。',
      role: 'assistant:decision:tool',
      offset: 0,
    );
    insertMessage(
      id: 'exclude_role_user_keep',
      content: '用户设定：寒山戒律要求李澈不能主动滥杀。',
      role: agentRoleUser,
      offset: 1,
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'keyword': '寒山戒律',
        'excludeRoles': ['assistant:decision:tool'],
      }),
    ];

    await engine.sendAgentMessage(projectId, '查找非工具日志里的寒山戒律', autoMode: false);

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = deepRetrieveTool.schema['properties'] as Map;
    expect(properties, contains('excludeRoles'));
    expect(properties, contains('excludeRole'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], ['用户设定：寒山戒律要求李澈不能主动滥杀。']);
    final records = payload['records'] as List;
    expect(records, hasLength(1));
    final record = records.single as Map<String, dynamic>;
    expect(record['id'], 'exclude_role_user_keep');
    expect(record['role'], agentRoleUser);
  });

  test('Agent 记忆：deepRetrieve 工具支持按 role 后缀排除所有工具审计噪声', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    void insertMessage({
      required String id,
      required String content,
      required String role,
      required int offset,
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
          role,
          0,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      id: 'exclude_role_suffix_decision_tool_noise',
      content: '决策工具噪声：寒山戒律 寒山戒律 寒山戒律 已写入任务日志。',
      role: 'assistant:decision:tool',
      offset: 0,
    );
    insertMessage(
      id: 'exclude_role_suffix_story_tool_noise',
      content: '子 Agent 工具噪声：寒山戒律 寒山戒律 寒山戒律 已写入任务日志。',
      role: 'assistant:execution:storySkeleton:tool',
      offset: 1,
    );
    insertMessage(
      id: 'exclude_role_suffix_user_keep',
      content: '用户设定：寒山戒律要求李澈必须先救沈微。',
      role: agentRoleUser,
      offset: 2,
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'keyword': '寒山戒律',
        'excludeRoleSuffixes': [':tool'],
      }),
    ];

    await engine.sendAgentMessage(projectId, '查找非工具日志里的寒山戒律', autoMode: false);

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = deepRetrieveTool.schema['properties'] as Map;
    expect(properties, contains('excludeRoleSuffixes'));
    expect(properties, contains('excludeRoleSuffix'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], ['用户设定：寒山戒律要求李澈必须先救沈微。']);
    final records = payload['records'] as List;
    expect(records, hasLength(1));
    final record = records.single as Map<String, dynamic>;
    expect(record['id'], 'exclude_role_suffix_user_keep');
    expect(record['role'], agentRoleUser);
  });

  test('Agent 记忆：deepRetrieve 工具支持按 type 只返回 summary 记录', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'type_filter_msg',
        '',
        '用户约束：寒山线里李澈必须保护沈微。',
        now,
        embeddingJson('用户约束：寒山线里李澈必须保护沈微。'),
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
        'type_filter_summary',
        '寒山线约束',
        '摘要：寒山线里李澈保护沈微，后续分镜必须保留救援桥段。',
        now + 1,
        embeddingJson('摘要：寒山线里李澈保护沈微，后续分镜必须保留救援桥段。'),
        'scriptAgent:$projectId',
        jsonEncode(['type_filter_msg']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'keyword': '寒山李澈沈微',
        'types': ['summary'],
      }),
    ];

    await engine.sendAgentMessage(projectId, '只召回摘要记忆', autoMode: false);

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = deepRetrieveTool.schema['properties'] as Map;
    expect(properties, contains('type'));
    expect(properties, contains('types'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], [
      '摘要：寒山线里李澈保护沈微，后续分镜必须保留救援桥段。',
    ]);
    final records = payload['records'] as List;
    expect(records, hasLength(1));
    final record = records.single as Map<String, dynamic>;
    expect(record['id'], 'type_filter_summary');
    expect(record['type'], agentMemoryTypeSummary);
  });

  test('Agent 记忆：deepRetrieve 工具支持按 type 召回长期 note 记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final noteId = engine.saveAgentMemory(
      projectId,
      name: '寒山视觉手册',
      content: '长期设定：寒山山门必须保持冷白色调和低机位压迫感。',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'note_filter_message_noise',
        '',
        '对话噪声：寒山山门可以临时改成暖色喜剧风。',
        now,
        embeddingJson('对话噪声：寒山山门可以临时改成暖色喜剧风。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        0,
        agentMemoryTypeMessage,
      ],
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'keyword': '寒山山门色调',
        'types': ['note'],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只召回长期记忆',
      autoMode: false,
      family: agentFamilyScript,
    );

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final typeSchema = (deepRetrieveTool.schema['properties'] as Map)['type']
        as Map<String, dynamic>;
    expect(typeSchema['enum'], contains(agentMemoryTypeNote));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], [
      '长期设定：寒山山门必须保持冷白色调和低机位压迫感。',
    ]);
    final records = payload['records'] as List;
    expect(records, hasLength(1));
    final record = records.single as Map<String, dynamic>;
    expect(record['id'], noteId);
    expect(record['type'], agentMemoryTypeNote);
    expect(record['role'], 'agent');
    expect(gateway.textCallCount, 0);
  });

  test('Agent 记忆：deepRetrieve 工具支持 scope=long_term 召回长期记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final noteId = engine.saveAgentMemory(
      projectId,
      name: '角色禁忌',
      content: '长期设定：李澈不能被改写成反派，也不能主动滥杀。',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'scope_long_term_message_noise',
        '',
        '对话噪声：李澈可以短暂黑化。',
        now,
        embeddingJson('对话噪声：李澈可以短暂黑化。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        0,
        agentMemoryTypeMessage,
      ],
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'keyword': '李澈反派',
        'scope': 'long_term',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按长期记忆召回李澈设定',
      autoMode: false,
      family: agentFamilyScript,
    );

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = deepRetrieveTool.schema['properties'] as Map;
    expect(properties, contains('scope'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], [
      '长期设定：李澈不能被改写成反派，也不能主动滥杀。',
    ]);
    final records = payload['records'] as List;
    expect(records, hasLength(1));
    final record = records.single as Map<String, dynamic>;
    expect(record['id'], noteId);
    expect(record['type'], agentMemoryTypeNote);
  });

  test('Agent 记忆：deepRetrieve records 标注记忆 scope', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final noteId = engine.saveAgentMemory(
      projectId,
      name: '角色禁忌',
      content: '长期设定：李澈不能被改写成反派，也不能主动滥杀。',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'scope_label_message',
        '',
        '历史对话：李澈必须保持正派，不能被塑造成反派。',
        now,
        embeddingJson('历史对话：李澈必须保持正派，不能被塑造成反派。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        0,
        agentMemoryTypeMessage,
      ],
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'keyword': '李澈反派',
        'scope': 'all',
        'limit': 2,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '召回所有层级的李澈禁忌设定',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    final records = (payload['records'] as List)
        .cast<Map>()
        .map((record) => record.cast<String, dynamic>())
        .toList();
    expect(records, hasLength(2));

    final noteRecord = records.singleWhere((record) => record['id'] == noteId);
    expect(noteRecord['type'], agentMemoryTypeNote);
    expect(noteRecord['scope'], 'long_term');

    final messageRecord =
        records.singleWhere((record) => record['id'] == 'scope_label_message');
    expect(messageRecord['type'], agentMemoryTypeMessage);
    expect(messageRecord['scope'], 'conversation');
  });

  test('Agent 记忆：deepRetrieve 不把当前用户消息当作历史召回结果', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'exclude_current_old_user_msg',
        '',
        '历史约束：李澈保护沈微，不能让沈微黑化。',
        now,
        embeddingJson('历史约束：李澈保护沈微，不能让沈微黑化。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        0,
        'message',
      ],
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'keyword': '李澈保护沈微',
        'roles': [agentRoleUser],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '当前问题：李澈保护沈微要怎么处理？',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], contains('历史约束：李澈保护沈微，不能让沈微黑化。'));
    expect(
      payload['memories'],
      isNot(contains('当前问题：李澈保护沈微要怎么处理？')),
    );
    final records = payload['records'] as List;
    expect(
      records.map((item) => (item as Map<String, dynamic>)['content']),
      isNot(contains('当前问题：李澈保护沈微要怎么处理？')),
    );
  });

  test('Agent 记忆：deepRetrieve 工具支持显式排除已读 memory id', () async {
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
          agentRoleAssistant,
          0,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'exclude_seen_memory',
      '已读记忆：寒山禁忌是李澈不能滥杀。',
      0,
    );
    insertMessage(
      'exclude_keep_memory',
      '新记忆：寒山禁忌还包括沈微不能黑化。',
      1,
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'keyword': '寒山禁忌',
        'excludeIds': ['exclude_seen_memory'],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '继续找未读过的寒山禁忌记忆',
      autoMode: false,
      family: agentFamilyScript,
    );

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = deepRetrieveTool.schema['properties'] as Map;
    expect(properties, contains('excludeIds'));
    expect(properties, contains('excludeMemoryIds'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], ['新记忆：寒山禁忌还包括沈微不能黑化。']);
    final records = payload['records'] as List;
    expect(records, hasLength(1));
    expect(
        (records.single as Map<String, dynamic>)['id'], 'exclude_keep_memory');
  });

  test('Agent 记忆：deepRetrieve 工具返回可追踪 records 元数据', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'trace_msg_user',
        '第1轮用户约束',
        '用户强调寒山少主李澈必须保持正派。',
        now,
        embeddingJson('用户强调寒山少主李澈必须保持正派。'),
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
        'trace_summary_lizhe',
        '李澈角色设定',
        '寒山少主李澈必须保持正派。',
        now + 1,
        embeddingJson('寒山少主李澈必须保持正派。'),
        'scriptAgent:$projectId',
        jsonEncode(['trace_msg_user']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'keyword': '李澈正派',
        'limit': 1,
      }),
    ];

    await engine.sendAgentMessage(projectId, '追踪角色设定来源', autoMode: false);

    final msg = engine.agentMessages(projectId).last;
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], ['用户强调寒山少主李澈必须保持正派。']);
    expect(payload['records'], isA<List>());
    final records = payload['records'] as List;
    expect(records, hasLength(1));
    final record = records.single as Map<String, dynamic>;
    expect(record['id'], 'trace_msg_user');
    expect(record['type'], agentMemoryTypeMessage);
    expect(record['name'], '第1轮用户约束');
    expect(record['createTime'], now);
    expect(record['role'], agentRoleUser);
    expect(record['sourceSummaryIds'], ['trace_summary_lizhe']);
    expect(record['content'], '用户强调寒山少主李澈必须保持正派。');
    expect(record['score'], isA<int>());
    expect(record['score'], greaterThan(0));
    expect(record['matchedTokens'], containsAll(['李澈', '正派']));
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

  test('AgentMemoryService deepRetrieve 支持结构化 relevant_summary_ids 输出',
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
          embeddingJson(content),
          'scriptAgent:$projectId',
          '[]',
          offset.isEven ? agentRoleUser : agentRoleAssistant,
          1,
          'message',
        ],
      );
    }

    insertMessage('msg_relevant', '用户强调李澈必须保持正派，不能被写成反派。', 0);
    insertMessage('msg_noise', '用户提到寒山远景可以多一点云雾。', 1);
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'summary_relevant',
        '李澈角色设定',
        '李澈必须保持正派，不能反派化。',
        now + 2,
        embeddingJson('李澈必须保持正派，不能反派化。'),
        'scriptAgent:$projectId',
        jsonEncode(['msg_relevant']),
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
        '寒山场景设定',
        '寒山远景适合云雾和夜色。',
        now + 3,
        embeddingJson('寒山远景适合云雾和夜色。'),
        'scriptAgent:$projectId',
        jsonEncode(['msg_noise']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    gateway.textResults = const [
      TextResult('{"relevant_summary_ids":["summary_relevant"]}'),
    ];

    final records = await service.deepRetrieve(
      isolationKey: 'scriptAgent:$projectId',
      keyword: '寒山李澈正派',
    );

    expect(records.map((item) => item.id), ['msg_relevant']);
    expect(gateway.textCallCount, 1);
  });

  test('AgentMemoryService deepRetrieve 可直接返回没有来源消息的相关 summary', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'summary_style_only',
        '寒山风格摘要',
        '寒山篇需要保持冷白色调、低机位山门压迫感和正派主角气质。',
        now,
        embeddingJson('寒山篇需要保持冷白色调、低机位山门压迫感和正派主角气质。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    gateway.textResults = const [
      TextResult('["summary_style_only"]'),
    ];

    final records = await service.deepRetrieve(
      isolationKey: 'scriptAgent:$projectId',
      keyword: '寒山低机位山门风格',
    );

    expect(records.map((item) => item.id), ['summary_style_only']);
    expect(records.single.type, agentMemoryTypeSummary);
    expect(records.single.content, contains('低机位山门压迫感'));
    expect(gateway.textCallCount, 1);
  });

  test('AgentMemoryService deepRetrieve 在来源 message 缺失时保留相关 summary', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'summary_missing_sources',
        '寒山导演记忆',
        '寒山导演记忆：山门段必须保持低机位压迫感，不能改成轻喜剧。',
        now,
        embeddingJson('寒山导演记忆：山门段必须保持低机位压迫感，不能改成轻喜剧。'),
        'productionAgent:$projectId',
        jsonEncode(['deleted_msg_a', 'deleted_msg_b']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    gateway.textResults = const [
      TextResult('["summary_missing_sources"]'),
    ];

    final records = await service.deepRetrieve(
      isolationKey: 'productionAgent:$projectId',
      keyword: '寒山山门低机位压迫感',
    );

    expect(records.map((item) => item.id), ['summary_missing_sources']);
    expect(records.single.type, agentMemoryTypeSummary);
    expect(records.single.content, contains('低机位压迫感'));
    expect(gateway.textCallCount, 1);
  });

  test('AgentMemoryService deepRetrieve 尊重 LLM 判别为空且不回退原始命中', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'msg_lizhe_direct',
        '',
        '用户说李澈来自寒山，但这条不应绕过 summary 判别。',
        now,
        embeddingJson('李澈来自寒山'),
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
        'summary_lizhe',
        '李澈角色设定',
        '寒山少主李澈是正派角色。',
        now + 1,
        embeddingJson('寒山少主李澈是正派角色。'),
        'scriptAgent:$projectId',
        jsonEncode(['msg_lizhe_direct']),
        agentRoleAssistant,
        0,
        'summary',
      ],
    );
    gateway.textResults = const [
      TextResult('[]'),
    ];

    final records = await service.deepRetrieve(
      isolationKey: 'scriptAgent:$projectId',
      keyword: '寒山李澈',
    );

    expect(records, isEmpty);
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

  test(
      'AgentMemoryService deepRetrieve 会用注入 embedding provider 迁移旧 summary embedding',
      () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    const embeddingProvider = _SemanticMemoryEmbeddingProvider();
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
      embeddingProvider: embeddingProvider,
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
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'semantic_summary_msg_1',
      '用户设定：李澈和沈微之间有不可背弃的师徒契约。',
      0,
    );
    insertMessage(
      'semantic_summary_msg_2',
      '助手确认：后续所有分镜都要遵守这段关系约束。',
      1,
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'semantic_summary_noise',
        '寒山场景设定',
        '用户设定：寒山宗门外景需要云海远景。',
        now + 2,
        embeddingJson('用户设定：寒山宗门外景需要云海远景。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleAssistant,
        0,
        agentMemoryTypeSummary,
      ],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'semantic_summary_contract',
        '关系约束',
        '李澈和沈微之间有不可背弃的师徒契约，关系约束必须延续。',
        now + 3,
        embeddingJson('李澈和沈微之间有不可背弃的师徒契约，关系约束必须延续。'),
        'scriptAgent:$projectId',
        jsonEncode(['semantic_summary_msg_1', 'semantic_summary_msg_2']),
        agentRoleAssistant,
        0,
        agentMemoryTypeSummary,
      ],
    );
    gateway.textResults = const [
      TextResult('["semantic_summary_contract"]'),
    ];

    final records = await service.deepRetrieve(
      isolationKey: 'scriptAgent:$projectId',
      keyword: '师承羁绊',
    );

    expect(records.map((item) => item.id),
        ['semantic_summary_msg_1', 'semantic_summary_msg_2']);
    expect(records.map((item) => item.sourceSummaryIds), [
      ['semantic_summary_contract'],
      ['semantic_summary_contract'],
    ]);
    expect(gateway.textCallCount, 1);
  });

  test('AgentMemoryService deepRetrieveSummaryLimit 为 0 时不绕回已摘要 message',
      () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.deepRetrieveSummaryLimit', '0'],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'msg_summarized_old',
        '',
        '旧消息：李澈来自寒山且必须保持正派。',
        now,
        embeddingJson('李澈来自寒山且必须保持正派'),
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
        'summary_old',
        '李澈旧设定',
        '李澈来自寒山且必须保持正派。',
        now + 1,
        embeddingJson('李澈来自寒山且必须保持正派'),
        'scriptAgent:$projectId',
        jsonEncode(['msg_summarized_old']),
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
        'msg_recent_direct',
        '',
        '新消息：李澈救下沈微这一幕必须保留。',
        now + 2,
        embeddingJson('李澈救下沈微这一幕必须保留'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        0,
        'message',
      ],
    );

    final records = await service.deepRetrieve(
      isolationKey: 'scriptAgent:$projectId',
      keyword: '李澈正派救下沈微',
    );

    expect(records.map((item) => item.id), ['msg_recent_direct']);
    expect(gateway.textCallCount, 0);
  });

  test('AgentMemoryService clear 按 ToonFlow 语义维护 message-summary 关系', () {
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    const isolationKey = 'scriptAgent:scope-clear';
    const otherIsolationKey = 'productionAgent:scope-clear';

    void insertMemory(
      String id,
      String key,
      String type, {
      int summarized = 0,
    }) {
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
          summarized,
          type,
        ],
      );
    }

    insertMemory('scope_msg', isolationKey, agentMemoryTypeMessage,
        summarized: 1);
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

    expect(typesFor(isolationKey), [agentMemoryTypeNote]);
    expect(typesFor(otherIsolationKey), [agentMemoryTypeMessage]);

    insertMemory('scope_msg_after', isolationKey, agentMemoryTypeMessage,
        summarized: 1);
    insertMemory('scope_sum_after', isolationKey, agentMemoryTypeSummary);

    service.clear(isolationKey: isolationKey, scope: agentMemoryTypeSummary);

    expect(
        typesFor(isolationKey), [agentMemoryTypeMessage, agentMemoryTypeNote]);
    final resetRow = db.select(
      'SELECT summarized FROM memories WHERE id=? AND isolationKey=?',
      ['scope_msg_after', isolationKey],
    ).single;
    expect(resetRow['summarized'], 0);
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

  test('AgentMemoryService 摘要前会跳过遗留未摘要工具审计记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '2'],
    );
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'legacy_tool_audit',
        '',
        '工具审计噪声：寒山戒律 寒山戒律 已写入日志。',
        now,
        embeddingJson('工具审计噪声：寒山戒律 寒山戒律 已写入日志。'),
        'scriptAgent:$projectId',
        '[]',
        'assistant:decision:tool',
        0,
        agentMemoryTypeMessage,
      ],
    );

    final userMemoryId = await service.add(
      isolationKey: 'scriptAgent:$projectId',
      role: agentRoleUser,
      content: '用户设定：寒山戒律要求李澈先保护沈微。',
      createTime: now + 1,
    );

    final rows = db.select(
      'SELECT id,summarized FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', agentMemoryTypeMessage],
    );
    expect(
      {for (final row in rows) row['id']: row['summarized']},
      {'legacy_tool_audit': 1, userMemoryId: 0},
    );
    final summaries = db.select(
      'SELECT content FROM memories WHERE isolationKey=? AND type=?',
      ['scriptAgent:$projectId', agentMemoryTypeSummary],
    );
    expect(summaries, isEmpty);
  });

  test('AgentMemoryService get 支持排除 exact role 和 role 后缀', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    void insertMessage({
      required String id,
      required String content,
      required String role,
      required int offset,
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
          role,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      id: 'get_tool_result_noise',
      content: '寒山戒律 继续写寒山戒律 工具结果噪声。',
      role: agentRoleTool,
      offset: 0,
    );
    insertMessage(
      id: 'get_tool_audit_noise',
      content: '寒山戒律 继续写寒山戒律 工具审计噪声。',
      role: 'assistant:decision:tool',
      offset: 1,
    );
    insertMessage(
      id: 'get_user_keep',
      content: '用户设定：寒山戒律要求李澈先保护沈微。',
      role: agentRoleUser,
      offset: 2,
    );

    final context = await service.get(
      isolationKey: 'scriptAgent:$projectId',
      query: '继续写寒山戒律',
      excludeRoles: {agentRoleTool},
      excludeRoleSuffixes: const {':tool'},
    );

    expect(context.relatedMessages.map((item) => item.id), ['get_user_keep']);
  });

  test('AgentMemoryService get 支持注入 embedding provider 召回语义相关 message',
      () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    const embeddingProvider = _SemanticMemoryEmbeddingProvider();
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
      embeddingProvider: embeddingProvider,
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
        'semantic_noise_msg',
        '',
        '用户设定：寒山宗门外景需要云海远景。',
        now,
        embeddingProvider.embeddingJson('用户设定：寒山宗门外景需要云海远景。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        1,
        agentMemoryTypeMessage,
      ],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'semantic_relevant_msg',
        '',
        '用户设定：李澈和沈微之间有不可背弃的师徒契约。',
        now + 1,
        embeddingProvider.embeddingJson('用户设定：李澈和沈微之间有不可背弃的师徒契约。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        1,
        agentMemoryTypeMessage,
      ],
    );

    final context = await service.get(
      isolationKey: 'scriptAgent:$projectId',
      query: '师承羁绊',
    );

    expect(context.relatedMessages.map((item) => item.id),
        ['semantic_relevant_msg']);
    expect(context.relatedMessages.single.score, greaterThan(0));
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
    expect(gateway.lastSystem, contains('<memory id="prompt_msg_1"'));
    expect(gateway.lastSystem, contains('type="message"'));
    expect(gateway.lastSystem, contains('role="user"'));
    expect(gateway.lastSystem, contains('createTime="$now"'));
    expect(gateway.lastSystem, contains('sourceSummaryIds="prompt_summary"'));
    expect(gateway.lastSystem, contains('<summary id="prompt_summary"'));
    expect(gateway.lastSystem,
        contains('relatedMessageIds="prompt_msg_1,prompt_msg_2"'));
    expect(gateway.lastSystem, contains('<recent id="agent_msg_'));
    final relatedBlock =
        gateway.lastSystem.split('历史摘要：').first.split('相关历史记忆：').last;
    expect(relatedBlock, isNot(contains('继续写寒山李澈入山')));
    expect(gateway.lastSystem, contains('寒山少主李澈不能写成反派'));
    expect(gateway.lastSystem, contains('寒山少主李澈是正派角色'));
    expect(gateway.lastSystem, contains('继续写寒山李澈入山'));
  });

  test('Agent turn system prompt 默认排除工具审计记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    void insertMessage({
      required String id,
      required String content,
      required String role,
      required int offset,
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
          role,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      id: 'decision_tool_noise',
      content: '工具审计噪声：寒山戒律 寒山戒律 寒山戒律 已写入日志。',
      role: 'assistant:decision:tool',
      offset: 0,
    );
    insertMessage(
      id: 'decision_tool_result_noise',
      content: '工具结果噪声：寒山戒律 寒山戒律 寒山戒律 寒山戒律 已写入日志。',
      role: agentRoleTool,
      offset: 1,
    );
    insertMessage(
      id: 'decision_user_keep',
      content: '用户设定：寒山戒律要求李澈先保护沈微。',
      role: agentRoleUser,
      offset: 2,
    );
    gateway.turns = [const AgentTurnResult.text('收到，我会沿用寒山戒律。')];

    await engine.sendAgentMessage(projectId, '继续写寒山戒律', autoMode: false);

    expect(gateway.lastSystem, contains('decision_user_keep'));
    expect(gateway.lastSystem, contains('李澈先保护沈微'));
    expect(gateway.lastSystem, isNot(contains('decision_tool_noise')));
    expect(gateway.lastSystem, isNot(contains('decision_tool_result_noise')));
    expect(gateway.lastSystem, isNot(contains('工具审计噪声')));
    expect(gateway.lastSystem, isNot(contains('工具结果噪声')));
  });

  test('Agent turn system prompt 可通过绑定 embedding 模型召回语义相关记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['binding.agent_embedding', 'fake:embed'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'remote_semantic_keep',
        '',
        'mentor bond rule: Li Che must protect Shen Wei before entering Hanshan.',
        now,
        '',
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        1,
        agentMemoryTypeMessage,
      ],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'remote_semantic_noise',
        '',
        'market comedy beat with no relationship constraint.',
        now + 1,
        '',
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        1,
        agentMemoryTypeMessage,
      ],
    );
    gateway.embeddingForText = (input) {
      final normalized = input.toLowerCase();
      if (normalized.contains('mentor bond') || input.contains('师承羁绊')) {
        return const [1, 0];
      }
      return const [0, 1];
    };
    gateway.turns = [const AgentTurnResult.text('会保留师承羁绊。')];

    await engine.sendAgentMessage(projectId, '师承羁绊怎么处理', autoMode: false);

    expect(gateway.embeddingInputs, contains('师承羁绊怎么处理'));
    expect(gateway.lastSystem, contains('remote_semantic_keep'));
    expect(gateway.lastSystem, contains('mentor bond rule'));
    expect(gateway.lastSystem, isNot(contains('remote_semantic_noise')));
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

  test('scriptAgent 决策消息注入 ToonFlow 项目信息', () async {
    db.execute(
      'UPDATE o_project SET type=?, intro=?, artStyle=?, videoRatio=? '
      'WHERE id=?',
      ['玄幻修仙', '石泉村少年入山测灵。', '国风水墨', '9:16', projectId],
    );
    engine.addNovels(projectId, const [
      ChapterItem(index: 1, reel: '正文卷', chapter: '选丁', chapterData: '选丁原文'),
      ChapterItem(index: 2, reel: '正文卷', chapter: '测灵', chapterData: '测灵原文'),
    ]);
    gateway.turns = [const AgentTurnResult.text('剧本决策已记录。')];

    await engine.sendAgentMessage(
      projectId,
      '规划前三集',
      autoMode: false,
      family: agentFamilyScript,
    );

    final content = gateway.lastMessages
        .map((message) => message['content'])
        .whereType<String>()
        .join('\n');
    expect(content, contains('## 项目信息'));
    expect(content, contains('小说名称：Agent测试'));
    expect(content, contains('小说类型：玄幻修仙'));
    expect(content, contains('小说简介：石泉村少年入山测灵。'));
    expect(content, contains('目标改编影视视觉手册|画风：国风水墨'));
    expect(content, contains('目标改编视频画幅：9:16'));
    expect(content, contains('章节数量：2章'));
  });

  test('productionAgent 决策消息注入 ToonFlow 模型信息', () async {
    db.execute(
      'UPDATE o_project SET imageModel=?, videoModel=?, mode=? WHERE id=?',
      [
        'azt:gpt-image-2',
        'volcengine:doubao-seedance-2-0-mini-260615',
        jsonEncode(['role', 'scene']),
        projectId,
      ],
    );
    gateway.turns = [const AgentTurnResult.text('制作决策已记录。')];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：生成导演计划',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final content = gateway.lastMessages
        .map((message) => message['content'])
        .whereType<String>()
        .join('\n');
    expect(content, contains('项目使用的模型如下：'));
    expect(content, contains('图像模型：gpt-image-2'));
    expect(content, contains('视频模型：doubao-seedance-2-0-mini-260615'));
    expect(content, contains('多参：是'));
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

  test('ScriptAgent 子 Agent 系统上下文默认排除工具审计记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    void insertMessage({
      required String id,
      required String content,
      required String role,
      required int offset,
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
          role,
          0,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      id: 'script_sub_context_tool_noise',
      content: '工具审计：霜刃戒律 霜刃戒律 霜刃戒律 已传给工具调用。',
      role: 'assistant:execution:storySkeleton:tool',
      offset: 0,
    );
    insertMessage(
      id: 'script_sub_context_user_keep',
      content: '用户设定：霜刃戒律要求李澈先保护沈微。',
      role: agentRoleUser,
      offset: 1,
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'prompt': '霜刃戒律'},
      ),
      const AgentTurnResult.text('<storySkeleton>霜刃戒律骨架</storySkeleton>'),
    ];

    await engine.sendAgentMessage(projectId, '先运行故事骨架 Agent', autoMode: false);

    expect(gateway.systems[1], contains('script_sub_context_user_keep'));
    expect(gateway.systems[1], contains('李澈先保护沈微'));
    expect(
        gateway.systems[1], isNot(contains('script_sub_context_tool_noise')));
    expect(gateway.systems[1], isNot(contains('已传给工具调用')));
  });

  test('ScriptAgent 子 Agent deepRetrieve 默认排除已注入上下文与工具审计记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    void insertMessage(
      String id,
      String content,
      int offset, {
      String role = agentRoleAssistant,
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
          role,
          0,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'sub_context_seen',
      '霜刃戒律 霜刃戒律 霜刃戒律 霜刃戒律：李澈不能滥杀无辜。',
      0,
    );
    insertMessage(
      'sub_context_tool_noise',
      '工具审计噪声：霜刃戒律 霜刃戒律 霜刃戒律 已传给工具调用。',
      1,
      role: 'assistant:execution:storySkeleton:tool',
    );
    insertMessage(
      'sub_context_unread',
      '霜刃戒律：沈微不能提前暴露灵根。',
      2,
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'prompt': '霜刃戒律'},
      ),
      AgentTurnResult.tool(
        'deepRetrieve',
        const {'keyword': '霜刃戒律'},
      ),
      const AgentTurnResult.text('<storySkeleton>寒山禁忌骨架</storySkeleton>'),
    ];

    await engine.sendAgentMessage(projectId, '先运行故事骨架 Agent', autoMode: false);

    expect(gateway.systems[1], contains('sub_context_seen'));
    final toolMsg = engine.agentMessages(projectId).lastWhere(
        (message) => message.toolName == 'run_sub_agent_storySkeleton');
    expect(toolMsg.content, contains('故事骨架 Agent 已写入工作区'));
    final auditRows = db.select(
      'SELECT content FROM memories '
      'WHERE isolationKey=? AND role=? ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', 'assistant:execution:storySkeleton:tool'],
    );
    final deepRetrieveAudit = auditRows.singleWhere(
      (row) => (row['content'] as String).contains('deepRetrieve'),
    );
    final payloadText = deepRetrieveAudit['content'] as String;
    expect(payloadText, contains('沈微不能提前暴露灵根'));
    expect(payloadText, isNot(contains('李澈不能滥杀无辜')));
    expect(payloadText, isNot(contains('工具审计噪声')));
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
      'SELECT role,name,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', 'message'],
    );

    expect(rows.map((row) => row['role']),
        contains('assistant:execution:storySkeleton'));
    final subAgentMemory = rows.singleWhere(
      (row) => row['role'] == 'assistant:execution:storySkeleton',
    );
    expect(subAgentMemory['name'], '编剧');
    expect(subAgentMemory['content'], '寒山篇三集骨架');
  });

  test('ScriptAgent 子 Agent 工具调用结果写入执行层审计记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final novelId = engine.addNovels(projectId, const [
      ChapterItem(index: 1, reel: '正文卷', chapter: '寒山起', chapterData: 'x'),
    ]).single;
    db.execute(
      'UPDATE o_novel SET event=?, eventState=1 WHERE id=?',
      ['李澈在寒山山门救下沈微。', novelId],
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        {
          'prompt': '读取事件后搭建寒山篇骨架',
          'novelIds': [novelId]
        },
      ),
      AgentTurnResult.tool(
        'get_novel_events',
        {
          'novelIds': [novelId]
        },
      ),
      const AgentTurnResult.text('<storySkeleton>寒山篇骨架</storySkeleton>'),
    ];

    await engine.sendAgentMessage(projectId, '先读取事件再做寒山故事骨架', autoMode: false);

    final rows = db.select(
      'SELECT role,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', 'message'],
    );

    final toolAudit = rows.singleWhere(
      (row) => row['role'] == 'assistant:execution:storySkeleton:tool',
    );
    expect(toolAudit['content'], contains('工具 get_novel_events 执行结果'));
    expect(toolAudit['content'], contains('李澈在寒山山门救下沈微'));
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

  test('Agent tool list honors ToonFlow subagent skill attribution', () async {
    engine.saveCustomAgentSkill(
      id: 'script_skeleton_exact_skill',
      name: '故事骨架专属技能',
      description: '只给故事骨架执行 Agent 使用。',
      script: r'return "skeleton";',
    );
    engine.saveCustomAgentSkill(
      id: 'script_adaptation_exact_skill',
      name: '改编策略专属技能',
      description: '只给改编策略执行 Agent 使用。',
      script: r'return "adaptation";',
    );
    engine.saveCustomAgentSkill(
      id: 'production_director_plan_exact_skill',
      name: '导演规划专属技能',
      description: '只给导演规划执行 Agent 使用。',
      script: r'return "director";',
    );
    engine.saveCustomAgentSkill(
      id: 'production_storyboard_table_exact_skill',
      name: '分镜表专属技能',
      description: '只给分镜表执行 Agent 使用。',
      script: r'return "table";',
    );
    db.execute(
      'INSERT INTO o_skillAttribution (attribution,skillId) VALUES (?,?)',
      ['script_execution_skeleton', 'script_skeleton_exact_skill'],
    );
    db.execute(
      'INSERT INTO o_skillAttribution (attribution,skillId) VALUES (?,?)',
      ['script_execution_adaptation', 'script_adaptation_exact_skill'],
    );
    db.execute(
      'INSERT INTO o_skillAttribution (attribution,skillId) VALUES (?,?)',
      [
        'production_execution_director_plan',
        'production_director_plan_exact_skill'
      ],
    );
    db.execute(
      'INSERT INTO o_skillAttribution (attribution,skillId) VALUES (?,?)',
      [
        'production_execution_storyboard_table',
        'production_storyboard_table_exact_skill'
      ],
    );

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'prompt': '搭建寒山篇前三集骨架'},
      ),
      const AgentTurnResult.text('<storySkeleton>寒山篇三集骨架</storySkeleton>'),
    ];
    await engine.sendAgentMessage(projectId, '先做故事骨架', autoMode: false);

    expect(gateway.stages.last, 'scriptAgent:storySkeletonAgent');
    expect(
        gateway.toolNamesByCall.last, contains('script_skeleton_exact_skill'));
    expect(gateway.toolNamesByCall.last,
        isNot(contains('script_adaptation_exact_skill')));

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_adaptationStrategy',
        const {'prompt': '制定寒山篇改编策略'},
      ),
      const AgentTurnResult.text(
        '<adaptationStrategy>前三集突出寒山压迫感</adaptationStrategy>',
      ),
    ];
    await engine.sendAgentMessage(projectId, '再做改编策略', autoMode: false);

    expect(gateway.stages.last, 'scriptAgent:adaptationStrategyAgent');
    expect(gateway.toolNamesByCall.last,
        contains('script_adaptation_exact_skill'));
    expect(gateway.toolNamesByCall.last,
        isNot(contains('script_skeleton_exact_skill')));

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

    expect(gateway.stages.last, 'productionAgent:directorPlanAgent');
    expect(gateway.toolNamesByCall.last,
        contains('production_director_plan_exact_skill'));
    expect(gateway.toolNamesByCall.last,
        isNot(contains('production_storyboard_table_exact_skill')));

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_table',
        {'prompt': '做第一集分镜表', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<storyboardTable>近景|横移</storyboardTable>'),
    ];
    await engine.sendAgentMessage(projectId, '制作分镜表', autoMode: false);

    expect(gateway.stages.last, 'productionAgent:storyboardTableAgent');
    expect(gateway.toolNamesByCall.last,
        contains('production_storyboard_table_exact_skill'));
    expect(gateway.toolNamesByCall.last,
        isNot(contains('production_director_plan_exact_skill')));
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
    final supervisionMemory = db.select(
      'SELECT name,content FROM memories '
      'WHERE isolationKey=? AND role=? AND type=?',
      ['scriptAgent:$projectId', 'assistant:supervision', 'message'],
    ).single;
    expect(supervisionMemory['name'], '编辑');
    expect(supervisionMemory['content'], '监督结论：节奏成立。');
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

  test('ProductionAgent 子 Agent 系统上下文默认排除工具审计记忆', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    void insertMessage({
      required String id,
      required String content,
      required String role,
      required int offset,
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
          'productionAgent:$projectId',
          '[]',
          role,
          0,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      id: 'production_sub_context_tool_noise',
      content: '工具审计：镜湖调度 镜湖调度 镜湖调度 已传给工具调用。',
      role: 'assistant:execution:directorPlan:tool',
      offset: 0,
    );
    insertMessage(
      id: 'production_sub_context_user_keep',
      content: '用户设定：镜湖调度要求第二镜保持贴地跟拍。',
      role: agentRoleUser,
      offset: 1,
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '镜湖调度', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<scriptPlan>镜湖调度计划</scriptPlan>'),
    ];

    await engine.sendAgentMessage(projectId, '制作画布：运行导演计划 Agent',
        autoMode: false);

    expect(gateway.systems[1], contains('production_sub_context_user_keep'));
    expect(gateway.systems[1], contains('第二镜保持贴地跟拍'));
    expect(gateway.systems[1],
        isNot(contains('production_sub_context_tool_noise')));
    expect(gateway.systems[1], isNot(contains('已传给工具调用')));
  });

  test('ProductionAgent 子 Agent deepRetrieve 默认排除已注入上下文与工具审计记忆', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    void insertMessage(
      String id,
      String content,
      int offset, {
      String role = agentRoleAssistant,
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
          'productionAgent:$projectId',
          '[]',
          role,
          0,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'production_context_seen',
      '镜湖调度 镜湖调度 镜湖调度 镜湖调度：开场不能使用俯拍大远景。',
      0,
    );
    insertMessage(
      'production_context_tool_noise',
      '工具审计噪声：镜湖调度 镜湖调度 镜湖调度 已传给工具调用。',
      1,
      role: 'assistant:execution:directorPlan:tool',
    );
    insertMessage(
      'production_context_unread',
      '镜湖调度：第二镜必须保持贴地跟拍。',
      2,
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '镜湖调度', 'scriptId': scriptId},
      ),
      AgentTurnResult.tool(
        'deepRetrieve',
        const {'keyword': '镜湖调度'},
      ),
      const AgentTurnResult.text('<scriptPlan>镜湖调度计划</scriptPlan>'),
    ];

    await engine.sendAgentMessage(projectId, '制作画布：运行导演计划 Agent',
        autoMode: false);

    expect(gateway.systems[1], contains('production_context_seen'));
    final toolMsg = engine
        .agentMessages(projectId, family: agentFamilyProduction)
        .lastWhere(
            (message) => message.toolName == 'run_sub_agent_director_plan');
    expect(toolMsg.content, contains('导演计划 Agent 已写入工作区'));
    final auditRows = db.select(
      'SELECT content FROM memories '
      'WHERE isolationKey=? AND role=? ORDER BY createTime ASC, id ASC',
      ['productionAgent:$projectId', 'assistant:execution:directorPlan:tool'],
    );
    final deepRetrieveAudit = auditRows.singleWhere(
      (row) => (row['content'] as String).contains('deepRetrieve'),
    );
    final payloadText = deepRetrieveAudit['content'] as String;
    expect(payloadText, contains('贴地跟拍'));
    expect(payloadText, isNot(contains('俯拍大远景')));
    expect(payloadText, isNot(contains('工具审计噪声')));
  });

  test('ProductionAgent 子 Agent 暴露项目画风和导演手册技能', () async {
    db.execute(
      'UPDATE o_project SET artStyle=?, directorManual=? WHERE id=?',
      ['水墨视觉', '仙侠叙事', projectId],
    );
    File(p.join(dir.path, 'skills', 'art_skills', 'InkStyle', 'meta.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'name': '水墨视觉'}));
    File(p.join(
      dir.path,
      'skills',
      'art_skills',
      'InkStyle',
      'driector_skills',
      'director_planning_style.md',
    ))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
---
name: director_planning_style.md
description: 画风导演规划技法
---

# 画风导演规划
冷白水墨，低饱和，镜头留白。
''');
    File(p.join(
      dir.path,
      'skills',
      'story_skills',
      'XianxiaStory',
      'meta.json',
    ))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'name': '仙侠叙事'}));
    File(p.join(
      dir.path,
      'skills',
      'story_skills',
      'XianxiaStory',
      'driector_skills',
      'director_planning_narrative.md',
    ))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
---
name: director_planning_narrative.md
description: 仙侠叙事导演规划技法
---

# 仙侠叙事导演规划
前三秒必须给宗门压迫和主角困境。
''');
    File(p.join(
      dir.path,
      'skills',
      'story_skills',
      'OtherStory',
      'driector_skills',
      'director_planning_narrative.md',
    ))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
---
name: other_story_skill.md
description: 不应出现在当前项目
---

其他题材。
''');

    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '做寒山导演计划', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<scriptPlan>冷白水墨压迫感开场</scriptPlan>'),
    ];

    await engine.sendAgentMessage(projectId, '制作画布：做寒山导演计划', autoMode: false);

    expect(gateway.lastSystem,
        contains('<name>director_planning_style.md</name>'));
    expect(gateway.lastSystem, contains('画风导演规划技法'));
    expect(
      gateway.lastSystem,
      contains('<name>director_planning_narrative.md</name>'),
    );
    expect(gateway.lastSystem, contains('仙侠叙事导演规划技法'));
    expect(gateway.lastSystem, isNot(contains('other_story_skill.md')));

    final activateSkill =
        gateway.lastTools.singleWhere((tool) => tool.name == 'activate_skill');
    final properties = activateSkill.schema['properties'] as Map;
    final nameSchema = properties['name'] as Map;
    expect(nameSchema['enum'], contains('director_planning_style.md'));
    expect(nameSchema['enum'], contains('director_planning_narrative.md'));
    expect(nameSchema['enum'], isNot(contains('other_story_skill.md')));
  });

  test('ProductionAgent project production_skills 仅暴露给分镜写入子 Agent', () async {
    db.execute(
      'UPDATE o_project SET artStyle=?, directorManual=? WHERE id=?',
      ['水墨视觉', '仙侠叙事', projectId],
    );
    File(p.join(dir.path, 'skills', 'art_skills', 'InkStyle', 'meta.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'name': '水墨视觉'}));
    File(p.join(
      dir.path,
      'skills',
      'art_skills',
      'InkStyle',
      'driector_skills',
      'director_planning_style.md',
    ))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
---
name: director_planning_style.md
description: 画风导演规划技法
---

画风导演规划。
''');
    File(p.join(
      dir.path,
      'skills',
      'story_skills',
      'XianxiaStory',
      'meta.json',
    ))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'name': '仙侠叙事'}));
    File(p.join(
      dir.path,
      'skills',
      'story_skills',
      'XianxiaStory',
      'driector_skills',
      'director_planning_narrative.md',
    ))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
---
name: director_planning_narrative.md
description: 叙事导演规划技法
---

叙事导演规划。
''');
    File(p.join(
      dir.path,
      'skills',
      'production_skills',
      'storyboard_layout_skill.md',
    ))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
---
name: storyboard_layout_skill.md
description: 分镜面板写入专用技法
---

只用于分镜面板或分镜表写入。
''');

    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '做寒山导演计划', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<scriptPlan>冷白水墨压迫感开场</scriptPlan>'),
    ];
    await engine.sendAgentMessage(projectId, '制作画布：做寒山导演计划', autoMode: false);
    expect(gateway.lastSystem, contains('director_planning_style.md'));
    expect(gateway.lastSystem, contains('director_planning_narrative.md'));
    expect(gateway.lastSystem, isNot(contains('storyboard_layout_skill.md')));
    var activateSkill =
        gateway.lastTools.singleWhere((tool) => tool.name == 'activate_skill');
    var properties = activateSkill.schema['properties'] as Map;
    var nameSchema = properties['name'] as Map;
    expect(nameSchema['enum'], isNot(contains('storyboard_layout_skill.md')));

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_panel',
        {'prompt': '写入首集分镜面板', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text(
        '<storyboardItem videoDesc="山门压迫" prompt="cold mountain gate" '
        'track="首集" shouldGenerateImage="false" duration="5" '
        'associateAssetsIds="[]"></storyboardItem>',
      ),
    ];
    await engine.sendAgentMessage(projectId, '制作画布：写入分镜面板', autoMode: false);
    expect(gateway.lastSystem, contains('storyboard_layout_skill.md'));
    activateSkill =
        gateway.lastTools.singleWhere((tool) => tool.name == 'activate_skill');
    properties = activateSkill.schema['properties'] as Map;
    nameSchema = properties['name'] as Map;
    expect(nameSchema['enum'], contains('storyboard_layout_skill.md'));
  });

  test('ProductionAgent 项目技能不会泄漏到其他项目', () async {
    db.execute(
      'UPDATE o_project SET artStyle=?, directorManual=? WHERE id=?',
      ['水墨视觉', '仙侠叙事', projectId],
    );
    File(p.join(dir.path, 'skills', 'art_skills', 'InkStyle', 'meta.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'name': '水墨视觉'}));
    File(p.join(
      dir.path,
      'skills',
      'art_skills',
      'InkStyle',
      'driector_skills',
      'ink_only_director_skill.md',
    ))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
---
name: ink_only_director_skill.md
description: 只属于水墨视觉项目
---

水墨项目专用导演技法。
''');
    final scriptA =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '做项目 A 导演计划', 'scriptId': scriptA},
      ),
      const AgentTurnResult.text('<scriptPlan>项目 A</scriptPlan>'),
    ];
    await engine.sendAgentMessage(projectId, '制作画布：项目 A 导演计划', autoMode: false);
    expect(gateway.lastSystem, contains('ink_only_director_skill.md'));
    db.execute(
      'INSERT OR REPLACE INTO o_skillAttribution (attribution,skillId) '
      'VALUES (?,?)',
      [
        'production_agent_execution',
        'project_${projectId}_ink_only_director_skill.md',
      ],
    );

    final projectB = engine.addProject(projectType: 'novel', name: '另一个项目');
    final scriptB =
        engine.addScript(projectId: projectB, name: '第一集', content: '林岚入城');
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '做项目 B 导演计划', 'scriptId': scriptB},
      ),
      const AgentTurnResult.text('<scriptPlan>项目 B</scriptPlan>'),
    ];
    await engine.sendAgentMessage(projectB, '制作画布：项目 B 导演计划', autoMode: false);
    expect(gateway.lastSystem, isNot(contains('ink_only_director_skill.md')));
    final activateSkill =
        gateway.lastTools.singleWhere((tool) => tool.name == 'activate_skill');
    final properties = activateSkill.schema['properties'] as Map;
    final nameSchema = properties['name'] as Map;
    expect(nameSchema['enum'], isNot(contains('ink_only_director_skill.md')));
  });

  test('ProductionAgent 子 Agent 输出按 ToonFlow 子阶段 memoryKey 写入记忆', () async {
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
      'SELECT role,name,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['productionAgent:$projectId', 'message'],
    );

    expect(rows.map((row) => row['role']),
        contains('assistant:execution:directorPlan'));
    final subAgentMemory = rows.singleWhere(
      (row) => row['role'] == 'assistant:execution:directorPlan',
    );
    expect(subAgentMemory['name'], '执行导演');
    expect(subAgentMemory['content'], '低机位跟拍寒山山门');

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_table',
        {'prompt': '做寒山分镜表', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<storyboardTable>山门压迫|低机位</storyboardTable>'),
    ];

    await engine.sendAgentMessage(projectId, '制作分镜表', autoMode: false);

    final updatedRows = db.select(
      'SELECT role,name,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['productionAgent:$projectId', 'message'],
    );
    expect(updatedRows.map((row) => row['role']),
        contains('assistant:execution:storyboardTable'));
    final storyboardTableMemory = updatedRows.singleWhere(
      (row) => row['role'] == 'assistant:execution:storyboardTable',
    );
    expect(storyboardTableMemory['name'], '执行导演');
    expect(storyboardTableMemory['content'], '山门压迫|低机位');
  });

  test('ProductionAgent 子 Agent 工具调用结果写入执行层审计记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '读取制作工作区后做导演计划', 'scriptId': scriptId},
      ),
      AgentTurnResult.tool(
        'get_flowData',
        {'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<scriptPlan>低机位跟拍寒山山门</scriptPlan>'),
    ];

    await engine.sendAgentMessage(projectId, '制作画布：读取工作区再做导演计划',
        autoMode: false);

    final rows = db.select(
      'SELECT role,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['productionAgent:$projectId', 'message'],
    );

    final toolAudit = rows.singleWhere(
      (row) => row['role'] == 'assistant:execution:directorPlan:tool',
    );
    expect(toolAudit['content'], contains('工具 get_flowData 执行结果'));
    expect(toolAudit['content'], contains('李澈入山'));
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
    final supervisionMemory = db.select(
      'SELECT name,content FROM memories '
      'WHERE isolationKey=? AND role=? AND type=?',
      ['productionAgent:$projectId', 'assistant:supervision', 'message'],
    ).single;
    expect(supervisionMemory['name'], '监制');
    expect(supervisionMemory['content'], '监督结论：制作链路通过。');
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

class _SemanticMemoryEmbeddingProvider
    extends TokenAgentMemoryEmbeddingProvider {
  const _SemanticMemoryEmbeddingProvider();

  @override
  Map<String, int> embeddingFromText(String text) {
    final normalized = normalizeMemoryText(text);
    if (normalized.contains('师徒契约') || normalized.contains('师承羁绊')) {
      return const {'mentor_bond': 1};
    }
    return super.embeddingFromText(text);
  }
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
  List<String> embeddingInputs = const [];
  List<double> Function(String input)? embeddingForText;
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
    embeddingInputs = [];
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

  Future<List<double>> generateEmbedding(String input,
      {required String stage, CancelToken? cancelToken}) async {
    embeddingInputs = [...embeddingInputs, input];
    return embeddingForText?.call(input) ?? const [0];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
