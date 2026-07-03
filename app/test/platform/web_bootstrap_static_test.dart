import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main uses platform bootstrap so web does not import io engine graph', () {
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(mainSource, isNot(contains("import 'dart:io'")));
    expect(mainSource, contains('if (dart.library.io)'));
    expect(mainSource, contains('if (dart.library.js_interop)'));

    final webBootstrap = File('lib/src/bootstrap/bootstrap_web.dart');
    expect(webBootstrap.existsSync(), isTrue);
    final webSource = webBootstrap.readAsStringSync();
    expect(webSource, isNot(contains("import 'dart:io'")));
    expect(webSource, isNot(contains("src/engine")));
    expect(webSource, isNot(contains("package:sqlite3/sqlite3.dart")));
  });
}
