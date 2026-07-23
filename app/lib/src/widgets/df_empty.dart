// 苹果风格大气 Hero 空白页占位组件
import 'package:flutter/material.dart';

import '../theme/theme.dart';

class DFEmpty extends StatelessWidget {
  final String text;
  final String? description;
  final Widget? action;

  const DFEmpty({
    super.key,
    required this.text,
    this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.df;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 大气发光光圈 Icon
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    colors.primary.withValues(alpha: 0.14),
                    colors.primary.withValues(alpha: 0.03),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.2),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.1),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                Icons.auto_awesome_outlined,
                color: colors.primary,
                size: 42,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 28),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
