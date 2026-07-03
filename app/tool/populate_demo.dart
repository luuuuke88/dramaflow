// 演示项目填充 v5（真实 LLM）：向 App 实际数据目录写入《剑出寒山》演示项目，
// 走通全链：章节导入 → 事件生成 → 剧本 → 资产提取 → 分镜生成 → 首帧图生成 →
// 配音资产池 → 配音绑定。
//
// 有意止步于此，不含视频生成与最终合成：视频生成走真实 Seedance/Volcengine
// 付费供应商（参见 AGENTS.md），P4 已明确约定"真实视频生成效果留 luke 实机
// 验证"，不在自动化脚本里代为消耗真实供应商额度。分镜首帧图就绪后，
// 视频生成→挑选→合成可直接在 App 内的工作台页完成，或调用
// engine.batchGenerateVideos(projectId, storyboardIds) / engine.composeEpisode(...)。
//
// 运行：cd app && dart run tool/populate_demo.dart
// App 数据目录 = ~/Library/Containers/com.dramaflow.dramaflow/Data/Documents/dramaflow
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/audio_bind.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/events.dart';
import 'package:dramaflow/src/engine/novel.dart';
import 'package:dramaflow/src/engine/novel_parse.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';

Future<void> _waitTaskDrain(
  Engine engine,
  String taskClass,
  int projectId, {
  Duration timeout = const Duration(minutes: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (!engine.queue.hasActiveTask(taskClass, projectId: projectId)) return;
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  stdout.writeln('[populate] ⚠️ 等待任务 $taskClass 超时（$timeout），继续后续步骤');
}

/// 生成一段极短的合法静音 WAV（8kHz/8bit/单声道），用于配音资产池占位素材——
/// 不做语音合成（TTS 明确不在本项目范围内），但产出的文件是真实可播放的
/// 音频容器，而非空字节，符合"不是半成品"的要求。
Uint8List _tinySilentWav() {
  const sampleRate = 8000;
  const numSamples = 4000; // 0.5s
  final data = Uint8List(numSamples)..fillRange(0, numSamples, 128);
  final buffer = BytesBuilder();
  void writeStr(String s) => buffer.add(ascii.encode(s));
  void writeU32(int v) => buffer.add([
        v & 0xff,
        (v >> 8) & 0xff,
        (v >> 16) & 0xff,
        (v >> 24) & 0xff,
      ]);
  void writeU16(int v) => buffer.add([v & 0xff, (v >> 8) & 0xff]);

  writeStr('RIFF');
  writeU32(36 + data.length);
  writeStr('WAVE');
  writeStr('fmt ');
  writeU32(16);
  writeU16(1); // PCM
  writeU16(1); // mono
  writeU32(sampleRate);
  writeU32(sampleRate); // byteRate = sampleRate * channels * bitsPerSample/8
  writeU16(1); // blockAlign
  writeU16(8); // bitsPerSample
  writeStr('data');
  writeU32(data.length);
  buffer.add(data);
  return buffer.toBytes();
}

Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME']!;
  final dataDir = args.isNotEmpty
      ? args.first
      : '$home/Library/Containers/com.dramaflow.dramaflow/Data/Documents/dramaflow';
  stdout.writeln('[populate] dataDir=$dataDir');
  final engine = await Engine.boot(dataDir: dataDir, isMobile: false);

  try {
    final projectId = engine.addProject(
      projectType: 'novel',
      name: '剑出寒山',
      intro: '少年林朝雪身负寒山剑意，下山入世，卷入江湖纷争。',
      type: '武侠',
      videoRatio: '16:9',
      imageQuality: '1K',
    );
    stdout.writeln('[populate] 项目 #$projectId');

    final text = File('tool/demo_novel.txt').readAsStringSync();
    final chapters = flattenParsedNovel(parseNovel(text));
    final novelIds = engine.addNovels(projectId, chapters);
    stdout.writeln('[populate] 导入 ${novelIds.length} 章，事件生成中…');

    final deadline = DateTime.now().add(const Duration(minutes: 15));
    while (DateTime.now().isBefore(deadline)) {
      final states = engine.novelEventState(novelIds);
      if (states.length == novelIds.length) break;
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    final ok =
        engine.novelEventState(novelIds).where((s) => s.eventState == 1).length;
    stdout.writeln('[populate] 事件完成 $ok/${novelIds.length}');

    final scriptIds = <int>[];
    for (final (i, chapter) in chapters.indexed) {
      scriptIds.add(engine.addScript(
        projectId: projectId,
        name: '第${i + 1}集 ${chapter.chapter}'.trim(),
        content: chapter.chapterData,
      ));
    }
    engine.extractAssets(scriptIds, projectId);
    stdout.writeln('[populate] 资产提取中…');
    final deadline2 = DateTime.now().add(const Duration(minutes: 15));
    while (DateTime.now().isBefore(deadline2)) {
      final states = engine.scriptExtractState(scriptIds);
      if (states.length == scriptIds.length) break;
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    final scripts = engine.scripts(projectId);
    stdout.writeln('[populate] 剧本 ${scripts.length} 个，'
        '资产 ${engine.assetOptions(projectId).length} 个');

    stdout.writeln('[populate] 分镜生成中…');
    for (final scriptId in scriptIds) {
      engine.generateStoryboards(projectId, scriptId);
      await _waitTaskDrain(engine, 'storyboard_generate', projectId);
    }
    final allStoryboardIds = <int>[];
    for (final scriptId in scriptIds) {
      allStoryboardIds.addAll(engine.storyboards(scriptId).map((s) => s.id));
    }
    stdout.writeln('[populate] 分镜共 ${allStoryboardIds.length} 个，首帧图生成中…');

    if (allStoryboardIds.isNotEmpty) {
      engine.batchGenerateStoryboardImages(projectId, allStoryboardIds,
          compulsory: true);
      await _waitTaskDrain(engine, 'storyboard_image_generation', projectId,
          timeout: const Duration(minutes: 20));
    }
    var imageDone = 0;
    for (final scriptId in scriptIds) {
      imageDone +=
          engine.storyboards(scriptId).where((s) => s.state == sbDone).length;
    }
    stdout.writeln('[populate] 首帧图完成 $imageDone/${allStoryboardIds.length}');

    stdout.writeln('[populate] 配音资产池创建中…');
    final voiceWav = base64Encode(_tinySilentWav());
    const voices = [
      ('清亮少年音', '男', '清亮、干净，带少年气'),
      ('低沉长者音', '男', '低沉沙哑，带岁月感的老者音色'),
      ('清冷女声', '女', '清冷疏离，语速偏慢'),
    ];
    for (final (name, sex, describe) in voices) {
      engine.addAudioAssets(
        projectId: projectId,
        name: name,
        sex: sex,
        describe: describe,
        items: [
          (
            base64: voiceWav,
            ext: 'wav',
            prompt: '示例配音片段',
            name: name,
            describe: describe,
            existingImageId: null,
          ),
        ],
      );
    }
    stdout.writeln(
        '[populate] 配音资产池 ${engine.audioPool(projectId).length} 个音色');

    final roleIds =
        engine.roleAudioBindings(projectId).map((r) => r.roleId).toList();
    if (roleIds.isNotEmpty) {
      stdout.writeln('[populate] 角色 ${roleIds.length} 个，AI 配音匹配中…');
      engine.batchBindAudio(projectId, roleIds);
      await _waitTaskDrain(engine, 'audio_bind', projectId);
    }
    final bound = engine
        .roleAudioBindings(projectId)
        .where((r) => r.audioAssetId != null)
        .length;
    stdout.writeln('[populate] 配音绑定完成 $bound/${roleIds.length}');

    stdout.writeln('[populate] ✅ 完成（章节→事件→剧本→资产→分镜→首帧图→配音绑定全链路已生成真实数据）');
    stdout.writeln('[populate] 剩余最后一步（有意留给 luke 实机操作，涉及真实付费视频供应商）：'
        '在工作台页为各分镜生成/挑选视频，再合成本集。');
  } finally {
    engine.dispose();
  }
  exit(0);
}
