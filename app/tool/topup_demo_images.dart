// 演示项目首帧图补齐：populate_demo 的 20 分钟等待窗口对 26 张真实图片生成
// 太短（每张 ~195s），只完成了 8/26。本脚本对指定项目内所有尚未完成首帧图的
// 分镜重新入队生成，给足 120 分钟，把演示项目补成完整全链。
// 运行：cd app && dart run tool/topup_demo_images.dart [projectId]
import 'dart:io';

import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';

Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME']!;
  final dataDir =
      '$home/Library/Containers/com.dramaflow.dramaflow/Data/Documents/dramaflow';
  final projectId = args.isNotEmpty ? int.parse(args.first) : 2;
  final engine = await Engine.boot(dataDir: dataDir, isMobile: false);
  try {
    // boot 已做冷启动恢复：把上次被 dispose 打断、滞留在"生成中"的分镜标记为失败，
    // 这里再统一重生成。
    final pending = <int>[];
    for (final script in engine.scripts(projectId)) {
      for (final sb in engine.storyboards(script.id)) {
        if (sb.state != sbDone) pending.add(sb.id);
      }
    }
    stdout.writeln('[topup] 项目 #$projectId 待补首帧图分镜 ${pending.length} 个');
    if (pending.isEmpty) {
      stdout.writeln('[topup] ✅ 已全部完成，无需补齐');
      return;
    }
    engine.batchGenerateStoryboardImages(projectId, pending, compulsory: true);

    final deadline = DateTime.now().add(const Duration(minutes: 120));
    while (DateTime.now().isBefore(deadline)) {
      if (!engine.queue.hasActiveTask('storyboard_image_generation',
          projectId: projectId)) {
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 10));
    }

    var done = 0;
    var total = 0;
    for (final script in engine.scripts(projectId)) {
      final sbs = engine.storyboards(script.id);
      total += sbs.length;
      done += sbs.where((s) => s.state == sbDone).length;
    }
    stdout.writeln('[topup] ✅ 首帧图完成 $done/$total 个');
  } finally {
    engine.dispose();
  }
  exit(0);
}
