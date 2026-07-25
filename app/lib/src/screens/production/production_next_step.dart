// 视频生产画布的「下一步」条。
//
// 画布把五个环节一字排开，但没告诉用户此刻该动哪一个——尤其是新建的一集，
// 五张卡片全是空的，看上去哪张都能点。原有的四步教程只在第一次进入时讲一遍
// 界面构成，之后再没有任何提示。
//
// 这里按 ToonFlow 生产 Agent 的流水线模型（各阶段有明确前置条件，必须顺序推进）
// 反推出「当前卡在哪一步」，把它常驻显示在剧集选择栏下面，并提供一个按钮把画布
// 定位到那张卡片上——无限画布上，知道该做什么还不够，还得找得到它在哪。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/compose_episode.dart';
import '../../engine/script_plan.dart';
import '../../engine/storyboard.dart';
import '../../engine/storyboard_table.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/l10n_ext.dart';
import 'production_node_card.dart';

/// 当前该做的一步。[nodeId] 指向画布上对应的节点，供「带我去」定位。
class ProductionNextStep {
  final ProductionStage stage;
  final String nodeId;
  final String text;

  /// 全部做完时为 true：此时只报喜，不再催下一步。
  final bool finished;

  const ProductionNextStep({
    required this.stage,
    required this.nodeId,
    required this.text,
    this.finished = false,
  });
}

/// 按流水线顺序推断当前该做哪一步。顺序与卡片上的序号一致。
ProductionNextStep resolveProductionNextStep(
  WidgetRef ref,
  BuildContext context, {
  required int projectId,
  required int scriptId,
}) {
  final l10n = context.l10n;
  // 任务跑完要立刻反映到这条提示上，否则用户干完一步还在被催同一步。
  ref.watch(jobsGenerationProvider);
  final engine = ref.watch(engineProvider);

  if (engine.scriptPlan(projectId).trim().isEmpty) {
    return ProductionNextStep(
      stage: ProductionStage.scriptPlan,
      nodeId: 'scriptPlan',
      text: l10n.productionNextStepPlan,
    );
  }
  if (engine.storyboardTable(projectId, scriptId).trim().isEmpty) {
    return ProductionNextStep(
      stage: ProductionStage.storyboardTable,
      nodeId: 'storyboardTable',
      text: l10n.productionNextStepTable,
    );
  }
  final storyboards = engine.storyboards(scriptId);
  if (storyboards.isEmpty) {
    return ProductionNextStep(
      stage: ProductionStage.storyboard,
      nodeId: 'storyboard',
      text: l10n.productionNextStepStoryboard,
    );
  }
  // 分镜已拆好，但还有镜头没出画面：先补齐画面再谈合成。
  final paths = engine.orderedSelectedVideoPaths(scriptId);
  final missing = paths.where((p) => p == null || p.isEmpty).length;
  if (missing > 0) {
    return ProductionNextStep(
      stage: ProductionStage.storyboard,
      nodeId: 'storyboard',
      text: l10n.productionNextStepImages(missing.toString()),
    );
  }
  return ProductionNextStep(
    stage: ProductionStage.workbench,
    nodeId: 'workbench',
    text: l10n.productionNextStepDone,
    finished: true,
  );
}

/// 常驻的「下一步」条：说清楚该做什么，并能把画布定位到那张卡片。
class ProductionNextStepBar extends StatelessWidget {
  final ProductionNextStep step;
  final VoidCallback onLocate;

  const ProductionNextStepBar({
    super.key,
    required this.step,
    required this.onLocate,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final accent = step.stage.accent;
    return Container(
      key: const Key('production-next-step'),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        // 序号沿用卡片上的那套，扫一眼就知道去找第几张卡。
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            step.finished
                ? l10n.productionNextStepLabel
                : '${l10n.productionNextStepLabel} · ${step.stage.step}',
            style: TextStyle(
              fontSize: 11,
              height: 1.0,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            step.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DFTokens.body14.copyWith(color: df.textPrimary),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          key: const Key('production-next-step-locate'),
          onPressed: onLocate,
          child: Text(l10n.productionNextStepLocate),
        ),
      ]),
    );
  }
}
