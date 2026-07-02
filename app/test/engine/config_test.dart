import 'package:flutter_test/flutter_test.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/config.dart';

void main() {
  test('桌面默认 azt，移动默认 ark 且 key 空', () {
    final d = EngineConfig(openEngineDb(':memory:'), isMobile: false);
    expect(d.str('textBaseUrl'), contains('127.0.0.1:8787'));
    expect(d.str('textModel'), 'gpt-5.5');
    final m = EngineConfig(openEngineDb(':memory:'), isMobile: true);
    expect(m.str('textBaseUrl'), contains('ark.cn-beijing'));
    expect(m.str('textApiKey'), isEmpty);
    expect(m.str('imageModel'), contains('seedream'));
  });

  test('打码与不修改语义', () {
    final c = EngineConfig(openEngineDb(':memory:'), isMobile: false);
    c.update({'videoApiKey': 'sk-realkey1234'});
    expect(c.getAllMasked()['videoApiKey'], '****1234');
    c.update({'videoApiKey': '****1234'});
    expect(c.str('videoApiKey'), 'sk-realkey1234');
    c.update({'videoApiKey': ''});
    expect(c.str('videoApiKey'), 'sk-realkey1234');
  });

  test('videoDuration 数值', () {
    final c = EngineConfig(openEngineDb(':memory:'), isMobile: false);
    c.update({'videoDuration': 8});
    expect(c.intOf('videoDuration'), 8);
  });

  test('未知键忽略，已知键持久化', () {
    final db = openEngineDb(':memory:');
    final c = EngineConfig(db, isMobile: false);
    c.update({'bogusKey': 'x', 'textModel': 'gpt-5.4'});
    expect(c.str('textModel'), 'gpt-5.4');
    final again = EngineConfig(db, isMobile: false);
    expect(again.str('textModel'), 'gpt-5.4');
  });
}
