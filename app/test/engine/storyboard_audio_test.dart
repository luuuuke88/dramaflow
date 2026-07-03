import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/audio_bind.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/storyboard_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late int projectId;
  late int scriptId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-storyboard-audio-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '分镜配音测试');
    scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: 'x');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('分镜可绑定配音素材，并按分镜顺序解析音频路径', () {
    final sb1 = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final audioId = engine.addAudioAssets(
      projectId: projectId,
      name: 'alloy',
      sex: '男',
      describe: '沉稳',
      items: [
        (
          base64: base64Encode([1, 2, 3]),
          ext: 'mp3',
          prompt: '少侠，该醒了。',
          name: 'alloy-1',
          describe: '平静',
          existingImageId: null,
        ),
      ],
    );

    engine.bindStoryboardAudio(
      storyboardId: sb1,
      audioAssetId: audioId,
      audioText: '少侠，该醒了。',
    );

    final first = engine.storyboards(scriptId).first;
    expect(first.audioAssetId, audioId);
    expect(first.audioText, '少侠，该醒了。');
    expect(engine.orderedStoryboardAudioPaths(scriptId), [
      engine.audioAssetAbsPath(audioId),
      null,
    ]);
  });
}
