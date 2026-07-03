// 未交付分区占位页（P2/P3/P4/P5 徽标）。对应批次交付时整页替换。
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../util/l10n_ext.dart';
import '../widgets/df_empty.dart';

class ComingSoonScreen extends StatelessWidget {
  final String batch;
  const ComingSoonScreen({super.key, required this.batch});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.df.surface,
      alignment: Alignment.center,
      child: DFEmpty(text: context.l10n.shellComingSoon(batch)),
    );
  }
}
