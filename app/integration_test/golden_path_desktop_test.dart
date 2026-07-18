// Real-process desktop golden-path navigation smoke test (macOS).
//
// The sibling golden_path_navigation_test.dart targets the <840dp mobile
// shell (bottom NavigationBar + top tab chips). This one pins a wide viewport
// so AppShell renders _DesktopShell (side icon rail + top project-menu bar)
// and drives THAT surface end to end. Same test-isolated engine (in-memory
// db, temp media dir, noop gateway): no real API calls, no user data touched.

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
    dir = await Directory.systemTemp.createTemp('dramaflow-desktop-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
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
      'desktop golden path: create project, navigate the side rail and top menu',
      (tester) async {
    // Pin a wide viewport so AppShell selects _DesktopShell (breakpoint 840dp).
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final provider = await engine.createProvider(
      name: 'Demo Provider',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );
    await engine.saveProviderModels(provider.id, [
      {'modelId': 'img-demo', 'label': '图像模型', 'kind': 'image', 'enabled': true},
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

    await tester.pumpWidget(app());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 1. Launch: empty project list inside the desktop shell.
    expect(find.text('暂无项目'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);

    // 2. Create a project via the real wizard.
    await tester.tap(find.text('新建项目').first);
    await tester.pumpAndSettle();
    expect(find.text('项目类型'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '桌面走查短剧');
    await tester.enterText(find.byType(TextField).at(1), '玄幻');
    await tester.enterText(find.byType(TextField).at(2), '少年出山历劫');
    await _selectDropdown(tester, '请选择图片模型', 'Demo Provider · 图像模型');
    await _selectDropdown(tester, '请选择视频模型', 'Demo Provider · 视频模型');
    await _selectDropdown(tester, '请选择模式', 'fast');
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(engine.projects().length, 1,
        reason: 'project creation must persist through the real desktop UI');
    expect(find.byType(ErrorWidget), findsNothing);

    // 3. Open the project -> the top project-menu bar appears.
    await tester.tap(find.text('桌面走查短剧').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(ErrorWidget), findsNothing);

    // 4. Visit every project tab via the desktop top-menu bar. The project
    //    opens ON the novel screen, whose inner TabBar carries the same
    //    '小说原文' label as the top menu — so first navigate to a non-novel
    //    tab (资产中心), unmounting that inner TabBar. From there every top-menu
    //    label is unambiguous at tap time (each tap unmounts the prior screen
    //    before the next lookup), and the loop genuinely exercises navigation.
    await tester.tap(find.text('资产中心'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.byType(ErrorWidget), findsNothing);

    const tabs = ['小说原文', '剧本管理', '塑角造景', '视频生产', '资产中心', '剧本Agent'];
    for (final tab in tabs) {
      final finder = find.text(tab);
      expect(finder, findsOneWidget,
          reason: 'desktop top-menu must show exactly one "$tab" entry at tap time');
      await tester.tap(finder);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      expect(find.byType(ErrorWidget), findsNothing,
          reason: 'tab "$tab" must render without throwing');
    }

    // 5. Side rail: task center + settings are icon buttons (Tooltip labels),
    //    driven by their icon, then back to the project list via the folder.
    await tester.tap(find.byIcon(Icons.view_list_outlined));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(ErrorWidget), findsNothing);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(ErrorWidget), findsNothing);

    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // Back at the project list. The project name shows both on the list card
    // and (until a project is re-selected) in the desktop top-bar title, so
    // assert presence + health rather than an exact count.
    expect(find.text('桌面走查短剧'), findsAtLeastNWidgets(1),
        reason: 'full desktop navigation round-trip returns to a healthy list');
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
