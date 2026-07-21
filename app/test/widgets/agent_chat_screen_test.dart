import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/assistant_chat.dart';
import 'package:dramaflow/src/engine/assistant_deploy.dart';
import 'package:dramaflow/src/engine/assistant_skill_library.dart';
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
import 'package:dramaflow/src/widgets/shell.dart';
import 'package:dramaflow/src/widgets/external_link_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:go_router/go_router.dart';
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

class _SkillFileSelector extends FileSelectorPlatform {
  final XFile file;
  _SkillFileSelector(this.file);

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async =>
      file;
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

Future<void> _openAssistantAdvanced(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('assistant-advanced-button')));
  await tester.pumpAndSettle();
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

  testWidgets('剧本 Agent 回复中的外部链接由安全链接文本承载', (tester) async {
    gateway.turns.add(
      const AgentTurnResult.text('参考 https://example.com/script-guide'),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '给我参考资料');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ExternalLinkText &&
            widget.text.contains('https://example.com/script-guide'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('助手默认页只显示对话，高级面板按需打开管理功能', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('部署'), findsNothing);
    expect(find.text('技能'), findsNothing);
    expect(find.text('项目笔记'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('assistant-advanced-button')));
    await tester.pumpAndSettle();
    expect(find.text('部署'), findsOneWidget);
    expect(find.text('技能'), findsOneWidget);
    expect(find.text('项目笔记'), findsOneWidget);
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
    await _openAssistantAdvanced(tester);

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
    await _openAssistantAdvanced(tester);
    await tester.tap(find.text('技能'));
    await tester.pumpAndSettle();

    expect(find.text('style-note'), findsOneWidget);
    expect(find.textContaining('自定义 JS'), findsNothing);
    expect(find.textContaining('新增自定义技能'), findsNothing);

    final generateEventsToggle =
        find.byKey(const ValueKey('assistant-skill-toggle-generate_events'));
    await tester.scrollUntilVisible(
      generateEventsToggle,
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(generateEventsToggle);
    await tester.pumpAndSettle();
    expect(find.text('generate_events'), findsOneWidget);
    await tester.tap(generateEventsToggle);
    await tester.pumpAndSettle();
    final skill =
        engine.assistantSkills().singleWhere((s) => s.id == 'generate_events');
    expect(skill.enabled, isFalse);
  });

  testWidgets('桌面技能页可导入、搜索、预览并编辑托管 Markdown', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sourceDir = Directory(p.join(dir.path, 'picked-skill'))..createSync();
    final source = File(p.join(sourceDir.path, 'SKILL.md'))
      ..writeAsStringSync('''---
name: framing_guide
description: 分镜画幅规范
---
镜头必须先交代环境，再推进主体。
''');
    final originalSelector = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = _SkillFileSelector(XFile(source.path));
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await _openAssistantAdvanced(tester);
    await tester.tap(find.text('技能'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('assistant-skills-import')));
    await tester.pumpAndSettle();
    expect(find.textContaining('先交代环境'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('assistant-skills-search')), 'framing');
    await tester.pumpAndSettle();
    expect(find.text('framing_guide/SKILL.md'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('assistant-skill-file-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('assistant-skill-editor')),
        '---\nname: framing_guide\ndescription: 新说明\n---\n改后的镜头规则');
    await tester.tap(find.byKey(const ValueKey('assistant-skill-file-save')));
    await tester.pumpAndSettle();
    expect(
        engine.readManagedAssistantSkill('framing_guide'), contains('改后的镜头规则'));
  });

  testWidgets('390dp 技能页可重扫并从 Markdown 详情返回列表', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final skillDir = Directory(p.join(dir.path, 'skills', 'mobile_guide'))
      ..createSync(recursive: true);
    File(p.join(skillDir.path, 'SKILL.md')).writeAsStringSync('''---
name: mobile_guide
description: 移动端构图
---
保留主体安全区域。
''');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await _openAssistantAdvanced(tester);
    await tester.tap(find.text('技能'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assistant-skills-scan')));
    await tester.pumpAndSettle();
    expect(find.text('mobile_guide'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('skill-tree-directory-mobile_guide')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('skill-tree-file-mobile_guide/SKILL.md')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('保留主体安全区域'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assistant-skill-back')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('skill-tree-directory-mobile_guide')),
      findsOneWidget,
    );
  });

  testWidgets('桌面技能树展开深层 Markdown，预览并保存资源文件', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _writeMarkdownSkill(
      dir,
      id: 'camera_guide',
      description: '运镜参考',
      body: '入口内容',
    );
    final references =
        Directory(p.join(dir.path, 'skills', 'camera_guide', 'references'))
          ..createSync();
    File(p.join(references.path, 'shot-list.md')).writeAsStringSync('深层镜头表');
    engine.saveMarkdownAssistantSkill(
      filePath: p.join(dir.path, 'skills', 'camera_guide', 'SKILL.md'),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await _openAssistantAdvanced(tester);
    await tester.tap(find.text('技能'));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('skill-tree-toggle-camera_guide')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('skill-tree-toggle-camera_guide/references')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('skill-tree-file-camera_guide/references/shot-list.md'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('深层镜头表'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('assistant-skill-file-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('assistant-skill-editor')),
      '改后的深层镜头表',
    );
    await tester.tap(find.byKey(const ValueKey('assistant-skill-file-save')));
    await tester.pumpAndSettle();
    expect(
      engine.readManagedSkillLibraryFile(
        'camera_guide',
        'references/shot-list.md',
      ),
      '改后的深层镜头表',
    );
  });

  testWidgets('390dp 技能树可进入目录、搜索深层文件并逐层返回', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _writeMarkdownSkill(
      dir,
      id: 'camera_guide',
      description: '运镜参考',
      body: '入口内容',
    );
    final references =
        Directory(p.join(dir.path, 'skills', 'camera_guide', 'references'))
          ..createSync();
    File(p.join(references.path, 'shot-list.md')).writeAsStringSync('深层镜头表');
    engine.saveMarkdownAssistantSkill(
      filePath: p.join(dir.path, 'skills', 'camera_guide', 'SKILL.md'),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await _openAssistantAdvanced(tester);
    await tester.tap(find.text('技能'));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('skill-tree-directory-camera_guide')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
          const ValueKey('skill-tree-directory-camera_guide/references')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('skill-tree-file-camera_guide/references/shot-list.md'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('深层镜头表'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assistant-skill-back')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
          const ValueKey('skill-tree-directory-camera_guide/references')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('assistant-skills-search')),
      'shot-list',
    );
    await tester.pumpAndSettle();
    expect(find.text('camera_guide/references/shot-list.md'), findsOneWidget);
  });

  testWidgets('项目笔记页使用 project_notes API，删除走危险确认', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await _openAssistantAdvanced(tester);
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

    await _openAssistantAdvanced(tester);
    await tester.tap(find.text('项目笔记'));
    await tester.pumpAndSettle();
    expect(find.textContaining('监督模式'), findsNothing);
    expect(find.textContaining('RAG'), findsNothing);
  });

  testWidgets(
      '手机宽度下经由 /p/:pid/scriptAgent 真实 ShellRoute 进入时只有一层 AppBar（回归：曾经壳自身 '
      'AppBar+Tab 条与本页 Scaffold+AppBar 叠加成两层工具栏）', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/p/$projectId/scriptAgent',
      routes: [
        ShellRoute(
          builder: (c, s, child) => AppShell(child: child),
          routes: [
            GoRoute(path: '/', builder: (c, s) => const Text('home')),
            GoRoute(path: '/tasks', builder: (c, s) => const Text('tasks')),
            GoRoute(
                path: '/settings', builder: (c, s) => const Text('settings')),
            GoRoute(
              path: '/p/:pid/scriptAgent',
              builder: (c, s) => AgentChatScreen(
                  projectId: int.parse(s.pathParameters['pid']!)),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
        locale: const Locale('zh'),
        theme: buildTheme(Brightness.light),
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();

    // 手机宽度下必须是 _MobileShell（有底部 NavigationBar），且被壳承载的
    // scriptAgent 页不能再套自己的 Scaffold+AppBar：应当只有壳自身那一层
    // AppBar，而不是壳 AppBar + 本页 AppBar 叠成两层。
    expect(find.byType(NavigationBar), findsOneWidget,
        reason: '手机宽度应命中 _MobileShell');
    expect(find.byType(AppBar), findsOneWidget,
        reason: '壳的 AppBar 与本页自己的 AppBar 曾经会叠成两层，这里必须只剩一层');

    // 原 AppBar actions（tune/info/清空 + 模式开关）仍可达：内嵌操作条里的
    // 高级面板按钮应当还能点开。
    expect(find.byKey(const ValueKey('assistant-advanced-button')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assistant-advanced-button')));
    await tester.pumpAndSettle();
    expect(find.text('部署'), findsOneWidget);
  });
}
