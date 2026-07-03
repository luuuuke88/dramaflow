import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/l10n_ext.dart';

enum DFStatusKind { processing, success, failed, pending }

class DFStatusTag extends StatelessWidget {
  final DFStatusKind kind;
  final String? text;
  final VoidCallback? onTapError;

  const DFStatusTag({
    super.key,
    required this.kind,
    this.text,
    this.onTapError,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.df;
    final foreground = switch (kind) {
      DFStatusKind.processing => colors.running,
      DFStatusKind.success => colors.success,
      DFStatusKind.failed => colors.danger,
      DFStatusKind.pending => colors.textSecondary,
    };
    final background = switch (kind) {
      DFStatusKind.processing => colors.primarySubtle,
      DFStatusKind.success => colors.success.withValues(alpha: 0.12),
      DFStatusKind.failed => colors.danger.withValues(alpha: 0.12),
      DFStatusKind.pending => colors.surfaceMuted,
    };
    final label = text ??
        switch (kind) {
          DFStatusKind.processing => context.l10n.statusRunning,
          DFStatusKind.success => context.l10n.statusSuccessShort,
          DFStatusKind.failed => context.l10n.statusFailed,
          DFStatusKind.pending => context.l10n.statusPendingShort,
        };

    final tag = AnimatedContainer(
      duration: DFTokens.fast120,
      curve: DFTokens.curve,
      padding: const EdgeInsets.symmetric(
        horizontal: DFTokens.s8,
        vertical: DFTokens.s4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(DFTokens.radiusChip),
        border: Border.all(color: foreground.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kind == DFStatusKind.processing)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foreground,
              ),
            )
          else
            Icon(_iconFor(kind), size: 13, color: foreground),
          const SizedBox(width: DFTokens.s4),
          Text(
            label,
            style: DFTokens.caption12.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    if (kind == DFStatusKind.failed && onTapError != null) {
      return InkWell(
        onTap: onTapError,
        borderRadius: BorderRadius.circular(DFTokens.radiusChip),
        child: tag,
      );
    }
    return tag;
  }

  IconData _iconFor(DFStatusKind kind) {
    return switch (kind) {
      DFStatusKind.processing => Icons.autorenew_rounded,
      DFStatusKind.success => Icons.check_circle_rounded,
      DFStatusKind.failed => Icons.error_rounded,
      DFStatusKind.pending => Icons.schedule_rounded,
    };
  }
}
