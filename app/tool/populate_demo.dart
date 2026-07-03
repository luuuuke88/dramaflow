// 演示项目填充 v3（真实 LLM）：向 App 实际数据目录写入《剑出寒山》演示项目，
// 全链：章节导入 → 事件生成 → 剧本 → 资产提取。
// 运行：cd app && dart run tool/populate_demo.dart
// App 数据目录 = ~/Library/Containers/com.dramaflow.dramaflow/Data/Documents/dramaflow
import 'dart:io';

import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/events.dart';
import 'package:dramaflow/src/engine/novel.dart';
import 'package:dramaflow/src/engine/novel_parse.dart';
import 'package:dramaflow/src/engine/scripts.dart';

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
    final ok = engine
        .novelEventState(novelIds)
        .where((s) => s.eventState == 1)
        .length;
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
    stdout.writeln(
        '[populate] 剧本 ${scripts.length} 个，资产 ${engine.assetOptions(projectId).length} 个');
    stdout.writeln('[populate] ✅ 完成');
  } finally {
    engine.dispose();
  }
  exit(0);
}
