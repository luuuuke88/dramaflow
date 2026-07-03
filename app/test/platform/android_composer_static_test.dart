import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android uses the native video composer channel instead of UnsupportedComposer',
      () {
    final bootstrapSource =
        File('lib/src/bootstrap/bootstrap_io.dart').readAsStringSync();
    final activitySource = File(
      'android/app/src/main/kotlin/com/dramaflow/dramaflow/MainActivity.kt',
    ).readAsStringSync();

    expect(
      bootstrapSource,
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
