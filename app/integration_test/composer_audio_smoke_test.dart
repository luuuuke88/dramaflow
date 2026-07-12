import 'dart:io';

import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/compose.dart';
import 'package:dramaflow/src/engine/compose_episode.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/storyboard_audio.dart';
import 'package:dramaflow/src/engine/video_track.dart';
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

  testWidgets(
      'macOS engine closes a selected-candidate episode with audio, fade, and clip registration',
      (_) async {
    if (!Platform.isMacOS) {
      return;
    }

    final dir = Directory.systemTemp.createTempSync('dramaflow-episode-smoke-');
    final db = openEngineDb(':memory:');
    final engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
      composer: const AVFoundationComposer(),
    );
    try {
      final projectId = engine.addProject(projectType: 'novel', name: '成片闭环');
      final scriptId =
          engine.addScript(projectId: projectId, name: '第一集', content: 'x');
      final redPath = engine.mediaAbsPath('shots/red.mp4');
      final bluePath = engine.mediaAbsPath('shots/blue.mp4');
      await _copyAsset('integration_test/fixtures/clip_red_2s.mp4', redPath);
      await _copyAsset('integration_test/fixtures/clip_blue_2s.mp4', bluePath);
      final audioBytes = await rootBundle
          .load('integration_test/fixtures/voice_880hz_1500ms.m4a');
      final audioAssetId = engine.uploadClip(
        projectId: projectId,
        name: '旁白',
        type: 'audio',
        ext: 'm4a',
        bytes: audioBytes.buffer.asUint8List(),
      );

      final blueStoryboard =
          engine.addStoryboard(projectId: projectId, scriptId: scriptId);
      final redStoryboard =
          engine.addStoryboard(projectId: projectId, scriptId: scriptId);
      final redTrack = engine.ensureTrackForStoryboard(redStoryboard);
      final blueTrack = engine.ensureTrackForStoryboard(blueStoryboard);
      db.execute(
        "INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) "
        "VALUES (?,?,?,?,?)",
        [projectId, scriptId, redTrack, 'shots/missing.mp4', vtDone],
      );
      db.execute(
        "INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) "
        "VALUES (?,?,?,?,?)",
        [projectId, scriptId, redTrack, 'shots/red.mp4', vtDone],
      );
      final redVideoId = db.lastInsertRowId;
      engine.selectVideo(redTrack, redVideoId);
      db.execute(
        "INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) "
        "VALUES (?,?,?,?,?)",
        [projectId, scriptId, blueTrack, 'shots/blue.mp4', vtDone],
      );
      final blueVideoId = db.lastInsertRowId;
      engine.selectVideo(blueTrack, blueVideoId);
      engine.updateVideoTransition(redTrack, 'fade');
      engine.bindStoryboardAudio(
        storyboardId: blueStoryboard,
        audioAssetId: audioAssetId,
      );
      engine.reorderStoryboards(scriptId, [redStoryboard, blueStoryboard]);

      final result = await engine.composeEpisode(projectId, scriptId);

      expect(result.segmentCount, 2);
      expect(
          File(engine.mediaAbsPath(result.outputRelPath)).existsSync(), isTrue);
      expect(engine.orderedSelectedVideoPaths(scriptId),
          ['shots/red.mp4', 'shots/blue.mp4']);
      final info = await const AVFoundationComposer()
          .inspectMedia(engine.mediaAbsPath(result.outputRelPath));
      expect(info.videoTrackCount, 1);
      expect(info.audioTrackCount, greaterThanOrEqualTo(1));
      expect(info.durationSec, isNotNull);
      expect(info.durationSec!, greaterThan(3));
      expect(info.durationSec!, lessThan(5));
      final clip = engine.getAssets(projectId, type: 'clip').data.single;
      expect(clip.id, result.clipAssetId);
      expect(clip.filePath, result.outputRelPath);
    } finally {
      engine.dispose();
      db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });
}

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _copyAsset(String assetPath, String outputPath) async {
  final bytes = await rootBundle.load(assetPath);
  final file = File(outputPath);
  file.parent.createSync(recursive: true);
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
}
