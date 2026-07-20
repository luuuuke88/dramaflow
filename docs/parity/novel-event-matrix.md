# 小说与事件模块对照

状态：**小说章节管理页已验证等价；事件规范化表仍有一项引擎层扩展待收口。**

本页只记录用户可观察行为，不把源码中未进入打包产物的遗留组件误算为产品功能。验证只使用临时 SQLite 与假供应商；没有提交真实文本、图片或视频请求，视频生成仍由后续人工验收。

## 基线与判定

| 维度 | 证据 | 结论 |
| --- | --- | --- |
| 原版版本 | `ToonFlow.app/Contents/Resources/data/version.txt` = `1.1.8` | 固定为本轮比对基线。 |
| 原版主页面 | `Toonflow-web/src/views/novel/index.vue:5-102`；打包版含 `/novel/event/generateEvents` 与 `/novel/getNovelEventState` 调用链 | 小说章节管理是有效功能。 |
| 事件列表遗留页 | `src/views/novel/components/event.vue` 存在，但无页面导入或路由引用；打包产物不含 `/novel/event/getEvent` 请求 | 不是 1.1.8 用户可进入的页面。 |
| 事件分析遗留页 | `src/views/novel/components/eventAnalysis.vue` 存在，但无页面导入或路由引用；打包产物不含 `/novel/event/eventAnalysis` 请求 | 不是 1.1.8 用户可进入的页面。 |

## 主链逐项对照

| 用户行为 | ToonFlow 1.1.8 | DramaFlow Flutter | 结论 |
| --- | --- | --- | --- |
| 导入 `.txt` / `.docx`、10 MB 上限、解析并选择章节 | `importNovel.vue:146-220` | `import_novel_dialog.dart:73-122`，`novel_parse.dart` | 已验证等价。 |
| 保存新章节后自动提取事件 | `addNovel.ts:30-50` 直接启动 `cleanNovel.start` | `novel.dart:75-97` 经 `onNovelsAdded` 接入 `events.dart` 同一流水线 | 已验证等价。 |
| 对选中章节重新生成事件 | 主页面唯一“事件分析”按钮确认后提交 `/novel/event/generateEvents`，`index.vue:272-289` | 唯一“事件分析”按钮在 `novel_screen.dart:93-112,257-263` 经费用确认策略后提交 `generateEvents` | 已验证等价。费用确认是本产品统一的调用前保护，不改变确认后任务、章节状态或可见结果。 |
| 事件状态刷新与生成中操作限制 | 原版每 3 秒查询未完成章节，且 `eventState == 0` 禁用编辑/删除，`index.vue:54-56,88-94,292-327` | 队列变更驱动刷新；`novel_screen.dart:197-215` 同样禁用两项行操作 | 已验证等价。响应式本地刷新替代网络轮询，用户可见终态一致。 |
| 成功/失败/详情、编辑、搜索、分页、单条与批量删除 | `index.vue:32-105,197-269` | `novel_screen.dart:114-357`、`novel.dart` | 已由 engine/widget 回归覆盖。 |

## 本轮页面收口

| 编号 | 原差异 | 已实施的收口 | 回归证据 |
| --- | --- | --- | --- |
| NE-01 | 小说页可切换“事件”Tab，暴露原版未挂载的 `event.vue` | `NovelScreen` 不再导入 `event_tab.dart`，仅渲染章节管理页 | `novel_screen_test.dart` 的“移动端小说页只保留原版事件分析入口并为选中章节入队”断言无 `TabBar`。 |
| NE-02 | “事件分析”会打开 Flutter 独有 LLM 汇总视图 | 删除 `NovelScreen` 对 `event_analysis_view.dart` 的入口；原版同名按钮现在直接排队生成章节事件 | 同一移动端用例断言唯一入口直接生成 `event_generation` 任务；桌面用例断言未选择时禁用、选择后只提交目标章节。 |
| NE-03 | 生成中的章节仍可编辑或删除 | `operationCell` 以 `eventState == 0` 禁用编辑和删除 | `novel_screen_test.dart` 的“事件生成中禁用章节的编辑和删除操作”。 |

`event_tab.dart` 与 `event_analysis_view.dart` 暂保留为未路由的内部代码，便于后续完整审计；它们不再从小说页或任意导航入口可达，因此不构成 1.1.8 用户功能。

## 仍待处理的引擎差异

| 编号 | Flutter 当前行为 | 原版基线 | 判定与后续位置 |
| --- | --- | --- | --- |
| NE-04 | `events.dart` 在每章事件生成成功后额外写入 `o_event/o_eventChapter`，并保留事件查询、删除、汇总 API | `generateEvents.ts:17-36` 只写 `o_novel.event/eventState/errorReason`；两张事件表在 1.1.8 的可达流程中没有写入方 | **未收口**。这不是小说页入口差异，但会产生原版没有的持久化数据，并可能被剧本选择器/助手内部 API 使用；总表 `W9A-DBTABLE-EVENT-001` 保持“部分实现”，后续按其独立任务审计。 |

## 自动化证据

本轮在当前基线执行：

```bash
cd /Users/luke/Documents/aivideo/dramaflow/app
flutter test --concurrency=1 \
  test/engine/events_test.dart test/engine/novel_crud_test.dart \
  test/engine/novel_parse_test.dart test/widgets/import_novel_dialog_test.dart \
  test/widgets/novel_screen_test.dart test/widgets/script_screen_test.dart
flutter analyze lib/src/engine/events.dart lib/src/engine/novel.dart \
  lib/src/engine/novel_parse.dart lib/src/screens/novel/novel_screen.dart \
  lib/src/screens/novel/import_novel_dialog.dart \
  lib/src/screens/novel/edit_novel_dialog.dart
```

结果：**53 条测试通过，静态分析零诊断。**

重点 widget 用例同时覆盖桌面和移动端：

- “勾选章节后「事件分析」按钮为选中章节入队 event_generation 任务”
- “移动端小说页只保留原版事件分析入口并为选中章节入队”
- “事件生成中禁用章节的编辑和删除操作”

## 结论

`W6-NOVEL-001` 的页面级缺口 `NE-01` 至 `NE-03` 已由源码、桌面/移动端回归共同证明关闭，可以上调为**已验证等价**。这不等于事件模块所有内部数据流已经完全复刻：`NE-04` 仍明确列为待处理，不会被页面级结论覆盖。
