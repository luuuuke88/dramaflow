import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/audio_bind.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late Database db;
  late _Gateway gateway;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-tts-');
    db = openEngineDb(':memory:');
    gateway = _Gateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 10),
    );
    projectId = engine.addProject(projectType: 'novel', name: '配音生成测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('synthesizeAudioAsset 生成音频文件并挂到音频资产', () async {
    final audioId = engine.addAsset(
      projectId: projectId,
      type: 'audio',
      name: '低音男声',
      describe: '男|沉稳、克制',
    );
    const relPath = '1/tts_demo.mp3';
    File(engine.mediaAbsPath(relPath))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3, 4]);
    gateway.nextSpeechRelPath = relPath;

    final imageId = await engine.synthesizeAudioAsset(
      audioAssetId: audioId,
      text: '少侠，该醒了。',
      voice: 'voice-low-male',
    );

    expect(gateway.lastText, '少侠，该醒了。');
    expect(gateway.lastVoice, 'voice-low-male');
    expect(gateway.lastProjectId, '$projectId');
    expect(gateway.lastStage, 'tts');

    final row = db.select('SELECT * FROM o_image WHERE id=?', [imageId]).single;
    expect(row['assetsId'], audioId);
    expect(row['type'], 'audio');
    expect(row['state'], '已完成');
    expect(row['filePath'], relPath);

    final assetImageId =
        db.select('SELECT imageId FROM o_assets WHERE id=?', [audioId]).single;
    expect(assetImageId['imageId'], imageId);
    expect(engine.audioAssetAbsPath(audioId), engine.mediaAbsPath(relPath));
    expect(File(engine.audioAssetAbsPath(audioId)!).readAsBytesSync(),
        [1, 2, 3, 4]);
  });

  test('addSynthesizedAudioAsset 从文本创建可试听的音频素材', () async {
    const relPath = '1/tts_new.mp3';
    File(engine.mediaAbsPath(relPath))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([5, 6, 7]);
    gateway.nextSpeechRelPath = relPath;

    final parentId = await engine.addSynthesizedAudioAsset(
      projectId: projectId,
      name: 'alloy',
      sex: '男',
      describe: '低音示例',
      text: '吾辈修士，何惧一战。',
      voice: 'alloy',
    );

    final page = engine.getAssets(projectId, type: 'audio');
    final parent = page.data.single;
    expect(parent.id, parentId);
    expect(parent.sex, '男');
    expect(parent.audioDescribe, '低音示例');
    expect(parent.sonAssets.single.prompt, '吾辈修士，何惧一战。');
    expect(parent.sonAssets.single.imageId, isNotNull);
    expect(engine.audioAssetAbsPath(parentId), engine.mediaAbsPath(relPath));
  });
}

class _Gateway implements ProviderGateway {
  String? nextSpeechRelPath;
  String? lastText;
  String? lastProjectId;
  String? lastStage;
  String? lastVoice;

  @override
  Future<String> generateSpeech(
    String text,
    String projectId, {
    required String stage,
    required String voice,
    CancelToken? cancelToken,
    String? format,
  }) async {
    lastText = text;
    lastProjectId = projectId;
    lastStage = stage;
    lastVoice = voice;
    return nextSpeechRelPath!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
