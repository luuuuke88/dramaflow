// 事件模块：契约照抄 ToonFlow /api/novel/event/*。
// 逐章事件文本 = CleanNovel 语义（工作池并发、stripThink、eventState 0/1/-1）；
// 与 ToonFlow 的偏差（已记录）：ToonFlow 后端无人写 o_event/o_eventChapter（事件列表页
// 读空表），DramaFlow 在逐章成功时解析管道格式落表，让事件页真正可用。
import 'dart:math';

import 'package:dio/dio.dart';
import 'engine.dart';
import 'errors.dart';
import 'queue.dart';

class EventRow {
  final int id;
  final String? name;
  final String? detail;
  final int? createTime;
  final List<int> chapters;

  const EventRow({
    required this.id,
    required this.name,
    required this.detail,
    required this.createTime,
    required this.chapters,
  });
}

/// 剥离思维链（`<think>…</think>` 与 `<reasoning>…</reasoning>`），对应 ToonFlow stripThink。
String stripThink(String text) => text
    .replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '')
    .replaceAll(RegExp(r'<reasoning>[\s\S]*?</reasoning>'), '')
    .trim();

String _ph(List<int> ids) => List.filled(ids.length, '?').join(',');

extension EventsApi on Engine {
  /// boot 时挂载：事件任务执行器 + 冷启动恢复 + 章节导入自动触发（addNovel→CleanNovel 语义）。
  void installNovelEventPipeline() {
    taskRunners['event_generation'] = _runEventGeneration;
    queue.registerRecover('event_generation', _recoverEventGeneration);
    onNovelsAdded = (projectId, novelIds) => generateEvents(projectId, novelIds);
  }

  /// 目标章置 0/清空 → 入队 event_generation。返回任务 id（无目标章返回 0）。
  int generateEvents(
    int projectId,
    List<int> novelIds, {
    int? concurrentCount,
  }) {
    if (novelIds.isEmpty) return 0;
    // 并发批量大小对齐 ToonFlow assetsBatchGenereateSize（未显式指定时取其他设置值）。
    final c = (concurrentCount ?? config.intOf('assetsBatchGenereateSize'))
        .clamp(1, 16);
    db.execute(
      'UPDATE o_novel SET eventState=0, event=NULL, errorReason=NULL '
      'WHERE projectId=? AND id IN (${_ph(novelIds)})',
      [projectId, ...novelIds],
    );
    return queue.enqueue(
      projectId: projectId,
      taskClass: 'event_generation',
      relatedObjects: {
        'kind': 'novel',
        'ids': novelIds,
        'concurrentCount': c,
      },
    );
  }

  Future<void> _runEventGeneration(TasksRow task, CancelToken token) async {
    final related = task.relatedObjectsJson;
    final ids = (related['ids'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final concurrent =
        ((related['concurrentCount'] as num?)?.toInt() ?? 5).clamp(1, 16);
    final system = await getPrompt('eventExtraction');

    var successCount = 0;
    EngineException? firstFailure;
    var cursor = 0;

    Future<void> worker() async {
      while (!token.isCancelled) {
        final i = cursor++;
        if (i >= ids.length) return;
        final id = ids[i];
        final rows = db.select('SELECT * FROM o_novel WHERE id=?', [id]);
        if (rows.isEmpty) continue;
        final row = rows.first;
        try {
          // 用户消息模板逐字照抄 cleanNovel.processChapter
          final user = '请根据以下小说章节数：${row['chapterIndex']}'
              '小说章节券：${row['reel'] ?? ''}'
              '小说章节名称：${row['chapter'] ?? ''}'
              '、小说章节内容生成事件摘要：\n${row['chapterData'] ?? ''}';
          final res = await gateway.generateText(
            system,
            user,
            stage: 'event_extract',
            cancelToken: token,
          );
          final event = stripThink(res.content);
          if (event.isEmpty) {
            throw const EngineException(errLlmFormat, {'reason': 'empty'});
          }
          db.execute(
            'UPDATE o_novel SET event=?, eventState=1, errorReason=NULL '
            'WHERE id=?',
            [event, id],
          );
          _replaceChapterEvent(id, event);
          successCount++;
        } catch (e) {
          if (token.isCancelled) return;
          final ex = e is EngineException
              ? e
              : (e is DioException
                  ? EngineException(errNetwork, {'message': e.message})
                  : EngineException(errLlmFormat, {'message': '$e'}));
          firstFailure ??= ex;
          db.execute(
            'UPDATE o_novel SET eventState=-1, errorReason=? WHERE id=?',
            [ex.toReasonJson(), id],
          );
        }
      }
    }

    await Future.wait(
      [for (var w = 0; w < min(concurrent, ids.length); w++) worker()],
    );
    if (token.isCancelled) {
      throw const EngineException(errCanceled);
    }
    // 单章失败不失败整个任务（行内 errorReason 可见可重试）；全军覆没才判任务失败。
    if (successCount == 0 && firstFailure != null) {
      throw firstFailure!;
    }
  }

  void _recoverEventGeneration(TasksRow task) {
    final ids = (task.relatedObjectsJson['ids'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    if (ids.isEmpty) return;
    db.execute(
      'UPDATE o_novel SET eventState=-1, errorReason=? '
      'WHERE id IN (${_ph(ids)}) AND eventState=0',
      [const EngineException(errAppRestart).toReasonJson(), ...ids],
    );
  }

  /// 重写该章的事件行：删旧关联+清孤儿，再落新事件（name=管道首字段，detail=整行）。
  void _replaceChapterEvent(int novelId, String eventLine) {
    final oldIds = db
        .select(
          'SELECT DISTINCT eventId FROM o_eventChapter WHERE novelId=?',
          [novelId],
        )
        .map((r) => r['eventId'] as int?)
        .whereType<int>()
        .toList();
    db.execute('DELETE FROM o_eventChapter WHERE novelId=?', [novelId]);
    if (oldIds.isNotEmpty) {
      db.execute(
        'DELETE FROM o_event WHERE id IN (${_ph(oldIds)}) AND id NOT IN '
        '(SELECT DISTINCT eventId FROM o_eventChapter WHERE eventId IS NOT NULL)',
        oldIds,
      );
    }
    final fields = eventLine
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final name = fields.isNotEmpty
        ? fields.first
        : eventLine.substring(0, min(40, eventLine.length));
    db.execute(
      'INSERT INTO o_event (name,detail,createTime) VALUES (?,?,?)',
      [name, eventLine, DateTime.now().millisecondsSinceEpoch],
    );
    db.execute(
      'INSERT INTO o_eventChapter (eventId,novelId) VALUES (?,?)',
      [db.lastInsertRowId, novelId],
    );
  }

  /// 事件列表：JOIN 语义照抄 getEvent（GROUP_CONCAT 章节号 → chapters 数组）。
  ({List<EventRow> list, int total}) events(
    int projectId, {
    int page = 1,
    int limit = 10,
    String? search,
  }) {
    final where = StringBuffer('n.projectId=?');
    final args = <Object?>[projectId];
    if (search != null && search.trim().isNotEmpty) {
      where.write(' AND e.name LIKE ?');
      args.add('%${search.trim()}%');
    }
    const joins = 'FROM o_event e '
        'JOIN o_eventChapter ec ON ec.eventId=e.id '
        'JOIN o_novel n ON n.id=ec.novelId ';
    final total = db
        .select(
          'SELECT COUNT(*) n FROM '
          '(SELECT e.id $joins WHERE $where GROUP BY e.id)',
          args,
        )
        .first['n'] as int;
    final rows = db.select(
      'SELECT e.id id, e.name name, e.detail detail, e.createTime createTime, '
      "GROUP_CONCAT(n.chapterIndex) chapterIndexes $joins "
      'WHERE $where GROUP BY e.id ORDER BY e.id LIMIT ? OFFSET ?',
      [...args, limit, (page - 1) * limit],
    );
    return (
      list: rows
          .map((r) => EventRow(
                id: r['id'] as int,
                name: r['name'] as String?,
                detail: r['detail'] as String?,
                createTime: r['createTime'] as int?,
                chapters: ((r['chapterIndexes'] as String?) ?? '')
                    .split(',')
                    .where((s) => s.isNotEmpty)
                    .map(int.parse)
                    .toList()
                  ..sort(),
              ))
          .toList(),
      total: total,
    );
  }

  void deleteEvents(List<int> ids) {
    if (ids.isEmpty) return;
    db.execute('DELETE FROM o_event WHERE id IN (${_ph(ids)})', ids);
    db.execute('DELETE FROM o_eventChapter WHERE eventId IN (${_ph(ids)})', ids);
  }

  /// 事件状态轮询语义（eventState!=0），供工具/E2E 使用；UI 走队列事件流。
  List<({int id, String? event, int eventState, String? errorReason})>
      novelEventState(List<int> ids) {
    if (ids.isEmpty) return const [];
    return db
        .select(
          'SELECT id,event,eventState,errorReason FROM o_novel '
          'WHERE id IN (${_ph(ids)}) AND eventState!=0',
          ids,
        )
        .map((r) => (
              id: r['id'] as int,
              event: r['event'] as String?,
              eventState: (r['eventState'] as int?) ?? 0,
              errorReason: r['errorReason'] as String?,
            ))
        .toList();
  }

  /// 事件分析：汇总各章事件行交 LLM，返回按章 JSON 文本
  ///（ToonFlow 前端有此入口但后端缺失，此处补齐为真实实现）。
  Future<String> eventAnalysis(int projectId, List<int> novelIds) async {
    if (novelIds.isEmpty) {
      throw const EngineException(errNoChapters);
    }
    final rows = db.select(
      'SELECT chapterIndex,chapter,event FROM o_novel '
      'WHERE projectId=? AND id IN (${_ph(novelIds)}) AND event IS NOT NULL '
      'ORDER BY chapterIndex ASC',
      [projectId, ...novelIds],
    );
    if (rows.isEmpty) {
      throw const EngineException(errNoChapters);
    }
    final system = await getPrompt('eventAnalysis');
    final user = [
      for (final r in rows) '第${r['chapterIndex']}章 ${r['chapter']}：${r['event']}',
    ].join('\n');
    final res = await gateway.generateText(
      system,
      user,
      stage: 'event_extract',
    );
    return stripThink(res.content);
  }
}
