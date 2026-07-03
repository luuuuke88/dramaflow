import 'dart:io';

import 'package:dramaflow/src/engine/compose.dart';
import 'package:dramaflow/src/platform/avfoundation_composer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apple composer exposes audio-aware compose method', () {
    final dartSource =
        File('lib/src/platform/avfoundation_composer.dart').readAsStringSync();
    final macosSource =
        File('macos/Runner/ComposerPlugin.swift').readAsStringSync();
    final iosSource =
        File('ios/Runner/ComposerPlugin.swift').readAsStringSync();

    expect(dartSource, contains("'compose'"));
    expect(dartSource, contains("'segments'"));
    expect(dartSource, contains("'audioPath'"));

    for (final source in [macosSource, iosSource]) {
      expect(source, contains('case "compose"'));
      expect(source, contains('case "inspectMedia"'));
      expect(source, contains('composeSegmentsArgument'));
      expect(source, contains('compositionVoiceTrack'));
      expect(source, contains('noAudioTrack'));
      expect(source, contains('transition'));
      expect(source, contains('filterPreset'));
    }
  });

  test('Apple composer renders NLE filters and fade transitions', () {
    final macosSource =
        File('macos/Runner/ComposerPlugin.swift').readAsStringSync();
    final iosSource =
        File('ios/Runner/ComposerPlugin.swift').readAsStringSync();

    for (final source in [macosSource, iosSource]) {
      expect(source, contains('AVMutableVideoComposition'));
      expect(source, contains('applyingCIFiltersWithHandler'));
      expect(source, contains('filterImage'));
      expect(source, contains('fadeOpacity'));
      expect(source, contains('CIColorControls'));
      expect(source, contains('CISepiaTone'));
      expect(source, contains('exportSession.videoComposition'));
    }
  });

  test('Apple composer renders cross-shot dissolve with layered tracks', () {
    final macosSource =
        File('macos/Runner/ComposerPlugin.swift').readAsStringSync();
    final iosSource =
        File('ios/Runner/ComposerPlugin.swift').readAsStringSync();

    for (final source in [macosSource, iosSource]) {
      expect(source, contains('secondaryCompositionVideoTrack'));
      expect(source, contains('makeLayeredVideoComposition'));
      expect(source, contains('AVMutableVideoCompositionLayerInstruction'));
      expect(source, contains('setOpacityRamp'));
      expect(source, contains('dissolveDuration'));
      expect(source, contains('applyFadeOpacityRamps'));
      expect(source, contains('transition == "dissolve"'));
    }
  });

  test('Dart composer wrapper uses localized error keys', () {
    final dartSource =
        File('lib/src/platform/avfoundation_composer.dart').readAsStringSync();

    expect(dartSource, contains('errPlatformComposer'));
    expect(
      RegExp(r"""(['"])(?:(?!\1).)*[\u4e00-\u9fff](?:(?!\1).)*\1""")
          .hasMatch(dartSource),
      isFalse,
      reason: 'Composer Dart wrapper must not throw hardcoded Chinese UI text.',
    );
  });

  test('Dart composer wrapper sends transition and filter metadata', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('dramaflow/composer'),
        null,
      );
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('dramaflow/composer'),
      (call) async {
        calls.add(call);
        return null;
      },
    );

    await const AVFoundationComposer().compose(
      const [
        ComposeSegment(
          videoAbsPath: '/tmp/a.mp4',
          audioAbsPath: '/tmp/a.m4a',
          transition: 'fade',
          filter: 'cinematic',
        ),
      ],
      '/tmp/out.mp4',
    );

    final args = calls.single.arguments as Map<Object?, Object?>;
    final segments = args['segments'] as List<Object?>;
    final first = segments.single as Map<Object?, Object?>;
    expect(first['transition'], 'fade');
    expect(first['filterPreset'], 'cinematic');
  });
}
