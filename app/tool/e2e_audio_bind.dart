// P4 E2E：配音 LLM 自动匹配（真跑，需 azt @8787）。
// 运行：dart run tool/e2e_audio_bind.dart
import 'dart:io';

import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/audio_bind.dart';
import 'package:dramaflow/src/engine/engine.dart';

Future<void> main() async {
  final tmp = Directory.systemTemp.createTempSync('df_e2e_audio_');
  final engine = await Engine.boot(dataDir: tmp.path, isMobile: false);
  try {
    final projectId = engine.addProject(projectType: 'novel', name: 'P4冒烟');
    final role1 = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: '十八岁少年剑客，清冷孤傲');
    final role2 = engine.addAsset(
        projectId: projectId, type: 'role', name: '沈青崖', describe: '寒山派掌门，年过五旬，威严持重');
    engine.addAsset(
        projectId: projectId, type: 'audio', name: '清亮少年音', describe: '音色清澈明亮，语速偏快');
    engine.addAsset(
        projectId: projectId, type: 'audio', name: '低沉长者音', describe: '音色低沉浑厚，语速沉稳');

    stdout.writeln('[p4] 配音匹配中…');
    final taskId = engine.batchBindAudio(projectId, [role1, role2]);
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    String state = '';
    while (DateTime.now().isBefore(deadline)) {
      state = (await engine.projectJobs(projectId))
          .firstWhere((t) => t.id == taskId)
          .state;
      if (state == 'success' || state == 'failed') break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (state != 'success') throw StateError('配音匹配失败: $state');

    final bindings = engine.roleAudioBindings(projectId);
    for (final b in bindings) {
      stdout.writeln('   - ${b.roleName} → ${b.audioName ?? "(未绑定)"}');
    }
    if (bindings.any((b) => b.audioAssetId == null)) {
      throw StateError('存在未绑定角色');
    }
    stdout.writeln('[p4] ✅ 配音自动匹配通过');
  } finally {
    engine.dispose();
    tmp.deleteSync(recursive: true);
  }
  exit(0);
}
