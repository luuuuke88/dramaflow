import 'dart:io';

import 'package:dramaflow/src/app.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/screens/first_run_guide.dart';
import 'package:dramaflow/src/screens/project/project_list_screen.dart';
import 'package:dramaflow/src/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('首次启动从引导进入供应商设置，跳过后持久化并打开项目页', (tester) async {
    final dir = Directory.systemTemp.createTempSync('df-onboarding-router-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = openEngineDb(':memory:');
    final engine = Engine(
      db: db,
      media: MediaStore('${dir.path}/media'),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
      credentials: InMemoryCredentialStore(),
    );
    addTearDown(engine.dispose);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: const DramaFlowApp(initialOnboardingComplete: false),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(FirstRunGuide), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-open-providers')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byKey(const Key('settings-section-providers')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-return')));
    await tester.pumpAndSettle();
    expect(find.byType(FirstRunGuide), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-open-bindings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byKey(const Key('settings-section-bindings')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-return')));
    await tester.pumpAndSettle();
    expect(find.byType(FirstRunGuide), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(engine.onboardingCompleted, isTrue);
    expect(find.byType(ProjectListScreen), findsOneWidget);
  });
}
