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

  test('旧通用 API Key 设置不再写入 SQLite', () {
    final c = EngineConfig(openEngineDb(':memory:'), isMobile: false);
    c.update({'videoApiKey': 'sk-realkey1234'});
    expect(c.str('videoApiKey'), isEmpty);
    expect(c.getAllMasked(), isNot(contains('videoApiKey')));
  });

  test('videoDuration 数值', () {
    final c = EngineConfig(openEngineDb(':memory:'), isMobile: false);
    c.update({'videoDuration': 8});
    expect(c.intOf('videoDuration'), 8);
  });

  test('themeMode 默认浅色且持久化', () {
    final db = openEngineDb(':memory:');
    final c = EngineConfig(db, isMobile: false);
    expect(c.str('themeMode'), 'light');
    c.update({'themeMode': 'dark'});
    expect(EngineConfig(db, isMobile: false).str('themeMode'), 'dark');
  });

  test('制作画布引导默认未完成且完成状态持久化', () {
    final db = openEngineDb(':memory:');
    final config = EngineConfig(db, isMobile: false);

    expect(config.str('production.guide.completed'), '0');

    config.update({'production.guide.completed': '1'});

    expect(
      EngineConfig(db, isMobile: false).str('production.guide.completed'),
      '1',
    );
  });

  test('未知键忽略，已知键持久化', () {
    final db = openEngineDb(':memory:');
    final c = EngineConfig(db, isMobile: false);
    c.update({'bogusKey': 'x', 'textModel': 'gpt-5.4'});
    expect(c.str('textModel'), 'gpt-5.4');
    final again = EngineConfig(db, isMobile: false);
    expect(again.str('textModel'), 'gpt-5.4');
  });

  test('其他设置默认值：chapterReg 空 / 集长 5000 / 批量 5', () {
    final c = EngineConfig(openEngineDb(':memory:'), isMobile: false);
    expect(c.str('chapterReg'), isEmpty);
    expect(c.intOf('scriptEpisodeLength'), 5000);
    expect(c.intOf('assetsBatchGenereateSize'), 5);
  });

  test('其他设置读写往返并持久化', () {
    final db = openEngineDb(':memory:');
    final c = EngineConfig(db, isMobile: false);
    c.update({
      'chapterReg': r'^第[0-9]+章',
      'scriptEpisodeLength': '8000',
      'assetsBatchGenereateSize': '3',
    });
    expect(c.str('chapterReg'), r'^第[0-9]+章');
    expect(c.intOf('scriptEpisodeLength'), 8000);
    expect(c.intOf('assetsBatchGenereateSize'), 3);
    // 新实例读同一 db 仍读到持久化值
    final again = EngineConfig(db, isMobile: false);
    expect(again.str('chapterReg'), r'^第[0-9]+章');
    expect(again.intOf('scriptEpisodeLength'), 8000);
    expect(again.intOf('assetsBatchGenereateSize'), 3);
  });

  test('chapterReg 可清回空串（恢复默认）', () {
    final db = openEngineDb(':memory:');
    final c = EngineConfig(db, isMobile: false);
    c.update({'chapterReg': r'^第[0-9]+章'});
    expect(c.str('chapterReg'), isNotEmpty);
    c.update({'chapterReg': ''});
    expect(c.str('chapterReg'), isEmpty);
  });
}
