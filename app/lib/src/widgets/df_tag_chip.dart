import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

enum DFTagTone { neutral, primary, accent, success, danger, warning }

class DFTagChip extends StatelessWidget {
  final String label;
  final VoidCallback? onClose;
  final DFTagTone? tone;

  const DFTagChip({super.key, required this.label, this.onClose, this.tone});

  @override
  Widget build(BuildContext context) {
    final colors = context.df;
    final foreground = _foreground(colors);
    final background = _background(colors);
    return AnimatedContainer(
      duration: DFTokens.fast120,
      curve: DFTokens.curve,
      padding: EdgeInsets.only(
        left: DFTokens.s8,
        right: onClose == null ? DFTokens.s8 : DFTokens.s4,
        top: DFTokens.s4,
        bottom: DFTokens.s4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(DFTokens.radiusChip),
        border: Border.all(color: foreground.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: DFTokens.caption12.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onClose != null) ...[
            const SizedBox(width: DFTokens.s4),
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(DFTokens.radiusChip),
              child: Icon(Icons.close_rounded, size: 14, color: foreground),
            ),
          ],
        ],
      ),
    );
  }

  Color _foreground(DFColors colors) {
    return switch (tone ?? DFTagTone.neutral) {
      DFTagTone.neutral => colors.textSecondary,
      DFTagTone.primary => colors.primary,
      DFTagTone.accent => colors.accent,
      DFTagTone.success => colors.success,
      DFTagTone.danger => colors.danger,
      DFTagTone.warning => colors.warning,
    };
  }

  Color _background(DFColors colors) {
    return switch (tone ?? DFTagTone.neutral) {
      DFTagTone.neutral => colors.surfaceMuted,
      DFTagTone.primary => colors.primarySubtle,
      DFTagTone.accent => colors.accent.withValues(alpha: 0.12),
      DFTagTone.success => colors.success.withValues(alpha: 0.12),
      DFTagTone.danger => colors.danger.withValues(alpha: 0.12),
      DFTagTone.warning => colors.warning.withValues(alpha: 0.12),
    };
  }
}
