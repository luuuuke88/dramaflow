import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings, tasks and shared widgets do not hardcode Chinese UI strings',
      () {
    final files = <String>[
      'lib/src/screens/settings_screen.dart',
      'lib/src/screens/tasks_screen.dart',
      ...Directory('lib/src/widgets')
          .listSync()
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
