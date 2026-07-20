import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

typedef ExternalUriOpener = Future<bool> Function(Uri uri);

sealed class ExternalTextPart {
  final String text;

  const ExternalTextPart(this.text);
}

class ExternalPlainTextPart extends ExternalTextPart {
  const ExternalPlainTextPart(super.text);
}

class ExternalLinkPart extends ExternalTextPart {
  final Uri uri;

  const ExternalLinkPart({required String text, required this.uri})
      : super(text);

  String get label => text;
}

const _linkPattern =
    r'\[([^\]\r\n]+)\]\((https?://[A-Za-z0-9][^\s)]+)\)|(https?://[A-Za-z0-9][^\s<>()\[\]{}]+)';
final _externalLinkPattern = RegExp(_linkPattern, caseSensitive: false);
final _trailingPunctuation = RegExp(r'[.,!?;:]+$');

/// Splits ordinary message text into plain text and links that are safe to
/// hand to the operating system. Unsupported schemes remain visible text.
List<ExternalTextPart> parseExternalLinkText(String text) {
  final parts = <ExternalTextPart>[];
  var cursor = 0;

  for (final match in _externalLinkPattern.allMatches(text)) {
    if (match.start > cursor) {
      parts.add(ExternalPlainTextPart(text.substring(cursor, match.start)));
    }

    final markdownLabel = match.group(1);
    final target = match.group(2) ?? match.group(3)!;
    final normalizedTarget = target.replaceFirst(_trailingPunctuation, '');
    final uri = Uri.tryParse(normalizedTarget);
    if (uri == null || !isSafeExternalUri(uri)) {
      parts.add(ExternalPlainTextPart(match.group(0)!));
    } else {
      parts.add(ExternalLinkPart(
        text: markdownLabel ?? normalizedTarget,
        uri: uri,
      ));
      final trailing = target.substring(normalizedTarget.length);
      if (trailing.isNotEmpty) parts.add(ExternalPlainTextPart(trailing));
    }
    cursor = match.end;
  }

  if (cursor < text.length) {
    parts.add(ExternalPlainTextPart(text.substring(cursor)));
  }
  return parts.isEmpty ? [ExternalPlainTextPart(text)] : parts;
}

bool isSafeExternalUri(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    RegExp(r'[A-Za-z0-9]').hasMatch(uri.host);

Future<bool> openExternalUri(Uri uri) {
  if (!isSafeExternalUri(uri)) return Future.value(false);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Inline message text that opens only explicit HTTP(S) links externally.
/// It supports bare URLs and Markdown's `[label](https://example.com)` form.
class ExternalLinkText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final int? maxLines;
  final TextOverflow overflow;
  final ExternalUriOpener? openExternal;

  const ExternalLinkText({
    super.key,
    required this.text,
    this.style,
    this.linkStyle,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.openExternal,
  });

  @override
  State<ExternalLinkText> createState() => _ExternalLinkTextState();
}

class _ExternalLinkTextState extends State<ExternalLinkText> {
  late List<ExternalTextPart> _parts;
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _refreshParts();
  }

  @override
  void didUpdateWidget(covariant ExternalLinkText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.openExternal != widget.openExternal) {
      _disposeRecognizers();
      _refreshParts();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _refreshParts() {
    _parts = parseExternalLinkText(widget.text);
    for (final part in _parts.whereType<ExternalLinkPart>()) {
      _recognizers.add(TapGestureRecognizer()..onTap = () => _open(part.uri));
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(Uri uri) async {
    await (widget.openExternal ?? openExternalUri)(uri);
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = widget.style ?? DefaultTextStyle.of(context).style;
    final links = _recognizers.iterator;
    final defaultLinkStyle = baseStyle.copyWith(
      color: baseStyle.color ?? Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: baseStyle.color ?? Theme.of(context).colorScheme.primary,
    );
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: _parts.map((part) {
          if (part is ExternalLinkPart) {
            links.moveNext();
            return TextSpan(
              text: part.text,
              style: widget.linkStyle ?? defaultLinkStyle,
              recognizer: links.current,
            );
          }
          return TextSpan(text: part.text);
        }).toList(growable: false),
      ),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
