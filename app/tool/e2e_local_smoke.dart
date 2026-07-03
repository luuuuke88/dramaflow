// Local E2E smoke: no network, no JS backend, no real AI provider.
//
// It proves the embedded Dart engine can carry a short-drama episode through:
// novel chapters -> script -> assets -> storyboard -> selected video candidates
// -> shot voice binding -> episode composition.
//
// Run:
//   cd app && dart run tool/e2e_local_smoke.dart [dataDir]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/compose.dart';
import 'package:dramaflow/src/engine/compose_episode.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/novel.dart';
import 'package:dramaflow/src/engine/novel_parse.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/storyboard_audio.dart';
import 'package:dramaflow/src/engine/video_track.dart';
import 'package:path/path.dart' as p;

class OfflinePipelineSmokeResult {
  final String projectName;
  final int chapterCount;
  final int scriptCount;
  final int assetCount;
  final int storyboardCount;
  final int selectedVideoCount;
  final int boundShotAudioCount;
  final int composeSegmentCount;
  final String outputAbsPath;

  const OfflinePipelineSmokeResult({
    required this.projectName,
    required this.chapterCount,
    required this.scriptCount,
    required this.assetCount,
    required this.storyboardCount,
    required this.selectedVideoCount,
    required this.boundShotAudioCount,
    required this.composeSegmentCount,
    required this.outputAbsPath,
  });
}

class OfflinePipelineSeedResult {
  final int projectId;
  final int scriptId;
  final List<int> chapterIds;
  final List<int> assetIds;
  final List<int> storyboardIds;
  final int voiceId;

  const OfflinePipelineSeedResult({
    required this.projectId,
    required this.scriptId,
    required this.chapterIds,
    required this.assetIds,
    required this.storyboardIds,
    required this.voiceId,
  });
}

OfflinePipelineSeedResult seedOfflinePipeline(Engine engine) {
  final projectId = engine.addProject(
    projectType: 'novel',
    name: '离线主链冒烟',
    intro: '不调用任何线上供应商的端到端数据流验证。',
    type: '武侠',
    videoRatio: '16:9',
    imageQuality: '1K',
  );

  final chapters = flattenParsedNovel(parseNovel(_demoNovel)).take(2).toList();
  final chapterIds = engine.addNovels(projectId, chapters);
  final scriptId = engine.addScript(
    projectId: projectId,
    name: '第一集 雪夜来客',
    content: chapters.map((c) => c.chapterData).join('\n\n'),
  );

  final roleId = engine.addAsset(
    projectId: projectId,
    type: 'role',
    name: '裴无咎',
    describe: '男性，披黑斗篷，灰色眼睛，脸上有火烧疤痕。',
    prompt: 'scarred swordsman, black cloak, gray eyes, wuxia drama style',
  );
  final sceneId = engine.addAsset(
    projectId: projectId,
    type: 'scene',
    name: '寒山派山门',
    describe: '积雪覆盖的山门，冷白月光，远处山道隐入风雪。',
    prompt: 'snowy sect gate, cold moonlight, wuxia mountain path',
  );
  engine.updateScript(scriptId, assets: [roleId, sceneId]);

  final firstShotId = engine.addStoryboard(
    projectId: projectId,
    scriptId: scriptId,
    prompt: '雪夜山门前，黑衣人踏雪而来',
    videoDesc: '低机位缓慢推近，斗篷边缘被风雪掀起',
    duration: '4',
    assetIds: [roleId, sceneId],
  );
  final secondShotId = engine.addStoryboard(
    projectId: projectId,
    scriptId: scriptId,
    prompt: '焦黑玉佩落在雪中，守门弟子震惊后退',
    videoDesc: '特写切到玉佩，再快速拉回弟子表情',
    duration: '5',
    assetIds: [sceneId],
  );

  _attachFirstFrame(engine, projectId, firstShotId);
  _attachFirstFrame(engine, projectId, secondShotId);
  _attachSelectedVideo(engine, projectId, scriptId, firstShotId, index: 1);
  _attachSelectedVideo(engine, projectId, scriptId, secondShotId, index: 2);

  final voiceId = engine.addAudioAssets(
    projectId: projectId,
    name: '沙哑复仇者',
    sex: '男',
    describe: '低沉沙哑，压抑愤怒',
    items: [
      (
        base64: base64Encode(_tinySilentWav()),
        ext: 'wav',
        prompt: '我找沈青崖。',
        name: '沙哑复仇者-样例',
        describe: '低声',
        existingImageId: null,
      ),
    ],
  );
  engine.bindStoryboardAudio(
    storyboardId: firstShotId,
    audioAssetId: voiceId,
    audioText: '我找沈青崖。',
  );

  return OfflinePipelineSeedResult(
    projectId: projectId,
    scriptId: scriptId,
    chapterIds: chapterIds,
    assetIds: [roleId, sceneId],
    storyboardIds: [firstShotId, secondShotId],
    voiceId: voiceId,
  );
}

Future<OfflinePipelineSmokeResult> runOfflinePipelineSmoke({
  required String dataDir,
}) async {
  Directory(dataDir).createSync(recursive: true);
  final db = openEngineDb(p.join(dataDir, 'dramaflow.sqlite'));
  final composer = _SmokeComposer();
  final engine = Engine(
    db: db,
    media: MediaStore(p.join(dataDir, 'media')),
    gateway: _OfflineGateway(),
    config: EngineConfig(db, isMobile: false),
    composer: composer,
  );

  try {
    final seed = seedOfflinePipeline(engine);
    final composeResult =
        await engine.composeEpisode(seed.projectId, seed.scriptId);
    final projectName =
        engine.projects().firstWhere((p) => p.id == seed.projectId).name!;
    final scripts = engine.scripts(seed.projectId);
    final storyboards = engine.storyboards(seed.scriptId);
    final selectedVideos = engine
        .orderedSelectedVideoPaths(seed.scriptId)
        .whereType<String>()
        .length;
    final boundShotAudio = engine
        .orderedStoryboardAudioPaths(seed.scriptId)
        .whereType<String>()
        .length;

    return OfflinePipelineSmokeResult(
      projectName: projectName,
      chapterCount: seed.chapterIds.length,
      scriptCount: scripts.length,
      assetCount: engine.assetOptions(seed.projectId).length,
      storyboardCount: storyboards.length,
      selectedVideoCount: selectedVideos,
      boundShotAudioCount: boundShotAudio,
      composeSegmentCount: composeResult.segmentCount,
      outputAbsPath: engine.mediaAbsPath(composeResult.outputRelPath),
    );
  } finally {
    engine.dispose();
    db.close();
  }
}

void _attachFirstFrame(Engine engine, int projectId, int storyboardId) {
  final rel = engine.media.saveImage(_tinyPngBytes, '$projectId');
  engine.setStoryboardImage(storyboardId, rel);
}

void _attachSelectedVideo(
  Engine engine,
  int projectId,
  int scriptId,
  int storyboardId, {
  required int index,
}) {
  final trackId = engine.ensureTrackForStoryboard(storyboardId);
  engine.updateVideoPrompt(trackId, 'offline dolly shot $index');
  engine.updateVideoDuration(trackId, index == 1 ? 4 : 5);
  final rel = engine.media.saveVideo([0, 0, 0, index], '$projectId');
  engine.db.execute(
    'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state,time) '
    'VALUES (?,?,?,?,?,?)',
    [
      projectId,
      scriptId,
      trackId,
      rel,
      vtDone,
      DateTime.now().millisecondsSinceEpoch,
    ],
  );
  engine.selectVideo(trackId, engine.db.lastInsertRowId);
}

class _SmokeComposer implements VideoComposer {
  @override
  Future<void> concat(
      List<String> segmentAbsPaths, String outputAbsPath) async {
    File(outputAbsPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([for (final _ in segmentAbsPaths) 1]);
  }

  @override
  Future<void> compose(
    List<ComposeSegment> segments,
    String outputAbsPath,
  ) async {
    File(outputAbsPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([
        for (final segment in segments) segment.hasAudio ? 2 : 1,
      ]);
  }

  @override
  Future<double?> probeDurationSec(String inputAbsPath) async => 9.0;
}

class _OfflineGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _tinyPngBytes = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x62,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

Uint8List _tinySilentWav() {
  const sampleRate = 8000;
  const sampleCount = 800;
  final samples = Uint8List(sampleCount)..fillRange(0, sampleCount, 128);
  final out = BytesBuilder();

  void str(String value) => out.add(ascii.encode(value));
  void u16(int value) => out.add([value & 0xff, (value >> 8) & 0xff]);
  void u32(int value) => out.add([
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ]);

  str('RIFF');
  u32(36 + samples.length);
  str('WAVEfmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(sampleRate);
  u32(sampleRate);
  u16(1);
  u16(8);
  str('data');
  u32(samples.length);
  out.add(samples);
  return out.toBytes();
}

const _demoNovel = '''
第一章 雪夜来客

寒山派山门前积雪三日未化。守门弟子陈默忽然看见山道尽头走来一个披黑斗篷的身影。

第二章 焦玉

黑衣人从怀中取出半块焦黑玉佩，扔在雪地上。陈默瞳孔骤缩，那是寒山派掌门信物。
''';

Future<void> main(List<String> args) async {
  final dataDir = args.isNotEmpty
      ? args.first
      : Directory.systemTemp.createTempSync('df-local-smoke-').path;
  final result = await runOfflinePipelineSmoke(dataDir: dataDir);
  stdout.writeln('[local-smoke] project=${result.projectName}');
  stdout.writeln('[local-smoke] chapters=${result.chapterCount}');
  stdout.writeln('[local-smoke] scripts=${result.scriptCount}');
  stdout.writeln('[local-smoke] assets=${result.assetCount}');
  stdout.writeln('[local-smoke] storyboards=${result.storyboardCount}');
  stdout.writeln('[local-smoke] selectedVideos=${result.selectedVideoCount}');
  stdout.writeln('[local-smoke] shotAudio=${result.boundShotAudioCount}');
  stdout.writeln('[local-smoke] output=${result.outputAbsPath}');
  stdout.writeln('[local-smoke] OK');
}
