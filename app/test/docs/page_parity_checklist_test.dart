import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ToonFlow page parity checklist covers every v0.3 page', () {
    final file = File(
      '../docs/superpowers/progress/2026-07-04-page-parity-checklist.md',
    );
    expect(file.existsSync(), isTrue);

    final text = file.readAsStringSync();
    final requiredSections = <String>[
      '项目列表 + 新建向导',
      '章节管理 + 事件',
      '剧本',
      '素材库',
      '制作画布',
      '节点式图片编辑器',
      '多轨工作台',
      '配音',
      '任务中心',
      'Agent 体系页',
      '全套设置',
    ];

    for (final section in requiredSections) {
      expect(text, contains('## $section'), reason: section);
      final start = text.indexOf('## $section');
      final next = text.indexOf('\n## ', start + 1);
      final block = text.substring(start, next == -1 ? text.length : next);
      expect(block, contains('Status:'), reason: '$section status');
      expect(block, contains('Desktop Evidence:'), reason: '$section desktop');
      expect(block, contains('Mobile Evidence:'), reason: '$section mobile');
      expect(block, contains('Known Gaps:'), reason: '$section gaps');
      expect(block, contains('Next Verification:'),
          reason: '$section next verification');
    }
  });
}
