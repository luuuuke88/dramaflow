import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/agent.dart';
import 'package:dramaflow/src/engine/agent_memory.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/agent/agent_chat_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Gateway implements ProviderGateway {
  AgentTurnResult next = const AgentTurnResult.text('好的，已收到。');

  @override
  Future<AgentTurnResult> generateAgentTurn(
    String system,
    List<Map<String, String>> messages,
    List<AgentToolDef> tools, {
    required String stage,
    CancelToken? cancelToken,
  }) async =>
      next;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _writeMarkdownSkill(
  Directory dir, {
  required String id,
  required String description,
  required String body,
}) {
  final skillDir = Directory(p.join(dir.path, 'skills', id))
    ..createSync(recursive: true);
  File(p.join(skillDir.path, 'SKILL.md')).writeAsStringSync('''
---
name: $id
description: $description
---

$body
''');
}

void main() {
  late Directory dir;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-agentchat-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: 'Agent页测试');
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app() {
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
        locale: const Locale('zh'),
        theme: buildTheme(Brightness.light),
        home: AgentChatScreen(projectId: projectId),
      ),
    );
  }

  testWidgets('空对话显示欢迎语', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('剧本 Agent'), findsWidgets);
  });

  testWidgets('发送消息后追加用户与助手气泡', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '现在进度如何');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(find.text('现在进度如何'), findsOneWidget);
    expect(find.text('好的，已收到。'), findsOneWidget);
    expect(engine.agentMessages(projectId), hasLength(2));
  });

  testWidgets('对话页可切换剧本和制作 Agent 并隔离消息', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '剧本侧推进事件');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(engine.agentMessages(projectId, family: agentFamilyScript),
        hasLength(2));
    expect(engine.agentMessages(projectId, family: agentFamilyProduction),
        isEmpty);

    await tester.tap(find.byKey(const ValueKey('agent-family-production')));
    await tester.pumpAndSettle();
    expect(find.textContaining('导演计划'), findsOneWidget);
    expect(find.text('剧本侧推进事件'), findsNothing);

    await tester.enterText(find.byType(TextField), '制作侧推进分镜');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(engine.agentMessages(projectId, family: agentFamilyProduction),
        hasLength(2));
    expect(find.text('制作侧推进分镜'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent-family-script')));
    await tester.pumpAndSettle();
    expect(find.text('剧本侧推进事件'), findsOneWidget);
    expect(find.text('制作侧推进分镜'), findsNothing);
  });

  testWidgets('清空记忆按钮：确认后清空并提示', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '你好');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(engine.agentMessages(projectId), isNotEmpty);

    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(engine.agentMessages(projectId), isEmpty);
    expect(find.text('记忆已清空'), findsOneWidget);
  });

  testWidgets('移动端 Agent：清空记忆确认使用全屏表单并清空', (tester) async {
    engine.dispose();
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'mobile-clear-memory-media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: true),
    );
    projectId = engine.addProject(projectType: 'novel', name: '移动清空记忆测试');

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '移动端清空前消息');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(engine.agentMessages(projectId), isNotEmpty);

    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('清空记忆'), findsOneWidget);
    expect(find.text('确定清空全部对话记录吗？此操作无法撤销。'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(engine.agentMessages(projectId), isEmpty);
    expect(find.text('记忆已清空'), findsOneWidget);
  });

  testWidgets('内置能力说明弹窗可打开关闭', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('内置能力'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('内置能力'), findsNothing);
  });

  testWidgets('移动端 Agent：内置能力说明使用全屏信息页', (tester) async {
    engine.dispose();
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'mobile-skills-info-media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: true),
    );
    projectId = engine.addProject(projectType: 'novel', name: '移动能力说明测试');

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('内置能力'), findsOneWidget);
    expect(find.textContaining('已有流水线真实动作'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('内置能力'), findsNothing);
  });

  testWidgets('自动/手动模式切换持久化并在重建后恢复', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    // 默认 manual
    expect(engine.agentUseMode(), isFalse);
    expect(find.text('手动确认'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    // 切到 auto 并持久化
    expect(engine.agentUseMode(), isTrue);
    expect(find.text('自动连跑'), findsOneWidget);

    // 重建页面后从引擎恢复为 auto
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('自动连跑'), findsOneWidget);
  });

  testWidgets('记忆页可启停监督模式并在重建后恢复', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    expect(engine.agentSupervisionEnabled(), isFalse);
    expect(find.text('监督模式'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent-supervision-switch')));
    await tester.pumpAndSettle();

    expect(engine.agentSupervisionEnabled(), isTrue);
    expect(find.text('开启'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();

    expect(find.text('开启'), findsOneWidget);
  });

  testWidgets('Agent 体系页展示部署配置、技能列表与记忆管理', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '记录一条记忆');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(engine.agentMessages(projectId), hasLength(2));

    await tester.tap(find.text('技能'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -360));
    await tester.pumpAndSettle();
    expect(find.text('generate_events'), findsOneWidget);
    expect(find.textContaining('为章节生成事件摘要'), findsOneWidget);

    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    expect(find.text('记忆条目 2'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('记录一条记忆'), findsOneWidget);

    await tester.tap(find.text('部署'));
    await tester.pumpAndSettle();
    expect(find.text('执行模式'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent-deploy-mode-switch')));
    await tester.pumpAndSettle();
    expect(engine.agentUseMode(), isTrue);

    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-memory-clear-messages')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(engine.agentMessages(projectId), isEmpty);
    expect(find.text('记忆条目 0'), findsOneWidget);
  });

  testWidgets('Agent 体系页按 Agent 分组部署、按归属过滤技能并保存记忆设置', (tester) async {
    _writeMarkdownSkill(
      dir,
      id: 'script_style_skill',
      description: '剧本决策技能',
      body: '剧本决策规则',
    );
    _writeMarkdownSkill(
      dir,
      id: 'production_style_skill',
      description: '制作执行技能',
      body: '制作执行规则',
    );
    engine.saveMarkdownAgentSkill(
      filePath: p.join(dir.path, 'skills', 'script_style_skill', 'SKILL.md'),
      attribution: 'script_agent_decision',
    );
    engine.saveMarkdownAgentSkill(
      filePath:
          p.join(dir.path, 'skills', 'production_style_skill', 'SKILL.md'),
      attribution: 'production_agent_execution',
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('部署'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-deploy-group-scriptAgent')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('agent-deploy-group-productionAgent')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('agent-deploy-group-pipeline')),
        findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-deploy-group-scriptAgent')),
        matching: find.text('剧本 Agent'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-deploy-group-productionAgent')),
        matching: find.text('制作 Agent'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-deploy-group-pipeline')),
        matching: find.text('流水线'),
      ),
      findsWidgets,
    );

    await tester.tap(find.text('技能'));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('agent-skill-attribution-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('制作执行').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('production_style_skill'),
      320,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('production_style_skill'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).last, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('agent-skill-attribution-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('剧本决策').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('script_style_skill'),
      -320,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('script_style_skill'), findsOneWidget);
    expect(find.text('production_style_skill'), findsNothing);

    await tester.drag(find.byType(Scrollable).last, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-custom-skill-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-skill-id-field')),
      'custom_ui_decision_only',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-skill-name-field')),
      '界面归属技能',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-skill-description-field')),
      '从剧本决策筛选页创建。',
    );
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    expect(
      engine
          .agentSkills(attribution: 'script_agent_decision')
          .map((skill) => skill.id),
      contains('custom_ui_decision_only'),
    );
    expect(find.text('界面归属技能'), findsOneWidget);

    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('agent-rag-limit-field')),
      '4',
    );
    await tester
        .ensureVisible(find.byKey(const ValueKey('agent-rag-limit-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-rag-limit-save')));
    await tester.pumpAndSettle();
    expect(engine.agentRagLimit(), 4);
  });

  testWidgets('技能页可编辑技能描述并启停技能定义', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('技能'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -360));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('agent-skill-edit-generate_events')));
    await tester.pumpAndSettle();

    expect(find.text('编辑技能'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('agent-skill-description-field')),
      '只处理用户明确选择的章节事件。',
    );
    await tester.tap(find.byKey(const ValueKey('agent-skill-enabled-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final skill = engine
        .agentSkills()
        .singleWhere((item) => item.id == 'generate_events');
    expect(skill.description, '只处理用户明确选择的章节事件。');
    expect(skill.enabled, isFalse);
    expect(find.text('只处理用户明确选择的章节事件。'), findsOneWidget);
  });

  testWidgets('移动端 Agent：技能编辑使用全屏表单并保存', (tester) async {
    engine.dispose();
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'mobile-media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: true),
    );
    projectId = engine.addProject(projectType: 'novel', name: '移动Agent页测试');

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('技能'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('agent-skill-edit-generate_events')),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -140));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('agent-skill-edit-generate_events')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('编辑技能'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('agent-skill-description-field')),
      '移动端也能编辑技能。',
    );
    await tester.tap(find.byKey(const ValueKey('agent-skill-enabled-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final skill = engine
        .agentSkills()
        .singleWhere((item) => item.id == 'generate_events');
    expect(skill.description, '移动端也能编辑技能。');
    expect(skill.enabled, isFalse);
    expect(find.text('移动端也能编辑技能。'), findsOneWidget);
  });

  testWidgets('技能页可新增自定义脚本技能', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('技能'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-custom-skill-add')));
    await tester.pumpAndSettle();

    expect(find.text('新增自定义技能'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-skill-id-field')),
      'custom_echo',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-skill-name-field')),
      '自定义回声',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-skill-description-field')),
      '返回用户传入的 text。',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-skill-schema-field')),
      '{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-skill-script-field')),
      r'return `ok:${args.text}`;',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final skill =
        engine.agentSkills().singleWhere((item) => item.id == 'custom_echo');
    expect(skill.name, '自定义回声');
    expect(skill.description, '返回用户传入的 text。');
    expect(skill.type, 'custom-js-agent');
    expect(skill.schema['required'], ['text']);
    expect(skill.script, r'return `ok:${args.text}`;');
    await tester.drag(find.byType(ListView).last, const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('自定义回声'), findsOneWidget);
  });

  testWidgets('移动端 Agent：新增自定义技能使用全屏表单并保存', (tester) async {
    engine.dispose();
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'mobile-custom-skill-media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: true),
    );
    projectId = engine.addProject(projectType: 'novel', name: '移动自定义技能测试');

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('技能'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-custom-skill-add')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('新增自定义技能'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-skill-id-field')),
      'mobile_echo',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-skill-name-field')),
      '移动回声',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-skill-description-field')),
      '移动端创建的自定义技能。',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-skill-schema-field')),
      '{"type":"object","properties":{"text":{"type":"string"}}}',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-custom-skill-script-field')),
      r'return args.text;',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final skill =
        engine.agentSkills().singleWhere((item) => item.id == 'mobile_echo');
    expect(skill.name, '移动回声');
    expect(skill.description, '移动端创建的自定义技能。');
    expect(skill.type, 'custom-js-agent');
    expect(skill.script, r'return args.text;');
  });

  testWidgets('部署页可配置阶段模型与 Agent 参数', (tester) async {
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

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('部署'));
    await tester.pumpAndSettle();
    expect(find.text('剧本决策 Agent'), findsOneWidget);
    expect(find.textContaining('gpt-5.5'), findsWidgets);

    await tester.scrollUntilVisible(
      find.byKey(
          const ValueKey('agent-deploy-model-scriptAgent:decisionAgent')),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -140));
    await tester.pumpAndSettle();
    await tester.tap(find
        .byKey(const ValueKey('agent-deploy-model-scriptAgent:decisionAgent')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('gpt-5.4-mini').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(
          const ValueKey('agent-deploy-max-tokens-scriptAgent:decisionAgent')),
      '1200',
    );
    await tester.enterText(
      find.byKey(
          const ValueKey('agent-deploy-temperature-scriptAgent:decisionAgent')),
      '35',
    );
    await tester.ensureVisible(find
        .byKey(const ValueKey('agent-deploy-save-scriptAgent:decisionAgent')));
    await tester.pumpAndSettle();
    await tester.tap(find
        .byKey(const ValueKey('agent-deploy-save-scriptAgent:decisionAgent')));
    await tester.pumpAndSettle();

    final deployment = engine
        .agentDeployments()
        .singleWhere((item) => item.key == 'scriptAgent:decisionAgent');
    expect(deployment.modelName, 'gpt-5.4-mini');
    expect(deployment.maxOutputTokens, 1200);
    expect(deployment.temperature, 35);
    expect(deployment.disabled, isFalse);
  });

  testWidgets('记忆页可新增长期记忆并与对话历史分开展示', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    expect(find.text('长期记忆 0'), findsOneWidget);

    await tester.tap(find.text('新增记忆'));
    await tester.pumpAndSettle();
    expect(find.text('新增长期记忆'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('agent-memory-name-field')),
      '主角设定',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-memory-content-field')),
      '寒山少主李澈，外冷内热。',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(engine.agentLongTermMemories(projectId), hasLength(1));
    expect(find.text('长期记忆 1'), findsOneWidget);
    expect(find.text('主角设定'), findsOneWidget);
    expect(find.textContaining('寒山少主李澈'), findsOneWidget);
  });

  testWidgets('记忆页可配置 RAG 搜索记忆条数', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('搜索记忆条数'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-rag-limit-field')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-rag-limit-field')),
      '2',
    );
    await tester
        .ensureVisible(find.byKey(const ValueKey('agent-rag-limit-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-rag-limit-save')));
    await tester.pumpAndSettle();

    expect(
      engine.db
          .select("SELECT value FROM o_setting WHERE key='ragLimit'")
          .single['value'],
      '2',
    );
  });

  testWidgets('记忆页可配置完整 Agent 记忆参数', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('摘要触发消息数'), findsOneWidget);
    expect(find.text('摘要最大字数'), findsOneWidget);
    expect(find.text('短期上下文条数'), findsOneWidget);
    expect(find.text('历史摘要条数'), findsOneWidget);
    expect(find.text('搜索记忆条数'), findsOneWidget);
    expect(find.text('深度召回摘要数'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('agent-memory-messages-per-summary-field')),
      '4',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-memory-summary-max-length-field')),
      '640',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-memory-short-term-limit-field')),
      '6',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-memory-summary-limit-field')),
      '8',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-rag-limit-field')),
      '2',
    );
    await tester.enterText(
      find.byKey(
        const ValueKey('agent-memory-deep-retrieve-summary-limit-field'),
      ),
      '7',
    );
    await tester
        .ensureVisible(find.byKey(const ValueKey('agent-rag-limit-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-rag-limit-save')));
    await tester.pumpAndSettle();

    String setting(String key) => engine.db.select(
            'SELECT value FROM o_setting WHERE key=?', [key]).single['value']
        as String;

    expect(setting('agent.memory.messagesPerSummary'), '4');
    expect(setting('agent.memory.summaryMaxLength'), '640');
    expect(setting('agent.memory.shortTermLimit'), '6');
    expect(setting('agent.memory.summaryLimit'), '8');
    expect(setting('agent.memory.ragLimit'), '2');
    expect(setting('ragLimit'), '2');
    expect(setting('agent.memory.deepRetrieveSummaryLimit'), '7');
  });

  testWidgets('记忆页可按类型清空摘要和长期记忆且保留对话', (tester) async {
    engine.saveAgentMemory(
      projectId,
      name: '角色守则',
      content: '李澈必须保持正派。',
    );
    engine.db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'ui_summary_msg_user',
        '',
        '用户说李澈来自寒山。',
        DateTime.now().millisecondsSinceEpoch,
        '{}',
        'scriptAgent:$projectId',
        '[]',
        agentRoleUser,
        1,
        agentMemoryTypeMessage,
      ],
    );
    engine.db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'ui_summary_msg_assistant',
        '',
        '助手确认李澈不能写成反派。',
        DateTime.now().millisecondsSinceEpoch + 1,
        '{}',
        'scriptAgent:$projectId',
        '[]',
        agentRoleAssistant,
        1,
        agentMemoryTypeMessage,
      ],
    );
    engine.db.execute(
      'INSERT INTO memories '
      '(id,name,content,createTime,embedding,isolationKey,relatedMessageIds,role,summarized,type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'ui_summary',
        '摘要',
        '用户和助手讨论过寒山设定。',
        DateTime.now().millisecondsSinceEpoch,
        '{}',
        'scriptAgent:$projectId',
        '["ui_summary_msg_user","ui_summary_msg_assistant"]',
        'assistant',
        0,
        agentMemoryTypeSummary,
      ],
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '记住寒山设定');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(engine.agentMessages(projectId), hasLength(2));

    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    expect(find.text('历史摘要 1'), findsOneWidget);
    expect(find.text('用户和助手讨论过寒山设定。'), findsOneWidget);
    expect(find.text('关联原文 2'), findsOneWidget);
    await tester.ensureVisible(find.text('关联原文 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关联原文 2'));
    await tester.pumpAndSettle();
    expect(find.text('用户说李澈来自寒山。'), findsOneWidget);
    expect(find.text('助手确认李澈不能写成反派。'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent-memory-clear-summary')));
    await tester.pumpAndSettle();
    expect(
      engine.db.select(
        'SELECT COUNT(*) AS n FROM memories WHERE isolationKey=? AND type=?',
        ['scriptAgent:$projectId', agentMemoryTypeSummary],
      ).single['n'],
      0,
    );
    expect(engine.agentMessages(projectId), hasLength(2));
    expect(engine.agentLongTermMemories(projectId), hasLength(1));
    await tester.pump();
    expect(find.text('用户和助手讨论过寒山设定。'), findsNothing);
    await tester.drag(find.byType(ListView).last, const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(find.text('历史摘要 0'), findsOneWidget);
    expect(find.text('记忆已清空'), findsOneWidget);

    await tester.drag(find.byType(ListView).last, const Offset(0, 520));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-memory-clear-note')));
    await tester.pumpAndSettle();
    expect(engine.agentLongTermMemories(projectId), isEmpty);
    expect(engine.agentMessages(projectId), hasLength(2));
  });

  testWidgets('移动端 Agent：新增长期记忆使用全屏表单并保存', (tester) async {
    engine.dispose();
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'mobile-memory-media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: true),
    );
    projectId = engine.addProject(projectType: 'novel', name: '移动记忆测试');

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增记忆'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('新增长期记忆'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('agent-memory-name-field')),
      '移动主角设定',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-memory-content-field')),
      '移动端保存的长期记忆。',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final memories = engine.agentLongTermMemories(projectId);
    expect(memories, hasLength(1));
    expect(memories.single.name, '移动主角设定');
    expect(memories.single.content, '移动端保存的长期记忆。');
  });

  testWidgets('记忆页可编辑已有长期记忆', (tester) async {
    final id = engine.saveAgentMemory(
      projectId,
      name: '主角设定',
      content: '旧设定',
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('agent-memory-edit-$id')));
    await tester.pumpAndSettle();

    expect(find.text('编辑长期记忆'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('agent-memory-name-field')),
      '主角新设定',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-memory-content-field')),
      '寒山少主李澈，不能写成反派。',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final memory = engine.agentLongTermMemories(projectId).single;
    expect(memory.id, id);
    expect(memory.name, '主角新设定');
    expect(memory.content, contains('不能写成反派'));
    expect(find.text('主角新设定'), findsOneWidget);
  });

  testWidgets('移动端 Agent：编辑长期记忆使用全屏表单并保存', (tester) async {
    engine.dispose();
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'mobile-memory-edit-media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: true),
    );
    projectId = engine.addProject(projectType: 'novel', name: '移动编辑记忆测试');
    final id = engine.saveAgentMemory(
      projectId,
      name: '旧移动设定',
      content: '旧移动内容',
    );

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('agent-memory-edit-$id')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('编辑长期记忆'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('agent-memory-name-field')),
      '移动新设定',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-memory-content-field')),
      '移动端编辑后的长期记忆。',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final memory = engine.agentLongTermMemories(projectId).single;
    expect(memory.id, id);
    expect(memory.name, '移动新设定');
    expect(memory.content, '移动端编辑后的长期记忆。');
  });
}
