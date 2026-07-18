// 聚焦测试：导入原文对话框第二步（章节选择）在移动端卡片上必须展示章节内容预览，
// 否则用户是「盲选」章节（参见 import_novel_dialog.dart 的 mobileCardBuilder 注释）。
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/novel/import_novel_dialog.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _NoopGateway implements ProviderGateway {
  @override
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken}) async {
    return TextResult('');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-import-dialog-ui-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '导入对话框测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app() => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MediaQuery(
          data: const MediaQueryData(size: Size(390, 900)),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
            locale: const Locale('zh'),
            theme: buildTheme(Brightness.light),
            home: Consumer(builder: (context, ref, _) {
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () =>
                        showImportNovelDialog(context, ref, projectId: projectId),
                    child: const Text('打开导入'),
                  ),
                ),
              );
            }),
          ),
        ),
      );

  testWidgets('移动端第二步章节卡片展示章节内容预览，而非仅索引与卷名', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).last,
      '第1章 雪夜\n黑衣人踏雪而来，掌门取出焦黑玉佩以示警告。\n'
      '第2章 入山\n少年穿过石阶，云海深处忽然亮起一道剑光。',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    // 第二步的移动端卡片应能看到章节正文片段，而不只是索引/卷名/章节名。
    expect(find.textContaining('黑衣人踏雪而来'), findsOneWidget);
    expect(find.textContaining('云海深处忽然亮起'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
