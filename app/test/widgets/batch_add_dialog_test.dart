import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/screens/script/batch_add_dialog.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-batchadd-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '批量剧本测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  // 一短一长两集：批量剧本导入默认按「第 N 集」拆分（对齐 ToonFlow，剧本按集、
  // 小说按章）。
  const content = '第1集 短集\n短\n第2集 长集\n长文内容超长';

  Widget app() => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          locale: const Locale('zh'),
          theme: buildTheme(Brightness.light),
          home: Consumer(builder: (c, ref, _) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      showBatchAddDialog(c, ref, projectId: projectId),
                  child: const Text('open'),
                ),
              ),
            );
          }),
        ),
      );

  // 移动宽度进入第二步。第二步默认不勾选任何分集（对齐 ToonFlow，见
  // script_screen_test「ToonFlow 第二步默认不勾选任何分集」），由各用例按需
  // 点标题勾选。
  Future<void> openStep2(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 粘贴内容 → 自动拆集。
    await tester.enterText(find.byType(TextField).last, content);
    await tester.pumpAndSettle();

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
  }

  testWidgets('存在超限分集时保存按钮禁用并显示告警', (tester) async {
    engine.config.update({'scriptEpisodeLength': '5'});
    await openStep2(tester);

    // 勾选超限的「长集」（正文「长文内容超长」6 字 > 5）后，保存应被禁用。
    await tester.tap(find.text('长集'));
    await tester.pumpAndSettle();

    final save = find.widgetWithText(FilledButton, '保存');
    expect(save, findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull,
        reason: '存在超限分集时保存禁用');
    expect(find.textContaining('超出单集字数上限'), findsWidgets);

    // 未落库任何剧本。
    expect(engine.scripts(projectId).length, 0);
  });

  testWidgets('限额足够大时保存可用并写入剧本', (tester) async {
    engine.config.update({'scriptEpisodeLength': '5000'});
    await openStep2(tester);

    // 勾选两集后保存。
    await tester.tap(find.text('短集'));
    await tester.tap(find.text('长集'));
    await tester.pumpAndSettle();

    final save = find.widgetWithText(FilledButton, '保存');
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(find.textContaining('超出单集字数上限'), findsNothing);

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(engine.scripts(projectId).length, 2);
  });

  testWidgets('移动端卡片标题超长时单行省略（对齐桌面单元格）', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const longTitle = '这是一个用于回归测试的超长章节标题文本';
    await tester.pumpWidget(app());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField).last, '第1集 $longTitle\n正文内容');
    await tester.pumpAndSettle();

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text(longTitle));
    expect(title.maxLines, 1, reason: '移动卡片标题应与桌面单元格一样单行截断');
    expect(title.overflow, TextOverflow.ellipsis,
        reason: '移动卡片标题应与桌面单元格一样单行截断');
  });
}
