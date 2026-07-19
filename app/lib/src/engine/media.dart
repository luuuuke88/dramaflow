import 'dart:io';
import 'package:path/path.dart' as p;
import 'util.dart';

/// 媒体文件仓库。rootDir 注入（App 用 documents/dramaflow/media，测试用临时目录）。
/// rel 路径统一正斜杠：`<projectId>/img_<id>.png`。
class MediaStore {
  final String rootDir;
  MediaStore(this.rootDir) {
    Directory(rootDir).createSync(recursive: true);
  }

  String saveImage(List<int> bytes, String projectId) =>
      _save(bytes, projectId, 'img', 'png');

  String saveVideo(List<int> bytes, String projectId) =>
      _save(bytes, projectId, 'vid', 'mp4');

  String saveAudio(List<int> bytes, String projectId, {String ext = 'mp3'}) =>
      _save(bytes, projectId, 'aud', ext);

  String _save(List<int> bytes, String projectId, String prefix, String ext) {
    final rel = '$projectId/${prefix}_${newId()}.$ext';
    final f = File(absPath(rel));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    return rel;
  }

  String absPath(String rel) => p.joinAll([rootDir, ...rel.split('/')]);

  /// 返回媒体根目录内、当前存在的普通文件的规范绝对路径。
  ///
  /// 数据库存的是相对路径，读取边界仍必须拒绝绝对路径、`..` 和链接逃逸，
  /// 避免导出或预览把媒体根目录外的文件当作项目素材。
  String? existingFilePath(String rel) {
    final value = rel.trim();
    if (value.isEmpty || p.isAbsolute(value) || p.split(value).contains('..')) {
      return null;
    }
    try {
      final root = Directory(rootDir).resolveSymbolicLinksSync();
      final candidate = File(p.normalize(p.join(root, value)));
      if (FileSystemEntity.typeSync(candidate.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      final resolved = candidate.resolveSymbolicLinksSync();
      return p.isWithin(root, resolved) ? resolved : null;
    } on FileSystemException {
      return null;
    }
  }

  void deleteProject(String projectId) {
    final dir = Directory(p.join(rootDir, projectId));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
