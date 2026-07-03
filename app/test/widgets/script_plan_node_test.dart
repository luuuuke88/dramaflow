import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/script_plan.dart';
import 'package:dramaflow/src/screens/production/script_plan_node.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-scriptplan-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '规划测试');
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  // 桌面宽度，让 showDFAdaptiveDialog 走对话框而非全屏页，便于就地断言。
  Widget app() {
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MediaQuery(
        data: const MediaQueryData(size: Size(1200, 900)),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          locale: const Locale('zh'),
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 260,
              child: ScriptPlanNode(projectId: projectId),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('无规划时显示空态与撰写按钮', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('剧本规划'), findsOneWidget); // 节点标题
    expect(find.text('还没有剧本规划，点此撰写整体思路、节奏与要点。'), findsOneWidget);
    expect(find.text('撰写规划'), findsOneWidget);
  });

  testWidgets('已有规划时预览已存 Markdown 文本', (tester) async {
    engine.saveScriptPlan(projectId, '# 主线\n少年逆袭夺回家产');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.textContaining('少年逆袭夺回家产'), findsOneWidget);
    expect(find.text('还没有剧本规划，点此撰写整体思路、节奏与要点。'), findsNothing);
  });

  testWidgets('打开编辑器、写入并保存后落库且刷新预览', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 打开编辑对话框。
    await tester.tap(find.text('撰写规划'));
    await tester.pumpAndSettle();
    expect(find.text('编辑剧本规划'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '## 分集节奏\n共 12 集，每集一个钩子');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 持久化断言：engine 读回。
    expect(engine.scriptPlan(projectId), '## 分集节奏\n共 12 集，每集一个钩子');
    expect(find.text('剧本规划已保存'), findsOneWidget);
    // 预览刷新断言。
    expect(find.textContaining('每集一个钩子'), findsOneWidget);
  });

  testWidgets('编辑器取消不落库', (tester) async {
    engine.saveScriptPlan(projectId, '原始内容');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '被丢弃的改动');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(engine.scriptPlan(projectId), '原始内容');
  });
}
