// 章节管理页占位（T11 全量实现：工具栏/表格/两步导入/事件 tab/事件分析）。
import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_empty.dart';

class NovelScreen extends StatelessWidget {
  final int projectId;
  const NovelScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.df.surface,
      alignment: Alignment.center,
      child: DFEmpty(text: context.l10n.menuNovel),
    );
  }
}
