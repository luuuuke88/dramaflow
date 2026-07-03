import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'Android uses the native video composer channel instead of UnsupportedComposer',
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
    expect(activitySource, contains('inspectMedia'));
    expect(activitySource, contains('videoTrackCount'));
    expect(activitySource, contains('audioTrackCount'));
    expect(activitySource, contains('concat'));
    expect(activitySource, contains('compose'));
    expect(
      activitySource,
      contains('copyExternalAudioTrack'),
      reason:
          'Android should at least mux silent video with standalone voice audio.',
    );
    expect(
      activitySource,
      isNot(contains('Android 当前合成器暂未支持分镜配音混合')),
    );
  });
}
