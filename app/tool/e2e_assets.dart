// P2 E2E：真实润色 + 真实生图（需 azt @8787）。运行：dart run tool/e2e_assets.dart
import 'dart:io';

import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/manuals.dart';

Future<void> main() async {
  final tmp = Directory.systemTemp.createTempSync('df_e2e_assets_');
  final engine = await Engine.boot(dataDir: tmp.path, isMobile: false);
  try {
    engine.saveVisualManual(name: '国风水墨', data: {
      for (final k in visualManualKeys)
        k: k == 'art_character'
            ? '你是角色视觉提示词专家。输出一段英文逗号分隔的角色图提示词，水墨国风，不要解释。'
            : '$k 占位',
    });
    final projectId = engine.addProject(
        projectType: 'novel', name: 'P2冒烟', artStyle: '国风水墨');
    final assetId = engine.addAsset(
        projectId: projectId,
        type: 'role',
        name: '林朝雪',
        describe: '十八岁少年剑客，白衣，背负长剑，眉目清冷');
    stdout.writeln('[p2] 润色中…');
    final prompt = await engine.polishAssetPrompt(assetId);
    stdout.writeln('[p2] 润色结果: ${prompt.substring(0, prompt.length > 120 ? 120 : prompt.length)}');
    if (prompt.trim().isEmpty) throw StateError('润色为空');

    stdout.writeln('[p2] 生图中（gpt-image-2，可能数分钟）…');
    engine.generateAssetImages(
        projectId, [(assetsId: assetId, refImageBase64: null)],
        resolution: '1K');
    final deadline = DateTime.now().add(const Duration(minutes: 15));
    while (DateTime.now().isBefore(deadline)) {
      final img = engine.assetImages(assetId).last;
      if (img.state == stateDone) {
        final f = File(engine.mediaAbsPath(img.filePath!));
        stdout.writeln('[p2] ✅ 生图完成 ${img.filePath} (${f.lengthSync()}B)');
        if (f.lengthSync() < 10 * 1024) throw StateError('图片过小');
        exit(0);
      }
      if (img.state == stateFailed) {
        throw StateError('生图失败: ${img.errorReason}');
      }
      await Future<void>.delayed(const Duration(seconds: 10));
    }
    throw StateError('生图超时');
  } finally {
    engine.dispose();
  }
}
