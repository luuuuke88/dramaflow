// P3 E2E：剧本→分镜（tool-calling 真跑）+ 首帧图批量生成（真实生图）。
// 运行：dart run tool/e2e_storyboard.dart
import 'dart:io';

import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';

Future<void> main() async {
  final tmp = Directory.systemTemp.createTempSync('df_e2e_sb_');
  final engine = await Engine.boot(dataDir: tmp.path, isMobile: false);
  try {
    final projectId = engine.addProject(
        projectType: 'novel', name: 'P3冒烟', artStyle: '国风水墨', videoRatio: '16:9');
    final scriptId = engine.addScript(
      projectId: projectId,
      name: '第一集',
      content: '林朝雪拔剑出鞘，剑光如雪。他望向远方的寒山，白衣猎猎，转身离去。',
    );
    stdout.writeln('[p3] 分镜生成中…');
    final taskId = engine.generateStoryboards(projectId, scriptId);
    final deadline1 = DateTime.now().add(const Duration(minutes: 5));
    String state = '';
    while (DateTime.now().isBefore(deadline1)) {
      state = (await engine.projectJobs(projectId))
          .firstWhere((t) => t.id == taskId)
          .state;
      if (state == 'success' || state == 'failed') break;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    if (state != 'success') throw StateError('分镜生成失败: $state');
    final shots = engine.storyboards(scriptId);
    stdout.writeln('[p3] ✅ 分镜生成 ${shots.length} 个');
    for (final s in shots) {
      stdout.writeln('   - S${s.index}: ${s.prompt} (轨:${s.track})');
    }
    if (shots.isEmpty) throw StateError('分镜为空');

    stdout.writeln('[p3] 首帧图生成中（可能数分钟）…');
    final imgTaskId = engine.batchGenerateStoryboardImages(
        projectId, shots.map((s) => s.id).toList(),
        compulsory: true);
    final deadline2 = DateTime.now().add(const Duration(minutes: 15));
    while (DateTime.now().isBefore(deadline2)) {
      state = (await engine.projectJobs(projectId))
          .firstWhere((t) => t.id == imgTaskId)
          .state;
      if (state == 'success' || state == 'failed') break;
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    final done = engine.storyboards(scriptId).where((s) => s.state == sbDone).length;
    stdout.writeln('[p3] 首帧图完成 $done/${shots.length}（任务状态=$state）');
    for (final s in engine.storyboards(scriptId)) {
      stdout.writeln('   - S${s.index}: state=${s.state} file=${s.filePath}');
    }
    if (done == 0) throw StateError('首帧图全部失败');
    stdout.writeln('[p3] ✅ 全链通过（剧本→分镜→首帧图）');
  } finally {
    engine.dispose();
    tmp.deleteSync(recursive: true);
  }
  exit(0);
}
