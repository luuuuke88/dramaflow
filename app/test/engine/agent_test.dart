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
    var msg = engine.agentMessages(projectId).last;
    expect(msg.toolName, 'activate_skill');
    expect(msg.content, contains('技能正文：短剧台词要短'));

    gateway.turns = [
      AgentTurnResult.tool('read_skill_file', const {
        'name': 'style_polisher',
        'path': 'references/rules.md',
      }),
    ];
    await engine.sendAgentMessage(projectId, '读取技能规则', autoMode: false);

    msg = engine.agentMessages(projectId).last;
    expect(msg.toolName, 'read_skill_file');
    expect(msg.content, '规则：每句台词不超过二十字。');
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

  test('AgentMemoryService get 返回相关记忆、历史摘要和近期对话', () async {
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

    final context = await service.get(
      isolationKey: 'scriptAgent:$projectId',
      query: '寒山李澈',
    );

    expect(context.relatedMessages.map((item) => item.id),
        ['ctx_msg_1', 'ctx_msg_2']);
    expect(context.summaries.map((item) => item.id), ['ctx_summary']);
    expect(context.recentMessages.map((item) => item.id),
        ['ctx_msg_2', 'ctx_msg_3']);
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
        [agentRoleUser, agentRoleAssistant]);
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
