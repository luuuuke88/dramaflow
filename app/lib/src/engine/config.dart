import 'package:sqlite3/sqlite3.dart';

/// 引擎设置（移植 server/src/config.ts，去掉 apiToken）。
/// 默认值按平台分化：桌面→azt(127.0.0.1)，移动→volcengine ark（Provider Reality 约定）。
class EngineConfig {
  final Database _db;
  final bool isMobile;

  static const maskedKeys = ['textApiKey', 'imageApiKey', 'videoApiKey'];

  static const _sizeDirective =
      'You MUST generate this image at exactly 1024x1024 resolution as a SQUARE 1:1 canvas. Do not add any text, watermark or border.';

  late final Map<String, String> _defaults = {
    'textBaseUrl': isMobile
        ? 'https://ark.cn-beijing.volces.com/api/v3'
        : 'http://127.0.0.1:8787/v1',
    'textApiKey': isMobile ? '' : 'local',
    'textModel': isMobile ? 'doubao-seed-1-6-250615' : 'gpt-5.5',
    'imageBaseUrl': isMobile
        ? 'https://ark.cn-beijing.volces.com/api/v3'
        : 'http://127.0.0.1:8787/v1',
    'imageApiKey': isMobile ? '' : 'local',
    'imageModel': isMobile ? 'doubao-seedream-4-0-250828' : 'gpt-image-2',
    'imageSizeDirective': _sizeDirective,
    'videoProvider': 'volcengine',
    'videoBaseUrl': 'https://ark.cn-beijing.volces.com/api/v3',
    'videoApiKey': '',
    'videoModel': 'doubao-seedance-2-0-mini-260615',
    'videoResolution': '720p',
    'videoDuration': '5',
    // 其他设置（对齐 ToonFlow otherConfig）：
    // chapterReg 空串=用 parseNovel 内置默认章节正则；scriptEpisodeLength 单集字数上限；
    // assetsBatchGenereateSize 事件/资产提取并发批量大小。
    'chapterReg': '',
    'scriptEpisodeLength': '5000',
    'assetsBatchGenereateSize': '5',
    'themeMode': 'light',
    'app.locale': '',
  };

  EngineConfig(this._db, {required this.isMobile});

  String str(String key) {
    final row = _db.select('SELECT value FROM o_setting WHERE key = ?', [key]);
    if (row.isNotEmpty) return row.first['value'] as String;
    return _defaults[key] ?? '';
  }

  int intOf(String key) => int.tryParse(str(key)) ?? 0;

  Map<String, dynamic> getAll() => {
        for (final k in _defaults.keys)
          k: k == 'videoDuration' ? intOf(k) : str(k)
      };

  Map<String, dynamic> getAllMasked() {
    final all = getAll();
    String mask(String v) =>
        v.isEmpty ? '' : '****${v.substring(v.length < 4 ? 0 : v.length - 4)}';
    for (final k in maskedKeys) {
      all[k] = mask(all[k] as String);
    }
    return all;
  }

  void update(Map<String, dynamic> patch) {
    final stmt = _db.prepare(
        'INSERT INTO o_setting (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value');
    try {
      for (final e in patch.entries) {
        if (!_defaults.containsKey(e.key) || e.value == null) continue;
        final v = e.value.toString();
        // 打码字段：空串或 **** 开头 = 不修改（v0.1 语义）
        if (maskedKeys.contains(e.key) && (v.isEmpty || v.startsWith('****'))) {
          continue;
        }
        stmt.execute([e.key, v]);
      }
    } finally {
      stmt.close();
    }
  }
}
