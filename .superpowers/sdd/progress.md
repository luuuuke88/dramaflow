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
Task 15: complete (进度文档改为 v0.4 assistant 降级版现状; ES-DSL/JS执行/多层监督/向量RAG 标注已移除; grep 命中9处; docs测试3测绿)

# ToonFlow Core Parity C2（plan: docs/superpowers/plans/2026-07-10-c2-prompt-packs-and-provenance.md）
C2 Task 1: complete (commits 28bb476..7e05a6c; 23 focused tests green; analyze clean; independent re-review approved)
C2 Task 2: complete (commits febd8e8..9bd1322; deterministic source resolution; focused tests green; analyze clean; independent re-review approved)
C2 Task 3: complete (commits 64d7dc6..4ec713d; queue task carries deterministic source unions plus per-target request traces without raw prompt text; private instruction payload is local-only and fails closed when missing or hash-mismatched; independent final re-review approved)
C2 completion gate: complete (final code 4ec713d plus tamper regression follow-up; focused prompt tests green; full suite, analyze, and macOS debug build green before the review follow-up; C3 boundary scan clean)

# ToonFlow Core Parity C3（plan: docs/superpowers/plans/2026-07-10-c3-seedance-capability-video.md）
C3 Task 1: complete (commits c97bc14..fc30a4c; explicit capability parser/request fingerprint and conservative Seedance profiles; 28 focused tests green; analyze clean; task re-review accepted. Cross-task gate: Task 4 must route runtime video submission through this validator.)
C3 Task 2: complete (074b466; v10 additive request/upstream storage, opt-in cold-start recovery, versioned per-shot controls, and effective prompt provenance; combined review's runtime integration finding resolved by Task 4.)
C3 Task 3: complete (5218473; typed Seedance submit/poll/cancel, kind-safe binding resolution, protocol-correct image/video/audio references, and Bearer-prefix regression coverage; combined review's runtime integration finding resolved by Task 4.)
C3 Task 4: complete (853e54d; project-model request build/preflight, persisted accepted IDs, no-resubmit cold recovery, upstream cancellation plus race protection, assistant/workbench same path; full 536 tests, analyze, macOS debug build green; independent review found no Critical/Important issues.)

# ToonFlow Core Parity C4（plan: docs/superpowers/plans/2026-07-11-c4-production-dependencies.md）
C4 Task 1: complete (62e2f16; additive v11 dependency-state table, source hashes, stale propagation from plan/table/script and asset-link updates; focused tests, analyze, full Flutter suite green; independent task reviewer unavailable because the local Codex agent quota was exhausted, controller performed diff review.)
C4 Task 2: complete (736db34; optional text model templates preserve strict C3 video behavior, C4 stages have mobile/desktop defaults, queue/policy/resolver/settings registration; focused tests, analyze, full Flutter suite green; independent task reviewer unavailable because the local Codex agent quota was exhausted, controller performed diff review.)
C4 Task 3: complete (director-plan task snapshots project script hash, resolves the documented prompt stack, records provenance without raw script text in task JSON, strips think blocks, and refuses missing/stale input before gateway submission; focused tests, analyze, full Flutter suite green; independent task reviewer unavailable because the local Codex agent quota was exhausted, controller performed diff review.)
C4 Task 4: complete (76f1167; storyboard-table generation snapshots plan/script/assets, records ordered provenance without raw source text, stores editable Markdown, and marks structured shots stale; focused tests, analyze, and full Flutter suite green.)
C4 Task 5: complete (strict Markdown table parser; table-authoritative shot metadata; pre/post-provider source and existing-output race guards; validated savepoint replacement with rollback; reusable media protection; 574 full tests and analyze green; independent re-review Ready.)
C4 Task 6: complete (dependency-aware plan/table/storyboard controls; stale badges; replacement then money confirmations; task labels and zh/en/ja copy; script changes invalidate the director plan; 580 full tests, analyze, and macOS debug build green; independent re-review Ready.)
