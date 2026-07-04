// Manual visual evidence capture for the production canvas parity checklist.
//
// Run from app/:
//   flutter test --update-goldens tool/capture_production_visual_evidence_test.dart
//
// The file lives under tool/ so the default `flutter test` suite does not
// rewrite committed PNG evidence on every run.
import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/compose.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/script_plan.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/storyboard_table.dart';
import 'package:dramaflow/src/screens/production/production_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import 'e2e_local_smoke.dart' as smoke;

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CaptureComposer implements VideoComposer {
  @override
  Future<void> concat(
      List<String> segmentAbsPaths, String outputAbsPath) async {
    File(outputAbsPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1]);
  }

  @override
  Future<void> compose(
      List<ComposeSegment> segments, String outputAbsPath) async {
    File(outputAbsPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(
          [for (final segment in segments) segment.hasAudio ? 2 : 1]);
  }

  @override
  Future<double?> probeDurationSec(String inputAbsPath) async => 9.0;
}

void main() {
  testWidgets('capture production canvas desktop evidence', (tester) async {
    final outputDir = _outputDir();
    stderr.writeln('[capture] desktop start');
    await _capture(
      tester,
      width: 1400,
      height: 900,
      isMobile: false,
      output: File(p.join(outputDir.path, 'desktop-canvas.png')),
    );
    stderr.writeln('[capture] desktop done');
  });

  testWidgets('capture production canvas mobile evidence', (tester) async {
    final outputDir = _outputDir();
    stderr.writeln('[capture] mobile start');
    await _capture(
      tester,
      width: 390,
      height: 900,
      isMobile: true,
      output: File(p.join(outputDir.path, 'mobile-tabs.png')),
    );
    stderr.writeln('[capture] mobile done');
  });
}

Directory _outputDir() {
  final outputDir = Directory(p.normalize(p.join(
    Directory.current.path,
    '../docs/superpowers/progress/visual-evidence/production-canvas',
  )));
  outputDir.createSync(recursive: true);
  return outputDir;
}

Future<void> _capture(
  WidgetTester tester, {
  required double width,
  required double height,
  required bool isMobile,
  required File output,
}) async {
  final dir = Directory.systemTemp.createTempSync('df-production-capture-');
  final db = openEngineDb(':memory:');
  final engine = Engine(
    db: db,
    media: MediaStore(p.join(dir.path, 'media')),
    gateway: _NoopGateway(),
    config: EngineConfig(db, isMobile: isMobile),
    composer: _CaptureComposer(),
  );
  engine.installStoryboardPipeline();

  stderr.writeln('[capture] seed width=$width');
  final seed = smoke.seedOfflinePipeline(engine);
  engine.saveScriptPlan(
    seed.projectId,
    '## 节奏规划\n雪夜来客 -> 亮出玉佩 -> 守门弟子退入山门。',
  );
  engine.saveStoryboardTable(
    seed.projectId,
    seed.scriptId,
    '| 镜号 | 画面 | 运镜 |\n|---|---|---|\n| S01 | 黑衣人踏雪 | 低机位推进 |\n| S02 | 玉佩落雪 | 特写拉回 |',
  );

  final screenshotKey = GlobalKey();
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(
      path: '/',
      builder: (context, state) =>
          Scaffold(body: ProductionScreen(projectId: seed.projectId)),
    ),
  ]);

  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;

  stderr.writeln('[capture] pump widget width=$width');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: RepaintBoundary(
        key: screenshotKey,
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, height)),
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [
              Locale('zh'),
              Locale('en'),
              Locale('ja'),
            ],
            locale: const Locale('zh'),
            theme: buildTheme(Brightness.light),
            routerConfig: router,
          ),
        ),
      ),
    ),
  );
  await _pumpCaptureFrames(tester);
  stderr.writeln('[capture] pumped width=$width');

  if (isMobile) {
    stderr.writeln('[capture] mobile select workbench');
    await tester.drag(find.byType(TabBar), const Offset(-280, 0));
    await _pumpCaptureFrames(tester);
    await tester.tap(find.widgetWithText(Tab, '工作台'));
    await _pumpCaptureFrames(tester);
  }

  stderr.writeln('[capture] golden width=$width');
  await expectLater(
    find.byKey(screenshotKey),
    matchesGoldenFile(output.path),
  );
  engine.dispose();
  db.close();
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  stderr.writeln('[capture] wrote ${output.path}');
}

Future<void> _pumpCaptureFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}
