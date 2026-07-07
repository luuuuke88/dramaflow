import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:dramaflow/src/widgets/policy_confirm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Engine engine;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-policyconfirm-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  // 桌面宽度，让 showDFAdaptiveDialog 走对话框而非全屏页，便于就地断言。
  Widget app(Future<void> Function(BuildContext context) action) {
    return MediaQuery(
      data: const MediaQueryData(size: Size(1200, 900)),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
        locale: const Locale('zh'),
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => action(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('confirmPolicyAction 花钱维度', () {
    testWidgets('开关开：弹窗出现，取消返回 false', (tester) async {
      engine.config.update({'policy.confirmMoney': '1'});
      bool? result;
      await tester.pumpWidget(app((context) async {
        result = await confirmPolicyAction(
          context,
          engine.config,
          taskClass: 'video_generation',
          description: '批量生成 12 张分镜图',
          units: 12,
        );
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('花费确认'), findsOneWidget);
      expect(
        find.textContaining('批量生成 12 张分镜图：本次将调用 12 次付费生成，确认继续？'),
        findsOneWidget,
      );

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(result, false);
    });

    testWidgets('开关开：弹窗出现，确认返回 true', (tester) async {
      engine.config.update({'policy.confirmMoney': '1'});
      bool? result;
      await tester.pumpWidget(app((context) async {
        result = await confirmPolicyAction(
          context,
          engine.config,
          taskClass: 'video_generation',
          description: '批量生成 12 张分镜图',
          units: 12,
        );
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('花费确认'), findsOneWidget);

      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(result, true);
    });

    testWidgets('开关关：不弹窗直接返回 true', (tester) async {
      engine.config.update({'policy.confirmMoney': '0'});
      bool? result;
      await tester.pumpWidget(app((context) async {
        result = await confirmPolicyAction(
          context,
          engine.config,
          taskClass: 'video_generation',
          description: '批量生成 12 张分镜图',
          units: 12,
        );
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('花费确认'), findsNothing);
      expect(result, true);
    });
  });

  group('confirmPolicyAction 破坏维度', () {
    testWidgets('开关开：弹窗出现，取消返回 false', (tester) async {
      engine.config.update({'policy.confirmDestructive': '1'});
      bool? result;
      await tester.pumpWidget(app((context) async {
        result = await confirmPolicyAction(
          context,
          engine.config,
          destructiveKey: 'clear_all_data',
          description: '清空所有数据',
        );
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('危险操作确认'), findsOneWidget);
      expect(
        find.textContaining('清空所有数据：该操作不可撤销，确认继续？'),
        findsOneWidget,
      );

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(result, false);
    });

    testWidgets('开关开：弹窗出现，确认返回 true', (tester) async {
      engine.config.update({'policy.confirmDestructive': '1'});
      bool? result;
      await tester.pumpWidget(app((context) async {
        result = await confirmPolicyAction(
          context,
          engine.config,
          destructiveKey: 'clear_all_data',
          description: '清空所有数据',
        );
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('危险操作确认'), findsOneWidget);

      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(result, true);
    });

    testWidgets('开关关：不弹窗直接返回 true', (tester) async {
      engine.config.update({'policy.confirmDestructive': '0'});
      bool? result;
      await tester.pumpWidget(app((context) async {
        result = await confirmPolicyAction(
          context,
          engine.config,
          destructiveKey: 'clear_all_data',
          description: '清空所有数据',
        );
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('危险操作确认'), findsNothing);
      expect(result, true);
    });
  });

  testWidgets('既非花钱也非破坏动作：直接返回 true', (tester) async {
    bool? result;
    await tester.pumpWidget(app((context) async {
      result = await confirmPolicyAction(
        context,
        engine.config,
        description: '普通操作',
      );
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(result, true);
  });
}
