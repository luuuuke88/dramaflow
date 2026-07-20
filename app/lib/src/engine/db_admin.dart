// 存储管理（P?/审计补齐）：数据库信息 + 清空数据。
// dbInfo() 列出所有业务表及其行数，供设置页"数据库信息"面板展示。
// clearAllData() 清空全部内容数据（项目/章节/剧本/资产/分镜/视频/任务/记忆），
// 并保留供应商、密钥、模型、绑定、提示词、外观/语言等用户配置（o_setting / o_secret /
// o_vendorConfig / o_prompt / o_user / o_artStyle），使应用清空后仍可直接继续使用。
// 同时清空媒体根目录下的项目媒体文件。清空在单个事务内完成，失败回滚。
import 'dart:io';

import 'package:path/path.dart' as p;

import 'engine.dart';
import 'errors.dart';

/// 单张数据表的行数统计。
class DbTableInfo {
  final String table;
  final int rowCount;

  const DbTableInfo(this.table, this.rowCount);
}

extension DbAdminApi on Engine {
  /// 清空数据时保留的用户配置表（供应商/密钥/模型/绑定/提示词/外观/语言/用户/画风）。
  static const _preservedTables = {
    'o_setting',
    'o_secret',
    'o_vendorConfig',
    'o_prompt',
    'o_modelPrompt',
    'o_modelPromptTemplate',
    'o_agentDeploy',
    'o_user',
    'o_artStyle',
    'o_skillList',
    'o_skillAttribution',
    'sqlite_sequence',
  };

  /// 列出数据库内所有表及其当前行数（按表名排序），供"数据库信息"面板展示。
  List<DbTableInfo> dbInfo() {
    final tables = db
        .select(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .map((row) => row['name'] as String)
        .toList();
    return [
      for (final table in tables)
        DbTableInfo(
          table,
          db.select('SELECT COUNT(*) n FROM "$table"').first['n'] as int,
        ),
    ];
  }

  /// 可由用户单独清空的内容表。供应商、凭证、模型绑定和编辑配置始终不在此列表中。
  List<DbTableInfo> clearableDbTables() => [
        for (final info in dbInfo())
          if (!_preservedTables.contains(info.table)) info,
      ];

  /// 清空一张用户选定的内容表。表名必须来自 [clearableDbTables]，避免任意 SQL 或
  /// 配置/凭证误删；完成后通知任务与数据观察者刷新。
  void clearTable(String table) {
    final allowed = clearableDbTables().map((info) => info.table).toSet();
    if (!allowed.contains(table)) {
      throw const EngineException(errDbTableClearForbidden);
    }

    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM "$table"');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    queue.notifyChanged();
  }

  /// 清空全部内容数据并删除媒体文件，保留用户配置。清空在事务内完成，失败回滚。
  void clearAllData() {
    final tables = db
        .select(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .map((row) => row['name'] as String)
        .where((name) => !_preservedTables.contains(name))
        .toList();

    db.execute('BEGIN');
    try {
      for (final table in tables) {
        db.execute('DELETE FROM "$table"');
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }

    // 媒体：清空根目录下所有项目子目录（保留根目录本身）。
    final root = Directory(media.rootDir);
    if (root.existsSync()) {
      for (final entry in root.listSync()) {
        try {
          entry.deleteSync(recursive: true);
        } catch (_) {
          // 单个文件删除失败不阻断整体清空。
        }
      }
    }

    queue.notifyChanged();
  }

  /// 数据目录绝对路径（媒体根目录的父目录，即 boot 时的 dataDir）。
  String dataDirPath() => p.dirname(media.rootDir);
}
