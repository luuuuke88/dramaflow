// P1 E2E 冒烟（真实 LLM，需 azt 运行于 127.0.0.1:8787）：
// 临时目录起引擎 → 建项目 → 导入 demo_novel.txt（parseNovel）→ 自动事件生成（真跑）
// → 手动建剧本 → 提取资产（真跑 tool-calling）→ 断言状态与落库。
// 运行：cd app && dart run tool/e2e_smoke.dart
import 'dart:io';

import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/events.dart';
import 'package:dramaflow/src/engine/novel.dart';
import 'package:dramaflow/src/engine/novel_parse.dart';
import 'package:dramaflow/src/engine/scripts.dart';

Future<void> main() async {
  final tmp = Directory.systemTemp.createTempSync('df_e2e_');
  stdout.writeln('[e2e] dataDir=${tmp.path}');
  final engine = await Engine.boot(dataDir: tmp.path, isMobile: false);

  try {
    final projectId = engine.addProject(
      projectType: 'novel',
      name: 'E2E冒烟',
      intro: '端到端验证',
      type: '玄幻',
      videoRatio: '16:9',
      imageQuality: '1K',
    );
    stdout.writeln('[e2e] 项目 #$projectId');

    // 1. 导入章节（自动触发事件生成）
    final text = File('tool/demo_novel.txt').readAsStringSync();
    final chapters = flattenParsedNovel(parseNovel(text)).take(2).toList();
    if (chapters.isEmpty) {
      throw StateError('demo_novel.txt 未解析出章节');
    }
    final novelIds = engine.addNovels(projectId, chapters);
    stdout.writeln('[e2e] 导入章节 ${novelIds.length} 个，事件生成中…');

    // 2. 等事件（真 LLM）
    await _waitUntil(() {
      final states = engine.novelEventState(novelIds);
      return states.length == novelIds.length;
    }, timeout: const Duration(minutes: 8), label: '事件生成');
    final eventStates = engine.novelEventState(novelIds);
    final okEvents = eventStates.where((s) => s.eventState == 1).length;
    stdout.writeln('[e2e] 事件完成：$okEvents/${novelIds.length} 成功');
    for (final s in eventStates) {
      stdout.writeln('   - #${s.id} state=${s.eventState} '
          'event=${(s.event ?? '').split('\n').first}');
    }
    if (okEvents == 0) {
      throw StateError('事件生成全部失败: ${eventStates.first.errorReason}');
    }
    final events = engine.events(projectId);
    stdout.writeln('[e2e] o_event 行数=${events.total}');
    if (events.total == 0) throw StateError('事件未落表');

    // 3. 建剧本 → 提取资产（真 LLM tool-calling）
    final scriptIds = <int>[];
    for (final (i, chapter) in chapters.indexed) {
      scriptIds.add(engine.addScript(
        projectId: projectId,
        name: '第${i + 1}集',
        content: chapter.chapterData,
      ));
    }
    engine.extractAssets(scriptIds, projectId);
    stdout.writeln('[e2e] 提取资产中…');
    await _waitUntil(() {
      final states = engine.scriptExtractState(scriptIds);
      return states.length == scriptIds.length;
    }, timeout: const Duration(minutes: 8), label: '资产提取');
    final scripts = engine.scripts(projectId);
    final okScripts =
        scripts.where((s) => s.extractState == 1).length;
    stdout.writeln('[e2e] 提取完成：$okScripts/${scripts.length} 成功');
    for (final s in scripts) {
      stdout.writeln(
          '   - ${s.name} state=${s.extractState} assets=${s.relatedAssets.map((a) => a.name).join('、')}');
    }
    if (okScripts == 0) {
      throw StateError('资产提取全部失败: ${scripts.first.errorReason}');
    }
    final assetCount = engine.assetOptions(projectId).length;
    stdout.writeln('[e2e] o_assets 行数=$assetCount');
    if (assetCount == 0) throw StateError('资产未落库');

    stdout.writeln('[e2e] ✅ 全链通过（章节→事件→剧本→资产）');
  } finally {
    engine.dispose();
    tmp.deleteSync(recursive: true);
  }
  exit(0);
}

Future<void> _waitUntil(bool Function() done,
    {required Duration timeout, required String label}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (done()) return;
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  throw StateError('$label 超时（${timeout.inMinutes} 分钟）');
}
