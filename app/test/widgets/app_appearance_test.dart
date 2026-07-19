import 'dart:io';

import 'package:dramaflow/src/app.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/project/project_list_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Engine engine;
  late ProviderContainer container;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-app-appearance-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
    );
    container = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(engine)],
    );
  });

  tearDown(() {
    container.dispose();
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('DramaFlowApp 将保存的主题色和字号应用到子页面', (tester) async {
    await engine.setThemePrimaryColor('#E34D59');
    await engine.setThemeFontSize(22);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const DramaFlowApp(),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(ProjectListScreen));
    expect(Theme.of(context).colorScheme.primary, const Color(0xFFE34D59));
    expect(MediaQuery.textScalerOf(context).scale(16), closeTo(22, 0.001));

    await container
        .read(themeModeProvider.notifier)
        .setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    expect(Theme.of(context).brightness, Brightness.dark);
    expect(
        Theme.of(context).colorScheme.primary, isNot(const Color(0xFF414CB2)));
  });

  testWidgets('DramaFlowApp 首次启动默认跟随系统主题', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const DramaFlowApp(),
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
  });
}
