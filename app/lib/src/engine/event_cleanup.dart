import 'package:sqlite3/sqlite3.dart';

String _placeholders(List<int> ids) => List.filled(ids.length, '?').join(',');

/// Remove chapter-event links and only the events that become unreferenced.
///
/// Event rows can be shared by multiple chapters, so callers must remove the
/// links before deleting the novels themselves.
void clearNovelEventLinks(Database db, List<int> novelIds) {
  if (novelIds.isEmpty) return;
  final placeholders = _placeholders(novelIds);
  final eventIds = db
      .select(
        'SELECT DISTINCT eventId FROM o_eventChapter '
        'WHERE novelId IN ($placeholders)',
        novelIds,
      )
      .map((row) => row['eventId'] as int?)
      .whereType<int>()
      .toList();
  db.execute(
    'DELETE FROM o_eventChapter WHERE novelId IN ($placeholders)',
    novelIds,
  );
  if (eventIds.isEmpty) return;
  db.execute(
    'DELETE FROM o_event WHERE id IN (${_placeholders(eventIds)}) '
    'AND id NOT IN (SELECT DISTINCT eventId FROM o_eventChapter '
    'WHERE eventId IS NOT NULL)',
    eventIds,
  );
}
