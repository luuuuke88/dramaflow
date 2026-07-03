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

  // 一短一长两集：默认章节正则拆分为「第1章/第2章」。
  const content = '第1章 短集\n短\n第2章 长集\n长文内容超长';

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

  Future<void> openStep2(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 粘贴内容 → 自动拆集。
    await tester.enterText(find.byType(TextField).last, content);
    await tester.pumpAndSettle();

    // 下一步（默认全选所有分集）。
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
  }

  testWidgets('存在超限分集时保存按钮禁用并显示告警', (tester) async {
    engine.config.update({'scriptEpisodeLength': '5'});
    await openStep2(tester);

    // 「长集」内容长度 > 5，全选状态下保存应被禁用。
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

    final save = find.widgetWithText(FilledButton, '保存');
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(find.textContaining('超出单集字数上限'), findsNothing);

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(engine.scripts(projectId).length, 2);
  });
}
