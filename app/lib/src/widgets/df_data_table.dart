import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/l10n_ext.dart';

class DFDataColumn {
  final String label;
  final bool numeric;

  const DFDataColumn({required this.label, this.numeric = false});
}

class DFDataRow {
  final String id;
  final List<Widget> cells;
  final VoidCallback? onTap;

  const DFDataRow({required this.id, required this.cells, this.onTap});
}

class DFPagination {
  final int page;
  final int pageSize;
  final int total;

  const DFPagination({
    required this.page,
    required this.pageSize,
    required this.total,
  });

  int get pageCount {
    if (total <= 0 || pageSize <= 0) return 1;
    return (total / pageSize).ceil();
  }
}

typedef DFMobileCardBuilder = Widget Function(
    BuildContext context, DFDataRow row);

class DFDataTable extends StatelessWidget {
  static const breakpoint = 840.0;

  final List<DFDataColumn> columns;
  final List<DFDataRow> rows;
  final bool selectable;
  final Set<String>? selectedIds;
  final ValueChanged<Set<String>>? onSelectionChanged;
  final DFPagination? pagination;
  final ValueChanged<int>? onPageChange;
  final DFMobileCardBuilder mobileCardBuilder;

  const DFDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.selectable = false,
    this.selectedIds,
    this.onSelectionChanged,
    this.pagination,
    this.onPageChange,
    required this.mobileCardBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      if (width < breakpoint) {
        return _MobileRows(
          rows: rows,
          selectable: selectable,
          selectedIds: selectedIds ?? const <String>{},
          onSelectionChanged: onSelectionChanged,
          pagination: pagination,
          onPageChange: onPageChange,
          mobileCardBuilder: mobileCardBuilder,
        );
      }
      return _DesktopTable(
        columns: columns,
        rows: rows,
        selectable: selectable,
        selectedIds: selectedIds ?? const <String>{},
        onSelectionChanged: onSelectionChanged,
        pagination: pagination,
        onPageChange: onPageChange,
      );
    });
  }
}

class _DesktopTable extends StatelessWidget {
  final List<DFDataColumn> columns;
  final List<DFDataRow> rows;
  final bool selectable;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>>? onSelectionChanged;
  final DFPagination? pagination;
  final ValueChanged<int>? onPageChange;

  const _DesktopTable({
    required this.columns,
    required this.rows,
    required this.selectable,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.pagination,
    required this.onPageChange,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.df;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        border: Border.all(color: colors.stroke),
        boxShadow: DFTokens.cardRest,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: selectable,
                onSelectAll: selectable ? _setAllSelected : null,
                headingRowColor: WidgetStatePropertyAll(colors.surfaceMuted),
                dataRowColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.selected)) {
                    return colors.primarySubtle;
                  }
                  return colors.surface;
                }),
                headingTextStyle: DFTokens.caption12.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
                dataTextStyle:
                    DFTokens.body14.copyWith(color: colors.textPrimary),
                dividerThickness: 1,
                columns: [
                  for (final column in columns)
                    DataColumn(
                      numeric: column.numeric,
                      label: Text(column.label),
                    ),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      key: ValueKey(row.id),
                      selected: selectedIds.contains(row.id),
                      onSelectChanged: selectable
                          ? (selected) =>
                              _setSelected(row.id, selected ?? false)
                          : row.onTap == null
                              ? null
                              : (_) => row.onTap?.call(),
                      cells: _cellsFor(row),
                    ),
                ],
              ),
            ),
            if (pagination != null)
              _PaginationBar(
                pagination: pagination!,
                onPageChange: onPageChange,
              ),
          ],
        ),
      ),
    );
  }

  List<DataCell> _cellsFor(DFDataRow row) {
    return [
      for (var i = 0; i < columns.length; i += 1)
        DataCell(i < row.cells.length ? row.cells[i] : const SizedBox.shrink()),
    ];
  }

  void _setSelected(String id, bool selected) {
    final next = Set<String>.from(selectedIds);
    if (selected) {
      next.add(id);
    } else {
      next.remove(id);
    }
    onSelectionChanged?.call(next);
  }

  void _setAllSelected(bool? selected) {
    final rowIds = rows.map((row) => row.id);
    final next = Set<String>.from(selectedIds);
    if (selected ?? false) {
      next.addAll(rowIds);
    } else {
      next.removeAll(rowIds);
    }
    onSelectionChanged?.call(next);
  }
}

class _MobileRows extends StatelessWidget {
  final List<DFDataRow> rows;
  final bool selectable;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>>? onSelectionChanged;
  final DFPagination? pagination;
  final ValueChanged<int>? onPageChange;
  final DFMobileCardBuilder mobileCardBuilder;

  const _MobileRows({
    required this.rows,
    required this.selectable,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.pagination,
    required this.onPageChange,
    required this.mobileCardBuilder,
  });

  @override
  Widget build(BuildContext context) {
    Widget list({required bool bounded}) => ListView.separated(
          shrinkWrap: !bounded,
          physics: bounded ? null : const NeverScrollableScrollPhysics(),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: DFTokens.s12),
          itemBuilder: (context, index) {
            final row = rows[index];
            final selected = selectedIds.contains(row.id);
            return _MobileCardFrame(
              selected: selected,
              onTap: selectable ? () => _toggle(row.id, selected) : row.onTap,
              child: mobileCardBuilder(context, row),
            );
          },
        );

    return LayoutBuilder(builder: (context, constraints) {
      // 外层给了确定高度（比如被 Expanded 包住）就用正常的可滚动列表，
      // 数据多时在自己范围内滚动；外层高度不确定（比如嵌在别的 ListView
      // 里）才用 shrinkWrap + 禁用自身滚动，交给外层滚动。
      // 之前一律用 shrinkWrap + 禁用滚动，数据一多、外层又给了固定高度时，
      // 内容会把外层撑爆（章节选择表数据多时的溢出报错正是这个原因）。
      final bounded = constraints.hasBoundedHeight;
      final listWidget = list(bounded: bounded);
      final column = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bounded ? Expanded(child: listWidget) : listWidget,
          if (pagination != null)
            Padding(
              padding: const EdgeInsets.only(top: DFTokens.s12),
              child: _PaginationBar(
                pagination: pagination!,
                onPageChange: onPageChange,
              ),
            ),
        ],
      );
      return bounded
          ? SizedBox(height: constraints.maxHeight, child: column)
          : column;
    });
  }

  void _toggle(String id, bool selected) {
    final next = Set<String>.from(selectedIds);
    if (selected) {
      next.remove(id);
    } else {
      next.add(id);
    }
    onSelectionChanged?.call(next);
  }
}

class _MobileCardFrame extends StatefulWidget {
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  const _MobileCardFrame({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  State<_MobileCardFrame> createState() => _MobileCardFrameState();
}

class _MobileCardFrameState extends State<_MobileCardFrame> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.df;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: DFTokens.fast120,
        curve: DFTokens.curve,
        decoration: BoxDecoration(
          color: widget.selected || _hovered
              ? colors.primarySubtle
              : colors.surface,
          borderRadius: BorderRadius.circular(DFTokens.radiusCard),
          border: Border.all(
            color: widget.selected ? colors.primary : colors.stroke,
          ),
          boxShadow: _hovered ? DFTokens.cardHover : DFTokens.cardRest,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(DFTokens.radiusCard),
            child: Padding(
              padding: const EdgeInsets.all(DFTokens.s16),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  final DFPagination pagination;
  final ValueChanged<int>? onPageChange;

  const _PaginationBar({
    required this.pagination,
    required this.onPageChange,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.df;
    final page = pagination.page.clamp(1, pagination.pageCount).toInt();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DFTokens.s16,
        vertical: DFTokens.s12,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(top: BorderSide(color: colors.stroke)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            context.l10n.dataTableTotal(pagination.total),
            style: DFTokens.caption12.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(width: DFTokens.s16),
          IconButton(
            tooltip: context.l10n.dataTablePrevPage,
            onPressed: page > 1 ? () => onPageChange?.call(page - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text(
            '$page / ${pagination.pageCount}',
            style: DFTokens.caption12.copyWith(
              color: colors.textPrimary,
              fontFeatures: DFTokens.tabularFigures,
            ),
          ),
          IconButton(
            tooltip: context.l10n.dataTableNextPage,
            onPressed: page < pagination.pageCount
                ? () => onPageChange?.call(page + 1)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}
