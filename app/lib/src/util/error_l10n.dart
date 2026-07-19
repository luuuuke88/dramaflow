// 引擎错误码 → 当前语言文案（唯一出口，新增 errKey 必须同步三语 ARB 与此映射）。
import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../engine/errors.dart';
import 'l10n_ext.dart';

String localizeErrKey(AppLocalizations l10n, EngineException e) =>
    switch (e.errKey) {
      errProviderMissing => l10n.errProviderMissing,
      errModelMissing => l10n.errModelMissing,
      errPromptMissing => l10n.errPromptMissing,
      errConfigVersion => l10n.errConfigVersion,
      errNetwork => l10n.errNetwork,
      errLlmFormat => l10n.errLlmFormat,
      errCanceled => l10n.errCanceled,
      errAppRestart => l10n.errAppRestart,
      errFileTooLarge => l10n.errFileTooLarge,
      errFileType => l10n.errFileType,
      errRegexInvalid => l10n.errRegexInvalid,
      errNoChapters => l10n.errNoChapters,
      errPlatformComposer => l10n.errPlatformComposer,
      errTaskUnsupported => l10n.errTaskUnsupported,
      errTaskActive => l10n.errTaskActive,
      errManualInvalid => l10n.errManualInvalid,
      _ => e.errKey,
    };

/// o_tasks.reason / 实体 errorReason（JSON）→ 文案；非错误 JSON 返回 null。
String? localizeReason(AppLocalizations l10n, String? reasonJson) {
  final reason = EngineException.fromReasonJson(reasonJson);
  if (reason == null) return null;
  return localizeErrKey(l10n, reason);
}

/// 捕获到的任意异常 → 文案（EngineException 走 ARB，其余原样）。
String localizeError(BuildContext context, Object e) =>
    e is EngineException ? localizeErrKey(context.l10n, e) : '$e';
