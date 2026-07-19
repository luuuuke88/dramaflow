# 工作台快速预览实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在工作台复刻 ToonFlow 的分镜首帧快速预览、按镜头时长播放与定位、镜头信息审阅和已选首帧 ZIP 导出，桌面与 390dp 窄屏都完整可用。

**Architecture:** 预览状态使用屏幕层的纯 `ChangeNotifier` 控制器；它只处理不可变时长列表的播放、跳镜与定位，不访问数据库也不创建 `Timer`。预览页从有序 `StoryboardRow` 与一次 `assetsByIds` 批量查询构建显示数据。UI 先请求系统保存位置，再由 Engine 校验媒体根目录内的普通文件并在独立 isolate 流式写入 ZIP。

**Tech Stack:** Flutter Material/Riverpod、SQLite Engine、`archive`、`file_selector`、Flutter widget/unit tests。

## 全局约束

- 不调用或测试任何真实文本、图像、音频、视频供应商。
- 不触碰 SQLite `o_secret` 密钥策略、供应商配置、视频提交或轮询协议。
- 快速预览只轮播首帧图，不能演变为视频播放器或实时合成器。
- 空、非法或非正分镜时长按 ToonFlow 的 3 秒兜底；seek 按毫秒处理。
- 关联资产只允许一次 `assetsByIds` 批量查询后内存映射，禁止 N+1。
- 画面描述使用 `StoryboardRow.videoDesc`；这是修复 ToonFlow 响应未投影 `description` 的本地可观测改进，文档必须说明。
- 所有文案同步中文、英文、日文；测试只用内存 SQLite、临时媒体与 fake gateway。

---

### Task 1: 可测试的预览时间轴控制器

**Files:**
- Create: `app/lib/src/screens/production/workbench_preview_controller.dart`
- Create: `app/test/widgets/workbench_preview_controller_test.dart`

**Produces:** `PreviewTimelineController(List<Duration> durations)`，公开 `currentIndex`、`elapsed`、`isPlaying`、`totalDuration`、`totalElapsed`、`progress` 与 `togglePlay()`、`pause()`、`previous()`、`next()`、`jumpTo(int)`、`seek(Duration)`、`tick(Duration)`。

- [x] 先写失败测试：两镜 2s/3s，`tick(2500ms)` 后落在第二镜 500ms；末镜结束自动暂停；从结尾点播放会复位；验证精确 seek、空镜头和 3 秒兜底。
- [x] 运行 `cd app && flutter test test/widgets/workbench_preview_controller_test.dart`，确认因控制器不存在而失败。
- [x] 实现控制器。`tick` 可以跨越多个镜头但每次最多 `notifyListeners()` 一次；`seek` 必须夹在 `[0,totalDuration]`；最后镜头恰到片尾时保持最后一镜和该镜完整 elapsed。
- [x] 重跑上面的测试，预期 PASS。
- [x] 提交：`d13dece feat(workbench): add preview timeline controller`。

### Task 2: 本地分镜首帧 ZIP 导出

**Files:**
- Modify: `app/lib/src/engine/storyboard.dart`
- Modify: `app/test/engine/storyboard_test.dart`

**Produces:**

```dart
int Engine.storyboardImageExportFileCount(int scriptId, Set<int> storyboardIds)

Future<int> Engine.exportStoryboardImagesToFile(
  int scriptId,
  Set<int> storyboardIds,
  String targetPath,
)
```

- [x] 先写失败引擎测试：创建两镜，其中一张首帧存在、另一张路径不存在；只导出已选且存在的图片；解压 ZIP 断言条目为 `分镜<id>.<扩展名>` 和原始字节。再覆盖空选择、未选镜头、缺图、绝对路径、`..` 路径和符号链接，均不写入或抛出。
- [x] 运行 `cd app && flutter test test/engine/storyboard_test.dart --plain-name "exportStoryboardImages"`，确认失败。
- [x] 用现有 `archive` 依赖在独立 isolate 流式读取已校验的 `MediaStore` 普通文件；扩展名为空或非法时使用 `jpg`；跳过不存在文件；零可导出图不创建目标 ZIP。不得删除或改写任何源图。
- [x] 重跑引擎测试，预期 PASS。
- [x] 提交：`5c26882 feat(storyboard): export selected first frames as zip`。

### Task 3: 工作台快速预览路由与响应式页面

**Files:**
- Create: `app/lib/src/screens/production/workbench_preview.dart`
- Modify: `app/lib/src/screens/production/workbench_screen.dart`
- Modify: `app/lib/l10n/app_zh.arb`
- Modify: `app/lib/l10n/app_en.arb`
- Modify: `app/lib/l10n/app_ja.arb`
- Modify: `app/test/widgets/workbench_screen_test.dart`

**Produces:**

```dart
Future<void> showWorkbenchQuickPreview(
  BuildContext context,
  WidgetRef ref, {
  required int projectId,
  required int scriptId,
})
```

The Workbench AppBar exposes this route through `ValueKey('workbench-quick-preview')`.

- [x] 先写失败桌面 widget 测试：从现有工作台入口点击预览；两张临时 PNG 按时长展示；点击“下一镜”切换到第二镜；断言 `videoDesc`、关联角色/场景/道具 chip、图片提示词、当前首帧和总时长均可见。
- [x] 先写失败 390x760 widget 测试：进入全屏预览、点缩略图切换、选择单张首帧、滚动至导出操作；断言无 overflow 或 Flutter 异常。
- [x] 运行 `cd app && flutter test test/widgets/workbench_screen_test.dart --plain-name "工作台快速预览"`，确认缺入口/页面而失败。
- [x] 实现页面：有首帧/缺图占位、上一镜/播放暂停/下一镜图标按钮、已播放/总时长文本、可 seek 的 Slider 与按时长比例段标记、关联资产、图片提示词、可水平滚动的镜头缩略图和复选框。点击缩略图或上一/下一镜暂停播放并更新当前镜。
- [x] 页面只在播放时启动 50ms `Timer.periodic`，以 `Stopwatch` 的实际间隔推进并在应用失活时暂停；`dispose` 时停止 Timer 并释放控制器。桌面使用预览与信息两栏、底部缩略图；小于 840dp 时使用单列可滚动布局，所有动作可达且不依赖 hover。
- [x] 导出时先用 `getSaveLocation`，再调用 `Engine.exportStoryboardImagesToFile`；用户取消或零图不写文件；导出期间禁用重复提交；零图显示已有 `storyboardExportNoImages`；成功给出文件数反馈。
- [x] 三语新增预览相关 ARB 字段，执行 `flutter gen-l10n`。
- [x] 执行：

```bash
cd app
flutter gen-l10n
flutter test test/widgets/workbench_preview_controller_test.dart test/engine/storyboard_test.dart test/widgets/workbench_screen_test.dart
flutter analyze
```

预期：全部通过，`flutter analyze` 输出 `No issues found!`。

- [x] 提交：`927de4f feat(workbench): add storyboard quick preview`。

### Task 4: 对照文档与完整验证

**Files:**
- Modify: `docs/parity/workbench-matrix.md`
- Modify: `docs/parity/master-checklist.md`
- Modify: `docs/parity/feature-parity-execution-report.md`
- Modify: `docs/superpowers/plans/2026-07-20-workbench-quick-preview.md`

- [x] 写入源码证据和验证结论：50ms 首帧轮播、时长定位、跳镜、资产/提示词审阅、`videoDesc` 修正、已选图 ZIP 导出、桌面与 390dp 路径。明确“恢复排序”是 ToonFlow 初始快照错误导致的不可用动作，不复制；Flutter 的持久分镜重排保留为既有更可用行为。
- [x] 明确独立空视频轨、候选视频单文件/批量 ZIP 下载、实时 NLE 预览和真实视频生成仍是未完成的独立条目，绝不因本批实现而标绿。
- [x] 审查修复：媒体路径仅接受根目录内的普通文件，拒绝绝对路径、`..` 和符号链接；ZIP 在独立 isolate 流式写入；缺失资产图有占位降级；时间段提供 48dp 命中区和选中语义；1100dp 以下将批量工作台动作收进菜单，覆盖 1024dp 英文场景。
- [x] 执行：

```bash
cd app
flutter test --concurrency=1 --reporter compact
flutter analyze
flutter build macos --debug
cd ..
node tool/parity/check_no_orphans.js
git diff --check
```

预期：全量离线测试通过、静态分析零 issue、macOS debug 构建成功、库存检查全绿、diff 检查无空白错误。不得设置 `QA_FULL`/`P0_LIVE`，不得调用真实供应商或提交视频任务。

- [x] 勾选已执行步骤并提交：`git add docs/parity docs/superpowers/plans/2026-07-20-workbench-quick-preview.md`，`git commit -m "docs(parity): verify workbench quick preview"`。

## 自审

- Task 1 把时间运算与 UI/Timer 分开，保证播放、跳镜和 seek 可直接单测。
- Task 2 是唯一的本地文件转换，责任放在 Engine；UI 不组装 ZIP。
- Task 3 覆盖原版用户可观察预览能力和双端布局，不引入实时视频功能。
- Task 4 明确不把独立轨道、候选下载或真实视频验收误报为已完成。
