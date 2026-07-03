import 'dart:io';

import 'package:dramaflow/src/engine/compose.dart';
import 'package:dramaflow/src/platform/avfoundation_composer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS AVFoundation composer mixes standalone audio into output',
      (_) async {
    if (!Platform.isMacOS) {
      return;
    }

    final dir = Directory.systemTemp.createTempSync('dramaflow-compose-smoke-');
    try {
      final videoPath = p.join(dir.path, 'silent-video.mp4');
      final audioPath = p.join(dir.path, 'voice.m4a');
      final outputPath = p.join(dir.path, 'episode.mp4');

      await _copyAsset(
        'integration_test/fixtures/silent_red_1500ms.mp4',
        videoPath,
      );
      await _copyAsset(
        'integration_test/fixtures/voice_880hz_1500ms.m4a',
        audioPath,
      );

      const composer = AVFoundationComposer();
      await composer.compose(
        [ComposeSegment(videoAbsPath: videoPath, audioAbsPath: audioPath)],
        outputPath,
      );

      expect(File(outputPath).existsSync(), isTrue);
      final info = await composer.inspectMedia(outputPath);
      expect(info.videoTrackCount, 1);
      expect(info.audioTrackCount, 1);
      final duration = await composer.probeDurationSec(outputPath);
      expect(duration, isNotNull);
      expect(duration!, greaterThan(1.0));
      expect(duration, lessThan(2.5));
    } finally {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });
}

Future<void> _copyAsset(String assetPath, String outputPath) async {
  final bytes = await rootBundle.load(assetPath);
  final file = File(outputPath);
  file.parent.createSync(recursive: true);
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
}
