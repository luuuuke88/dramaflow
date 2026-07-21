# 画风参考图提示词提取实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 复刻 ToonFlow 从一至多张参考图提取一个可编辑画风提示词的工作流。

**Architecture:** 引擎只负责验证本地图片、构造视觉模型请求和返回清理后的文本，绝不写画风表；编辑器持有参考图选择与加载态，成功后仅回填提示词。保存动作继续是既有 CRUD API 的唯一持久化入口。

**Tech Stack:** Flutter/Dart、既有 `ProviderGateway`、`MediaStore`、SQLite、flutter_test fake gateway。

## Global Constraints

- 不修改 Toonflow-app 或 Toonflow-web，不新增 schema、供应商、密钥字段或网络协议。
- 不调用真实文字、图片、音频或视频供应商；视频仅保留既有代码，不做真实测试。
- 只接受应用数据目录内既有常规图片；拒绝空列表、越界、链接、非图片与不存在文件。
- 成功仅回填编辑器；失败绝不覆盖输入；只有用户点击保存才写 `o_artStyle`。
- 桌面和 <840dp 使用同一编辑器，所有命令可触达且不依赖 hover。
- 不暂存 `.superpowers/sdd/progress.md` 或 `docs/superpowers/acceptance/`。

---

### Task 1: 安全的视觉提取引擎 API

**Files:**
- Modify: `app/lib/src/engine/art_style.dart`
- Test: `app/test/engine/art_style_test.dart`

**Produces:**
```dart
Future<String> extractArtStylePrompt(List<String> imagePaths);
```

- [ ] 写失败测试：fake gateway 捕获一张和两张图片的 data URL 顺序，断言系统指令包含“画风”、中英文与多图综合；空列表、`../x.png`、非图片和缺失路径在 gateway 调用前抛 `EngineException`；成功不改变 `o_artStyle` 行数；空结果抛格式错误。
- [ ] 运行 `cd app && flutter test test/engine/art_style_test.dart --plain-name '画风参考图提示词提取'`，确认 API 不存在而失败。
- [ ] 在 `art_style.dart` 用既有 `MediaStore` 常规文件检查读取最多 8 张图片为 data URL；调用现有视觉文本 gateway，去除 think 标签并验证非空文本；不执行任何数据库写入。
- [ ] 运行 `flutter test test/engine/art_style_test.dart --concurrency=1 && flutter analyze lib/src/engine/art_style.dart test/engine/art_style_test.dart`，确认通过后提交 `feat(art-style): add reference prompt extraction`。

### Task 2: 响应式编辑器回填

**Files:**
- Modify: `app/lib/src/screens/assets/art_style_library.dart`
- Modify: `app/lib/l10n/app_zh.arb`, `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_ja.arb` 及生成文件
- Test: `app/test/widgets/art_style_library_test.dart`

- [ ] 写失败 widget 测试：在 1200dp 和 390dp 打开画风编辑器，添加两个本地参考图，确认花费后等待 fake gateway，断言提示词被回填但数据库尚无新行；gateway 失败时原提示词不变；保存后才新增一行。
- [ ] 运行 `flutter test test/widgets/art_style_library_test.dart --plain-name '参考图提取画风'`，确认缺少提取入口而失败。
- [ ] 在 `_ArtStyleEditor` 增加最多 8 张参考图缩略图、移除动作和带 tooltip 的提取按钮；提取前走既有花费确认，进行时禁用保存/重复提取，成功回填 `_prompt`，失败用本地化错误 toast；补齐三语文案并运行 `flutter gen-l10n`。
- [ ] 运行相关 widget/engine 测试与 `flutter analyze`，通过后提交 `feat(art-style): add responsive reference extraction`。

### Task 3: 对照记录与全量离线验证

**Files:**
- Modify: `docs/parity/master-checklist.md`
- Modify: `docs/parity/feature-parity-execution-report.md`
- Modify: `docs/superpowers/plans/2026-07-21-art-style-reference-extraction.md`

- [ ] 仅当双端回填、失败保护、无自动保存和引擎图片边界均有测试证据时，把 `W7E-ARTSTYLE-EXTRACT-001` 更新为已验证等价；明确真实供应商与视频未测试。
- [ ] 运行 `node tool/parity/check_no_orphans.js && cd app && flutter test --concurrency=1 --reporter compact && flutter analyze && flutter build macos --debug && cd .. && git diff --check`。
- [ ] 仅提交上述对照文档和计划，提交信息 `docs(parity): close art style extraction gap`。
