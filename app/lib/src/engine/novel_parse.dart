// 拆章算法：逐行移植 docs/reference/toonflow-parseNovel.ts（行为一致优先于 Dart 惯用法）。
// docx 文本提取：解 zip 取 word/document.xml，按 <w:p> 段落聚合 <w:t>。
import 'dart:convert';

import 'package:archive/archive.dart';

import 'errors.dart';

final _reelRegex = RegExp(
  r'^(第[\d一二三四五六七八九十百千]+卷)\s*([^\n第]*)',
  multiLine: true,
);
final _defaultChapterRegex = RegExp(
  r'第\s*([0-9０-９零一二三四五六七八九十百千万]+)\s*[章回节]\s*([^\n\r]*)',
);

const _chineseNumMap = {
  '零': 0,
  '一': 1,
  '二': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
  '九': 9,
};
const _chineseUnitMap = {'十': 10, '百': 100, '千': 1000};

class ParsedChapter {
  final int index;
  final String chapter;
  final String text;
  const ParsedChapter({
    required this.index,
    required this.chapter,
    required this.text,
  });
}

class ReelParse {
  final int index;
  final String reel;
  final List<ParsedChapter> chapters;
  ReelParse({required this.index, required this.reel, required this.chapters});
}

class ChapterItem {
  final int index;
  final String reel;
  final String chapter;
  final String chapterData;
  const ChapterItem({
    required this.index,
    required this.reel,
    required this.chapter,
    required this.chapterData,
  });
}

/// ts parseNumber 逐行移植（含"十X"特例；非法输入返回 0，行为与 JS 一致）。
int parseChineseNumber(String numStr) {
  if (RegExp(r'^\d+$').hasMatch(numStr)) return int.parse(numStr);
  if (RegExp(r'^十[一二三四五六七八九]?$').hasMatch(numStr)) {
    if (numStr.length == 1) return 10;
    return 10 + _chineseNumMap[numStr[1]]!;
  }
  var num = 0, digit = 0;
  for (final c in numStr.split('')) {
    if (_chineseNumMap.containsKey(c)) {
      digit = _chineseNumMap[c]!;
    } else if (_chineseUnitMap.containsKey(c)) {
      if (digit == 0 && c == '十') digit = 1;
      num += digit * _chineseUnitMap[c]!;
      digit = 0;
    }
  }
  return num + digit;
}

RegExp _resolveChapterRegex(String? chapterReg) {
  final regStr = chapterReg?.trim() ?? '';
  if (regStr.isEmpty) return _defaultChapterRegex;
  final m = RegExp(r'^/(.*)/([igmuy]*)$').firstMatch(regStr);
  final pattern = m != null ? m.group(1)! : regStr;
  final flags = m?.group(2) ?? '';
  try {
    return RegExp(
      pattern,
      caseSensitive: !flags.contains('i'),
      multiLine: flags.contains('m'),
      unicode: flags.contains('u'),
    );
  } on FormatException {
    throw EngineException(errRegexInvalid, {'pattern': regStr});
  }
}

List<ParsedChapter> _parseChaptersIn(String section, RegExp chapterRegex) {
  final matches = chapterRegex.allMatches(section).toList();
  final chapters = <ParsedChapter>[];
  for (var i = 0; i < matches.length; i++) {
    final start = matches[i].end;
    final end = i + 1 < matches.length ? matches[i + 1].start : section.length;
    final content = section
        .substring(start, end)
        .replaceFirst(RegExp(r'^[\r\n]+'), '')
        .trim();
    chapters.add(ParsedChapter(
      index: parseChineseNumber(
        matches[i].group(1)!.replaceAll(RegExp('第|章'), ''),
      ),
      chapter: (matches[i].group(2) ?? '').trim(),
      text: content,
    ));
  }
  return chapters;
}

List<ReelParse> parseNovel(String text, {String? chapterReg}) {
  final reelMatches = _reelRegex.allMatches(text).toList();
  final chapterRegex = _resolveChapterRegex(chapterReg);

  // 没有卷结构
  if (reelMatches.isEmpty) {
    var chapters = _parseChaptersIn(text, chapterRegex);
    if (chapters.isEmpty && text.trim().isNotEmpty) {
      chapters = [ParsedChapter(index: 1, chapter: '', text: text.trim())];
    }
    chapters.sort((a, b) => a.index - b.index);
    return [ReelParse(index: 1, reel: '正文卷', chapters: chapters)];
  }

  // 有卷结构
  final reelMap = <String, ReelParse>{};
  for (var i = 0; i < reelMatches.length; i++) {
    final match = reelMatches[i];
    final reelRaw = match.group(1)!;
    final reelName = (match.group(2) ?? '').trim();
    final end =
        i + 1 < reelMatches.length ? reelMatches[i + 1].start : text.length;
    final reelSection = text.substring(match.start, end);

    var chapters = _parseChaptersIn(reelSection, chapterRegex);
    if (chapters.isEmpty &&
        reelSection.replaceAll(_reelRegex, '').trim().isNotEmpty) {
      chapters = [
        ParsedChapter(
          index: 1,
          chapter: '',
          text: reelSection.replaceAll(_reelRegex, '').trim(),
        ),
      ];
    }
    chapters.sort((a, b) => a.index - b.index);

    final reel = reelMap.putIfAbsent(
      reelName,
      () => ReelParse(
        index: parseChineseNumber(reelRaw.replaceAll(RegExp('第|卷'), '')),
        reel: reelName,
        chapters: [],
      ),
    );
    reel.chapters.addAll(chapters);
  }
  final result = reelMap.values.toList()
    ..sort((a, b) => a.index - b.index);
  for (final reel in result) {
    reel.chapters.sort((a, b) => a.index - b.index);
  }
  return result;
}

/// 供导入页/引擎使用：卷结构拍平为章节条目（对应 importNovel.vue 的 flatMap）。
List<ChapterItem> flattenParsedNovel(List<ReelParse> reels) => [
      for (final reel in reels)
        for (final chapter in reel.chapters)
          ChapterItem(
            index: chapter.index,
            reel: reel.reel,
            chapter: chapter.chapter,
            chapterData: chapter.text,
          ),
    ];

String _unescapeXml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    )
    .replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!)),
    )
    .replaceAll('&amp;', '&');

/// docx → 纯文本：段落（`<w:p>`）之间以换行连接。坏文件抛 errFileType。
String extractDocxText(List<int> bytes) {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const EngineException(errFileType);
  }
  final entry = archive.findFile('word/document.xml');
  if (entry == null) {
    throw const EngineException(errFileType);
  }
  final xml = utf8.decode(entry.content as List<int>, allowMalformed: true);
  final textRun = RegExp(r'<w:t[^>]*>([\s\S]*?)</w:t>');
  final paragraphs = <String>[];
  for (final para in xml.split('</w:p>')) {
    final buf = StringBuffer();
    for (final m in textRun.allMatches(para)) {
      buf.write(_unescapeXml(m.group(1)!));
    }
    final line = buf.toString();
    if (line.trim().isNotEmpty) paragraphs.add(line);
  }
  return paragraphs.join('\n');
}
