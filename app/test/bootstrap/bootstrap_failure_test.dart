import 'dart:io';

import 'package:dramaflow/src/bootstrap/bootstrap_io.dart';
import 'package:dramaflow/src/bootstrap/startup_failure_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('启动存储失败时挂载可重试的失败页而非向框架抛出异常', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final roots = <Widget>[];

    await expectLater(
      bootstrap(
        appBuilder: () async =>
            throw FileSystemException('permission denied', '/tmp/dramaflow'),
        runAppOverride: roots.add,
      ),
      completes,
    );

    expect(roots, hasLength(1));
    expect(roots.single.runtimeType.toString(), 'StartupFailureApp');
  });

  testWidgets('390dp 失败页展示目录并允许重试', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: StartupFailureApp(
          failure: const StartupFailure(
            cause: FileSystemException('permission denied'),
            dataDirectory: '/tmp/dramaflow',
          ),
          onRetry: () async => attempts++,
        ),
      ),
    );

    expect(find.text('/tmp/dramaflow'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(attempts, 1);
    expect(tester.takeException(), isNull);
  });
}
