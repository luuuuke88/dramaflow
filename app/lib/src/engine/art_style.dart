// 画风库（照抄 ToonFlow artStyle/{addArtStyle,editArtStyle,getArtStyle}）：
// 全局画风条目，每条 = 名称 + 封面图 + 画风提示词，存 o_artStyle。
// 与项目级视觉手册（skills/art_skills 文件包）不同，画风库是轻量的提示词条目，
// 项目的 artStyle 字段可引用某条画风库条目的名称。
// 访问模式镜像 script_plan.dart（extension on Engine），图片经 media 落盘。
import 'dart:convert';
import 'dart:io';

import 'engine.dart';
import 'errors.dart';

class ArtStyleRow {
  final int id;
  final String name;
  final String label;
  final String prompt;
  final String? fileUrl; // rel 媒体路径（如 `artStyle/xxx.png`）
  const ArtStyleRow({
    required this.id,
    required this.name,
    required this.label,
    required this.prompt,
    required this.fileUrl,
  });
}

extension ArtStyleApi on Engine {
  /// 画风库全量列表（照抄 getArtStyle）。
  List<ArtStyleRow> artStyles() => db
      .select('SELECT * FROM o_artStyle ORDER BY id DESC')
      .map((r) => ArtStyleRow(
            id: r['id'] as int,
            name: (r['name'] as String?) ?? '',
            label: (r['label'] as String?) ?? '',
            prompt: (r['prompt'] as String?) ?? '',
            fileUrl: r['fileUrl'] as String?,
          ))
      .toList();

  /// 新增画风（照抄 addArtStyle）：base64 封面落盘，label 同 name。
  int addArtStyle({
    required String name,
    required String prompt,
    String? base64Image,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const EngineException(errLlmFormat, {'reason': '画风名称不能为空'});
    }
    final rel = _saveCover(base64Image);
    db.execute(
      'INSERT INTO o_artStyle (name,label,prompt,fileUrl) VALUES (?,?,?,?)',
      [trimmed, trimmed, prompt, rel],
    );
    return db.lastInsertRowId;
  }

  /// 编辑画风（照抄 editArtStyle）：给了新封面才替换，label 同 name。
  void editArtStyle(
    int id, {
    required String name,
    required String prompt,
    String? base64Image,
  }) {
    final row = db
        .select('SELECT fileUrl FROM o_artStyle WHERE id=?', [id]).firstOrNull;
    if (row == null) {
      throw const EngineException(errLlmFormat, {'reason': '画风不存在'});
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const EngineException(errLlmFormat, {'reason': '画风名称不能为空'});
    }
    var rel = row['fileUrl'] as String?;
    if (base64Image != null && base64Image.isNotEmpty) {
      _deleteCover(rel);
      rel = _saveCover(base64Image);
    }
    db.execute(
      'UPDATE o_artStyle SET name=?, label=?, prompt=?, fileUrl=? WHERE id=?',
      [trimmed, trimmed, prompt, rel, id],
    );
  }

  /// 删除画风：连同封面文件。
  void deleteArtStyle(int id) {
    final row = db
        .select('SELECT fileUrl FROM o_artStyle WHERE id=?', [id]).firstOrNull;
    if (row == null) return;
    _deleteCover(row['fileUrl'] as String?);
    db.execute('DELETE FROM o_artStyle WHERE id=?', [id]);
  }

  String? _saveCover(String? base64Image) {
    if (base64Image == null || base64Image.isEmpty) return null;
    final raw = base64Image.contains(',')
        ? base64Image.substring(base64Image.indexOf(',') + 1)
        : base64Image;
    return media.saveImage(base64Decode(raw), 'artStyle');
  }

  void _deleteCover(String? rel) {
    if (rel == null || rel.isEmpty) return;
    final f = File(media.absPath(rel));
    if (f.existsSync()) f.deleteSync();
  }
}
