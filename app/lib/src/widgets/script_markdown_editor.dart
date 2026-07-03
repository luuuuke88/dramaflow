import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/l10n_ext.dart';

class ScriptMarkdownEditor extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const ScriptMarkdownEditor({
    super.key,
    required this.controller,
    required this.hintText,
    this.minLines = 10,
    this.maxLines = 18,
    this.onChanged,
  });

  @override
  State<ScriptMarkdownEditor> createState() => _ScriptMarkdownEditorState();
}

class _ScriptMarkdownEditorState extends State<ScriptMarkdownEditor> {
  bool _preview = false;

  void _notifyChanged() => widget.onChanged?.call(widget.controller.text);

  void _insertOrWrap(String prefix, String suffix, String placeholder) {
    final value = widget.controller.value;
    final text = value.text;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: text.length);
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final selected = start == end ? placeholder : text.substring(start, end);
    final insert = '$prefix$selected$suffix';
    final next = text.replaceRange(start, end, insert);
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection(
        baseOffset: start + prefix.length,
        extentOffset: start + prefix.length + selected.length,
      ),
    );
    _notifyChanged();
    if (_preview) setState(() => _preview = false);
  }

  void _insertHeading() {
    final value = widget.controller.value;
    final text = value.text;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: text.length);
    final cursor = selection.start.clamp(0, text.length);
    final lineStart = text.lastIndexOf('\n', cursor == 0 ? 0 : cursor - 1) + 1;
    final hasHeading = text.substring(lineStart).startsWith('# ');
    if (hasHeading) return;
    final next = text.replaceRange(lineStart, lineStart, '# ');
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor + 2),
    );
    _notifyChanged();
    if (_preview) setState(() => _preview = false);
  }

  void _insertDialogue() {
    final text = widget.controller.text;
    final suffix = text.isEmpty || text.endsWith('\n') ? '' : '\n';
    final snippet = '> ${context.l10n.scriptMarkdownDialogueSnippet}';
    widget.controller.value = TextEditingValue(
      text: '$text$suffix$snippet',
      selection: TextSelection.collapsed(
        offset: '$text$suffix$snippet'.length,
      ),
    );
    _notifyChanged();
    if (_preview) setState(() => _preview = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: df.stroke),
        borderRadius: BorderRadius.circular(DFTokens.radiusControl),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ToolButton(
                tooltip: l10n.scriptMarkdownBold,
                icon: Icons.format_bold,
                onPressed: () => _insertOrWrap(
                    '**', '**', l10n.scriptMarkdownBoldPlaceholder),
              ),
              _ToolButton(
                tooltip: l10n.scriptMarkdownItalic,
                icon: Icons.format_italic,
                onPressed: () => _insertOrWrap(
                    '*', '*', l10n.scriptMarkdownItalicPlaceholder),
              ),
              _ToolButton(
                tooltip: l10n.scriptMarkdownHeading,
                icon: Icons.title,
                onPressed: _insertHeading,
              ),
              _ToolButton(
                tooltip: l10n.scriptMarkdownDialogue,
                icon: Icons.record_voice_over_outlined,
                onPressed: _insertDialogue,
              ),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(l10n.scriptMarkdownEdit),
                    icon: const Icon(Icons.edit_note_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(l10n.scriptMarkdownPreview),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                  ),
                ],
                selected: {_preview},
                onSelectionChanged: (v) => setState(() => _preview = v.single),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: df.stroke),
        if (_preview)
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: widget.minLines * 22,
              maxHeight: widget.maxLines * 24,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: ScriptMarkdownPreview(markdown: widget.controller.text),
            ),
          )
        else
          TextField(
            controller: widget.controller,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 13, height: 1.5),
            decoration: InputDecoration(
              hintText: widget.hintText,
              alignLabelWithHint: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(12),
            ),
            onChanged: widget.onChanged,
          ),
      ]),
    );
  }
}

class ScriptMarkdownPreview extends StatelessWidget {
  final String markdown;

  const ScriptMarkdownPreview({super.key, required this.markdown});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final lines = markdown.split('\n');
    if (markdown.trim().isEmpty) {
      return Text(
        context.l10n.scriptMarkdownPreviewEmpty,
        style: TextStyle(fontSize: 12, color: df.textTertiary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines) _MarkdownLine(line: line),
      ],
    );
  }
}

class _MarkdownLine extends StatelessWidget {
  final String line;

  const _MarkdownLine({required this.line});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final trimmed = line.trimRight();
    if (trimmed.isEmpty) return const SizedBox(height: 8);
    if (trimmed.startsWith('# ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          _stripInline(trimmed.substring(2)),
          style: TextStyle(
            fontSize: 15,
            height: 1.35,
            fontWeight: FontWeight.w800,
            color: df.textPrimary,
          ),
        ),
      );
    }
    if (trimmed.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(
          _stripInline(trimmed.substring(3)),
          style: TextStyle(
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w700,
            color: df.textPrimary,
          ),
        ),
      );
    }
    if (trimmed.startsWith('> ')) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: df.primary, width: 3)),
          color: df.surfaceMuted,
        ),
        child: Text(
          _stripInline(trimmed.substring(2)),
          style: TextStyle(fontSize: 12, height: 1.45, color: df.textMid),
        ),
      );
    }
    if (trimmed.startsWith('- ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('• ', style: TextStyle(fontSize: 12, color: df.textMid)),
          Expanded(
            child: Text(
              _stripInline(trimmed.substring(2)),
              style: TextStyle(fontSize: 12, height: 1.45, color: df.textMid),
            ),
          ),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        _stripInline(trimmed),
        style: TextStyle(fontSize: 12, height: 1.5, color: df.textMid),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _ToolButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
    );
  }
}

String _stripInline(String input) {
  return input
      .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1) ?? '')
      .replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1) ?? '')
      .replaceAllMapped(RegExp(r'`(.+?)`'), (m) => m.group(1) ?? '');
}
