// 视频生产画布的节点卡片外壳。
//
// 这里的颜色不是装饰，是信息：画布上的六个节点构成一条流水线
// （剧本 → 规划 → 分镜表 → 分镜 → 工作台，资产是挂在剧本旁边的支线），
// 卡片顶端那条色带按「冷 → 暖」排布，缩到很小、标题已经看不清的时候，
// 靠色带的冷暖依然读得出流程走向和自己在哪一段。
//
// 支线节点（资产）用紫色并且不给序号——它不在主链的计数里，标个数字反而误导。
import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../theme/tokens.dart';

/// 画布节点在流水线中的位置。顺序即声明顺序，色相由冷到暖。
enum ProductionStage {
  script(1, Color(0xFF3B5BA9)),
  assets(null, Color(0xFF7A5AA8)),
  scriptPlan(2, Color(0xFF2F8A82)),
  storyboardTable(3, Color(0xFFB08420)),
  storyboard(4, Color(0xFFC2703A)),
  workbench(5, Color(0xFFB4483F));

  /// 主链上的步骤号；支线节点为 null。
  final int? step;
  final Color accent;
  const ProductionStage(this.step, this.accent);
}

/// 节点卡片外壳：圆角、描边、投影，顶端一条 3px 的阶段色带。
class ProductionNodeCard extends StatelessWidget {
  final ProductionStage stage;
  final Widget child;

  const ProductionNodeCard({
    super.key,
    required this.stage,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Container(
      decoration: BoxDecoration(
        color: df.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: df.stroke),
        boxShadow: [
          // 两层投影：一层贴边勾轮廓，一层散开托起卡片。画布背景有网格，
          // 单层硬投影会显得卡片"贴"在网格上，浮不起来。
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 3, child: ColoredBox(color: stage.accent)),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// 节点标题栏：浅色底 + 细分隔线，左侧是阶段徽标，右侧放操作。
///
/// 原先这里是整条纯黑填充（`df.textPrimary`），六张卡片并排时像六根黑杠，
/// 既压过了卡片内容，也和画布的浅色调打架。
class ProductionNodeHeader extends StatelessWidget {
  final ProductionStage stage;
  final String title;
  final VoidCallback? onEdit;
  final Widget? action;
  final String editTooltip;

  const ProductionNodeHeader({
    super.key,
    required this.stage,
    required this.title,
    required this.editTooltip,
    this.onEdit,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final compactRight = action != null || onEdit != null;
    return Container(
      padding: EdgeInsets.fromLTRB(10, 6, compactRight ? 6 : 12, 6),
      decoration: BoxDecoration(
        color: df.surfaceMuted,
        border: Border(bottom: BorderSide(color: df.stroke)),
      ),
      child: Row(children: [
        _StageBadge(stage: stage),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              color: df.textPrimary,
            ),
          ),
        ),
        if (action != null) ...[
          action!,
          const SizedBox(width: 4),
        ],
        if (onEdit != null)
          IconButton(
            tooltip: editTooltip,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(Icons.edit_outlined, size: 15, color: df.textSecondary),
            onPressed: onEdit,
          ),
      ]),
    );
  }
}

/// 阶段徽标：主链显示步骤号，支线显示一个圆点。
class _StageBadge extends StatelessWidget {
  final ProductionStage stage;
  const _StageBadge({required this.stage});

  @override
  Widget build(BuildContext context) {
    final step = stage.step;
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: stage.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: step == null
          ? Container(
              width: 5,
              height: 5,
              decoration:
                  BoxDecoration(color: stage.accent, shape: BoxShape.circle),
            )
          : Text(
              '$step',
              style: TextStyle(
                fontSize: 11,
                height: 1.0,
                fontWeight: FontWeight.w700,
                color: stage.accent,
              ),
            ),
    );
  }
}

/// 节点内的次级留白，统一给各节点正文用，免得每处各写一套。
const productionNodeBodyPadding = EdgeInsets.all(DFTokens.s12);
