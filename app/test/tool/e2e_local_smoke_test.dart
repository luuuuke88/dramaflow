import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/e2e_local_smoke.dart' as smoke;

void main() {
  test('离线主链 smoke 串起章节、剧本、分镜、候选、配音与合成', () async {
    final dir = Directory.systemTemp.createTempSync('df-local-smoke-test-');
    try {
      final result = await smoke.runOfflinePipelineSmoke(dataDir: dir.path);

      expect(result.projectName, '离线主链冒烟');
      expect(result.chapterCount, 2);
      expect(result.scriptCount, 1);
      expect(result.storyboardCount, 2);
      expect(result.selectedVideoCount, 2);
      expect(result.boundShotAudioCount, 1);
      expect(result.composeSegmentCount, 2);
      expect(File(result.outputAbsPath).existsSync(), isTrue);
    } finally {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });
}
