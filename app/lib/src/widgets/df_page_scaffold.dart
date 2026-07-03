import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

class DFPageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? toolbar;
  final Widget body;

  const DFPageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.toolbar,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.df.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DFTokens.s32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: DFTokens.display24w700
                              .copyWith(color: context.df.textPrimary),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: DFTokens.s4),
                          Text(
                            subtitle!,
                            style: DFTokens.body14
                                .copyWith(color: context.df.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (toolbar != null) ...[
                    const SizedBox(width: DFTokens.s24),
                    toolbar!,
                  ],
                ],
              ),
              const SizedBox(height: DFTokens.s24),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}
