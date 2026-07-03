// 剧本管理页占位（T12 全量实现：卡片流/新增/编辑/批量添加/提取资产/导出）。
import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_empty.dart';

class ScriptScreen extends StatelessWidget {
  final int projectId;
  const ScriptScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.df.surface,
      alignment: Alignment.center,
      child: DFEmpty(text: context.l10n.menuScriptManage),
    );
  }
}
