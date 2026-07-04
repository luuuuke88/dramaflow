import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UI-facing Dart files do not hardcode Chinese strings', () {
    final files = <String>[
      ...Directory('lib/src/screens')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path),
      ...Directory('lib/src/widgets')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path),
      ...Directory('lib/src/util')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path),
      ...Directory('lib/src/state')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path),
    ]..sort();

    final offenders = <String>[];
    final chineseString = RegExp(
      r"""(['"])(?:(?!\1).)*[\u4e00-\u9fff](?:(?!\1).)*\1""",
    );

    for (final file in files) {
      final lines = File(file).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].split('//').first;
        if (chineseString.hasMatch(line)) {
          offenders.add('$file:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'UI 文案必须走 AppLocalizations，残留中文硬编码：\n'
          '${offenders.take(80).join('\n')}',
    );
  });
}
