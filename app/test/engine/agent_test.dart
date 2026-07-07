import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/agent.dart';
import 'package:dramaflow/src/engine/agent_memory.dart';
import 'package:dramaflow/src/engine/art_style.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/events.dart';
import 'package:dramaflow/src/engine/manuals.dart';
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

  test('Agent 顶层批量工具接受 ToonFlow 列表 id 别名', () async {
    final novelIds = engine.addNovels(projectId, const [
      ChapterItem(index: 1, reel: '正文卷', chapter: '一', chapterData: 'x'),
      ChapterItem(index: 2, reel: '正文卷', chapter: '二', chapterData: 'y'),
    ]);
    gateway.turns = [
      AgentTurnResult.tool('generate_events', {
        'novel_ids': '${novelIds.first}',
      }),
    ];

    await engine.sendAgentMessage(projectId, '只生成第一章事件', autoMode: false);

    final eventTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'generate_events');
    final eventProperties = eventTool.schema['properties'] as Map;
    expect(eventProperties, contains('novel_ids'));
    expect(engine.agentMessages(projectId).last.content, contains('1 个章节'));

    final scriptA =
        engine.addScript(projectId: projectId, name: '第一集', content: 'A');
    engine.addScript(projectId: projectId, name: '第二集', content: 'B');
    gateway.turns = [
      AgentTurnResult.tool('extract_assets', {
        'script_ids': '$scriptA',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只提取第一集资产',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final assetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'extract_assets');
    final assetProperties = assetTool.schema['properties'] as Map;
    expect(assetProperties, contains('script_ids'));
    expect(
      engine
          .agentMessages(projectId, family: agentFamilyProduction)
          .last
          .content,
      contains('1 个剧本'),
    );
  });

  test('Agent 顶层批量工具接受 ToonFlow 自然章节号和集号别名', () async {
    engine.addNovels(projectId, const [
      ChapterItem(index: 1, reel: '正文卷', chapter: '第一章', chapterData: 'x'),
      ChapterItem(index: 2, reel: '正文卷', chapter: '第二章', chapterData: 'y'),
    ]);
    db.execute('DELETE FROM o_tasks');
    gateway.turns = [
      AgentTurnResult.tool('generate_events', const {
        'chapterNo': 2,
      }),
    ];

    await engine.sendAgentMessage(projectId, '只生成第二章事件', autoMode: false);

    final eventTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'generate_events');
    final eventProperties = eventTool.schema['properties'] as Map;
    expect(eventProperties, contains('chapterNo'));
    expect(engine.agentMessages(projectId).last.content, contains('1 个章节'));
    final eventTask = db.select(
      'SELECT relatedObjects FROM o_tasks WHERE taskClass=?',
      ['event_generation'],
    ).single;
    final eventRelated = jsonDecode(eventTask['relatedObjects'] as String)
        as Map<String, dynamic>;
    expect(eventRelated['ids'], [2]);

    engine.addScript(projectId: projectId, name: '第一集', content: 'A');
    final secondScript =
        engine.addScript(projectId: projectId, name: '第二集', content: 'B');
    gateway.turns = [
      AgentTurnResult.tool('extract_assets', const {
        'episodeNo': 2,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只提取第二集资产',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final assetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'extract_assets');
    final assetProperties = assetTool.schema['properties'] as Map;
    expect(assetProperties, contains('episodeNo'));
    expect(
      engine
          .agentMessages(projectId, family: agentFamilyProduction)
          .last
          .content,
      contains('1 个剧本'),
    );
    final assetTask = db.select(
      'SELECT relatedObjects FROM o_tasks WHERE taskClass=?',
      ['asset_extraction'],
    ).single;
    final assetRelated = jsonDecode(assetTask['relatedObjects'] as String)
        as Map<String, dynamic>;
    expect(assetRelated['ids'], [secondScript]);
  });

  test('Agent 顶层事件工具接受 ToonFlow 章节名称别名', () async {
    final novelIds = engine.addNovels(projectId, const [
      ChapterItem(index: 1, reel: '正文卷', chapter: '雪夜入山', chapterData: 'x'),
      ChapterItem(index: 2, reel: '正文卷', chapter: '寒山初雪', chapterData: 'y'),
    ]);
    db.execute('DELETE FROM o_tasks');
    gateway.turns = [
      AgentTurnResult.tool('generate_events', const {
        'chapterName': '寒山初雪',
      }),
    ];

    await engine.sendAgentMessage(projectId, '只生成《寒山初雪》的事件', autoMode: false);

    final eventTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'generate_events');
    final eventProperties = eventTool.schema['properties'] as Map;
    expect(eventProperties, contains('chapterName'));
    expect(engine.agentMessages(projectId).last.content, contains('1 个章节'));
    final eventTask = db.select(
      'SELECT relatedObjects FROM o_tasks WHERE taskClass=?',
      ['event_generation'],
    ).single;
    final eventRelated = jsonDecode(eventTask['relatedObjects'] as String)
        as Map<String, dynamic>;
    expect(eventRelated['ids'], [novelIds[1]]);
  });

  test('Agent 自然章节号未匹配时不会回退成全量事件任务', () async {
    engine.addNovels(projectId, const [
      ChapterItem(index: 1, reel: '正文卷', chapter: '第一章', chapterData: 'x'),
      ChapterItem(index: 2, reel: '正文卷', chapter: '第二章', chapterData: 'y'),
    ]);
    db.execute('DELETE FROM o_tasks');
    gateway.turns = [
      AgentTurnResult.tool('generate_events', const {
        'chapterNo': 99,
      }),
    ];

    await engine.sendAgentMessage(projectId, '只生成第 99 章事件', autoMode: false);

    expect(engine.agentMessages(projectId).last.content, contains('未找到匹配章节'));
    final eventTasks = db.select(
      'SELECT id FROM o_tasks WHERE taskClass=?',
      ['event_generation'],
    );
    expect(eventTasks, isEmpty);
  });

  test('Agent 顶层剧本工具接受 ToonFlow 剧本名称别名', () async {
    engine.addScript(projectId: projectId, name: '雪夜入山', content: 'A');
    final targetScript =
        engine.addScript(projectId: projectId, name: '灵脉试炼', content: 'B');
    gateway.turns = [
      AgentTurnResult.tool('extract_assets', const {
        'scriptName': '灵脉试炼',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只提取《灵脉试炼》的资产',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final assetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'extract_assets');
    final assetProperties = assetTool.schema['properties'] as Map;
    expect(assetProperties, contains('scriptName'));
    expect(
      engine
          .agentMessages(projectId, family: agentFamilyProduction)
          .last
          .content,
      contains('1 个剧本'),
    );
    final assetTask = db.select(
      'SELECT relatedObjects FROM o_tasks WHERE taskClass=?',
      ['asset_extraction'],
    ).single;
    final assetRelated = jsonDecode(assetTask['relatedObjects'] as String)
        as Map<String, dynamic>;
    expect(assetRelated['ids'], [targetScript]);
  });

  test('Agent 顶层媒体工具接受 ToonFlow 剧本和分镜 id 别名', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final storyboardA =
        engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final storyboardB =
        engine.addStoryboard(projectId: projectId, scriptId: scriptId);

    gateway.turns = [
      AgentTurnResult.tool('generate_storyboards', {
        'script_id': scriptId,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '给第一集生成分镜',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final storyboardTool = gateway.lastTools
        .singleWhere((tool) => tool.name == 'generate_storyboards');
    final storyboardProperties = storyboardTool.schema['properties'] as Map;
    expect(storyboardProperties, contains('script_id'));
    expect(
      engine
          .agentMessages(projectId, family: agentFamilyProduction)
          .last
          .content,
      contains('已提交分镜生成任务'),
    );

    gateway.turns = [
      AgentTurnResult.tool('generate_shot_images', {
        'episodeId': scriptId,
        'storyboard_ids': '$storyboardA',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只生成第一镜首帧',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final imageTool = gateway.lastTools
        .singleWhere((tool) => tool.name == 'generate_shot_images');
    final imageProperties = imageTool.schema['properties'] as Map;
    expect(imageProperties, contains('episodeId'));
    expect(imageProperties, contains('storyboard_ids'));
    expect(
      engine
          .agentMessages(projectId, family: agentFamilyProduction)
          .last
          .content,
      contains('1 个分镜'),
    );

    engine.setStoryboardImage(storyboardA, 'images/a.png');
    engine.setStoryboardImage(storyboardB, 'images/b.png');
    gateway.turns = [
      AgentTurnResult.tool('generate_videos', {
        'episode_id': scriptId,
        'storyboardIds': [storyboardB],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只生成第二镜视频',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final videoTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'generate_videos');
    final videoProperties = videoTool.schema['properties'] as Map;
    expect(videoProperties, contains('episode_id'));
    expect(
      engine
          .agentMessages(projectId, family: agentFamilyProduction)
          .last
          .content,
      contains('1 个分镜'),
    );
  });

  test('Agent 顶层媒体工具接受 ToonFlow 自然集号别名', () async {
    engine.addScript(projectId: projectId, name: '第一集', content: 'A');
    final secondScript =
        engine.addScript(projectId: projectId, name: '第二集', content: 'B');
    gateway.turns = [
      AgentTurnResult.tool('generate_storyboards', const {
        'episodeNo': 2,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '给第二集生成分镜',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final storyboardTool = gateway.lastTools
        .singleWhere((tool) => tool.name == 'generate_storyboards');
    final storyboardProperties = storyboardTool.schema['properties'] as Map;
    expect(storyboardProperties, contains('episodeNo'));
    expect(
      engine
          .agentMessages(projectId, family: agentFamilyProduction)
          .last
          .content,
      contains('已提交分镜生成任务'),
    );
    final task = db.select(
      'SELECT relatedObjects FROM o_tasks WHERE taskClass=?',
      ['storyboard_generate'],
    ).single;
    final related =
        jsonDecode(task['relatedObjects'] as String) as Map<String, dynamic>;
    expect(related['scriptId'], secondScript);
  });

  test('Agent 顶层媒体工具接受 ToonFlow 自然镜头号别名', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final storyboardA = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      videoDesc: '第一镜',
    );
    final storyboardB = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      videoDesc: '第二镜',
    );
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      videoDesc: '第三镜',
    );
    gateway.turns = [
      AgentTurnResult.tool('generate_shot_images', {
        'scriptId': scriptId,
        'shotNo': 2,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只生成第二镜首帧',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final imageTool = gateway.lastTools
        .singleWhere((tool) => tool.name == 'generate_shot_images');
    final imageProperties = imageTool.schema['properties'] as Map;
    expect(imageProperties, contains('shotNo'));
    expect(
      engine
          .agentMessages(projectId, family: agentFamilyProduction)
          .last
          .content,
      contains('1 个分镜'),
    );
    final imageTask = db.select(
      'SELECT relatedObjects FROM o_tasks WHERE taskClass=?',
      ['storyboard_image_generation'],
    ).single;
    final imageRelated = jsonDecode(imageTask['relatedObjects'] as String)
        as Map<String, dynamic>;
    expect(imageRelated['ids'], [storyboardB]);
    expect(imageRelated['ids'], isNot(contains(storyboardA)));

    engine.setStoryboardImage(storyboardA, 'images/a.png');
    engine.setStoryboardImage(storyboardB, 'images/b.png');
    gateway.turns = [
      AgentTurnResult.tool('generate_videos', {
        'scriptId': scriptId,
        'storyboardNo': 2,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只生成第二镜视频',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final videoTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'generate_videos');
    final videoProperties = videoTool.schema['properties'] as Map;
    expect(videoProperties, contains('storyboardNo'));
    final videoTask = db.select(
      'SELECT relatedObjects FROM o_tasks WHERE taskClass=?',
      ['video_generation'],
    ).single;
    final videoRelated = jsonDecode(videoTask['relatedObjects'] as String)
        as Map<String, dynamic>;
    final trackIds = (videoRelated['trackIds'] as List)
        .map((value) => (value as num).toInt())
        .toList();
    expect(trackIds, hasLength(1));
    final storyboardRow = db.select(
        'SELECT id FROM o_storyboard WHERE trackId=?',
        [trackIds.single]).single;
    expect(storyboardRow['id'], storyboardB);
  });

  test('Agent 自然镜头号未匹配时不会回退成全量媒体任务', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      videoDesc: '第一镜',
    );
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      videoDesc: '第二镜',
    );
    gateway.turns = [
      AgentTurnResult.tool('generate_shot_images', {
        'scriptId': scriptId,
        'shotNo': 99,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只生成第 99 镜首帧',
      autoMode: false,
      family: agentFamilyProduction,
    );

    expect(
      engine
          .agentMessages(projectId, family: agentFamilyProduction)
          .last
          .content,
      contains('未找到匹配分镜'),
    );
    final imageTasks = db.select(
      'SELECT id FROM o_tasks WHERE taskClass=?',
      ['storyboard_image_generation'],
    );
    expect(imageTasks, isEmpty);
  });

  test('Agent 可按资产名分析参考图并返回视觉描述', () async {
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    engine.saveAssetImage(
      assetsId: roleId,
      projectId: projectId,
      base64Image: base64Encode([137, 80, 78, 71]),
      type: 'role',
    );
    gateway.imageAnalysisResult = '冷白水墨风，少年剑修，轮廓清晰，适合角色一致性参考。';
    gateway.turns = [
      const AgentTurnResult.tool('analyze_reference_image', {
        'assetName': '李澈',
        'prompt': '提炼角色外观和画风关键词',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '分析李澈这张参考图',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final visionTool = gateway.lastTools
        .singleWhere((tool) => tool.name == 'analyze_reference_image');
    final properties = visionTool.schema['properties'] as Map;
    expect(properties, contains('assetName'));
    expect(gateway.imageAnalysisPrompts.single, '提炼角色外观和画风关键词');
    expect(gateway.imageAnalysisPaths.single, endsWith('.png'));
    final msg =
        engine.agentMessages(projectId, family: agentFamilyProduction).last;
    expect(msg.toolName, 'analyze_reference_image');
    expect(jsonDecode(msg.content), {
      'analysis': '冷白水墨风，少年剑修，轮廓清晰，适合角色一致性参考。',
      'source': 'asset:李澈',
    });
  });

  test('Agent 可一次分析多张参考图并返回分图视觉描述', () async {
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    final sceneId = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '寒山山门',
      describe: '宗门入口',
    );
    engine.saveAssetImage(
      assetsId: roleId,
      projectId: projectId,
      base64Image: base64Encode([137, 80, 78, 71, 1]),
      type: 'role',
    );
    engine.saveAssetImage(
      assetsId: sceneId,
      projectId: projectId,
      base64Image: base64Encode([137, 80, 78, 71, 2]),
      type: 'scene',
    );
    gateway.imageAnalysisResults = const [
      '角色参考：少年剑修，冷白衣袍，轮廓清晰。',
      '场景参考：山门高耸，云雾压低，冷白低饱和。',
    ];
    gateway.turns = [
      const AgentTurnResult.tool('analyze_reference_image', {
        'assetNames': ['李澈', '寒山山门'],
        'prompt': '分别提炼角色和场景的一致性关键词',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '同时分析角色和场景参考图',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final visionTool = gateway.lastTools
        .singleWhere((tool) => tool.name == 'analyze_reference_image');
    final properties = visionTool.schema['properties'] as Map;
    expect(properties, contains('assetNames'));
    expect(properties, contains('imagePaths'));
    expect(gateway.imageAnalysisPrompts, [
      '分别提炼角色和场景的一致性关键词',
      '分别提炼角色和场景的一致性关键词',
    ]);
    expect(gateway.imageAnalysisPaths, hasLength(2));
    final msg =
        engine.agentMessages(projectId, family: agentFamilyProduction).last;
    expect(msg.toolName, 'analyze_reference_image');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['sources'], ['asset:李澈', 'asset:寒山山门']);
    expect(payload['analysis'], contains('角色参考：少年剑修'));
    expect(payload['analysis'], contains('场景参考：山门高耸'));
    expect(payload['analyses'], [
      {
        'source': 'asset:李澈',
        'analysis': '角色参考：少年剑修，冷白衣袍，轮廓清晰。',
      },
      {
        'source': 'asset:寒山山门',
        'analysis': '场景参考：山门高耸，云雾压低，冷白低饱和。',
      },
    ]);
  });

  test('Agent 可按当前剧本资产引用分析参考图', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final decoyId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '误绑角色',
      describe: '不属于本集',
    );
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    final sceneId = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '寒山宗门',
      describe: '冷白山门',
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, roleId]);
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, sceneId]);
    engine.saveAssetImage(
      assetsId: decoyId,
      projectId: projectId,
      base64Image: base64Encode([137, 80, 78, 71, 0]),
      type: 'role',
    );
    engine.saveAssetImage(
      assetsId: roleId,
      projectId: projectId,
      base64Image: base64Encode([137, 80, 78, 71, 1]),
      type: 'role',
    );
    engine.saveAssetImage(
      assetsId: sceneId,
      projectId: projectId,
      base64Image: base64Encode([137, 80, 78, 71, 2]),
      type: 'scene',
    );
    gateway.imageAnalysisResults = const [
      'A001角色参考：李澈少年剑修。',
      'A002场景参考：寒山宗门冷白云雾。',
    ];
    gateway.turns = [
      AgentTurnResult.tool('analyze_reference_image', {
        'scriptId': scriptId,
        'assetRefs': const ['A001', 'A002'],
        'prompt': '按资产引用分析一致性',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按 A001 A002 分析参考图',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final visionTool = gateway.lastTools
        .singleWhere((tool) => tool.name == 'analyze_reference_image');
    final properties = visionTool.schema['properties'] as Map;
    expect(properties, contains('assetRef'));
    expect(properties, contains('assetRefs'));

    final msg =
        engine.agentMessages(projectId, family: agentFamilyProduction).last;
    expect(msg.toolName, 'analyze_reference_image');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['sources'], ['asset:李澈', 'asset:寒山宗门']);
    expect(payload['analysis'], contains('A001角色参考'));
    expect(payload['analysis'], contains('A002场景参考'));
    expect(payload['analysis'], isNot(contains('误绑角色')));
    expect(gateway.imageAnalysisPaths, hasLength(2));
  });

  test('Agent 可按自然镜头号分析分镜首帧参考图', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final firstStoryboard = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      videoDesc: '第一镜，山脚远景',
    );
    final secondStoryboard = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      videoDesc: '第二镜，山门近景',
    );
    const firstRel = 'shots/first.png';
    const secondRel = 'shots/second.png';
    final firstFile = File(engine.mediaAbsPath(firstRel));
    firstFile.parent.createSync(recursive: true);
    firstFile.writeAsBytesSync([137, 80, 78, 71, 1]);
    final secondFile = File(engine.mediaAbsPath(secondRel));
    secondFile.parent.createSync(recursive: true);
    secondFile.writeAsBytesSync([137, 80, 78, 71, 2]);
    engine.setStoryboardImage(firstStoryboard, firstRel);
    engine.setStoryboardImage(secondStoryboard, secondRel);
    gateway.imageAnalysisResult = '第二镜首帧：寒山山门冷白云雾，低机位。';
    gateway.turns = [
      AgentTurnResult.tool('analyze_reference_image', {
        'scriptId': scriptId,
        'shotNo': 2,
        'prompt': '分析第二镜首帧',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '分析第二镜首帧参考图',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final visionTool = gateway.lastTools
        .singleWhere((tool) => tool.name == 'analyze_reference_image');
    final properties = visionTool.schema['properties'] as Map;
    expect(properties, contains('shotNo'));
    expect(properties, contains('storyboardNo'));
    expect(gateway.imageAnalysisPrompts.single, '分析第二镜首帧');
    expect(gateway.imageAnalysisPaths.single, secondFile.path);
    expect(gateway.imageAnalysisPaths.single, isNot(firstFile.path));

    final msg =
        engine.agentMessages(projectId, family: agentFamilyProduction).last;
    expect(msg.toolName, 'analyze_reference_image');
    expect(jsonDecode(msg.content), {
      'analysis': '第二镜首帧：寒山山门冷白云雾，低机位。',
      'source': 'storyboard:$secondStoryboard',
    });
  });

  test('Agent 可按项目画风分析视觉手册封面参考图', () async {
    engine.saveVisualManual(
      name: '国风水墨',
      imageBytesBase64: [
        base64Encode([137, 80, 78, 71, 9])
      ],
      data: {for (final key in visualManualKeys) key: '$key 内容'},
    );
    final coverPath = engine.visualManuals().single.images.single;
    db.execute(
        'UPDATE o_project SET artStyle=? WHERE id=?', ['国风水墨', projectId]);
    gateway.imageAnalysisResult = '项目画风：冷白水墨、低饱和、云雾留白。';
    gateway.turns = [
      const AgentTurnResult.tool('analyze_reference_image', {
        'projectArtStyle': true,
        'prompt': '提炼项目视觉手册封面画风',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '分析项目画风封面',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final visionTool = gateway.lastTools
        .singleWhere((tool) => tool.name == 'analyze_reference_image');
    final properties = visionTool.schema['properties'] as Map;
    expect(properties, contains('projectArtStyle'));
    expect(properties, contains('visualManualName'));
    expect(gateway.imageAnalysisPrompts.single, '提炼项目视觉手册封面画风');
    expect(gateway.imageAnalysisPaths.single, coverPath);

    final msg =
        engine.agentMessages(projectId, family: agentFamilyProduction).last;
    expect(msg.toolName, 'analyze_reference_image');
    expect(jsonDecode(msg.content), {
      'analysis': '项目画风：冷白水墨、低饱和、云雾留白。',
      'source': 'visualManual:国风水墨',
    });
  });

  test('Agent 视觉分析 schema 暴露项目画风和保存记忆中文别名', () async {
    engine.saveVisualManual(
      name: '国风水墨',
      imageBytesBase64: [
        base64Encode([137, 80, 78, 71, 12])
      ],
      data: {for (final key in visualManualKeys) key: '$key 内容'},
    );
    final coverPath = engine.visualManuals().single.images.single;
    db.execute(
        'UPDATE o_project SET artStyle=? WHERE id=?', ['国风水墨', projectId]);
    gateway.imageAnalysisResult = '项目画风：冷白水墨、云雾留白、人物轮廓清晰。';
    gateway.turns = [
      const AgentTurnResult.tool('analyze_reference_image', {
        '项目画风': true,
        '提示词': '提炼项目画风',
        '保存记忆': true,
        '记忆名称': '项目画风视觉参考',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '分析项目画风并保存成记忆',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final visionTool = gateway.lastTools
        .singleWhere((tool) => tool.name == 'analyze_reference_image');
    final properties = (visionTool.schema['properties'] as Map).keys;
    expect(
      properties,
      containsAll([
        'project_art_style',
        'use_project_art_style',
        '项目画风',
        '当前画风',
        'art_style_name',
        'visual_manual_name',
        '画风',
        '画风名称',
        '视觉手册',
        '视觉手册名称',
        'save_memory',
        '记住',
        '保存记忆',
        '写入记忆',
        '记忆名称',
        '标题',
      ]),
    );
    expect(gateway.imageAnalysisPrompts.single, '提炼项目画风');
    expect(gateway.imageAnalysisPaths.single, coverPath);

    final msg =
        engine.agentMessages(projectId, family: agentFamilyProduction).last;
    expect(msg.toolName, 'analyze_reference_image');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['analysis'], '项目画风：冷白水墨、云雾留白、人物轮廓清晰。');
    expect(payload['source'], 'visualManual:国风水墨');
    expect(payload['memory'], {
      'saved': true,
      'id': isA<String>(),
      'type': agentMemoryTypeNote,
      'scope': 'long_term',
      'name': '项目画风视觉参考',
    });

    final saved = engine
        .agentLongTermMemories(projectId)
        .singleWhere((item) => item.name == '项目画风视觉参考');
    expect(saved.content, contains('visualManual:国风水墨'));
    expect(saved.content, contains('云雾留白'));
  });

  test('Agent 可按画风库名称分析画风封面参考图', () async {
    engine.addArtStyle(
      name: '赛博霓虹',
      prompt: 'neon cyberpunk',
      base64Image: base64Encode([137, 80, 78, 71, 10]),
    );
    final coverRel = engine.artStyles().single.fileUrl!;
    final coverPath = engine.mediaAbsPath(coverRel);
    gateway.imageAnalysisResult = '画风库封面：高饱和霓虹、赛博城市、强对比光。';
    gateway.turns = [
      const AgentTurnResult.tool('analyze_reference_image', {
        'artStyleName': '赛博霓虹',
        'prompt': '提炼画风库封面',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '分析画风库封面',
      autoMode: false,
      family: agentFamilyProduction,
    );

    expect(gateway.imageAnalysisPrompts, ['提炼画风库封面']);
    expect(gateway.imageAnalysisPaths, [coverPath]);
    final msg =
        engine.agentMessages(projectId, family: agentFamilyProduction).last;
    expect(msg.toolName, 'analyze_reference_image');
    expect(jsonDecode(msg.content), {
      'analysis': '画风库封面：高饱和霓虹、赛博城市、强对比光。',
      'source': 'artStyle:赛博霓虹',
    });
  });

  test('Agent 视觉分析可保存为长期记忆并被 memory_get 召回', () async {
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    engine.saveAssetImage(
      assetsId: roleId,
      projectId: projectId,
      base64Image: base64Encode([137, 80, 78, 71]),
      type: 'role',
    );
    gateway.imageAnalysisResult = '视觉设定：李澈是冷白水墨风少年剑修，衣袍低饱和，轮廓清晰。';
    gateway.turns = [
      const AgentTurnResult.tool('analyze_reference_image', {
        'assetName': '李澈',
        'prompt': '提炼角色视觉设定',
        'remember': true,
        'memoryName': '李澈视觉参考',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '分析并记住李澈参考图',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final visionTool = gateway.lastTools
        .singleWhere((tool) => tool.name == 'analyze_reference_image');
    final properties = visionTool.schema['properties'] as Map;
    expect(properties, contains('remember'));
    expect(properties, contains('saveMemory'));
    expect(properties, contains('memoryName'));

    final analyzeMsg =
        engine.agentMessages(projectId, family: agentFamilyProduction).last;
    expect(analyzeMsg.toolName, 'analyze_reference_image');
    final analyzePayload =
        jsonDecode(analyzeMsg.content) as Map<String, dynamic>;
    expect(analyzePayload['memory'], {
      'saved': true,
      'id': isA<String>(),
      'type': agentMemoryTypeNote,
      'scope': 'long_term',
      'name': '李澈视觉参考',
    });

    final longTerm = engine.agentLongTermMemories(projectId);
    final saved = longTerm.singleWhere((item) => item.name == '李澈视觉参考');
    expect(saved.content, contains('asset:李澈'));
    expect(saved.content, contains('冷白水墨风少年剑修'));

    gateway.turns = [
      const AgentTurnResult.tool('memory_get', {
        'query': '李澈 冷白水墨 少年剑修',
        'scope': 'long_term',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '查一下李澈视觉设定',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final memoryMsg =
        engine.agentMessages(projectId, family: agentFamilyProduction).last;
    expect(memoryMsg.toolName, 'memory_get');
    final memoryPayload = jsonDecode(memoryMsg.content) as Map<String, dynamic>;
    expect(memoryPayload['found'], isTrue);
    expect(memoryPayload['notes'], contains(saved.content));
    expect(
      memoryPayload['records'],
      contains(isA<Map>().having((record) => record['id'], 'id', saved.id)),
    );
  });

  test('Agent 顶层配音工具接受 ToonFlow 自然角色号别名', () async {
    engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '少年剑修',
    );
    final roleB = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '沈微',
      describe: '冷静师姐',
    );
    engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '秦岳',
      describe: '宗门长老',
    );
    gateway.turns = [
      AgentTurnResult.tool('bind_audio', const {
        'roleNo': 2,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只给第二个角色匹配配音',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final audioTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'bind_audio');
    final audioProperties = audioTool.schema['properties'] as Map;
    expect(audioProperties, contains('roleNo'));
    expect(
      engine
          .agentMessages(projectId, family: agentFamilyProduction)
          .last
          .content,
      contains('1 个角色'),
    );
    final audioTask = db.select(
      'SELECT relatedObjects FROM o_tasks WHERE taskClass=?',
      ['audio_bind'],
    ).single;
    final related = jsonDecode(audioTask['relatedObjects'] as String)
        as Map<String, dynamic>;
    expect(related['roleIds'], [roleB]);
  });

  test('Agent 顶层配音工具按角色名精确匹配且保留名称空格', () async {
    final roleA = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: 'Old Master Li',
      describe: '隐世长者',
    );
    engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '沈微',
      describe: '冷静师姐',
    );
    gateway.turns = [
      AgentTurnResult.tool('bind_audio', const {
        'roleName': 'Old Master Li',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只给 Old Master Li 匹配配音',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final audioTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'bind_audio');
    final audioProperties = audioTool.schema['properties'] as Map;
    expect(audioProperties, contains('roleName'));
    final audioTask = db.select(
      'SELECT relatedObjects FROM o_tasks WHERE taskClass=?',
      ['audio_bind'],
    ).single;
    final related = jsonDecode(audioTask['relatedObjects'] as String)
        as Map<String, dynamic>;
    expect(related['roleIds'], [roleA]);
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

  test('监督 Agent 接受中文自然放行结论', () async {
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
      const AgentTurnResult.text('可以执行：章节范围明确。'),
    ];

    await engine.sendAgentMessage(projectId, '生成事件', autoMode: false);

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
    final memoryRoles = db.select(
      'SELECT role FROM memories WHERE isolationKey=? AND type=? '
      'ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', agentMemoryTypeMessage],
    ).map((row) => row['role']);
    expect(memoryRoles, contains('assistant:supervision'));
  });

  test('监督 Agent 清理中文自然拒绝前缀', () async {
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
      AgentTurnResult.text('不允许执行：没有明确授权批量生成全部章节。'),
    ];

    await engine.sendAgentMessage(projectId, '直接批量生成事件', autoMode: false);

    expect(db.select('SELECT id FROM o_tasks'), isEmpty);
    final msg = engine.agentMessages(projectId).last;
    expect(
      msg.content,
      '监督 Agent 已拦截 generate_events：没有明确授权批量生成全部章节。',
    );
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

  test('自定义脚本技能：支持 Object.groupBy 和 Map.groupBy 分组资产', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_group_by_runtime',
      name: '分组脚本运行时',
      description: '验证自定义技能兼容模型常写的 Object.groupBy/Map.groupBy 资产分组。',
      script: r'''
const grouped = Object.groupBy(args.assets, asset => asset.type);
const frontLoaded = Object.groupBy(args.assets, (asset, index) =>
  index < 2 ? 'front' : asset.type);
const groupedMap = Map.groupBy(args.assets, asset => asset.type);
return JSON.stringify({
  keys: Object.keys(grouped).sort().join('|'),
  roles: grouped.role.map(asset => asset.name.trim()).join('、'),
  sceneCount: grouped.scene.length,
  front: frontLoaded.front.map(asset => asset.name.trim()).join('、'),
  mapKeys: Array.from(groupedMap.keys()).sort().join('|'),
  tools: groupedMap.get('tool').map(asset => asset.name.trim()).join('、'),
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
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_group_by_runtime', const {
        'assets': [
          {'type': 'role', 'name': ' 李澈 '},
          {'type': 'scene', 'name': '寒山宗门'},
          {'type': 'tool', 'name': ' 霜剑 '},
          {'type': 'role', 'name': '沈微'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用分组脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_group_by_runtime');
    expect(jsonDecode(msg.content), {
      'keys': 'role|scene|tool',
      'roles': '李澈、沈微',
      'sceneCount': 1,
      'front': '李澈、寒山宗门',
      'mapKeys': 'role|scene|tool',
      'tools': '霜剑',
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

  test('自定义脚本技能：支持 Object.fromEntries 直接读取 Map', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_from_entries_map_runtime',
      name: 'Object.fromEntries Map 脚本运行时',
      description: '验证自定义技能兼容模型常写的 Object.fromEntries(map)。',
      script: r'''
const assetsById = new Map(Object.entries(args.assetsById));
assetsById.delete('A002');
assetsById.set('A004', {
  type: 'tool',
  name: args.fallbackName.trim(),
});
const payload = Object.fromEntries(assetsById);
return JSON.stringify({
  keys: Object.keys(payload).join('|'),
  primaryName: payload.A001.name.trim(),
  generatedName: payload.A004.name,
  removed: Object.hasOwn(payload, 'A002'),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'assetsById': {'type': 'object'},
          'fallbackName': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_from_entries_map_runtime', const {
        'assetsById': {
          'A001': {'type': 'role', 'name': ' 李澈 '},
          'A002': {'type': 'scene', 'name': '废弃场景'},
          'A003': {'type': 'scene', 'name': '寒山宗门'},
        },
        'fallbackName': ' 灵剑 ',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Object.fromEntries Map 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_from_entries_map_runtime');
    expect(msg.content, isNot(startsWith('执行失败')));
    expect(jsonDecode(msg.content), {
      'keys': 'A001|A003|A004',
      'primaryName': '李澈',
      'generatedName': '灵剑',
      'removed': false,
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

  test('自定义脚本技能：支持 Array.of 组合引用列表', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_array_of_runtime',
      name: 'Array.of 脚本运行时',
      description: '验证自定义技能兼容模型常写的 Array.of(...) 快速组合列表。',
      script: r'''
const references = Array.of(args.hero, args.scene, ...args.extras)
  .filter(Boolean)
  .map((item, index) => `${index + 1}.${item.name.trim()}`);
const empty = Array.of();
return JSON.stringify({
  references: references.join('、'),
  emptyLength: empty.length,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'hero': {'type': 'object'},
          'scene': {'type': 'object'},
          'extras': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_array_of_runtime', const {
        'hero': {'name': ' 李澈 '},
        'scene': {'name': '寒山宗门'},
        'extras': [
          {'name': ' 霜剑 '},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Array.of 脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_array_of_runtime');
    expect(jsonDecode(msg.content), {
      'references': '1.李澈、2.寒山宗门、3.霜剑',
      'emptyLength': 0,
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

  test('自定义脚本技能：支持数组 keys values entries 迭代', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_array_iteration_runtime',
      name: '数组迭代器脚本运行时',
      description: '验证自定义技能兼容模型常写的 array.keys/values/entries。',
      script: r'''
const labels = [];
for (const [index, shot] of args.storyboards.entries()) {
  if (!shot.videoDesc?.trim()) {
    continue;
  }
  labels.push(`${index + 1}.${shot.videoDesc.trim()}`);
}
return JSON.stringify({
  labels: labels.join('、'),
  keys: Array.from(args.storyboards.keys()).join('|'),
  values: args.storyboards.values()
    .map(shot => shot.videoDesc?.trim() || '空镜')
    .join('|'),
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
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_array_iteration_runtime', const {
        'storyboards': [
          {'videoDesc': ' 雪夜山门 '},
          {'videoDesc': ''},
          {'videoDesc': '李澈拔剑'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用数组迭代器脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_array_iteration_runtime');
    expect(jsonDecode(msg.content), {
      'labels': '1.雪夜山门、3.李澈拔剑',
      'keys': '0|1|2',
      'values': '雪夜山门|空镜|李澈拔剑',
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

  test('自定义脚本技能：支持 Set forEach keys values entries 迭代', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_set_iteration_runtime',
      name: 'Set 迭代脚本运行时',
      description: '验证自定义技能兼容模型常写的 set.forEach/values/entries。',
      script: r'''
const unique = new Set(args.assets.map(asset => asset.type.trim()));
const visited = [];
unique.forEach(function (value, duplicateValue, source) {
  visited.push(`${value}:${duplicateValue}:${source.size}`);
});

return JSON.stringify({
  values: Array.from(unique.values()).join('|'),
  keys: Array.from(unique.keys()).join('|'),
  entries: Array.from(unique.entries()).map(([key, value]) => `${key}=${value}`).join('|'),
  visited: visited.join('|'),
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
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_set_iteration_runtime', const {
        'assets': [
          {'type': ' role '},
          {'type': 'scene'},
          {'type': 'role'},
          {'type': 'tool'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Set 迭代脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_set_iteration_runtime');
    expect(jsonDecode(msg.content), {
      'values': 'role|scene|tool',
      'keys': 'role|scene|tool',
      'entries': 'role=role|scene=scene|tool=tool',
      'visited': 'role:role:3|scene:scene:3|tool:tool:3',
    });
  });

  test('自定义脚本技能：支持 Set 集合运算检查资产覆盖', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_set_operations_runtime',
      name: 'Set 集合运算脚本运行时',
      description: '验证自定义技能兼容模型常写的 Set union/intersection/difference。',
      script: r'''
const required = new Set(args.requiredAssets.map(asset => asset.trim()));
const existing = new Set(args.existingAssets.map(asset => asset.trim()));
const optional = new Set(args.optionalAssets.map(asset => asset.trim()));
const missing = required.difference(existing);
const matched = required.intersection(existing);
const candidates = missing.union(optional);
return JSON.stringify({
  matched: Array.from(matched).sort().join('、'),
  missing: Array.from(missing).sort().join('、'),
  candidates: Array.from(candidates).sort().join('、'),
  complete: required.isSubsetOf(existing),
  hasOptionalGap: optional.isDisjointFrom(existing),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'requiredAssets': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'existingAssets': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'optionalAssets': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_set_operations_runtime', const {
        'requiredAssets': [' A001 ', 'A002', 'A003'],
        'existingAssets': ['A001', 'A003', 'A004'],
        'optionalAssets': ['A005', ' A006 '],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Set 集合运算脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_set_operations_runtime');
    expect(msg.content, isNot(startsWith('执行失败')));
    expect(jsonDecode(msg.content), {
      'matched': 'A001、A003',
      'missing': 'A002',
      'candidates': 'A002、A005、A006',
      'complete': false,
      'hasOptionalGap': true,
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

  test('自定义脚本技能：支持 Map.forEach 用 value key source 聚合', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_map_foreach_runtime',
      name: 'Map forEach 脚本运行时',
      description: '验证自定义技能兼容模型常写的 map.forEach((value, key, source) => ...)。',
      script: r'''
const assetsById = new Map(Object.entries(args.assetsById));
let labels = [];
let totalDuration = 0;
let sourceSeen = [];
assetsById.forEach((asset, id, source) => {
  if (asset.enabled === false) {
    return;
  }
  labels.push(`${id}:${source.get(id).name.trim()}`);
  sourceSeen.push(`${id}/${source.size}`);
  totalDuration += asset.duration ?? 0;
});
return JSON.stringify({
  labels: labels.join('、'),
  sourceSeen: sourceSeen.join('|'),
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
      'sourceSeen': 'A001/3|A003/3',
      'totalDuration': 5,
    });
  });

  test('自定义脚本技能：支持 for of 直接遍历 Map entries', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_map_for_of_runtime',
      name: 'Map for of 脚本运行时',
      description: '验证自定义技能兼容模型常写的 for (const [id, asset] of map) 语法。',
      script: r'''
const assetsById = new Map(Object.entries(args.assetsById));
let labels = [];
let totalDuration = 0;
for (const [id, asset] of assetsById) {
  if (asset.enabled === false) {
    continue;
  }
  labels.push(`${id}:${asset.name.trim()}`);
  totalDuration += asset.duration ?? 0;
}
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
      AgentTurnResult.tool('custom_script_map_for_of_runtime', const {
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
      '调用 Map for of 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_map_for_of_runtime');
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

  test('自定义脚本技能：支持 Date 拆分年月日时分秒', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_date_parts_runtime',
      name: 'Date 拆分脚本运行时',
      description: '验证自定义技能兼容模型常写的 Date getter 批次命名。',
      script: r'''
const date = new Date(args.iso);
const batch = [
  date.getFullYear(),
  String(date.getMonth() + 1).padStart(2, '0'),
  String(date.getDate()).padStart(2, '0'),
  String(date.getHours()).padStart(2, '0'),
  String(date.getMinutes()).padStart(2, '0'),
  String(date.getSeconds()).padStart(2, '0'),
].join('');
return JSON.stringify({
  batch,
  utcYear: date.getUTCFullYear(),
  utcMonth: date.getUTCMonth(),
  utcDate: date.getUTCDate(),
  utcDay: date.getUTCDay(),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'iso': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_date_parts_runtime', const {
        'iso': '2026-07-08T09:10:11.000Z',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Date 拆分脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_date_parts_runtime');
    expect(msg.content, isNot(startsWith('执行失败')));
    expect(jsonDecode(msg.content), {
      'batch': '20260708091011',
      'utcYear': 2026,
      'utcMonth': 6,
      'utcDate': 8,
      'utcDay': 3,
    });
  });

  test('自定义脚本技能：支持 Date 多参数构造和 UTC 静态方法', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_date_multi_arg_runtime',
      name: 'Date 多参数脚本运行时',
      description: '验证自定义技能兼容模型常写的 new Date(y,m,d) 和 Date.UTC。',
      script: r'''
const scheduled = new Date(
  args.year,
  args.month,
  args.day,
  args.hour,
  args.minute,
  args.second,
  args.ms,
);
const startOfMonth = new Date(Date.UTC(args.year, args.month, 1));
return JSON.stringify({
  scheduledIso: scheduled.toISOString(),
  scheduledTime: scheduled.getTime(),
  startIso: startOfMonth.toISOString(),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'year': {'type': 'number'},
          'month': {'type': 'number'},
          'day': {'type': 'number'},
          'hour': {'type': 'number'},
          'minute': {'type': 'number'},
          'second': {'type': 'number'},
          'ms': {'type': 'number'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_date_multi_arg_runtime', const {
        'year': 2026,
        'month': 6,
        'day': 8,
        'hour': 9,
        'minute': 10,
        'second': 11,
        'ms': 120,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Date 多参数脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_date_multi_arg_runtime');
    expect(msg.content, isNot(startsWith('执行失败')));
    expect(jsonDecode(msg.content), {
      'scheduledIso': '2026-07-08T09:10:11.120Z',
      'scheduledTime': 1783501811120,
      'startIso': '2026-07-01T00:00:00.000Z',
    });
  });

  test('自定义脚本技能：支持 Date setter 顺延排期', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_date_setter_runtime',
      name: 'Date setter 脚本运行时',
      description: '验证自定义技能兼容模型常写的 Date.setDate 排期顺延。',
      script: r'''
const date = new Date(Date.UTC(args.year, args.month, args.day, 23, 0, 0));
const nextTime = date.setDate(date.getDate() + args.offsetDays);
const finalTime = date.setHours(args.hour, args.minute, args.second, args.ms);
return JSON.stringify({
  nextIso: new Date(nextTime).toISOString(),
  finalIso: date.toISOString(),
  finalTime,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'year': {'type': 'number'},
          'month': {'type': 'number'},
          'day': {'type': 'number'},
          'offsetDays': {'type': 'number'},
          'hour': {'type': 'number'},
          'minute': {'type': 'number'},
          'second': {'type': 'number'},
          'ms': {'type': 'number'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_date_setter_runtime', const {
        'year': 2026,
        'month': 6,
        'day': 30,
        'offsetDays': 2,
        'hour': 8,
        'minute': 30,
        'second': 15,
        'ms': 250,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Date setter 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_date_setter_runtime');
    expect(msg.content, isNot(startsWith('执行失败')));
    expect(jsonDecode(msg.content), {
      'nextIso': '2026-08-01T23:00:00.000Z',
      'finalIso': '2026-08-01T08:30:15.250Z',
      'finalTime': 1785573015250,
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

  test('自定义脚本技能：支持嵌套对象解构读取工作区字段', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_nested_destructure_runtime',
      name: '嵌套解构脚本运行时',
      description: '验证自定义技能兼容模型常写的嵌套对象解构整理工作区数据。',
      script: r'''
const {
  project: { name: projectName },
  meta: { style = '默认画风' },
} = args.workspace;

const labels = args.shots.map(({
  storyboard: { videoDesc, duration = 3 },
  asset: { name: assetName = '未命名资产' },
}, index) => `${index + 1}.${videoDesc.trim()}@${duration}s/${assetName.trim()}`);

return JSON.stringify({
  projectName: projectName.trim(),
  style,
  labels,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'workspace': {'type': 'object'},
          'shots': {'type': 'array'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_nested_destructure_runtime', const {
        'workspace': {
          'project': {'name': ' 寒山短剧 '},
          'meta': {},
        },
        'shots': [
          {
            'storyboard': {'videoDesc': ' 雪夜山门 ', 'duration': 4},
            'asset': {'name': ' 李澈 '},
          },
          {
            'storyboard': {'videoDesc': ' 沈微回头 '},
            'asset': {},
          },
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用嵌套解构脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_nested_destructure_runtime');
    expect(jsonDecode(msg.content), {
      'projectName': '寒山短剧',
      'style': '默认画风',
      'labels': ['1.雪夜山门@4s/李澈', '2.沈微回头@3s/未命名资产'],
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

  test('自定义脚本技能：支持数组中的嵌套解构读取参考项', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_nested_array_destructure_runtime',
      name: '数组嵌套解构脚本运行时',
      description: '验证自定义技能兼容模型常写的数组项嵌套对象/数组解构。',
      script: r'''
const [coverImage, { name: heroName = '未命名角色' }, [sceneName, sceneMood = '默认氛围']] = args.references;

const labels = args.rows.map(([index, {
  storyboard: { videoDesc, duration = 3 },
}, [assetName = '未命名资产']], rowIndex) =>
  `${rowIndex + 1}/${index}.${videoDesc.trim()}@${duration}s/${assetName.trim()}`);

return JSON.stringify({
  cover: coverImage.name.trim(),
  heroName: heroName.trim(),
  scene: `${sceneName.trim()}-${sceneMood.trim()}`,
  labels,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'references': {'type': 'array'},
          'rows': {'type': 'array'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool(
        'custom_script_nested_array_destructure_runtime',
        const {
          'references': [
            {'name': ' 封面图 '},
            {'name': ' 李澈 '},
            [' 寒山宗门 ', ' 冷白云雾 '],
          ],
          'rows': [
            [
              1,
              {
                'storyboard': {'videoDesc': ' 雪夜拔剑 ', 'duration': 4},
              },
              [' 霜刃 '],
            ],
            [
              2,
              {
                'storyboard': {'videoDesc': ' 沈微回望 '},
              },
              [],
            ],
          ],
        },
      ),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用数组嵌套解构脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_nested_array_destructure_runtime');
    expect(jsonDecode(msg.content), {
      'cover': '封面图',
      'heroName': '李澈',
      'scene': '寒山宗门-冷白云雾',
      'labels': ['1/1.雪夜拔剑@4s/霜刃', '2/2.沈微回望@3s/未命名资产'],
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

  test('自定义脚本技能：支持 structuredClone 复制并改写分镜 payload', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_structured_clone_runtime',
      name: 'structuredClone 脚本运行时',
      description: '验证自定义技能兼容模型常写的 structuredClone(args) 防止改写原始入参。',
      script: r'''
const cloned = structuredClone(args.storyboards);
cloned[0].videoDesc = cloned[0].videoDesc.trim();
cloned[0].refs.push('首帧');
cloned[1].refs = [...cloned[1].refs, '角色参考'];
return JSON.stringify({
  clonedFirst: `${cloned[0].videoDesc}:${cloned[0].refs.join('|')}`,
  clonedSecond: `${cloned[1].videoDesc}:${cloned[1].refs.join('|')}`,
  originalFirst: `${args.storyboards[0].videoDesc}:${args.storyboards[0].refs.join('|')}`,
  originalSecond: `${args.storyboards[1].videoDesc}:${args.storyboards[1].refs.join('|')}`,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'storyboards': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_structured_clone_runtime', const {
        'storyboards': [
          {
            'videoDesc': ' 寒山宗门 ',
            'refs': ['A001'],
          },
          {
            'videoDesc': '李澈拔剑',
            'refs': ['A002'],
          },
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 structuredClone 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_structured_clone_runtime');
    expect(msg.content, isNot(startsWith('执行失败')));
    expect(jsonDecode(msg.content), {
      'clonedFirst': '寒山宗门:A001|首帧',
      'clonedSecond': '李澈拔剑:A002|角色参考',
      'originalFirst': ' 寒山宗门 :A001',
      'originalSecond': '李澈拔剑:A002',
    });
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

  test('自定义脚本技能：支持 switch case 归类资产', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_switch_runtime',
      name: 'switch 分类脚本运行时',
      description: '验证自定义技能兼容模型常写的 switch/case/default 分类逻辑。',
      script: r'''
const buckets = { role: [], scene: [], other: [] };
for (const asset of args.assets) {
  switch (asset.type) {
    case 'role':
      buckets.role.push(asset.name.trim());
      break;
    case 'scene':
      buckets.scene.push(asset.name.trim());
      break;
    case 'tool':
    case 'audio':
      buckets.other.push(`asset:${asset.name.trim()}`);
      break;
    default:
      buckets.other.push(`misc:${asset.name.trim()}`);
  }
}
return JSON.stringify(buckets);
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
      AgentTurnResult.tool('custom_script_switch_runtime', const {
        'assets': [
          {'type': 'role', 'name': ' 李澈 '},
          {'type': 'scene', 'name': '寒山宗门'},
          {'type': 'tool', 'name': '灵剑'},
          {'type': 'audio', 'name': '风雪声'},
          {'type': 'unknown', 'name': '残卷'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 switch 分类脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_switch_runtime');
    expect(jsonDecode(msg.content), {
      'role': ['李澈'],
      'scene': ['寒山宗门'],
      'other': ['asset:灵剑', 'asset:风雪声', 'misc:残卷'],
    });
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

  test('自定义脚本技能：支持数组方法传入匿名 function 回调', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_function_expression_callback_runtime',
      name: '匿名函数回调脚本运行时',
      description: '验证自定义技能兼容模型常写的 map(function (item) { ... }) 回调。',
      script: r'''
const usable = args.storyboards
  .filter(function (shot) {
    return !shot.disabled && !!shot.videoDesc?.trim();
  })
  .map(function (shot, index, all) {
    return `${index + 1}/${all.length}.${shot.videoDesc.trim()}`;
  });

const total = args.storyboards.reduce(function (sum, shot) {
  return sum + Number(shot.duration ?? 1);
}, 0);

return JSON.stringify({
  labels: usable.join('、'),
  total,
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
      AgentTurnResult.tool(
          'custom_script_function_expression_callback_runtime', const {
        'storyboards': [
          {'videoDesc': ' 雪夜山门 ', 'duration': 3},
          {'videoDesc': '', 'duration': 4},
          {'videoDesc': '废弃镜头', 'duration': 8, 'disabled': true},
          {'videoDesc': '李澈拔剑'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用匿名函数回调脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_function_expression_callback_runtime');
    expect(jsonDecode(msg.content), {
      'labels': '1/2.雪夜山门、2/2.李澈拔剑',
      'total': 16,
    });
  });

  test('自定义脚本技能：支持同步 async function 和 await 表达式', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_sync_async_await_runtime',
      name: '同步 async await 脚本运行时',
      description: '验证自定义技能兼容模型常写的纯计算 async function/await helper。',
      script: r'''
async function normalizeShot(shot, index) {
  const desc = await shot.videoDesc.trim();
  const duration = await Number(shot.duration ?? 1);
  return `${index + 1}.${desc}:${duration}s`;
}

const labels = [];
for (const [index, shot] of args.storyboards.entries()) {
  if (shot.disabled || !shot.videoDesc?.trim()) {
    continue;
  }
  labels.push(await normalizeShot(shot, index));
}

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
      AgentTurnResult.tool('custom_script_sync_async_await_runtime', const {
        'storyboards': [
          {'videoDesc': ' 雪夜山门 ', 'duration': 3},
          {'videoDesc': '', 'duration': 4},
          {'videoDesc': '废弃镜头', 'duration': 8, 'disabled': true},
          {'videoDesc': '李澈拔剑'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用同步 async await 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_sync_async_await_runtime');
    expect(msg.content, '1.雪夜山门:3s、4.李澈拔剑:1s');
  });

  test('自定义脚本技能：支持 Promise.all 和 Promise.resolve 包裹同步结果', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_promise_static_runtime',
      name: 'Promise 静态工具脚本运行时',
      description: '验证自定义技能兼容模型常写的 await Promise.all([...].map(...)) 纯数据整理。',
      script: r'''
const labels = await Promise.all(
  args.storyboards
    .filter(shot => !shot.disabled && !!shot.videoDesc?.trim())
    .map((shot, index) => Promise.resolve(`${index + 1}.${shot.videoDesc.trim()}`))
);

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
      AgentTurnResult.tool('custom_script_promise_static_runtime', const {
        'storyboards': [
          {'videoDesc': ' 山门落雪 '},
          {'videoDesc': ''},
          {'videoDesc': '废弃镜头', 'disabled': true},
          {'videoDesc': '灵剑出鞘'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Promise 静态工具脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_promise_static_runtime');
    expect(msg.content, '1.山门落雪、2.灵剑出鞘');
  });

  test('自定义脚本技能：支持 Promise.all 内的同步 async 箭头回调', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_async_arrow_promise_runtime',
      name: 'Promise async 箭头脚本运行时',
      description:
          '验证自定义技能兼容模型常写的 await Promise.all(list.map(async (...) => ...)) 纯数据整理。',
      script: r'''
const labels = await Promise.all(
  args.storyboards
    .filter(shot => !shot.disabled && !!shot.videoDesc?.trim())
    .map(async (shot, index) => {
      const desc = await shot.videoDesc.trim();
      return Promise.resolve(`${index + 1}.${desc}`);
    })
);

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
      AgentTurnResult.tool('custom_script_async_arrow_promise_runtime', const {
        'storyboards': [
          {'videoDesc': ' 宗门晨练 '},
          {'videoDesc': ''},
          {'videoDesc': '废弃镜头', 'disabled': true},
          {'videoDesc': '灵阵亮起'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Promise async 箭头脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_async_arrow_promise_runtime');
    expect(msg.content, '1.宗门晨练、2.灵阵亮起');
  });

  test('自定义脚本技能：Promise.all rejected 可被链式 catch 捕获', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_promise_all_rejected_runtime',
      name: 'Promise all rejected 脚本运行时',
      description: '验证自定义技能兼容模型常写的 Promise.all(...).catch(...) 失败兜底。',
      script: r'''
const result = await Promise.all(
  args.storyboards.map((shot, index) => {
    if (!shot.videoDesc?.trim()) {
      return Promise.reject(new Error(`第${index + 1}镜缺少画面描述`));
    }
    return Promise.resolve(`${index + 1}.${shot.videoDesc.trim()}`);
  })
).catch(err => `兜底:${err.message}`);

return Array.isArray(result) ? result.join('、') : result;
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
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_promise_all_rejected_runtime', const {
        'storyboards': [
          {'videoDesc': ' 雪落山门 '},
          {'videoDesc': ''},
          {'videoDesc': '主角回眸'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Promise all rejected 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_promise_all_rejected_runtime');
    expect(msg.content, '兜底:第2镜缺少画面描述');
  });

  test('自定义脚本技能：支持 Promise.allSettled 包裹同步批量结果', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_promise_all_settled_runtime',
      name: 'Promise allSettled 脚本运行时',
      description:
          '验证自定义技能兼容模型常写的 await Promise.allSettled(list.map(async (...) => ...)) 批量整理。',
      script: r'''
const settled = await Promise.allSettled(
  args.storyboards
    .filter(shot => !!shot.videoDesc?.trim())
    .map(async (shot, index) => {
      const desc = await shot.videoDesc.trim();
      return `${index + 1}.${desc}`;
    })
);

const labels = settled
  .filter(item => item.status === 'fulfilled')
  .map(item => item.value)
  .join('、');

return labels;
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
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_promise_all_settled_runtime', const {
        'storyboards': [
          {'videoDesc': ' 雪落山门 '},
          {'videoDesc': ''},
          {'videoDesc': '主角回眸'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Promise allSettled 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_promise_all_settled_runtime');
    expect(msg.content, '1.雪落山门、2.主角回眸');
  });

  test('自定义脚本技能：Promise.allSettled 保留 rejected 批量结果', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_promise_all_settled_rejected_runtime',
      name: 'Promise allSettled rejected 脚本运行时',
      description: '验证自定义技能兼容模型常写的 Promise.allSettled 混合成功/失败批量整理。',
      script: r'''
const settled = await Promise.allSettled(
  args.storyboards.map((shot, index) => {
    if (!shot.videoDesc?.trim()) {
      return Promise.reject(new Error(`第${index + 1}镜缺少画面描述`));
    }
    return Promise.resolve(`${index + 1}.${shot.videoDesc.trim()}`);
  })
);

const ok = settled
  .filter(item => item.status === 'fulfilled')
  .map(item => item.value)
  .join('、');
const failed = settled
  .filter(item => item.status === 'rejected')
  .map(item => item.reason.message)
  .join('、');

return JSON.stringify({ ok, failed });
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
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool(
        'custom_script_promise_all_settled_rejected_runtime',
        const {
          'storyboards': [
            {'videoDesc': ' 雪落山门 '},
            {'videoDesc': ''},
            {'videoDesc': '主角回眸'},
          ],
        },
      ),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Promise allSettled rejected 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_promise_all_settled_rejected_runtime');
    expect(jsonDecode(msg.content), {
      'ok': '1.雪落山门、3.主角回眸',
      'failed': '第2镜缺少画面描述',
    });
  });

  test('自定义脚本技能：Promise.allSettled 支持链式 then', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_promise_all_settled_then_runtime',
      name: 'Promise allSettled then 脚本运行时',
      description: '验证自定义技能兼容模型常写的 Promise.allSettled(...).then(...) 批量整理。',
      script: r'''
const label = await Promise.allSettled(
  args.storyboards.map((shot, index) => {
    if (!shot.videoDesc?.trim()) {
      return Promise.reject(new Error(`第${index + 1}镜缺少画面描述`));
    }
    return Promise.resolve(`${index + 1}.${shot.videoDesc.trim()}`);
  })
).then(results => {
  const ok = results
    .filter(item => item.status === 'fulfilled')
    .map(item => item.value)
    .join('、');
  const failed = results
    .filter(item => item.status === 'rejected')
    .map(item => item.reason.message)
    .join('、');
  return `${ok}|${failed}`;
});

return label;
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
              },
            },
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool(
        'custom_script_promise_all_settled_then_runtime',
        const {
          'storyboards': [
            {'videoDesc': ' 雪落山门 '},
            {'videoDesc': ''},
            {'videoDesc': '主角回眸'},
          ],
        },
      ),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Promise allSettled then 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_promise_all_settled_then_runtime');
    expect(msg.content, '1.雪落山门、3.主角回眸|第2镜缺少画面描述');
  });

  test('自定义脚本技能：支持 Promise.race 首个 settled 结果', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_promise_race_runtime',
      name: 'Promise race 脚本运行时',
      description: '验证自定义技能兼容模型常写的 Promise.race(...).then/catch 首个结果选择。',
      script: r'''
const firstOk = await Promise.race([
  Promise.resolve(args.candidates[0].trim()),
  Promise.resolve(args.candidates[1].trim()),
]).then(value => `首选:${value}`);

const firstFail = await Promise.race([
  Promise.reject(new Error(args.reason)),
  Promise.resolve('不会到这里'),
]).catch(err => `失败:${err.message}`);

return `${firstOk}|${firstFail}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'candidates': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'reason': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_promise_race_runtime', const {
        'candidates': [' 雪落山门 ', '主角回眸'],
        'reason': '首个候选缺少参考图',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Promise race 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_promise_race_runtime');
    expect(msg.content, '首选:雪落山门|失败:首个候选缺少参考图');
  });

  test('自定义脚本技能：支持 Promise.any 跳过失败候选', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_promise_any_runtime',
      name: 'Promise any 脚本运行时',
      description: '验证自定义技能兼容模型常写的 Promise.any(...) 候选兜底选择。',
      script: r'''
const label = await Promise.any([
  Promise.reject(new Error(args.missingReason)),
  Promise.resolve(args.candidates[0].trim()),
  Promise.resolve(args.candidates[1].trim()),
]);

return `可用:${label}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'missingReason': {'type': 'string'},
          'candidates': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_promise_any_runtime', const {
        'missingReason': '首张参考图缺失',
        'candidates': [' 雪落山门 ', '主角回眸'],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Promise any 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_promise_any_runtime');
    expect(msg.content, '可用:雪落山门');
  });

  test('自定义脚本技能：Promise.any 全失败时暴露 errors', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_promise_any_rejected_runtime',
      name: 'Promise any rejected 脚本运行时',
      description: '验证自定义技能兼容模型常写的 Promise.any(...).catch(err.errors) 失败汇总。',
      script: r'''
const fallback = await Promise.any([
  Promise.reject(new Error(args.reasons[0])),
  Promise.reject(new Error(args.reasons[1])),
]).catch(err => {
  const messages = err.errors.map(error => error.message).join('、');
  return `${err.name}|${err instanceof Error}|${messages}`;
});

return fallback;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'reasons': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_promise_any_rejected_runtime', const {
        'reasons': ['首图缺失', '备选图不合格'],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Promise any rejected 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_promise_any_rejected_runtime');
    expect(msg.content, 'AggregateError|true|首图缺失、备选图不合格');
  });

  test('自定义脚本技能：支持 Promise.resolve 后的同步 then 链', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_promise_then_runtime',
      name: 'Promise then 脚本运行时',
      description:
          '验证自定义技能兼容模型常写的 Promise.resolve(value).then(...).then(...) 纯数据整理。',
      script: r'''
const label = await Promise.resolve(args.title)
  .then(title => title.trim())
  .then(title => `${title}:${args.storyboards.length}`);

return label;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
          'storyboards': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_promise_then_runtime', const {
        'title': '  灵脉初醒  ',
        'storyboards': [
          {'videoDesc': '山门'},
          {'videoDesc': '拔剑'},
          {'videoDesc': '回眸'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Promise then 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_promise_then_runtime');
    expect(msg.content, '灵脉初醒:3');
  });

  test('自定义脚本技能：支持 Promise.reject catch 后继续 then 链', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_promise_catch_runtime',
      name: 'Promise catch 脚本运行时',
      description:
          '验证自定义技能兼容模型常写的 Promise.reject(...).catch(...).then(...) 容错整理。',
      script: r'''
const label = await Promise.reject(new Error(args.reason))
  .catch(err => `兜底:${err.message}`)
  .then(text => `${text}:${args.storyboards.length}`);

return label;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'reason': {'type': 'string'},
          'storyboards': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_promise_catch_runtime', const {
        'reason': '资产缺少参考图',
        'storyboards': [
          {'videoDesc': '山门'},
          {'videoDesc': '拔剑'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Promise catch 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_promise_catch_runtime');
    expect(msg.content, '兜底:资产缺少参考图:2');
  });

  test('自定义脚本技能：支持 Promise.finally 保留状态并执行清理', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_promise_finally_runtime',
      name: 'Promise finally 脚本运行时',
      description:
          '验证自定义技能兼容模型常写的 Promise.finally(...) 清理链，同时保留 fulfilled/rejected 状态。',
      script: r'''
const trace = [];

const ok = await Promise.resolve(args.title)
  .finally(() => trace.push('ok-cleanup'))
  .then(title => title.trim());

const fallback = await Promise.reject(new Error(args.reason))
  .finally(() => trace.push('fail-cleanup'))
  .catch(err => `兜底:${err.message}`);

return `${ok}|${fallback}|${trace.join(',')}`;
''',
      schema: const {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
          'reason': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_promise_finally_runtime', const {
        'title': '  灵脉初醒  ',
        'reason': '资产缺少参考图',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Promise finally 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_promise_finally_runtime');
    expect(msg.content, '灵脉初醒|兜底:资产缺少参考图|ok-cleanup,fail-cleanup');
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

  test('自定义脚本技能：支持 Number.isInteger 和 Number.isSafeInteger', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_number_integer_runtime',
      name: 'Number 整数判定脚本运行时',
      description: '验证自定义技能兼容模型常写的 Number.isInteger/isSafeInteger 校验镜头号和资产 id。',
      script: r'''
const shotNos = args.shots.map(shot => Number(shot.no));
const durations = args.shots.map(shot => Number.parseFloat(shot.duration));
return JSON.stringify({
  integerShotNos: shotNos.every(value => Number.isInteger(value)),
  integerDurations: durations.map(value => Number.isInteger(value)).join('|'),
  safeAssetId: Number.isSafeInteger(args.assetId),
  unsafeAssetId: Number.isSafeInteger(args.unsafeAssetId),
  safeFloat: Number.isSafeInteger(3.5),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'shots': {
            'type': 'array',
            'items': {'type': 'object'},
          },
          'assetId': {'type': 'number'},
          'unsafeAssetId': {'type': 'number'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_number_integer_runtime', const {
        'shots': [
          {'no': '1', 'duration': '3s'},
          {'no': 2, 'duration': '3.5s'},
        ],
        'assetId': 9007199254740991,
        'unsafeAssetId': 9007199254740992,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 Number 整数判定脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_number_integer_runtime');
    expect(jsonDecode(msg.content), {
      'integerShotNos': true,
      'integerDurations': 'true|false',
      'safeAssetId': true,
      'unsafeAssetId': false,
      'safeFloat': false,
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

  test('自定义脚本技能：支持正则 split 清洗文本和标签', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_regex_split_runtime',
      name: '正则拆分脚本运行时',
      description: r'验证自定义技能兼容模型常写的 split(/\r?\n+/) 和 split(/[，,]/)。',
      script: r'''
const lines = args.table
  .split(/\r?\n+/)
  .map(line => line.trim())
  .filter(Boolean);
const labels = lines.map((line, index) => {
  const [title, duration, track] = line.split(/[|｜]/).map(part => part.trim());
  return `${index + 1}.${title}:${parseFloat(duration)}:${track}`;
});
const tags = args.tags
  .split(/[，,]\s*/)
  .map(tag => tag.trim())
  .filter(Boolean)
  .join('|');
const preview = args.table
  .split(/\r?\n+/, 2)
  .map(line => line.trim())
  .join('>');
return JSON.stringify({ labels: labels.join('、'), tags, preview });
''',
      schema: const {
        'type': 'object',
        'properties': {
          'table': {'type': 'string'},
          'tags': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_regex_split_runtime', const {
        'table': '雪夜山门 | 3秒 | 首帧\n\n李澈拔剑｜2.5秒｜视频参考\n沈微回眸 | 1.5秒 | 尾帧',
        'tags': '角色，场景, 动作，',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用正则拆分脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_regex_split_runtime');
    expect(jsonDecode(msg.content), {
      'labels': '1.雪夜山门:3:首帧、2.李澈拔剑:2.5:视频参考、3.沈微回眸:1.5:尾帧',
      'tags': '角色|场景|动作',
      'preview': '雪夜山门 | 3秒 | 首帧>李澈拔剑｜2.5秒｜视频参考',
    });
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

  test('自定义脚本技能：支持 try catch finally 清理逻辑', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_try_catch_finally_runtime',
      name: 'try catch finally 脚本运行时',
      description: '验证自定义技能兼容模型常写的 finally 清理逻辑。',
      script: r'''
const log = [];

try {
  log.push('try');
  throw new Error(args.reason);
} catch (err) {
  log.push(`catch:${err.message}`);
} finally {
  log.push('finally');
}

return log.join('|');
''',
      schema: const {
        'type': 'object',
        'properties': {
          'reason': {'type': 'string'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_try_catch_finally_runtime', const {
        'reason': '资产解析失败',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 try catch finally 脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_try_catch_finally_runtime');
    expect(msg.content, 'try|catch:资产解析失败|finally');
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

  test('自定义脚本技能：支持 RegExp.exec 提取首个匹配分组', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_regex_exec_runtime',
      name: '正则首个匹配脚本运行时',
      description: '验证自定义技能兼容模型常写的 /.../.exec(text) 分镜解析。',
      script: r'''
const shot = /<storyboardItem\b[^>]*videoDesc="([^"]+)"[^>]*duration="([^"]+)"/.exec(args.workspace);
const sound = /sound="([^"]+)"/.exec(args.workspace);
return JSON.stringify({
  found: Boolean(shot),
  desc: shot ? shot[1].trim() : '',
  duration: shot ? shot[2] : '',
  sound: sound ? sound[1] : 'none',
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
      AgentTurnResult.tool('custom_script_regex_exec_runtime', const {
        'workspace':
            '<storyboardItem videoDesc=" 雪夜山门 " duration="3秒"></storyboardItem>',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用正则首个匹配脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_regex_exec_runtime');
    expect(jsonDecode(msg.content), {
      'found': true,
      'desc': '雪夜山门',
      'duration': '3秒',
      'sound': 'none',
    });
  });

  test('自定义脚本技能：支持全局 RegExp.exec lastIndex 循环提取', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_regex_exec_global_runtime',
      name: '全局正则循环脚本运行时',
      description: '验证自定义技能兼容模型常写的 while ((m = re.exec(text)) !== null)。',
      script: r'''
const pattern = /<storyboardItem\b[^>]*videoDesc="([^"]+)"[^>]*duration="([^"]+)"/g;
let match = null;
const shots = [];
while ((match = pattern.exec(args.workspace)) !== null) {
  shots.push(`${shots.length + 1}.${match[1].trim()}@${match[2]}`);
}
const afterLoop = pattern.lastIndex;
pattern.lastIndex = 0;
const firstAgain = pattern.exec(args.workspace);
return JSON.stringify({
  shots,
  afterLoop,
  firstAgain: firstAgain ? firstAgain[1].trim() : '',
  afterFirstAgain: pattern.lastIndex,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'workspace': {'type': 'string'},
        },
      },
    );

    const workspace = '''
<storyboardItem videoDesc=" 雪夜山门 " duration="3秒"></storyboardItem>
<storyboardItem videoDesc="李澈拔剑" duration="2.5s"></storyboardItem>
''';
    final expectedAfterFirstAgain = RegExp(
      r'<storyboardItem\b[^>]*videoDesc="([^"]+)"[^>]*duration="([^"]+)"',
    ).firstMatch(workspace)!.end;
    gateway.turns = [
      AgentTurnResult.tool('custom_script_regex_exec_global_runtime', const {
        'workspace': workspace,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用全局正则循环脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_regex_exec_global_runtime');
    expect(jsonDecode(msg.content), {
      'shots': ['1.雪夜山门@3秒', '2.李澈拔剑@2.5s'],
      'afterLoop': 0,
      'firstAgain': '雪夜山门',
      'afterFirstAgain': expectedAfterFirstAgain,
    });
  });

  test('自定义脚本技能：支持正则匹配结果 index 和 input 元数据', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_regex_match_metadata_runtime',
      name: '正则匹配元数据脚本运行时',
      description: '验证自定义技能兼容模型常写的 match.index 和 match.input。',
      script: r'''
const first = args.workspace.match(/<storyboardItem\b[^>]*videoDesc="([^"]+)"/);
const all = [...args.workspace.matchAll(/<storyboardItem\b[^>]*videoDesc="([^"]+)"/g)];
const exec = /duration="([^"]+)"/.exec(args.workspace);
return JSON.stringify({
  firstIndex: first.index,
  firstInputSame: first.input === args.workspace,
  firstDesc: first[1].trim(),
  allIndexes: all.map(match => match.index),
  allInputSame: all.every(match => match.input === args.workspace),
  execIndex: exec.index,
  execDuration: exec[1],
  execInputSame: exec.input === args.workspace,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'workspace': {'type': 'string'},
        },
      },
    );

    const workspace = '''
<scriptPlan>寒山宗门外，雪夜开场。</scriptPlan>
<storyboardItem videoDesc=" 雪夜山门 " duration="3秒"></storyboardItem>
<storyboardItem videoDesc="李澈拔剑" duration="2.5s"></storyboardItem>
''';
    final itemPattern = RegExp(r'<storyboardItem\b[^>]*videoDesc="([^"]+)"');
    final durationPattern = RegExp(r'duration="([^"]+)"');
    gateway.turns = [
      AgentTurnResult.tool('custom_script_regex_match_metadata_runtime', const {
        'workspace': workspace,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用正则匹配元数据脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_regex_match_metadata_runtime');
    expect(jsonDecode(msg.content), {
      'firstIndex': itemPattern.firstMatch(workspace)!.start,
      'firstInputSame': true,
      'firstDesc': '雪夜山门',
      'allIndexes': [
        for (final match in itemPattern.allMatches(workspace)) match.start,
      ],
      'allInputSame': true,
      'execIndex': durationPattern.firstMatch(workspace)!.start,
      'execDuration': '3秒',
      'execInputSame': true,
    });
  });

  test('自定义脚本技能：支持正则命名捕获 groups 元数据', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_regex_named_groups_runtime',
      name: '正则命名分组脚本运行时',
      description: '验证自定义技能兼容模型常写的 match.groups.desc。',
      script: r'''
const first = args.workspace.match(/<storyboardItem\b[^>]*videoDesc="(?<desc>[^"]+)"[^>]*duration="(?<duration>[^"]+)"/);
const exec = /track="(?<track>[^"]+)"/.exec(args.workspace);
return JSON.stringify({
  desc: first.groups.desc.trim(),
  duration: first.groups['duration'],
  groupKeys: Object.keys(first.groups).sort().join('|'),
  groupValues: Object.values(first.groups).map(value => value.trim()).join('|'),
  track: exec.groups.track,
  missingGroups: /sound="([^"]+)"/.exec(args.workspace)?.groups ?? null,
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
      AgentTurnResult.tool('custom_script_regex_named_groups_runtime', const {
        'workspace':
            '<storyboardItem videoDesc=" 雪夜山门 " duration="3秒" track="首帧"></storyboardItem>',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用正则命名分组脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_regex_named_groups_runtime');
    expect(jsonDecode(msg.content), {
      'desc': '雪夜山门',
      'duration': '3秒',
      'groupKeys': 'desc|duration',
      'groupValues': '雪夜山门|3秒',
      'track': '首帧',
      'missingGroups': null,
    });
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

  test('自定义脚本技能：支持全局 RegExp.test 推进 lastIndex', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_regexp_test_global_runtime',
      name: '全局正则 test 脚本运行时',
      description: '验证自定义技能兼容模型常写的 while (re.test(text)) 循环。',
      script: r'''
const re = /<storyboardItem\b[^>]*videoDesc="([^"]+)"/g;
const names = [];
while (re.test(args.workspace)) {
  if (re.lastIndex <= 0 || names.length > 5) {
    throw new Error('RegExp.test did not advance');
  }
  const desc = args.workspace
    .slice(0, re.lastIndex)
    .match(/videoDesc="([^"]+)"/g)
    .at(-1)
    .replace(/videoDesc="|"/g, '')
    .trim();
  names.push(desc);
}
const afterLoop = re.lastIndex;
const firstAgain = re.test(args.workspace);
return JSON.stringify({
  names,
  afterLoop,
  firstAgain,
  afterFirst: re.lastIndex,
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
      AgentTurnResult.tool('custom_script_regexp_test_global_runtime', const {
        'workspace': '''
<storyboardItem videoDesc="雪夜山门"></storyboardItem>
<storyboardItem videoDesc="李澈拔剑"></storyboardItem>
''',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用全局正则 test 脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_regexp_test_global_runtime');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['names'], ['雪夜山门', '李澈拔剑']);
    expect(payload['afterLoop'], 0);
    expect(payload['firstAgain'], true);
    expect(payload['afterFirst'], greaterThan(0));
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

  test('自定义脚本技能：支持正则 replace 的命名分组替换', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_regex_replace_named_groups_runtime',
      name: '正则命名分组替换脚本运行时',
      description: r'验证自定义技能兼容模型常写的 replace(/.../, "$<name>")。',
      script: r'''
const compact = args.workspace
  .replace(/<storyboardItem\b[^>]*videoDesc="(?<desc>[^"]+)"[^>]*duration="(?<duration>[^"]+)"[^>]*><\/storyboardItem>/g, '$<desc>@$<duration>')
  .replace(/\s+/g, ' ')
  .trim();
const labeled = args.title.replace(/^(?<title>.*)$/,'《$<title>》');
return JSON.stringify({ compact, labeled });
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
          'custom_script_regex_replace_named_groups_runtime', const {
        'workspace': '''
<storyboardItem videoDesc="雪夜山门" duration="3秒"></storyboardItem>
<storyboardItem videoDesc="李澈拔剑" duration="2.5s"></storyboardItem>
''',
        'title': '雪夜开场',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用正则命名分组替换脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_regex_replace_named_groups_runtime');
    expect(jsonDecode(msg.content), {
      'compact': '雪夜山门@3秒 李澈拔剑@2.5s',
      'labeled': '《雪夜开场》',
    });
  });

  test('自定义脚本技能：支持正则 replace 回调读取命名分组', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_regex_replace_callback_groups_runtime',
      name: '正则回调命名分组脚本运行时',
      description: '验证自定义技能兼容模型常写的 replace 回调 groups 参数。',
      script: r'''
const compact = args.workspace
  .replace(/<storyboardItem\b[^>]*videoDesc="(?<desc>[^"]+)"[^>]*duration="(?<duration>[^"]+)"[^>]*><\/storyboardItem>/g,
    (match, desc, duration, offset, source, groups) =>
      `${groups.desc.trim()}@${groups.duration}@${Object.keys(groups).sort().join('|')}`)
  .replace(/\s+/g, ' ')
  .trim();
const marked = args.title.replace(/^(?<title>.*)$/, function(match, title, offset, source, groups) {
  return `《${groups.title.trim()}》`;
});
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
          'custom_script_regex_replace_callback_groups_runtime', const {
        'workspace': '''
<storyboardItem videoDesc=" 雪夜山门 " duration="3秒"></storyboardItem>
<storyboardItem videoDesc="李澈拔剑" duration="2.5s"></storyboardItem>
''',
        'title': ' 雪夜开场 ',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用正则回调命名分组脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(
      msg.toolName,
      'custom_script_regex_replace_callback_groups_runtime',
    );
    expect(jsonDecode(msg.content), {
      'compact': '雪夜山门@3秒@desc|duration 李澈拔剑@2.5s@desc|duration',
      'marked': '《雪夜开场》',
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

  test('自定义脚本技能：支持 findLast 和 findLastIndex 定位最后可用参考图', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_find_last_runtime',
      name: '倒序查找脚本运行时',
      description: '验证自定义技能兼容模型常写的 findLast/findLastIndex 最后可用参考图选择。',
      script: r'''
const refs = args.references;
const lastImage = refs.findLast(ref => ref.type === 'image' && ref.enabled !== false);
const lastImageIndex = refs.findLastIndex(ref => ref.type === 'image' && ref.enabled !== false);
const sourceChecked = refs.findLast((ref, index, source) =>
  source.length === refs.length && index < source.length && ref.type === 'scene'
);
const missingAudio = refs.findLast(ref => ref.type === 'audio');
return JSON.stringify({
  lastImageName: lastImage.name.trim(),
  lastImageIndex: lastImageIndex,
  sourceCheckedName: sourceChecked.name.trim(),
  missingAudioIsNull: missingAudio === null,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'references': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_find_last_runtime', const {
        'references': [
          {'type': 'image', 'name': ' 首帧 ', 'enabled': true},
          {'type': 'scene', 'name': ' 寒山宗门 ', 'enabled': true},
          {'type': 'image', 'name': '废弃参考', 'enabled': false},
          {'type': 'image', 'name': ' 尾帧 ', 'enabled': true},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用倒序查找脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_find_last_runtime');
    expect(jsonDecode(msg.content), {
      'lastImageName': '尾帧',
      'lastImageIndex': 3,
      'sourceCheckedName': '寒山宗门',
      'missingAudioIsNull': true,
    });
  });

  test('自定义脚本技能：支持 toSorted 和 toReversed 的非原地数组语义', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_copy_sort_reverse_runtime',
      name: '非原地排序反转脚本运行时',
      description: '验证自定义技能兼容模型常写的 toSorted/toReversed，且不改变原数组。',
      script: r'''
const assets = args.assets;
const sorted = assets.toSorted((a, b) => b.priority - a.priority);
const reversedSteps = args.steps.toReversed();
return JSON.stringify({
  originalAssets: assets.map(asset => asset.name.trim()).join('>'),
  sortedAssets: sorted.map(asset => asset.name.trim()).join('>'),
  originalSteps: args.steps.join('>'),
  reversedSteps: reversedSteps.join('>'),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'assets': {
            'type': 'array',
            'items': {'type': 'object'},
          },
          'steps': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_copy_sort_reverse_runtime', const {
        'assets': [
          {'name': ' 李澈 ', 'priority': 20},
          {'name': '寒山宗门', 'priority': 10},
          {'name': '沈微', 'priority': 30},
        ],
        'steps': ['构图', '首帧', '视频'],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用非原地排序反转脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_copy_sort_reverse_runtime');
    expect(jsonDecode(msg.content), {
      'originalAssets': '李澈>寒山宗门>沈微',
      'sortedAssets': '沈微>李澈>寒山宗门',
      'originalSteps': '构图>首帧>视频',
      'reversedSteps': '视频>首帧>构图',
    });
  });

  test('自定义脚本技能：支持 toSpliced 和 with 的非原地数组更新', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_copy_update_runtime',
      name: '非原地数组更新脚本运行时',
      description: '验证自定义技能兼容模型常写的 toSpliced/with，便于派生分镜和参考图列表。',
      script: r'''
const refs = args.references;
const inserted = refs.toSpliced(1, 1, { id: 'R2b', name: ' 修正版中景 ' });
const patched = refs.with(-1, { id: 'R9', name: ' 替换尾帧 ' });
return JSON.stringify({
  original: refs.map(ref => ref.id).join('>'),
  inserted: inserted.map(ref => `${ref.id}:${ref.name.trim()}`).join('>'),
  patched: patched.map(ref => `${ref.id}:${ref.name.trim()}`).join('>'),
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'references': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_copy_update_runtime', const {
        'references': [
          {'id': 'R1', 'name': ' 首帧 '},
          {'id': 'R2', 'name': '中景'},
          {'id': 'R3', 'name': '尾帧'},
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用非原地数组更新脚本运行时技能',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_copy_update_runtime');
    expect(jsonDecode(msg.content), {
      'original': 'R1>R2>R3',
      'inserted': 'R1:首帧>R2b:修正版中景>R3:尾帧',
      'patched': 'R1:首帧>R2:中景>R9:替换尾帧',
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

  test('自定义脚本技能：支持 typeof 类型保护', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_typeof_runtime',
      name: 'typeof 类型保护脚本运行时',
      description: '验证自定义技能兼容模型常写的 typeof value === "string" 类型保护。',
      script: r'''
function normalizeName(value) {
  if (typeof value === 'string') {
    return value.trim();
  }
  if (typeof value === 'number') {
    return `#${value}`;
  }
  if (typeof value === 'boolean') {
    return value ? '是' : '否';
  }
  return '对象';
}
const labels = args.assets
  .map(asset => `${normalizeName(asset.name)}:${typeof asset.meta}`)
  .join('|');
return JSON.stringify({
  labels,
  missing: typeof notDeclared,
  nil: typeof null,
  helper: typeof normalizeName,
  assets: typeof args.assets,
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
      AgentTurnResult.tool('custom_script_typeof_runtime', const {
        'assets': [
          {
            'name': ' 李澈 ',
            'meta': {'role': 'hero'},
          },
          {
            'name': 7,
            'meta': ['scene'],
          },
          {
            'name': true,
            'meta': null,
          },
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 typeof 类型保护脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_typeof_runtime');
    expect(jsonDecode(msg.content), {
      'labels': '李澈:object|#7:object|是:object',
      'missing': 'undefined',
      'nil': 'object',
      'helper': 'function',
      'assets': 'object',
    });
  });

  test('自定义脚本技能：支持 instanceof 类型分支', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_instanceof_runtime',
      name: 'instanceof 类型分支脚本运行时',
      description: '验证自定义技能兼容模型常写的 value instanceof Array/Date/Map/Set/Error。',
      script: r'''
const startedAt = new Date(args.startedAt);
const assetMap = new Map(Object.entries(args.assetsById));
const selected = new Set(args.selectedIds);
function helper() {
  return 'ok';
}
let caught = null;
try {
  throw new Error('bad storyboard payload');
} catch (error) {
  caught = error;
}
return JSON.stringify({
  assetsIsArray: args.assets instanceof Array,
  startedAtIsDate: startedAt instanceof Date,
  mapIsMap: assetMap instanceof Map,
  selectedIsSet: selected instanceof Set,
  caughtIsError: caught instanceof Error,
  plainObjectIsObject: args.assetsById instanceof Object,
  stringIsStringObject: args.assets[0].name instanceof String,
  helperIsFunction: helper instanceof Function,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'startedAt': {'type': 'integer'},
          'selectedIds': {
            'type': 'array',
            'items': {'type': 'number'},
          },
          'assets': {
            'type': 'array',
            'items': {'type': 'object'},
          },
          'assetsById': {'type': 'object'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool('custom_script_instanceof_runtime', const {
        'startedAt': 1704067200000,
        'selectedIds': [1, 2],
        'assets': [
          {'name': '李澈'},
        ],
        'assetsById': {
          'A001': {'name': '李澈'},
        },
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用 instanceof 类型分支脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_instanceof_runtime');
    expect(jsonDecode(msg.content), {
      'assetsIsArray': true,
      'startedAtIsDate': true,
      'mapIsMap': true,
      'selectedIsSet': true,
      'caughtIsError': true,
      'plainObjectIsObject': true,
      'stringIsStringObject': false,
      'helperIsFunction': true,
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

  test('自定义脚本技能：支持普通变量逻辑赋值', () async {
    engine.saveCustomAgentSkill(
      id: 'custom_script_variable_logical_assignment_runtime',
      name: '变量逻辑赋值脚本运行时',
      description: '验证自定义技能兼容模型常写的 name ||= fallback 和 value ??= fallback。',
      script: r'''
let name = args.name.trim();
name ||= '未命名';
let prompt = args.prompt;
prompt ??= `${name}:默认提示词`;
let caption = args.caption;
caption ??= '备用字幕';
let publish = args.publish;
publish &&= args.allowPublish;
let zero = 0;
zero ||= 7;
let existing = '已有';
existing &&= `${existing}-通过`;
return JSON.stringify({
  name,
  prompt,
  caption,
  publish,
  zero,
  existing,
});
''',
      schema: const {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'prompt': {'type': 'string'},
          'caption': {'type': 'string'},
          'publish': {'type': 'boolean'},
          'allowPublish': {'type': 'boolean'},
        },
      },
    );

    gateway.turns = [
      AgentTurnResult.tool(
        'custom_script_variable_logical_assignment_runtime',
        const {
          'name': '   ',
          'prompt': null,
          'caption': '',
          'publish': true,
          'allowPublish': false,
        },
      ),
    ];

    await engine.sendAgentMessage(
      projectId,
      '调用变量逻辑赋值脚本运行时技能',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'custom_script_variable_logical_assignment_runtime');
    expect(msg.content, isNot(startsWith('执行失败')));
    expect(jsonDecode(msg.content), {
      'name': '未命名',
      'prompt': '未命名:默认提示词',
      'caption': '',
      'publish': false,
      'zero': 7,
      'existing': '已有-通过',
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

  test('SkillRuntime read_skill_file schema lists stage-visible skill aliases',
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

    var readTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'read_skill_file');
    var properties =
        Map<String, dynamic>.from(readTool.schema['properties'] as Map);
    for (final key in ['name', 'skill', 'skillName', 'skillId', 'skill_name']) {
      final schema = Map<String, dynamic>.from(properties[key] as Map);
      expect(schema['enum'], ['style_polisher']);
    }
    expect(readTool.description, contains('style_polisher'));
    expect(readTool.description, isNot(contains('director_checker')));

    gateway.turns = [const AgentTurnResult.text('制作规划已记录。')];
    await engine.sendAgentMessage(
      projectId,
      '制作导演计划',
      autoMode: false,
      family: agentFamilyProduction,
    );

    readTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'read_skill_file');
    properties =
        Map<String, dynamic>.from(readTool.schema['properties'] as Map);
    for (final key in ['name', 'skill', 'skillName', 'skillId', 'skill_name']) {
      final schema = Map<String, dynamic>.from(properties[key] as Map);
      expect(schema['enum'], ['director_checker']);
    }
    expect(readTool.description, contains('director_checker'));
    expect(readTool.description, isNot(contains('style_polisher')));
  });

  test('SkillRuntime read_skill_file schema lists stage-visible resource files',
      () async {
    final scriptSkillFile = _writeSkillFixture(
      dir,
      id: 'style_polisher',
      body: '剧本技能正文。',
      extraFiles: {
        'references/rules.md': '文风规则。',
        'references/tone.md': '语气规则。',
      },
    );
    final productionSkillFile = _writeSkillFixture(
      dir,
      id: 'director_checker',
      body: '制作技能正文。',
      extraFiles: {
        'references/lens.md': '镜头规则。',
      },
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

    var readTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'read_skill_file');
    var properties =
        Map<String, dynamic>.from(readTool.schema['properties'] as Map);
    for (final key in [
      'filePath',
      'path',
      'file',
      'filename',
      'relativePath'
    ]) {
      final schema = Map<String, dynamic>.from(properties[key] as Map);
      expect(schema['enum'], ['references/rules.md', 'references/tone.md']);
    }
    expect(readTool.description, contains('references/rules.md'));
    expect(readTool.description, isNot(contains('references/lens.md')));

    gateway.turns = [const AgentTurnResult.text('制作规划已记录。')];
    await engine.sendAgentMessage(
      projectId,
      '制作导演计划',
      autoMode: false,
      family: agentFamilyProduction,
    );

    readTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'read_skill_file');
    properties =
        Map<String, dynamic>.from(readTool.schema['properties'] as Map);
    for (final key in [
      'filePath',
      'path',
      'file',
      'filename',
      'relativePath'
    ]) {
      final schema = Map<String, dynamic>.from(properties[key] as Map);
      expect(schema['enum'], ['references/lens.md']);
    }
    expect(readTool.description, contains('references/lens.md'));
    expect(readTool.description, isNot(contains('references/rules.md')));
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

  test('SkillRuntime activate_skill 支持模型常见技能名称别名', () async {
    final skillFile = _writeSkillFixture(
      dir,
      id: 'style_polisher',
      body: '技能正文：短剧台词要短。',
    );
    engine.saveMarkdownAgentSkill(filePath: skillFile.path);

    gateway.turns = [
      AgentTurnResult.tool('activate_skill', const {'skill': 'style_polisher'}),
    ];

    await engine.sendAgentMessage(projectId, '用技能润色剧本', autoMode: false);

    final activateSkillTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'activate_skill');
    final properties = activateSkillTool.schema['properties'] as Map;
    expect(properties, contains('skill'));
    expect(properties, contains('skillName'));
    expect(properties, contains('skillId'));
    expect(properties, contains('skill_name'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.toolName, 'activate_skill');
    expect(msg.content, startsWith('<skill_content name="style_polisher">'));
    expect(msg.content, contains('技能正文：短剧台词要短。'));
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

  test('SkillRuntime read_skill_file 支持模型常见技能名称别名', () async {
    final styleSkill = _writeSkillFixture(
      dir,
      id: 'style_polisher',
      body: '技能正文：短剧台词要短。',
      extraFiles: {
        'references/rules.md': '文风规则：每句台词不超过二十字。',
      },
    );
    final dialogueSkill = _writeSkillFixture(
      dir,
      id: 'dialogue_checker',
      body: '技能正文：检查台词潜台词。',
      extraFiles: {
        'references/rules.md': '台词规则：每句都要带人物意图。',
      },
    );
    engine
      ..saveMarkdownAgentSkill(filePath: styleSkill.path)
      ..saveMarkdownAgentSkill(filePath: dialogueSkill.path);

    gateway.turns = [
      AgentTurnResult.tool('activate_skill', const {'name': 'style_polisher'}),
      AgentTurnResult.tool(
        'activate_skill',
        const {'name': 'dialogue_checker'},
      ),
      AgentTurnResult.tool('read_skill_file', const {
        'skill': 'dialogue_checker',
        'file': 'references/rules.md',
      }),
    ];

    await engine.sendAgentMessage(projectId, '读取台词技能规则', autoMode: true);

    final read = engine.agentMessages(projectId).lastWhere(
          (message) => message.toolName == 'read_skill_file',
        );
    expect(read.content, contains('台词规则：每句都要带人物意图。'));
    expect(read.content, isNot(contains('文风规则')));

    final readSkillFileTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'read_skill_file');
    final properties = readSkillFileTool.schema['properties'] as Map;
    expect(properties, contains('skill'));
    expect(properties, contains('skillId'));
    expect(properties, contains('skill_name'));
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

  test('长期记忆：system prompt 注入模型重排理由', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.rerankEnabled', '1'],
    );
    final keepId = engine.saveAgentMemory(
      projectId,
      id: 'prompt_note_rerank_keep',
      name: '角色底线',
      content: '长期设定：用户明确要求李澈保持正派，不能写成反派。',
    );
    engine.saveAgentMemory(
      projectId,
      id: 'prompt_note_rerank_noise',
      name: '山门匾额',
      content: '长期噪声：李澈正派 李澈正派 李澈正派 是山门匾额文案，不是角色底线。',
    );
    gateway.textResults = const [
      TextResult(
        '[{"memory_id":"prompt_note_rerank_keep","reason":"长期设定直接约束角色立场"}]',
      ),
    ];
    gateway.turns = [const AgentTurnResult.text('收到')];

    await engine.sendAgentMessage(projectId, '继续写李澈正派线', autoMode: false);

    expect(gateway.textCallCount, 1);
    expect(gateway.textStages, ['scriptAgent:decisionAgent']);
    expect(gateway.lastSystem, contains('<note id="$keepId"'));
    expect(gateway.lastSystem, contains('matchedTokens="李澈,正派"'));
    expect(
      gateway.lastSystem,
      contains('relevanceReason="长期设定直接约束角色立场"'),
    );
    expect(gateway.lastSystem, isNot(contains('prompt_note_rerank_noise')));
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

  test('长期记忆：minScore 设置会过滤弱相关 note', () async {
    final keepId = engine.saveAgentMemory(
      projectId,
      name: '角色约束',
      content: '用户明确要求：李澈正派设定必须保留，不能反派化。',
    );
    engine.saveAgentMemory(
      projectId,
      name: '角色出身',
      content: '用户补充：李澈来自寒山宗门。',
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.minScore', '80'],
    );

    final matched = await engine.searchAgentMemories(
      projectId,
      '李澈正派设定',
      limit: 5,
    );

    expect(matched.map((item) => item.id), [keepId]);
    expect(matched.single.score, greaterThanOrEqualTo(80));
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

  test('长期记忆：外部 embedding 保留小数向量精度用于相似度排序', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['binding.agent_embedding', 'fake:embed'],
    );
    final keepId = engine.saveAgentMemory(
      projectId,
      name: 'Tiny Vector Keep',
      content: '保留微弱相似度的真实向量召回规则。',
    );
    engine.saveAgentMemory(
      projectId,
      name: 'Tiny Vector Noise',
      content: '正交噪声向量，不应该被细粒度查询召回。',
    );
    gateway.embeddingForText = (input) {
      if (input.contains('细粒度向量查询')) return const [0.0000004, 0];
      if (input.contains('保留微弱相似度')) return const [0.00000039, 0];
      if (input.contains('正交噪声向量')) return const [0, 0.0000004];
      return const [0, 0];
    };

    final matched = await engine.searchAgentMemories(
      projectId,
      '细粒度向量查询',
      limit: 1,
    );

    expect(matched.map((item) => item.id), [keepId]);
    final stored = db.select('SELECT embedding FROM memories WHERE id=?',
        [keepId]).single['embedding'] as String;
    final decoded = jsonDecode(stored) as Map<String, dynamic>;
    expect(decoded['__gateway_embedding_v1'], 1);
    expect(decoded['vector'], isA<List>());
    expect((decoded['vector'] as List).first, closeTo(0.00000039, 1e-12));
  });

  test('长期记忆：外部 embedding 回填同步写入向量索引并随记忆删除', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['binding.agent_embedding', 'fake:embed'],
    );
    final memoryId = engine.saveAgentMemory(
      projectId,
      name: 'Vector Index',
      content: '向量索引记忆用于后续真实 RAG 检索。',
    );
    gateway.embeddingForText = (input) {
      if (input.contains('向量索引')) return const [0.25, -0.5, 0.75];
      return const [0, 0, 0];
    };

    final matched = await engine.searchAgentMemories(
      projectId,
      '向量索引',
      limit: 1,
    );

    expect(matched.map((item) => item.id), [memoryId]);
    final rows = db.select(
      'SELECT memoryId,isolationKey,type,provider,model,dimension,vector '
      'FROM o_memoryVector WHERE memoryId=?',
      [memoryId],
    );
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row['isolationKey'], 'project:$projectId');
    expect(row['type'], agentMemoryTypeNote);
    expect(row['provider'], 'gateway');
    expect(row['model'], 'agent_embedding');
    expect(row['dimension'], 3);
    expect(jsonDecode(row['vector'] as String), [0.25, -0.5, 0.75]);

    engine.deleteAgentMemory(projectId, memoryId);

    expect(
      db.select(
          'SELECT memoryId FROM o_memoryVector WHERE memoryId=?', [memoryId]),
      isEmpty,
    );
  });

  test('长期记忆：RAG 可直接使用 o_memoryVector 索引避免逐条远程回填', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['binding.agent_embedding', 'fake:embed'],
    );
    final keepId = engine.saveAgentMemory(
      projectId,
      name: 'Indexed Keep',
      content: '索引命中：李澈必须保护沈微。',
    );
    final noiseId = engine.saveAgentMemory(
      projectId,
      name: 'Indexed Noise',
      content: '索引噪声：山门远景和云雾。',
    );
    db.execute(
      'UPDATE memories SET embedding=? WHERE id IN (?,?)',
      ['', keepId, noiseId],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final item in [
      (keepId, [1.0, 0.0]),
      (noiseId, [0.0, 1.0]),
    ]) {
      db.execute(
        'INSERT OR REPLACE INTO o_memoryVector '
        '(memoryId,isolationKey,type,provider,model,dimension,vector,updatedAt) '
        'VALUES (?,?,?,?,?,?,?,?)',
        [
          item.$1,
          'project:$projectId',
          agentMemoryTypeNote,
          'gateway',
          'agent_embedding',
          item.$2.length,
          jsonEncode(item.$2),
          now,
        ],
      );
    }
    gateway.embeddingForText = (input) {
      if (input.contains('保护沈微')) return const [1, 0];
      return const [0, 1];
    };

    final matched = await engine.searchAgentMemories(
      projectId,
      '保护沈微',
      limit: 1,
    );

    expect(matched.map((item) => item.id), [keepId]);
    expect(gateway.embeddingInputs, ['保护沈微']);
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

  test('Agent 记忆：memory_get 工具返回普通 RAG 上下文', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    void insertMemory({
      required String id,
      required String content,
      required int offset,
      required String type,
      String name = '',
      String role = agentRoleAssistant,
      int summarized = 0,
      List<String> relatedMessageIds = const [],
    }) {
      db.execute(
        'INSERT INTO memories '
        '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          name,
          content,
          now + offset,
          embeddingJson(content),
          'scriptAgent:$projectId',
          jsonEncode(relatedMessageIds),
          role,
          summarized,
          type,
        ],
      );
    }

    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.summaryLimit', '1'],
    );
    insertMemory(
      id: 'memory_get_msg',
      content: '用户明确要求：李澈正派设定必须保留，不能反派化。',
      offset: 0,
      type: 'message',
      role: agentRoleUser,
      summarized: 1,
    );
    insertMemory(
      id: 'memory_get_summary',
      name: '寒山线摘要',
      content: '寒山线已经确认李澈是正派角色，外冷内热。',
      offset: 1,
      type: 'summary',
      relatedMessageIds: const ['memory_get_msg'],
    );
    insertMemory(
      id: 'memory_get_recent',
      content: '用户刚刚补充沈微要和李澈同行入山。',
      offset: 2,
      type: 'message',
      role: agentRoleUser,
    );
    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'query': '李澈正派设定',
        'limit': 1,
      }),
    ];

    await engine.sendAgentMessage(projectId, '按普通记忆找李澈设定', autoMode: false);

    final tool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final properties = tool.schema['properties'] as Map;
    expect(properties, contains('query'));
    expect(properties, contains('limit'));
    expect(properties, contains('minScore'));
    expect(properties, contains('excludeMemoryIds'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'memory_get');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], ['用户明确要求：李澈正派设定必须保留，不能反派化。']);
    expect(payload['summaries'], ['寒山线已经确认李澈是正派角色，外冷内热。']);
    expect(payload['recent'], ['用户刚刚补充沈微要和李澈同行入山。']);
    final records = payload['records'] as List;
    expect(
      records,
      contains(
        isA<Map>()
            .having((record) => record['id'], 'id', 'memory_get_msg')
            .having((record) => record['scope'], 'scope', 'conversation')
            .having((record) => record['content'], 'content',
                contains('李澈正派设定必须保留')),
      ),
    );
    expect(
      records,
      contains(
        isA<Map>()
            .having((record) => record['id'], 'id', 'memory_get_summary')
            .having((record) => record['scope'], 'scope', 'summary'),
      ),
    );
    expect(
      records,
      contains(
        isA<Map>()
            .having((record) => record['id'], 'id', 'memory_get_recent')
            .having((record) => record['scope'], 'scope', 'conversation'),
      ),
    );
  });

  test('Agent 记忆：memory_get 顶层数量限制会限制摘要结果', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.summaryLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '0'],
    );

    void insertSummary({
      required String id,
      required String content,
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
          agentRoleAssistant,
          0,
          agentMemoryTypeSummary,
        ],
      );
    }

    insertSummary(
      id: 'memory_get_summary_limit_old',
      content: '旧摘要：星岚设定第一次记录，角色要隐藏身份。',
      offset: 1,
    );
    insertSummary(
      id: 'memory_get_summary_limit_new',
      content: '新摘要：星岚设定第二次记录，角色要主动救人。',
      offset: 2,
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'query': '星岚设定',
        'scope': 'summary',
        'limit': 1,
        'orderBy': 'latest',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只取一条最新星岚摘要',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'memory_get');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['summaries'], ['新摘要：星岚设定第二次记录，角色要主动救人。']);
    expect(
      (payload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['memory_get_summary_limit_new'],
    );
  });

  test('Agent 记忆：memory_get 顶层数量限制会限制近期对话结果', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.summaryLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertRecent({
      required String id,
      required String content,
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
          agentRoleUser,
          0,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertRecent(
      id: 'memory_get_recent_limit_old',
      content: '旧近期：星桥设定第一次记录，保留雾夜入场。',
      offset: 1,
    );
    insertRecent(
      id: 'memory_get_recent_limit_new',
      content: '新近期：星桥设定第二次记录，改成雨夜救人。',
      offset: 2,
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'query': '星桥设定',
        'limit': 1,
        'orderBy': 'latest',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只取一条最新星桥近期对话',
      autoMode: false,
      family: agentFamilyScript,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'memory_get');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], isEmpty);
    expect(payload['recent'], ['新近期：星桥设定第二次记录，改成雨夜救人。']);
    expect(
      (payload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['memory_get_recent_limit_new'],
    );
  });

  test('Agent 记忆：memory_get 工具支持 roles 只返回指定角色上下文', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    void insertMemory({
      required String id,
      required String content,
      required int offset,
      required String type,
      required String role,
      String name = '',
      int summarized = 0,
      List<String> relatedMessageIds = const [],
    }) {
      db.execute(
        'INSERT INTO memories '
        '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          name,
          content,
          now + offset,
          embeddingJson(content),
          'scriptAgent:$projectId',
          jsonEncode(relatedMessageIds),
          role,
          summarized,
          type,
        ],
      );
    }

    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.summaryLimit', '4'],
    );
    insertMemory(
      id: 'memory_get_role_user_msg',
      content: '用户提到李澈来自寒山宗门。',
      offset: 0,
      type: 'message',
      role: agentRoleUser,
      summarized: 1,
    );
    insertMemory(
      id: 'memory_get_role_assistant_msg',
      content: '助手确认李澈必须救沈微，保持正派立场。',
      offset: 1,
      type: 'message',
      role: agentRoleAssistant,
      summarized: 1,
    );
    insertMemory(
      id: 'memory_get_role_user_summary',
      name: '用户约束摘要',
      content: '用户设定李澈来自寒山。',
      offset: 2,
      type: 'summary',
      role: agentRoleUser,
      relatedMessageIds: const ['memory_get_role_user_msg'],
    );
    insertMemory(
      id: 'memory_get_role_assistant_summary',
      name: '执行结论摘要',
      content: '助手执行结论：李澈保持正派并救沈微。',
      offset: 3,
      type: 'summary',
      role: agentRoleAssistant,
      relatedMessageIds: const ['memory_get_role_assistant_msg'],
    );
    insertMemory(
      id: 'memory_get_role_user_recent',
      content: '用户近期补充李澈要低调入山。',
      offset: 4,
      type: 'message',
      role: agentRoleUser,
    );
    insertMemory(
      id: 'memory_get_role_assistant_recent',
      content: '助手近期整理：李澈入山镜头保持克制。',
      offset: 5,
      type: 'message',
      role: agentRoleAssistant,
    );
    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'query': '李澈',
        'roles': [agentRoleAssistant],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只找助手侧整理过的李澈记忆',
      autoMode: false,
    );

    final tool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final properties = tool.schema['properties'] as Map;
    expect(properties, contains('role'));
    expect(properties, contains('roles'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'memory_get');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], everyElement(contains('助手')));
    expect(payload['summaries'], everyElement(contains('助手')));
    expect(payload['recent'], everyElement(contains('助手')));
    final records = payload['records'] as List;
    expect(records, isNotEmpty);
    expect(
      records,
      everyElement(
        isA<Map>().having(
          (record) => record['role'],
          'role',
          agentRoleAssistant,
        ),
      ),
    );
  });

  test('Agent 记忆：memory_get schema 暴露模型常见 RAG 字段别名', () async {
    gateway.turns = [const AgentTurnResult.text('收到')];

    await engine.sendAgentMessage(
      projectId,
      '查看 memory_get 参数',
      autoMode: false,
    );

    final tool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final properties = tool.schema['properties'] as Map;
    expect(
      properties.keys,
      containsAll([
        'q',
        'max',
        'count',
        'min_score',
        'minimumScore',
        'minimum_score',
        'threshold',
        'memoryRoles',
        'memory_roles',
        'memoryScope',
        'memory_scope',
        'excludedRoles',
        'excluded_roles',
        'excludeMemoryRoles',
        'exclude_memory_roles',
        'excludedMemoryRoles',
        'excluded_memory_roles',
        'excludeId',
        'seenIds',
        'readIds',
        'previousMemoryIds',
        'previousRecords',
      ]),
    );
  });

  test('Agent 记忆：memory_get 工具支持 q 和 memory_roles 别名', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    void insertMemory({
      required String id,
      required String content,
      required int offset,
      required String role,
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
          jsonEncode(const <String>[]),
          role,
          0,
          agentMemoryTypeMessage,
        ],
      );
    }

    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '4'],
    );
    insertMemory(
      id: 'memory_get_alias_user',
      content: '用户记录寒山伏笔：李澈先隐藏断剑。',
      offset: 0,
      role: agentRoleUser,
    );
    insertMemory(
      id: 'memory_get_alias_execution',
      content: '执行层记录寒山伏笔：第三集结尾露出断剑。',
      offset: 1,
      role: 'assistant:execution:script',
    );
    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'q': '寒山伏笔',
        'memory_roles': ['assistant:execution:script'],
        'memory_scope': 'conversation',
        'count': 1,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按执行层记忆找寒山伏笔',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.toolName, 'memory_get');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    final records = payload['records'] as List;
    expect(records, isNotEmpty);
    expect(
      records,
      everyElement(
        isA<Map>().having(
          (record) => record['role'],
          'role',
          'assistant:execution:script',
        ),
      ),
    );
  });

  test('Agent 记忆：memory_get 工具支持 queries 多查询合并上下文', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
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
          agentRoleUser,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'memory_get_multi_role',
      '角色约束：李澈必须保持正派，不能反派化。',
      0,
    );
    insertMessage(
      'memory_get_multi_scene',
      '场景画风：寒山山门保持冷白云雾和低机位压迫感。',
      1,
    );
    insertMessage(
      'memory_get_multi_noise',
      '噪声记忆：市集喜剧桥段可以更热闹。',
      2,
    );
    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queries': ['李澈正派约束', '寒山山门冷白低机位'],
        'limit': 4,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '同时查看角色和场景上下文',
      autoMode: false,
    );

    final memoryGetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final properties = memoryGetTool.schema['properties'] as Map;
    expect(properties, contains('queries'));
    expect(properties, contains('queryList'));
    expect(properties, contains('keywords'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'memory_get');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['queries'], ['李澈正派约束', '寒山山门冷白低机位']);
    expect(payload['memories'], contains('角色约束：李澈必须保持正派，不能反派化。'));
    expect(payload['memories'], contains('场景画风：寒山山门保持冷白云雾和低机位压迫感。'));
    expect(payload['memories'], isNot(contains('噪声记忆：市集喜剧桥段可以更热闹。')));
    final recordIds = [
      for (final record in payload['records'] as List)
        (record as Map)['id'] as String,
    ];
    expect(
      recordIds,
      containsAll(['memory_get_multi_role', 'memory_get_multi_scene']),
    );
    expect(recordIds.toSet(), hasLength(recordIds.length));
  });

  test('Agent 记忆：memory_get 和 deepRetrieve 工具支持结构化查询计划', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
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
          agentRoleUser,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage('query_plan_role', '角色约束：李澈必须保持正派，不能反派化。', 0);
    insertMessage('query_plan_scene', '场景画风：寒山山门保持冷白云雾和低机位压迫感。', 1);
    insertMessage('query_plan_noise', '噪声记忆：市集喜剧桥段可以更热闹。', 2);

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {'query': '李澈正派约束', 'reason': '角色一致性'},
          {
            'keywords': ['寒山山门冷白低机位'],
            'scope': 'visual',
          },
        ],
        'limit': 4,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {'q': '李澈正派约束'},
          {'查询': '寒山山门冷白低机位'},
        ],
        'limit': 4,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按结构化查询计划找角色和场景上下文',
      autoMode: true,
    );

    final memoryGetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final memoryGetProperties = memoryGetTool.schema['properties'] as Map;
    expect(
      memoryGetProperties.keys,
      containsAll(['queryPlan', 'retrievalPlan', 'searchQueries', '查询计划']),
    );
    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final deepRetrieveProperties = deepRetrieveTool.schema['properties'] as Map;
    expect(
      deepRetrieveProperties.keys,
      containsAll(['queryPlan', 'retrievalPlan', 'searchQueries', '查询计划']),
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(memoryGetPayload['queries'], ['李澈正派约束', '寒山山门冷白低机位']);
    expect(memoryGetPayload['memories'], contains('角色约束：李澈必须保持正派，不能反派化。'));
    expect(memoryGetPayload['memories'], contains('场景画风：寒山山门保持冷白云雾和低机位压迫感。'));
    expect(memoryGetPayload['memories'], isNot(contains('噪声记忆：市集喜剧桥段可以更热闹。')));

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(deepRetrievePayload['queries'], ['李澈正派约束', '寒山山门冷白低机位']);
    expect(deepRetrievePayload['memories'], contains('角色约束：李澈必须保持正派，不能反派化。'));
    expect(
        deepRetrievePayload['memories'], contains('场景画风：寒山山门保持冷白云雾和低机位压迫感。'));
    expect(
      deepRetrievePayload['memories'],
      isNot(contains('噪声记忆：市集喜剧桥段可以更热闹。')),
    );
  });

  test('Agent 记忆：memory_get queryPlan 可按计划项开启模型重排', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
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
      ['agent.memory.summaryLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.rerankEnabled', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
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
          agentRoleUser,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'query_plan_rerank_keep',
      '用户明确约束：李澈必须保持正派，不能被写成反派。',
      0,
    );
    insertMessage(
      'query_plan_rerank_noise',
      '道具噪声：李澈正派 李澈正派 匾额用于山门背景，和角色立场无关。',
      1,
    );
    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '李澈正派',
            '模型重排': true,
            'reason': '角色立场判别',
          },
        ],
        'limit': 1,
      }),
    ];
    gateway.textResults = const [
      TextResult('["query_plan_rerank_keep"]'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按模型重排找李澈角色立场',
      autoMode: true,
      family: agentFamilyScript,
    );

    final memoryGetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final properties = memoryGetTool.schema['properties'] as Map;
    expect(properties, contains('rerank'));
    expect(properties, contains('模型重排'));
    expect(gateway.textCallCount, 1);
    expect(gateway.textStages, ['scriptAgent:decisionAgent']);

    final toolMessage = engine
        .agentMessages(projectId)
        .singleWhere((message) => message.role == agentRoleTool);
    final payload = jsonDecode(toolMessage.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], [
      '用户明确约束：李澈必须保持正派，不能被写成反派。',
    ]);
    expect(
      payload['records'],
      contains(
        isA<Map>()
            .having((record) => record['id'], 'id', 'query_plan_rerank_keep')
            .having((record) => record['queryReason'], 'queryReason', '角色立场判别'),
      ),
    );
    expect(jsonEncode(payload), isNot(contains('query_plan_rerank_noise')));
  });

  test('Agent 记忆：memory_get queryPlan 可对长期 note 开启模型重排', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.rerankEnabled', '0'],
    );
    final keepId = engine.saveAgentMemory(
      projectId,
      id: 'note_query_plan_rerank_keep',
      name: '角色底线',
      content: '长期设定：用户明确要求李澈保持正派，不能被写成反派。',
    );
    engine.saveAgentMemory(
      projectId,
      id: 'note_query_plan_rerank_noise',
      name: '山门匾额',
      content: '长期噪声：李澈正派约束 李澈正派约束 李澈正派约束 是匾额临时文案，不是角色底线。',
    );
    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '李澈正派约束',
            'scope': 'long_term',
            'rerank': true,
            'reason': '长期设定判别',
          },
        ],
        'limit': 1,
      }),
    ];
    gateway.textResults = const [
      TextResult(
        '[{"memory_id":"note_query_plan_rerank_keep","reason":"长期记忆明确记录角色立场"}]',
      ),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按模型重排找李澈长期设定',
      autoMode: true,
      family: agentFamilyScript,
    );

    expect(gateway.textCallCount, 1);
    expect(gateway.textStages, ['scriptAgent:decisionAgent']);

    final toolMessage = engine
        .agentMessages(projectId)
        .singleWhere((message) => message.role == agentRoleTool);
    final payload = jsonDecode(toolMessage.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['notes'], [
      '长期设定：用户明确要求李澈保持正派，不能被写成反派。',
    ]);
    expect(
      payload['records'],
      contains(
        isA<Map>()
            .having((record) => record['id'], 'id', keepId)
            .having((record) => record['scope'], 'scope', 'long_term')
            .having(
              (record) => record['queryReason'],
              'queryReason',
              '长期设定判别',
            )
            .having(
              (record) => record['relevanceReason'],
              'relevanceReason',
              '长期记忆明确记录角色立场',
            ),
      ),
    );
    expect(
        jsonEncode(payload), isNot(contains('note_query_plan_rerank_noise')));
  });

  test('Agent 记忆：deepRetrieve queryPlan 可按计划项开启模型重排', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.rerankEnabled', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
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
          agentRoleUser,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'deep_query_plan_rerank_keep',
      '用户明确约束：李澈必须保持正派，不能被写成反派。',
      0,
    );
    insertMessage(
      'deep_query_plan_rerank_noise',
      '道具噪声：李澈正派 李澈正派 匾额用于山门背景，和角色立场无关。',
      1,
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'queryPlan': [
          {
            'query': '李澈正派',
            '模型重排': true,
            'reason': '深度召回语义过滤',
          },
        ],
        'limit': 1,
      }),
    ];
    gateway.textResults = const [
      TextResult('["deep_query_plan_rerank_keep"]'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '深度召回时按模型重排找李澈角色立场',
      autoMode: true,
      family: agentFamilyScript,
    );

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = deepRetrieveTool.schema['properties'] as Map;
    expect(properties, contains('rerank'));
    expect(properties, contains('模型重排'));
    expect(gateway.textCallCount, 1);
    expect(gateway.textStages, ['scriptAgent:decisionAgent']);

    final toolMessage = engine
        .agentMessages(projectId)
        .singleWhere((message) => message.role == agentRoleTool);
    final payload = jsonDecode(toolMessage.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], [
      '用户明确约束：李澈必须保持正派，不能被写成反派。',
    ]);
    expect(
      payload['records'],
      contains(
        isA<Map>()
            .having(
              (record) => record['id'],
              'id',
              'deep_query_plan_rerank_keep',
            )
            .having(
              (record) => record['queryReason'],
              'queryReason',
              '深度召回语义过滤',
            ),
      ),
    );
    expect(
      jsonEncode(payload),
      isNot(contains('deep_query_plan_rerank_noise')),
    );
  });

  test('Agent 记忆：queryPlan 计划项支持内容包含与排除词过滤', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '5'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
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
          agentRoleUser,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'query_plan_content_keep',
      '镜湖路线约束：第二镜必须经过冷白水面，保持贴地跟拍。',
      0,
    );
    insertMessage(
      'query_plan_content_excluded',
      '镜湖路线旧设定：第二镜改成暖色宫廷风，镜头高机位俯拍。',
      1,
    );
    insertMessage(
      'query_plan_content_missing_required',
      '镜湖路线备忘：第三镜只记录山门钟声，不涉及水面。',
      2,
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '镜湖路线 第二镜',
            'mustInclude': ['冷白', '水面'],
            'excludeTerms': ['暖色', '旧设定'],
          },
        ],
        'limit': 5,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {
            '查询': '镜湖路线 第二镜',
            '包含关键词': ['冷白', '水面'],
            '排除关键词': ['暖色', '旧设定'],
          },
        ],
        'limit': 5,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按查询计划过滤镜湖路线记忆',
      autoMode: true,
      family: agentFamilyScript,
    );

    final memoryGetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    for (final tool in [memoryGetTool, deepRetrieveTool]) {
      final properties = tool.schema['properties'] as Map;
      expect(properties, contains('mustInclude'));
      expect(properties, contains('excludeTerms'));
      expect(properties, contains('包含关键词'));
      expect(properties, contains('排除关键词'));
    }

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(memoryGetPayload['memories'], [
      '镜湖路线约束：第二镜必须经过冷白水面，保持贴地跟拍。',
    ]);
    expect(
      (memoryGetPayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['query_plan_content_keep'],
    );

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(deepRetrievePayload['memories'], [
      '镜湖路线约束：第二镜必须经过冷白水面，保持贴地跟拍。',
    ]);
    expect(
      (deepRetrievePayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['query_plan_content_keep'],
    );
  });

  test('Agent 记忆：queryPlan schema 暴露对象包裹计划', () async {
    gateway.turns = [
      const AgentTurnResult.text('查看结构化查询计划 schema'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '查看 RAG 查询计划工具 schema',
      autoMode: false,
      family: agentFamilyScript,
    );

    bool acceptsObjectPlan(Map<String, dynamic> property) {
      final type = property['type'];
      if (type is List) return type.contains('object');
      return type == 'object';
    }

    final memoryGetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final memoryGetProperties =
        memoryGetTool.schema['properties'] as Map<String, dynamic>;
    final deepRetrieveProperties =
        deepRetrieveTool.schema['properties'] as Map<String, dynamic>;

    for (final key in const [
      'queryPlan',
      'retrievalPlan',
      'searchPlan',
      'searchQueries',
      'plannedQueries',
      '查询计划',
      '检索计划',
      '搜索计划',
    ]) {
      expect(
        acceptsObjectPlan(memoryGetProperties[key] as Map<String, dynamic>),
        isTrue,
        reason: 'memory_get.$key should accept wrapped query-plan objects',
      );
      expect(
        acceptsObjectPlan(deepRetrieveProperties[key] as Map<String, dynamic>),
        isTrue,
        reason: 'deepRetrieve.$key should accept wrapped query-plan objects',
      );
    }
  });

  test('Agent 记忆：结构化查询计划可携带记忆范围', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final noteId = engine.saveAgentMemory(
      projectId,
      name: '寒山视觉长期设定',
      content: '长期设定：寒山山门保持冷白云雾和低机位压迫感。',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'query_plan_scope_noise',
        '',
        '普通聊天噪声：寒山山门可以改成热闹暖色市集。',
        now,
        embeddingJson('普通聊天噪声：寒山山门可以改成热闹暖色市集。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        1,
        agentMemoryTypeMessage,
      ],
    );
    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {'query': '寒山山门冷白低机位', 'scope': 'long_term'},
        ],
        'limit': 5,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {'查询': '寒山山门冷白低机位', '记忆范围': '长期记忆'},
        ],
        'limit': 5,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按计划项里的范围查长期视觉设定',
      autoMode: true,
      family: agentFamilyScript,
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(memoryGetPayload['memories'], isEmpty);
    expect(memoryGetPayload['summaries'], isEmpty);
    expect(memoryGetPayload['recent'], isEmpty);
    expect(memoryGetPayload['notes'], [
      '长期设定：寒山山门保持冷白云雾和低机位压迫感。',
    ]);
    expect(
      memoryGetPayload['records'],
      contains(
        isA<Map>()
            .having((record) => record['id'], 'id', noteId)
            .having((record) => record['scope'], 'scope', 'long_term'),
      ),
    );

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(deepRetrievePayload['memories'], [
      '长期设定：寒山山门保持冷白云雾和低机位压迫感。',
    ]);
    expect(
      deepRetrievePayload['records'],
      contains(
        isA<Map>()
            .having((record) => record['id'], 'id', noteId)
            .having((record) => record['scope'], 'scope', 'long_term'),
      ),
    );
  });

  test('Agent 记忆：结构化查询计划可携带记忆角色过滤', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertMessage({
      required String id,
      required String content,
      required int offset,
      required String role,
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
      id: 'query_plan_role_user_noise',
      content: '用户约束噪声：寒山门规可以改成轻松喜剧。',
      offset: 0,
      role: agentRoleUser,
    );
    insertMessage(
      id: 'query_plan_role_execution',
      content: '执行层记忆：寒山门规必须冷峻，李澈入山时保持低机位压迫感。',
      offset: 1,
      role: 'assistant:execution:script',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '寒山门规低机位',
            'memoryRoles': ['assistant:execution:script'],
          },
        ],
        'limit': 5,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {
            '查询': '寒山门规低机位',
            '记忆角色': ['assistant:execution:script'],
          },
        ],
        'limit': 5,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按计划项里的角色过滤查执行层记忆',
      autoMode: true,
      family: agentFamilyScript,
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(memoryGetPayload['memories'], [
      '执行层记忆：寒山门规必须冷峻，李澈入山时保持低机位压迫感。',
    ]);
    expect(
      memoryGetPayload['records'],
      everyElement(
        isA<Map>().having(
          (record) => record['role'],
          'role',
          'assistant:execution:script',
        ),
      ),
    );

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(deepRetrievePayload['memories'], [
      '执行层记忆：寒山门规必须冷峻，李澈入山时保持低机位压迫感。',
    ]);
    expect(
      deepRetrievePayload['records'],
      everyElement(
        isA<Map>().having(
          (record) => record['role'],
          'role',
          'assistant:execution:script',
        ),
      ),
    );
  });

  test('Agent 记忆：结构化查询计划可携带排除角色过滤', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertMessage({
      required String id,
      required String content,
      required int offset,
      required String role,
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
      id: 'query_plan_exclude_keep',
      content: '用户约束：玄铁门规甲子必须保持冷峻。',
      offset: 0,
      role: agentRoleUser,
    );
    insertMessage(
      id: 'query_plan_exclude_tool_noise',
      content: '研究噪声：玄铁门规甲子可以改成喜剧。',
      offset: 1,
      role: 'assistant:research',
    );
    insertMessage(
      id: 'query_plan_suffix_keep',
      content: '助手结论：霜桥试炼乙卯保留低机位压迫感。',
      offset: 2,
      role: agentRoleAssistant,
    );
    insertMessage(
      id: 'query_plan_suffix_tool_noise',
      content: '草稿噪声：霜桥试炼乙卯可以省略低机位。',
      offset: 3,
      role: 'assistant:execution:script:scratch',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '玄铁门规甲子',
            'excludeRoles': ['assistant:research'],
          },
        ],
        'limit': 5,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {
            '查询': '霜桥试炼乙卯',
            '排除角色后缀': [':scratch'],
          },
        ],
        'limit': 5,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按计划项里的排除角色过滤工具审计噪声',
      autoMode: true,
      family: agentFamilyScript,
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(memoryGetPayload['memories'], [
      '用户约束：玄铁门规甲子必须保持冷峻。',
    ]);
    expect(
      memoryGetPayload['records'],
      everyElement(
        isA<Map>().having(
          (record) => record['role'],
          'role',
          isNot('assistant:research'),
        ),
      ),
    );

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(deepRetrievePayload['memories'], [
      '助手结论：霜桥试炼乙卯保留低机位压迫感。',
    ]);
    expect(
      deepRetrievePayload['records'],
      everyElement(
        isA<Map>().having(
          (record) => record['role'],
          'role',
          isNot(endsWith(':scratch')),
        ),
      ),
    );
  });

  test('Agent 记忆：结构化查询计划可携带相似度阈值', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
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
          agentRoleAssistant,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'query_plan_similarity_high',
      '用户明确要求：李澈正派设定必须保留，不能反派化。',
      0,
    );
    insertMessage(
      'query_plan_similarity_low',
      '用户补充：李澈来自寒山宗门。',
      1,
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '李澈正派设定',
            'minSimilarity': 0.8,
          },
        ],
        'limit': 5,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {
            '查询': '李澈正派设定',
            '相似度阈值': '0.8',
          },
        ],
        'limit': 5,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按计划项里的相似度阈值找李澈设定',
      autoMode: true,
      family: agentFamilyScript,
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(
      memoryGetPayload['memories'],
      contains('用户明确要求：李澈正派设定必须保留，不能反派化。'),
    );
    expect(
      memoryGetPayload['memories'],
      isNot(contains('用户补充：李澈来自寒山宗门。')),
    );

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(
      deepRetrievePayload['memories'],
      contains('用户明确要求：李澈正派设定必须保留，不能反派化。'),
    );
    expect(
      deepRetrievePayload['memories'],
      isNot(contains('用户补充：李澈来自寒山宗门。')),
    );
  });

  test('Agent 记忆：结构化查询计划按 priority 保留高优先级结果', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
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
          agentRoleAssistant,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'query_plan_priority_low',
      '背景参考：青云市集可以有热闹烟火气。',
      0,
    );
    insertMessage(
      'query_plan_priority_medium',
      '制作提示：沈微入场时可以保留月光轮廓。',
      1,
    );
    insertMessage(
      'query_plan_priority_high',
      '硬性约束：李澈绝不能反派化，所有分镜必须保持正派克制。',
      2,
    );

    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'queryPlan': [
          {
            'query': '青云市集烟火气',
            'priority': 1,
          },
          {
            'query': '沈微月光轮廓',
            'weight': 5,
          },
          {
            'query': '李澈不能反派化',
            '重要性': 10,
          },
        ],
        'limit': 1,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按查询计划优先级找最重要约束',
      autoMode: false,
    );

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = deepRetrieveTool.schema['properties'] as Map;
    expect(properties, contains('queryPlan'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['queries'], ['青云市集烟火气', '沈微月光轮廓', '李澈不能反派化']);
    expect(payload['memories'], [
      '硬性约束：李澈绝不能反派化，所有分镜必须保持正派克制。',
    ]);
    expect(
      payload['records'],
      contains(
        isA<Map>()
            .having((record) => record['id'], 'id', 'query_plan_priority_high')
            .having((record) => record['priority'], 'priority', 10),
      ),
    );
  });

  test('Agent 记忆：memory_get 结构化查询计划按 priority 保留高优先级结果', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
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
          agentRoleAssistant,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'memory_get_priority_low',
      '背景参考：青云市集可以有热闹烟火气。',
      0,
    );
    insertMessage(
      'memory_get_priority_medium',
      '制作提示：沈微入场时可以保留月光轮廓。',
      1,
    );
    insertMessage(
      'memory_get_priority_high',
      '硬性约束：李澈绝不能反派化，所有分镜必须保持正派克制。',
      2,
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '青云市集烟火气',
            'priority': 1,
          },
          {
            'query': '沈微月光轮廓',
            'weight': 5,
          },
          {
            'query': '李澈不能反派化',
            '重要性': 10,
          },
        ],
        'limit': 1,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '快速上下文也按查询计划优先级找最重要约束',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'memory_get');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['queries'], ['青云市集烟火气', '沈微月光轮廓', '李澈不能反派化']);
    expect(payload['memories'], [
      '硬性约束：李澈绝不能反派化，所有分镜必须保持正派克制。',
    ]);
    expect(
      payload['records'],
      contains(
        isA<Map>()
            .having((record) => record['id'], 'id', 'memory_get_priority_high')
            .having((record) => record['priority'], 'priority', 10),
      ),
    );
  });

  test('Agent 记忆：memory_get 结构化查询计划重复命中取最高 priority', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
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
          agentRoleAssistant,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'memory_get_priority_reused',
      '硬性约束：李澈绝不能反派化，所有分镜必须保持正派克制。',
      0,
    );
    insertMessage(
      'memory_get_priority_competing',
      '制作提示：沈微入场时可以保留月光轮廓。',
      1,
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '李澈',
            'priority': 1,
          },
          {
            'query': '沈微月光轮廓',
            'priority': 5,
          },
          {
            'query': '李澈不能反派化',
            'priority': 10,
          },
        ],
        'limit': 1,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '快速上下文里同一条记忆重复命中时按最高优先级保留',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'memory_get');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], [
      '硬性约束：李澈绝不能反派化，所有分镜必须保持正派克制。',
    ]);
    expect(
      payload['records'],
      contains(
        isA<Map>()
            .having(
                (record) => record['id'], 'id', 'memory_get_priority_reused')
            .having((record) => record['priority'], 'priority', 10),
      ),
    );
  });

  test('Agent 记忆：结构化查询计划重复命中取最高 priority', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
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
          agentRoleAssistant,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'query_plan_priority_reused',
      '硬性约束：李澈绝不能反派化，所有分镜必须保持正派克制。',
      0,
    );
    insertMessage(
      'query_plan_priority_competing',
      '制作提示：沈微入场时可以保留月光轮廓。',
      1,
    );

    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'queryPlan': [
          {
            'query': '李澈',
            'priority': 1,
          },
          {
            'query': '沈微月光轮廓',
            'priority': 5,
          },
          {
            'query': '李澈不能反派化',
            'priority': 10,
          },
        ],
        'limit': 1,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '同一条记忆重复命中时按最高优先级保留',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], [
      '硬性约束：李澈绝不能反派化，所有分镜必须保持正派克制。',
    ]);
    expect(
      payload['records'],
      contains(
        isA<Map>()
            .having(
                (record) => record['id'], 'id', 'query_plan_priority_reused')
            .having((record) => record['priority'], 'priority', 10),
      ),
    );
  });

  test('Agent 记忆：queryPlan records 标注最高优先级命中来源', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
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
          agentRoleAssistant,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'query_plan_trace_reused',
      '硬性约束：李澈绝不能反派化，所有分镜必须保持正派克制。',
      0,
    );
    insertMessage(
      'query_plan_trace_competing',
      '制作提示：沈微入场时可以保留月光轮廓。',
      1,
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '李澈',
            'priority': 1,
            'reason': '宽泛角色检索',
          },
          {
            'query': '李澈不能反派化',
            'priority': 10,
            'reason': '硬性角色约束',
          },
        ],
        'limit': 1,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        'queryPlan': [
          {
            'query': '李澈',
            'priority': 1,
            'reason': '宽泛角色检索',
          },
          {
            'query': '李澈不能反派化',
            'priority': 10,
            'reason': '硬性角色约束',
          },
        ],
        'limit': 1,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '追踪 RAG 结果来自哪条查询计划',
      autoMode: true,
      family: agentFamilyScript,
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    for (final message in toolMessages) {
      final payload = jsonDecode(message.content) as Map<String, dynamic>;
      expect(payload['found'], isTrue);
      final records = payload['records'] as List;
      expect(records, hasLength(1));
      expect(
        records.single,
        isA<Map>()
            .having((record) => record['id'], 'id', 'query_plan_trace_reused')
            .having((record) => record['priority'], 'priority', 10)
            .having(
                (record) => record['matchedQuery'], 'matchedQuery', '李澈不能反派化')
            .having((record) => record['queryPlanIndex'], 'queryPlanIndex', 2)
            .having((record) => record['queryReason'], 'queryReason', '硬性角色约束'),
      );
    }
  });

  test('Agent 记忆：records 标注向量索引命中来源', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
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
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.summaryLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertIndexedMessage({
      required String id,
      required String content,
      required List<double> vector,
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
          '',
          'scriptAgent:$projectId',
          '[]',
          agentRoleAssistant,
          1,
          agentMemoryTypeMessage,
        ],
      );
      db.execute(
        'INSERT OR REPLACE INTO o_memoryVector '
        '(memoryId,isolationKey,type,provider,model,dimension,vector,updatedAt) '
        'VALUES (?,?,?,?,?,?,?,?)',
        [
          id,
          'scriptAgent:$projectId',
          agentMemoryTypeMessage,
          'gateway',
          'agent_embedding',
          vector.length,
          jsonEncode(vector),
          now + offset,
        ],
      );
    }

    insertIndexedMessage(
      id: 'vector_trace_keep',
      content: '向量审计命中：李澈必须保护沈微。',
      vector: const [1, 0],
      offset: 0,
    );
    insertIndexedMessage(
      id: 'vector_trace_noise',
      content: '向量审计噪声：山门远景云雾。',
      vector: const [0, 1],
      offset: 1,
    );
    gateway.embeddingForText = (input) {
      if (input.contains('保护沈微')) return const [1, 0];
      return const [0, 1];
    };
    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'query': '保护沈微',
        'limit': 1,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        'keyword': '保护沈微',
        'limit': 1,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '追踪向量索引召回来源',
      autoMode: true,
      family: agentFamilyScript,
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);
    expect(gateway.embeddingInputs, containsAll(['保护沈微']));

    for (final message in toolMessages) {
      final payload = jsonDecode(message.content) as Map<String, dynamic>;
      expect(payload['found'], isTrue);
      final records = payload['records'] as List;
      expect(records, hasLength(1));
      expect(
        records.single,
        isA<Map>()
            .having((record) => record['id'], 'id', 'vector_trace_keep')
            .having((record) => record['retrievalSource'], 'retrievalSource',
                'vector_index')
            .having((record) => record['embeddingProvider'],
                'embeddingProvider', 'gateway')
            .having((record) => record['embeddingModel'], 'embeddingModel',
                'agent_embedding')
            .having((record) => record['embeddingDimension'],
                'embeddingDimension', 2),
      );
    }
  });

  test('Agent 记忆：queryPlan 可要求只接受向量索引命中', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '2'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.summaryLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertMessage({
      required String id,
      required String content,
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
          '',
          'scriptAgent:$projectId',
          '[]',
          agentRoleAssistant,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      id: 'vector_only_fallback_match',
      content: '未索引记忆：李澈必须保护沈微。',
      offset: 0,
    );
    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '保护沈微',
            'retrievalSource': 'vector_index',
          },
        ],
        'limit': 2,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        'queryPlan': [
          {
            'query': '保护沈微',
            '只用向量索引': true,
          },
        ],
        'limit': 2,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只接受向量索引里已经存在的召回',
      autoMode: true,
      family: agentFamilyScript,
    );

    final memoryGetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    for (final tool in [memoryGetTool, deepRetrieveTool]) {
      final properties = tool.schema['properties'] as Map;
      expect(properties, contains('retrievalSource'));
      expect(properties, contains('onlyVectorIndex'));
      expect(properties, contains('检索来源'));
      expect(properties, contains('只用向量索引'));
    }

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    for (final message in toolMessages) {
      final payload = jsonDecode(message.content) as Map<String, dynamic>;
      expect(payload['found'], isFalse,
          reason: '${message.toolName}: ${message.content}');
      expect(payload['message'], '未找到相关记忆');
      expect(payload['records'], isEmpty);
      expect(payload['memories'], isEmpty);
      if (message.toolName == 'memory_get') {
        expect(payload['summaries'], isEmpty);
        expect(payload['recent'], isEmpty);
        expect(payload['notes'], isEmpty);
      }
      expect(
          jsonEncode(payload), isNot(contains('vector_only_fallback_match')));
      expect(jsonEncode(payload), isNot(contains('未索引记忆：李澈必须保护沈微')));
    }
  });

  test('Agent 记忆：queryPlan 支持语义向量查询字段并保留硬过滤词', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['binding.agent_embedding', 'fake:embed'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.summaryLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertIndexedMessage({
      required String id,
      required String content,
      required List<double> vector,
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
          '',
          'scriptAgent:$projectId',
          '[]',
          agentRoleAssistant,
          1,
          agentMemoryTypeMessage,
        ],
      );
      db.execute(
        'INSERT OR REPLACE INTO o_memoryVector '
        '(memoryId,isolationKey,type,provider,model,dimension,vector,updatedAt) '
        'VALUES (?,?,?,?,?,?,?,?)',
        [
          id,
          'scriptAgent:$projectId',
          agentMemoryTypeMessage,
          'gateway',
          'agent_embedding',
          vector.length,
          jsonEncode(vector),
          now + offset,
        ],
      );
    }

    insertIndexedMessage(
      id: 'semantic_vector_plan_filtered',
      content: '角色设定：陆衡和顾眠之间有不可背弃的师徒契约。',
      vector: const [1, 0],
      offset: 1,
    );
    insertIndexedMessage(
      id: 'semantic_vector_plan_keep',
      content: '角色设定：李澈和沈微之间有不可背弃的师徒契约。',
      vector: const [1, 0],
      offset: 0,
    );
    insertIndexedMessage(
      id: 'semantic_vector_plan_noise',
      content: '场景设定：山门远景云雾遮住日光。',
      vector: const [0, 1],
      offset: 2,
    );
    gateway.embeddingForText = (input) {
      if (input.contains('不可背弃') || input.contains('师徒契约')) {
        return const [1, 0];
      }
      return const [0, 1];
    };
    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'semanticQuery': '不可背弃的师徒契约',
            'mustInclude': ['李澈', '沈微'],
            'retrievalSource': 'vector_index',
            'reason': '语义角色约束',
          },
        ],
        'limit': 2,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {
            '向量查询': '不可背弃的师徒契约',
            '必须包含': ['李澈', '沈微'],
            '只用向量索引': true,
            'reason': '语义角色约束',
          },
        ],
        'limit': 2,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '用语义向量查询召回角色契约硬约束',
      autoMode: true,
      family: agentFamilyScript,
    );

    final memoryGetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    for (final tool in [memoryGetTool, deepRetrieveTool]) {
      final properties = tool.schema['properties'] as Map;
      expect(properties, contains('semanticQuery'));
      expect(properties, contains('vectorQuery'));
      expect(properties, contains('向量查询'));
      expect(properties, contains('语义查询'));
    }

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);
    expect(gateway.embeddingInputs, contains('不可背弃的师徒契约'));

    for (final message in toolMessages) {
      final payload = jsonDecode(message.content) as Map<String, dynamic>;
      expect(payload['found'], isTrue,
          reason: '${message.toolName}: ${message.content}');
      final payloadText = jsonEncode(payload);
      expect(payloadText, contains('semantic_vector_plan_keep'));
      expect(payloadText, isNot(contains('semantic_vector_plan_filtered')));
      expect(payloadText, isNot(contains('semantic_vector_plan_noise')));
      expect(
        payload['records'],
        contains(
          isA<Map>()
              .having(
                  (record) => record['id'], 'id', 'semantic_vector_plan_keep')
              .having((record) => record['retrievalSource'], 'retrievalSource',
                  'vector_index')
              .having((record) => record['matchedQuery'], 'matchedQuery',
                  '不可背弃的师徒契约')
              .having(
                  (record) => record['queryReason'], 'queryReason', '语义角色约束'),
        ),
      );
    }
  });

  test('Agent 记忆：queryPlan 可要求同项查询全部命中', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.summaryLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertMessage({
      required String id,
      required String content,
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
          agentRoleAssistant,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      id: 'query_plan_all_match_keep',
      content: '硬性约束：李澈必须保护沈微，并且绝不能反派化。',
      offset: 0,
    );
    insertMessage(
      id: 'query_plan_all_match_only_protect',
      content: '人物设定：李澈必须保护沈微。',
      offset: 1,
    );
    insertMessage(
      id: 'query_plan_all_match_only_role',
      content: '人物设定：李澈绝不能反派化。',
      offset: 2,
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'queries': ['保护沈微', '不能反派化'],
            'match': 'all',
            'reason': '组合硬约束',
          },
        ],
        'limit': 4,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        'queryPlan': [
          {
            '查询列表': ['保护沈微', '不能反派化'],
            '必须全部命中': true,
            'reason': '组合硬约束',
          },
        ],
        'limit': 4,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只召回同时满足两个硬性约束的记忆',
      autoMode: true,
      family: agentFamilyScript,
    );

    final memoryGetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    for (final tool in [memoryGetTool, deepRetrieveTool]) {
      final properties = tool.schema['properties'] as Map;
      expect(properties, contains('match'));
      expect(properties, contains('operator'));
      expect(properties, contains('必须全部命中'));
    }

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    for (final message in toolMessages) {
      final payload = jsonDecode(message.content) as Map<String, dynamic>;
      expect(payload['found'], isTrue,
          reason: '${message.toolName}: ${message.content}');
      expect(jsonEncode(payload), contains('query_plan_all_match_keep'));
      expect(
        jsonEncode(payload),
        isNot(contains('query_plan_all_match_only_protect')),
      );
      expect(
        jsonEncode(payload),
        isNot(contains('query_plan_all_match_only_role')),
      );
      final records = payload['records'] as List;
      expect(records, hasLength(1));
      expect(
        records.single,
        isA<Map>()
            .having((record) => record['id'], 'id', 'query_plan_all_match_keep')
            .having((record) => record['queryReason'], 'queryReason', '组合硬约束'),
      );
    }
  });

  test('Agent 记忆：queryPlan fallback 仅在前序无结果时执行', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.summaryLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertMessage({
      required String id,
      required String content,
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
          agentRoleAssistant,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      id: 'query_plan_fallback_strict_keep',
      content: '硬性约束：李澈必须保护沈微，并且绝不能反派化。',
      offset: 0,
    );
    insertMessage(
      id: 'query_plan_fallback_broad_noise',
      content: '宽泛设定：李澈使用寒铁剑，但没有沈微保护规则。',
      offset: 1,
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'queries': ['保护沈微', '不能反派化'],
            'match': 'all',
            'reason': '严格硬约束',
          },
          {
            'query': '寒铁剑',
            'fallback': true,
            'reason': '兜底宽召回',
          },
        ],
        'limit': 4,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        'queryPlan': [
          {
            '查询列表': ['保护沈微', '必须进入魔道'],
            '必须全部命中': true,
            'reason': '严格硬约束',
          },
          {
            'query': '寒铁剑',
            '仅在无结果时使用': true,
            'reason': '兜底宽召回',
          },
        ],
        'limit': 4,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '先严格召回，没结果再兜底',
      autoMode: true,
      family: agentFamilyScript,
    );

    final memoryGetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    for (final tool in [memoryGetTool, deepRetrieveTool]) {
      final properties = tool.schema['properties'] as Map;
      expect(properties, contains('fallback'));
      expect(properties, contains('whenEmpty'));
      expect(properties, contains('仅在无结果时使用'));
    }

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages[0].content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(jsonEncode(memoryGetPayload),
        contains('query_plan_fallback_strict_keep'));
    expect(jsonEncode(memoryGetPayload),
        isNot(contains('query_plan_fallback_broad_noise')));
    expect(jsonEncode(memoryGetPayload), isNot(contains('兜底宽召回')));

    final deepRetrievePayload =
        jsonDecode(toolMessages[1].content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(jsonEncode(deepRetrievePayload),
        contains('query_plan_fallback_broad_noise'));
    expect(jsonEncode(deepRetrievePayload),
        isNot(contains('query_plan_fallback_strict_keep')));
    expect(
      deepRetrievePayload['records'],
      contains(
        isA<Map>()
            .having((record) => record['id'], 'id',
                'query_plan_fallback_broad_noise')
            .having((record) => record['queryReason'], 'queryReason', '兜底宽召回'),
      ),
    );
  });

  test('Agent 记忆：queryPlan fallback 按检索分组独立判断', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '6'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.summaryLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertMessage({
      required String id,
      required String content,
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
          agentRoleAssistant,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      id: 'query_plan_group_role_strict_keep',
      content: '角色硬约束：李澈必须保护沈微，并且绝不能反派化。',
      offset: 0,
    );
    insertMessage(
      id: 'query_plan_group_role_fallback_noise',
      content: '角色兜底设定：李澈携带寒铁剑。',
      offset: 1,
    );
    insertMessage(
      id: 'query_plan_group_scene_fallback_keep',
      content: '场景兜底设定：镜湖夜雨必须压低曝光。',
      offset: 2,
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'queries': ['保护沈微', '不能反派化'],
            'match': 'all',
            'group': 'role',
            'reason': '角色严格检索',
          },
          {
            'query': '寒铁剑',
            'fallback': true,
            'group': 'role',
            'reason': '角色兜底',
          },
          {
            'queries': ['镜湖夜雨', '雪崩'],
            'match': 'all',
            'fallbackGroup': 'scene',
            'reason': '场景严格检索',
          },
          {
            'query': '镜湖夜雨压低曝光',
            'fallback': true,
            'fallbackGroup': 'scene',
            'reason': '场景兜底',
          },
        ],
        'limit': 6,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        'queryPlan': [
          {
            '查询列表': ['保护沈微', '不能反派化'],
            '必须全部命中': true,
            '检索分组': 'role',
            'reason': '角色严格检索',
          },
          {
            'query': '寒铁剑',
            '仅在无结果时使用': true,
            '检索分组': 'role',
            'reason': '角色兜底',
          },
          {
            '查询列表': ['镜湖夜雨', '雪崩'],
            '必须全部命中': true,
            '检索分组': 'scene',
            'reason': '场景严格检索',
          },
          {
            'query': '镜湖夜雨压低曝光',
            '仅在无结果时使用': true,
            '检索分组': 'scene',
            'reason': '场景兜底',
          },
        ],
        'limit': 6,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '角色和场景两组检索各自决定是否兜底',
      autoMode: true,
      family: agentFamilyScript,
    );

    final memoryGetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    for (final tool in [memoryGetTool, deepRetrieveTool]) {
      final properties = tool.schema['properties'] as Map;
      expect(properties, contains('group'));
      expect(properties, contains('fallbackGroup'));
      expect(properties, contains('检索分组'));
    }

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    for (final message in toolMessages) {
      final payload = jsonDecode(message.content) as Map<String, dynamic>;
      final payloadText = jsonEncode(payload);
      expect(payload['found'], isTrue,
          reason: '${message.toolName}: ${message.content}');
      expect(payloadText, contains('query_plan_group_role_strict_keep'));
      expect(payloadText, contains('query_plan_group_scene_fallback_keep'));
      expect(
        payloadText,
        isNot(contains('query_plan_group_role_fallback_noise')),
      );
      expect(
        payload['records'],
        contains(
          isA<Map>()
              .having((record) => record['id'], 'id',
                  'query_plan_group_scene_fallback_keep')
              .having((record) => record['queryGroup'], 'queryGroup', 'scene')
              .having((record) => record['queryReason'], 'queryReason', '场景兜底'),
        ),
      );
    }
  });

  test('Agent 记忆：结构化查询计划可携带时间窗口', () async {
    const baseTime = 1900000000000;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertMessage({
      required String id,
      required String content,
      required int createTime,
    }) {
      db.execute(
        'INSERT INTO memories '
        '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          '',
          content,
          createTime,
          embeddingJson(content),
          'scriptAgent:$projectId',
          '[]',
          agentRoleAssistant,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      id: 'query_plan_time_memory_get_old',
      content: '旧记忆：玄天策划甲子采用暖色市集。',
      createTime: baseTime,
    );
    insertMessage(
      id: 'query_plan_time_memory_get_new',
      content: '新记忆：玄天策划甲子保持冷白山门。',
      createTime: baseTime + 1000,
    );
    insertMessage(
      id: 'query_plan_time_deep_old',
      content: '旧记忆：霜岭执行乙卯删除低机位。',
      createTime: baseTime,
    );
    insertMessage(
      id: 'query_plan_time_deep_new',
      content: '新记忆：霜岭执行乙卯保留低机位。',
      createTime: baseTime + 1000,
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '玄天策划甲子',
            'createdAfter': baseTime + 500,
          },
        ],
        'limit': 5,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {
            '查询': '霜岭执行乙卯',
            '开始时间': baseTime + 500,
          },
        ],
        'limit': 5,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按计划项里的时间窗口查制作期记忆',
      autoMode: true,
      family: agentFamilyScript,
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(memoryGetPayload['memories'], ['新记忆：玄天策划甲子保持冷白山门。']);
    expect(
      memoryGetPayload['records'],
      everyElement(
        isA<Map>().having(
          (record) => record['createTime'],
          'createTime',
          greaterThanOrEqualTo(baseTime + 500),
        ),
      ),
    );

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(deepRetrievePayload['memories'], ['新记忆：霜岭执行乙卯保留低机位。']);
    expect(
      deepRetrievePayload['records'],
      everyElement(
        isA<Map>().having(
          (record) => record['createTime'],
          'createTime',
          greaterThanOrEqualTo(baseTime + 500),
        ),
      ),
    );
  });

  test('Agent 记忆：结构化查询计划可携带自然排序', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertMessage({
      required String id,
      required String content,
      required int offset,
      required String role,
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
      id: 'query_plan_sort_memory_get_old',
      content: '旧记忆：云台校验甲子第一次记录，李澈采用远景。',
      offset: 1,
      role: 'assistant:sort:get',
    );
    insertMessage(
      id: 'query_plan_sort_memory_get_new',
      content: '新记忆：云台校验甲子第二次记录，李澈采用近景。',
      offset: 2,
      role: 'assistant:sort:get',
    );
    insertMessage(
      id: 'query_plan_sort_deep_old',
      content: '旧记忆：玄火校验乙卯第一次记录，沈微独白保留。',
      offset: 3,
      role: 'assistant:sort:deep',
    );
    insertMessage(
      id: 'query_plan_sort_deep_new',
      content: '新记忆：玄火校验乙卯第二次记录，沈微独白删除。',
      offset: 4,
      role: 'assistant:sort:deep',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '云台校验甲子',
            'orderBy': 'oldest',
            'memoryRoles': ['assistant:sort:get'],
          },
        ],
        'limit': 2,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {
            '查询': '玄火校验乙卯',
            '排序': '最旧',
            '记忆角色': ['assistant:sort:deep'],
          },
        ],
        'limit': 2,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按计划项里的排序方式查最新制作记忆',
      autoMode: true,
      family: agentFamilyScript,
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(
      (memoryGetPayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['query_plan_sort_memory_get_old', 'query_plan_sort_memory_get_new'],
    );
    expect(memoryGetPayload['memories'], [
      '旧记忆：云台校验甲子第一次记录，李澈采用远景。',
      '新记忆：云台校验甲子第二次记录，李澈采用近景。',
    ]);

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(
      (deepRetrievePayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['query_plan_sort_deep_old', 'query_plan_sort_deep_new'],
    );
    expect(deepRetrievePayload['memories'], [
      '旧记忆：玄火校验乙卯第一次记录，沈微独白保留。',
      '新记忆：玄火校验乙卯第二次记录，沈微独白删除。',
    ]);
  });

  test('Agent 记忆：结构化查询计划多项排序互不串味', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertMessage({
      required String id,
      required String content,
      required int offset,
      required String role,
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
      id: 'query_plan_item_sort_get_a_old',
      content: 'iota_sort_get_a：甲组旧记录必须保留蓝火。',
      offset: 1,
      role: 'assistant:item-sort:get:a',
    );
    insertMessage(
      id: 'query_plan_item_sort_get_a_new',
      content: 'iota_sort_get_a：甲组新记录必须保留蓝火。',
      offset: 2,
      role: 'assistant:item-sort:get:a',
    );
    insertMessage(
      id: 'query_plan_item_sort_get_b_old',
      content: 'kappa_sort_get_b：乙组旧记录必须保留雾门。',
      offset: 3,
      role: 'assistant:item-sort:get:b',
    );
    insertMessage(
      id: 'query_plan_item_sort_get_b_new',
      content: 'kappa_sort_get_b：乙组新记录必须保留雾门。',
      offset: 4,
      role: 'assistant:item-sort:get:b',
    );
    insertMessage(
      id: 'query_plan_item_sort_deep_a_old',
      content: 'lambda_sort_deep_a：丙组旧记录必须保留水纹。',
      offset: 5,
      role: 'assistant:item-sort:deep:a',
    );
    insertMessage(
      id: 'query_plan_item_sort_deep_a_new',
      content: 'lambda_sort_deep_a：丙组新记录必须保留水纹。',
      offset: 6,
      role: 'assistant:item-sort:deep:a',
    );
    insertMessage(
      id: 'query_plan_item_sort_deep_b_old',
      content: 'mu_sort_deep_b：丁组旧记录必须保留云台。',
      offset: 7,
      role: 'assistant:item-sort:deep:b',
    );
    insertMessage(
      id: 'query_plan_item_sort_deep_b_new',
      content: 'mu_sort_deep_b：丁组新记录必须保留云台。',
      offset: 8,
      role: 'assistant:item-sort:deep:b',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': 'iota_sort_get_a',
            'memoryRoles': ['assistant:item-sort:get:a'],
            'orderBy': 'latest',
            'minSimilarity': 0.8,
          },
          {
            'query': 'kappa_sort_get_b',
            'memoryRoles': ['assistant:item-sort:get:b'],
            'orderBy': 'oldest',
            'minSimilarity': 0.8,
          },
        ],
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {
            '查询': 'lambda_sort_deep_a',
            '记忆角色': ['assistant:item-sort:deep:a'],
            '排序': '最新',
            '相似度阈值': 0.8,
          },
          {
            '查询': 'mu_sort_deep_b',
            '记忆角色': ['assistant:item-sort:deep:b'],
            '排序': '最旧',
            '相似度阈值': 0.8,
          },
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按每个计划项自己的排序查记忆',
      autoMode: true,
      family: agentFamilyScript,
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(
      (memoryGetPayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      [
        'query_plan_item_sort_get_a_new',
        'query_plan_item_sort_get_a_old',
        'query_plan_item_sort_get_b_old',
        'query_plan_item_sort_get_b_new',
      ],
    );

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(
      (deepRetrievePayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      [
        'query_plan_item_sort_deep_a_new',
        'query_plan_item_sort_deep_a_old',
        'query_plan_item_sort_deep_b_old',
        'query_plan_item_sort_deep_b_new',
      ],
    );
  });

  test('Agent 记忆：结构化查询计划可携带返回数量限制', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertMessage({
      required String id,
      required String content,
      required int offset,
      required String role,
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
      id: 'query_plan_limit_memory_get_old',
      content: '旧记忆：青碑限量甲子第一次记录，保留宗门门规。',
      offset: 1,
      role: 'assistant:limit:get',
    );
    insertMessage(
      id: 'query_plan_limit_memory_get_new',
      content: '新记忆：青碑限量甲子第二次记录，增加宗门门规。',
      offset: 2,
      role: 'assistant:limit:get',
    );
    insertMessage(
      id: 'query_plan_limit_deep_old',
      content: '旧记忆：赤桥限量乙卯第一次记录，保留低机位。',
      offset: 3,
      role: 'assistant:limit:deep',
    );
    insertMessage(
      id: 'query_plan_limit_deep_new',
      content: '新记忆：赤桥限量乙卯第二次记录，增加俯拍。',
      offset: 4,
      role: 'assistant:limit:deep',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '青碑限量甲子',
            'limit': 1,
            'orderBy': 'oldest',
            'memoryRoles': ['assistant:limit:get'],
          },
        ],
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {
            '查询': '赤桥限量乙卯',
            '数量': 1,
            '排序': '最旧',
            '记忆角色': ['assistant:limit:deep'],
          },
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按计划项里的返回数量限制查制作记忆',
      autoMode: true,
      family: agentFamilyScript,
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(
      (memoryGetPayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['query_plan_limit_memory_get_old'],
    );
    expect(memoryGetPayload['memories'], [
      '旧记忆：青碑限量甲子第一次记录，保留宗门门规。',
    ]);

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(
      (deepRetrievePayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['query_plan_limit_deep_old'],
    );
    expect(deepRetrievePayload['memories'], [
      '旧记忆：赤桥限量乙卯第一次记录，保留低机位。',
    ]);
  });

  test('Agent 记忆：结构化查询计划多项返回数量互不串味', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertMessage({
      required String id,
      required String content,
      required int offset,
      required String role,
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
      id: 'query_plan_item_limit_get_a_old',
      content: 'epsilon_limit_get_a：甲组第一次记录必须保留蓝火。',
      offset: 1,
      role: 'assistant:item-limit:get:a',
    );
    insertMessage(
      id: 'query_plan_item_limit_get_a_new',
      content: 'epsilon_limit_get_a：甲组第二次记录必须保留蓝火。',
      offset: 2,
      role: 'assistant:item-limit:get:a',
    );
    insertMessage(
      id: 'query_plan_item_limit_get_b_old',
      content: 'zeta_limit_get_b：乙组第一次记录必须保留雾门。',
      offset: 3,
      role: 'assistant:item-limit:get:b',
    );
    insertMessage(
      id: 'query_plan_item_limit_get_b_new',
      content: 'zeta_limit_get_b：乙组第二次记录必须保留雾门。',
      offset: 4,
      role: 'assistant:item-limit:get:b',
    );
    insertMessage(
      id: 'query_plan_item_limit_deep_a_old',
      content: 'eta_limit_deep_a：丙组第一次记录必须保留水纹。',
      offset: 5,
      role: 'assistant:item-limit:deep:a',
    );
    insertMessage(
      id: 'query_plan_item_limit_deep_a_new',
      content: 'eta_limit_deep_a：丙组第二次记录必须保留水纹。',
      offset: 6,
      role: 'assistant:item-limit:deep:a',
    );
    insertMessage(
      id: 'query_plan_item_limit_deep_b_old',
      content: 'theta_limit_deep_b：丁组第一次记录必须保留云台。',
      offset: 7,
      role: 'assistant:item-limit:deep:b',
    );
    insertMessage(
      id: 'query_plan_item_limit_deep_b_new',
      content: 'theta_limit_deep_b：丁组第二次记录必须保留云台。',
      offset: 8,
      role: 'assistant:item-limit:deep:b',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': 'epsilon_limit_get_a',
            'memoryRoles': ['assistant:item-limit:get:a'],
            'limit': 1,
            'orderBy': 'oldest',
            'minSimilarity': 0.8,
          },
          {
            'query': 'zeta_limit_get_b',
            'memoryRoles': ['assistant:item-limit:get:b'],
            'limit': 1,
            'orderBy': 'oldest',
            'minSimilarity': 0.8,
          },
        ],
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {
            '查询': 'eta_limit_deep_a',
            '记忆角色': ['assistant:item-limit:deep:a'],
            '数量': 1,
            '排序': '最旧',
            '相似度阈值': 0.8,
          },
          {
            '查询': 'theta_limit_deep_b',
            '记忆角色': ['assistant:item-limit:deep:b'],
            '数量': 1,
            '排序': '最旧',
            '相似度阈值': 0.8,
          },
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按每个计划项自己的数量限制查记忆',
      autoMode: true,
      family: agentFamilyScript,
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(
      (memoryGetPayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      [
        'query_plan_item_limit_get_a_old',
        'query_plan_item_limit_get_b_old',
      ],
    );

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(
      (deepRetrievePayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      [
        'query_plan_item_limit_deep_a_old',
        'query_plan_item_limit_deep_b_old',
      ],
    );
  });

  test('Agent 记忆：结构化查询计划摘要返回数量互不串味', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.summaryLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '0'],
    );

    void insertSummary({
      required String id,
      required String content,
      required int offset,
      required String role,
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
          agentMemoryTypeSummary,
        ],
      );
    }

    insertSummary(
      id: 'query_plan_summary_a_old',
      content: 'A组旧摘要：青灯策划保留第一版门规。',
      offset: 1,
      role: 'assistant:item-summary:a',
    );
    insertSummary(
      id: 'query_plan_summary_a_new',
      content: 'A组新摘要：青灯策划保留第二版门规。',
      offset: 2,
      role: 'assistant:item-summary:a',
    );
    insertSummary(
      id: 'query_plan_summary_b_old',
      content: 'B组旧摘要：雪桥执行保留第一版低机位。',
      offset: 3,
      role: 'assistant:item-summary:b',
    );
    insertSummary(
      id: 'query_plan_summary_b_new',
      content: 'B组新摘要：雪桥执行保留第二版低机位。',
      offset: 4,
      role: 'assistant:item-summary:b',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '青灯策划',
            'memoryRoles': ['assistant:item-summary:a'],
            'scope': 'summary',
            'limit': 1,
            'orderBy': 'latest',
          },
          {
            'query': '雪桥执行',
            'memoryRoles': ['assistant:item-summary:b'],
            'scope': 'summary',
            'limit': 1,
            'orderBy': 'oldest',
          },
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按每个计划项自己的数量限制查摘要记忆',
      autoMode: true,
      family: agentFamilyScript,
    );

    final msg = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .single;
    expect(msg.toolName, 'memory_get');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(
      (payload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['query_plan_summary_a_new', 'query_plan_summary_b_old'],
    );
    expect(payload['summaries'], [
      'A组新摘要：青灯策划保留第二版门规。',
      'B组旧摘要：雪桥执行保留第一版低机位。',
    ]);
  });

  test('Agent 记忆：结构化查询计划近期对话返回数量互不串味', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.summaryLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertRecent({
      required String id,
      required String content,
      required int offset,
      required String role,
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

    insertRecent(
      id: 'query_plan_recent_a_old',
      content: 'A组旧近期：青灯计划保留第一版门规。',
      offset: 1,
      role: 'assistant:item-recent:a',
    );
    insertRecent(
      id: 'query_plan_recent_a_new',
      content: 'A组新近期：青灯计划改成第二版门规。',
      offset: 2,
      role: 'assistant:item-recent:a',
    );
    insertRecent(
      id: 'query_plan_recent_b_old',
      content: 'B组旧近期：雪桥执行保留第一版低机位。',
      offset: 3,
      role: 'assistant:item-recent:b',
    );
    insertRecent(
      id: 'query_plan_recent_b_new',
      content: 'B组新近期：雪桥执行改成第二版俯拍。',
      offset: 4,
      role: 'assistant:item-recent:b',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '青灯计划',
            'memoryRoles': ['assistant:item-recent:a'],
            'scope': 'conversation',
            'limit': 1,
            'orderBy': 'latest',
          },
          {
            'query': '雪桥执行',
            'memoryRoles': ['assistant:item-recent:b'],
            'scope': 'conversation',
            'limit': 1,
            'orderBy': 'oldest',
          },
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按每个计划项自己的数量限制查近期对话',
      autoMode: true,
      family: agentFamilyScript,
    );

    final msg = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .single;
    expect(msg.toolName, 'memory_get');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['recent'], [
      'A组新近期：青灯计划改成第二版门规。',
      'B组旧近期：雪桥执行保留第一版低机位。',
    ]);
    expect(
      (payload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['query_plan_recent_a_new', 'query_plan_recent_b_old'],
    );
  });

  test('Agent 记忆：结构化查询计划可携带已读记忆排除', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertMessage({
      required String id,
      required String content,
      required int offset,
      required String role,
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
      id: 'query_plan_seen_memory_get_skip',
      content: '已读记忆：青灯排重甲子第一次记录，保留旧镜头。',
      offset: 1,
      role: 'assistant:seen:get',
    );
    insertMessage(
      id: 'query_plan_seen_memory_get_keep',
      content: '未读记忆：青灯排重甲子第二次记录，采用新镜头。',
      offset: 2,
      role: 'assistant:seen:get',
    );
    insertMessage(
      id: 'query_plan_seen_deep_skip',
      content: '已读记忆：雪桥排重乙卯第一次记录，保留旧台词。',
      offset: 3,
      role: 'assistant:seen:deep',
    );
    insertMessage(
      id: 'query_plan_seen_deep_keep',
      content: '未读记忆：雪桥排重乙卯第二次记录，采用新台词。',
      offset: 4,
      role: 'assistant:seen:deep',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '青灯排重甲子',
            'excludeIds': ['query_plan_seen_memory_get_skip'],
            'memoryRoles': ['assistant:seen:get'],
          },
        ],
        'limit': 5,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {
            '查询': '雪桥排重乙卯',
            '已读记忆': ['query_plan_seen_deep_skip'],
            '记忆角色': ['assistant:seen:deep'],
          },
        ],
        'limit': 5,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按计划项里的已读记忆排除重复召回',
      autoMode: true,
      family: agentFamilyScript,
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(
      (memoryGetPayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['query_plan_seen_memory_get_keep'],
    );
    expect(memoryGetPayload['memories'], [
      '未读记忆：青灯排重甲子第二次记录，采用新镜头。',
    ]);

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(
      (deepRetrievePayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['query_plan_seen_deep_keep'],
    );
    expect(deepRetrievePayload['memories'], [
      '未读记忆：雪桥排重乙卯第二次记录，采用新台词。',
    ]);
  });

  test('Agent 记忆：结构化查询计划可携带视觉参考开关', () async {
    final visualId = engine.saveAgentMemory(
      projectId,
      name: '项目视觉参考',
      content: '视觉参考分析：冷白云雾、水墨留白，角色服饰避免高饱和霓虹。',
    );
    engine.saveAgentMemory(
      projectId,
      name: '剧情设定',
      content: '长期设定：第三集必须保留宗门试炼。',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': '下一步导演计划',
            '视觉参考': true,
          },
        ],
        'limit': 5,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {
            '查询': '下一步导演计划',
            '画风参考': true,
          },
        ],
        'limit': 5,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按计划项里的视觉参考开关召回画风记忆',
      autoMode: true,
      family: agentFamilyProduction,
    );

    final toolMessages = engine
        .agentMessages(projectId, family: agentFamilyProduction)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(memoryGetPayload['notes'], [
      '视觉参考分析：冷白云雾、水墨留白，角色服饰避免高饱和霓虹。',
    ]);
    expect(
      memoryGetPayload['records'],
      contains(isA<Map>().having((record) => record['id'], 'id', visualId)),
    );

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(deepRetrievePayload['memories'], [
      '视觉参考分析：冷白云雾、水墨留白，角色服饰避免高饱和霓虹。',
    ]);
    expect(
      deepRetrievePayload['records'],
      contains(isA<Map>().having((record) => record['id'], 'id', visualId)),
    );
  });

  test('Agent 记忆：结构化查询计划视觉参考按项顺序合并', () async {
    final visualId = engine.saveAgentMemory(
      projectId,
      name: '项目视觉参考',
      content: '视觉参考分析：冷白云雾、水墨留白。',
    );
    final ordinaryId = engine.saveAgentMemory(
      projectId,
      name: '剧情长期设定',
      content: '长期设定：xi_ordinary_second 第三集必须保留宗门试炼。',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': 'visual_plan_slot',
            '视觉参考': true,
            'scope': 'long_term',
            'minSimilarity': 0.8,
          },
          {
            'query': 'xi_ordinary_second',
            'scope': 'long_term',
            'minSimilarity': 0.8,
          },
        ],
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {
            '查询': 'visual_plan_slot',
            '画风参考': true,
            '范围': '长期记忆',
            '相似度阈值': 0.8,
          },
          {
            '查询': 'xi_ordinary_second',
            '范围': '长期记忆',
            '相似度阈值': 0.8,
          },
        ],
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按计划项顺序召回视觉参考和长期设定',
      autoMode: true,
      family: agentFamilyProduction,
    );

    final toolMessages = engine
        .agentMessages(projectId, family: agentFamilyProduction)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(
      (memoryGetPayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      [visualId, ordinaryId],
    );
    expect(memoryGetPayload['notes'], [
      '视觉参考分析：冷白云雾、水墨留白。',
      '长期设定：xi_ordinary_second 第三集必须保留宗门试炼。',
    ]);

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(
      (deepRetrievePayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      [visualId, ordinaryId],
    );
    expect(deepRetrievePayload['memories'], [
      '视觉参考分析：冷白云雾、水墨留白。',
      '长期设定：xi_ordinary_second 第三集必须保留宗门试炼。',
    ]);
  });

  test('Agent 记忆：结构化查询计划可在 queries 包裹项里携带过滤', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertMessage({
      required String id,
      required String content,
      required int offset,
      required String role,
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
      id: 'query_plan_wrapped_get_keep',
      content: '执行层记忆：星门封印甲子必须使用冷白逆光。',
      offset: 1,
      role: 'assistant:wrapped:get',
    );
    insertMessage(
      id: 'query_plan_wrapped_get_noise',
      content: '噪声记忆：星门封印甲子可以使用暖色喜剧光。',
      offset: 2,
      role: agentRoleUser,
    );
    insertMessage(
      id: 'query_plan_wrapped_deep_keep',
      content: '执行层记忆：云桥试炼乙卯必须保留低机位压迫感。',
      offset: 3,
      role: 'assistant:wrapped:deep',
    );
    insertMessage(
      id: 'query_plan_wrapped_deep_noise',
      content: '噪声记忆：云桥试炼乙卯可以删除低机位。',
      offset: 4,
      role: agentRoleUser,
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': {
          'queries': [
            {
              'query': '星门封印甲子',
              'memoryRoles': ['assistant:wrapped:get'],
              'limit': 1,
            },
          ],
        },
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': {
          'queries': [
            {
              '查询': '云桥试炼乙卯',
              '记忆角色': ['assistant:wrapped:deep'],
              '数量': 1,
            },
          ],
        },
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按 queries 包裹的计划项过滤执行层记忆',
      autoMode: true,
      family: agentFamilyScript,
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(
      (memoryGetPayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['query_plan_wrapped_get_keep'],
    );
    expect(memoryGetPayload['memories'], [
      '执行层记忆：星门封印甲子必须使用冷白逆光。',
    ]);

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(
      (deepRetrievePayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['query_plan_wrapped_deep_keep'],
    );
    expect(deepRetrievePayload['memories'], [
      '执行层记忆：云桥试炼乙卯必须保留低机位压迫感。',
    ]);
  });

  test('Agent 记忆：结构化查询计划多项过滤互不串味', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '4'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );

    void insertMessage({
      required String id,
      required String content,
      required int offset,
      required String role,
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
      id: 'query_plan_item_get_a_keep',
      content: 'alpha_blue_artifact：青霜道具必须发蓝光。',
      offset: 1,
      role: 'assistant:item:get:a',
    );
    insertMessage(
      id: 'query_plan_item_get_a_noise',
      content: 'alpha_blue_artifact 噪声：青霜道具可以发红光。',
      offset: 2,
      role: 'assistant:item:get:b',
    );
    insertMessage(
      id: 'query_plan_item_get_b_keep',
      content: 'beta_fog_gate：玄门场景必须保留雾门。',
      offset: 3,
      role: 'assistant:item:get:b',
    );
    insertMessage(
      id: 'query_plan_item_get_b_noise',
      content: 'beta_fog_gate 噪声：玄门场景可以改晴天。',
      offset: 4,
      role: 'assistant:item:get:a',
    );
    insertMessage(
      id: 'query_plan_item_deep_a_keep',
      content: 'gamma_water_array：龙舟阵法必须保留青色水纹。',
      offset: 5,
      role: 'assistant:item:deep:a',
    );
    insertMessage(
      id: 'query_plan_item_deep_a_noise',
      content: 'gamma_water_array 噪声：龙舟阵法可以改成火纹。',
      offset: 6,
      role: 'assistant:item:deep:b',
    );
    insertMessage(
      id: 'query_plan_item_deep_b_keep',
      content: 'delta_cloud_ritual：云台礼法必须保留三拜。',
      offset: 7,
      role: 'assistant:item:deep:b',
    );
    insertMessage(
      id: 'query_plan_item_deep_b_noise',
      content: 'delta_cloud_ritual 噪声：云台礼法可以删掉三拜。',
      offset: 8,
      role: 'assistant:item:deep:a',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'queryPlan': [
          {
            'query': 'alpha_blue_artifact',
            'memoryRoles': ['assistant:item:get:a'],
            'minSimilarity': 0.8,
          },
          {
            'query': 'beta_fog_gate',
            'memoryRoles': ['assistant:item:get:b'],
            'minSimilarity': 0.8,
          },
        ],
        'limit': 6,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        '检索计划': [
          {
            '查询': 'gamma_water_array',
            '记忆角色': ['assistant:item:deep:a'],
            '相似度阈值': 0.8,
          },
          {
            '查询': 'delta_cloud_ritual',
            '记忆角色': ['assistant:item:deep:b'],
            '相似度阈值': 0.8,
          },
        ],
        'limit': 6,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按每个计划项自己的角色过滤查记忆',
      autoMode: true,
      family: agentFamilyScript,
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    final memoryGetRecordIds = [
      for (final record in memoryGetPayload['records'] as List)
        (record as Map<String, dynamic>)['id'],
    ];
    expect(
      memoryGetRecordIds,
      containsAll(['query_plan_item_get_a_keep', 'query_plan_item_get_b_keep']),
    );
    expect(memoryGetRecordIds, isNot(contains('query_plan_item_get_a_noise')));
    expect(memoryGetRecordIds, isNot(contains('query_plan_item_get_b_noise')));

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    final deepRetrieveRecordIds = [
      for (final record in deepRetrievePayload['records'] as List)
        (record as Map<String, dynamic>)['id'],
    ];
    expect(
      deepRetrieveRecordIds,
      containsAll(
          ['query_plan_item_deep_a_keep', 'query_plan_item_deep_b_keep']),
    );
    expect(
        deepRetrieveRecordIds, isNot(contains('query_plan_item_deep_a_noise')));
    expect(
        deepRetrieveRecordIds, isNot(contains('query_plan_item_deep_b_noise')));
  });

  test('Agent 记忆工具可显式召回视觉参考长期记忆', () async {
    final visualId = engine.saveAgentMemory(
      projectId,
      name: '项目视觉参考',
      content: '视觉参考分析：冷白水墨、低饱和云雾留白，人物服饰避免高饱和霓虹。',
    );
    engine.saveAgentMemory(
      projectId,
      name: '剧情设定',
      content: '长期设定：第二集必须保留宗门试炼，不直接进入大战。',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'query': '下一步导演计划',
        'includeVisualReferences': true,
        'limit': 5,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '取出视觉参考辅助导演计划',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final memoryGetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final memoryGetProperties = memoryGetTool.schema['properties'] as Map;
    expect(
      memoryGetProperties.keys,
      containsAll([
        'includeVisualReferences',
        'visualReferences',
        'include_visual_references',
        'visual_references',
        '包含视觉参考',
        '视觉参考',
      ]),
    );

    final memoryGetMsg =
        engine.agentMessages(projectId, family: agentFamilyProduction).last;
    expect(memoryGetMsg.toolName, 'memory_get');
    final memoryGetPayload =
        jsonDecode(memoryGetMsg.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(
      memoryGetPayload['notes'],
      contains('视觉参考分析：冷白水墨、低饱和云雾留白，人物服饰避免高饱和霓虹。'),
    );
    expect(
      memoryGetPayload['records'],
      contains(isA<Map>().having((record) => record['id'], 'id', visualId)),
    );

    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'keyword': '下一步导演计划',
        'visualReferences': true,
        'limit': 5,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '深度召回视觉参考辅助导演计划',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final deepRetrieveProperties = deepRetrieveTool.schema['properties'] as Map;
    expect(
      deepRetrieveProperties.keys,
      containsAll([
        'includeVisualReferences',
        'visualReferences',
        'include_visual_references',
        'visual_references',
        '包含视觉参考',
        '视觉参考',
      ]),
    );

    final deepRetrieveMsg =
        engine.agentMessages(projectId, family: agentFamilyProduction).last;
    expect(deepRetrieveMsg.toolName, 'deepRetrieve');
    final deepRetrievePayload =
        jsonDecode(deepRetrieveMsg.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(
      deepRetrievePayload['memories'],
      contains('视觉参考分析：冷白水墨、低饱和云雾留白，人物服饰避免高饱和霓虹。'),
    );
    expect(
      deepRetrievePayload['records'],
      contains(isA<Map>().having((record) => record['id'], 'id', visualId)),
    );
  });

  test('Agent 记忆：memory_get 工具支持中文查询和范围别名', () async {
    final noteId = engine.saveAgentMemory(
      projectId,
      name: '寒山视觉',
      content: '长期设定：寒山山门保持冷白色调。',
    );
    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        '查询': '寒山山门色调',
        '记忆范围': '长期记忆',
        '数量': 1,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '用中文参数查长期记忆',
      autoMode: false,
    );

    final tool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final properties = tool.schema['properties'] as Map;
    expect(properties, contains('查询'));
    expect(properties, contains('数量'));
    expect(properties, contains('记忆范围'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'memory_get');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['notes'], ['长期设定：寒山山门保持冷白色调。']);
    final records = payload['records'] as List;
    expect(
      records.single,
      isA<Map>()
          .having((record) => record['id'], 'id', noteId)
          .having((record) => record['scope'], 'scope', 'long_term'),
    );
  });

  test('Agent 记忆：memory_get 工具支持 long_term scope 返回长期 note', () async {
    final noteId = engine.saveAgentMemory(
      projectId,
      name: '角色随身物',
      content: '长期设定：李澈佩戴青玉扳指，入山前不能摘下。',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'memory_get_long_term_chat_noise',
        '',
        '普通聊天噪声：李澈青玉扳指只是误传。',
        now,
        embeddingJson('普通聊天噪声：李澈青玉扳指只是误传。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        1,
        agentMemoryTypeMessage,
      ],
    );
    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'query': '李澈青玉扳指',
        'scope': 'long_term',
        'limit': 5,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只查长期设定里的李澈随身物',
      autoMode: false,
    );

    final tool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final properties = tool.schema['properties'] as Map;
    expect(properties, contains('scope'));
    expect(properties, contains('memoryType'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'memory_get');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], isEmpty);
    expect(payload['summaries'], isEmpty);
    expect(payload['recent'], isEmpty);
    expect(payload['notes'], ['长期设定：李澈佩戴青玉扳指，入山前不能摘下。']);
    final records = payload['records'] as List;
    expect(records, hasLength(1));
    expect(
      records.single,
      isA<Map>()
          .having((record) => record['id'], 'id', noteId)
          .having((record) => record['type'], 'type', agentMemoryTypeNote)
          .having((record) => record['scope'], 'scope', 'long_term')
          .having(
              (record) => record['content'], 'content', contains('李澈佩戴青玉扳指')),
    );
  });

  test('Agent 记忆：memory_get 工具支持 memoryType=long_term 别名', () async {
    final noteId = engine.saveAgentMemory(
      projectId,
      name: '角色信物',
      content: '长期设定：沈微持有霜纹玉佩，关键反转前不能遗失。',
    );
    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'query': '沈微霜纹玉佩',
        'memoryType': 'long_term',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按 memoryType 查长期设定',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['notes'], ['长期设定：沈微持有霜纹玉佩，关键反转前不能遗失。']);
    final records = payload['records'] as List;
    expect(
      records.single,
      isA<Map>()
          .having((record) => record['id'], 'id', noteId)
          .having((record) => record['scope'], 'scope', 'long_term'),
    );
  });

  test('Agent 记忆：memory_add 工具写入普通 message 记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    gateway.turns = [
      AgentTurnResult.tool('memory_add', const {
        'role': agentRoleUser,
        'name': '用户约束',
        'content': '用户明确要求：李澈不能黑化，第三集必须救沈微。',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '把这个用户约束写进记忆',
      autoMode: false,
    );

    final tool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_add');
    final properties = tool.schema['properties'] as Map;
    expect(properties, contains('content'));
    expect(properties, contains('role'));
    expect(properties, contains('scope'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'memory_add');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['saved'], isTrue);
    expect(payload['type'], agentMemoryTypeMessage);
    expect(payload['scope'], 'conversation');
    final memoryId = payload['id'] as String;
    expect(memoryId, isNotEmpty);

    final row = db.select(
      'SELECT id,name,content,role,type,summarized FROM memories '
      'WHERE id=? AND isolationKey=?',
      [memoryId, 'scriptAgent:$projectId'],
    ).single;
    expect(row['name'], '用户约束');
    expect(row['content'], '用户明确要求：李澈不能黑化，第三集必须救沈微。');
    expect(row['role'], agentRoleUser);
    expect(row['type'], agentMemoryTypeMessage);
    expect(row['summarized'], 0);
  });

  test('Agent 记忆：memory_add schema 暴露模型常见字段别名', () async {
    gateway.turns = [const AgentTurnResult.text('收到')];

    await engine.sendAgentMessage(
      projectId,
      '查看 memory_add 参数',
      autoMode: false,
    );

    final tool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_add');
    final properties = tool.schema['properties'] as Map;
    expect(
      properties.keys,
      containsAll([
        'message',
        'prompt',
        'input',
        'value',
        'label',
        'memoryName',
        'memory_name',
        'memoryRole',
        'memory_role',
        'authorRole',
        'author_role',
        'memoryScope',
        'memory_scope',
        'createdAt',
        'created_at',
        'timestamp',
        'time',
      ]),
    );
  });

  test('Agent 记忆：memory_add 工具支持模型常见字段别名写入普通记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    gateway.turns = [
      AgentTurnResult.tool('memory_add', const {
        'message': '执行记忆：第三集结尾保留断剑伏笔。',
        'memoryName': '执行线索',
        'memory_role': 'assistant:execution:script',
        'memory_scope': 'conversation',
        'createdAt': 123456,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '把执行线索写进普通记忆',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.toolName, 'memory_add');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['saved'], isTrue);
    expect(payload['type'], agentMemoryTypeMessage);
    final row = db.select(
      'SELECT name,content,role,type,createTime FROM memories '
      'WHERE id=? AND isolationKey=?',
      [payload['id'], 'scriptAgent:$projectId'],
    ).single;
    expect(row['name'], '执行线索');
    expect(row['content'], '执行记忆：第三集结尾保留断剑伏笔。');
    expect(row['role'], 'assistant:execution:script');
    expect(row['type'], agentMemoryTypeMessage);
    expect(row['createTime'], 123456);
  });

  test('Agent 记忆：memory_add 工具支持中文字段写入长期记忆', () async {
    gateway.turns = [
      AgentTurnResult.tool('memory_add', const {
        '内容': '长期设定：李澈不能主动滥杀。',
        '记忆名称': '角色禁忌',
        '记忆范围': '长期记忆',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '用中文参数写长期记忆',
      autoMode: false,
    );

    final tool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_add');
    final properties = tool.schema['properties'] as Map;
    expect(properties, contains('内容'));
    expect(properties, contains('记忆名称'));
    expect(properties, contains('记忆范围'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.toolName, 'memory_add');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['saved'], isTrue);
    expect(payload['type'], agentMemoryTypeNote);
    expect(payload['scope'], 'long_term');
    expect(payload['name'], '角色禁忌');
    expect(payload['content'], '长期设定：李澈不能主动滥杀。');

    final longTerm = engine.agentLongTermMemories(projectId);
    expect(
        longTerm.singleWhere((item) => item.id == payload['id']).name, '角色禁忌');
    expect(
      longTerm.singleWhere((item) => item.id == payload['id']).content,
      '长期设定：李澈不能主动滥杀。',
    );
  });

  test('Agent 记忆：memory_add 工具支持 long_term scope 写入长期 note', () async {
    gateway.turns = [
      AgentTurnResult.tool('memory_add', const {
        'scope': 'long_term',
        'name': '角色底线',
        'content': '长期设定：沈微不能背叛李澈，只能被误会。',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '把角色底线写到长期记忆',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.toolName, 'memory_add');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['saved'], isTrue);
    expect(payload['type'], agentMemoryTypeNote);
    expect(payload['scope'], 'long_term');
    final memoryId = payload['id'] as String;

    final longTerm = engine.agentLongTermMemories(projectId);
    expect(longTerm.map((item) => item.id), contains(memoryId));
    expect(longTerm.singleWhere((item) => item.id == memoryId).content,
        '长期设定：沈微不能背叛李澈，只能被误会。');
  });

  test('Agent 记忆：memory_add 工具支持 conversation scope 别名写入 message', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    gateway.turns = [
      AgentTurnResult.tool('memory_add', const {
        'scope': 'conversation',
        'content': '执行决策：第二集结尾保留寒山钟声伏笔。',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '把执行决策写进普通记忆',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.toolName, 'memory_add');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['saved'], isTrue);
    expect(payload['type'], agentMemoryTypeMessage);
    expect(payload['scope'], 'conversation');

    final rows = db.select(
      'SELECT content,type FROM memories WHERE id=? AND isolationKey=?',
      [payload['id'], 'scriptAgent:$projectId'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['content'], '执行决策：第二集结尾保留寒山钟声伏笔。');
    expect(rows.single['type'], agentMemoryTypeMessage);
  });

  test('Agent 记忆：memory_clear 工具按 scope 清理当前 Agent 家族', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'clear_tool_script_msg',
        '',
        '剧本侧待恢复消息。',
        now,
        embeddingJson('剧本侧待恢复消息。'),
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
        'clear_tool_script_summary',
        '剧本摘要',
        '剧本侧摘要。',
        now + 1,
        embeddingJson('剧本侧摘要。'),
        'scriptAgent:$projectId',
        jsonEncode(['clear_tool_script_msg']),
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
        'clear_tool_production_summary',
        '制作摘要',
        '制作侧摘要。',
        now + 2,
        embeddingJson('制作侧摘要。'),
        'productionAgent:$projectId',
        '[]',
        agentRoleAssistant,
        0,
        agentMemoryTypeSummary,
      ],
    );
    final noteId = engine.saveAgentMemory(
      projectId,
      name: '长期设定',
      content: '长期设定：李澈不能黑化。',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_clear', const {
        'scope': 'summary',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '清理剧本摘要记忆',
      autoMode: false,
      family: agentFamilyScript,
    );

    final tool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_clear');
    final properties = tool.schema['properties'] as Map;
    expect(properties, contains('scope'));
    expect(properties, contains('memoryScope'));
    expect(properties, contains('记忆范围'));

    final summaryPayload =
        jsonDecode(engine.agentMessages(projectId).last.content)
            as Map<String, dynamic>;
    expect(summaryPayload['cleared'], isTrue);
    expect(summaryPayload['scope'], agentMemoryTypeSummary);
    expect(summaryPayload['family'], agentFamilyScript);
    expect(summaryPayload['target'], 'conversation');

    expect(
      db.select(
          'SELECT id FROM memories WHERE id=?', ['clear_tool_script_summary']),
      isEmpty,
    );
    expect(
      db.select(
        'SELECT summarized FROM memories WHERE id=?',
        ['clear_tool_script_msg'],
      ).single['summarized'],
      0,
    );
    expect(
      db.select('SELECT id FROM memories WHERE id=?',
          ['clear_tool_production_summary']),
      hasLength(1),
    );
    expect(engine.agentLongTermMemories(projectId).map((item) => item.id),
        contains(noteId));

    gateway.turns = [
      AgentTurnResult.tool('memory_clear', const {
        '记忆范围': '长期记忆',
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '清理长期记忆',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final notePayload = jsonDecode(
      engine
          .agentMessages(projectId, family: agentFamilyProduction)
          .last
          .content,
    ) as Map<String, dynamic>;
    expect(notePayload['cleared'], isTrue);
    expect(notePayload['scope'], agentMemoryTypeNote);
    expect(notePayload['target'], 'long_term');
    expect(engine.agentLongTermMemories(projectId), isEmpty);
    expect(
      db.select('SELECT id FROM memories WHERE id=?',
          ['clear_tool_production_summary']),
      hasLength(1),
    );
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

  test('Agent 记忆：deepRetrieve 工具支持 minScore 过滤弱相关记忆', () async {
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
          'message',
        ],
      );
    }

    insertMessage('score_msg_high', '用户明确要求：李澈正派设定必须保留，不能反派化。', 0);
    insertMessage('score_msg_low', '用户补充：李澈来自寒山宗门。', 1);

    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'query': '李澈正派设定',
        'minScore': 80,
      }),
    ];

    await engine.sendAgentMessage(projectId, '找高置信的李澈设定', autoMode: false);

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = deepRetrieveTool.schema['properties'] as Map;
    expect(properties, contains('minScore'));
    expect(properties, contains('scoreThreshold'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], contains('用户明确要求：李澈正派设定必须保留，不能反派化。'));
    expect(payload['memories'], isNot(contains('用户补充：李澈来自寒山宗门。')));
  });

  test('Agent 记忆：memory_get 和 deepRetrieve 工具支持相似度阈值别名', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
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
          agentRoleAssistant,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage('similarity_high', '用户明确要求：李澈正派设定必须保留，不能反派化。', 0);
    insertMessage('similarity_low', '用户补充：李澈来自寒山宗门。', 1);

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'query': '李澈正派设定',
        'minSimilarity': 0.8,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        'query': '李澈正派设定',
        '相似度阈值': '0.8',
      }),
      AgentTurnResult.tool('memory_get', const {
        'query': '李澈正派设定',
        'threshold': 0.8,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '找相似度足够高的李澈设定',
      autoMode: true,
    );

    final memoryGetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final memoryGetProperties = memoryGetTool.schema['properties'] as Map;
    expect(
      memoryGetProperties.keys,
      containsAll([
        'minSimilarity',
        'min_similarity',
        'similarityThreshold',
        '相似度阈值',
      ]),
    );
    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final deepRetrieveProperties = deepRetrieveTool.schema['properties'] as Map;
    expect(
      deepRetrieveProperties.keys,
      containsAll([
        'minSimilarity',
        'min_similarity',
        'similarityThreshold',
        '相似度阈值',
      ]),
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve', 'memory_get']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(
      memoryGetPayload['memories'],
      contains('用户明确要求：李澈正派设定必须保留，不能反派化。'),
    );
    expect(
      memoryGetPayload['memories'],
      isNot(contains('用户补充：李澈来自寒山宗门。')),
    );

    final deepRetrievePayload =
        jsonDecode(toolMessages[1].content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(
      deepRetrievePayload['memories'],
      contains('用户明确要求：李澈正派设定必须保留，不能反派化。'),
    );
    expect(
      deepRetrievePayload['memories'],
      isNot(contains('用户补充：李澈来自寒山宗门。')),
    );

    final thresholdPayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(thresholdPayload['found'], isTrue);
    expect(
      thresholdPayload['memories'],
      contains('用户明确要求：李澈正派设定必须保留，不能反派化。'),
    );
    expect(
      thresholdPayload['memories'],
      isNot(contains('用户补充：李澈来自寒山宗门。')),
    );
  });

  test('Agent 记忆：deepRetrieve 工具支持 topK/maxResults 自然数量别名', () async {
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
          'message',
        ],
      );
    }

    insertMessage('topk_msg_old', '旧制作记忆：寒山雪夜需要低机位压迫感。', 0);
    insertMessage('topk_msg_mid', '中段制作记忆：寒山山门镜头需要蓝灰冷色。', 1);
    insertMessage('topk_msg_new', '最新制作记忆：寒山首帧优先角色正脸。', 2);

    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'query': '寒山制作记忆',
        'topK': 2,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '找两条寒山制作记忆',
      autoMode: false,
      family: agentFamilyScript,
    );

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = deepRetrieveTool.schema['properties'] as Map;
    expect(properties, contains('topK'));
    expect(properties, contains('top_k'));
    expect(properties, contains('maxResults'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], isA<List>());
    expect(payload['memories'], hasLength(2));
    expect(
      (payload['memories'] as List).join('\n'),
      contains('寒山'),
    );
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

  test('Agent 记忆：deepRetrieve 工具支持 queries 多查询合并召回', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
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
          agentRoleUser,
          0,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage('multi_query_role', '角色约束：李澈必须保持正派，不能反派化。', 0);
    insertMessage('multi_query_scene', '场景画风：寒山山门保持冷白云雾和低机位压迫感。', 1);
    insertMessage('multi_query_noise', '噪声记忆：市集喜剧桥段可以更热闹。', 2);

    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'queries': ['李澈正派约束', '寒山山门冷白低机位'],
        'limit': 4,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '同时找角色约束和场景画风',
      autoMode: false,
    );

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = deepRetrieveTool.schema['properties'] as Map;
    expect(properties, contains('queries'));
    expect(properties, contains('queryList'));
    expect(properties, contains('keywords'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['queries'], ['李澈正派约束', '寒山山门冷白低机位']);
    expect(payload['memories'], contains('角色约束：李澈必须保持正派，不能反派化。'));
    expect(payload['memories'], contains('场景画风：寒山山门保持冷白云雾和低机位压迫感。'));
    expect(payload['memories'], isNot(contains('噪声记忆：市集喜剧桥段可以更热闹。')));
    final recordIds = [
      for (final record in payload['records'] as List)
        (record as Map)['id'] as String,
    ];
    expect(recordIds, containsAll(['multi_query_role', 'multi_query_scene']));
    expect(recordIds.toSet(), hasLength(recordIds.length));
  });

  test('Agent 记忆：deepRetrieve 未命中时返回查询列表便于多 Agent 审计', () async {
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'queryPlan': [
          {'query': '李澈正派约束'},
          {'query': '寒山山门冷白低机位'},
        ],
        'limit': 3,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '查一下还没写入的角色和场景记忆',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isFalse);
    expect(payload['message'], '未找到相关记忆');
    expect(payload['queries'], ['李澈正派约束', '寒山山门冷白低机位']);
  });

  test('Agent 记忆：deepRetrieve schema 暴露模型常见 RAG 字段别名', () async {
    gateway.turns = [const AgentTurnResult.text('收到')];

    await engine.sendAgentMessage(
      projectId,
      '查看 deepRetrieve 参数',
      autoMode: false,
    );

    final tool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = tool.schema['properties'] as Map;
    expect(
      properties.keys,
      containsAll([
        'q',
        'max',
        'count',
        'min_score',
        'minimumScore',
        'minimum_score',
        'threshold',
        'memoryRoles',
        'memory_roles',
        'memoryScope',
        'memory_scope',
        'excludedRoles',
        'excluded_roles',
        'excludeMemoryRoles',
        'exclude_memory_roles',
        'excludedMemoryRoles',
        'excluded_memory_roles',
        'excludeId',
        'seenIds',
        'readIds',
        'previousMemoryIds',
        'previousRecords',
      ]),
    );
  });

  test('Agent 记忆：deepRetrieve 工具支持 q 和 memory_roles 别名', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    void insertMessage({
      required String id,
      required String content,
      required int offset,
      required String role,
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
      id: 'deep_alias_user',
      content: '用户记录寒山伏笔：李澈先隐藏断剑。',
      offset: 0,
      role: agentRoleUser,
    );
    insertMessage(
      id: 'deep_alias_execution',
      content: '执行层记录寒山伏笔：第三集结尾露出断剑。',
      offset: 1,
      role: 'assistant:execution:script',
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'q': '寒山伏笔',
        'memory_roles': ['assistant:execution:script'],
        'memory_scope': 'conversation',
        'count': 1,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '深度找执行层寒山伏笔',
      autoMode: false,
    );

    final msg = engine.agentMessages(projectId).last;
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    final records = payload['records'] as List;
    expect(records, isNotEmpty);
    expect(
      records,
      everyElement(
        isA<Map>().having(
          (record) => record['role'],
          'role',
          'assistant:execution:script',
        ),
      ),
    );
  });

  test('Agent 记忆：deepRetrieve 工具支持中文查询和范围别名', () async {
    final noteId = engine.saveAgentMemory(
      projectId,
      name: '寒山分镜约束',
      content: '长期设定：寒山飞行镜头要保持冷白雾气。',
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        '查询': '寒山飞行镜头',
        '记忆范围': '长期记忆',
        '数量': 1,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '用中文参数深度找寒山飞行设定',
      autoMode: false,
    );

    final tool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = tool.schema['properties'] as Map;
    expect(properties, contains('查询'));
    expect(properties, contains('数量'));
    expect(properties, contains('记忆范围'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], ['长期设定：寒山飞行镜头要保持冷白雾气。']);
    final records = payload['records'] as List;
    expect(
      records.single,
      isA<Map>()
          .having((record) => record['id'], 'id', noteId)
          .having((record) => record['scope'], 'scope', 'long_term'),
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

  test('Agent 记忆：deepRetrieve 工具支持 memoryType=all 召回全部层级', () async {
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
        'memory_type_all_message',
        '',
        '历史对话：用户强调李澈必须保持正派，不能被塑造成反派。',
        now,
        embeddingJson('历史对话：用户强调李澈必须保持正派，不能被塑造成反派。'),
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
        'memoryType': 'all',
        'limit': 2,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按 memoryType 召回全部记忆层级',
      autoMode: false,
      family: agentFamilyScript,
    );

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = deepRetrieveTool.schema['properties'] as Map;
    expect(properties, contains('memoryType'));
    expect(properties, contains('memoryTypes'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    final records = (payload['records'] as List)
        .cast<Map>()
        .map((record) => record.cast<String, dynamic>())
        .toList();
    expect(records.map((record) => record['id']), contains(noteId));
    expect(records.map((record) => record['id']),
        contains('memory_type_all_message'));
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

  test('Agent 记忆：deepRetrieve 工具支持 seenMemoryIds 等已读别名', () async {
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
      'alias_keep_memory',
      '新记忆：寒山禁忌还包括沈微不能黑化。',
      0,
    );
    insertMessage(
      'alias_seen_memory',
      '已读记忆：寒山禁忌是李澈不能滥杀。',
      1,
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        'query': '寒山禁忌',
        'seenMemoryIds': ['alias_seen_memory'],
        'topK': 1,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '继续找还没读过的寒山禁忌记忆',
      autoMode: false,
      family: agentFamilyScript,
    );

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = deepRetrieveTool.schema['properties'] as Map;
    expect(properties, contains('seenMemoryIds'));
    expect(properties, contains('memoryIds'));
    expect(properties, contains('readMemoryIds'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], ['新记忆：寒山禁忌还包括沈微不能黑化。']);
    final records = payload['records'] as List;
    expect(records, hasLength(1));
    expect((records.single as Map<String, dynamic>)['id'], 'alias_keep_memory');
  });

  test('Agent 记忆：deepRetrieve 工具支持中文已读和排除角色别名', () async {
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
      id: 'cn_seen_memory',
      content: '已读记忆：寒山禁忌 寒山禁忌 是李澈不能滥杀。',
      role: agentRoleAssistant,
      offset: 0,
    );
    insertMessage(
      id: 'cn_tool_noise_memory',
      content: '工具审计：寒山禁忌 寒山禁忌 已经写入查询日志。',
      role: 'assistant:decision:tool',
      offset: 1,
    );
    insertMessage(
      id: 'cn_keep_memory',
      content: '新记忆：寒山禁忌还包括沈微不能黑化。',
      role: agentRoleUser,
      offset: 2,
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', const {
        '查询': '寒山禁忌',
        '已读记忆': ['cn_seen_memory'],
        '排除角色': ['assistant:decision:tool'],
        '数量': 2,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '继续用中文参数找还没读过的寒山禁忌记忆',
      autoMode: false,
      family: agentFamilyScript,
    );

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = deepRetrieveTool.schema['properties'] as Map;
    expect(properties, contains('已读记忆'));
    expect(properties, contains('排除角色'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], ['新记忆：寒山禁忌还包括沈微不能黑化。']);
    final records = payload['records'] as List;
    expect(records, hasLength(1));
    expect((records.single as Map<String, dynamic>)['id'], 'cn_keep_memory');
  });

  test('Agent 记忆：deepRetrieve 工具支持 records 字段排除已读记忆', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final keepId = engine.saveAgentMemory(
      projectId,
      name: '角色补充',
      content: '长期设定：李澈需要保护沈微，不能让沈微黑化。',
    );
    final seenId = engine.saveAgentMemory(
      projectId,
      name: '角色禁忌',
      content: '长期设定：李澈滥杀 李澈滥杀 是严禁的。',
    );
    gateway.turns = [
      AgentTurnResult.tool('deepRetrieve', {
        'query': '李澈滥杀',
        'scope': 'long_term',
        'records': [
          {
            'id': seenId,
            'type': 'note',
            'scope': 'long_term',
            'content': '长期设定：李澈滥杀 李澈滥杀 是严禁的。',
          },
        ],
        'topK': 1,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '继续找还没读过的李澈禁忌记忆',
      autoMode: false,
      family: agentFamilyScript,
    );

    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final properties = deepRetrieveTool.schema['properties'] as Map;
    expect(properties, contains('records'));
    expect(properties, contains('seenRecords'));
    expect(properties, contains('readRecords'));

    final msg = engine.agentMessages(projectId).last;
    expect(msg.role, agentRoleTool);
    expect(msg.toolName, 'deepRetrieve');
    final payload = jsonDecode(msg.content) as Map<String, dynamic>;
    expect(payload['found'], isTrue);
    expect(payload['memories'], ['长期设定：李澈需要保护沈微，不能让沈微黑化。']);
    final records = payload['records'] as List;
    expect(records, hasLength(1));
    expect((records.single as Map<String, dynamic>)['id'], keepId);
  });

  test('Agent 记忆：memory_get 和 deepRetrieve 工具支持时间窗口别名', () async {
    const baseTime = 1000000000;
    void insertMemory({
      required String id,
      required String isolationKey,
      required String content,
      required int createTime,
      required String type,
      String name = '',
      String role = agentRoleUser,
      int summarized = 0,
      List<String> relatedMessageIds = const [],
    }) {
      db.execute(
        'INSERT INTO memories '
        '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          name,
          content,
          createTime,
          embeddingJson(content),
          isolationKey,
          jsonEncode(relatedMessageIds),
          role,
          summarized,
          type,
        ],
      );
    }

    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.summaryLimit', '5'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '5'],
    );
    insertMemory(
      id: 'time_old_msg',
      isolationKey: 'scriptAgent:$projectId',
      content: '窗口外旧记忆：李澈正派设定来自寒山。',
      createTime: baseTime,
      type: agentMemoryTypeMessage,
      summarized: 1,
    );
    insertMemory(
      id: 'time_keep_msg',
      isolationKey: 'scriptAgent:$projectId',
      content: '窗口内记忆：李澈正派设定来自寒山戒律。',
      createTime: baseTime + 1000,
      type: agentMemoryTypeMessage,
      summarized: 1,
    );
    insertMemory(
      id: 'time_new_recent',
      isolationKey: 'scriptAgent:$projectId',
      content: '窗口外新近记忆：李澈正派设定已经用于最新分镜。',
      createTime: baseTime + 2000,
      type: agentMemoryTypeMessage,
    );
    insertMemory(
      id: 'time_keep_summary',
      isolationKey: 'scriptAgent:$projectId',
      content: '窗口内摘要：李澈正派设定已经锁定。',
      createTime: baseTime + 1100,
      type: agentMemoryTypeSummary,
      name: '窗口摘要',
      role: agentRoleAssistant,
      relatedMessageIds: const ['time_keep_msg'],
    );
    insertMemory(
      id: 'time_old_note',
      isolationKey: 'project:$projectId',
      content: '窗口外旧长期记忆：沈微护送路线走山门。',
      createTime: baseTime,
      type: agentMemoryTypeNote,
      name: '旧护送路线',
    );
    insertMemory(
      id: 'time_keep_note',
      isolationKey: 'project:$projectId',
      content: '窗口内长期记忆：沈微护送路线必须经过镜湖。',
      createTime: baseTime + 1000,
      type: agentMemoryTypeNote,
      name: '镜湖护送路线',
    );
    insertMemory(
      id: 'time_new_note',
      isolationKey: 'project:$projectId',
      content: '窗口外新长期记忆：沈微护送路线改为雪桥。',
      createTime: baseTime + 2000,
      type: agentMemoryTypeNote,
      name: '雪桥护送路线',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'query': '李澈正派设定',
        'createdAfter': baseTime + 500,
        'createdBefore': baseTime + 1500,
        'limit': 5,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        'query': '沈微护送路线',
        'scope': 'long_term',
        'since': baseTime + 500,
        'until': baseTime + 1500,
        'limit': 5,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按时间窗口召回李澈和沈微设定',
      autoMode: true,
      family: agentFamilyScript,
    );

    final memoryGetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final memoryGetProperties = memoryGetTool.schema['properties'] as Map;
    expect(
      memoryGetProperties.keys,
      containsAll(['createdAfter', 'createdBefore', 'since', 'until', '开始时间']),
    );
    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final deepRetrieveProperties = deepRetrieveTool.schema['properties'] as Map;
    expect(
      deepRetrieveProperties.keys,
      containsAll(['createdAfter', 'createdBefore', 'since', 'until', '结束时间']),
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(memoryGetPayload['memories'], ['窗口内记忆：李澈正派设定来自寒山戒律。']);
    expect(memoryGetPayload['summaries'], ['窗口内摘要：李澈正派设定已经锁定。']);
    expect(memoryGetPayload['recent'], isEmpty);
    expect(
      (memoryGetPayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['time_keep_msg', 'time_keep_summary'],
    );

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(deepRetrievePayload['memories'], ['窗口内长期记忆：沈微护送路线必须经过镜湖。']);
    expect(
      (deepRetrievePayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['time_keep_note'],
    );
  });

  test('Agent 记忆：memory_get 和 deepRetrieve 工具支持相对最近时间别名', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    void insertMemory({
      required String id,
      required String isolationKey,
      required String content,
      required int createTime,
      required String type,
      String name = '',
      String role = agentRoleUser,
      int summarized = 0,
      List<String> relatedMessageIds = const [],
    }) {
      db.execute(
        'INSERT INTO memories '
        '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          name,
          content,
          createTime,
          embeddingJson(content),
          isolationKey,
          jsonEncode(relatedMessageIds),
          role,
          summarized,
          type,
        ],
      );
    }

    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.summaryLimit', '5'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '5'],
    );
    insertMemory(
      id: 'recent_old_msg',
      isolationKey: 'scriptAgent:$projectId',
      content: '旧记忆：镜湖誓言要求李澈护送沈微。',
      createTime: now - const Duration(minutes: 10).inMilliseconds,
      type: agentMemoryTypeMessage,
      summarized: 1,
    );
    insertMemory(
      id: 'recent_keep_msg',
      isolationKey: 'scriptAgent:$projectId',
      content: '最近记忆：镜湖誓言要求李澈护送沈微并隐藏身份。',
      createTime: now - const Duration(minutes: 1).inMilliseconds,
      type: agentMemoryTypeMessage,
      summarized: 1,
    );
    insertMemory(
      id: 'recent_old_note',
      isolationKey: 'project:$projectId',
      content: '旧长期记忆：镜湖路线从山门出发。',
      createTime: now - const Duration(minutes: 10).inMilliseconds,
      type: agentMemoryTypeNote,
      name: '旧镜湖路线',
    );
    insertMemory(
      id: 'recent_keep_note',
      isolationKey: 'project:$projectId',
      content: '最近长期记忆：镜湖路线必须绕开守山阵。',
      createTime: now - const Duration(minutes: 1).inMilliseconds,
      type: agentMemoryTypeNote,
      name: '新镜湖路线',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'query': '镜湖誓言 李澈 沈微',
        'recentMinutes': 5,
        'limit': 5,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        'query': '镜湖路线',
        'scope': 'long_term',
        '最近分钟': 5,
        'limit': 5,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '只召回最近几分钟的镜湖设定',
      autoMode: true,
      family: agentFamilyScript,
    );

    final memoryGetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final memoryGetProperties = memoryGetTool.schema['properties'] as Map;
    expect(
      memoryGetProperties.keys,
      containsAll(['recentMinutes', 'lastMinutes', 'withinMinutes', '最近分钟']),
    );
    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final deepRetrieveProperties = deepRetrieveTool.schema['properties'] as Map;
    expect(
      deepRetrieveProperties.keys,
      containsAll(['recentMinutes', 'lastMinutes', 'withinMinutes', '最近分钟']),
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(memoryGetPayload['memories'], ['最近记忆：镜湖誓言要求李澈护送沈微并隐藏身份。']);
    expect(
      (memoryGetPayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['recent_keep_msg'],
    );

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(deepRetrievePayload['memories'], ['最近长期记忆：镜湖路线必须绕开守山阵。']);
    expect(
      (deepRetrievePayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['recent_keep_note'],
    );
  });

  test('Agent 记忆：memory_get 和 deepRetrieve 工具支持自然排序别名', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    void insertMemory({
      required String id,
      required String isolationKey,
      required String content,
      required int createTime,
      required String type,
      String name = '',
      String role = agentRoleUser,
      int summarized = 0,
      List<String> relatedMessageIds = const [],
    }) {
      db.execute(
        'INSERT INTO memories '
        '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          name,
          content,
          createTime,
          embeddingJson(content),
          isolationKey,
          jsonEncode(relatedMessageIds),
          role,
          summarized,
          type,
        ],
      );
    }

    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    insertMemory(
      id: 'sort_new_msg',
      isolationKey: 'scriptAgent:$projectId',
      content: '霜刃戒律：第二次记录，李澈必须在山门前救沈微。',
      createTime: now + 2,
      type: agentMemoryTypeMessage,
      summarized: 1,
    );
    insertMemory(
      id: 'sort_old_msg',
      isolationKey: 'scriptAgent:$projectId',
      content: '霜刃戒律：第一次记录，李澈不能滥杀。',
      createTime: now + 1,
      type: agentMemoryTypeMessage,
      summarized: 1,
    );
    insertMemory(
      id: 'sort_new_note',
      isolationKey: 'project:$projectId',
      content: '霜刃戒律长期记忆：第二条，沈微必须保留镜湖线索。',
      createTime: now + 2,
      type: agentMemoryTypeNote,
      name: '霜刃戒律二',
    );
    insertMemory(
      id: 'sort_old_note',
      isolationKey: 'project:$projectId',
      content: '霜刃戒律长期记忆：第一条，李澈不能滥杀。',
      createTime: now + 1,
      type: agentMemoryTypeNote,
      name: '霜刃戒律一',
    );

    gateway.turns = [
      AgentTurnResult.tool('memory_get', const {
        'query': '霜刃戒律 李澈',
        'orderBy': 'oldest',
        'limit': 5,
      }),
      AgentTurnResult.tool('deepRetrieve', const {
        'query': '霜刃戒律',
        'scope': 'long_term',
        '排序': '最旧',
        'limit': 5,
      }),
    ];

    await engine.sendAgentMessage(
      projectId,
      '按时间顺序回顾霜刃戒律',
      autoMode: true,
      family: agentFamilyScript,
    );

    final memoryGetTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'memory_get');
    final memoryGetProperties = memoryGetTool.schema['properties'] as Map;
    expect(
      memoryGetProperties.keys,
      containsAll(['orderBy', 'sortBy', 'sortOrder', '排序']),
    );
    final deepRetrieveTool =
        gateway.lastTools.singleWhere((tool) => tool.name == 'deepRetrieve');
    final deepRetrieveProperties = deepRetrieveTool.schema['properties'] as Map;
    expect(
      deepRetrieveProperties.keys,
      containsAll(['orderBy', 'sortBy', 'sortOrder', '排序']),
    );

    final toolMessages = engine
        .agentMessages(projectId)
        .where((message) => message.role == agentRoleTool)
        .toList();
    expect(toolMessages.map((message) => message.toolName),
        ['memory_get', 'deepRetrieve']);

    final memoryGetPayload =
        jsonDecode(toolMessages.first.content) as Map<String, dynamic>;
    expect(memoryGetPayload['found'], isTrue);
    expect(
      memoryGetPayload['memories'],
      [
        '霜刃戒律：第一次记录，李澈不能滥杀。',
        '霜刃戒律：第二次记录，李澈必须在山门前救沈微。',
      ],
    );
    expect(
      (memoryGetPayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['sort_old_msg', 'sort_new_msg'],
    );

    final deepRetrievePayload =
        jsonDecode(toolMessages.last.content) as Map<String, dynamic>;
    expect(deepRetrievePayload['found'], isTrue);
    expect(
      deepRetrievePayload['memories'],
      [
        '霜刃戒律长期记忆：第一条，李澈不能滥杀。',
        '霜刃戒律长期记忆：第二条，沈微必须保留镜湖线索。',
      ],
    );
    expect(
      (deepRetrievePayload['records'] as List)
          .map((record) => (record as Map<String, dynamic>)['id']),
      ['sort_old_note', 'sort_new_note'],
    );
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
    gateway.textResults = const [
      TextResult(
        '[{"summary_id":"trace_summary_lizhe","reason":"角色正派约束命中"}]',
      ),
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
    expect(record['sourceSummaries'], [
      {
        'id': 'trace_summary_lizhe',
        'type': agentMemoryTypeSummary,
        'name': '李澈角色设定',
        'createTime': now + 1,
        'role': agentRoleAssistant,
        'content': '寒山少主李澈必须保持正派。',
        'reason': '角色正派约束命中',
      },
    ]);
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

  test('AgentMemoryService deepRetrieve 可解析带 reason 的对象数组摘要选择', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.deepRetrieveSummaryLimit', '2'],
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
          agentRoleUser,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'object_summary_relevant_msg',
      '用户强调李澈必须保持正派，不能被写成反派。',
      0,
    );
    insertMessage(
      'object_summary_noise_msg',
      '用户提到寒山远景可以多一点云雾。',
      1,
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'object_summary_relevant',
        '李澈角色约束',
        '李澈必须保持正派，不能反派化。',
        now + 2,
        embeddingJson('李澈必须保持正派，不能反派化。'),
        'scriptAgent:$projectId',
        jsonEncode(['object_summary_relevant_msg']),
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
        'object_summary_noise',
        '寒山场景设定',
        '寒山远景适合云雾和夜色。',
        now + 3,
        embeddingJson('寒山远景适合云雾和夜色。'),
        'scriptAgent:$projectId',
        jsonEncode(['object_summary_noise_msg']),
        agentRoleAssistant,
        0,
        agentMemoryTypeSummary,
      ],
    );
    gateway.textResults = const [
      TextResult(
        '[{"summary_id":"object_summary_relevant","reason":"角色约束命中"}]',
      ),
    ];

    final records = await service.deepRetrieve(
      isolationKey: 'scriptAgent:$projectId',
      keyword: '寒山李澈正派',
    );

    expect(records.map((item) => item.id), ['object_summary_relevant_msg']);
    expect(gateway.textCallCount, 1);
  });

  test('AgentMemoryService deepRetrieve 可解析模型返回的 summary 候选序号', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.deepRetrieveSummaryLimit', '2'],
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
          agentRoleUser,
          1,
          agentMemoryTypeMessage,
        ],
      );
    }

    insertMessage(
      'ordinal_summary_noise_msg',
      '场景道具：寒山山门有李澈正派匾额，但不代表角色约束。',
      0,
    );
    insertMessage(
      'ordinal_summary_relevant_msg',
      '用户明确要求李澈保持正派，不能被写成反派。',
      1,
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'ordinal_summary_relevant',
        '李澈角色约束',
        '李澈必须保持正派，不能反派化。',
        now + 2,
        embeddingJson('李澈必须保持正派，不能反派化。'),
        'scriptAgent:$projectId',
        jsonEncode(['ordinal_summary_relevant_msg']),
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
        'ordinal_summary_noise',
        '寒山道具噪声',
        '寒山李澈正派 寒山李澈正派 只是山门匾额道具，和角色约束无关。',
        now + 3,
        embeddingJson('寒山李澈正派 寒山李澈正派 只是山门匾额道具，和角色约束无关。'),
        'scriptAgent:$projectId',
        jsonEncode(['ordinal_summary_noise_msg']),
        agentRoleAssistant,
        0,
        agentMemoryTypeSummary,
      ],
    );
    gateway.textResults = const [TextResult('第 2 条摘要最相关')];

    final records = await service.deepRetrieve(
      isolationKey: 'scriptAgent:$projectId',
      keyword: '寒山李澈正派',
    );

    expect(records.map((item) => item.id), ['ordinal_summary_relevant_msg']);
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

  test('AgentMemoryService deepRetrieve 支持 minScore 过滤弱相关 message', () async {
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
          agentRoleUser,
          0,
          'message',
        ],
      );
    }

    insertMessage('service_score_high', '用户明确要求：李澈正派设定必须保留，不能反派化。', 0);
    insertMessage('service_score_low', '用户补充：李澈来自寒山宗门。', 1);

    final records = await service.deepRetrieve(
      isolationKey: 'scriptAgent:$projectId',
      keyword: '李澈正派设定',
      minScore: 80,
    );

    expect(records.map((item) => item.id), ['service_score_high']);
    expect(records.single.score, greaterThanOrEqualTo(80));
  });

  test('AgentMemoryService deepRetrieve 使用 minScore 设置过滤弱相关 message', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.minScore', '80'],
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
          agentRoleUser,
          0,
          'message',
        ],
      );
    }

    insertMessage('service_setting_score_high', '用户明确要求：李澈正派设定必须保留，不能反派化。', 0);
    insertMessage('service_setting_score_low', '用户补充：李澈来自寒山宗门。', 1);

    final records = await service.deepRetrieve(
      isolationKey: 'scriptAgent:$projectId',
      keyword: '李澈正派设定',
    );

    expect(records.map((item) => item.id), ['service_setting_score_high']);
    expect(records.single.score, greaterThanOrEqualTo(80));
  });

  test('AgentMemoryService deepRetrieve 支持 types=all 召回对话和长期记忆', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    final noteId = engine.saveAgentMemory(
      projectId,
      name: '角色禁忌',
      content: '长期设定：李澈不能被改写成反派，也不能主动滥杀。',
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'service_all_message',
        '',
        '历史对话：用户强调李澈必须保持正派，不能被塑造成反派。',
        now,
        embeddingJson('历史对话：用户强调李澈必须保持正派，不能被塑造成反派。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        0,
        agentMemoryTypeMessage,
      ],
    );

    final records = await service.deepRetrieve(
      isolationKey: 'scriptAgent:$projectId',
      keyword: '李澈反派',
      types: const {'all'},
      noteIsolationKey: 'project:$projectId',
    );

    expect(records.map((item) => item.id), contains(noteId));
    expect(records.map((item) => item.id), contains('service_all_message'));
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

    void insertVector(String id, String key, String type) {
      db.execute(
        'INSERT OR REPLACE INTO o_memoryVector '
        '(memoryId,isolationKey,type,provider,model,dimension,vector,updatedAt) '
        'VALUES (?,?,?,?,?,?,?,?)',
        [
          id,
          key,
          type,
          'gateway',
          'agent_embedding',
          2,
          jsonEncode([1, 0]),
          1000,
        ],
      );
    }

    insertMemory('scope_msg', isolationKey, agentMemoryTypeMessage,
        summarized: 1);
    insertMemory('scope_sum', isolationKey, agentMemoryTypeSummary);
    insertMemory('scope_note', isolationKey, agentMemoryTypeNote);
    insertMemory('other_msg', otherIsolationKey, agentMemoryTypeMessage);
    insertVector('scope_msg', isolationKey, agentMemoryTypeMessage);
    insertVector('scope_sum', isolationKey, agentMemoryTypeSummary);
    insertVector('scope_note', isolationKey, agentMemoryTypeNote);
    insertVector('other_msg', otherIsolationKey, agentMemoryTypeMessage);

    List<String> typesFor(String key) => [
          for (final row in db.select(
            'SELECT type FROM memories WHERE isolationKey=? ORDER BY type ASC',
            [key],
          ))
            row['type'] as String,
        ];
    List<String> vectorIdsFor(String key) => [
          for (final row in db.select(
            'SELECT memoryId FROM o_memoryVector '
            'WHERE isolationKey=? ORDER BY memoryId ASC',
            [key],
          ))
            row['memoryId'] as String,
        ];

    service.clear(isolationKey: isolationKey, scope: agentMemoryTypeMessage);

    expect(typesFor(isolationKey), [agentMemoryTypeNote]);
    expect(typesFor(otherIsolationKey), [agentMemoryTypeMessage]);
    expect(vectorIdsFor(isolationKey), ['scope_note']);
    expect(vectorIdsFor(otherIsolationKey), ['other_msg']);

    insertMemory('scope_msg_after', isolationKey, agentMemoryTypeMessage,
        summarized: 1);
    insertMemory('scope_sum_after', isolationKey, agentMemoryTypeSummary);
    insertVector('scope_msg_after', isolationKey, agentMemoryTypeMessage);
    insertVector('scope_sum_after', isolationKey, agentMemoryTypeSummary);

    service.clear(isolationKey: isolationKey, scope: agentMemoryTypeSummary);

    expect(
        typesFor(isolationKey), [agentMemoryTypeMessage, agentMemoryTypeNote]);
    final resetRow = db.select(
      'SELECT summarized FROM memories WHERE id=? AND isolationKey=?',
      ['scope_msg_after', isolationKey],
    ).single;
    expect(resetRow['summarized'], 0);
    expect(typesFor(otherIsolationKey), [agentMemoryTypeMessage]);
    expect(vectorIdsFor(isolationKey), ['scope_msg_after', 'scope_note']);
    expect(vectorIdsFor(otherIsolationKey), ['other_msg']);

    service.clear(isolationKey: isolationKey, scope: 'all');

    expect(typesFor(isolationKey), isEmpty);
    expect(typesFor(otherIsolationKey), [agentMemoryTypeMessage]);
    expect(vectorIdsFor(isolationKey), isEmpty);
    expect(vectorIdsFor(otherIsolationKey), ['other_msg']);
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

  test('AgentMemoryService get 使用 minScore 设置过滤弱相关 message', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.minScore', '80'],
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
          agentRoleUser,
          1,
          'message',
        ],
      );
    }

    insertMessage('get_score_high', '用户明确要求：李澈正派设定必须保留，不能反派化。', 0);
    insertMessage('get_score_low', '用户补充：李澈来自寒山宗门。', 1);

    final context = await service.get(
      isolationKey: 'scriptAgent:$projectId',
      query: '李澈正派设定',
    );

    expect(context.relatedMessages.map((item) => item.id), ['get_score_high']);
    expect(context.relatedMessages.single.score, greaterThanOrEqualTo(80));
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

  test('AgentMemoryService 写入 gateway message 和 summary 时同步向量索引', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '2'],
    );
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
      embeddingProvider: GatewayAgentMemoryEmbeddingProvider(
        gateway,
        stage: 'agent_embedding',
      ),
    );
    gateway.embeddingForText = (input) {
      if (input.contains('第一条')) return const [0.1, 0.2];
      if (input.contains('第二条')) return const [0.3, 0.4];
      if (input.contains('摘要')) return const [0.5, 0.6];
      return const [0.7, 0.8];
    };
    gateway.textResults = const [TextResult('摘要：李澈保护沈微。')];
    final now = DateTime.now().millisecondsSinceEpoch;

    final firstId = await service.add(
      isolationKey: 'scriptAgent:$projectId',
      role: agentRoleUser,
      content: '第一条：李澈必须保护沈微。',
      createTime: now,
    );
    await service.add(
      isolationKey: 'scriptAgent:$projectId',
      role: agentRoleAssistant,
      content: '第二条：后续剧情保持这个承诺。',
      createTime: now + 1,
    );

    final firstVector = db.select(
      'SELECT isolationKey,type,provider,model,dimension,vector '
      'FROM o_memoryVector WHERE memoryId=?',
      [firstId],
    ).single;
    expect(firstVector['isolationKey'], 'scriptAgent:$projectId');
    expect(firstVector['type'], agentMemoryTypeMessage);
    expect(firstVector['provider'], 'gateway');
    expect(firstVector['model'], 'agent_embedding');
    expect(firstVector['dimension'], 2);
    expect(jsonDecode(firstVector['vector'] as String), [0.1, 0.2]);

    final summaryId = db.select(
      'SELECT id FROM memories WHERE isolationKey=? AND type=?',
      ['scriptAgent:$projectId', agentMemoryTypeSummary],
    ).single['id'] as String;
    final summaryVector = db.select(
      'SELECT isolationKey,type,provider,model,dimension,vector '
      'FROM o_memoryVector WHERE memoryId=?',
      [summaryId],
    ).single;
    expect(summaryVector['isolationKey'], 'scriptAgent:$projectId');
    expect(summaryVector['type'], agentMemoryTypeSummary);
    expect(summaryVector['provider'], 'gateway');
    expect(summaryVector['model'], 'agent_embedding');
    expect(summaryVector['dimension'], 2);
    expect(jsonDecode(summaryVector['vector'] as String), [0.5, 0.6]);
  });

  test('AgentMemoryService get 走 gateway 向量索引时不逐条回填未索引候选', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    final service = AgentMemoryService(
      db,
      gateway,
      summaryStage: 'scriptAgent:decisionAgent',
      embeddingProvider: GatewayAgentMemoryEmbeddingProvider(
        gateway,
        stage: 'agent_embedding',
      ),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'indexed_gateway_msg',
        '',
        '用户设定：李澈必须保护沈微。',
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
        'unindexed_gateway_noise',
        '',
        '旧消息：山门远景和云雾氛围。',
        now + 1,
        '',
        'scriptAgent:$projectId',
        '[]',
        agentRoleAssistant,
        1,
        agentMemoryTypeMessage,
      ],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_memoryVector '
      '(memoryId,isolationKey,type,provider,model,dimension,vector,updatedAt) '
      'VALUES (?,?,?,?,?,?,?,?)',
      [
        'indexed_gateway_msg',
        'scriptAgent:$projectId',
        agentMemoryTypeMessage,
        'gateway',
        'agent_embedding',
        2,
        jsonEncode([1.0, 0.0]),
        now,
      ],
    );
    gateway.embeddingForText = (input) {
      if (input.contains('保护沈微')) return const [1, 0];
      return const [0, 1];
    };

    final context = await service.get(
      isolationKey: 'scriptAgent:$projectId',
      query: '保护沈微',
    );

    expect(context.relatedMessages.map((item) => item.id),
        ['indexed_gateway_msg']);
    expect(gateway.embeddingInputs, ['保护沈微']);
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

  test('AgentMemoryService get 重排可解析模型返回的候选序号', () async {
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
        'rerank_ordinal_relevant',
        '',
        '用户明确要求李澈保持正派，不能被写成反派。',
        now,
        embeddingJson('用户明确要求李澈保持正派，不能被写成反派。'),
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
        'rerank_ordinal_noise',
        '',
        '道具标签：李澈正派 李澈正派 匾额用于山门背景，和角色立场无关。',
        now + 1,
        embeddingJson('道具标签：李澈正派 李澈正派 匾额用于山门背景，和角色立场无关。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleAssistant,
        1,
        agentMemoryTypeMessage,
      ],
    );
    gateway.textResults = const [TextResult('第 2 条最相关')];

    final context = await service.get(
      isolationKey: 'scriptAgent:$projectId',
      query: '李澈正派',
    );

    expect(context.relatedMessages.map((item) => item.id),
        ['rerank_ordinal_relevant']);
    expect(gateway.textCallCount, 1);
  });

  test('AgentMemoryService get 重排可解析带 reason 的对象数组 message 选择', () async {
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
        'rerank_object_relevant',
        '',
        '用户明确要求李澈保持正派，不能被写成反派。',
        now,
        embeddingJson('用户明确要求李澈保持正派，不能被写成反派。'),
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
        'rerank_object_noise',
        '',
        '道具标签：李澈正派 匾额用于山门背景，和角色立场无关。',
        now + 1,
        embeddingJson('道具标签：李澈正派 匾额用于山门背景，和角色立场无关。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleAssistant,
        1,
        agentMemoryTypeMessage,
      ],
    );
    gateway.textResults = const [
      TextResult(
        '[{"message_id":"rerank_object_relevant","reason":"用户明确约束"}]',
      ),
    ];

    final context = await service.get(
      isolationKey: 'scriptAgent:$projectId',
      query: '李澈正派',
    );

    expect(context.relatedMessages.map((item) => item.id),
        ['rerank_object_relevant']);
    expect(context.relatedMessages.single.relevanceReason, '用户明确约束');
    expect(gateway.textCallCount, 1);
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

  test('Agent turn system prompt 注入 RAG 重排理由和匹配词', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '99'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.shortTermLimit', '0'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.ragLimit', '1'],
    );
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.rerankEnabled', '1'],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'prompt_rerank_noise',
        '',
        '道具说明：山门匾额写着李澈正派四个字，但这不是角色设定。',
        now,
        embeddingJson('道具说明：山门匾额写着李澈正派四个字，但这不是角色设定。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleAssistant,
        1,
        agentMemoryTypeMessage,
      ],
    );
    db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'prompt_rerank_keep',
        '',
        '用户明确要求李澈保持正派，不能被写成反派。',
        now + 1,
        embeddingJson('用户明确要求李澈保持正派，不能被写成反派。'),
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        1,
        agentMemoryTypeMessage,
      ],
    );
    gateway.textResults = const [
      TextResult(
        '[{"message_id":"prompt_rerank_keep","reason":"用户明确给出角色立场约束"}]',
      ),
    ];
    gateway.turns = [const AgentTurnResult.text('收到，我会保持李澈正派。')];

    await engine.sendAgentMessage(projectId, '继续写李澈正派线', autoMode: false);

    expect(gateway.lastSystem, contains('<memory id="prompt_rerank_keep"'));
    expect(gateway.lastSystem, contains('matchedTokens="李澈,正派"'));
    expect(gateway.lastSystem, contains('relevanceReason="用户明确给出角色立场约束"'));
    expect(gateway.lastSystem, isNot(contains('prompt_rerank_noise')));
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

  test('ScriptAgent 子 Agent 失败后停止自动调度且不触发监督层', () async {
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'prompt': '搭建寒山篇前三集骨架'},
      ),
      const AgentTurnResult.text('   '),
      AgentTurnResult.tool(
        'run_supervision_agent',
        const {'prompt': '不应审核失败的故事骨架'},
      ),
      const AgentTurnResult.text('监督结论：不应出现。'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '自动完成故事骨架并审核',
      autoMode: true,
    );

    expect(gateway.stages, [
      'scriptAgent:decisionAgent',
      'scriptAgent:storySkeletonAgent',
    ]);
    final messages = engine.agentMessages(projectId);
    expect(
      messages.where((message) => message.toolName == 'run_supervision_agent'),
      isEmpty,
    );
    expect(messages.last.role, agentRoleAssistant);
    expect(messages.last.content, contains('故事骨架 Agent 未返回可写入内容'));
    expect(messages.last.content, contains('当前阶段已停止'));
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

  test('ScriptAgent 子 Agent memory_add 默认写入当前执行层 role', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'prompt': '搭建寒山篇前三集骨架并记录关键约束'},
      ),
      AgentTurnResult.tool(
        'memory_add',
        const {'content': '执行发现：寒山篇必须保留山门钟声伏笔。'},
      ),
      const AgentTurnResult.text('<storySkeleton>寒山篇三集骨架</storySkeleton>'),
    ];

    await engine.sendAgentMessage(projectId, '先做寒山故事骨架', autoMode: false);

    expect(gateway.toolNamesByCall[1], contains('memory_add'));
    final rows = db.select(
      'SELECT role,content FROM memories '
      'WHERE isolationKey=? AND type=? AND content=?',
      [
        'scriptAgent:$projectId',
        agentMemoryTypeMessage,
        '执行发现：寒山篇必须保留山门钟声伏笔。',
      ],
    );
    expect(rows, hasLength(1));
    expect(rows.single['role'], 'assistant:execution:storySkeleton');
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

  test('剧本执行工具调用接受 chapterNo 别名读取小说事件', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final novelIds = engine.addNovels(projectId, const [
      ChapterItem(index: 7, reel: '正文卷', chapter: '寒山试炼', chapterData: 'x'),
      ChapterItem(index: 8, reel: '正文卷', chapter: '镜湖初见', chapterData: 'y'),
    ]);
    db.execute(
      'UPDATE o_novel SET event=?, eventState=1 WHERE id=?',
      ['李澈在第七章寒山试炼中守住山门。', novelIds[0]],
    );
    db.execute(
      'UPDATE o_novel SET event=?, eventState=1 WHERE id=?',
      ['不应读取的第八章事件。', novelIds[1]],
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'request': '读取第七章事件'},
      ),
      AgentTurnResult.tool(
        'get_novel_events',
        const {'chapterNo': 1},
      ),
      const AgentTurnResult.text('<storySkeleton>第七章骨架</storySkeleton>'),
    ];

    await engine.sendAgentMessage(projectId, '读取第七章事件后做骨架', autoMode: false);

    final rows = db.select(
      'SELECT role,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', 'message'],
    );
    final toolAudit = rows.singleWhere(
      (row) => row['role'] == 'assistant:execution:storySkeleton:tool',
    );
    expect(toolAudit['content'], contains('工具 get_novel_events 执行结果'));
    expect(toolAudit['content'], contains('李澈在第七章寒山试炼中守住山门'));
    expect(toolAudit['content'], isNot(contains('不应读取的第八章事件')));
  });

  test('剧本执行工具调用接受 chapterName 别名读取小说事件', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final novelIds = engine.addNovels(projectId, const [
      ChapterItem(index: 7, reel: '正文卷', chapter: '寒山试炼', chapterData: 'x'),
      ChapterItem(index: 8, reel: '正文卷', chapter: '镜湖初见', chapterData: 'y'),
    ]);
    db.execute(
      'UPDATE o_novel SET event=?, eventState=1 WHERE id=?',
      ['李澈在寒山试炼中守住山门。', novelIds[0]],
    );
    db.execute(
      'UPDATE o_novel SET event=?, eventState=1 WHERE id=?',
      ['不应读取的镜湖事件。', novelIds[1]],
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'request': '读取寒山试炼事件'},
      ),
      AgentTurnResult.tool(
        'get_novel_events',
        const {'chapterName': '寒山试炼'},
      ),
      const AgentTurnResult.text('<storySkeleton>寒山试炼骨架</storySkeleton>'),
    ];

    await engine.sendAgentMessage(projectId, '读取寒山试炼事件后做骨架', autoMode: false);

    final rows = db.select(
      'SELECT role,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', 'message'],
    );
    final toolAudit = rows.singleWhere(
      (row) => row['role'] == 'assistant:execution:storySkeleton:tool',
    );
    expect(toolAudit['content'], contains('工具 get_novel_events 执行结果'));
    expect(toolAudit['content'], contains('李澈在寒山试炼中守住山门'));
    expect(toolAudit['content'], isNot(contains('不应读取的镜湖事件')));
  });

  test('剧本执行工具调用接受 episodeIds 别名读取已有剧本', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    engine.addScript(projectId: projectId, name: '第一集', content: '不应读取');
    final secondScriptId = engine.addScript(
      projectId: projectId,
      name: '第二集',
      content: '沈微在镜湖现身。',
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_script',
        {'request': '续写前先读取第二集', 'episodeId': secondScriptId},
      ),
      AgentTurnResult.tool(
        'get_script_content',
        {
          'episodeIds': [secondScriptId],
        },
      ),
      const AgentTurnResult.text('<scriptItem name="第三集">镜湖之后。</scriptItem>'),
    ];

    await engine.sendAgentMessage(projectId, '读取第二集后续写第三集', autoMode: false);

    final rows = db.select(
      'SELECT role,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', 'message'],
    );
    final toolAudit = rows.singleWhere(
      (row) => row['role'] == 'assistant:execution:script:tool',
    );
    expect(toolAudit['content'], contains('工具 get_script_content 执行结果'));
    expect(toolAudit['content'], contains('沈微在镜湖现身'));
    expect(toolAudit['content'], isNot(contains('不应读取')));
  });

  test('剧本执行工具调用接受 scriptName 别名读取已有剧本', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    engine.addScript(projectId: projectId, name: '第一集', content: '不应读取');
    engine.addScript(
      projectId: projectId,
      name: '第二集',
      content: '沈微在镜湖现身。',
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_script',
        const {'request': '续写前先读取第二集'},
      ),
      AgentTurnResult.tool(
        'get_script_content',
        const {'scriptName': '第二集'},
      ),
      const AgentTurnResult.text('<scriptItem name="第三集">镜湖之后。</scriptItem>'),
    ];

    await engine.sendAgentMessage(projectId, '读取第二集后续写第三集', autoMode: false);

    final rows = db.select(
      'SELECT role,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', 'message'],
    );
    final toolAudit = rows.singleWhere(
      (row) => row['role'] == 'assistant:execution:script:tool',
    );
    expect(toolAudit['content'], contains('工具 get_script_content 执行结果'));
    expect(toolAudit['content'], contains('沈微在镜湖现身'));
    expect(toolAudit['content'], isNot(contains('不应读取')));
  });

  test('剧本执行工具调用接受 dataKey 别名读取剧本工作区片段', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'request': '生成寒山篇故事骨架'},
      ),
      const AgentTurnResult.text('<storySkeleton>寒山篇三集骨架</storySkeleton>'),
    ];
    await engine.sendAgentMessage(projectId, '先生成故事骨架', autoMode: false);

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_adaptationStrategy',
        const {'request': '生成寒山篇改编策略'},
      ),
      const AgentTurnResult.text(
        '<adaptationStrategy>前三集强化退婚冲突</adaptationStrategy>',
      ),
    ];
    await engine.sendAgentMessage(projectId, '继续生成改编策略', autoMode: false);

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_script',
        const {'request': '读取故事骨架后写第一集'},
      ),
      AgentTurnResult.tool(
        'get_planData',
        const {'dataKey': 'story_skeleton'},
      ),
      const AgentTurnResult.text('<scriptItem name="第一集">寒山开篇。</scriptItem>'),
    ];

    await engine.sendAgentMessage(projectId, '读取骨架写剧本', autoMode: false);

    final rows = db.select(
      'SELECT role,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['scriptAgent:$projectId', 'message'],
    );
    final toolAudit = rows.singleWhere(
      (row) => row['role'] == 'assistant:execution:script:tool',
    );
    expect(toolAudit['content'], contains('工具 get_planData 执行结果'));
    expect(toolAudit['content'], contains('寒山篇三集骨架'));
    expect(toolAudit['content'], isNot(contains('前三集强化退婚冲突')));
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

  test('ScriptAgent 监督返回后自动模式等待用户确认再继续', () async {
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'prompt': '搭建寒山篇前三集骨架'},
      ),
      const AgentTurnResult.text('<storySkeleton>寒山篇三集骨架</storySkeleton>'),
      AgentTurnResult.tool(
        'run_supervision_agent',
        const {'prompt': '检查前三集是否连续'},
      ),
      const AgentTurnResult.text('监督结论：节奏成立。'),
      AgentTurnResult.tool(
        'run_sub_agent_adaptationStrategy',
        const {'prompt': '不应自动进入改编策略'},
      ),
      const AgentTurnResult.text(
        '<adaptationStrategy>不应写入</adaptationStrategy>',
      ),
    ];

    await engine.sendAgentMessage(
      projectId,
      '自动完成故事骨架并审核',
      autoMode: true,
    );

    expect(gateway.stages, [
      'scriptAgent:decisionAgent',
      'scriptAgent:storySkeletonAgent',
      'scriptAgent:decisionAgent',
      'scriptAgent:supervisionAgent',
    ]);
    final data = _scriptAgentWorkData(db, projectId);
    expect(data['storySkeleton'], '寒山篇三集骨架');
    expect(data['supervision'], contains('节奏成立'));
    expect(data['adaptationStrategy'], '');
    final messages = engine.agentMessages(projectId);
    expect(
      messages.where(
        (message) => message.toolName == 'run_sub_agent_adaptationStrategy',
      ),
      isEmpty,
    );
    expect(messages.last.role, agentRoleAssistant);
    expect(messages.last.content, contains('请确认'));
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

  test('ScriptAgentOrchestrator accepts scriptItem name aliases', () async {
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_script',
        const {'prompt': '写第一集'},
      ),
      const AgentTurnResult.text(
        '<scriptItem episodeName="第一集"><content>李澈入山。</content></scriptItem>'
        '<scriptItem scriptName="第二集">寒山试剑。</scriptItem>',
      ),
    ];

    await engine.sendAgentMessage(projectId, '生成剧本正文', autoMode: false);

    final rows = engine.scripts(projectId);
    expect(rows.map((row) => row.name), ['第一集', '第二集']);
    expect(rows[0].content, '李澈入山。');
    expect(rows[1].content, '寒山试剑。');
  });

  test('ScriptAgentOrchestrator accepts scriptItem child element fields',
      () async {
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_script',
        const {'prompt': '写第一集'},
      ),
      const AgentTurnResult.text('''
<scriptItem>
  <name>第一集</name>
  <content>李澈入山。</content>
</scriptItem>
<scriptItem>
  <episodeName>第二集</episodeName>
  <scriptContent>寒山试剑。</scriptContent>
</scriptItem>
'''),
    ];

    await engine.sendAgentMessage(projectId, '生成子元素剧本正文', autoMode: false);

    final rows = engine.scripts(projectId);
    expect(rows.map((row) => row.name), ['第一集', '第二集']);
    expect(rows[0].content, '李澈入山。');
    expect(rows[1].content, '寒山试剑。');
  });

  test('ScriptAgentOrchestrator accepts JSON script items', () async {
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_script',
        const {'prompt': '写第一集'},
      ),
      const AgentTurnResult.text('''
[
  {"scriptName":"第一集","content":"李澈入山。"},
  {"episodeName":"第二集","scriptContent":"寒山试剑。"}
]
'''),
    ];

    await engine.sendAgentMessage(projectId, '生成 JSON 剧本正文', autoMode: false);

    final rows = engine.scripts(projectId);
    expect(rows.map((row) => row.name), ['第一集', '第二集']);
    expect(rows[0].content, '李澈入山。');
    expect(rows[1].content, '寒山试剑。');
  });

  test('ScriptAgentOrchestrator accepts wrapped JSON script items', () async {
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_script',
        const {'prompt': '写第一集'},
      ),
      const AgentTurnResult.text('''
```json
{
  "scripts": [
    {"title": "第一集", "body": "李澈入山。"},
    {"scriptName": "第二集", "content": "寒山试剑。"}
  ]
}
```
'''),
    ];

    await engine.sendAgentMessage(projectId, '生成包裹 JSON 剧本正文', autoMode: false);

    final rows = engine.scripts(projectId);
    expect(rows.map((row) => row.name), ['第一集', '第二集']);
    expect(rows[0].content, '李澈入山。');
    expect(rows[1].content, '寒山试剑。');
  });

  test('ScriptAgentOrchestrator accepts Chinese wrapped JSON script items',
      () async {
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_script',
        const {'prompt': '写第一集'},
      ),
      const AgentTurnResult.text('''
{
  "剧本": [
    {"剧本名称": "第一集", "剧本内容": "李澈入山。"},
    {"标题": "第二集", "正文": "寒山试剑。"}
  ]
}
'''),
    ];

    await engine.sendAgentMessage(projectId, '生成中文 JSON 剧本正文', autoMode: false);

    final rows = engine.scripts(projectId);
    expect(rows.map((row) => row.name), ['第一集', '第二集']);
    expect(rows[0].content, '李澈入山。');
    expect(rows[1].content, '寒山试剑。');
  });

  test('ScriptAgentOrchestrator accepts Chinese scriptItem child fields',
      () async {
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_script',
        const {'prompt': '写第一集'},
      ),
      const AgentTurnResult.text('''
<scriptItem>
  <剧本名称>第一集</剧本名称>
  <剧本内容>李澈入山。</剧本内容>
</scriptItem>
'''),
    ];

    await engine.sendAgentMessage(projectId, '生成中文 XML 剧本正文', autoMode: false);

    final rows = engine.scripts(projectId);
    expect(rows.map((row) => row.name), ['第一集']);
    expect(rows.single.content, '李澈入山。');
  });

  test('ScriptAgentOrchestrator preserves CDATA script content', () async {
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_script',
        const {'prompt': '写第一集'},
      ),
      const AgentTurnResult.text('''
<scriptItem>
  <name>第一集</name>
  <content><![CDATA[李澈看见<寒山令> & 转身。]]></content>
</scriptItem>
'''),
    ];

    await engine.sendAgentMessage(projectId, '生成 CDATA 剧本正文', autoMode: false);

    final rows = engine.scripts(projectId);
    expect(rows.map((row) => row.name), ['第一集']);
    expect(rows.single.content, '李澈看见<寒山令> & 转身。');
  });

  test('ScriptAgentOrchestrator ignores partial scriptItem attribute names',
      () async {
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_script',
        const {'prompt': '写第一集'},
      ),
      const AgentTurnResult.text(
        '<scriptItem username="不该成为剧本名">李澈入山。</scriptItem>',
      ),
    ];

    await engine.sendAgentMessage(projectId, '生成剧本正文', autoMode: false);

    expect(engine.scripts(projectId), isEmpty);
    expect(engine.agentMessages(projectId).last.content,
        contains('剧本 Agent 未输出 scriptItem'));
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

  test('子 Agent 工具 schema 暴露常见任务字段别名', () async {
    gateway.turns = [const AgentTurnResult.text('收到')];

    await engine.sendAgentMessage(projectId, '规划故事骨架', autoMode: false);

    final scriptTool = gateway.lastTools.singleWhere(
      (tool) => tool.name == 'run_sub_agent_storySkeleton',
    );
    final scriptProperties = scriptTool.schema['properties'] as Map;
    expect(
      scriptProperties.keys,
      containsAll(
          ['prompt', 'instruction', 'task', 'input', 'request', 'message']),
    );
    expect(scriptTool.schema['required'], isNull);

    gateway.turns = [const AgentTurnResult.text('收到')];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：做导演计划',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final productionTool = gateway.lastTools.singleWhere(
      (tool) => tool.name == 'run_sub_agent_director_plan',
    );
    final productionProperties = productionTool.schema['properties'] as Map;
    expect(
      productionProperties.keys,
      containsAll(
          ['prompt', 'instruction', 'task', 'input', 'request', 'message']),
    );
    expect(
      productionProperties.keys,
      containsAll([
        'scriptId',
        'episodeId',
        'episodesId',
        'scriptIds',
        'episodeIds',
        'script_id',
        'episode_id',
        'episodes_id',
        'script_ids',
        'episode_ids',
        'episodeNo',
        'episodeNos',
        'scriptNo',
        'scriptNos',
        'episode_no',
        'episode_nos',
        'script_no',
        'script_nos',
        'scriptName',
        'scriptNames',
        'episodeName',
        'episodeNames',
        'scriptTitle',
        'scriptTitles',
        'episodeTitle',
        'episodeTitles',
        'script_name',
        'script_names',
        'episode_name',
        'episode_names',
        'script_title',
        'script_titles',
        'episode_title',
        'episode_titles',
      ]),
    );
    expect(productionTool.schema['required'], isNull);
  });

  test('剧本执行读取工具 schema 暴露章节和剧本 id 字段别名', () async {
    gateway.turns = [const AgentTurnResult.text('收到')];

    await engine.sendAgentMessage(projectId, '规划故事骨架', autoMode: false);

    final eventsTool = gateway.lastTools.singleWhere(
      (tool) => tool.name == 'get_novel_events',
    );
    final eventsProperties = eventsTool.schema['properties'] as Map;
    expect(
      eventsProperties.keys,
      containsAll([
        'novelIds',
        'novel_ids',
        'chapterIndexs',
        'chapterIndexes',
        'chapterIndex',
        'chapterNo',
        'chapterNos',
        'chapter_index',
        'chapter_indexes',
        'chapter_no',
        'chapter_nos',
        'chapterName',
        'chapterNames',
        'chapterTitle',
        'chapterTitles',
        'chapter_name',
        'chapter_names',
        'chapter_title',
        'chapter_titles',
        'ids',
      ]),
    );
    expect(eventsTool.schema['required'], isNull);

    final planTool = gateway.lastTools.singleWhere(
      (tool) => tool.name == 'get_planData',
    );
    final planProperties = planTool.schema['properties'] as Map;
    expect(
      planProperties.keys,
      containsAll([
        'key',
        'name',
        'section',
        'dataKey',
        'flowKey',
        'workspaceKey',
        'data_key',
        'flow_key',
        'workspace_key',
      ]),
    );
    expect(
      ((planProperties['dataKey'] as Map)['enum'] as List),
      containsAll(['story_skeleton', 'adaptation_strategy']),
    );
    expect(planTool.schema['required'], isNull);

    final textTool = gateway.lastTools.singleWhere(
      (tool) => tool.name == 'get_novel_text',
    );
    final textProperties = textTool.schema['properties'] as Map;
    expect(
      textProperties.keys,
      containsAll(['chapterNo', 'chapter_no', 'novelIds', 'novel_ids']),
    );
    expect(textTool.schema['required'], isNull);

    final scriptTool = gateway.lastTools.singleWhere(
      (tool) => tool.name == 'get_script_content',
    );
    final scriptProperties = scriptTool.schema['properties'] as Map;
    expect(
      scriptProperties.keys,
      containsAll([
        'ids',
        'scriptIds',
        'episodeIds',
        'script_id',
        'episode_id',
        'script_ids',
        'episode_ids',
        'scriptName',
        'scriptNames',
        'episodeName',
        'episodeNames',
        'scriptTitle',
        'scriptTitles',
        'episodeTitle',
        'episodeTitles',
        'script_name',
        'script_names',
        'episode_name',
        'episode_names',
        'script_title',
        'script_titles',
        'episode_title',
        'episode_titles',
      ]),
    );
    expect(scriptTool.schema['required'], isNull);
  });

  test('制作执行工具 schema 暴露资产生图 id 字段别名', () async {
    gateway.turns = [const AgentTurnResult.text('收到')];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：生成衍生资产图片',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final tool = gateway.lastTools.singleWhere(
      (tool) => tool.name == 'generate_deriveAsset',
    );
    final properties = tool.schema['properties'] as Map;
    expect(
      properties.keys,
      containsAll([
        'ids',
        'assetIds',
        'assetsIds',
        'deriveAssetIds',
        'deriveAssetsIds',
        'asset_ids',
        'assets_ids',
        'derive_asset_ids',
        'derive_assets_ids',
        'assetName',
        'assetNames',
        'deriveAssetName',
        'deriveAssetNames',
        'childAssetName',
        'childAssetNames',
        'asset_name',
        'asset_names',
        'derive_asset_name',
        'derive_asset_names',
        'child_asset_name',
        'child_asset_names',
      ]),
    );
    expect(tool.schema['required'], isNull);
  });

  test('制作执行工具 schema 暴露衍生资产写入字段别名', () async {
    gateway.turns = [const AgentTurnResult.text('收到')];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：写衍生资产',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final tool = gateway.lastTools.singleWhere(
      (tool) => tool.name == 'add_deriveAsset',
    );
    final properties = tool.schema['properties'] as Map;
    expect(
      properties.keys,
      containsAll([
        'assetsId',
        'assetId',
        'parentAssetId',
        'parentAssetsId',
        'asset_id',
        'assets_id',
        'parent_asset_id',
        'parent_assets_id',
        'parentAssetName',
        'parentAssetNames',
        'parentName',
        'parentNames',
        'sourceAssetName',
        'sourceAssetNames',
        'parent_asset_name',
        'parent_asset_names',
        'source_asset_name',
        'source_asset_names',
        'episodeNo',
        'scriptName',
        'episodeName',
        'name',
        'assetName',
        'asset_name',
        'desc',
        'describe',
        'description',
        'assetDesc',
        'asset_desc',
      ]),
    );
    expect(tool.schema['required'], isNull);
  });

  test('制作执行工具 schema 暴露衍生资产删除 id 字段别名', () async {
    gateway.turns = [const AgentTurnResult.text('收到')];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：删除衍生资产',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final tool = gateway.lastTools.singleWhere(
      (tool) => tool.name == 'del_deriveAsset',
    );
    final properties = tool.schema['properties'] as Map;
    expect(
      properties.keys,
      containsAll([
        'id',
        'assetId',
        'deriveAssetId',
        'childAssetId',
        'asset_id',
        'derive_asset_id',
        'child_asset_id',
        'assetName',
        'assetNames',
        'deriveAssetName',
        'deriveAssetNames',
        'childAssetName',
        'childAssetNames',
        'asset_name',
        'asset_names',
        'derive_asset_name',
        'derive_asset_names',
        'child_asset_name',
        'child_asset_names',
      ]),
    );
    expect(tool.schema['required'], isNull);
  });

  test('制作执行工具 schema 暴露分镜首帧 id 字段别名', () async {
    gateway.turns = [const AgentTurnResult.text('收到')];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：生成分镜首帧',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final tool = gateway.lastTools.singleWhere(
      (tool) => tool.name == 'generate_storyboard',
    );
    final properties = tool.schema['properties'] as Map;
    expect(
      properties.keys,
      containsAll([
        'ids',
        'storyboardIds',
        'shotIds',
        'panelIds',
        'storyboard_ids',
        'shot_ids',
        'panel_ids',
        'shotNo',
        'shotNos',
        'storyboardNo',
        'storyboardNos',
        'shot_no',
        'shot_nos',
        'storyboard_no',
        'storyboard_nos',
      ]),
    );
    expect(tool.schema['required'], isNull);
  });

  test('制作执行工具 schema 暴露分镜写入字段别名', () async {
    gateway.turns = [const AgentTurnResult.text('收到')];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：写分镜面板',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final tool = gateway.lastTools.singleWhere(
      (tool) => tool.name == 'add_flowData_storyboard',
    );
    final properties = tool.schema['properties'] as Map;
    expect(
      properties.keys,
      containsAll([
        'videoDesc',
        'videoDescription',
        'description',
        'shotDesc',
        'video_desc',
        'video_description',
        'shot_desc',
        'prompt',
        'imagePrompt',
        'image_prompt',
        'episodeNo',
        'scriptName',
        'episodeName',
        'associateAssetsIds',
        'assetIds',
        'asset_ids',
        'assetName',
        'assetNames',
        'roleName',
        'roleNames',
        'sceneName',
        'sceneNames',
        'toolName',
        'toolNames',
        'asset_name',
        'asset_names',
        'associate_asset_ids',
        'associatedAssetIds',
        'associated_asset_ids',
        'shouldGenerateImage',
        'generateImage',
        'should_generate_image',
        'generate_image',
      ]),
    );
    expect(tool.schema['required'], isNull);
  });

  test('制作执行工具 schema 暴露制作工作区读取字段别名', () async {
    gateway.turns = [const AgentTurnResult.text('收到')];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：读取资产工作区',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final tool = gateway.lastTools.singleWhere(
      (tool) => tool.name == 'get_flowData',
    );
    final properties = tool.schema['properties'] as Map;
    expect(
      properties.keys,
      containsAll([
        'key',
        'dataKey',
        'data_key',
        'flowKey',
        'flow_key',
        'section',
        'resource',
        'scriptId',
        'episodeId',
        'episodesId',
        'script_id',
        'episode_id',
        'episodes_id',
        'episodeNo',
        'episodeNos',
        'scriptNo',
        'scriptNos',
        'episode_no',
        'episode_nos',
        'script_no',
        'script_nos',
        'scriptName',
        'scriptNames',
        'episodeName',
        'episodeNames',
        'scriptTitle',
        'scriptTitles',
        'episodeTitle',
        'episodeTitles',
        'script_name',
        'script_names',
        'episode_name',
        'episode_names',
        'script_title',
        'script_titles',
        'episode_title',
        'episode_titles',
      ]),
    );
    expect(tool.schema['required'], isNull);
  });

  test('子 Agent 工具调用接受常见提示词别名作为执行任务', () async {
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storySkeleton',
        const {'message': '用 message 字段搭建寒山篇骨架'},
      ),
      const AgentTurnResult.text('<storySkeleton>寒山篇骨架</storySkeleton>'),
    ];

    await engine.sendAgentMessage(projectId, '先做故事骨架', autoMode: false);

    expect(gateway.stages.last, 'scriptAgent:storySkeletonAgent');
    expect(
      gateway.lastMessages.last['content'],
      '用 message 字段搭建寒山篇骨架',
    );

    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'request': '用 request 字段制作第一集导演计划', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<scriptPlan>第一集导演计划</scriptPlan>'),
    ];

    await engine.sendAgentMessage(projectId, '制作导演计划', autoMode: false);

    expect(gateway.stages.last, 'productionAgent:directorPlanAgent');
    expect(
      gateway.lastMessages.last['content'],
      '用 request 字段制作第一集导演计划',
    );
  });

  test('制作子 Agent 工具调用接受 episodeId 别名定位剧本', () async {
    engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final secondScriptId =
        engine.addScript(projectId: projectId, name: '第二集', content: '沈微入局');
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'request': '为第二集做导演计划', 'episodeId': secondScriptId},
      ),
      const AgentTurnResult.text('<scriptPlan>第二集镜湖调度</scriptPlan>'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：做第二集导演计划',
      autoMode: false,
      family: agentFamilyProduction,
    );

    expect(gateway.stages.last, 'productionAgent:directorPlanAgent');
    final content = gateway.lastMessages
        .map((message) => message['content'])
        .whereType<String>()
        .join('\n');
    expect(content, contains('当前剧本：第二集'));
    expect(content, contains('剧本内容：沈微入局'));
    expect(
      _productionAgentWorkData(db, projectId, secondScriptId)['scriptPlan'],
      '第二集镜湖调度',
    );
  });

  test('制作子 Agent 工具调用接受 episodeName 别名定位剧本', () async {
    engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final secondScriptId =
        engine.addScript(projectId: projectId, name: '第二集', content: '沈微入局');
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        const {'request': '为第二集做导演计划', 'episodeName': '第二集'},
      ),
      const AgentTurnResult.text('<scriptPlan>第二集镜湖调度</scriptPlan>'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：做第二集导演计划',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final content = gateway.lastMessages
        .map((message) => message['content'])
        .whereType<String>()
        .join('\n');
    expect(content, contains('当前剧本：第二集'));
    expect(content, contains('剧本内容：沈微入局'));
    expect(
      _productionAgentWorkData(db, projectId, secondScriptId)['scriptPlan'],
      '第二集镜湖调度',
    );
  });

  test('制作执行工具调用接受 section 和 episodeId 别名读取指定工作区段', () async {
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
        'run_sub_agent_director_plan',
        {'request': '先写导演计划', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<scriptPlan>不应出现在资产段</scriptPlan>'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：写导演计划',
      autoMode: false,
      family: agentFamilyProduction,
    );

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'request': '只读取资产段', 'episodeId': scriptId},
      ),
      AgentTurnResult.tool(
        'get_flowData',
        {'section': 'assets', 'episodeId': scriptId},
      ),
      const AgentTurnResult.text('<scriptPlan>资产段读取完成</scriptPlan>'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：读取资产段',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final rows = db.select(
      'SELECT role,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['productionAgent:$projectId', 'message'],
    );
    final toolAudit = rows.singleWhere(
      (row) => row['role'] == 'assistant:execution:directorPlan:tool',
    );
    expect(toolAudit['content'], contains('工具 get_flowData 执行结果'));
    expect(toolAudit['content'], contains('寒山少主'));
    expect(toolAudit['content'], isNot(contains('不应出现在资产段')));
    expect(toolAudit['content'], isNot(contains('李澈入山')));
  });

  test('制作执行工具调用接受 scriptName 别名读取指定工作区段', () async {
    engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    engine.addScript(projectId: projectId, name: '第二集', content: '沈微入局');
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        const {'request': '读取第二集剧本段'},
      ),
      AgentTurnResult.tool(
        'get_flowData',
        const {'section': 'script', 'scriptName': '第二集'},
      ),
      const AgentTurnResult.text('<scriptPlan>第二集读取完成</scriptPlan>'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：读取第二集剧本段',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final rows = db.select(
      'SELECT role,content FROM memories '
      'WHERE isolationKey=? AND type=? ORDER BY createTime ASC, id ASC',
      ['productionAgent:$projectId', 'message'],
    );
    final toolAudit = rows.singleWhere(
      (row) => row['role'] == 'assistant:execution:directorPlan:tool',
    );
    expect(toolAudit['content'], contains('工具 get_flowData 执行结果'));
    expect(toolAudit['content'], contains('沈微入局'));
    expect(toolAudit['content'], isNot(contains('李澈入山')));
  });

  test('制作执行工具调用接受衍生资产写入字段别名', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final parentAssetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_derive_assets',
        {'request': '衍生战损造型', 'episodeId': scriptId},
      ),
      AgentTurnResult.tool(
        'add_deriveAsset',
        {
          'parentAssetId': parentAssetId,
          'assetName': '李澈战损造型',
          'description': '衣甲破损，脸侧有血痕',
          'episodeId': scriptId,
        },
      ),
      const AgentTurnResult.text('衍生资产完成'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：写衍生资产',
      autoMode: false,
      family: agentFamilyProduction,
    );

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
  });

  test('制作执行工具调用接受 parentAssetName 别名写入衍生资产', () async {
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
        {'request': '按名字衍生雪夜造型', 'scriptId': scriptId},
      ),
      AgentTurnResult.tool(
        'add_deriveAsset',
        const {
          'parentAssetName': '李澈',
          'assetName': '李澈雪夜造型',
          'description': '白衣带雪，肩甲结霜',
        },
      ),
      const AgentTurnResult.text('衍生资产完成'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：按名字写衍生资产',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final child = db.select(
      'SELECT * FROM o_assets WHERE assetsId=? AND name=?',
      [parentAssetId, '李澈雪夜造型'],
    ).single;
    expect(child['describe'], '白衣带雪，肩甲结霜');
    expect(
      db.select('SELECT assetId FROM o_scriptAssets WHERE scriptId=?',
          [scriptId]).map((row) => row['assetId']),
      contains(child['id']),
    );
  });

  test('制作执行工具调用接受 deriveAssetId 别名删除衍生资产', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final parentAssetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    final childAssetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈战损造型',
      describe: '衣甲破损',
      parentAssetsId: parentAssetId,
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, childAssetId]);
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_derive_assets',
        {'request': '删除错误衍生资产', 'scriptId': scriptId},
      ),
      AgentTurnResult.tool(
        'del_deriveAsset',
        {'deriveAssetId': childAssetId, 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('衍生资产已删除'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：删除衍生资产',
      autoMode: false,
      family: agentFamilyProduction,
    );

    expect(db.select('SELECT id FROM o_assets WHERE id=?', [childAssetId]),
        isEmpty);
    expect(
      db.select(
          'SELECT assetId FROM o_scriptAssets WHERE assetId=?', [childAssetId]),
      isEmpty,
    );
  });

  test('制作执行工具调用接受 assetName 别名删除衍生资产', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final parentAssetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    final otherParentId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '沈微',
      describe: '镜湖医修',
    );
    final childAssetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈战损造型',
      describe: '衣甲破损',
      parentAssetsId: parentAssetId,
    );
    final unlinkedChildId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈战损造型',
      describe: '另一集的同名造型',
      parentAssetsId: otherParentId,
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, childAssetId]);
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_derive_assets',
        {'request': '按名字删除错误衍生资产', 'scriptId': scriptId},
      ),
      const AgentTurnResult.tool(
        'del_deriveAsset',
        {'assetName': '李澈战损造型'},
      ),
      const AgentTurnResult.text('衍生资产已删除'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：按名字删除衍生资产',
      autoMode: false,
      family: agentFamilyProduction,
    );

    expect(db.select('SELECT id FROM o_assets WHERE id=?', [childAssetId]),
        isEmpty);
    expect(
      db.select(
          'SELECT assetId FROM o_scriptAssets WHERE assetId=?', [childAssetId]),
      isEmpty,
    );
    expect(
      db.select('SELECT id FROM o_assets WHERE id=?', [unlinkedChildId]),
      isNotEmpty,
    );
  });

  test('制作执行工具调用接受 assetIds 别名生成衍生资产图片', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final parentAssetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    final childAssetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈战损造型',
      describe: '衣甲破损',
      parentAssetsId: parentAssetId,
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, childAssetId]);
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_generate_assets',
        {'request': '生成衍生资产图片', 'scriptId': scriptId},
      ),
      AgentTurnResult.tool('generate_deriveAsset', {
        'assetIds': [childAssetId],
      }),
      const AgentTurnResult.text('开始生成'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：生成衍生资产图片',
      autoMode: false,
      family: agentFamilyProduction,
    );

    expect(
      db.select('SELECT taskClass FROM o_tasks').map((row) => row['taskClass']),
      contains('asset_image_generation'),
    );
  });

  test('制作执行工具调用接受 assetName 别名生成衍生资产图片', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final parentAssetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    final childAssetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈战损造型',
      describe: '衣甲破损',
      parentAssetsId: parentAssetId,
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, childAssetId]);
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_generate_assets',
        {'request': '生成衍生资产图片', 'scriptId': scriptId},
      ),
      AgentTurnResult.tool('generate_deriveAsset', const {
        'assetName': '李澈战损造型',
      }),
      const AgentTurnResult.text('开始生成'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：生成衍生资产图片',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final task = db.select(
      'SELECT relatedObjects FROM o_tasks WHERE taskClass=?',
      ['asset_image_generation'],
    ).single;
    final related =
        jsonDecode(task['relatedObjects'] as String) as Map<String, dynamic>;
    expect(related['ids'], [childAssetId]);
  });

  test('制作执行工具调用接受 shotIds 别名生成分镜首帧', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '寒山宗门远景',
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_gen',
        {'request': '生成分镜首帧', 'scriptId': scriptId},
      ),
      AgentTurnResult.tool('generate_storyboard', {
        'shotIds': [storyboardId],
      }),
      const AgentTurnResult.text('开始生成'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：生成分镜首帧',
      autoMode: false,
      family: agentFamilyProduction,
    );

    expect(
      db.select('SELECT taskClass FROM o_tasks').map((row) => row['taskClass']),
      contains('storyboard_image_generation'),
    );
  });

  test('制作执行工具调用接受 shotNo 别名生成分镜首帧', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final firstStoryboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '第一镜',
    );
    final secondStoryboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '第二镜',
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_gen',
        {'request': '生成第二镜首帧', 'scriptId': scriptId},
      ),
      AgentTurnResult.tool('generate_storyboard', const {
        'shotNo': 2,
      }),
      const AgentTurnResult.text('开始生成'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：生成第二镜首帧',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final task = db.select(
      'SELECT relatedObjects FROM o_tasks WHERE taskClass=?',
      ['storyboard_image_generation'],
    ).single;
    final related =
        jsonDecode(task['relatedObjects'] as String) as Map<String, dynamic>;
    expect(related['ids'], [secondStoryboardId]);
    expect(related['ids'], isNot(contains(firstStoryboardId)));
  });

  test('制作执行工具调用接受分镜写入字段别名', () async {
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
        'run_sub_agent_storyboard_panel',
        {'request': '写第一集分镜', 'scriptId': scriptId},
      ),
      AgentTurnResult.tool('add_flowData_storyboard', {
        'videoDescription': '李澈踏入寒山宗门',
        'imagePrompt': '冷色调，少年入山，远景',
        'track': '主线',
        'duration': '3.5',
        'asset_ids': [roleId],
        'generateImage': false,
        'scriptId': scriptId,
      }),
      const AgentTurnResult.text('分镜已写入'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：写分镜面板',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final rows = engine.storyboards(scriptId);
    expect(rows, hasLength(1));
    expect(rows.single.videoDesc, '李澈踏入寒山宗门');
    expect(rows.single.prompt, '冷色调，少年入山，远景');
    expect(rows.single.duration, '3.5');
    expect(rows.single.track, '主线');
    expect(rows.single.shouldGenerateImage, 0);
    expect(rows.single.assetIds, [roleId]);
  });

  test('制作执行工具调用接受 assetName 别名写入分镜关联资产', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, roleId]);
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_panel',
        {'request': '写第一集分镜', 'scriptId': scriptId},
      ),
      AgentTurnResult.tool('add_flowData_storyboard', const {
        'videoDescription': '李澈踏入寒山宗门',
        'imagePrompt': '冷色调，少年入山，远景',
        'assetName': '李澈',
        'generateImage': false,
      }),
      const AgentTurnResult.text('分镜已写入'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：按资产名写分镜面板',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final rows = engine.storyboards(scriptId);
    expect(rows, hasLength(1));
    expect(rows.single.assetIds, [roleId]);
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

  test('ProductionAgent 子 Agent 自动注入视觉参考长期记忆', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    engine.saveAgentMemory(
      projectId,
      name: '项目视觉参考',
      content: '视觉参考分析：冷白水墨、低饱和云雾留白，角色和场景都避免霓虹赛博色。',
    );
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '继续当前制作任务', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<scriptPlan>导演计划沿用项目视觉参考</scriptPlan>'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：做导演计划',
      autoMode: false,
      family: agentFamilyProduction,
    );

    expect(gateway.stages, [
      'productionAgent:decisionAgent',
      'productionAgent:directorPlanAgent',
    ]);
    expect(gateway.systems[1], contains('长期记忆'));
    expect(gateway.systems[1], contains('name="项目视觉参考"'));
    expect(gateway.systems[1], contains('冷白水墨'));
    expect(gateway.systems[1], contains('避免霓虹赛博色'));
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

  test('ProductionAgent 子 Agent memory_add 默认写入当前执行层 role', () async {
    db.execute(
      'INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
      ['agent.memory.messagesPerSummary', '20'],
    );
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '寒山开场');
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '做寒山导演计划并记录镜头约束', 'scriptId': scriptId},
      ),
      AgentTurnResult.tool(
        'memory_add',
        const {'content': '执行发现：寒山山门镜头必须保持贴地低机位。'},
      ),
      const AgentTurnResult.text('<scriptPlan>低机位跟拍寒山山门</scriptPlan>'),
    ];

    await engine.sendAgentMessage(projectId, '制作画布：做寒山导演计划', autoMode: false);

    expect(gateway.toolNamesByCall[1], contains('memory_add'));
    final rows = db.select(
      'SELECT role,content FROM memories '
      'WHERE isolationKey=? AND type=? AND content=?',
      [
        'productionAgent:$projectId',
        agentMemoryTypeMessage,
        '执行发现：寒山山门镜头必须保持贴地低机位。',
      ],
    );
    expect(rows, hasLength(1));
    expect(rows.single['role'], 'assistant:execution:directorPlan');
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

  test('ProductionAgent 子 Agent 失败最多重试两次后停止自动调度', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '做第一集导演计划', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('   '),
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '修正后重试导演计划，补足镜头调度', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('   '),
      AgentTurnResult.tool(
        'run_sub_agent_director_plan',
        {'prompt': '第二次重试导演计划，只输出 scriptPlan', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('   '),
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_table',
        {'prompt': '不应在导演计划失败后继续分镜表', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<storyboardTable>不应写入</storyboardTable>'),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：自动重试导演计划',
      autoMode: true,
      family: agentFamilyProduction,
    );

    expect(gateway.stages, [
      'productionAgent:decisionAgent',
      'productionAgent:directorPlanAgent',
      'productionAgent:decisionAgent',
      'productionAgent:directorPlanAgent',
      'productionAgent:decisionAgent',
      'productionAgent:directorPlanAgent',
    ]);
    final messages =
        engine.agentMessages(projectId, family: agentFamilyProduction);
    expect(
      messages.where(
          (message) => message.toolName == 'run_sub_agent_storyboard_table'),
      isEmpty,
    );
    expect(messages.last.role, agentRoleAssistant);
    expect(messages.last.content, contains('最多重试 2 次'));
    expect(messages.last.content, contains('导演计划 Agent 未返回可写入内容'));
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

  test('ProductionAgent storyboard panel XML resolves asset refs and names',
      () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final decoyRoleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '误绑角色',
      describe: '不属于本集',
    );
    final decoySceneId = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '误绑场景',
      describe: '不属于本集',
    );
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    final sceneId = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '寒山宗门',
      describe: '冷白山门',
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, roleId]);
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, sceneId]);

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_panel',
        {'prompt': '写第一集分镜面板', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text(
        "<storyboardItem videoDesc='李澈穿过寒山宗门' "
        "prompt='冷白山门，少年入山，远景' track='主线' "
        "shouldGenerateImage='false' duration='3.5' "
        "associateAssetsIds='[&quot;A001&quot;,&quot;寒山宗门&quot;]'>"
        '</storyboardItem>',
      ),
    ];

    await engine.sendAgentMessage(
      projectId,
      '写分镜面板',
      autoMode: false,
      family: agentFamilyProduction,
    );

    expect(gateway.lastMessages.first['content'], contains('[A001, role, 李澈]'));
    expect(
      gateway.lastMessages.first['content'],
      contains('[A002, scene, 寒山宗门]'),
    );
    final rows = engine.storyboards(scriptId);
    expect(rows, hasLength(1));
    expect(rows.single.assetIds, [roleId, sceneId]);
    expect(rows.single.assetIds, isNot(contains(decoyRoleId)));
    expect(rows.single.assetIds, isNot(contains(decoySceneId)));
  });

  test('ProductionAgent storyboard panel XML accepts self closing items',
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
        'run_sub_agent_storyboard_panel',
        {'prompt': '写第一集分镜面板', 'scriptId': scriptId},
      ),
      AgentTurnResult.text(
        "<storyboardItem videoDesc='李澈立于寒山山门前' "
        "prompt='冷白山门，少年停步，远景' track='主线' "
        "shouldGenerateImage='true' duration='4' "
        "associateAssetsIds='[$roleId]' />",
      ),
    ];

    await engine.sendAgentMessage(
      projectId,
      '写自闭合分镜面板',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final rows = engine.storyboards(scriptId);
    expect(rows, hasLength(1));
    expect(rows.single.videoDesc, '李澈立于寒山山门前');
    expect(rows.single.prompt, '冷白山门，少年停步，远景');
    expect(rows.single.duration, '4');
    expect(rows.single.track, '主线');
    expect(rows.single.shouldGenerateImage, 1);
    expect(rows.single.assetIds, [roleId]);
  });

  test('ProductionAgent storyboard panel XML accepts field aliases', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, roleId]);

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_panel',
        {'prompt': '写第一集分镜面板', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text(
        "<storyboardItem videoDescription='李澈抬头望向山门匾额' "
        "imagePrompt='冷白山门，少年抬头，近景' track='主线' "
        "generateImage='false' durationSec='2.5' "
        "assetNames='[&quot;李澈&quot;]' />",
      ),
    ];

    await engine.sendAgentMessage(
      projectId,
      '写别名字段分镜面板',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final rows = engine.storyboards(scriptId);
    expect(rows, hasLength(1));
    expect(rows.single.videoDesc, '李澈抬头望向山门匾额');
    expect(rows.single.prompt, '冷白山门，少年抬头，近景');
    expect(rows.single.duration, '2.5');
    expect(rows.single.shouldGenerateImage, 0);
    expect(rows.single.assetIds, [roleId]);
  });

  test('ProductionAgent storyboard panel XML accepts child element fields',
      () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, roleId]);

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_panel',
        {'prompt': '写第一集分镜面板', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('''
<storyboardItem>
  <videoDesc>李澈穿过寒山宗门</videoDesc>
  <imagePrompt>冷白山门，少年入山，远景</imagePrompt>
  <track>主线</track>
  <generateImage>false</generateImage>
  <durationSec>2.5</durationSec>
  <assetNames>["李澈"]</assetNames>
</storyboardItem>
'''),
    ];

    await engine.sendAgentMessage(
      projectId,
      '写子元素字段分镜面板',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final rows = engine.storyboards(scriptId);
    expect(rows, hasLength(1));
    expect(rows.single.videoDesc, '李澈穿过寒山宗门');
    expect(rows.single.prompt, '冷白山门，少年入山，远景');
    expect(rows.single.track, '主线');
    expect(rows.single.duration, '2.5');
    expect(rows.single.shouldGenerateImage, 0);
    expect(rows.single.assetIds, [roleId]);
  });

  test('ProductionAgent storyboard panel accepts JSON storyboard items',
      () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, roleId]);

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_panel',
        {'prompt': '写第一集分镜面板', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('''
[
  {
    "videoDescription": "李澈穿过寒山宗门",
    "imagePrompt": "冷白山门，少年入山，远景",
    "track": "主线",
    "generateImage": false,
    "durationSec": 2.5,
    "assetNames": ["李澈"]
  }
]
'''),
    ];

    await engine.sendAgentMessage(
      projectId,
      '写 JSON 分镜面板',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final rows = engine.storyboards(scriptId);
    expect(rows, hasLength(1));
    expect(rows.single.videoDesc, '李澈穿过寒山宗门');
    expect(rows.single.prompt, '冷白山门，少年入山，远景');
    expect(rows.single.track, '主线');
    expect(rows.single.duration, '2.5');
    expect(rows.single.shouldGenerateImage, 0);
    expect(rows.single.assetIds, [roleId]);
  });

  test('ProductionAgent storyboard panel accepts wrapped JSON storyboard items',
      () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, roleId]);

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_panel',
        {'prompt': '写第一集分镜面板', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('''
{
  "storyboards": [
    {
      "shotDesc": "李澈穿过寒山宗门",
      "imagePrompt": "冷白山门，少年入山，远景",
      "track": "主线",
      "generateImage": false,
      "durationSec": 2.5,
      "assetNames": ["李澈"]
    }
  ]
}
'''),
    ];

    await engine.sendAgentMessage(
      projectId,
      '写包裹 JSON 分镜面板',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final rows = engine.storyboards(scriptId);
    expect(rows, hasLength(1));
    expect(rows.single.videoDesc, '李澈穿过寒山宗门');
    expect(rows.single.prompt, '冷白山门，少年入山，远景');
    expect(rows.single.track, '主线');
    expect(rows.single.duration, '2.5');
    expect(rows.single.shouldGenerateImage, 0);
    expect(rows.single.assetIds, [roleId]);
  });

  test('ProductionAgent storyboard panel accepts Chinese wrapped JSON items',
      () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, roleId]);

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_panel',
        {'prompt': '写第一集分镜面板', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('''
{
  "分镜": [
    {
      "画面描述": "李澈穿过寒山宗门",
      "图片提示词": "冷白山门，少年入山，远景",
      "分组": "主线",
      "是否生成图片": "否",
      "时长": 2.5,
      "资产名称": ["李澈"]
    }
  ]
}
'''),
    ];

    await engine.sendAgentMessage(
      projectId,
      '写中文 JSON 分镜面板',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final rows = engine.storyboards(scriptId);
    expect(rows, hasLength(1));
    expect(rows.single.videoDesc, '李澈穿过寒山宗门');
    expect(rows.single.prompt, '冷白山门，少年入山，远景');
    expect(rows.single.track, '主线');
    expect(rows.single.duration, '2.5');
    expect(rows.single.shouldGenerateImage, 0);
    expect(rows.single.assetIds, [roleId]);
  });

  test('ProductionAgent storyboard panel XML accepts Chinese child fields',
      () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, roleId]);

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_panel',
        {'prompt': '写第一集分镜面板', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('''
<storyboardItem>
  <画面描述>李澈穿过寒山宗门</画面描述>
  <图片提示词>冷白山门，少年入山，远景</图片提示词>
  <分组>主线</分组>
  <是否生成图片>否</是否生成图片>
  <时长>2.5</时长>
  <资产名称>["李澈"]</资产名称>
</storyboardItem>
'''),
    ];

    await engine.sendAgentMessage(
      projectId,
      '写中文 XML 分镜面板',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final rows = engine.storyboards(scriptId);
    expect(rows, hasLength(1));
    expect(rows.single.videoDesc, '李澈穿过寒山宗门');
    expect(rows.single.prompt, '冷白山门，少年入山，远景');
    expect(rows.single.track, '主线');
    expect(rows.single.duration, '2.5');
    expect(rows.single.shouldGenerateImage, 0);
    expect(rows.single.assetIds, [roleId]);
  });

  test('ProductionAgent storyboard panel XML accepts repeated asset elements',
      () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    final sceneId = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '寒山宗门',
      describe: '冷白山门',
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, roleId]);
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, sceneId]);

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_panel',
        {'prompt': '写第一集分镜面板', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('''
<storyboardItem>
  <videoDesc>李澈站在寒山宗门前</videoDesc>
  <imagePrompt>冷白山门，少年停步，远景</imagePrompt>
  <assetName>李澈</assetName>
  <assetName>寒山宗门</assetName>
</storyboardItem>
'''),
    ];

    await engine.sendAgentMessage(
      projectId,
      '写重复资产字段分镜面板',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final rows = engine.storyboards(scriptId);
    expect(rows, hasLength(1));
    expect(rows.single.videoDesc, '李澈站在寒山宗门前');
    expect(rows.single.assetIds, [roleId, sceneId]);
  });

  test('ProductionAgent storyboard panel XML preserves CDATA field text',
      () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '李澈',
      describe: '寒山少主',
    );
    db.execute('INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [scriptId, roleId]);

    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_panel',
        {'prompt': '写第一集分镜面板', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('''
<storyboardItem>
  <videoDesc><![CDATA[李澈看见<寒山令> & 抬头]]></videoDesc>
  <imagePrompt><![CDATA[冷白山门 <wide shot> & mist]]></imagePrompt>
  <duration>3</duration>
  <assetNames>["李澈"]</assetNames>
</storyboardItem>
'''),
    ];

    await engine.sendAgentMessage(
      projectId,
      '写 CDATA 分镜面板',
      autoMode: false,
      family: agentFamilyProduction,
    );

    final rows = engine.storyboards(scriptId);
    expect(rows, hasLength(1));
    expect(rows.single.videoDesc, '李澈看见<寒山令> & 抬头');
    expect(rows.single.prompt, '冷白山门 <wide shot> & mist');
    expect(rows.single.duration, '3');
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

  test('ProductionAgent 监督返回后自动模式等待用户确认再继续', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '李澈入山');
    gateway.turns = [
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_table',
        {'prompt': '构建分镜表', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('<storyboardTable>近景|横移</storyboardTable>'),
      AgentTurnResult.tool(
        'run_sub_agent_supervision',
        {'prompt': '审核分镜表', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text('监督结论：制作链路通过。'),
      AgentTurnResult.tool(
        'run_sub_agent_storyboard_panel',
        {'prompt': '不应自动写入面板', 'scriptId': scriptId},
      ),
      const AgentTurnResult.text(
        '<storyboardItem prompt="不应写入" videoDesc="不应写入" />',
      ),
    ];

    await engine.sendAgentMessage(
      projectId,
      '制作画布：构建分镜表并审核',
      autoMode: true,
      family: agentFamilyProduction,
    );

    expect(gateway.stages, [
      'productionAgent:decisionAgent',
      'productionAgent:storyboardTableAgent',
      'productionAgent:decisionAgent',
      'productionAgent:supervisionAgent',
    ]);
    final flowData = _productionAgentWorkData(db, projectId, scriptId);
    expect(flowData['storyboardTable'], '近景|横移');
    expect(flowData['supervision'], contains('制作链路通过'));
    expect(engine.storyboards(scriptId), isEmpty);
    final messages = engine.agentMessages(
      projectId,
      family: agentFamilyProduction,
    );
    expect(
      messages.where(
        (message) => message.toolName == 'run_sub_agent_storyboard_panel',
      ),
      isEmpty,
    );
    expect(messages.last.role, agentRoleAssistant);
    expect(messages.last.content, contains('请确认'));
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

class _Gateway implements ProviderGateway, ImageUnderstandingGateway {
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
  List<String> imageAnalysisPrompts = const [];
  List<String> imageAnalysisPaths = const [];
  String imageAnalysisResult = '';
  List<String> imageAnalysisResults = const [];
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
    imageAnalysisPrompts = [];
    imageAnalysisPaths = [];
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
  Future<TextResult> analyzeImage(
    String prompt,
    String imageAbsPath, {
    required String stage,
    CancelToken? cancelToken,
  }) async {
    imageAnalysisPrompts = [...imageAnalysisPrompts, prompt];
    imageAnalysisPaths = [...imageAnalysisPaths, imageAbsPath];
    final index = imageAnalysisPaths.length - 1;
    if (index < imageAnalysisResults.length) {
      return TextResult(imageAnalysisResults[index]);
    }
    return TextResult(imageAnalysisResult);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
