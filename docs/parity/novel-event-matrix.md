# 小说与事件模块对照

状态：**核心链路已验证，页面级 1:1 尚未收口**。

本页只记录可观察行为，不把源码中未进入打包产物的遗留组件误算为产品功能。验证不触发真实文本、图片或视频供应商；视频生成仍由后续人工验收。

## 基线与判定

| 维度 | 证据 | 结论 |
| --- | --- | --- |
| 原版版本 | `ToonFlow.app/Contents/Resources/data/version.txt` = `1.1.8` | 固定为本轮比对基线。 |
| 原版主页面 | `Toonflow-web/src/views/novel/index.vue`，且打包版 `data/web/index.html` 含同一 `/novel/event/generateEvents` 与 `/novel/getNovelEventState` 调用链 | 小说章节管理页是有效功能。 |
| 事件列表遗留页 | `src/views/novel/components/event.vue` 存在，但无页面导入或路由引用；打包产物中仅保留多语言文案，不含 `/novel/event/getEvent` 请求 | 不是 1.1.8 用户可进入的页面。 |
| 事件分析遗留页 | `src/views/novel/components/eventAnalysis.vue` 存在，但无页面导入或路由引用；打包产物中不含 `/novel/event/eventAnalysis` 请求 | 不是 1.1.8 用户可进入的页面。 |

## 主链逐项对照

| 用户行为 | ToonFlow 1.1.8 | DramaFlow Flutter | 结论 |
| --- | --- | --- | --- |
| 导入 `.txt` / `.docx`、10 MB 上限、解析并选择章节 | `importNovel.vue:146-220` | `import_novel_dialog.dart:73-122`，`novel_parse.dart` | 已验证等价。 |
| 保存新章节后自动提取事件 | `addNovel.ts:30-50` 直接启动 `cleanNovel.start` | `novel.dart:75-97` 通过 `onNovelsAdded`；`events.dart:37-42` 接入同一事件生成流水线 | 已验证等价。 |
| 对选中章节重新生成事件 | 主页面“事件分析”确认框提交 `/novel/event/generateEvents`，`index.vue:272-289` | `NovelScreen` 的“生成事件”提交 `generateEvents`，`novel_screen.dart:95-114` | 引擎语义等价；标签与入口数量不同，见下方缺口。 |
| 事件状态刷新 | 原版每 3 秒查询未完成章节，`index.vue:292-327` | 队列变更驱动 UI 刷新，`novel_screen.dart:197-201` | 已验证更优的同等可见结果；不做网络轮询。 |
| 成功/失败/详情、编辑、搜索、分页、单条与批量删除 | `index.vue:32-105,197-269` | `novel_screen.dart`、`novel.dart` | 已由 engine/widget 回归覆盖。 |

## 当前页面级差异

| 编号 | 当前 Flutter 行为 | 为什么不属于原版 1.1.8 | 处理方向 |
| --- | --- | --- | --- |
| NE-01 | 小说页出现可切换的“事件”Tab，含事件搜索、重生成、删除和独立 `o_event` 数据流 | 对应原版 `event.vue` 没有被路由或主页面挂载，打包版也没有该请求实现 | 需要在后续收口时从用户入口移除或明确隐藏；数据迁移和引擎代码暂不删除。 |
| NE-02 | “事件分析”会打开 `event_analysis_view.dart`，再发起一次 LLM 汇总分析 | 原版同名按钮实际只重新提交章节事件提取；`eventAnalysis.vue` 未进打包版且后端没有对应路由 | 需要把原版入口语义复原为事件生成；独立分析能力先保留为内部代码，不作为小说页功能。 |

## 已有自动化证据

| 范围 | 用例 |
| --- | --- |
| 事件提取、并发、失败落库、冷启动恢复、事件关联 | `app/test/engine/events_test.dart` |
| 章节 CRUD、导入解析与分页 | `app/test/engine/novel_crud_test.dart`、`app/test/engine/novel_parse_test.dart` |
| 移动/桌面小说页、导入与选中章节生成 | `app/test/widgets/novel_screen_test.dart` |
| 额外事件 Tab | `app/test/widgets/event_tab_test.dart`，该测试证明实现存在，不可作为原版等价证据。 |

## 结论

章节导入、自动事件提取、重新生成、状态展示与 CRUD 已有足够的源码和测试证据。当前未达到“页面级 1:1”的原因不是漏做，而是多暴露了原版没有接通的事件列表与分析界面。总清单的 `W6-NOVEL-001` 因此维持为**部分实现**，直到 `NE-01`、`NE-02` 完成收口并回归验证。
