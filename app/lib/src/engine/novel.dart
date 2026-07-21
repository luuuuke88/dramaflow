// 章节模块：契约照抄 ToonFlow /api/novel/*（getNovel/addNovel/updateNovel/delNovel/
// batchDeleteNovel/getNovelIndex）。eventState：0=生成中 1=成功 -1=失败。
import 'package:sqlite3/sqlite3.dart';

import 'engine.dart';
import 'event_cleanup.dart';
import 'novel_parse.dart';

String _ph(List<int> ids) => List.filled(ids.length, '?').join(',');

class NovelRow {
  final int id;
  final int projectId;
  final int chapterIndex;
  final String? reel;
  final String? chapter;
  final String? chapterData;
  final String? event;
  final int? eventState;
  final String? errorReason;
  final int? createTime;

  const NovelRow({
    required this.id,
    required this.projectId,
    required this.chapterIndex,
    required this.reel,
    required this.chapter,
    required this.chapterData,
    required this.event,
    required this.eventState,
    required this.errorReason,
    required this.createTime,
  });

  factory NovelRow.fromRow(Row row) => NovelRow(
        id: row['id'] as int,
        projectId: row['projectId'] as int,
        chapterIndex: (row['chapterIndex'] as int?) ?? 0,
        reel: row['reel'] as String?,
        chapter: row['chapter'] as String?,
        chapterData: row['chapterData'] as String?,
        event: row['event'] as String?,
        eventState: row['eventState'] as int?,
        errorReason: row['errorReason'] as String?,
        createTime: row['createTime'] as int?,
      );
}

extension NovelApi on Engine {
  ({List<NovelRow> data, int total}) novels(
    int projectId, {
    int page = 1,
    int limit = 10,
    String? search,
  }) {
    final where = StringBuffer('projectId=?');
    final args = <Object?>[projectId];
    if (search != null && search.trim().isNotEmpty) {
      where.write(' AND chapter LIKE ?');
      args.add('%${search.trim()}%');
    }
    final total = db
        .select('SELECT COUNT(*) n FROM o_novel WHERE $where', args)
        .first['n'] as int;
    final rows = db.select(
      'SELECT * FROM o_novel WHERE $where ORDER BY chapterIndex ASC '
      'LIMIT ? OFFSET ?',
      [...args, limit, (page - 1) * limit],
    );
    return (data: rows.map(NovelRow.fromRow).toList(), total: total);
  }

  /// 导入章节：chapterIndex 从项目现有最大值续排，eventState=0，完成后触发
  /// onNovelsAdded（T6 注入事件生成）。返回新增行 id 列表。
  List<int> addNovels(int projectId, List<ChapterItem> items) {
    if (items.isEmpty) return const [];
    final base = db.select(
      'SELECT COALESCE(MAX(chapterIndex),0) m FROM o_novel WHERE projectId=?',
      [projectId],
    ).first['m'] as int;
    final now = DateTime.now().millisecondsSinceEpoch;
    final ids = <int>[];
    var idx = base;
    for (final item in items) {
      idx += 1;
      db.execute(
        'INSERT INTO o_novel '
        '(projectId,chapterIndex,reel,chapter,chapterData,createTime,eventState) '
        'VALUES (?,?,?,?,?,?,0)',
        [projectId, idx, item.reel, item.chapter, item.chapterData, now],
      );
      ids.add(db.lastInsertRowId);
    }
    onNovelsAdded?.call(projectId, ids);
    return ids;
  }

  void updateNovel(
    int id, {
    int? index,
    String? reel,
    String? chapter,
    String? chapterData,
    String? event,
  }) {
    final sets = <String>[];
    final args = <Object?>[];
    void set(String column, Object? value) {
      if (value == null) return;
      sets.add('$column=?');
      args.add(value);
    }

    set('chapterIndex', index);
    set('reel', reel);
    set('chapter', chapter);
    set('chapterData', chapterData);
    set('event', event);
    if (sets.isEmpty) return;
    args.add(id);
    db.execute('UPDATE o_novel SET ${sets.join(',')} WHERE id=?', args);
  }

  /// 删除章节：先解除事件关联，再清孤儿事件（照抄 delNovel 级联语义）。
  void deleteNovels(List<int> ids) {
    if (ids.isEmpty) return;
    clearNovelEventLinks(db, ids);
    db.execute('DELETE FROM o_novel WHERE id IN (${_ph(ids)})', ids);
  }

  /// 选中章节里正在生成事件（eventState=0）的 id 子集。
  ///
  /// 事件生成 worker（events.dart 的 _runEventGeneration/_replaceChapterEvent）
  /// 在网络请求期间持有 novelId；若这期间该章节被删除，worker 返回后仍会照常对
  /// 已删除的 novelId 插入新事件行，产生 events() 的 INNER JOIN 永远查不到、也无法
  /// 通过 UI 删除的孤儿事件行。批量删除等操作应先用这个方法排除生成中的行。
  List<int> generatingNovelIds(List<int> ids) {
    if (ids.isEmpty) return const [];
    return db
        .select(
          'SELECT id FROM o_novel WHERE id IN (${_ph(ids)}) AND eventState=0',
          ids,
        )
        .map((row) => row['id'] as int)
        .toList();
  }

  List<({int id, int index, String chapter})> novelIndex(int projectId) => db
      .select(
        'SELECT id,chapterIndex,chapter FROM o_novel WHERE projectId=? '
        'ORDER BY chapterIndex ASC',
        [projectId],
      )
      .map((row) => (
            id: row['id'] as int,
            index: (row['chapterIndex'] as int?) ?? 0,
            chapter: (row['chapter'] as String?) ?? '',
          ))
      .toList();
}
