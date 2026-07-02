// M3 验收：真实 FFmpegKit 合成集成测试（需要真实设备运行时：flutter test integration_test -d macos）
// 流程：FfmpegKit 合成两个 2s 测试片源 → 写入引擎 takes → composeEpisode → 断言 mp4 产出与时长。
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dramaflow/src/engine/compose.dart';
import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/util.dart';

class _StubGateway implements ProviderGateway {
  @override
  Future<TextResult> generateText(String system, String user,
          {String stage = 'script_gen', CancelToken? cancelToken}) async =>
      const TextResult('{}');
  @override
  Future<String> generateImage(String prompt, String projectId,
          {String stage = 'asset_image', CancelToken? cancelToken}) async =>
      '';
  @override
  Future<String> generateVideo(
          String prompt, String firstFrameAbsPath, String projectId,
          {String stage = 'shot_video', CancelToken? cancelToken}) async =>
      '';
}

Future<void> _makeClip(String path, String color, double seconds) async {
  // 桌面运行时与引擎同款 Process 运行器（PATH ffmpeg）
  const runner = ProcessFfmpegRunner();
  final result = await runner.run([
    '-y',
    '-f', 'lavfi', '-i', 'color=c=$color:s=640x640:d=$seconds:r=30',
    '-f', 'lavfi', '-i', 'anullsrc=channel_layout=stereo:sample_rate=44100',
    '-shortest', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac',
    path,
  ]);
  if (!result.success) {
    fail('测试片源生成失败: ${result.stderr}');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实 FFmpegKit 合成两镜为一集 mp4', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('compose_it');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final db = openEngineDb('${tmp.path}/t.sqlite');
    final media = MediaStore('${tmp.path}/media');
    final engine = Engine(
        db: db,
        media: media,
        gateway: _StubGateway(),
        config: EngineConfig(db, isMobile: false));
    engine.queue.start();

    // 预置项目/集/两镜
    db.execute(
        "INSERT INTO projects (id,name,createdAt,updatedAt) VALUES ('p','t','x','x')");
    db.execute(
        "INSERT INTO episodes (id,projectId,idx,title,createdAt) VALUES ('e','p',1,'一','x')");
    for (final (i, id) in ['s1', 's2'].indexed) {
      db.execute(
          "INSERT INTO shots (id,episodeId,projectId,idx,createdAt) VALUES ('$id','e','p',${i + 1},'x')");
    }

    // 真实生成两个 2s 片源并登记为选中 take
    for (final (i, spec) in [('s1', 'red'), ('s2', 'blue')].indexed) {
      final rel = 'p/vid_take$i.mp4';
      final abs = media.absPath(rel);
      File(abs).parent.createSync(recursive: true);
      await _makeClip(abs, spec.$2, 2);
      final takeId = newId();
      db.execute(
          "INSERT INTO video_takes (id,shotId,videoPath,durationSec,createdAt) VALUES ('$takeId','${spec.$1}','$rel',2.0,'x')");
      db.execute(
          "UPDATE shots SET selectedTakeId='$takeId', videoPath='$rel', videoStatus='done' WHERE id='${spec.$1}'");
    }

    // 合成并等待
    await engine.composeEpisode('e');
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    String status = '';
    while (DateTime.now().isBefore(deadline)) {
      status = db.select("SELECT composeStatus FROM episodes WHERE id='e'")
          .first['composeStatus'] as String;
      if (status == 'done' || status == 'failed') break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final err = db.select("SELECT composeError FROM episodes WHERE id='e'")
        .first['composeError'];
    expect(status, 'done', reason: '合成失败: $err');

    final rel = db.select("SELECT composedPath FROM episodes WHERE id='e'")
        .first['composedPath'] as String;
    final out = File(media.absPath(rel));
    expect(out.existsSync(), isTrue);
    expect(out.lengthSync(), greaterThan(10 * 1024),
        reason: '产出 mp4 过小: ${out.lengthSync()}B');
    engine.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
