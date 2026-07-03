import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android uses the native video composer channel instead of UnsupportedComposer',
      () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final activitySource = File(
      'android/app/src/main/kotlin/com/dramaflow/dramaflow/MainActivity.kt',
    ).readAsStringSync();

    expect(
      mainSource,
      contains('Platform.isAndroid'),
      reason: 'Android must enter the native composer path for mobile export.',
    );
    expect(
      activitySource,
      contains('MethodChannel'),
      reason: 'Android must register a native composer channel.',
    );
    expect(activitySource, contains('dramaflow/composer'));
    expect(activitySource, contains('probeDuration'));
    expect(activitySource, contains('concat'));
  });
}
