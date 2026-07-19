import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automated tests contain no opt-in real video generation harness', () {
    const removedHarness = 'test/preflight/p0_live_preflight_test.dart';
    expect(File(removedHarness).existsSync(), isFalse,
        reason: '真实 Seedance 预检只能由用户最终手动执行，不能留在自动化测试树中');

    final files = Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) =>
            file.path.endsWith('_test.dart') &&
            file.path != 'test/preflight/video_safety_boundary_test.dart');
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('P0_LIVE')),
          reason: '${file.path} 不能通过环境变量解锁真实视频生成');
      expect(source, isNot(contains('P0_PHASE')),
          reason: '${file.path} 不能保留真实视频预检阶段开关');
    }
  });
}
