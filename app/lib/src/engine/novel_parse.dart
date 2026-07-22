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

// 卷名/章节名前经常跟着"：""·""-"这类分隔符（比如"第一卷：血染白狼谷"），
// 正则只按空白切分，这些分隔符会被原样留在捕获到的名字开头，这里统一清掉。
final _leadingSeparator = RegExp(r'^[：:·\-—\s]+');
String _stripLeadingSeparator(String s) => s.replaceFirst(_leadingSeparator, '');

List<ParsedChapter> _parseChaptersIn(String section, RegExp chapterRegex) {
  final matches = chapterRegex.allMatches(section).toList();
  final chapters = <ParsedChapter>[];
  // 同一个道理：第一个"第X章"之前可能还有楔子/序之类不按"第X章"格式写的
  // 开篇内容，同样不能整段丢掉，归到章号 0（无章名）里。
  if (matches.isNotEmpty) {
    final leading = section.substring(0, matches.first.start).trim();
    if (leading.isNotEmpty) {
      chapters.add(ParsedChapter(index: 0, chapter: '', text: leading));
    }
  }
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
      chapter: _stripLeadingSeparator((matches[i].group(2) ?? '').trim()),
      text: content,
    ));
  }
  return chapters;
}

// 有些小说会在卷末写一句"下卷预告"式的过渡句（如"第一卷·XX" + "开篇完" +
// 书名重复，然后才是真正的"第一卷：XX"正文标题），这句预告长得跟真卷标题
// 一模一样，会被 _reelRegex 误判成一个新卷。
// 判断标准：如果这个"卷标题"紧挨着下一个卷标题（间隔很短），且中间没有夹着
// 任何真正的章节标记，那它大概率只是装饰性的过渡句，不是真卷标题——直接
// 丢弃，不生成卷、也不把中间的"开篇完"之类残余文字当成一个空章节。
// 阈值 200 字符：真正的"整卷无章节细分、直接大段正文"场景（比如后面没有
// 下一卷了）间隔通常远超这个数，不会被误伤。
const _noiseGapChars = 200;

List<RegExpMatch> _dropDecorativeReelHeadings(
  String text,
  List<RegExpMatch> reelMatches,
  RegExp chapterRegex,
) {
  final kept = <RegExpMatch>[];
  for (var i = 0; i < reelMatches.length; i++) {
    final isLast = i == reelMatches.length - 1;
    if (!isLast) {
      final next = reelMatches[i + 1];
      final gapText = text.substring(reelMatches[i].end, next.start);
      final isNoise =
          gapText.length < _noiseGapChars && !chapterRegex.hasMatch(gapText);
      if (isNoise) continue;
    }
    kept.add(reelMatches[i]);
  }
  return kept;
}

List<ReelParse> parseNovel(String text, {String? chapterReg}) {
  final chapterRegex = _resolveChapterRegex(chapterReg);
  final reelMatches = _dropDecorativeReelHeadings(
    text,
    _reelRegex.allMatches(text).toList(),
    chapterRegex,
  );

  // 没有卷结构
  if (reelMatches.isEmpty) {
    var chapters = _parseChaptersIn(text, chapterRegex);
    if (chapters.isEmpty && text.trim().isNotEmpty) {
      chapters = [ParsedChapter(index: 1, chapter: '', text: text.trim())];
    }
    chapters.sort((a, b) => a.index - b.index);
    return [ReelParse(index: 1, reel: '正文卷', chapters: chapters)];
  }

  // 有卷结构，但第一个"第X卷"标记之前可能还有楔子/前几章正文（很多小说是
  // "楔子 + 若干章" 写在最前面，后面才分卷）。这段内容不属于任何卷，之前会
  // 被整段丢弃；这里单独解析出来，排在最前面（用负数卷号确保排序在所有正式
  // 卷之前，不跟循环里按 reelName 建的 map 混用，避免卷名恰好也是空字符串
  // 时互相冲突）。
  ReelParse? leadingReel;
  final leadingText = text.substring(0, reelMatches.first.start);
  var leadingChapters = _parseChaptersIn(leadingText, chapterRegex);
  if (leadingChapters.isEmpty && leadingText.trim().isNotEmpty) {
    leadingChapters = [
      ParsedChapter(index: 1, chapter: '', text: leadingText.trim()),
    ];
  }
  if (leadingChapters.isNotEmpty) {
    leadingChapters.sort((a, b) => a.index - b.index);
    leadingReel = ReelParse(index: -1, reel: '', chapters: leadingChapters);
  }

  final reelMap = <String, ReelParse>{};
  for (var i = 0; i < reelMatches.length; i++) {
    final match = reelMatches[i];
    final reelRaw = match.group(1)!;
    final reelName = _stripLeadingSeparator((match.group(2) ?? '').trim());
    final end =
        i + 1 < reelMatches.length ? reelMatches[i + 1].start : text.length;
    final reelSection = text.substring(match.start, end);
    // 章节解析从卷标题这一行之后开始算，不然"第一卷：XX"这行本身会被
    // _parseChaptersIn 的"首章前置内容"兜底逻辑误当成一段空标题的正文。
    final chapterSection = text.substring(match.end, end);

    var chapters = _parseChaptersIn(chapterSection, chapterRegex);
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
  final result = [
    if (leadingReel != null) leadingReel,
    ...reelMap.values,
  ]..sort((a, b) => a.index - b.index);
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
