import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dramaflow/src/engine/media.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mediastore'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('saveImage 落盘并返回 rel 路径', () {
    final store = MediaStore(tmp.path);
    final rel = store.saveImage([1, 2, 3], 'proj1');
    expect(rel, matches(RegExp(r'^proj1/img_[0-9a-z]{14}\.png$')));
    expect(File(store.absPath(rel)).readAsBytesSync(), [1, 2, 3]);
  });

  test('saveVideo 后缀 mp4', () {
    final store = MediaStore(tmp.path);
    final rel = store.saveVideo([9], 'p9');
    expect(rel, matches(RegExp(r'^p9/vid_[0-9a-z]{14}\.mp4$')));
  });

  test('deleteProject 清目录', () {
    final store = MediaStore(tmp.path);
    final rel = store.saveImage([1], 'p2');
    store.deleteProject('p2');
    expect(File(store.absPath(rel)).existsSync(), isFalse);
  });
}
