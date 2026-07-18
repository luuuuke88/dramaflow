// Real-device/simulator golden-path navigation smoke test.
//
// Unlike the widget tests under test/widgets/, this boots the actual
// DramaFlowApp() root widget (real _router, real MaterialApp.router) on a
// real iOS Simulator / macOS process via `flutter test integration_test`,
// exercising the real rendering pipeline rather than the flutter_test
// in-memory harness. The engine is still test-isolated (in-memory DB, temp
// media dir, noop gateway -- no real API calls, no user data touched).

import 'dart:io';

import 'package:dramaflow/src/app.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _selectDropdown(
    WidgetTester tester, String closedLabel, String optionLabel) async {
  await tester.ensureVisible(find.text(closedLabel).first);
  final field = find.ancestor(
    of: find.text(closedLabel).first,
    matching: find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<String>,
    ),
  );
  await tester.tap(field.first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionLabel).last);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Engine engine;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dramaflow-golden-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
    );
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app() {
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: const DramaFlowApp(),
    );
  }

  testWidgets(
      'golden path: launch, create project, visit every main screen',
      (tester) async {
    // Seed enough config that the real project wizard can complete without
    // hitting a real provider.
    final provider = await engine.createProvider(
      name: 'Demo Provider',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );
    await engine.saveProviderModels(provider.id, [
      {
        'modelId': 'img-demo',
        'label': '图像模型',
        'kind': 'image',
        'enabled': true,
      },
      {
        'modelId': 'video-demo',
        'label': '视频模型',
        'kind': 'video',
        'enabled': true,
        'capabilities': {
          'modes': ['fast'],
        },
      },
    ]);

    // Pin a phone-portrait viewport so AppShell deterministically selects the
    // mobile shell (breakpoint 840dp): the desktop shell has no BackButton and
    // its nav labels exist only as Tooltip messages, so this test's finders
    // would match nothing on an iPad / landscape / wide desktop window.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 1. Launch state: empty project list.
    expect(find.text('暂无项目'), findsOneWidget,
        reason: 'app should boot straight to the empty project-list state');
    expect(find.byType(ErrorWidget), findsNothing);

    // 2. Create a project via the real wizard.
    await tester.tap(find.text('新建项目').first);
    await tester.pumpAndSettle();
    expect(find.text('项目类型'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '真机走查短剧');
    await tester.enterText(find.byType(TextField).at(1), '玄幻');
    await tester.enterText(find.byType(TextField).at(2), '少年出山历劫');
    await _selectDropdown(tester, '请选择图片模型', 'Demo Provider · 图像模型');
    await _selectDropdown(tester, '请选择视频模型', 'Demo Provider · 视频模型');
    await _selectDropdown(tester, '请选择模式', 'fast');

    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(engine.projects().length, 1,
        reason: 'project creation must actually persist through the real UI');
    expect(find.byType(ErrorWidget), findsNothing);

    // 3. Open the project -> lands on the workbench.
    await tester.tap(find.text('真机走查短剧').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(ErrorWidget), findsNothing);

    // 4. Visit every project tab and confirm it renders cleanly.
    //
    // Scope the finder to the AppBar's tab strip: the novel screen mounts an
    // inner TabBar whose first tab carries the SAME l10n string as the outer
    // nav chip ('小说原文'), and Scaffold's element tree visits body before
    // appBar — an unscoped find.text().first would tap the inner (already
    // selected) tab as a silent no-op instead of exercising navigation.
    const tabs = ['小说原文', '剧本管理', '塑角造景', '视频生产', '资产中心', '剧本Agent'];
    for (final tab in tabs) {
      final finder = find
          .descendant(of: find.byType(AppBar), matching: find.text(tab))
          .first;
      final tabStrip = find
          .descendant(
              of: find.byType(AppBar), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(finder, 320, scrollable: tabStrip);
      await tester.pump();
      expect(tester.getCenter(finder).dx, greaterThan(0),
          reason: 'tab "$tab" must be fully on-screen, not clipped at the edge, before tapping');
      await tester.tap(finder);
      await tester.pumpAndSettle(const Duration(milliseconds: 800));
      expect(find.byType(ErrorWidget), findsNothing,
          reason: 'tab "$tab" must render without throwing');
    }

    // 5. Back out to the project list, then visit task center + settings.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('真机走查短剧'), findsOneWidget);

    await tester.tap(find.text('任务中心').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(ErrorWidget), findsNothing);

    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(ErrorWidget), findsNothing);

    await tester.tap(find.text('我的项目').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('真机走查短剧'), findsOneWidget,
        reason: 'full navigation round-trip must return to a healthy project list');
  });
}
