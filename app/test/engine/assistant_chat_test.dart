import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/assistant_chat.dart';
import 'package:dramaflow/src/engine/assistant_skills.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
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
  Object? failWith;

  @override
  Future<AgentTurnResult> generateAgentTurn(
    String system,
    List<Map<String, String>> messages,
    List<AgentToolDef> tools, {
    required String stage,
    CancelToken? cancelToken,
  }) async {
    if (failWith != null) {
      throw failWith!;
    }
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

/// 回合结果可手动 Completer 卡住的网关：用于复现"清空记忆发生在请求飞行中"的
/// 竞态——测试拿到 completer 后可以在请求挂起期间执行别的引擎调用（比如清空），
/// 再手动 complete 观察飞行请求 resolve 之后的行为。
class _PendingGateway implements ProviderGateway {
  final List<Completer<AgentTurnResult>> completers = [];

  @override
  Future<AgentTurnResult> generateAgentTurn(
    String system,
    List<Map<String, String>> messages,
    List<AgentToolDef> tools, {
    required String stage,
    CancelToken? cancelToken,
  }) {
    final completer = Completer<AgentTurnResult>();
    completers.add(completer);
    return completer.future;
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

  AssistantSkill importSkill(String name, String description, String body) {
    final file = File(p.join(dir.path, '$name.md'))
      ..writeAsStringSync(
        '---\nname: $name\ndescription: $description\n---\n$body',
      );
    return engine.saveMarkdownAssistantSkill(filePath: file.path);
  }

  AssistantSkill importSkillPackage(
    String name, {
    required String body,
    required String resource,
  }) {
    final package = Directory(p.join(dir.path, '$name-package'))
      ..createSync();
    final entry = File(p.join(package.path, 'SKILL.md'))
      ..writeAsStringSync(
        '---\nname: $name\ndescription: 运镜规范\n---\n$body',
      );
    File(p.join(package.path, resource)).writeAsStringSync('资源：$resource');
    return engine.saveMarkdownAssistantSkill(filePath: entry.path);
  }

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

  test('网关报错时只追加一条错误消息，不会再补一条空气泡', () async {
    gateway.failWith = Exception('网关连接失败');

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
    final decoded = jsonDecode(messages.last.content) as Map;
    expect(decoded['errKey'], errLlmFormat);
  });

  test('技能正文不进入初始 system prompt，目录和两个工具可见', () async {
    importSkill('camera_guide', '运镜规范', '不可预先泄露的正文');
    gateway.turns = const [AgentTurnResult.text('收到')];

    await engine.sendAssistantMessage(
      projectId,
      '帮我规划镜头',
      family: assistantFamilyScript,
      autoMode: false,
    );

    expect(gateway.lastSystem, contains('camera_guide'));
    expect(gateway.lastSystem, isNot(contains('不可预先泄露的正文')));
    expect(
      gateway.lastTools.map((tool) => tool.name),
      containsAll(['activate_skill', 'read_skill_file']),
    );
  });

  test('manual 会话在激活后自动继续一次并将正文作为工具结果回传', () async {
    importSkill('camera_guide', '运镜规范', '先建立空间关系');
    gateway.turns = const [
      AgentTurnResult.tool('activate_skill', {'skillName': 'camera_guide'}),
      AgentTurnResult.text('我会按空间关系设计镜头。'),
    ];

    await engine.sendAssistantMessage(
      projectId,
      '规划镜头',
      family: assistantFamilyScript,
      autoMode: false,
    );

    expect(gateway.callCount, 2);
    expect(gateway.lastMessages.last['content'], contains('先建立空间关系'));
    expect(
      engine
          .assistantMessages(projectId, family: assistantFamilyScript)
          .map((message) => message.role),
      ['user', 'tool', 'assistant'],
    );
  });

  test('未激活资源读取以工具错误回传，不能绕过当前会话边界', () async {
    importSkillPackage(
      'camera_guide',
      body: '规则',
      resource: 'notes.md',
    );
    gateway.turns = const [
      AgentTurnResult.tool('read_skill_file', {
        'skillName': 'camera_guide',
        'relativePath': 'notes.md',
      }),
      AgentTurnResult.text('请先激活技能。'),
    ];

    await engine.sendAssistantMessage(
      projectId,
      '读取资源',
      family: assistantFamilyProduction,
      autoMode: false,
    );

    expect(gateway.callCount, 2);
    expect(gateway.lastMessages.last['content'], contains('skillMissing'));
    // Bug 2 回归：失败的技能工具调用必须存成 assistant role（走本地化渲染、
    // 不被 UI 标成"已执行”），不能是 tool role（对照 _runAssistantActionAndAppend
    // 失败分支的既有写法）。
    final failure = engine
        .assistantMessages(projectId, family: assistantFamilyProduction)
        .singleWhere((m) => m.toolName == 'read_skill_file');
    expect(failure.role, assistantRoleAssistant);
  });

  test('连续技能工具最多执行三次，不挤占业务动作上限', () async {
    importSkill('camera_guide', '运镜规范', '规则');
    gateway.turns = const [
      AgentTurnResult.tool('activate_skill', {'skillName': 'camera_guide'}),
      AgentTurnResult.tool('activate_skill', {'skillName': 'camera_guide'}),
      AgentTurnResult.tool('activate_skill', {'skillName': 'camera_guide'}),
      AgentTurnResult.text('不应继续到这一轮'),
    ];

    await engine.sendAssistantMessage(
      projectId,
      '读取技能',
      family: assistantFamilyScript,
      autoMode: false,
    );

    expect(gateway.callCount, 3);
    final limitMessage =
        engine.assistantMessages(projectId, family: assistantFamilyScript).last;
    expect(limitMessage.content, contains('assistantSkillToolLimit'));
    // Bug 2 回归：跳数超限是失败/中止提示，不是一次成功执行的技能结果，role
    // 必须是 assistant（走本地化渲染），不能是 tool（会被 UI 原样显示 JSON
    // 并标成"已执行"）。
    expect(limitMessage.role, assistantRoleAssistant);
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

  test('manual 模式下 get_status 探测后还能再进行一轮', () async {
    // 手动模式以前"跑完一个工具调用就停"，如果 AI 第一步只是调用免确认的
    // get_status 探路（比如不确定该操作哪个 scriptId），整轮就直接结束，
    // 用户只看到一段状态文本，AI 没机会说明或接着动手——只能重新发一遍。
    // 现在允许 get_status 这类只读探测之后再给一轮，让 AI 能继续解释/行动。
    gateway.turns = [
      const AgentTurnResult.tool('get_status', {}),
      const AgentTurnResult.text('已了解现状，建议先补全资产提取。'),
    ];

    await engine.sendAssistantMessage(
      projectId,
      '看看进度',
      family: assistantFamilyScript,
      autoMode: false,
    );

    expect(gateway.callCount, 2);
    final messages = engine.assistantMessages(
      projectId,
      family: assistantFamilyScript,
    );
    expect(messages.last.role, 'assistant');
    expect(messages.last.content, '已了解现状，建议先补全资产提取。');
  });

  test('manual 模式下真实动作只执行一轮，不会自行连续追加', () async {
    gateway.turns = [
      const AgentTurnResult.tool('note_search', {'query': '角色'}),
      const AgentTurnResult.text('不应继续到第二轮'),
    ];

    await engine.sendAssistantMessage(
      projectId,
      '查一下笔记',
      family: assistantFamilyScript,
      autoMode: false,
    );

    expect(gateway.callCount, 1);
    final messages = engine.assistantMessages(
      projectId,
      family: assistantFamilyScript,
    );
    expect(messages.last.role, 'tool');
    expect(messages.last.toolName, 'note_search');
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
    importSkill('camera_guide', '运镜规范', '规则');
    engine.activateAssistantSkill(
      projectId,
      family: assistantFamilyScript,
      skillName: 'camera_guide',
    );
    engine.clearAssistantChat(projectId, family: assistantFamilyScript);
    expect(
      engine.assistantMessages(projectId, family: assistantFamilyScript),
      isEmpty,
    );
    expect(
      engine.activatedAssistantSkillIds(
        projectId,
        family: assistantFamilyScript,
      ),
      isEmpty,
    );
  });

  group('Bug 1 回归：清空记忆发生在请求飞行中不能被复活', () {
    test('飞行中的普通对话请求 resolve 后，清空后的消息列表仍然为空', () async {
      final pendingGateway = _PendingGateway();
      final flightEngine = Engine(
        db: db,
        media: MediaStore(p.join(dir.path, 'media-flight-text')),
        gateway: pendingGateway,
        config: EngineConfig(db, isMobile: false),
      );
      addTearDown(flightEngine.dispose);

      // sendAssistantMessage 在真正调用 gateway 之前全是同步代码（保存用户
      // 消息、进入 _driveAssistantLoop、发起 generateAgentTurn），所以这里不
      // 需要额外 pump：不 await 这个 Future，completer 已经就绪，用户消息也
      // 已经落库——这正是复现时"发消息等回复期间点清空"的那个飞行窗口。
      final flightFuture = flightEngine.sendAssistantMessage(
        projectId,
        '你好，请帮我推进',
        family: assistantFamilyScript,
        autoMode: false,
      );

      expect(pendingGateway.completers, hasLength(1));
      expect(
        engine.assistantMessages(projectId, family: assistantFamilyScript),
        hasLength(1),
        reason: '飞行请求发起时应该已经把用户消息落库',
      );

      engine.clearAssistantChat(projectId, family: assistantFamilyScript);
      expect(
        engine.assistantMessages(projectId, family: assistantFamilyScript),
        isEmpty,
        reason: '清空应该立刻生效',
      );

      // 手动放行飞行中的请求，让它带着"清空前"的内存态尝试回写。
      pendingGateway.completers.single.complete(
        const AgentTurnResult.text('抱歉久等了，已经处理好了。'),
      );
      await flightFuture;

      expect(
        engine.assistantMessages(projectId, family: assistantFamilyScript),
        isEmpty,
        reason: '飞行请求完成后不能把清空前的消息复活',
      );
    });

    test('飞行中的技能激活请求 resolve 后，清空后的已激活技能集合仍然为空', () async {
      importSkill('camera_guide', '运镜规范', '先建立空间关系');
      final pendingGateway = _PendingGateway();
      final flightEngine = Engine(
        db: db,
        media: MediaStore(p.join(dir.path, 'media-flight-skill')),
        gateway: pendingGateway,
        config: EngineConfig(db, isMobile: false),
      );
      addTearDown(flightEngine.dispose);

      unawaited(flightEngine.sendAssistantMessage(
        projectId,
        '规划镜头',
        family: assistantFamilyScript,
        autoMode: false,
      ));
      expect(pendingGateway.completers, hasLength(1));

      engine.clearAssistantChat(projectId, family: assistantFamilyScript);
      expect(
        engine.activatedAssistantSkillIds(
          projectId,
          family: assistantFamilyScript,
        ),
        isEmpty,
      );

      pendingGateway.completers.single.complete(
        const AgentTurnResult.tool(
          'activate_skill',
          {'skillName': 'camera_guide'},
        ),
      );
      // 只需要推进一步：足够让 _driveAssistantLoop 处理完这次 resolve——不管是
      // 修复后直接因代际号过期放弃，还是修复前继续激活技能并把状态写回去。
      // 不等待整条消息链跑完（那还需要第二轮 gateway 调用），所以不用第二个
      // completer，也不会因此挂起。
      await Future<void>.delayed(Duration.zero);

      expect(
        engine.activatedAssistantSkillIds(
          projectId,
          family: assistantFamilyScript,
        ),
        isEmpty,
        reason: '飞行请求 resolve 后不能把清空前的技能激活状态复活',
      );
    });
  });
}
