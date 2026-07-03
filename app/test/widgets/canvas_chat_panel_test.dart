import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/agent.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/production/canvas_chat_panel.dart';
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
    dir = Directory.systemTemp.createTempSync('dramaflow-canvaschat-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _Gateway(),
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

  testWidgets('空对话显示欢迎语与面板标题', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('剧本 Agent'), findsOneWidget); // 面板头部标题
    expect(find.textContaining('我是剧本 Agent'), findsOneWidget);
  });

  testWidgets('发送消息后追加用户与助手气泡并落库', (tester) async {
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

  testWidgets('提供 onClose 时显示关闭按钮并回调', (tester) async {
    var closed = false;
    await tester.pumpWidget(app(onClose: () => closed = true));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });
}
