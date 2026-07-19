# Production Canvas Guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 DramaFlow 的桌面和窄屏制作页交付一次性的四步操作引导，并按本机 SQLite 设置持久化完成状态。

**Architecture:** `ProductionGuideOverlay` 是独立、无业务依赖的展示组件；`ProductionScreen` 提供真实目标控件和完成回调；`EngineConfig` 只保存一个设备级布尔键。画布 fit 动作留在 `DFCanvas`/制作页，不让教程组件操纵业务数据。

**Tech Stack:** Flutter Material、Riverpod、SQLite `o_setting`、现有 Flutter widget/engine tests。

## Global Constraints

- 复刻 ToonFlow 的四个操作概念，不引入第三方引导 SDK。
- 视频、文本、图像和音频供应商绝不在本任务中调用。
- 密钥继续仅属于 SQLite `o_secret`；本任务不得读取、导出或记录凭证。
- 桌面与 390dp 都必须有完整可达路径；窄屏不渲染桌面锚点浮层。
- 新增可见文本提供 zh/en/ja 三份 ARB。

---

### Task 1: 持久化契约和三语文案

**Files:**
- Modify: `app/lib/src/engine/config.dart:34-40`
- Modify: `app/test/engine/config_test.dart`
- Modify: `app/lib/l10n/app_zh.arb`
- Modify: `app/lib/l10n/app_en.arb`
- Modify: `app/lib/l10n/app_ja.arb`

**Interfaces:** `EngineConfig.str('production.guide.completed')` 默认 `'0'`，可通过 `update` 持久化为 `'1'`。

- [ ] **Step 1: 写失败测试**

```dart
test('制作画布引导默认未完成且完成状态持久化', () {
  final db = openEngineDb(':memory:');
  final config = EngineConfig(db, isMobile: false);
  expect(config.str('production.guide.completed'), '0');
  config.update({'production.guide.completed': '1'});
  expect(EngineConfig(db, isMobile: false)
      .str('production.guide.completed'), '1');
});
```

- [ ] **Step 2: 运行 RED 验证**

Run: `cd app && flutter test test/engine/config_test.dart`

Expected: 新用例失败，因为未知键不会被 `EngineConfig.update` 写入。

- [ ] **Step 3: 实现最小契约**

在 `_defaults` 增加 `'production.guide.completed': '0'`。三份 ARB 同时新增：
`productionGuideTitle`、`productionGuideStepCounter`、`productionGuideEpisodeTitle`、
`productionGuideEpisodeBody`、`productionGuideRefreshTitle`、`productionGuideRefreshBody`、
`productionGuideLayoutTitle`、`productionGuideLayoutBody`、`productionGuideCanvasTitle`、
`productionGuideCanvasBody`、`productionGuideMobileLayoutBody`、`productionGuideSkip`、
`productionGuideBack`、`productionGuideNext`、`productionGuideFinish`、`productionRefresh`、
`productionRefreshed`。

- [ ] **Step 4: 运行 GREEN 验证**

Run: `cd app && flutter gen-l10n && flutter test test/engine/config_test.dart`

Expected: 测试通过，三个 locale 的生成访问器存在。

### Task 2: 独立、响应式的引导展示组件

**Files:**
- Create: `app/lib/src/screens/production/production_guide.dart`
- Create: `app/test/widgets/production_guide_test.dart`

**Interfaces:** `ProductionGuideOverlay({required bool compact, required List<GlobalKey> targets, required VoidCallback onComplete})`。桌面读取当前目标 `RenderBox` 的全局矩形，画遮罩与镂空高亮；窄屏渲染全屏卡片；跳过或第 4 步完成时只调用一次 `onComplete`。

- [ ] **Step 1: 写失败 widget 测试**

```dart
testWidgets('桌面引导按四步推进并在完成时仅回调一次', (tester) async {
  var completed = 0;
  final targets = List.generate(4, (_) => GlobalKey());
  await tester.pumpWidget(host(
    child: ProductionGuideOverlay(
      compact: false, targets: targets, onComplete: () => completed++,
    ),
    targets: targets,
  ));
  expect(find.textContaining('1 / 4'), findsOneWidget);
  for (var i = 0; i < 3; i++) {
    await tester.tap(find.byKey(const Key('production-guide-next')));
    await tester.pump();
  }
  expect(find.textContaining('4 / 4'), findsOneWidget);
  await tester.tap(find.byKey(const Key('production-guide-finish')));
  expect(completed, 1);
});
```

另写 390dp 测试：断言全屏布局没有桌面定位浮卡，`跳过` 仅回调一次。

- [ ] **Step 2: 运行 RED 验证**

Run: `cd app && flutter test test/widgets/production_guide_test.dart`

Expected: 编译失败，`ProductionGuideOverlay` 尚不存在。

- [ ] **Step 3: 实现组件**

实现 `ProductionGuideOverlay`、私有 `_ProductionGuideCard` 与 `_GuideScrimPainter`。桌面以
`RenderBox.localToGlobal` 得到目标矩形，在画面边缘自动翻转卡片；`CustomPaint` 用 even-odd
Path 画遮罩洞；窄屏用 `SafeArea` 全屏步骤页。四步的 icon/标题/正文均读 l10n，不保留中文硬编码。
使用 `Focus` 的 Escape 快捷键结束，按钮有 `Key` 与 `Semantics`。

- [ ] **Step 4: 运行 GREEN 验证**

Run: `cd app && flutter test test/widgets/production_guide_test.dart`

Expected: 桌面四步、跳过、390dp 可达性用例均通过。

### Task 3: 制作页、真实目标与画布 fit 接线

**Files:**
- Modify: `app/lib/src/widgets/df_canvas.dart`
- Modify: `app/lib/src/screens/production/production_screen.dart`
- Modify: `app/test/widgets/production_screen_test.dart`

**Interfaces:** `DFCanvasController` 是公开类型，提供 `void fitView()`；`DFCanvas` 以可选 `controller` 参数挂接/解绑该实例。`ProductionScreen` 使用四个 `GlobalKey`，首次有剧本并完成首帧布局后展示引导；完成时写 `production.guide.completed=1`。

- [ ] **Step 1: 写失败制作页测试**

```dart
testWidgets('桌面制作页首次显示四步引导，完成后重进不再出现', (tester) async {
  engine.addScript(projectId: projectId, name: '第一集', content: 'x');
  await tester.pumpWidget(app(1400));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('production-guide')), findsOneWidget);
  for (var i = 0; i < 3; i++) {
    await tester.tap(find.byKey(const Key('production-guide-next')));
    await tester.pump();
  }
  expect(find.textContaining('4 / 4'), findsOneWidget);
  await tester.tap(find.byKey(const Key('production-guide-finish')));
  await tester.pumpAndSettle();
  expect(engine.config.str('production.guide.completed'), '1');
  await tester.pumpWidget(app(1400));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('production-guide')), findsNothing);
});
```

另写 390dp 用例，断言首次有 guide、完成后状态为 `1`、TabBar 仍可访问；既有自动布局测试补断言，复位后主节点可见。

- [ ] **Step 2: 运行 RED 验证**

Run: `cd app && flutter test test/widgets/production_screen_test.dart`

Expected: guide finder 不存在，测试失败。

- [ ] **Step 3: 实现接线**

`ProductionScreen` 创建目标 key 与 `_showGuide`，使用 post-frame callback 避免 build 中写状态；最外层 `Stack` 加入 `ProductionGuideOverlay`，其完成回调更新 config。`_EpisodeBar` 增加 `onRefresh` 和 `production-refresh` 图标按钮，刷新只重建当前制作视图，不写业务数据或完成状态。`_CanvasLayout` 持有 `DFCanvasController`，复位节点后调用 `fitView()`；`DFCanvas` 卸载时解除 controller 回调。移动页传入 Tab/检查器 target 并以 compact 模式展示。

- [ ] **Step 4: 运行 GREEN 定向回归**

Run: `cd app && flutter test --concurrency=1 test/widgets/production_guide_test.dart test/widgets/production_screen_test.dart test/widgets/df_widgets_test.dart`

Expected: 新引导、既有画布拖拽/裁剪/390dp 用例全部通过。

### Task 4: 对照档案和全量验证

**Files:**
- Modify: `docs/parity/master-checklist.md`
- Modify: `docs/parity/w1-canvas-reference.md`
- Modify: `docs/parity/README.md`
- Modify: `docs/parity/feature-parity-execution-report.md`

- [ ] **Step 1: 更新证据和计数**

把 `W6E-CMP-PRODUCTION-GUIDE-001` 写明四步映射、原版 localStorage 与 Flutter SQLite 键差异、桌面/390dp 测试路径、无真实供应商调用。将该行从缺失改为已验证等价；用脚本重算 README 与执行报告计数，不改其他状态。

- [ ] **Step 2: 完整验证**

Run: `cd app && dart format --set-exit-if-changed lib/src/engine/config.dart lib/src/widgets/df_canvas.dart lib/src/screens/production/production_screen.dart lib/src/screens/production/production_guide.dart test/engine/config_test.dart test/widgets/production_guide_test.dart test/widgets/production_screen_test.dart && flutter analyze && flutter test --concurrency=1 && flutter build macos --debug`

Run: `cd .. && node tool/parity/check_no_orphans.js && git diff --check`

Expected: format 无改动、analyze 零诊断、全套测试和 macOS Debug 构建成功、538 项库存仍全覆盖、diff 无空白错误；不运行真实视频生成。

## Plan Self-Review

- 覆盖性：Task 1 持久化/文案；Task 2 跨端 UI；Task 3 制作页和画布；Task 4 对照文档与全量验证。
- 无占位：每项文件、设置键、组件、测试动作和验证命令均已给出。
- 一致性：完成键固定为 `production.guide.completed`，公开组件固定为 `ProductionGuideOverlay`，只由 `ProductionScreen` 写完成状态。
