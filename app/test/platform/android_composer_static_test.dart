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
    expect(activitySource, contains('transition'));
    expect(activitySource, contains('filterPreset'));
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

  test('Android composer renders video-only NLE fade and filters with Media3', () {
    final activitySource = File(
      'android/app/src/main/kotlin/com/dramaflow/dramaflow/MainActivity.kt',
    ).readAsStringSync();
    final gradleSource = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradleSource, contains('androidx.media3:media3-transformer'));
    expect(gradleSource, contains('androidx.media3:media3-effect'));
    expect(gradleSource, contains('androidx.media3:media3-common'));
    expect(activitySource, contains('composeWithNleEffects'));
    expect(activitySource, contains('EditedMediaItem'));
    expect(activitySource, contains('Effects'));
    expect(activitySource, contains('RgbMatrix'));
    expect(activitySource, contains('Transformer.Builder'));
    expect(activitySource, contains('transformer.start'));
    expect(activitySource, contains('fadeMatrix'));
    expect(activitySource, contains('filterMatrix'));
    expect(
      activitySource,
      contains('copyTrack(item.segment.videoPath'),
      reason: 'Non-NLE mux fallback should remain for external-audio paths.',
    );
  });
}
