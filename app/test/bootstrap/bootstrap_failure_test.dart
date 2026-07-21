import 'dart:io';

import 'package:dramaflow/src/bootstrap/bootstrap_io.dart';
import 'package:dramaflow/src/bootstrap/startup_failure_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

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

  testWidgets('数据库迁移失败等非文件系统错误走通用文案，展开详细信息后展示真实错误文本（不只是 debugPrint 里才有）',
      (tester) async {
    // 复现 db_test.dart 里"迁移失败"场景真实抛出的异常类型：SqliteException，
    // 不是 FileSystemException——如果恢复页继续显示"检查磁盘空间和目录权限"，
    // 会把用户导向错误的排查方向（重试永远无法解决数据库损坏/版本不兼容）。
    final cause = SqliteException(
      extendedResultCode: 11,
      message: 'database disk image is malformed',
      operation: 'preparing a statement',
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1024, 900)),
        child: StartupFailureApp(
          failure: StartupFailure(
            cause: cause,
            dataDirectory: '/tmp/dramaflow',
          ),
          onRetry: _neverRetry,
        ),
      ),
    );
    // AppLocalizations 的委托是异步加载的，pumpWidget 的首帧还看不到本地化
    // 文本，需要再推进一帧才能稳定读到 l10n 字符串。StartupFailureApp 没有
    // 固定 locale，测试环境下解析到的是 en（而不是仓库其它测试常见的
    // 显式 Locale('zh')），所以这里断言英文文案。
    await tester.pump();

    expect(find.text('Unexpected error during startup'), findsOneWidget);
    expect(find.text("Can't open the local workspace"), findsNothing,
        reason: '不应该继续显示权限/磁盘空间专属标题');

    // 详细信息默认收起：真实错误文本还不应该出现在界面上。
    expect(
        find.textContaining('database disk image is malformed'), findsNothing);

    await tester.tap(find.text('Show details'));
    await tester.pump();

    expect(find.textContaining('database disk image is malformed'),
        findsOneWidget);
  });

  testWidgets('权限/磁盘 IO 类失败仍然展示原有的磁盘空间与权限文案', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(1024, 900)),
        child: StartupFailureApp(
          failure: StartupFailure(
            cause: FileSystemException('permission denied'),
            dataDirectory: '/tmp/dramaflow',
          ),
          onRetry: _neverRetry,
        ),
      ),
    );
    await tester.pump();

    expect(find.text("Can't open the local workspace"), findsOneWidget);
    expect(find.text('Unexpected error during startup'), findsNothing);
  });

  testWidgets('非 macOS 平台也能拿到可用的退出回调，不会卡在恢复页出不去', (tester) async {
    // bootstrap() 里真正的退出动作是 dart:io 的 exit(1)——在单测进程里直接调用
    // 会把测试 runner 本身杀掉，所以这里必须通过 exitOverride 注入替身来验证
    // 退出回调确实被无条件传给了 StartupFailureApp（而不是像修复前那样只在
    // Platform.isMacOS 时才有 onExit）。
    TestWidgetsFlutterBinding.ensureInitialized();
    final roots = <Widget>[];
    var exited = false;

    await bootstrap(
      appBuilder: () async => throw StateError('boom'),
      runAppOverride: roots.add,
      exitOverride: () => exited = true,
    );

    final app = roots.single as StartupFailureApp;
    expect(app.onExit, isNotNull);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1024, 900)),
        child: app,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Quit app'));
    await tester.pump();

    expect(exited, isTrue);
  });
}

Future<void> _neverRetry() async {}
