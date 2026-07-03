import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

class DFEmpty extends StatelessWidget {
  final String text;
  final Widget? action;

  const DFEmpty({super.key, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final colors = context.df;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DFTokens.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                shape: BoxShape.circle,
                border: Border.all(color: colors.stroke),
              ),
              child: Icon(
                Icons.inbox_outlined,
                color: colors.textTertiary,
                size: 28,
              ),
            ),
            const SizedBox(height: DFTokens.s12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: DFTokens.body14.copyWith(color: colors.textSecondary),
            ),
            if (action != null) ...[
              const SizedBox(height: DFTokens.s16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
