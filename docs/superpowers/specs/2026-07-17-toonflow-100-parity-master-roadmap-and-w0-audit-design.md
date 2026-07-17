# ToonFlow 100% 复刻总路线与 W0 审计规范

状态：总路线（meta-spec）。本文档只批准 W0 与 P0 进入实施，并设立 L0 许可证/分发阻塞门；W1–W4 须在 W0 总清单经用户确认、且 L0 过门后，各自另写独立 spec 与 plan。

本 spec 取代 `2026-07-10-toonflow-core-parity-convergence-design.md` 中与"核心工作流即可"相关的边界决策（详见第 10 节 Decision Log）。该收敛 spec 的其余工程约束（凭证不落 SQLite、任务恢复语义、原生合成路线等）继续有效。

## 1. 背景与目标

DramaFlow 现状：页面级对照清单 11 个条目中 9 个 Verified、2 个 Partial（多轨工作台与 Agent 页）；C5 真机验收从未执行；视频生成链路（Seedance）从建仓起零实测。

用户决策（2026-07-17）：目标从"核心工作流复刻"升级为对 ToonFlow 的 **100% 复刻**，并要求：

- 参照物为本地 ToonFlow 1.1.8 整体：`Toonflow-app`（Electron 后端与运行资源）+ `Toonflow-web`（前端源码，Vue）+ 打包版 `ToonFlow.app`（用户实际在用的行为参照）。
- 达标标准为**功能等价**，不要求像素级 UI 一致（见第 2 节精确定义）。
- 平台先 macOS 单平台达标，iOS/Android/Web/Windows 之后逐个跟进。
- 开发期间用户**零参与测试**；全部缺口补齐并经我方自验证后，用户只做一次收尾总验收。
- 无限画布必须定可测量的性能/手感硬指标（用户对旧 Electron 版画布的核心不满，Flutter 版不得重蹈覆辙）。

## 2. "100%" 的定义

**100% = 固定基线下的用户可观察功能等价。**

- 基线：本地 ToonFlow v1.1.8（`Toonflow-app` + `Toonflow-web` + 打包 `ToonFlow.app`），经第 3 节流程冻结。
- 等价判定只看**用户可观察行为**：某个操作在 ToonFlow 能做到什么效果，在 DramaFlow 就要能做到不弱于它的效果。
- 明确**不**要求：内部代码与架构一致、复制 Electron 特有实现、复制历史 bug、复制无用户价值的内部实现细节。DramaFlow 可以（且应当）使用更适合 Flutter 的实现。
- 允许"已验证更优"，但不得由实施者主观认定：必须附对照用例（同一操作在 ToonFlow 打包版与 DramaFlow 中的行为对比记录），并逐点确认原能力没有丢失；缺任一项证据按"部分实现"处理。

## 3. 基线冻结（W0 产物之一）

ToonFlow 的前端源码不在 `Toonflow-app` 内：`Toonflow-app/src` 只含后端（routes / agents / socket / middleware 等），页面、画布与 WebAV/NLE 的源码在独立 git 仓库 `Toonflow-web`（Vue），`Toonflow-app/data/web/index.html` 是其打包产物（约 26MB 单文件）。基线必须同时冻结三者：

- `Toonflow-app`（非 git 仓库）：记录版本 `1.1.8`（`package.json`）；生成源码 SHA-256 清单，覆盖 `src/`、`data/`（vendor、modelPrompt、skills、web 等资产目录）与 `package.json`，排除 `node_modules/` 与构建中间产物，但**包含**实际作为参照运行的 `dist/mac-arm64/ToonFlow.app` 资源哈希。清单落库为 `docs/parity/baseline-manifest.json`。
- `Toonflow-web`（git 仓库）：记录 commit（当前 `9c4cb0e`）与 dirty 状态，源码纳入审计输入。
- 对应关系声明：前端源码 commit 与打包 `data/web/index.html` 无构建指纹可严格对应，清单中同时记录两者哈希，并约定**行为歧义时以打包版 `ToonFlow.app` 的实际行为为仲裁**。
- 运行库能力冻结：Seedance 2.0 Mini 等能力存于运行库 `o_vendorConfig` 而非源码，额外生成**不含任何密钥**的 `docs/parity/baseline-runtime-capabilities.json`，冻结模型 ID、能力声明、提示词映射与供应商配置结构。该快照必须在任何黑盒验证会话（5.2）之前生成，避免运行打包版污染运行库配置。
- **原版能力与本地扩展分开标记**。本地非上游修改至少包括：`data/vendor/ima2.ts`、`data/vendor/azt.ts`、Seedance 2.0 Mini 运行时模型、`src/lib/fixDB.ts` 等本地修复（完整清单见仓库外 `aivideo/AGENTS.md`"Known Local Fixes"）。本地扩展同样在复刻范围内（用户实际在用），但清单中必须标注来源为"本地扩展"，不得混入"ToonFlow 原版"。
- 基线漂移处理：若基线内容变化导致 SHA-256 / commit 不匹配，必须显式重新冻结并 diff 说明变化，禁止无声吸收。审计期间不修改 `Toonflow-app` 与 `Toonflow-web`。
- 许可证事实（2026-07-18 已核实）：`Toonflow-app/LICENSE` 共 258 行 = Apache-2.0 正文 + **补充协议**——向两个及以上独立第三方分发/销售/提供本软件或衍生品须事先取得 HBAI-Ltd 书面商业授权（附分级定价表）；不得删除或修改 Toonflow 标识与版权信息；v1.0.8 前为 AGPL-3.0（带不追溯条款）。**不得按普通 Apache-2.0 处理**，处置见第 6 节 L0 门。

## 4. 里程碑结构

```text
W0  冻结基线 + 总对照清单 + 许可证审计   （只读审计，零实现改动）——本 spec 批准
P0  最小真实供应商预检                    （真实付费恰好一次 + 隔离失败演练）——本 spec 批准
L0  许可证与分发决策门                    （W0 证据 → 用户决策；未过门不开工 W1–W4）
W1  无限画布体验达标                      （待独立 spec）
W2  Agent 体系移植                        （待独立 spec）
W3  NLE 工作台补全                        （待独立 spec）
W4  长尾缺口清零                          （按批次，每批过审核门）
终  用户一次性收尾总验收                  （12 步真机流程 + 画布体验签字）
```

- W0 与 P0 可并行；L0 依赖 W0 的许可证审计产出，并**阻塞 W1–W4 全部实现工作**；W1–W3 顺序开工（画布是用户点名痛点，排最前）；W4 批次穿插但**每批必须独立过审核门**，不得零散混入 W1–W3 的分支。
- 需要用户参与的三个点（均为决策，不是测试）：① W0 完成后对总清单做一次**范围确认**；② L0 分发路径决策；③ 全部绿灯后的收尾总验收。

## 5. W0 审计规范（本次批准执行）

### 5.1 总对照清单

产物：`docs/parity/master-checklist.md`，进仓库持续维护，是"100%"的唯一法定定义。字段：

```text
ID | 模块/页面 | ToonFlow 源码证据 | 用户行为 | 数据依赖 | DramaFlow 实现证据 | 状态 | 验收方法 | 自动化测试 | 备注
```

状态枚举（六态）：

```text
未审计 / 缺失 / 部分实现 / 已验证等价 / 已验证更优 / 不适用
```

判定纪律：

- 只有**已验证等价 / 已验证更优 / 不适用**算绿。"部分实现"不算绿。
- DramaFlow 有代码但没有对应测试或运行证据的，最高只能标"部分实现"。
- "ToonFlow 源码证据"必须落到文件路径（必要时行号）；"用户行为"用一句话描述用户可观察效果；禁止只写"页面存在"这类无行为断言。
- "不适用"仅限 Electron/浏览器平台特有且在 macOS 原生形态下无对应用户价值的项，每条必须写理由。

### 5.2 审计方法

- 输入 = **静态源码审计 + 打包 App 黑盒验证**：静态侧为 `Toonflow-web` 前端源码与 `Toonflow-app` 后端源码及运行资源；黑盒侧为打包版 `ToonFlow.app`——凡源码歧义、行为存疑、或纯源码无法断定用户可观察效果的条目，直接运行打包版确认（由我方执行，不占用用户时间）。
- 先机械生成**库存清单（inventory）**，再归并为对照清单条目，库存维度至少包括：前端路由、页面、菜单与主要操作；HTTP 路由与 Socket 事件；Agent 工具（scriptAgent / productionAgent 及其 tools、`src/utils/agent/` 的 memory / embedding / skillsTools）；设置项、数据库表与默认数据；vendor、模型、提示词与技能资产；Electron IPC、文件导入导出、更新与平台功能。
- 每个审计单元：通读源码 → 提取用户可观察行为条目 → 对照 DramaFlow 现状（代码 + 测试）定状态。
- DramaFlow 侧证据优先引用现有测试文件；`docs/superpowers/progress/2026-07-04-page-parity-checklist.md` 作为线索输入，但其"Verified"结论不自动继承——按本 spec 的六态标准重判。

### 5.3 许可证审计（W0 内完成，供 L0 决策）

- 已核实事实（2026-07-18）：ToonFlow LICENSE 非普通 Apache-2.0（补充协议详见第 3 节）。DramaFlow 仓库根目录当前**无 LICENSE / NOTICE**，却已打包 ToonFlow 衍生资产：`app/assets/default_skills/toonflow_default_skills.zip`、`app/assets/default_prompts/toonflow_model_prompts.zip`。
- 审计任务：逐项梳理 DramaFlow 内所有源自 ToonFlow 的内容（提示词模板、画风包 `art_skills` / `story_skills`、技能文件、按源码行为移植的功能逻辑）及第三方资产（字体、图片、内置素材）的许可证与署名义务。
- 品牌条款核对："不得删除或修改 Toonflow 标识与版权信息"条款与改名产品 DramaFlow 的关系属法律判断，在审计中标注为**需专业意见项**，不自行下结论。
- 产物：`docs/parity/license-audit.md`——事实清单 + 义务清单 + L0 决策选项。本审计不构成法律意见。

### 5.4 W0 完成判定

- 基线清单（`baseline-manifest.json` + `baseline-runtime-capabilities.json`）已生成并提交。
- 库存清单（5.2）全部条目**要么映射到总清单条目 ID，要么标注有理由的 N/A**——不存在孤儿项。
- 总对照清单覆盖 ToonFlow 全部页面/路由/agent 工具面/资产面，无"未审计"残留。
- 许可证审计（`license-audit.md`）完成并给出 L0 决策选项。
- 用户完成一次范围确认（确认清单条目与"不适用"判定，可调整）。

## 6. L0：许可证与分发阻塞门（W1–W4 前置）

定位：W0 完成后、W1–W4 任何实现开工前的强制门。依据：ToonFlow 补充协议将"向 ≥2 独立第三方分发衍生产品"设为需书面商业授权，而 DramaFlow 的既定目标是可上架分发——继续大规模投入前必须先定分发路径，避免做完再拆。

- 门内产出：基于 5.3 审计，用户在以下选项中做出记录在案的决策：
  1. 联系 HBAI-Ltd 取得书面商业授权（或书面确认符合"永久免费/内部使用"场景）；
  2. 移除/替换全部 ToonFlow 衍生资产与受约束内容后再分发；
  3. 明确本项目仅个人使用、不对外分发（解除上架目标）。
- 无论选哪项：补齐仓库 `LICENSE` / `NOTICE` 与随包资产署名（Apache-2.0 正文部分的既有义务）在 L0 内立即执行，不等待商业决策，也不推迟到 W4。
- 本 spec 与审计产物均不构成法律意见；对外分发前应取得授权方确认或专业法律意见。
- 未过 L0：W1–W4 不开工。W0 / P0 不受影响（本地只读审计与一次本地预检不构成分发）。

## 7. P0：最小真实供应商预检（本次批准执行）

目的：视频链路零实测是全项目最大风险，必须在 W1–W4 大规模开发前暴露，而不是拖到终验收。

- 范围拆成两个互不污染的场景：
  - **真实付费场景（恰好一次）**：Seedance 2.0 Mini、480p、最短时长，向真实供应商提交**一次**；待 `upstreamTaskId` 落库后强制退出 App；重启后验证仅继续轮询、下载落盘，并以请求日志/任务表断言全程真实提交次数 == 1。
  - **失败与重试场景（零真实调用）**：通过本地测试网关或在提交前制造确定性错误，验证错误落库、任务中心可见、重试路径可走通；**不得触达真实供应商**。
  - 文本/图片链路用 azt（Codex OAuth）做同等冒烟，零边际成本。
- 凭证纪律：火山引擎 key 从旧 ToonFlow 运行库（`~/Library/Application Support/toonflow/data/db2.sqlite` 的 `o_vendorConfig`）一次性迁移，**只写入 DramaFlow 现有凭证存储**（`flutter_secure_storage`——macOS 上即系统 Keychain；release 构建启用 Data Protection Keychain 形态，对应 `Release.entitlements` 的 keychain-access-groups）。若旧库中无有效 key，则退化为用户在设置页填入一次（属一次性配置，不计入"用户测试"）。key 不得出现在：日志、spec/文档、SQLite 明文、git 提交、终端回显。迁移脚本用后即删。
- 修复纪律：P0 期间**默认只诊断与记录**（缺陷进总清单/任务卡）。确需修复才能完成预检的阻塞缺陷，必须单独立任务卡——限定文件白名单 + 明确验收命令，在独立 worktree/分支执行，经逐行审核后合入 `develop`。
- 产物：`docs/parity/p0-provider-preflight.md`（记录任务 id、耗时、产物路径、恢复行为；不含 key 与完整 prompt）。

## 8. W1–W4 概要（占位，不在本次批准范围）

- **W1 画布**：先定可测量指标再动手（方向示例：数百节点下拖拽/缩放满帧不掉、缩放跟随光标、触控板捏合与惯性、节点拖动无卡顿；具体数值与测法在 W1 spec 定，用 profile 基准 + 录屏证据验证）。
- **W2 Agent 体系移植**：以 ToonFlow 源码的用户可观察行为为准（decision/execution/supervision 多 Agent 编排、消息摘要、向量记忆与 RAG 检索、Markdown 技能的 activate/read 工具流），在现有 Dart assistant 架构上**移植**。**明令禁止**：恢复自定义 JS 解释器、ES-DSL 查询、或将 v0.4 前的旧实现整体回滚——经源码验证（2026-07-17，`src/utils/agent/` 与 `src/agents/` 全量 grep），JS 解释器与 ES-DSL 非 ToonFlow 原版能力，是 DramaFlow 历史膨胀产物；旧代码只可作局部参考。注意：该验证仅覆盖 `Toonflow-app` 后端，W0 须在含 `Toonflow-web` 的完整基线上复核此结论后方可写入 W2 spec。
- **W3 NLE 工作台**：以 ToonFlow WebAV 剪辑器的用户可观察行为为基准，解冻现有被隐藏的高级时间线能力并补齐剩余自由剪辑缺口。
- **W4 长尾清零**：完全由总清单驱动，按批次立项、实施、过审核门，直至清单全绿。

## 9. 执行与验证模式

- 协作分工沿用既有模式：Claude 写规格、逐行审核 diff、亲自复跑测试、提交；`codex exec --full-auto` 执行实现。每个任务卡必须限定可改文件白名单与验收命令。
- 分支纪律：每个任务卡在**独立 worktree/分支**执行，逐行审核通过后合入 `develop`；**禁止任何 Agent 直接在 `develop` 上无边界运行 `--full-auto`**。提交只 add 明确列出的文件，禁止 `git add .`（当前 `docs/superpowers/acceptance/` 为未跟踪目录，且工作区可能存在其他未跟踪产物）。
- 测试纪律：每个移植/新增能力必须带 engine/widget 测试；全套 `flutter test` 保持绿色是每个审核门的前置条件。
- 自验证边界：文本/图片用 azt 真实调用；视频真实调用仅发生在 P0 与各里程碑关口的少量确认点，成本可控。

## 10. Decision Log

- 2026-07-17 目标变更：从"核心工作流复刻"改为"固定 ToonFlow 1.1.8 基线下的用户可观察功能等价 100% 复刻"。取代 2026-07-10 收敛 spec 中"Rejected: complete ToonFlow feature parity"的决策。
- "100%" 定义为用户可观察行为等价，不是内部实现一致；"已验证更优"须附打包版对照用例并确认无能力丢失。
- 基线 = `Toonflow-app`（SHA-256 清单）+ `Toonflow-web`（commit `9c4cb0e`）+ 打包 `ToonFlow.app`；行为歧义以打包版为仲裁；运行库能力另以无密钥 `baseline-runtime-capabilities.json` 冻结。（2026-07-18 修订：外部评审指出原基线漏掉前端源码仓库，已核实 `Toonflow-app/src` 仅含后端。）
- 审计方法 = 静态源码 + 打包版黑盒验证 + 机械库存清单；库存无孤儿项是 W0 完成条件。
- 许可证（2026-07-18 修订）：ToonFlow LICENSE 为 Apache-2.0 正文 + 商业授权/品牌保留补充协议，不得按普通 Apache-2.0 处理；新增 L0 分发决策门阻塞 W1–W4；仓库 LICENSE/NOTICE 补齐在 L0 内执行，不推迟到 W4。
- macOS 先达标；iOS / Android / Web / Windows 后续逐平台跟进。
- 开发期用户零测试；用户参与仅三点：W0 范围确认、L0 分发决策、最终收尾总验收。
- P0 独立于 W0（W0 保持只读审计）；P0 拆"真实付费恰好一次"与"隔离失败演练（零真实调用）"两场景；P0 默认只诊断记录，修复走文件白名单任务卡 + 独立 worktree，审核后合入。火山 key 只存现有 Keychain 凭证存储，禁止任何明文落地。
- W2 不恢复 JS 解释器与 ES-DSL（经 `Toonflow-app` 后端源码验证为非原版能力；W0 须在完整基线上复核）；多 Agent / 向量记忆 / 摘要 / Markdown 技能按源码行为移植。
- W4 长尾按批次过审核门，不穿插打断 W1–W3。
- 本 spec 仅批准 W0 + P0；L0 依赖 W0 产出；W1–W4 待 W0 清单确认与 L0 过门后各写独立 spec。
