# 塑角造景页面等价实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `CornerScapeScreen` 恢复为 ToonFlow 的角色、场景、道具批量参考图工作台，并保留通用资产音频关联操作。

**Architecture:** 页面只派生 `Engine` 的资产、图片历史、队列和通用资产音频绑定数据。批量图片继续调用 `generateAssetImages`，单图选择继续调用 `saveAssetImage`，取消继续调用 `cancelJob`；UI 不直接访问数据库或供应商。历史名为 `o_assetsRole2Audio` 的表由通用 API 复用，不做 schema 迁移。桌面以设置栏和卡片网格组织，窄屏改为纵向设置与全屏详情页。

**Tech Stack:** Flutter、Riverpod、SQLite/Drift 兼容引擎、现有任务队列、Flutter widget tests、假 ProviderGateway。

## Global Constraints

- 对照基线是 `/Users/luke/Documents/aivideo/Toonflow-web/src/views/cornerScape/index.vue`。
- 不调用任何真实图像、文本、语音或视频服务；视频生成代码不改。
- 新行为必须先有失败测试，桌面与 390dp 至少各验证一个真实入口。
- 不新增数据库表、供应商协议、队列 lane 或重复的图片/音频模型。
- 每完成一个任务更新本计划复选框；所有完成证据写入 `docs/parity/`，不写流水账。

---

### Task 1: 资产卡片数据适配与可取消任务定位

**Files:**
- Modify: `app/lib/src/engine/assets.dart`
- Modify: `app/test/engine/assets_test.dart`

**Interfaces:**
- Consumes: `AssetRow`, `AssetImageRow`, `Engine.projectJobs`, `Engine.cancelJob`。
- Produces: `CornerScapeAsset` 只读记录和 `Engine.cornerScapeAssets(int projectId, {Set<String> types})`；`Engine.cornerScapeImageTaskId(int assetsId)` 返回生成中图片对应的 `asset_image_generation` 任务 id 或 `null`。

- [x] **Step 1: 写失败的引擎测试**

```dart
test('cornerScapeAssets 按角色/场景/道具筛选并附带历史图与当前状态', () {
  final role = engine.addAsset(projectId: projectId, type: 'role', name: '甲', describe: '');
  final scene = engine.addAsset(projectId: projectId, type: 'scene', name: '山门', describe: '');
  engine.saveAssetImage(assetsId: role, projectId: projectId, type: 'role', base64Image: base64Encode([1, 2, 3]));
  final result = engine.cornerScapeAssets(projectId, types: {'role'});
  expect(result.single.asset.id, role);
  expect(result.single.images, hasLength(1));
  expect(result.single.asset.imageState, stateDone);
  expect(result.map((item) => item.asset.id), isNot(contains(scene)));
});
```

- [x] **Step 2: 运行失败测试**

Run: `cd app && flutter test --concurrency=1 test/engine/assets_test.dart --name cornerScapeAssets`

Expected: fail because `cornerScapeAssets` does not exist.

- [x] **Step 3: 实现最小只读适配**

```dart
class CornerScapeAsset {
  final AssetRow asset;
  final List<AssetImageRow> images;
  const CornerScapeAsset({required this.asset, required this.images});
}

List<CornerScapeAsset> cornerScapeAssets(int projectId, {Set<String> types = const {'role', 'scene', 'tool'}}) {
  final values = <CornerScapeAsset>[];
  for (final type in types) {
    final rows = getAssets(projectId, type: type, page: 1, limit: 10000).data;
    values.addAll(rows.map((asset) => CornerScapeAsset(asset: asset, images: assetImages(asset.id))));
  }
  return values;
}
```

Implement task lookup by reading active `asset_image_generation` task payload `items[].assetsId`, never infer it from the image row alone.

- [x] **Step 4: 验证通过**

Run: `cd app && flutter test --concurrency=1 test/engine/assets_test.dart --name cornerScapeAssets`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add app/lib/src/engine/assets.dart app/test/engine/assets_test.dart
git commit -m "feat(cornerscape): expose asset generation state"
```

### Task 2: 通用资产音频关联

**Files:**
- Modify: `app/lib/src/engine/audio_bind.dart`
- Modify: `app/test/engine/audio_bind_test.dart`

**Interfaces:**
- Consumes: `o_assetsRole2Audio`（历史列名 `assetsRoleId` 代表任意父资产）、`Engine.audioPool`、既有 `RoleAudioBinding` API。
- Produces: `AssetAudioBinding`、`Engine.assetAudioBindings(int projectId, {Set<String> types})`、`Engine.bindAssetAudio(int assetId, int? audioAssetId)`；`roleAudioBindings`、`bindRoleAudio` 保持可用，内部委托通用 API。

- [x] **Step 1: 写失败的通用关联测试**

```dart
test('场景和道具可以复用原有关联表绑定音频，角色兼容 API 不回归', () {
  final scene = engine.addAsset(projectId: projectId, type: 'scene', name: '山门', describe: '雪夜');
  final tool = engine.addAsset(projectId: projectId, type: 'tool', name: '灵剑', describe: '长剑');
  final role = engine.addAsset(projectId: projectId, type: 'role', name: '林朝雪', describe: '剑客');
  final audio = engine.addAsset(projectId: projectId, type: 'audio', name: '低音男声', describe: '');
  engine.bindAssetAudio(scene, audio);
  engine.bindAssetAudio(tool, audio);
  engine.bindRoleAudio(role, audio);
  expect(engine.assetAudioBindings(projectId).map((row) => row.assetId), containsAll([scene, tool, role]));
  expect(engine.roleAudioBindings(projectId).single.audioAssetId, audio);
});
```

- [x] **Step 2: 运行失败测试**

Run: `cd app && flutter test --concurrency=1 test/engine/audio_bind_test.dart --name 场景和道具可以复用`

Expected: fail because only role-specific query and binding APIs exist.

- [x] **Step 3: 实现泛化且兼容的关联 API**

```dart
class AssetAudioBinding {
  final int assetId;
  final String? assetName;
  final String assetType;
  final int? audioAssetId;
  final String? audioName;
  const AssetAudioBinding({required this.assetId, required this.assetName, required this.assetType, required this.audioAssetId, required this.audioName});
}

void bindAssetAudio(int assetId, int? audioAssetId) {
  db.execute('DELETE FROM o_assetsRole2Audio WHERE assetsRoleId=?', [assetId]);
  if (audioAssetId != null) db.execute('INSERT INTO o_assetsRole2Audio (assetsAudioId,assetsRoleId) VALUES (?,?)', [audioAssetId, assetId]);
}
```

`batchBindAudio` 的 payload 改为 `assetIds`，工具结果读取 `assetId`；为已有队列记录和角色测试兼容，读取时也接受旧 `roleIds`/`roleId` 字段。提示词必须显示资产类型，且仅允许项目内角色、场景、道具和项目内音频 id。

- [x] **Step 4: 验证通过**

Run: `cd app && flutter test --concurrency=1 test/engine/audio_bind_test.dart`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add app/lib/src/engine/audio_bind.dart app/test/engine/audio_bind_test.dart
git commit -m "feat(cornerscape): generalize asset audio bindings"
```

### Task 3: 桌面批量生图工作台

**Files:**
- Modify: `app/lib/src/screens/cornerscape/corner_scape_screen.dart`
- Modify: `app/test/widgets/corner_scape_screen_test.dart`
- Modify: `app/lib/src/engine/pipeline_policy.dart`
- Modify: `app/test/engine/pipeline_policy_test.dart`
- Modify: `app/lib/l10n/app_zh.arb`
- Modify: `app/lib/l10n/app_en.arb`
- Modify: `app/lib/l10n/app_ja.arb`

**Interfaces:**
- Consumes: `Engine.cornerScapeAssets`, `Engine.assetAudioBindings`, `Engine.generateAssetImages`, `Engine.polishAssetPrompt`, `confirmPolicyAction`。
- Produces: card grid type filter and quick selection state; `Key('cornerscape-card-<assetId>')`; `Key('cornerscape-cancel-<assetId>')`.

- [x] **Step 1: 写失败的桌面入口测试**

```dart
testWidgets('桌面塑角造景按类型筛选未生成资产并以模型和分辨率发起批量图片任务', (tester) async {
  final role = engine.addAsset(projectId: projectId, type: 'role', name: '林朝雪', describe: '', prompt: '剑客');
  engine.addAsset(projectId: projectId, type: 'scene', name: '山门', describe: '', prompt: '雪夜');
  await tester.pumpWidget(app(width: 1400));
  await tester.tap(find.text('角色'));
  await tester.tap(find.text('选择未生成'));
  await tester.tap(find.text('2K'));
  await tester.tap(find.widgetWithText(FilledButton, '开始批量生成'));
  final task = engine.projectJobs(projectId).singleWhere((job) => job.taskClass == 'asset_image_generation');
  expect(task.relatedObjectsJson['ids'], [role]);
  expect(task.relatedObjectsJson['resolution'], '2K');
});
```

- [x] **Step 2: 运行失败测试**

Run: `cd app && flutter test --concurrency=1 test/widgets/corner_scape_screen_test.dart --name 桌面塑角造景按类型筛选`

Expected: fail because the screen contains only the audio binding list.

- [x] **Step 3: 实现页面结构和批量动作**

Replace the audio-only list with `LayoutBuilder`:

```dart
final compact = constraints.maxWidth < 840;
return compact
  ? Column(children: [settingsPanel, Expanded(child: cardGrid)])
  : Row(children: [SizedBox(width: 328, child: settingsPanel), Expanded(child: cardGrid)]);
```

The settings panel must provide role/scene/tool `FilterChip`s, all original quick selections, model selection, 1K/2K/4K `SegmentedButton`, prompt textarea, count label, prompt-generation button, audio-match button, image-generation button and preview button. Selection is always intersected with currently visible asset ids after filters change. `startBatch` calls `confirmPolicyAction` with `taskClass: 'asset_image_generation'`, then `generateAssetImages(projectId, selected.map((id) => (assetsId: id, refImageBase64: null)).toList(), model: selectedModel, resolution: resolution)`. Audio matching passes all selected visible asset ids to the generalized `batchBindAudio` API.

Cards must represent empty, generating, failed and completed image states with fixed-height previews; card taps open detail only when not generating.

- [x] **Step 4: 验证通过**

Run: `cd app && flutter test --concurrency=1 test/widgets/corner_scape_screen_test.dart --name 桌面塑角造景按类型筛选`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add app/lib/src/screens/cornerscape/corner_scape_screen.dart app/test/widgets/corner_scape_screen_test.dart app/lib/l10n
git commit -m "feat(cornerscape): restore batch image workspace"
```

### Task 4: 详情、历史图、提示词和取消

**Files:**
- Modify: `app/lib/src/screens/cornerscape/corner_scape_screen.dart`
- Modify: `app/test/widgets/corner_scape_screen_test.dart`

**Interfaces:**
- Consumes: `Engine.assetImages`, `Engine.saveAssetImage`, `Engine.updateAsset`, `Engine.polishAssetPrompt`, `Engine.cornerScapeImageTaskId`, `Engine.cancelJob`, generic asset audio APIs, shared action policy.
- Produces: desktop side sheet / mobile full-screen detail form, historical image selection and cancellation confirmation.

**Review correction:** `asset_prompt_polish` must pass the shared money-confirmation gate and reject an empty prompt before it can enqueue. Add the semantically correct non-queue destructive key `cancel_generation` to `destructiveActionKeys`; task cancellation must use that key rather than `delete_assets`. Cover both keys and the confirm/reject branches with engine/widget tests.

- [ ] **Step 1: 写失败的详情测试**

```dart
testWidgets('选择历史图会保存为当前图，生成中卡片经确认取消任务', (tester) async {
  final assetId = engine.addAsset(projectId: projectId, type: 'role', name: '林朝雪', describe: '', prompt: '剑客');
  engine.saveAssetImage(assetsId: assetId, projectId: projectId, type: 'role', base64Image: base64Encode([1, 2, 3]));
  engine.saveAssetImage(assetsId: assetId, projectId: projectId, type: 'role', base64Image: base64Encode([4, 5, 6]));
  final historyId = db.select('SELECT id FROM o_image WHERE assetsId=? ORDER BY id ASC', [assetId]).first['id'] as int;
  await tester.pumpWidget(app(width: 1400));
  await tester.tap(find.byKey(Key('cornerscape-card-$assetId')));
  await tester.tap(find.byKey(Key('cornerscape-history-image-$historyId')));
  expect(engine.assetsByIds([assetId]).single.imageId, historyId);
  final taskId = engine.generateAssetImages(projectId, [(assetsId: assetId, refImageBase64: null)]);
  await tester.pump();
  await tester.tap(find.byKey(Key('cornerscape-cancel-$assetId')));
  await tester.tap(find.text('确认'));
  expect(engine.projectJobs(projectId).singleWhere((job) => job.id == taskId).state, 'failed');
  expect(EngineException.fromReasonJson(db.select('SELECT reason FROM o_tasks WHERE id=?', [taskId]).single['reason'] as String)!.errKey, errCanceled);
});
```

- [ ] **Step 2: 运行失败测试**

Run: `cd app && flutter test --concurrency=1 test/widgets/corner_scape_screen_test.dart --name 选择历史图会保存`

Expected: fail because there is no asset detail UI or cancellation action.

- [ ] **Step 3: 实现详情与取消**

Use `showDFAdaptiveDialog` for detail instead of a platform-specific drawer. Its title shows asset name and type. Include:

- horizontal image history with deterministic `cornerscape-history-image-<id>` keys; selecting an image calls `saveAssetImage` with current prompt and type;
- a prompt `TextField` persisting with `updateAsset` on blur;
- image model and resolution controls; AI polish calls `polishAssetPrompt`; regenerate passes the one asset to `generateAssetImages` through the shared confirmation gate;
- every role/scene/tool asset shows the audio selector, unbind and existing audition button through the generic asset audio API;
- cancelled task confirmation calls `engine.cancelJob(taskId)` and refreshes through `jobsGenerationProvider`.

- [ ] **Step 4: 验证通过**

Run: `cd app && flutter test --concurrency=1 test/widgets/corner_scape_screen_test.dart --name 选择历史图会保存`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/screens/cornerscape/corner_scape_screen.dart app/test/widgets/corner_scape_screen_test.dart app/lib/src/engine/pipeline_policy.dart app/test/engine/pipeline_policy_test.dart
git commit -m "feat(cornerscape): add asset detail and task cancellation"
```

### Task 5: 390dp 可用性与回归收口

**Files:**
- Modify: `app/test/widgets/corner_scape_screen_test.dart`
- Modify: `docs/parity/master-checklist.md`
- Modify: `docs/parity/feature-parity-execution-report.md`

**Interfaces:**
- Consumes: Task 1–3 public Engine and UI APIs.
- Produces: desktop and mobile test evidence; final parity documentation.

- [ ] **Step 1: 写失败的移动端测试**

```dart
testWidgets('390dp 塑角造景可筛选资产、选择卡片、打开详情并发起批量生成', (tester) async {
  tester.view.physicalSize = const Size(390, 667);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  engine.addAsset(projectId: projectId, type: 'role', name: '林朝雪', describe: '', prompt: '剑客');
  engine.addAsset(projectId: projectId, type: 'scene', name: '山门雪夜', describe: '', prompt: '雪夜');
  engine.addAsset(projectId: projectId, type: 'tool', name: '灵剑', describe: '', prompt: '长剑');
  await tester.pumpWidget(app(width: 390));
  await tester.tap(find.text('场景'));
  await tester.tap(find.text('选择未生成'));
  await tester.dragUntilVisible(find.text('开始批量生成'), find.byKey(const Key('cornerscape-scroll')), const Offset(0, -80));
  await tester.tap(find.text('开始批量生成'));
  expect(engine.projectJobs(projectId).any((job) => job.taskClass == 'asset_image_generation'), isTrue);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: 运行失败测试**

Run: `cd app && flutter test --concurrency=1 test/widgets/corner_scape_screen_test.dart --name 390dp 塑角造景`

Expected: fail because the old audio-only layout has no asset type filter or image generation command.

- [ ] **Step 3: 实现窄屏布局收口**

Give the outer vertical body `Key('cornerscape-scroll')`; ensure the settings section wraps controls, the grid uses one column, the selected-count and action controls stay reachable, and every card/asset detail action has a touchable text or icon button. No fixed width may exceed the 390dp viewport.

- [ ] **Step 4: 运行完整针对性验证**

Run:

```bash
cd app
flutter test --concurrency=1 test/widgets/corner_scape_screen_test.dart test/engine/assets_test.dart test/engine/audio_bind_test.dart
flutter analyze
flutter build macos --debug
cd .. && node tool/parity/check_no_orphans.js
```

Expected: all tests pass, analyzer reports no issues, debug application builds, parity checker reports all inventory items covered.

- [ ] **Step 5: 更新对照文档并提交**

Set `W6-CORNERSCAPE-002` to “已验证等价” only when desktop and 390dp evidence covers filters, shortcuts, preview, cancel, history switch, prompt/regenerate and generic asset audio behavior. Record that real provider image/video generation remains user-owned final acceptance.

```bash
git add app/test/widgets/corner_scape_screen_test.dart docs/parity/master-checklist.md docs/parity/feature-parity-execution-report.md
git commit -m "docs(parity): verify cornerscape workspace"
```
