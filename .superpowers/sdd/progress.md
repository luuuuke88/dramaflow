# v0.4 收敛期执行台账（plan: docs/superpowers/plans/2026-07-08-v0.4-convergence.md）
起点 BASE: e5169fe
排期修正: T5 严格在 T3 合入后（同文件 workbench_screen.dart）
Task 1: complete (commit 03823a4, review clean; Minor×3: 测试setUp重复/未close db/未知taskClass+destructiveKey组合分支未测)
Task 4: complete (commit HEAD, 21 基线+全量904绿; 待 T6 等价性矩阵二次验证)
T9先于T8执行（T8分发引用笔记API），接口不变
Task 9: complete (T8 前置，6 测绿)
Task 2: complete (commit f1304f3, review clean; Minor×3: autoMode路径无helper级测试/遮罩关闭路径未测/开关即时生效与同区保存钮不一致)
Task 3: complete (8个花钱UI入口接闸; analyze绿; 全量938测绿; 从Claude失败worktree恢复并合入)
Task 8: complete (12测绿; AssistantAction 增 taskClass 字段供 T10 查闸; T11 先于 T10 执行——T10 系统提示词依赖 assistantSkillContexts)
Task 11: complete (先于T10, 8测新增938全绿; 旧文件未动)
Task 10: complete (assistant_chat 对话循环+确认挂起; 7测新增945全绿; 旧文件未动)
Task 12: complete (UI切到 assistant_*; 去除 custom-JS/监督/RAG 入口; 项目笔记走 project_notes; analyze绿; 全量931测绿; 旧 agent.dart 未动)
Task 13: complete (删除旧 agent/agent_memory/agent_orchestrator/agent_skills/agent_stage_registry + 旧 agent_test; 旧符号扫描仅剩 db.dart schema 定义 o_memoryVector; assistant_* + project_notes 共 1395 行; analyze绿; 全量479测绿)
Task 5: complete (workbench 切分新尾段保留选中; 批量裁剪忽略选中自撞; 拖拽 helper 单手势复用时间线快照; workbench 80测绿; analyze绿; 全量480测绿)
Task 6: complete (新增时间线单/批量等价性矩阵; 发现并修复 resizeTimelineClipsEndRipple 相邻选中裁尾时下游按单片段缩短量重复叠加的净位移 bug; timeline定向31测绿; analyze绿; 全量490测绿)
Task 7: complete (补 policy_confirm UI 层 autoMode 矩阵: 花钱自动放行、破坏自动仍确认; project_notes 中文检索用例已覆盖计划项并随本卡验收; 定向15测绿; analyze绿; 全量492测绿)
Task 14: complete (workbench 两处 _toast 收敛为共享 SnackBar helper; 候选生成中/失败状态改用 StatusChip; grep _toast=0; workbench 80测绿; analyze绿; 全量492测绿)
