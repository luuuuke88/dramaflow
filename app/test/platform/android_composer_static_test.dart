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

  test('Android composer renders video-only NLE fade and filters with Media3',
      () {
    final activitySource = File(
      'android/app/src/main/kotlin/com/dramaflow/dramaflow/MainActivity.kt',
    ).readAsStringSync();
    final gradleSource =
        File('android/app/build.gradle.kts').readAsStringSync();

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

  test('Android composer renders whip-pan with a Media3 matrix transform', () {
    final activitySource = File(
      'android/app/src/main/kotlin/com/dramaflow/dramaflow/MainActivity.kt',
    ).readAsStringSync();

    expect(activitySource, contains('MatrixTransformation'));
    expect(activitySource, contains('WhipPanTransformation'));
    expect(activitySource, contains('whipPanMatrix'));
    expect(activitySource, contains('segment.transition == "whip_pan"'));
    expect(activitySource, contains('it.transition != "whip_pan"'));
    expect(
      activitySource,
      contains('postTranslate'),
      reason: 'Whip-pan should move frames spatially, not just tint or fade.',
    );
  });

  test('Android composer renders cross-shot dissolve with compositor alpha',
      () {
    final activitySource = File(
      'android/app/src/main/kotlin/com/dramaflow/dramaflow/MainActivity.kt',
    ).readAsStringSync();

    expect(activitySource, contains('VideoCompositorSettings'));
    expect(activitySource, contains('OverlaySettings'));
    expect(activitySource, contains('composeWithDissolveTransitions'));
    expect(activitySource, contains('DissolveCompositionPlan'));
    expect(activitySource, contains('DissolveVideoCompositorSettings'));
    expect(activitySource, contains('dissolveAlpha'));
    expect(activitySource, contains('MediaItem.ClippingConfiguration'));
    expect(activitySource, contains('setVideoCompositorSettings'));
    expect(activitySource, contains('transition == "dissolve"'));
    expect(activitySource, contains('it.transition != "dissolve"'));
  });

  test('Android composer pre-renders NLE clips before muxing external audio',
      () {
    final activitySource = File(
      'android/app/src/main/kotlin/com/dramaflow/dramaflow/MainActivity.kt',
    ).readAsStringSync();

    expect(activitySource, contains('composeWithNleEffectsAndExternalAudio'));
    expect(activitySource, contains('renderNleSegmentToTemp'));
    expect(activitySource, contains('nleTempFiles'));
    expect(activitySource, contains('deleteNleTempFiles'));
    expect(
      activitySource,
      contains('composeWithExternalAudio(renderedSegments, output)'),
      reason:
          'Rendered video clips should reuse the proven external-audio mux path.',
    );
    expect(
      activitySource,
      contains('copyTrack(item.segment.videoPath'),
      reason:
          'Plain external-audio mux fallback should remain for non-NLE shots.',
    );
  });

  test('Android composer keeps dissolve when muxing external audio', () {
    final activitySource = File(
      'android/app/src/main/kotlin/com/dramaflow/dramaflow/MainActivity.kt',
    ).readAsStringSync();

    expect(activitySource,
        contains('composeWithDissolveTransitionsAndExternalAudio'));
    expect(activitySource, contains('renderDissolveCompositionToTemp'));
    expect(activitySource, contains('muxRenderedVideoWithTimelineAudio'));
    expect(activitySource, contains('buildTimelineAudioSegments'));
    expect(activitySource, contains('TimelineAudioSegment'));
    expect(activitySource, contains('sourceStartUs'));
    expect(activitySource, contains('inputStartUs'));
    expect(
      activitySource,
      contains('segments.any { it.transition == "dissolve" }'),
      reason:
          'External-audio paths must detect cross-shot dissolve before falling back to per-clip rendering.',
    );
  });

  test('Android composer routes timeline clip layers into Media3 overlays', () {
    final activitySource = File(
      'android/app/src/main/kotlin/com/dramaflow/dramaflow/MainActivity.kt',
    ).readAsStringSync();

    expect(
      activitySource,
      contains('List<Map<String, Any?>>'),
      reason:
          'Timeline metadata includes numeric lane/start/duration values, not only strings.',
    );
    expect(activitySource, contains('timelineKind'));
    expect(activitySource, contains('val lane: Int'));
    expect(activitySource, contains('val startMs: Int?'));
    expect(activitySource, contains('val durationMs: Int?'));
    expect(activitySource, contains('hasTimelineMetadata'));
    expect(activitySource, contains('isOverlayClip'));
    expect(activitySource, contains('hasTimelineOverlays'));
    expect(activitySource, contains('composeWithTimelineOverlays'));
    expect(activitySource, contains('primaryTimelineSegments'));
    expect(activitySource, contains('timelineOverlaySegments'));
    expect(activitySource, contains('TimelineOverlay'));
    expect(activitySource, contains('TimelineVideoCompositorSettings'));
    expect(activitySource, contains('timeUsFromMs'));
    expect(activitySource, contains('addGap(startUs)'));
    expect(activitySource,
        contains('setVideoCompositorSettings(TimelineVideoCompositorSettings'));
  });
}
