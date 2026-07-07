import 'package:flutter/material.dart';

import '../engine/config.dart';
import '../engine/pipeline_policy.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/l10n_ext.dart';
import 'df_adaptive_dialog.dart';

/// 依据 [checkAction] 的判定结果决定是否需要弹窗确认。
///
/// 返回 true=放行（verdict==allow 或用户已在弹窗中确认），false=用户取消。
Future<bool> confirmPolicyAction(
  BuildContext context,
  EngineConfig config, {
  String? taskClass,
  String? destructiveKey,
  bool autoMode = false,
  required String description,
  int units = 1,
}) async {
  final verdict = checkAction(
    config,
    taskClass: taskClass,
    destructiveKey: destructiveKey,
    autoMode: autoMode,
  );
  if (verdict == PolicyVerdict.allow) return true;

  final l10n = context.l10n;
  final isDestructive = verdict == PolicyVerdict.confirmDestructive;
  final confirmed = await showDFAdaptiveDialog<bool>(
    context,
    title: isDestructive
        ? l10n.policyConfirmDestructiveTitle
        : l10n.policyConfirmMoneyTitle,
    desktopWidthFactor: .36,
    builder: (c) => _PolicyConfirmBody(
      message: isDestructive
          ? l10n.policyConfirmDestructiveBody(description)
          : l10n.policyConfirmMoneyBody(description, units),
      destructive: isDestructive,
    ),
  );
  return confirmed == true;
}

class _PolicyConfirmBody extends StatelessWidget {
  final String message;
  final bool destructive;
  const _PolicyConfirmBody({required this.message, required this.destructive});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(DFTokens.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.commonCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: context.df.danger)
                    : null,
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.commonConfirm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
