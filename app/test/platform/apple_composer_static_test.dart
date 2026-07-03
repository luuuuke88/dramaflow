import 'dart:io';

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
}
