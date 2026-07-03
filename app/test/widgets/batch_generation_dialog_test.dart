import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/assets/batch_generation_dialog.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _Gateway implements ProviderGateway {
  @override
  Future<TextResult> generateText(String system, String user,
          {required String stage, CancelToken? cancelToken}) async =>
      const TextResult('x');

  @override
  Future<String> generateImage(String prompt, String projectId,
          {required String stage,
          CancelToken? cancelToken,
          List<String> referenceAbsPaths = const [],
          String? editInstruction,
          String? ratio,
          String? quality,
          String? modelOverride}) async =>
      'p/img.png';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-batchdlg-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(
        projectType: 'novel', name: '批量测试', artStyle: '国风');
    // 两个带提示词的角色资产（生图要求 prompt 非空）
    engine.addAsset(
        projectId: projectId,
        type: 'role',
        name: '林逸',
        describe: 'x',
        prompt: 'hero');
    engine.addAsset(
        projectId: projectId,
        type: 'role',
        name: '白容',
        describe: 'y',
        prompt: 'heroine');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app() => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          locale: const Locale('zh'),
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Consumer(builder: (context, ref, _) {
              return Center(
                child: ElevatedButton(
                  onPressed: () => showBatchGenerationDialog(context, ref,
                      projectId: projectId, type: 'role', mode: 2),
                  child: const Text('open'),
                ),
              );
            }),
          ),
        ),
      );

  testWidgets('图片模式：渲染模型/分辨率/并发控件，并把参数带入任务', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 控件存在：模型/分辨率/并发/补充提示词只在 prompt 模式出现
    expect(find.text('模型'), findsOneWidget);
    expect(find.text('分辨率'), findsOneWidget);
    expect(find.text('并发数'), findsOneWidget);
    expect(find.text('2K'), findsOneWidget);

    // 选 2K 分辨率
    await tester.tap(find.text('2K'));
    await tester.pumpAndSettle();

    // 并发数改为 3
    await tester.enterText(find.widgetWithText(TextField, '1-8'), '3');
    await tester.pump();

    // 全选并生成图片
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '生成图片'));
    await tester.pumpAndSettle();

    // 断言：入队了 asset_image_generation 任务，relatedObjects 带 resolution/concurrentCount
    final row = db
        .select(
            "SELECT relatedObjects FROM o_tasks WHERE taskClass='asset_image_generation' ORDER BY id DESC LIMIT 1")
        .single;
    final related =
        jsonDecode(row['relatedObjects'] as String) as Map<String, dynamic>;
    expect(related['resolution'], '2K');
    expect(related['concurrentCount'], 3);
    expect((related['items'] as List).length, 2);
  });
}
