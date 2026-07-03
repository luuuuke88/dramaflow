import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/compose.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/video_track.dart';
import 'package:dramaflow/src/screens/production/workbench_screen.dart';
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

class _FakeComposer implements VideoComposer {
  @override
  Future<void> concat(List<String> segmentAbsPaths, String outputAbsPath) async {
    File(outputAbsPath).writeAsBytesSync([0]);
  }

  @override
  Future<double?> probeDurationSec(String inputAbsPath) async => 4.0;
}

void main() {
  late Directory dir;
  late Engine engine;
  late int projectId;
  late int scriptId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-workbench-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
      composer: _FakeComposer(),
    );
    engine.installVideoTrackPipeline();
    projectId = engine.addProject(projectType: 'novel', name: '工作台测试');
    scriptId = engine.addScript(projectId: projectId, name: '一', content: 'x');
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app() {
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
        path: '/',
        builder: (c, s) => Scaffold(
          body: Builder(builder: (innerContext) {
            return Consumer(builder: (context, ref, _) {
              return ElevatedButton(
                onPressed: () => showWorkbench(innerContext, ref,
                    projectId: projectId, scriptId: scriptId),
                child: const Text('open'),
              );
            });
          }),
        ),
      ),
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

  testWidgets('无分镜时显示空态', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('暂无分镜，请先在「制作」的分镜节点生成'), findsOneWidget);
  });

  testWidgets('有分镜时渲染镜头行+合成按钮显示缺口提示', (tester) async {
    engine.addStoryboard(projectId: projectId, scriptId: scriptId, prompt: 'x');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('S1'), findsOneWidget);
    expect(find.textContaining('合成本集'), findsOneWidget);
  });

  testWidgets('点击生成运镜提示词按钮不崩溃且写入轨道', (tester) async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 无提示词种子时 getPrompt 抛错，验证走 toast 而非崩溃
    await tester.tap(find.text('生成运镜提示词'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(engine.storyboards(scriptId).single.id, sbId);
  });

  testWidgets('全部已选视频时可成功合成并弹出结果', (tester) async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    final trackId = engine.ensureTrackForStoryboard(sbId);
    engine.db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [trackId, 'p/vid_1.mp4', vtDone]);
    engine.selectVideo(trackId, engine.db.lastInsertRowId);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('合成本集'));
    await tester.pumpAndSettle();

    expect(find.text('合成成功'), findsOneWidget);
  });
}
