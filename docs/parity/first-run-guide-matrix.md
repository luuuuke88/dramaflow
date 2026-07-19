# 首次启动引导对照：欢迎、配置入口与一次性状态

首次引导看起来像一张欢迎页，实际上决定了新用户是否能走到正确的配置位置、是否会反复被打断，以及在桌面和手机上能否安全完成。这里按可观察的旅程对照 ToonFlow `hello.vue` 与 DramaFlow 的 `FirstRunGuide`，不把品牌推广素材误算成创作能力。

本轮只跑本地 Flutter widget/引擎测试；没有请求文本、图片、音频或视频供应商。

## 用户旅程

| 旅程节点 | ToonFlow 1.1.8 | DramaFlow 当前实现 | 结论 |
| --- | --- | --- | --- |
| 第一次打开应用 | `helloGuideDone=false` 时出现 680px 欢迎对话框 | `onboarding.completed != '1'` 时根路由直接进入全屏引导 | **等价**：形态不同，阻断首次工作流的效果一致 |
| 欢迎页 | Logo、欢迎说明、语言菜单、开始设置与跳过 | 欢迎说明、中文/英语/日语菜单、开始设置与跳过；窄屏使用安全区全屏表单 | **等价** |
| 第一步 | 打开设置中的供应商配置 | 深链到设置的供应商分区，并可返回引导 | **等价** |
| 第二步 | 打开 `agentConfog`：普通/高级模式、逐 Agent 部署与参数 | 深链到“流水线模型绑定”分区，并可返回引导 | **部分实现** |
| 第三步 | 完成文案、微信群二维码、GitHub Star；完成时撒花 | 完成文案和完成动作 | **创作工作流等价；不复制 ToonFlow 品牌推广素材** |
| 跳过或完成后再启动 | 浏览器 `localStorage.helloGuideDone=true`，不再弹出 | SQLite `o_setting['onboarding.completed']='1'`，不再路由到 onboarding | **等价** |

## 两侧的状态边界

原版在 [`hello.vue`](../../../Toonflow-web/src/components/hello.vue) 用 `useLocalStorage('helloGuideDone', false)` 保存完成状态，组件由 [`workbench/index.vue`](../../../Toonflow-web/src/pages/workbench/index.vue) 挂载。它不检测供应商是否真的可用：开始、跳过和完成都会将引导标记为完成，用户之后可以自行回到设置。

DramaFlow 在 [`engine/config.dart`](../../app/lib/src/engine/config.dart) 默认 `onboarding.completed='0'`，由 [`engine.dart`](../../app/lib/src/engine/engine.dart) 持久化；启动时 [`bootstrap_io.dart`](../../app/lib/src/bootstrap/bootstrap_io.dart) 把结果传给 [`app.dart`](../../app/lib/src/app.dart)，根路由据此选择 `/onboarding` 或工作台。这比浏览器 localStorage 更适合原生应用：状态随本机数据库和用户数据目录留存，不依赖一个网页存储键，也没有在引导期写入凭证或提交模型请求。

两个实现都允许没有完成供应商配置就跳过。这里不应强加“必须填 Key 才能继续”的新规则，因为那会改变 ToonFlow 当前的可观察行为；后续项目创建时的模型可用性校验才是正确的保护位置。

## 第二步的实际缺口

这是当前 `W6E-CMP-HELLO-001` 不能升绿的唯一工作流原因。

ToonFlow 点击第二步会令 `settingStore.activeMenu='agentConfog'`。该页包含 Agent 使用模式、逐 Agent 模型部署和相关参数。DramaFlow 当前点击“打开模型绑定”只会进入项目流水线阶段的模型绑定页面。它能指导用户把已有模型分配给剧本、分镜、图像和视频阶段，但不能替代完整 Agent 配置。

这不应该在首次引导组件里临时补一套配置表。正确的修复顺序是先完成总清单中 `W7A-AGENT-USEMODE-001`、`W7A-AGENT-SETKEY-001` 等 Agent 配置能力；随后只把引导第二步的目标换成那个已有、可跨端使用的设置分区，并补一条从引导进出该分区的回归。这样引导保持薄，配置模型不会被复制两次。

## 跨端证据

| 验收点 | 现有证据 |
| --- | --- |
| 桌面欢迎页和跳过 | [`first_run_guide_test.dart`](../../app/test/widgets/first_run_guide_test.dart) 验证宽屏“开始设置”入口与跳过回调。 |
| 390dp 三步流 | 同一测试验证欢迎→供应商设置→模型绑定→完成的顺序与回调。 |
| 从设置回到引导 | [`onboarding_router_test.dart`](../../app/test/widgets/onboarding_router_test.dart) 驱动 providers/bindings 深链、返回与跳过后的路由。 |
| 完成状态持久化 | [`onboarding_test.dart`](../../app/test/engine/onboarding_test.dart) 断言默认未完成、写入 `1` 后可读回。 |
| 三语选择 | `first_run_guide_test.dart` 驱动语言菜单；`app.dart` 把选择交给 `localeProvider`。 |

这些用例使用内存 SQLite、临时目录和假回调，不调用任何供应商。手机端以完整安全区页面替代桌面对话框，所有进入设置、上一步、下一步、跳过和完成按钮都有触控可达路径。

## 判定与后续

总清单 `W6E-CMP-HELLO-001` 保持**部分实现**，且原因已收敛为一个明确依赖：完整 Agent 配置页尚未复刻。二维码、GitHub Star 和撒花是 ToonFlow 的品牌/社区推广素材，不属于“制作短剧”的核心能力；它们不应驱动架构设计或让首次引导重新判缺失。

完成 Agent 配置后，复验应包含：首次安装状态、已完成状态重启、桌面与 390dp 的第二步深链和返回、无模型时不阻断跳过，以及所有语言菜单项。视频生成仍只保留本地 fake gateway 验证，真实视频调用由用户最终确认。

## 独立复验快照（2026-07-19）

当前 `develop` 工作树重新执行了以下与首次引导直接相关的验证：

```bash
cd app
flutter test --concurrency=1 \
  test/engine/onboarding_test.dart \
  test/widgets/first_run_guide_test.dart \
  test/widgets/onboarding_router_test.dart
flutter analyze \
  lib/src/screens/first_run_guide.dart \
  lib/src/app.dart \
  test/widgets/first_run_guide_test.dart \
  test/widgets/onboarding_router_test.dart
```

结果为 `5` 条测试全部通过，静态分析为 `No issues found`。这些用例在内存 SQLite、
临时目录和假供应商环境中运行，没有写入任何真实凭证，也没有调用文本、图片、音频或
视频服务。它们重新证明了当前欢迎、语言、跳过、引导深链和完成持久化的实现；不能替代
完整 Agent 配置页的缺失项，因此本页和总清单仍保持“部分实现”。
