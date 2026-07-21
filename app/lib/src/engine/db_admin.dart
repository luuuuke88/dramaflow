// 存储管理（P?/审计补齐）：数据库信息 + 清空数据。
// dbInfo() 列出所有业务表及其行数，供设置页"数据库信息"面板展示。
// clearAllData() 清空全部内容数据（项目/章节/剧本/资产/分镜/视频/任务/记忆），
// 并保留供应商、密钥、模型、绑定、提示词、外观/语言等用户配置（o_setting / o_secret /
// o_vendorConfig / o_prompt / o_user / o_artStyle），使应用清空后仍可直接继续使用。
// 同时清空媒体根目录下的项目媒体文件。清空在单个事务内完成，失败回滚。
//
// clearTable(table) 清空用户在设置页单独选中的一张内容表。历史上 deleteScripts/
// deleteAssets/deleteNovels/deleteProject 都曾因为"只删自己这张表、不清子孙表/磁盘
// 文件"产生孤儿数据或磁盘泄漏而各自修过一次（见各文件注释）；clearTable 曾经是同一类
// bug 的最后一个漏网之鱼——裸 `DELETE FROM "$table"`，不做任何级联。
// 现在按下游依赖分两类处理：
//   1. 有子孙表或磁盘文件的表：复用已经写好级联逻辑的 deleteXxx(ids)（先查出该表全部
//      主键 id，再调用对应函数），不在这里重新发明级联删除。
//   2. 真正的叶子表/纯连接表（没有任何表引用它的主键、也不持有磁盘文件）：保留裸
//      DELETE，这类表清空不会产生孤儿引用。
// 例外是 o_imageFlow：它持有的磁盘文件（画布节点里的上传图/生成图/蒙版）以任意结构
// 内嵌在 flowData 的 JSON 里，没有现成级联函数可用，解析这段 JSON 做级联清理的风险与
// 收益不成比例，因此仍保留裸 DELETE，并通过 [nonCascadingClearTables]/
// [tableClearCascades] 让设置页在确认弹窗里对这张表给出诚实提示。
import 'dart:io';

import 'package:path/path.dart' as p;

import 'assets.dart' show AssetsApi;
import 'engine.dart';
import 'errors.dart';
import 'events.dart' show EventsApi;
import 'novel.dart' show NovelApi;
import 'scripts.dart' show ScriptsApi;
import 'storyboard.dart' show StoryboardApi;
import 'timeline_clip.dart' show TimelineClipApi;
import 'video_track.dart' show VideoTrackApi;

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

  /// clearTable 里没有接入级联清理的表：只会裸删除该表自身，可能残留指向它的孤儿
  /// 引用或磁盘文件（原因见文件头注释）。settings_screen 据此在确认弹窗里追加提示。
  static const nonCascadingClearTables = {'o_imageFlow'};

  /// 该表清空时是否已接入完整级联删除（子孙表 + 磁盘文件）。供设置页决定要不要在
  /// 清空确认弹窗里追加"可能产生孤儿记录/磁盘泄漏"的诚实提示。
  bool tableClearCascades(String table) =>
      !nonCascadingClearTables.contains(table);

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

  /// 表名必须来自 schema 内建表（clearTable 调用前已校验过白名单），可以安全地拼进
  /// 列名固定的 `SELECT id FROM "$table"`；主键值本身走参数绑定的地方各自处理。
  List<int> _allIds(String table) => db
      .select('SELECT id FROM "$table"')
      .map((row) => row['id'] as int)
      .toList();

  /// 清空一张用户选定的内容表。表名必须来自 [clearableDbTables]，避免任意 SQL 或
  /// 配置/凭证误删。有下游子孙表/磁盘文件的表复用既有级联删除函数（见文件头注释），
  /// 真正的叶子表/纯连接表走裸 DELETE。完成后通知任务与数据观察者刷新。
  void clearTable(String table) {
    final allowed = clearableDbTables().map((info) => info.table).toSet();
    if (!allowed.contains(table)) {
      throw const EngineException(errDbTableClearForbidden);
    }

    switch (table) {
      case 'o_project':
        // deleteProject 一次只接受一个 id，且各自内部已有事务；逐个调用即可，
        // 不能在外层再包一层 BEGIN（deleteProject 内部会再次 BEGIN，SQLite 不支持
        // 事务嵌套）。
        for (final id in _allIds(table)) {
          deleteProject(id);
        }
        break;
      case 'o_novel':
        deleteNovels(_allIds(table));
        break;
      case 'o_script':
        deleteScripts(_allIds(table));
        break;
      case 'o_assets':
        deleteAssets(_allIds(table));
        break;
      case 'o_storyboard':
        deleteStoryboards(_allIds(table));
        break;
      case 'o_video':
        for (final id in _allIds(table)) {
          deleteVideo(id);
        }
        break;
      case 'o_videoTrack':
        for (final id in _allIds(table)) {
          deleteVideoTrack(id);
        }
        break;
      case 'o_event':
        deleteEvents(_allIds(table));
        break;
      case 'o_timelineClip':
        deleteTimelineClips(_allIds(table));
        break;
      case 'o_tasks':
        _clearTasks();
        break;
      case 'o_image':
        _clearImages();
        break;
      default:
        // 叶子表/纯连接表：memories（o_memoryVector 靠 schema 里的
        // ON DELETE CASCADE 外键自动清理）、o_agentWorkData、o_assets2Storyboard、
        // o_assetsRole2Audio、o_eventChapter、o_memoryVector、
        // o_productionDependencyState、o_scriptAssets ——
        // 没有任何表引用它们的主键，也不持有磁盘文件，裸删除不会产生孤儿。
        // 例外 o_imageFlow 见文件头注释与 nonCascadingClearTables。
        db.execute('BEGIN');
        try {
          db.execute('DELETE FROM "$table"');
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
        break;
    }
    queue.notifyChanged();
  }

  /// o_tasks 自身没有下游数据表，但每个任务可能在 task_payloads/ 下有一份私有载荷
  /// 文件（写入见 writeTaskPrivatePayload），裸 DELETE 会泄漏这些文件。顺序照抄
  /// deleteProject：先删数据库行，再逐个删对应的载荷文件。
  void _clearTasks() {
    final ids = _allIds('o_tasks');
    db.execute('DELETE FROM o_tasks');
    for (final id in ids) {
      deleteTaskPrivatePayload(id);
    }
  }

  /// o_image 被 o_assets.imageId 反向引用，且持有磁盘图片文件；裸 DELETE 会让
  /// o_assets 里留下指向已删行的 imageId（孤儿引用），并泄漏磁盘文件。顺序对齐
  /// deleteProject：数据库改动在事务内完成，事务提交后再删磁盘文件。
  void _clearImages() {
    final paths = db
        .select('SELECT filePath FROM o_image WHERE filePath IS NOT NULL')
        .map((row) => row['filePath'] as String)
        .toList();
    db.execute('BEGIN');
    try {
      db.execute('UPDATE o_assets SET imageId=NULL WHERE imageId IS NOT NULL');
      db.execute('DELETE FROM o_image');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    for (final rel in paths) {
      final file = File(media.absPath(rel));
      if (file.existsSync()) file.deleteSync();
    }
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
