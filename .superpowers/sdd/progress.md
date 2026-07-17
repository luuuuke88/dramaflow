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
C4 Task 7: complete (assistant generate_scripts delegates to the existing event-to-script queue; structured-shot assistant path is table-driven and refuses replacement; fake-provider C4 chain verifies source hashes and excludes credentials/raw prompt bodies from task JSON; 583 full tests, analyze, and macOS debug build green; independent re-review Ready.)

# C5 Episode Close And Real Acceptance（plan: docs/superpowers/plans/2026-07-11-c5-episode-close-real-acceptance.md）
C5 Task 1: complete (failed tasks retain their reason and become immutable history when retried; each retry is a new visible attempt with lineage metadata; private prompt payload moves atomically to the latest attempt; focused 46, full 583, and analyze green; independent reviewer could not complete because Codex quota was exhausted, controller completed transaction-boundary review.)
C5 Task 2: complete (accepted running Seedance candidates resume polling without submit; terminal failures and corrected prepared requests create one new candidate; uncertain submissions refuse retry; legacy tasks without videoIds retry only each track's latest failed candidate; successful retry selects a usable candidate; focused video tests, full 588, and analyze green; controller diff review.)
C5 Task 3: complete (shared transition/filter allowlists validate engine export, default composer, and AVFoundation channel wrapper; unknown effects fail before native export rather than silently dropping; focused composition/platform tests, full 592, and analyze green; controller diff review.)
C5 Task 4: complete (macOS AVFoundation Engine-to-MP4 integration test covers reverse-created then reordered selected candidates, bound narration, fade, inspectable MP4 output, and registered clip asset; discovered and corrected the fade route from the hanging Core Image callback path to existing AVFoundation layer instructions on both macOS and iOS; native integration, full Flutter suite, analyze, and macOS debug build green.)

# W0 基线审计（plan: docs/superpowers/plans/2026-07-18-w0-parity-baseline-audit.md）
起点 BASE: dca83dd（develop）；worktree ../dramaflow-w0 分支 w0-audit；Task 6-11 串行（共写 master-checklist.md）

# P0 供应商预检（plan: docs/superpowers/plans/2026-07-18-p0-provider-preflight.md）
起点 BASE: dca83dd（develop）；worktree ../dramaflow-p0 分支 p0-preflight；Task 4/5（azt 冒烟+真实调用）主会话执行，不派子代理
W0 Task 1: complete (5941dea; 脚本与简报逐字一致经程序化 diff 验证; manifest 473+249 文件哈希结构自洽; 验证 1.1.8/9c4cb0e/true/true dirty=false; review clean. Minor×2: 实现报告行数记账有误/walk 对 symlink 与不可读文件静默跳过——基线若引入 symlink 会少计,留意后续)
P0 Task 1: complete (e2b2272; 两脚本与简报字节级一致(独立diff验证); 日志路径穷举证明无 headers/body/query 泄漏通道; node --check 绿; review clean. Minor×4(均简报代码固有,非实现者裁量): hop-by-hop 头透传/Buffer 分块 UTF-8 拼接隐患/入站 req 无 error handler/实现报告漏述 mark 日志形态)
P0 Task 2 中途发现: 自测门抓到计划参考代码 bug——fake_upstream 用原始 req.url 路由,带 query 的提交 POST 404(自测故意带 ?debug=1 验证代理去 query)。属计划自身缺陷,非实现者错误;修复卡已派(pathOnly 路由+计划文档同步修正)
W0 Task 2: complete (797e56d; 脚本与简报逐字一致(diff -u 0差异); 提交产物经叶级遍历+正则扫描零秘密值; 13 vendors 全部通过白名单结构断言; selftest 独立复跑 PASS; review clean. Minor×3: volcengineSd2 是当前唯一实测秘密键排除路径的 vendor/源数据有 id="null" 字符串 vendor(下游黑盒会话留意)/modelPrompts 投影因表空未实测)
P0 Task 2: complete (d3a9214+9a35bff; 自测抓到并修复假上游 query 路由 bug(计划文档同步修正,两处 hunk 字节一致); selftest 13 断言全 PASS; sentinel=代理文件 SHA-256 落盘; 审查逐字节核验 approved. Minor×2: 报告文件缺原 BLOCKED 记录文本/phase-2 未复查假上游 pid(简报代码固有))
W0 Task 3: complete (cc0f20f; 538 项库存,15 类计数全部被审查者独立对源复算一致,零漏生成; 脚本与简报逐字一致; review approved. 简报级发现×2(控制器裁定,不改产物): ①items 无 kind 字段(简报散文与代码自矛盾)→下游一律按 id.split(':')[0] 推导,Task4 校验器本就如此; ②web.route:/detail 是注释掉的死路由(正则不剥注释)→Task 6 审计时按"不适用+死路由理由"进 inventory-na.md,不得费力审计. Minor: ToonFlow 源里多个" copy"文件属上游 dev 残留,如实收录)
W0 Task 4: complete (d6914c8; 三文件与简报字节级一致(diff 验证); TDD序列538→537→538在独立scratch副本复现; 五条校验器语义逐一执行验证(覆盖列索引/NA缺理由error+exitCode穿透/未知id仅WARN/孤儿列表+exit1/全覆盖OK+exit0); review approved. Minor: 简报参考实现对"行首缺|"边界未防御,当前0数据行未触发,Task6+写真实行后留意)
P0 Task 3: complete (151bd91; 两用例语义经引擎源码交叉验证为真(video_track.dart:936-963 switch路由 uncertain→_throwUncertainVideoRetry / accepted+终态失败→新候选); 授权偏差仅4个extension import+dart format换行,逐行核验; 默认套件零副作用经目录mtime前后比对独立复现; analyze 0 issues; review approved. Minor: 报告措辞不够精确(非代码问题)
P0 Task 4: complete (无提交,纯服务冒烟); azt 文本 2.2s 返回OK; 图片 b64_json 长度1171768(>10000门槛) 耗时26.7s,远快于AGENTS.md历史195-342s记录(模型/负载差异,非异常); /tmp/p0-azt-smoke.txt 留证
W0 Task 5: complete (f078961; 脚本与简报 SHA-256 逐字一致; 夹具自测(mktemp隔离,含二次隔离阻断/restore丢弃隔离期污染数据验证)全过; 真实目录 backup+verify(1144文件,1项目)只读证据链完整,LIVE 未被触碰; review approved. Important×2(简报锁定设计固有,休眠中): ①restore 靠 $ASIDE 是否存在判隔离态,无会话/时间戳校验——若某次 isolate 后会话被遗弃、真实新数据又在 $LIVE 长出来,后续 restore 会先 rm -rf 掉新数据再覆盖旧快照;②assert_quit 只精确匹配进程名 ToonFlow,抓不到孤儿 Helper/Renderer 子进程. **硬性前置纪律**:今后任何审计单元(Task 6-10)如果真的需要调用 isolate(而不只是 backup/verify),必须先手动确认 `$HOME/Documents/dramaflow-w0-blackbox/live-aside` 不存在(证明没有遗弃的隔离态)且用 `ps aux | grep -i toonflow` 确认无残留 Helper 进程,再调用,不得默认脚本自身的检查已经足够
P0 Task 5 尝试1: 真实调用已发生(exactly-once纪律成立,proxy日志仅1次POST)。供应商 HTTP 400 拒绝(10.99s),o_video落 uncertain+errNetwork,o_tasks落 failed。根因诊断:测试参考图 864x1821(比例0.475)与请求 videoRatio=9:16(比例0.5625)不匹配——测试夹具问题非引擎/协议缺陷。GATE1未过,脚本按设计正确停手未进入RESTART/resume,未重试。已征得用户授权对同一预检做第二次真实尝试(裁剪出精确9:16参考图,原图未动,harness路径更新)。尝试2 进行中。
P0 Task 5: 真实调用已完成两次(均用户授权),均未达成生成成功。尝试1(原图,比例0.475 vs 请求9:16=0.5625)→400。假设比例不符,征得用户授权重试。尝试2(裁剪至精确9:16)→仍400,假设证伪。两次均恰好1次POST(代理日志核验),GATE1(硬杀点到达)在两次都正确拒绝进入RESTART/resume,未发生任何重复提交。根因未知(代理设计不记录响应体+引擎错误处理只存dio通用消息,真实拒绝原因永久丢失)。经用户明确决策(本轮对话):视频供应商联调问题暂搁置不再排查。断言 2/6 PASS(提交次数=1/候选行数=1 两项安全性断言成立), 4/6 FAIL(无成功生成)。P0 期间零产品代码改动。已撤销脚手架路径的图片试验性改动,harness 回到已提交状态。证据文档 f3817eb 如实记录全过程,防泄漏自检两次假阳性(task-/acceptThenFail 均非密钥)人工核实排除。
W0 Task 6a: complete (4c56571+f4d1fba; 13顶层页面/路由,7绿+3部分实现+4不适用; 独立审查7/13逐项开源码文件核实claim真实性+N/A双条件逐一核验; approved但2条Important已修正: /test N/A补充"仅满足无价值prong,不满足平台特有prong,需W0范围确认时用户追认"说明; W6-WORKBENCH-001(script项目隐藏novelOnly项分支)补审查标注挂已知测试缺口而非静默维持无保留绿). production 页正确封顶部分实现(有widget测试但画布手感是W1开放里程碑,判绿会与W1自相矛盾)——评审确认这是正确判断不是过度保守。
W0 Task 6b: complete (6079e3a; 20行,11绿+8部分实现+1缺失(poster节点真缺失,旧清单未发现的新发现); 独立审查9/20逐项开双侧源码+测试体核实,poster用grep独立确认零实现,NLE特性数量(6vs3转场/10vs4滤镜/8vs0特效)逐一核对源码确认; approved,3条Minor(数字标注误差)已修正commit 4843592). 
W0 Task 6c: complete(内容层面; 6项,1绿(removeLine)+4部分实现+1不适用(results.vue死代码)). **流程事故**:我在6c子代理仍在编辑同一 master-checklist.md 时对该文件做了自己的修正提交(4843592),导致6c的5行W6C-*内容被并发扫入4843592而非6c自己的提交a1b7420(git -S pickaxe确认)。内容验证无损失(5行齐全/orphan gate对6c范围EMPTY/6c自己commit仅剩inventory-na.md 1行)——纯提交归属记录不准,不重写历史,如实记录。**教训**:今后在 dramaflow-w0 worktree 对 master-checklist.md/inventory-na.md 的任何自行编辑,必须等所有并行审计子代理(当前6d/6e在飞)确认落盘提交后再动手,不得假设"小修正"可以插队并发。
QA真实全链路修复(storyboard boolean parser): complete(82a7f07 fix + f462e92 test harness; review approved 19/19测试独立复核). 真实bug: base prompt(engine.dart)只命名"生成首帧"列从不规定取值格式,解析器又只认硬编码枚举,真实调用gpt-5.6-luna时输出了解析器不认的token导致整张分镜表报废。双重修复:解析器宽松匹配+无法识别时降级默认true(不再炸整表)+提示词加约束。已用真实全链路重跑验证修复生效(结构化分镜阶段从失败→23个镜头成功)。**跟进项(评审标注非阻塞)**:兜底逻辑是精确token匹配非子串,LLM若写含"不需要"的完整长句(非精确token)仍会掉入默认true分支触发非预期付费生图;建议后续给false分支加子串包含判断或对fallback分支加日志观察真实分布。
