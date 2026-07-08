// P5 E2E：Assistant 多工具自由选择真实调用（需 azt @8787）。
// 运行：dart run tool/e2e_agent.dart
import 'dart:io';

import 'package:dramaflow/src/engine/assistant_chat.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/scripts.dart';

Future<void> main() async {
  final tmp = Directory.systemTemp.createTempSync('df_e2e_agent_');
  final engine = await Engine.boot(dataDir: tmp.path, isMobile: false);
  try {
    final projectId = engine.addProject(projectType: 'novel', name: 'P5冒烟');
    // 注意：不用"导入章节+让 Agent 生成事件"做验收场景——addNovels 会
    // 通过 onNovelsAdded 钩子自动触发事件生成（照抄 ToonFlow 的"导入即生成"
    // 行为），真实 LLM 调用会在 Agent 的第二轮之前就跑完，导致"没有需要
    // 处理的章节"这个完全正确但看起来像没生效的输出。改用剧本+资产提取，
    // 该阶段没有任何自动触发钩子，能干净地证明 Agent 工具调用确实新增了任务。
    engine.addScript(
        projectId: projectId, name: '雪夜', content: '林朝雪拔剑而立，望向雪夜中的来客。');

    stdout.writeln('[p5] 询问进度…');
    await engine.sendAssistantMessage(
      projectId,
      '现在项目进度如何？',
      family: assistantFamilyScript,
      autoMode: false,
    );
    for (final m in engine.assistantMessages(
      projectId,
      family: assistantFamilyScript,
    )) {
      stdout.writeln(
          '   [${m.role}${m.toolName != null ? ":${m.toolName}" : ""}] '
          '${m.content.substring(0, m.content.length > 80 ? 80 : m.content.length)}');
    }
    final afterStatus = engine.assistantMessages(
      projectId,
      family: assistantFamilyScript,
    );
    if (afterStatus.length < 2) throw StateError('未收到助手回复');

    stdout.writeln('[p5] 请求提取资产…');
    await engine.sendAssistantMessage(
      projectId,
      '帮我把这个剧本的角色道具场景提取一下',
      family: assistantFamilyScript,
      autoMode: false,
    );
    var afterExtract = engine.assistantMessages(
      projectId,
      family: assistantFamilyScript,
    );
    if (afterExtract.any((m) =>
        m.role == assistantRoleConfirm && m.confirmStatus == 'pending')) {
      await engine.confirmPendingAssistantAction(
        projectId,
        family: assistantFamilyScript,
        approve: true,
      );
      afterExtract = engine.assistantMessages(
        projectId,
        family: assistantFamilyScript,
      );
    }
    for (final m in afterExtract.skip(afterStatus.length)) {
      stdout.writeln(
          '   [${m.role}${m.toolName != null ? ":${m.toolName}" : ""}] '
          '${m.content.substring(0, m.content.length > 80 ? 80 : m.content.length)}');
    }
    final tasks = await engine.projectJobs(projectId);
    if (!tasks.any((t) => t.taskClass == 'asset_extraction')) {
      throw StateError(
          'Agent 未能正确调用 extract_assets 工具（任务表无 asset_extraction 记录）');
    }
    stdout.writeln('[p5] ✅ Agent 真实工具调用通过（任务表确认落库）');
  } finally {
    engine.dispose();
    tmp.deleteSync(recursive: true);
  }
  exit(0);
}
