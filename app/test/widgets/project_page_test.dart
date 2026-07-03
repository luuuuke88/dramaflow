import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/screens/project/project_list_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Engine engine;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-projpage-');
    engine = Engine(
      db: openEngineDb(':memory:'),
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(openEngineDb(':memory:'), isMobile: false),
    );
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app() {
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(path: '/', builder: (c, s) => const Scaffold(body: ProjectListScreen())),
      GoRoute(
          path: '/p/:pid/novel', builder: (c, s) => const Text('novel-page')),
    ]);
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
        locale: const Locale('zh'),
        theme: buildTheme(Brightness.light),
        routerConfig: router,
      ),
    );
  }

  testWidgets('空态：提示与新建按钮', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('暂无项目'), findsOneWidget);
    expect(find.text('新建项目'), findsNWidgets(2)); // 头部+空态
  });

  testWidgets('项目卡片渲染与点击跳转', (tester) async {
    engine.addProject(
        projectType: 'novel',
        name: '剑出寒山',
        intro: '少年得剑',
        artStyle: '国风水墨');
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('剑出寒山'), findsOneWidget);
    expect(find.text('基于小说原文'), findsOneWidget);
    expect(find.text('国风水墨'), findsOneWidget);

    await tester.tap(find.text('剑出寒山'));
    await tester.pumpAndSettle();
    expect(find.text('novel-page'), findsOneWidget);
  });

  testWidgets('新建对话框：名称必填校验', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建项目').first);
    await tester.pumpAndSettle();
    expect(find.text('项目类型'), findsOneWidget);
    expect(find.text('视觉手册'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SnackBar, '请输入项目名称'), findsOneWidget);
  });
}
