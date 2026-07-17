# ToonFlow 100% 复刻总路线与 W0 审计规范

状态：总路线（meta-spec）。本文档只批准 W0 与 P0 进入实施；W1–W4 须在 W0 总清单经用户确认后，各自另写独立 spec 与 plan。

本 spec 取代 `2026-07-10-toonflow-core-parity-convergence-design.md` 中与"核心工作流即可"相关的边界决策（详见第 9 节 Decision Log）。该收敛 spec 的其余工程约束（凭证不落 SQLite、任务恢复语义、原生合成路线等）继续有效。

## 1. 背景与目标

DramaFlow 现状：10 个页面中 9 个在页面级对照清单中为 Verified，多轨工作台与 Agent 页为 Partial；C5 真机验收从未执行；视频生成链路（Seedance）从建仓起零实测。

用户决策（2026-07-17）：目标从"核心工作流复刻"升级为对 ToonFlow 的 **100% 复刻**，并要求：

- 参照物为本地 `Toonflow-app`（Electron 版，v1.1.8）。
- 达标标准为**功能等价**，不要求像素级 UI 一致（见第 2 节精确定义）。
- 平台先 macOS 单平台达标，iOS/Android/Web/Windows 之后逐个跟进。
- 开发期间用户**零参与测试**；全部缺口补齐并经我方自验证后，用户只做一次收尾总验收。
- 无限画布必须定可测量的性能/手感硬指标（用户对旧 Electron 版画布的核心不满，Flutter 版不得重蹈覆辙）。

## 2. "100%" 的定义

**100% = 固定基线下的用户可观察功能等价。**

- 基线：本地 `Toonflow-app` v1.1.8 源码，经第 3 节流程冻结。
- 等价判定只看**用户可观察行为**：某个操作在 ToonFlow 能做到什么效果，在 DramaFlow 就要能做到不弱于它的效果。
- 明确**不**要求：内部代码与架构一致、复制 Electron 特有实现、复制历史 bug、复制无用户价值的内部实现细节。DramaFlow 可以（且应当）使用更适合 Flutter 的实现。
- 允许"已验证更优"：DramaFlow 的实现体验优于 ToonFlow 原版时，按更优记录，同样算达标。

## 3. 基线冻结（W0 产物之一）

`Toonflow-app` 不是 git 仓库，无法用 commit 锁定，必须显式冻结：

- 记录基线版本：ToonFlow `1.1.8`（`package.json`），许可证 Apache-2.0（`LICENSE` + `NOTICES.txt`）。
- 生成源码 SHA-256 清单：覆盖 `src/`、`data/`（vendor、modelPrompt、skills 等资产目录）与 `package.json`；排除 `node_modules/`、`dist/`、构建产物。清单落库为 `docs/parity/baseline-manifest.json`。
- **原版能力与本地扩展分开标记**。本地 `Toonflow-app` 含非上游修改，至少包括：`data/vendor/ima2.ts`、`data/vendor/azt.ts`、Seedance 2.0 Mini 运行时模型（存于运行库 `o_vendorConfig.models`，不在源码内）、`src/lib/fixDB.ts` 等本地修复（完整清单见仓库外 `aivideo/AGENTS.md`"Known Local Fixes"）。本地扩展同样在复刻范围内（用户实际在用），但清单中必须标注来源为"本地扩展"，不得混入"ToonFlow 原版"。
- 基线漂移处理：若 `Toonflow-app` 目录内容变化导致 SHA-256 不匹配，必须显式重新冻结并 diff 说明变化，禁止无声吸收。审计期间不修改 `Toonflow-app` 目录。

## 4. 里程碑结构

```text
W0  冻结基线 + 总对照清单 + 许可证审计   （只读审计，零实现改动）——本 spec 批准
P0  最小真实供应商预检                    （一次最低成本视频全链路）——本 spec 批准
W1  无限画布体验达标                      （待独立 spec）
W2  Agent 体系移植                        （待独立 spec）
W3  NLE 工作台补全                        （待独立 spec）
W4  长尾缺口清零                          （按批次，每批过审核门）
终  用户一次性收尾总验收                  （12 步真机流程 + 画布体验签字）
```

- W0 与 P0 可并行；W1–W3 顺序开工（画布是用户点名痛点，排最前）；W4 批次穿插但**每批必须独立过审核门**，不得零散混入 W1–W3 的分支。
- 唯一需要用户参与的两个点：① W0 完成后对总清单做一次**范围确认**（这是范围决策，不是测试）；② 全部绿灯后的收尾总验收。

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

- 以 ToonFlow 源码为唯一输入，按模块划分审计单元：前端页面/路由、后端 routes、agents（scriptAgent / productionAgent 及其 tools）、`src/utils/agent/`（memory / embedding / skillsTools）、vendor 与模型提示词资产、导出与合成链路。
- 每个单元：通读源码 → 提取用户可观察行为条目 → 对照 DramaFlow 现状（代码 + 测试）定状态。
- DramaFlow 侧证据优先引用现有测试文件；`docs/superpowers/progress/2026-07-04-page-parity-checklist.md` 作为线索输入，但其"Verified"结论不自动继承——按本 spec 的六态标准重判。

### 5.3 许可证审计（W0 内完成）

- ToonFlow 为 Apache-2.0：核对 DramaFlow 对 LICENSE / NOTICE 的继承义务（含移植提示词模板、内置画风包 `art_skills` / `story_skills`、模型提示词等随包资产的署名要求）。
- 梳理第三方资产许可证：字体、图片、内置画风素材、模型提示词模板。
- 确认不复制 ToonFlow 商标、名称与品牌资源（产品名 DramaFlow 已区隔；检查图标、启动图、内置示例是否有残留）。
- 产物：清单中的许可证节 + 需要的 LICENSE/NOTICE 文件变更建议（变更本身可放入 W4 首批）。

### 5.4 W0 完成判定

- 基线清单（SHA-256 manifest）已生成并提交。
- 总对照清单覆盖 ToonFlow 全部页面/路由/agent 工具面/资产面，无"未审计"残留。
- 许可证审计节完成。
- 用户完成一次范围确认（确认清单条目与"不适用"判定，可调整）。

## 6. P0：最小真实供应商预检（本次批准执行）

目的：视频链路零实测是全项目最大风险，必须在 W1–W4 大规模开发前暴露，而不是拖到终验收。

- 范围：**恰好一次**最低成本真实视频生成——Seedance 2.0 Mini、480p、最短时长；同链路验证：任务提交、轮询、下载落盘、中途重启后恢复且不重复提交、人为构造一次失败并确认错误落库可重试。文本/图片链路用 azt（Codex OAuth）做同等冒烟，零边际成本。
- 凭证纪律：火山引擎 key 从旧 ToonFlow 运行库（`~/Library/Application Support/toonflow/data/db2.sqlite` 的 `o_vendorConfig`）一次性迁移，**只写入 DramaFlow 现有凭证存储**（`flutter_secure_storage`，release 走 macOS Keychain）。若旧库中无有效 key，则退化为用户在设置页填入一次（属一次性配置，不计入"用户测试"）。key 不得出现在：日志、spec/文档、SQLite 明文、git 提交、终端回显。迁移脚本用后即删。
- P0 不修实现 bug 之外的任何东西：发现的缺陷记录进总清单或直接修复该缺陷本身，不顺手扩功能。
- 产物：`docs/parity/p0-provider-preflight.md`（记录任务 id、耗时、产物路径、恢复行为；不含 key 与完整 prompt）。

## 7. W1–W4 概要（占位，不在本次批准范围）

- **W1 画布**：先定可测量指标再动手（方向示例：数百节点下拖拽/缩放满帧不掉、缩放跟随光标、触控板捏合与惯性、节点拖动无卡顿；具体数值与测法在 W1 spec 定，用 profile 基准 + 录屏证据验证）。
- **W2 Agent 体系移植**：以 ToonFlow 源码的用户可观察行为为准（decision/execution/supervision 多 Agent 编排、消息摘要、向量记忆与 RAG 检索、Markdown 技能的 activate/read 工具流），在现有 Dart assistant 架构上**移植**。**明令禁止**：恢复自定义 JS 解释器、ES-DSL 查询、或将 v0.4 前的旧实现整体回滚——经源码验证（2026-07-17，`src/utils/agent/` 与 `src/agents/` 全量 grep），JS 解释器与 ES-DSL 非 ToonFlow 原版能力，是 DramaFlow 历史膨胀产物；旧代码只可作局部参考。
- **W3 NLE 工作台**：以 ToonFlow WebAV 剪辑器的用户可观察行为为基准，解冻现有被隐藏的高级时间线能力并补齐剩余自由剪辑缺口。
- **W4 长尾清零**：完全由总清单驱动，按批次立项、实施、过审核门，直至清单全绿。

## 8. 执行与验证模式

- 协作分工沿用既有模式：Claude 写规格、逐行审核 diff、亲自复跑测试、提交；`codex exec --full-auto` 执行实现。规格限定可改文件范围。
- 分支纪律：工作在 `develop`；**提交只 add 明确列出的文件，禁止 `git add .`**（当前 `docs/superpowers/acceptance/` 为未跟踪目录，且工作区可能存在其他未跟踪产物）。
- 测试纪律：每个移植/新增能力必须带 engine/widget 测试；全套 `flutter test` 保持绿色是每个审核门的前置条件。
- 自验证边界：文本/图片用 azt 真实调用；视频真实调用仅发生在 P0 与各里程碑关口的少量确认点，成本可控。

## 9. Decision Log

- 2026-07-17 目标变更：从"核心工作流复刻"改为"固定 ToonFlow 1.1.8 基线下的用户可观察功能等价 100% 复刻"。取代 2026-07-10 收敛 spec 中"Rejected: complete ToonFlow feature parity"的决策。
- "100%" 定义为用户可观察行为等价，不是内部实现一致；允许"已验证更优"。
- 基线用 SHA-256 清单冻结；原版能力与本地扩展（ima2 / azt / Seedance Mini 等）分开标记，均在范围内。
- macOS 先达标；iOS / Android / Web / Windows 后续逐平台跟进。
- 开发期用户零测试；仅 W0 后一次范围确认 + 最终一次收尾总验收。
- P0 独立于 W0（W0 保持只读审计）；火山 key 只存现有 Keychain 凭证store，禁止任何明文落地。
- W2 不恢复 JS 解释器与 ES-DSL（经 ToonFlow 1.1.8 源码验证为非原版能力）；多 Agent / 向量记忆 / 摘要 / Markdown 技能按源码行为移植。
- W4 长尾按批次过审核门，不穿插打断 W1–W3。
- 本 spec 仅批准 W0 + P0；W1–W4 待 W0 清单确认后各写独立 spec。
