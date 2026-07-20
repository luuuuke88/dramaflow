import 'package:dramaflow/src/widgets/external_link_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('只把带主机名的 http 与 https 地址识别为外部链接', () {
    final parts = parseExternalLinkText(
      '文档见 [安全页面](https://example.com/docs)，不要打开 '
      'javascript:alert(1) 或 https://。',
    );

    expect(parts.whereType<ExternalLinkPart>(), hasLength(1));
    final link = parts.whereType<ExternalLinkPart>().single;
    expect(link.label, '安全页面');
    expect(link.uri, Uri.parse('https://example.com/docs'));
  });

  testWidgets('裸 https 地址点击后交由传入的外部打开器处理', (tester) async {
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExternalLinkText(
            text: 'https://example.com/guide',
            openExternal: (uri) async {
              opened = uri;
              return true;
            },
          ),
        ),
      ),
    );

    await tester.tap(
      find.text('https://example.com/guide', findRichText: true),
    );
    await tester.pump();

    expect(opened, Uri.parse('https://example.com/guide'));
  });
}
