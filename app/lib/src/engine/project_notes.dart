// 项目笔记（v0.4 spec §4：原"长期记忆"降级命名）：
// 复用 memories 表（type='note'，isolationKey='project:<id>'），embedding 列弃用不写。
// 检索为中文友好三路加权：字符 bi-gram 重叠×2 + 整串子串命中×3 + 词元重叠×1。
// 禁止接回旧向量记忆模块或写入弃用向量索引（spec §2 半残调用清零）。
import 'engine.dart';

class ProjectNote {
  final String id;
  final String name;
  final String content;
  final int updatedAt;
  const ProjectNote({
    required this.id,
    required this.name,
    required this.content,
    required this.updatedAt,
  });
}

String _noteIsolationKey(int projectId) => 'project:$projectId';

extension ProjectNotesApi on Engine {
  List<ProjectNote> projectNotes(int projectId) => db
      .select(
        "SELECT id,name,content,createTime FROM memories "
        "WHERE isolationKey=? AND type='note' ORDER BY createTime DESC",
        [_noteIsolationKey(projectId)],
      )
      .map((r) => ProjectNote(
            id: r['id'] as String,
            name: (r['name'] as String?) ?? '',
            content: (r['content'] as String?) ?? '',
            updatedAt: (r['createTime'] as int?) ?? 0,
          ))
      .toList();

  String saveProjectNote(
    int projectId, {
    String? id,
    required String name,
    required String content,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (id != null) {
      db.execute(
        "UPDATE memories SET name=?, content=?, createTime=? "
        "WHERE id=? AND isolationKey=? AND type='note'",
        [name, content, now, id, _noteIsolationKey(projectId)],
      );
      return id;
    }
    final newId = 'note_${DateTime.now().microsecondsSinceEpoch}';
    db.execute(
      "INSERT INTO memories (id,isolationKey,name,content,createTime,type) "
      "VALUES (?,?,?,?,?,'note')",
      [newId, _noteIsolationKey(projectId), name, content, now],
    );
    return newId;
  }

  void deleteProjectNote(int projectId, String id) {
    db.execute(
      "DELETE FROM memories WHERE id=? AND isolationKey=? AND type='note'",
      [id, _noteIsolationKey(projectId)],
    );
  }

  List<ProjectNote> searchProjectNotes(
    int projectId,
    String query, {
    int limit = 5,
  }) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final qLower = q.toLowerCase();
    final qBigrams = _charBigrams(qLower);
    final qTokens = _latinTokens(qLower);
    final scored = <(int, ProjectNote)>[];
    for (final note in projectNotes(projectId)) {
      final text = '${note.name} ${note.content}'.toLowerCase();
      final bigramOverlap = qBigrams.intersection(_charBigrams(text)).length;
      final substringHit = text.contains(qLower) ? 1 : 0;
      final tokenOverlap = qTokens.intersection(_latinTokens(text)).length;
      final score = 2 * bigramOverlap + 3 * substringHit + tokenOverlap;
      if (score > 0) scored.add((score, note));
    }
    scored.sort((a, b) => b.$1 != a.$1
        ? b.$1.compareTo(a.$1)
        : b.$2.updatedAt.compareTo(a.$2.updatedAt));
    return [for (final s in scored.take(limit)) s.$2];
  }
}

/// 去空白后取相邻双字符集合（对中文即字 bi-gram，对英文为字符对）。
Set<String> _charBigrams(String s) {
  final compact = s.replaceAll(RegExp(r'\s+'), '');
  if (compact.length < 2) return compact.isEmpty ? const {} : {compact};
  return {
    for (var i = 0; i < compact.length - 1; i++) compact.substring(i, i + 2),
  };
}

/// 按空白/标点切词（拉丁词、数字串成词元；单个 CJK 字符也作为词元兜底）。
Set<String> _latinTokens(String s) => s
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((t) => t.isNotEmpty)
    .toSet();
