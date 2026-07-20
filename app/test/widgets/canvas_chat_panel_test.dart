import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/assistant_chat.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/production/canvas_chat_panel.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:dramaflow/src/widgets/external_link_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Gateway implements ProviderGateway {
  final Queue<Object> turns = Queue<Object>();

  _Gateway([List<Object> seed = const []]) {
    turns.addAll(seed);
  }

  @override
  Future<AgentTurnResult> generateAgentTurn(
    String system,
    List<Map<String, String>> messages,
    List<AgentToolDef> tools, {
    required String stage,
    CancelToken? cancelToken,
  }) async {
    final next = turns.isEmpty
        ? const AgentTurnResult.text('好的，已收到。')
        : turns.removeFirst();
    if (next is EngineException) throw next;
    return next as AgentTurnResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Engine engine;
  late int projectId;
  late _Gateway gateway;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-canvaschat-');
    final db = openEngineDb(':memory:');
    gateway = _Gateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '画布对话测试');
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app({VoidCallback? onClose}) {
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
        locale: const Locale('zh'),
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: CanvasChatPanel(projectId: projectId, onClose: onClose),
        ),
      ),
    );
  }

  testWidgets('空对话显示制作助手标题与欢迎语', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('制作 Agent'), findsOneWidget);
    expect(find.textContaining('我是制作 Agent'), findsOneWidget);
  });

  testWidgets('发送消息写入 production 助手会话', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '现在进度如何');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(find.text('现在进度如何'), findsOneWidget);
    expect(find.text('好的，已收到。'), findsOneWidget);
    expect(
      engine.assistantMessages(projectId, family: assistantFamilyProduction),
      hasLength(2),
    );
  });

  testWidgets('制作 Agent 回复中的 Markdown 链接可由统一链接组件渲染', (tester) async {
    gateway.turns.add(
      const AgentTurnResult.text('请看[镜头说明](https://example.com/shot-guide)。'),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '查看镜头说明');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ExternalLinkText &&
            widget.text.contains('https://example.com/shot-guide'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('花钱工具调用显示确认卡片，批准后执行动作', (tester) async {
    gateway.turns.add(const AgentTurnResult.tool('generate_events', {}));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '生成事件');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(find.textContaining('需要确认'), findsOneWidget);
    expect(
      engine
          .assistantMessages(projectId, family: assistantFamilyProduction)
          .last
          .role,
      assistantRoleConfirm,
    );

    await tester.tap(find.byKey(const ValueKey('assistant-confirm-approve')));
    await tester.pumpAndSettle();

    final messages =
        engine.assistantMessages(projectId, family: assistantFamilyProduction);
    expect(messages.where((m) => m.confirmStatus == 'approved'), hasLength(1));
    expect(find.textContaining('没有需要生成事件的章节'), findsOneWidget);
  });

  testWidgets('errKey JSON 消息渲染为本地化错误文案', (tester) async {
    gateway.turns.add(const EngineException(errNetwork));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '测试错误');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(find.text('网络请求失败'), findsOneWidget);
  });

  testWidgets('清空按钮确认后只清空 production 助手会话', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '你好');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(
      engine.assistantMessages(projectId, family: assistantFamilyProduction),
      isNotEmpty,
    );

    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(
      engine.assistantMessages(projectId, family: assistantFamilyProduction),
      isEmpty,
    );
    expect(find.text('对话已清空'), findsOneWidget);
  });

  testWidgets('提供 onClose 时显示关闭按钮并回调', (tester) async {
    var closed = false;
    await tester.pumpWidget(app(onClose: () => closed = true));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });
}
