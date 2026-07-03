import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/agent.dart';
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

  testWidgets('Agent 体系页展示部署配置、技能列表与记忆管理', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '记录一条记忆');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(engine.agentMessages(projectId), hasLength(2));

    await tester.tap(find.text('技能'));
    await tester.pumpAndSettle();
    expect(find.text('generate_events'), findsOneWidget);
    expect(find.textContaining('为章节生成事件摘要'), findsOneWidget);

    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    expect(find.text('记忆条目 2'), findsOneWidget);
    expect(find.text('记录一条记忆'), findsOneWidget);

    await tester.tap(find.text('部署'));
    await tester.pumpAndSettle();
    expect(find.text('执行模式'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent-deploy-mode-switch')));
    await tester.pumpAndSettle();
    expect(engine.agentUseMode(), isTrue);

    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空记忆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(engine.agentMessages(projectId), isEmpty);
    expect(find.text('记忆条目 0'), findsOneWidget);
  });
}
