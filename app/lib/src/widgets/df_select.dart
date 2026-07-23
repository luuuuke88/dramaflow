// 苹果 macOS 风格自适应下拉选择器 (DFSelect)：
// - 针对 AI 模型名称过长方案：
//   1. 自动解构 "供应商 · 模型名" -> [供应商 Badge] + 突出模型真实名称
//   2. 下拉菜单浮层宽自适应 (280px ~ 460px)，解决显示不全裁切问题
//   3. 鼠标 Hover 显示 Full Label 浮动完整提示 (Tooltip)
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

class DFSelectItem<T> {
  final T value;
  final String label;
  final String? subtitle;
  final String? badge;

  const DFSelectItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.badge,
  });

  /// 智能解析：若 label 含有 " · " (如 "volcengine · doubao-seedance")，自动提取前缀为 Badge
  String get parsedBadge {
    if (badge != null && badge!.isNotEmpty) return badge!;
    if (label.contains(' · ')) {
      return label.split(' · ').first.trim();
    }
    return '';
  }

  String get parsedModelName {
    if (label.contains(' · ')) {
      final parts = label.split(' · ');
      if (parts.length > 1) return parts.sublist(1).join(' · ').trim();
    }
    return label;
  }
}

class DFSelect<T> extends StatefulWidget {
  final T? value;
  final String? hint;
  final List<DFSelectItem<T>> items;
  final ValueChanged<T?> onChanged;
  final double? popoverMinWidth;
  final double? popoverMaxWidth;

  const DFSelect({
    super.key,
    required this.value,
    this.hint,
    required this.items,
    required this.onChanged,
    this.popoverMinWidth,
    this.popoverMaxWidth,
  });

  @override
  State<DFSelect<T>> createState() => _DFSelectState<T>();
}

class _DFSelectState<T> extends State<DFSelect<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final selectedItem = widget.items
        .where((item) => item.value == widget.value)
        .firstOrNull;

    final displayText = selectedItem?.label ?? widget.hint ?? '';
    final isHint = selectedItem == null;

    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: df.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shadowColor: Colors.black38,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: df.stroke, width: 1),
          ),
        ),
      ),
      child: PopupMenuButton<T>(
        tooltip: '',
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        constraints: BoxConstraints(
          minWidth: widget.popoverMinWidth ?? 280,
          maxWidth: widget.popoverMaxWidth ?? 460,
        ),
        onSelected: widget.onChanged,
        itemBuilder: (context) => [
          for (final item in widget.items)
            PopupMenuItem<T>(
              value: item.value,
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: _DFSelectOptionTile<T>(
                item: item,
                isSelected: item.value == widget.value,
              ),
            ),
        ],
        child: Tooltip(
          message: displayText,
          waitDuration: const Duration(milliseconds: 500),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: AnimatedContainer(
              duration: DFTokens.fast120,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _hover
                    ? df.surfaceMuted.withValues(alpha: 0.8)
                    : df.surfaceMuted,
                borderRadius: BorderRadius.circular(DFTokens.radiusControl),
                border: Border.all(
                  color: _hover ? df.primary.withValues(alpha: 0.5) : df.stroke,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTriggerLabel(df, selectedItem, isHint),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.unfold_more,
                    size: 16,
                    color: df.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTriggerLabel(
      DFColors df, DFSelectItem<T>? selectedItem, bool isHint) {
    if (isHint || selectedItem == null) {
      return Text(
        widget.hint ?? '',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: df.textTertiary),
      );
    }

    final badge = selectedItem.parsedBadge;
    final modelName = selectedItem.parsedModelName;

    if (badge.isNotEmpty) {
      return Row(
        children: [
          // 供应商名可能很长：角标允许收缩省略，避免把触发框挤爆。
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: df.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: df.primary.withValues(alpha: 0.3), width: 0.5),
              ),
              child: Text(
                badge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: df.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              modelName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: df.textPrimary,
              ),
            ),
          ),
        ],
      );
    }

    return Text(
      displayText(selectedItem),
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, color: df.textPrimary),
    );
  }

  String displayText(DFSelectItem<T> item) => item.label;
}

class _DFSelectOptionTile<T> extends StatefulWidget {
  final DFSelectItem<T> item;
  final bool isSelected;

  const _DFSelectOptionTile({
    required this.item,
    required this.isSelected,
  });

  @override
  State<_DFSelectOptionTile<T>> createState() => _DFSelectOptionTileState<T>();
}

class _DFSelectOptionTileState<T> extends State<_DFSelectOptionTile<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final isSelected = widget.isSelected;
    final item = widget.item;
    final badge = item.parsedBadge;
    final modelName = item.parsedModelName;

    return Tooltip(
      message: item.label,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: DFTokens.fast120,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? df.primary.withValues(alpha: 0.15)
                : (_hover ? df.surfaceMuted : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              if (badge.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? df.primary.withValues(alpha: 0.2)
                        : df.surfaceMuted,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected
                          ? df.primary.withValues(alpha: 0.4)
                          : df.stroke,
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? df.primary : df.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  modelName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected ? df.primary : df.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check, size: 16, color: df.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
