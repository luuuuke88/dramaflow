import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/manuals/manual_editor.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:path/path.dart' as p;

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAF/gL+6fD6nwAAAABJRU5ErkJggg==';

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageSelector extends FileSelectorPlatform {
  final List<XFile> files;
  int openFilesCalls = 0;

  _ImageSelector(this.files);

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    openFilesCalls++;
    return files;
  }
}

void main() {
  late Directory dir;
  late Engine engine;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-manual-editor-');
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

  Widget app() => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          locale: const Locale('zh'),
          theme: buildTheme(Brightness.light),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Column(children: [
                FilledButton(
                  onPressed: () =>
                      showManualEditor(context, ref, kind: 'director'),
                  child: const Text('打开导演手册'),
                ),
                FilledButton(
                  onPressed: () =>
                      showManualEditor(context, ref, kind: 'visual'),
                  child: const Text('打开视觉手册'),
                ),
                FilledButton(
                  onPressed: engine.visualManuals().isEmpty
                      ? null
                      : () => showManualEditor(
                            context,
                            ref,
                            kind: 'visual',
                            existing: engine.visualManuals().single,
                          ),
                  child: const Text('编辑视觉手册'),
                ),
              ]),
            ),
          ),
        ),
      );

  testWidgets('导演手册缺少封面时不能保存', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开导演手册'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '悬疑导演');
    await _fillActiveTab(tester, 'README 内容');
    await tester.tap(find.text('导演规划'));
    await tester.pumpAndSettle();
    await _fillActiveTab(tester, '规划内容');
    await tester.tap(find.text('分镜表'));
    await tester.pumpAndSettle();
    await _fillActiveTab(tester, '分镜表内容');

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget,
        reason: 'ToonFlow 对导演手册也要求至少一张封面，校验失败不能关闭表单');
    expect(engine.directorManuals(), isEmpty);
  });

  testWidgets('导演手册带封面与全部标签内容后保存到技能目录', (tester) async {
    final originalSelector = FileSelectorPlatform.instance;
    final selector = _ImageSelector([
      XFile.fromData(base64Decode(_pngBase64), path: 'cover.png'),
    ]);
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开导演手册'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '悬疑导演');
    await _fillDirectorTabs(tester);
    await tester.tap(find.text('上传封面'));
    await tester.pumpAndSettle();
    expect(selector.openFilesCalls, 1);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final pack = engine.directorManuals().single;
    expect(pack.name, '悬疑导演');
    expect(pack.images, hasLength(1));
    expect(pack.data, {
      'README': 'README 内容',
      'director_planning_narrative': '规划内容',
      'director_storyboard_table_narrative': '分镜表内容',
    });
  });

  testWidgets('移动端视觉手册以全屏编辑器呈现，封面、标签和保存操作可达', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开视觉手册'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing,
        reason: '390dp 不能挤压 12 标签的桌面手册对话框');
    expect(find.text('新建视觉手册'), findsOneWidget);
    expect(find.text('视觉手册封面'), findsOneWidget);
    expect(find.text('README'), findsOneWidget);
    expect(find.text('前缀'), findsOneWidget);
    expect(
        find.widgetWithText(FilledButton, '保存').hitTestable(), findsOneWidget,
        reason: '移动端滚动编辑器的保存操作必须始终可达');
    expect(tester.takeException(), isNull);
  });

  testWidgets('新建手册可填写稳定目录 ID，编辑时目录 ID 锁定', (tester) async {
    engine.saveVisualManual(
      name: '已有视觉',
      pack: 'existing_visual',
      data: {for (final key in visualManualKeys) key: key},
    );
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开视觉手册'));
    await tester.pumpAndSettle();
    final newPackField = tester.widget<TextField>(
      find.byKey(const Key('manual-pack-id-input')),
    );
    expect(newPackField.enabled, isTrue);
    await tester.enterText(
      find.byKey(const Key('manual-pack-id-input')),
      'new_visual',
    );
    expect(find.text('new_visual'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑视觉手册'));
    await tester.pumpAndSettle();
    final existingPackField = tester.widget<TextField>(
      find.byKey(const Key('manual-pack-id-input')),
    );
    expect(existingPackField.controller!.text, 'existing_visual');
    expect(existingPackField.enabled, isFalse);
  });
}

Future<void> _fillActiveTab(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextField).last, value);
}

Future<void> _fillDirectorTabs(WidgetTester tester) async {
  await _fillActiveTab(tester, 'README 内容');
  await tester.tap(find.text('导演规划'));
  await tester.pumpAndSettle();
  await _fillActiveTab(tester, '规划内容');
  await tester.tap(find.text('分镜表'));
  await tester.pumpAndSettle();
  await _fillActiveTab(tester, '分镜表内容');
}
