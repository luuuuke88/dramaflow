import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/assistant_chat.dart';
import 'package:dramaflow/src/engine/assistant_deploy.dart';
import 'package:dramaflow/src/engine/assistant_skills.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/project_notes.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/agent/agent_chat_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Gateway implements ProviderGateway {
  final Queue<AgentTurnResult> turns = Queue<AgentTurnResult>();

  _Gateway([List<AgentTurnResult> seed = const []]) {
    turns.addAll(seed);
  }

  @override
  Future<AgentTurnResult> generateAgentTurn(
    String system,
    List<Map<String, String>> messages,
    List<AgentToolDef> tools, {
    required String stage,
    CancelToken? cancelToken,
  }) async =>
      turns.isEmpty
          ? const AgentTurnResult.text('好的，已收到。')
          : turns.removeFirst();

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
  late _Gateway gateway;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('dramaflow-agentchat-');
    final db = openEngineDb(':memory:');
    gateway = _Gateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
    );
    await engine.createProvider(
      name: 'azt',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );
    await engine.saveProviderModels('azt', [
      {'modelId': 'gpt-5.5', 'kind': 'text', 'enabled': true},
    ]);
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

  testWidgets('对话页使用 assistant_chat，并按入口隔离剧本/制作会话', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.textContaining('剧本 Agent'), findsWidgets);
    await tester.enterText(find.byType(TextField), '剧本侧推进事件');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(
      engine.assistantMessages(projectId, family: assistantFamilyScript),
      hasLength(2),
    );
    expect(
      engine.assistantMessages(projectId, family: assistantFamilyProduction),
      isEmpty,
    );

    await tester.tap(find.byKey(const ValueKey('assistant-family-production')));
    await tester.pumpAndSettle();
    expect(find.text('剧本侧推进事件'), findsNothing);

    await tester.enterText(find.byType(TextField), '制作侧推进分镜');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(
      engine.assistantMessages(projectId, family: assistantFamilyProduction),
      hasLength(2),
    );
  });

  testWidgets('自动/手动模式使用 assistantAutoMode 持久化', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(engine.assistantAutoMode(), isFalse);
    expect(find.text('手动确认'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(engine.assistantAutoMode(), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('自动连跑'), findsOneWidget);
  });

  testWidgets('确认卡片可拒绝，不执行待确认动作', (tester) async {
    gateway.turns.add(const AgentTurnResult.tool('generate_events', {}));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '生成事件');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(find.textContaining('需要确认'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assistant-confirm-reject')));
    await tester.pumpAndSettle();

    final messages =
        engine.assistantMessages(projectId, family: assistantFamilyScript);
    expect(messages.where((m) => m.confirmStatus == 'rejected'), hasLength(1));
    expect(find.textContaining('没有需要生成事件'), findsNothing);
  });

  testWidgets('部署页只展示两个助手基座并可保存文本模型绑定', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('部署'));
    await tester.pumpAndSettle();

    expect(engine.assistantDeployments(), hasLength(2));
    expect(find.text('scriptAgent'), findsOneWidget);
    expect(find.text('productionAgent'), findsOneWidget);
    expect(find.text('流水线'), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('assistant-deploy-edit-scriptAgent')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('assistant-deploy-vendor')), 'azt');
    await tester.enterText(
        find.byKey(const ValueKey('assistant-deploy-model')), 'gpt-5.5');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final deployment = engine
        .assistantDeployments()
        .singleWhere((d) => d.key == 'scriptAgent');
    expect(deployment.vendorId, 'azt');
    expect(deployment.modelName, 'gpt-5.5');
  });

  testWidgets('技能页只保留内置动作和 Markdown 技能，不暴露 custom-js 创建入口', (tester) async {
    _writeMarkdownSkill(
      dir,
      id: 'style-note',
      description: '画风提示',
      body: '统一冷白月光。',
    );
    engine.saveMarkdownAssistantSkill(
      filePath: p.join(dir.path, 'skills', 'style-note', 'SKILL.md'),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('技能'));
    await tester.pumpAndSettle();

    expect(find.text('generate_events'), findsOneWidget);
    expect(find.text('style-note'), findsOneWidget);
    expect(find.textContaining('自定义 JS'), findsNothing);
    expect(find.textContaining('新增自定义技能'), findsNothing);

    await tester.tap(
        find.byKey(const ValueKey('assistant-skill-toggle-generate_events')));
    await tester.pumpAndSettle();
    final skill =
        engine.assistantSkills().singleWhere((s) => s.id == 'generate_events');
    expect(skill.enabled, isFalse);
  });

  testWidgets('项目笔记页使用 project_notes API，删除走危险确认', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('项目笔记'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增笔记'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('project-note-name')), '角色设定');
    await tester.enterText(
        find.byKey(const ValueKey('project-note-content')), '林朝雪使用青霜剑');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(engine.projectNotes(projectId), hasLength(1));
    expect(find.text('角色设定'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('project-note-search')), '青霜');
    await tester.tap(find.byKey(const ValueKey('project-note-search-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('青霜剑'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('project-note-delete')));
    await tester.pumpAndSettle();
    expect(find.text('危险操作确认'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(engine.projectNotes(projectId), isEmpty);
  });

  testWidgets('页面不再出现监督模式和 RAG 设置入口', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.textContaining('监督模式'), findsNothing);
    expect(find.textContaining('RAG'), findsNothing);

    await tester.tap(find.text('项目笔记'));
    await tester.pumpAndSettle();
    expect(find.textContaining('监督模式'), findsNothing);
    expect(find.textContaining('RAG'), findsNothing);
  });
}
