// 事件分析视图（照抄 eventAnalysis.vue 的按章折叠呈现；ToonFlow 后端缺失此功能，
// DramaFlow 以真实 LLM 分析补齐）。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/events.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';

Future<void> showEventAnalysisView(BuildContext context, WidgetRef ref,
    {required int projectId, required List<int> novelIds}) {
  return showDFAdaptiveDialog<void>(
    context,
    title: context.l10n.novelEventAnalysis,
    desktopWidthFactor: 0.56,
    builder: (c) =>
        _EventAnalysisBody(projectId: projectId, novelIds: novelIds, ref: ref),
  );
}

class _EventAnalysisBody extends StatefulWidget {
  final int projectId;
  final List<int> novelIds;
  final WidgetRef ref;
  const _EventAnalysisBody(
      {required this.projectId, required this.novelIds, required this.ref});

  @override
  State<_EventAnalysisBody> createState() => _EventAnalysisBodyState();
}

class _EventAnalysisBodyState extends State<_EventAnalysisBody> {
  bool _loading = false;
  String? _error;
  List<({int chapterIndex, String analysis})> _items = const [];

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.ref
          .read(engineProvider)
          .eventAnalysis(widget.projectId, widget.novelIds);
      final decoded = jsonDecode(raw);
      _items = [
        if (decoded is List)
          for (final item in decoded.whereType<Map>())
            (
              chapterIndex: ((item['chapterIndex'] as num?) ?? 0).toInt(),
              analysis: (item['analysis'] ?? '').toString(),
            ),
      ];
      if (_items.isEmpty) _error = raw; // 非 JSON 时原样展示
    } catch (e) {
      _error = mounted ? localizeError(context, e) : '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: SizedBox(
          height: 420,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _loading
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(l10n.novelAnalysisAnalyzing,
                          style: TextStyle(
                              fontSize: 13, color: df.textSecondary)),
                    ],
                  )
                : _items.isEmpty && _error == null
                    ? Center(
                        child: FilledButton.icon(
                          onPressed: _run,
                          icon: const Icon(Icons.analytics_outlined, size: 18),
                          label: Text(l10n.novelAnalysisStartAnalysis),
                        ),
                      )
                    : _error != null
                        ? SingleChildScrollView(
                            child: SelectableText(_error!,
                                style: TextStyle(
                                    fontSize: 13, color: df.textSecondary)))
                        : ListView(children: [
                            for (final item in _items)
                              Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ExpansionTile(
                                  initiallyExpanded: true,
                                  title: Text(
                                    l10n.novelAnalysisChapterHeader(
                                        '${item.chapterIndex}', ''),
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  childrenPadding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  children: [
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: SelectableText(item.analysis,
                                          style:
                                              const TextStyle(fontSize: 13)),
                                    ),
                                  ],
                                ),
                              ),
                          ]),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
        ]),
      ),
    ]);
  }
}
