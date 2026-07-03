import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/novel_parse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('无卷结构：两章拆分，章名与内容正确', () {
    final reels = parseNovel('第一章 起\n内容A\n第二章 承\n内容B');
    expect(reels, hasLength(1));
    expect(reels.first.reel, '正文卷');
    final chapters = reels.first.chapters;
    expect(chapters, hasLength(2));
    expect(chapters[0].index, 1);
    expect(chapters[0].chapter, '起');
    expect(chapters[0].text, '内容A');
    expect(chapters[1].index, 2);
    expect(chapters[1].chapter, '承');
    expect(chapters[1].text, '内容B');
  });

  test('有卷结构：章节归属各卷且卷名正确', () {
    final reels = parseNovel(
      '第一卷 风起\n第一章 甲\n内容1\n第二卷 云涌\n第二章 乙\n内容2',
    );
    expect(reels, hasLength(2));
    expect(reels[0].reel, '风起');
    expect(reels[0].chapters.single.chapter, '甲');
    expect(reels[0].chapters.single.text, '内容1');
    expect(reels[1].reel, '云涌');
    expect(reels[1].chapters.single.index, 2);
    expect(reels[1].chapters.single.text, '内容2');
  });

  test('中文数字章节号解析（第十三章 → 13）', () {
    final reels = parseNovel('第十三章 试炼\n正文内容');
    expect(reels.single.chapters.single.index, 13);
    expect(parseChineseNumber('十'), 10);
    expect(parseChineseNumber('十三'), 13);
    expect(parseChineseNumber('二十一'), 21);
    expect(parseChineseNumber('一百零五'), 105);
  });

  test('无章节标记：全文作为单章', () {
    final reels = parseNovel('就是一段没有章节标记的文字。');
    final chapter = reels.single.chapters.single;
    expect(chapter.index, 1);
    expect(chapter.chapter, '');
    expect(chapter.text, '就是一段没有章节标记的文字。');
  });

  test('自定义分章正则（/pattern/flags 写法）生效', () {
    final reels = parseNovel(
      'CH1 alpha\nbody1\nCH2 beta\nbody2',
      chapterReg: r'/CH(\d+)\s*([^\n]*)/g',
    );
    final chapters = reels.single.chapters;
    expect(chapters, hasLength(2));
    expect(chapters[0].chapter, 'alpha');
    expect(chapters[0].text, 'body1');
    expect(chapters[1].index, 2);
  });

  test('非法自定义正则抛 errRegexInvalid', () {
    expect(
      () => parseNovel('文本', chapterReg: '/[unclosed/g'),
      throwsA(
        isA<EngineException>().having((e) => e.errKey, 'errKey', errRegexInvalid),
      ),
    );
  });

  test('flattenParsedNovel 拍平保留卷名', () {
    final flat = flattenParsedNovel(
      parseNovel('第一卷 风起\n第一章 甲\n内容1'),
    );
    expect(flat.single.reel, '风起');
    expect(flat.single.chapter, '甲');
    expect(flat.single.chapterData, '内容1');
  });

  test('docx 提取段落文本', () {
    const doc = '<?xml version="1.0" encoding="UTF-8"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>'
        '<w:p><w:r><w:t>第一章 起</w:t></w:r></w:p>'
        '<w:p><w:r><w:t xml:space="preserve">内容 &amp; 转义</w:t></w:r></w:p>'
        '</w:body></w:document>';
    final archive = Archive()
      ..addFile(ArchiveFile('word/document.xml', utf8.encode(doc).length,
          utf8.encode(doc)));
    final bytes = ZipEncoder().encode(archive);
    expect(extractDocxText(bytes), '第一章 起\n内容 & 转义');
  });

  test('坏文件抛 errFileType', () {
    expect(
      () => extractDocxText([1, 2, 3]),
      throwsA(
        isA<EngineException>().having((e) => e.errKey, 'errKey', errFileType),
      ),
    );
  });
}
