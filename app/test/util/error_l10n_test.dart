// engineErrorText（widgets/common.dart）和 localizeErrKey（util/error_l10n.dart）
// 各自维护一份 errKey → 文案的 switch，文件头注释都自称"唯一映射/唯一出口"。
// 任务 4：两边都曾经漏过 errDbTableClearForbidden/errProviderExists 等分支，
// 漏掉的 errKey 会落到各自的 default 分支，把裸 errKey 原样显示给用户。
// 这里用 errors.dart 定义的完整错误码集合驱动两个函数，锁住"不漏码"这个不变量。
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/util/error_l10n.dart';
import 'package:dramaflow/src/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _allErrKeys = <String>{
  errProviderMissing,
  errProviderExists,
  errModelMissing,
  errPromptMissing,
  errConfigVersion,
  errNetwork,
  errLlmFormat,
  errCanceled,
  errAppRestart,
  errFileTooLarge,
  errFileType,
  errRegexInvalid,
  errNoChapters,
  errPlatformComposer,
  errTaskUnsupported,
  errTaskActive,
  errManualInvalid,
  errManualExists,
  errDbTableClearForbidden,
};

void main() {
  test('localizeErrKey 覆盖 errors.dart 定义的每一个错误码，不裸露原始 errKey', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    for (final key in _allErrKeys) {
      final text = localizeErrKey(l10n, EngineException(key));
      expect(text, isNot(key),
          reason: '$key 缺少 localizeErrKey 映射，会把原始 errKey 显示给用户');
    }
  });

  testWidgets('engineErrorText 覆盖 errors.dart 定义的每一个错误码，且与 localizeErrKey 文案一致',
      (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
      locale: const Locale('zh'),
      home: Builder(builder: (context) {
        capturedContext = context;
        return const SizedBox();
      }),
    ));
    await tester.pump();
    final l10n = AppLocalizations.of(capturedContext);

    for (final key in _allErrKeys) {
      final viaCommon = engineErrorText(capturedContext, EngineException(key));
      expect(viaCommon, isNot(key),
          reason: '$key 缺少 engineErrorText 映射，会把原始 errKey 显示给用户');
      // 两份"唯一映射"对同一个错误码必须给出同一句文案，否则用户在不同页面
      // 看到的同一个错误会显示成两种不同的话术。
      expect(viaCommon, localizeErrKey(l10n, EngineException(key)),
          reason: '$key 在 engineErrorText 与 localizeErrKey 之间文案不一致');
    }
  });
}
