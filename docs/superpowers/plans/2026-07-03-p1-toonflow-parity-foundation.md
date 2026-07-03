# P1：ToonFlow 对齐地基（schema v3 + i18n + 设计系统 + 导航壳 + 项目/章节/事件/剧本）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **本仓执行约定**：任务卡由审核方（Claude）改写为 codex 规格后 `codex exec --full-auto -C /Users/luke/Documents/aivideo/dramaflow "<spec>"` 执行；codex 沙箱跑不了 `flutter test`/`git commit`，**验证与提交一律由审核方完成**。

**Goal:** 按 spec `docs/superpowers/specs/2026-07-03-v0.3-toonflow-parity-design.md` 完成 P1 批次：引擎数据模型换成 ToonFlow 22 表、三语 i18n 基建、设计系统 v2、ToonFlow 导航壳、项目/章节/事件/剧本四组页面 1:1 移植。

**Architecture:** 底座（JobQueue/MediaStore/ProviderGateway/零 ffmpeg 合成）不动；引擎业务层与全部页面推倒重建。「抄」的唯一基准 = `/Users/luke/Documents/aivideo/Toonflow-web/src`（UI/文案/交互）与 `/Users/luke/Documents/aivideo/Toonflow-app/src`（契约/状态机/提示词流），本计划已把关键契约抠成任务卡。

**Tech Stack:** Flutter 3.44+ / Riverpod 3 / go_router / sqlite3 / dio / gen-l10n / archive(docx)

## Global Constraints（每个任务隐含遵守）

- `flutter analyze` 零告警 + `flutter test` 全绿是合入门槛（跑于 `app/`）。
- 引擎纯 Dart（`app/lib/src/engine/` 禁止 import flutter）。
- **UI 禁止硬编码文案**：一律 `AppLocalizations.of(context)`，每个字符串必须同时有 zh/en/ja 三条 ARB；zh 值照抄 Toonflow-web 语言包/源码，en/ja 优先取自 `docs/reference/toonflow-locales/`（T1 引入），缺失才自行翻译。
- **引擎错误禁止裸中文**：抛 `EngineException(errKey, errParams)`（T3 定义），任务表存 `reason` = JSON `{"key":...,"params":{...}}`。
- 表名/字段名与 ToonFlow `database.d.ts` 逐字一致（camelCase、含 `describe` 这类别扭名，不许"改进"）。
- 状态枚举值逐字一致：`o_novel.eventState` 0=生成中/1=成功/-1=失败；`o_script.extractState` 0=提取中/1=成功/-1=失败/2=待提取；`o_tasks.state` pending/processing/success/failed。
- 每个页面交付即含**桌面（≥840，抄 ToonFlow 布局）+ 移动（<840，同功能自适配：表格→卡片、对话框→全屏页、侧栏→底栏）**两形态。
- schema 只经 `initSchema` + `PRAGMA user_version`；v3 检测到旧版本直接**删库重建**（spec 已定：旧数据不要）。
- `server/` 与 `Toonflow-*` 参照目录只读。
- conventional commits；每任务一提交。

## File Structure（P1 落点总览）

```
app/l10n.yaml                                  # T1 新建
app/lib/l10n/app_zh.arb|app_en.arb|app_ja.arb  # T1 新建（后续任务追加条目）
docs/reference/toonflow-locales/*.json          # T1 引入（zh-CN/en/ja_JP 参照包）
app/lib/src/theme/tokens.dart                  # T2 新建（DFColors v2 全量 token）
app/lib/src/theme/theme.dart                   # T2 重写（旧 theme.dart 移入）
app/lib/src/widgets/df_*.dart                  # T2 新建（DFPageScaffold/DFDataTable/DFStatusTag/DFEmpty/DFAdaptiveDialog/DFTagChip/DFSearchField）
app/lib/src/engine/errors.dart                 # T3 新建（EngineException + errKey 常量）
app/lib/src/engine/db.dart                     # T3 重写 initSchema→v3（26 表）
app/lib/src/engine/queue.dart                  # T3 改造（jobs→o_tasks、reason=JSON）
app/lib/src/engine/config.dart                 # T4 改造（o_setting/o_vendorConfig/o_prompt）
app/lib/src/engine/providers/resolve.dart      # T4 适配新表
app/lib/src/engine/novel.dart                  # T5 新建（章节 CRUD+导入解析）
app/lib/src/engine/novel_parse.dart            # T5 新建（parseNovel Dart 移植 + docx 提取）
app/lib/src/engine/events.dart                 # T6 新建（事件提取/查询/分析）
app/lib/src/engine/scripts.dart                # T7 新建（剧本 CRUD+提取资产）
app/lib/src/engine/providers/gateway.dart      # T7 增 generateToolJson
app/lib/src/engine/engine.dart                 # T3-T7 门面逐步重写
app/lib/src/screens/shell.dart                 # T8 重写（ToonFlow 壳）
app/lib/src/screens/project/*.dart             # T9 新建（列表+对话框+模型选择器）
app/lib/src/screens/manuals/*.dart             # T10 新建（视觉/导演手册画廊+MD 编辑器）
app/lib/src/engine/manuals.dart                # T10 新建（手册文件包存储）
app/lib/src/screens/novel/*.dart               # T11 新建（章节表+两步导入+事件 tab+事件分析）
app/lib/src/screens/script/*.dart              # T12 新建（剧本卡片流+三对话框）
app/tool/populate_demo.dart / e2e_smoke.dart   # T13 重写 v3
删除：screens/{project_screen,novel_screen,assets_screen,episode_screen,shots_screen}.dart 旧版、engine/{pipeline/,director.dart,compose.dart 中 episode 依赖部分——compose 接口保留（P4 复用），episode 绑定改挂 o_script}
```

**P1 交付边界**：素材库/制作画布/配音页 P1 不实现——导航项存在但禁用态+徽标「P2/P3/P4」；任务中心与设置页**改读新表后保留**（完整重设计在 P5）。旧 v0.2 的 assets/episode/shots 页面与 pipeline runners 一并删除（推倒重建已定，不留死代码）。

---

### Task 1：i18n 基建（gen-l10n 三语 + 参照包引入）

**Files:**
- Create: `app/l10n.yaml`、`app/lib/l10n/app_zh.arb`、`app/lib/l10n/app_en.arb`、`app/lib/l10n/app_ja.arb`
- Create: `docs/reference/toonflow-locales/`（zh-CN.json/en.json/ja_JP.json 参照副本）
- Modify: `app/pubspec.yaml`（flutter_localizations + intl + `generate: true`）、`app/lib/src/app.dart`（localizationsDelegates/supportedLocales/locale）
- Modify: `app/lib/src/state/providers.dart`（`localeProvider`）
- Test: `app/test/l10n_test.dart`

**Interfaces:**
- Produces: `AppLocalizations`（`context.l10n` 扩展 getter，放 `app/lib/src/util/l10n_ext.dart`）；`localeProvider`：`NotifierProvider<LocaleNotifier, Locale?>`，`Locale?` null=跟随系统，`setLocale(Locale?)` 持久化到 `o_setting` key=`app.locale`（值 `zh`/`en`/`ja`/空=系统）——**T3 之前 o_setting 未建，先落现有 settings 表，T3 迁移由删库重建自然完成**。
- ARB 键名规约（后续所有任务遵守）：ToonFlow `$t("workbench.novel.col.chapter")` → `novelColChapter`（去 `workbench.` 前缀后逐段驼峰）；错误码 `errXxx`；通用动作 `commonSave`/`commonCancel`…

- [ ] **Step 0（审核方执行）**：把参照包复制进仓库：
```bash
mkdir -p /Users/luke/Documents/aivideo/dramaflow/docs/reference/toonflow-locales
cp /Users/luke/Documents/aivideo/Toonflow-web/src/locales/language/{zh-CN,en,ja_JP}.json \
   /Users/luke/Documents/aivideo/dramaflow/docs/reference/toonflow-locales/
```
- [ ] **Step 1（codex）**：接 gen-l10n；ARB 首批条目 = 三个语言包里 `workbench.menu.*` 全部键 + `commonSave/commonCancel/commonConfirm/commonDelete/commonSearch/commonNextStep/commonPrevStep`（zh/en/ja 从参照包对应键取值）；写 `l10n_test.dart`：断言三语 delegate 可加载、`menuMyProject` 三语非空且互不相同。
- [ ] **Step 2（审核方）**：`cd app && flutter gen-l10n && flutter analyze && flutter test test/l10n_test.dart` 全绿。
- [ ] **Step 3（审核方）**：`git commit -m "feat(i18n): gen-l10n 三语基建（zh/en/ja）+ ToonFlow 语言包参照"`

### Task 2：设计系统 v2（tokens + 通用组件族）

**Files:**
- Create: `app/lib/src/theme/tokens.dart`、`app/lib/src/theme/theme.dart`（替换旧 `theme.dart`，旧文件删除）
- Create: `app/lib/src/widgets/df_page_scaffold.dart`、`df_data_table.dart`、`df_status_tag.dart`、`df_empty.dart`、`df_adaptive_dialog.dart`、`df_tag_chip.dart`、`df_search_field.dart`
- Test: `app/test/widgets/df_widgets_test.dart`

**Interfaces（Produces，后续所有 UI 任务只准从这里取样式）:**

> 设计定稿（frontend-design 已执行，2026-07-03）：方向「墨青×暖纸×琥珀」——浅色=暖纸底+墨青靛主色+片场琥珀点缀（工作室气质，区别于 TDesign 冷灰企业风）；暗色=放映厅暖黑。下表为最终值，Codex 逐字实现。

```dart
// tokens.dart —— 最终定稿值（浅色 / 深色）
class DFColors extends ThemeExtension<DFColors> {
  final Color bg;            // #F5F4F0 / #141419   暖纸页底 / 放映厅暖黑
  final Color surface;       // #FFFFFF / #1C1C24
  final Color surfaceMuted;  // #FAF9F6 / #22222C   表头/悬浮底/输入底
  final Color stroke;        // #E7E4DD / #2C2C38
  final Color strokeStrong;  // #D8D4CA / #3A3A48   选中描边/分隔强调
  final Color primary;       // #414CB2 / #8B93E8   墨青靛
  final Color primaryHover;  // #3540A0 / #A0A7F0
  final Color primarySubtle; // #EEEFFA / #262A45   主色淡底（选中行/激活 tag 底）
  final Color accent;        // #C97F1B / #E8A33D   片场琥珀（高光/选中节点/徽标）
  final Color textPrimary;   // #201F1B / #EDECE6
  final Color textSecondary; // #6B685F / #A5A299
  final Color textTertiary;  // #97938A / #6E6E7A   占位/时间戳
  final Color success;       // #2E9E63 / #4CC583
  final Color danger;        // #D9463E / #E86A62
  final Color warning;       // #DB8B1F / #D98E2B
  final Color running;       // = primary（运行态统一主色，转圈+primarySubtle 底）
  final Color focusRing;     // primary @40% 双端一致
}
// 非色 token（同文件常量类 DFTokens）：
// radius: shell 16 / card 12 / control 8 / chip 999
// 间距阶: 4 / 8 / 12 / 16 / 20 / 24 / 32
// 阴影: cardRest = [0,1,2,#201F1B@5%]（配 1px stroke 描边）；cardHover = [0,6,20,#201F1B@8%]；dialog = [0,24,48,#141419@18%]
// 动效: fast 120ms（hover/按压）/ standard 200ms（对话框/展开）/ emphasized 320ms（页面切换）曲线 easeOutCubic；骨架屏 shimmer 1200ms 循环
// 字阶: display 24/w700、title 20/w700、section 16/w600、body 14/w400、caption 12/w400；行高 1.5
// 字体: CJK 用系统栈（PingFang SC/HarmonyOS Sans 回退）；数字与时长用 tabular figures（FontFeature.tabularFigures()），不引入外挂字体（多端体积优先，P5 可再评估品牌字体）
```
```dart
// 组件族关键签名
class DFPageScaffold extends StatelessWidget { // 页级容器：标题区+工具栏区+内容区，统一 32px 边距
  const DFPageScaffold({required this.title, this.subtitle, this.toolbar, required this.body});
}
class DFDataTable extends StatelessWidget { // 桌面表格/移动卡片双形态 + 复选 + 分页
  const DFDataTable({required this.columns, required this.rows, this.selectable = false,
    this.selectedIds, this.onSelectionChanged, this.pagination, this.onPageChange,
    required this.mobileCardBuilder});
}
class DFStatusTag extends StatelessWidget { // 状态徽章：kind ∈ processing(转圈+文案)/success/failed(可点开错误)/pending
  const DFStatusTag({required this.kind, this.text, this.onTapError});
}
Future<T?> showDFAdaptiveDialog<T>(BuildContext c, {required String title, required WidgetBuilder builder,
  double desktopWidthFactor = .6}); // 桌面居中弹窗 / 移动全屏页
class DFEmpty extends StatelessWidget { const DFEmpty({required this.text, this.action}); }
class DFTagChip extends StatelessWidget { const DFTagChip({required this.label, this.onClose, this.tone}); }
class DFSearchField extends StatelessWidget { const DFSearchField({required this.hint, required this.onSearch, this.width = 260}); }
```

- [ ] **Step 1（审核方）**：调用 frontend-design skill 对基线 token 做视觉定稿（输出最终十六进制色值/字阶/阴影/圆角，回填本卡）。
- [ ] **Step 2（codex）**：实现 tokens+theme（双主题，`context.df` 保留）+ 七个组件；widget test：DFDataTable 在 900px 宽渲染 DataTable、380px 宽渲染卡片列表且 mobileCardBuilder 被调用；DFStatusTag processing 态含 CircularProgressIndicator；showDFAdaptiveDialog 两断点形态断言。
- [ ] **Step 3（审核方）**：analyze+test 全绿（旧页面若因 theme 改动编译报错，本任务内一并修引用，不改其行为）。
- [ ] **Step 4（审核方）**：`git commit -m "feat(theme): 设计系统 v2 tokens + DF 组件族（桌面/移动双形态）"`

### Task 3：schema v3（26 表）+ 错误码基建 + 队列改造

**Files:**
- Create: `app/lib/src/engine/errors.dart`
- Modify: `app/lib/src/engine/db.dart`（initSchema v3）、`app/lib/src/engine/queue.dart`、`app/lib/src/engine/engine.dart`（门面骨架：projects CRUD 先行）
- Delete: `app/lib/src/engine/pipeline/runners.dart` 及 episode/shot/asset 相关门面方法与旧表（v0.2 页面同步删除在 T8 前完成编译需要——本任务把旧 screens 从路由摘除并删文件，导航壳 T8 重建）
- Test: `app/test/engine/db_v3_test.dart`、`app/test/engine/errors_test.dart`

**Interfaces:**
- Produces:
```dart
class EngineException implements Exception {
  final String errKey; final Map<String, Object?> errParams;
  EngineException(this.errKey, [this.errParams = const {}]);
  String toReasonJson(); // {"key":errKey,"params":errParams}
  static EngineException? fromReasonJson(String? s);
}
// errKey 常量（ARB 同名条目三语，本任务补入）：
// errProviderMissing / errModelMissing / errNetwork / errLlmFormat / errCanceled / errAppRestart / errFileTooLarge / errFileType / errRegexInvalid / errNoChapters
```
- schema v3：26 张表 CREATE TABLE 语句字段=《database.d.ts》逐字（`o_novel.chapterIndex INTEGER`、`o_project.id INTEGER PRIMARY KEY`（AUTOINCREMENT，全表统一自增；ToonFlow 用 Date.now() 只是取巧，不抄）、TEXT/INTEGER 映射：string→TEXT、number→INTEGER、boolean→INTEGER）；索引：`o_novel(projectId,chapterIndex)`、`o_eventChapter(eventId)/(novelId)`、`o_scriptAssets(scriptId)`、`o_tasks(projectId,state)`。
- `PRAGMA user_version=3`；打开时 `user_version<3` → 关闭连接、删除 db 文件与 `-wal/-shm`、重建（**注意仅删数据库文件，不碰 media 目录**）。
- queue 改造：任务持久化到 `o_tasks`（state=pending/processing/success/failed；reason=EngineException JSON；relatedObjects=JSON `{"kind":"novel","ids":[...]}`；taskClass ∈ `event_generation`/`asset_extraction`（P1 两类，后批扩展））。冷启动恢复：processing→failed reason=`errAppRestart`，关联实体状态回置由各 runner 注册的 recover 回调处理（`queue.registerRecover(String taskClass, void Function(TasksRow) fn)`）。
- Engine 门面（本任务先落 projects）：
```dart
List<ProjectRow> projects();
int addProject({required String projectType, required String name, String? intro, String? type,
  String? artStyle, String? directorManual, String? videoRatio, String? imageModel,
  String? videoModel, String? imageQuality, String? mode});
void editProject(int id, {/* 同上全字段 */});
void deleteProject(int id); // 级联删除照抄 delProject：o_agentWorkData/o_novel/o_scriptAssets/o_script/o_assets2Storyboard/o_image/o_assets(imageId 置空后删)/o_tasks/o_videoTrack/o_video/memories(isolationKey LIKE 'id:%') + media/<id>/ 目录删除
```

- [ ] **Step 1（codex）**：先写失败测试：`db_v3_test.dart`（新库 user_version==3、22 表存在、旧版本文件被重建）、`errors_test.dart`（toReasonJson/fromReasonJson 往返、参数保序）、projects CRUD+级联删除测试（插入全链假数据→deleteProject→逐表 COUNT==0）；再实现至全绿。旧 screens/pipeline 删除与编译修复同卡完成。
- [ ] **Step 2（审核方）**：analyze+全量 test；确认 `flutter run -d macos` 可启动（临时首页允许为项目占位列表）。
- [ ] **Step 3（审核方）**：`git commit -m "feat(engine)!: schema v3（ToonFlow 22 表）+ EngineException 错误码 + o_tasks 队列"`

### Task 4：供应商/提示词/设置存储迁移

**Files:**
- Modify: `engine/config.dart`、`engine/providers/resolve.dart`、`engine/engine.dart`、`screens/settings_screen.dart`（仅改数据源，不改布局——P5 重设计）
- Test: `app/test/engine/config_v3_test.dart`

**Interfaces:**
- `o_vendorConfig`：id=协议实例 id（TEXT），`inputValues` JSON（baseUrl/apiKey/自定义头），`models` JSON 数组 `[{modelId,label,kind,enabled}]`，`enable` 0/1。resolve 层签名不变（stage→vendor+model），绑定存 `o_setting` key=`binding.<stage>`。
- `o_prompt` 出厂种子（`data`=默认、`useData`=用户覆写、type 为键）：`eventExtraction`、`scriptAssetExtraction`——**默认文案从 Toonflow-app 种子提示词逐字移植**（审核方 Step 0 把 `Toonflow-app` 中两段种子 prompt 抄入 `docs/reference/toonflow-prompts.md` 供 codex 取用）；`getPrompt(type)` 返回 `useData ?? data`。
- 平台种子照旧：桌面 azt(127.0.0.1:8787,key=local)+volcengine；移动 volcengine-only。
- 配置导出/导入 JSON 结构随新表调整，导入时校验版本字段 `configVersion:3`。

- [ ] **Step 0（审核方）**：提取两段种子提示词到 `docs/reference/toonflow-prompts.md`（源：Toonflow-app 内 o_prompt 种子/初始化 SQL，grep `eventExtraction`、`scriptAssetExtraction`）。
- [ ] **Step 1（codex）**：失败测试（种子后 vendors/prompts 可读、useData 覆写生效、binding resolve 三失败路径抛对应 errKey、导出→清库→导入等价）→ 实现全绿；settings 页改读新 API。
- [ ] **Step 2（审核方）**：analyze+test；设置页手工点一遍（供应商增删/测试连通/绑定下拉/提示词编辑保存重置）。
- [ ] **Step 3（审核方）**：`git commit -m "feat(engine): 供应商/提示词/设置迁移至 o_vendorConfig/o_prompt/o_setting"`

### Task 5：小说引擎（章节 CRUD + parseNovel 移植 + docx）

**Files:**
- Create: `engine/novel.dart`、`engine/novel_parse.dart`；Modify: `engine/engine.dart`；`pubspec.yaml` 加 `archive`
- Test: `app/test/engine/novel_parse_test.dart`、`novel_crud_test.dart`

**Interfaces（Produces）:**
```dart
// novel_parse.dart —— 逐行移植 Toonflow-web/src/utils/parseNovel.ts
// REEL_REGEX  = ^(第[\d一二三四五六七八九十百千]+卷)\s*([^\n第]*)   (multiLine)
// CHAPTER_REGEX 默认 = 第\s*([0-9０-９零一二三四五六七八九十百千万]+)\s*[章回节]\s*([^\n\r]*)
// 自定义正则设置 key: o_setting 'chapterReg'，支持 "/pattern/flags" 与裸 pattern 两种写法
// 中文数字解析 parseChineseNumber（零一二…九 + 十百千，"十X"特例）照抄
// 无卷 → 单卷 reel="正文卷"；无章匹配且全文非空 → index=1 chapter="" 全文一章；章按 index 升序
List<ReelParse> parseNovel(String text, {String? chapterReg});
class ChapterItem { final int index; final String reel; final String chapter; final String chapterData; }
String extractDocxText(List<int> bytes); // archive 解 zip → word/document.xml → <w:p> 段落拼 \n；坏文件抛 errFileType
// novel.dart 门面：
({List<NovelRow> data, int total}) novels(int projectId, {int page = 1, int limit = 10, String? search}); // chapter LIKE %search%
void addNovels(int projectId, List<ChapterItem> items); // chapterIndex 自增续排、eventState=0、随后自动入队 event_generation（T6 提供 enqueue，本任务留 hook 回调注入）
void updateNovel(int id, {int? index, String? reel, String? chapter, String? chapterData, String? event});
void deleteNovels(List<int> ids); // 级联删 o_eventChapter + 孤儿 o_event
List<({int id, int index, String chapter})> novelIndex(int projectId);
```

- [ ] **Step 1（codex）**：失败测试先行——parseNovel 用例组：①`第一章 起\nA\n第二章 承\nB`→2 章名/内容正确；②含`第一卷 xx`双卷文本→卷归属正确；③中文数字`第十三章`→index 13；④全文无章→单章 index1；⑤自定义 `chapterReg=/CH(\d+)\s*(.*)/g` 生效；docx 用例：脚本内构造最小 docx（archive 打包 document.xml）解出段落文本；CRUD 用例：分页 total/搜索/删除级联孤儿事件清理。实现至全绿。
- [ ] **Step 2（审核方）**：analyze+test；`git commit -m "feat(engine): 章节模块（parseNovel 移植/docx 解析/CRUD 分页）"`

### Task 6：事件引擎（event_generation 任务 + 事件查询 + 事件分析）

**Files:**
- Create: `engine/events.dart`；Modify: `engine/engine.dart`、`engine/queue.dart`（注册 recover）
- Test: `app/test/engine/events_test.dart`

**Interfaces:**
```dart
void generateEvents(int projectId, List<int> novelIds, {int concurrentCount = 5});
// 语义照抄：先把目标章 eventState=0/event=NULL/errorReason=NULL；入队一个 event_generation 任务（text lane）；
// 任务内并发 concurrentCount 处理各章：prompt = getPrompt('eventExtraction')，user 消息模板逐字：
// "请根据以下小说章节数：{chapterIndex}小说章节券：{reel}小说章节名称：{chapter}、小说章节内容生成事件摘要：\n{chapterData}"
// 成功：o_novel.event=剥离思维链后的文本、eventState=1；并解析事件行写 o_event(name,detail,createTime)+o_eventChapter；
// 失败：eventState=-1、errorReason=EngineException JSON；单章失败不中断其余章。
({List<EventRow> list, int total}) events(int projectId, {int page = 1, int limit = 10, String? search});
// JOIN 语义照抄 getEvent：GROUP_CONCAT(chapterIndex) → chapters: List<int>
void deleteEvents(List<int> ids); // o_event + o_eventChapter
List<({int id, String? event, int eventState, String? errorReason})> novelEventState(List<int> ids); // eventState!=0 过滤照抄
Future<String> eventAnalysis(int projectId, List<int> novelIds); // 汇总各章 event 交 LLM 出分析文本（对照 eventAnalysis.vue 的按章折叠展示，返回按章 JSON）
```
- addNovels 自动触发：T5 的 hook 接到 `generateEvents(projectId, newIds)`（照抄 addNovel 行为）。
- recover：event_generation processing 中断 → 对应 novelIds eventState=-1 reason=errAppRestart。
- UI 刷新机制：**不抄 3 秒轮询**——引擎 queue 事件广播即时驱动（体验优于 ToonFlow），页面观察 provider 即可；novelEventState 仍实现（供 e2e/populate 用）。

- [ ] **Step 1（codex）**：失败测试（StubGateway 注入：①三章两成功一失败→各章状态/o_event 行数/关联正确、任务 success；②取消→errCanceled；③冷启动 recover→-1/errAppRestart；④events 分页 JOIN chapters 数组正确）→实现全绿。
- [ ] **Step 2（审核方）**：analyze+test；`git commit -m "feat(engine): 事件提取（event_generation 任务/o_event 关联/分析）"`

### Task 7：剧本引擎（CRUD + 批量导入 + 提取资产 tool-calling + 导出）

**Files:**
- Create: `engine/scripts.dart`；Modify: `engine/providers/gateway.dart`、`openai_text.dart`、`engine/engine.dart`
- Test: `app/test/engine/scripts_test.dart`、`gateway_tooljson_test.dart`

**Interfaces:**
```dart
// gateway 扩展：
Future<Map<String, dynamic>> generateToolJson(String system, String user,
  {required String stage, required String toolName, required Map<String, dynamic> schema, CancelToken? cancelToken});
// openai_compatible：tools=[{type:function,name:toolName,parameters:schema}] + tool_choice 强制；
// 无 tool_call 回退解析首个 JSON 块；解析失败抛 errLlmFormat。
// scripts.dart：
List<ScriptRow> scripts(int projectId, {String? search}); // 含 relatedAssets: [{id,name}]（JOIN o_scriptAssets→o_assets）
int addScript({required int projectId, required String name, required String content, List<int> assets = const []});
void batchAddScripts(int projectId, List<({String scriptName, String scriptData})> items);
void updateScript(int id, {String? name, String? content, List<int>? assets}); // assets 全删重插
void deleteScripts(List<int> ids); // 级联照抄 delScript（agentWorkData/assets2Storyboard/scriptAssets/storyboard/video + storyboard 图文件删除）
void extractAssets(List<int> scriptIds, int projectId, {int groupSize = 5});
// 语义照抄：目标剧本 extractState=2；入队 asset_extraction；组内 extractState=0；
// system=getPrompt('scriptAssetExtraction')；user="当前已有资产列表：{列表}\n\n请根据以下{count}集剧本提取对应的剧本资产（角色、场景、道具）:\n{分隔拼接}"
// 分隔符逐字："===== 【剧本ID: {id}】{name} ====="
// resultTool schema：{newAssets:[{name,desc,type∈[role,tool,scene],scriptIds}],existingAssetRefs:[{name,scriptIds}]}
// 落库照抄 persistGroupResult：去重新增 o_assets(name,type,describe,projectId,startTime)→重查映射→组内 scriptAssets 全删重插→extractState=1
// 失败：extractState=-1 reason JSON；recover 同理。
Future<String> aiEpisodeRegex(String content); // 前 2000 字→LLM 出分集正则（getAiRegex 语义）
Future<List<int>> exportScripts(List<int> ids); // zip bytes：每剧本一个 "{name}.txt"
```

- [ ] **Step 1（codex）**：失败测试（tool-call 响应/纯 JSON 回退/坏响应 errLlmFormat；extractAssets：已有资产去重、scriptAssets 重建、部分组失败状态互不污染；导出 zip 可解出同名 txt）→实现全绿。
- [ ] **Step 2（审核方）**：analyze+test；`git commit -m "feat(engine): 剧本模块（tool-calling 提取资产/批量导入/导出）"`

### Task 8：导航壳（ToonFlow 布局 1:1 + 移动适配）

**Files:**
- Modify: `app/lib/src/screens/shell.dart`（重写）、`app/lib/src/app.dart`（路由重排）
- Test: `app/test/widgets/shell_test.dart`

**要求（桌面 ≥840，抄 workbench/index.vue）:**
- 左侧细栏（~96px，圆角 16，tooltip 右浮）：Logo；菜单【我的项目 `menuMyProject`、任务中心 `menuTaskCenter`】；底部【反馈问题、设置、GitHub】（反馈/GitHub 为外链 url_launcher，设置进 `/settings`）。
- 顶栏 50px：左=当前项目名 h2（无项目显示 `menuSelectProjectHint`「请选择项目」）；右=项目内菜单（未选项目时禁用）：原文小说(novelOnly)/剧本Agent(novelOnly，P1 禁用+徽标 P5)/剧本管理/配音(禁用 P4)/制作(禁用 P3)/分隔线/资产中心(禁用 P2)。projectType=script 的项目隐藏 novelOnly 项（语义照抄）。
- 选中项目进入路由 `/p/:pid/novel`（novel 型）或 `/p/:pid/script`（script 型），照抄跳转逻辑；`currentProjectProvider` 持有当前项目。
- 移动 <840：底栏【项目/任务/设置】；项目内子页顶部横滑 Tab 承接顶栏菜单；禁用项同样置灰。
- 三语：菜单 label 全部 ARB（zh/en/ja 取参照包 `workbench.menu.*`）。

- [ ] **Step 1（codex）**：widget test（900px 宽渲染侧栏+顶栏且禁用项 onTap 无效；380px 渲染底栏；未选项目时顶栏菜单禁用）→实现。
- [ ] **Step 2（审核方）**：analyze+test+macOS 运行截图对照 ToonFlow；`git commit -m "feat(ui): ToonFlow 导航壳（细栏+顶栏项目菜单/移动底栏）"`

### Task 9：项目页（卡片 + 两栏对话框 + 模型选择器）

**Files:**
- Create: `screens/project/project_list_screen.dart`、`project_dialog.dart`、`model_select.dart`
- Test: `app/test/widgets/project_page_test.dart`

**要求（抄 views/project）：**
- 头部：标题「我的项目」+ 副标题；右上「+ 新建项目」primary。
- 卡片 3 列 grid（<1100 两列、<840 单列）：名称(20px bold)+类型圆角 tag（`基于小说原文`/`基于剧本`）、画风 tag、简介 2 行截断、创建时间(YYYY-MM-DD HH:mm:ss, 50% 透明)、hover 显示编辑/删除 icon（删除确认弹窗文案取 `projectMsgDelete*` ARB）。点击卡片=选中项目并按类型跳转（T8 逻辑）。
- 对话框（桌面 `showDFAdaptiveDialog` 双栏 / 移动全屏单列上下排）：
  - 左栏字段逐项照抄：项目类型 select(novel/script)、项目名称、小说类型、图片模型（model_select type=image）+ 画质 select(1K/2K/4K)、视频模型（model_select type=video）+ mode select（选项由所选视频模型的 models JSON `modes` 字段动态给出，无则隐藏）、影片比例 select(16:9/9:16)、项目简介 textarea(3-6 行)。
  - 右栏：视觉手册画廊 + 导演手册画廊（**T10 交付组件，本任务先放占位容器并留 slot 参数**，T10 接入）。
  - 校验照抄：名称必填（warning toast `msgEnterProjectName`）。
- `model_select.dart`：下拉列出所有启用 vendor 的对应 kind 模型（`vendor名 / model label`），值存 `imageModel`/`videoModel` 为 `vendorId:modelId`。
- 引擎对接：T3 projects API。三语 ARB 从参照包 `workbench.project.*` 移植。

- [ ] **Step 1（codex）**：widget test（空态渲染 DFEmpty+新建按钮；假数据 3 项目渲染 3 卡；打开对话框必填校验触发；保存回调收到全字段 payload）→实现。
- [ ] **Step 2（审核方）**：analyze+test+双端截图；`git commit -m "feat(ui): 项目页 1:1（卡片/两栏新建向导/模型选择器）"`

### Task 10：手册子系统（视觉/导演手册：存储 + 画廊 + MD 编辑器）

**Files:**
- Create: `engine/manuals.dart`、`screens/manuals/manual_gallery.dart`、`manual_editor.dart`
- Modify: `screens/project/project_dialog.dart`（接入画廊 slot）
- Test: `app/test/engine/manuals_test.dart`

**Interfaces（照抄文件包语义，根在 MediaStore 兄弟目录 `skills/`）:**
```dart
// 视觉手册 → skills/art_skills/<stylePath>/；导演手册 → skills/story_skills/<directorManual>/
// 包内：README.md + 各 tab md 文件 + images/ 封面
class ManualPack { final String name; final String path; final List<String> images; final Map<String,String> data; }
List<ManualPack> visualManuals(); List<ManualPack> directorManuals();
void saveVisualManual({required String name, required String stylePath, required List<String> imagesBase64OrPaths, required Map<String,String> data, bool editing = false});
void saveDirectorManual({...同构});
void deleteVisualManual(String stylePath); void deleteDirectorManual(String directorManual);
// data 键（视觉，逐字照抄 addVisualManual 合法值）：README/prefix/art_character/art_character_derivative/art_prop/art_prop_derivative/art_scene/art_scene_derivative/director_storyboard/art_storyboard_video/director_planning_style/director_storyboard_table_style
// data 键（导演）：README/director_planning_narrative/director_storyboard_table_narrative
```
**UI：**画廊 grid（100px 封面、底部名条、hover 编辑/删除/预览、选中 2px 主色描边——项目的 `artStyle`=选中视觉手册 name、`directorManual`=选中导演手册 name）；编辑器对话框 90vw/75vh：名称+md 位置(编辑禁改)+封面多图上传（80px 预览+X删除+虚线上传格）+ Tab 组（视觉 12 tab/导演 3 tab，中文 tab 名照抄：README/前缀/角色/角色衍生/道具/道具衍生/场景/场景衍生/分镜/分镜视频/技法-导演规划/技法-分镜表设计）；每 tab 一个 markdown 输入区（P1 用等宽 TextField+字符计数，md 预览按钮留 P5 增强，页面注明）；校验：全 tab 非空+封面必传+名称必填。

- [ ] **Step 1（codex）**：引擎测试（save→list 往返、images 落盘、delete 清目录、编辑改名不动 path）→实现引擎+UI。
- [ ] **Step 2（审核方）**：analyze+test+手工建一份视觉手册并在新建项目里选中；`git commit -m "feat: 视觉/导演手册子系统（文件包存储+画廊+编辑器）"`

### Task 11：章节页（表格 + 两步导入 + 编辑 + 事件 tab + 事件分析）

**Files:**
- Create: `screens/novel/novel_screen.dart`、`import_novel_dialog.dart`、`edit_novel_dialog.dart`、`event_tab.dart`、`event_analysis_view.dart`
- Test: `app/test/widgets/novel_page_test.dart`

**要求（抄 views/novel）：**
- 工具栏：左【导入原文(primary,+icon) / 批量删除(danger)+选中数 / 事件分析+数】右【搜索框 260px+搜索钮】。
- 表格列照抄：复选/序号50/卷100/章节名100截断/章节内容(截断80字+「查看详情」链接弹全文)/事件(状态渲染)/操作200(编辑+删除)。事件列三态：eventState=0→loading「生成中...」；-1→danger 文字钮「生成失败」点开 errorReason；else→80 字截断+「查看详情」。分页默认 10。
- 数据源即时刷新：watch 任务事件 provider（引擎广播），无轮询。
- 导入对话框两步（宽 50%）：Step1 上传区（虚线框、i-upload 图标、拖拽+点击、.txt/.docx≤10MB，超限/类型错 toast errFileTooLarge/errFileType）+「或」分隔+粘贴 textarea(12行)+底部字数(<100 警示)与「已解析 X 章节」实时数（调 parseNovel）+「下一步」（无章节禁用）；Step2 章节选择表（复选/第X章/卷/章节名/内容截断）+已选字数+「上一步/保存」→ addNovels（保存后自动触发事件生成，行内进入「生成中」态）。
- 编辑对话框：章节名称/事件内容/章节内容(15行) + 取消/保存。
- 事件 tab（页内 Tab 或子路由）：事件表（id/事件名/关联章节(逗号 idx)/详情/时间/操作）、重新生成事件、批量删除、空态含「生成事件」按钮。
- 事件分析视图：按章折叠面板展示 eventAnalysis 结果，逐章 loading。
- 移动端：表格→卡片（章节名+卷+事件状态徽章+操作菜单），导入对话框→全屏两步页。三语 ARB `workbench.novel.*` 全量移植。

- [ ] **Step 1（codex）**：widget test（三态事件列渲染正确；导入 Step1 粘贴文本→解析数联动、无章节时下一步禁用；Step2 选择行数联动已选字数）→实现。
- [ ] **Step 2（审核方）**：analyze+test+macOS 真数据导入一部小说跑事件生成；`git commit -m "feat(ui): 章节页 1:1（两步导入/事件状态/事件分析）"`

### Task 12：剧本页（卡片流 + 新增/编辑/批量添加 + 提取资产）

**Files:**
- Create: `screens/script/script_screen.dart`、`add_script_dialog.dart`、`edit_script_dialog.dart`、`batch_add_dialog.dart`、`asset_picker.dart`
- Test: `app/test/widgets/script_page_test.dart`

**要求（抄 views/script）：**
- 工具栏：左【搜索 300px+搜索 / 新增剧本 / 批量添加】右（有剧本时）【全选↔取消全选 / 导出剧本+数 / 提取资产+数(loading 态) / 删除+数】。
- 卡片流（400px 宽 wrap，移动单列）：名称单行截断+右上复选；内容 1 行截断；资产 tag 行（light-outline 小号）；状态区四态（0「提取中...」/2「等待提取...」/-1 danger tag「提取失败」tooltip errorReason/1 显示 tags）；hover 右下删除。点击卡片开编辑。
- 新增对话框（60vw）：剧本名称/上传文件(同导入规范)/剧本内容 textarea(12行)+右下 `X/上限` 计数（上限= o_setting `scriptEpisodeLength` 默认 2000，超限确定禁用）/关联资产（「+ 选择资产」→ asset_picker 多选已有 o_assets，tag 可删）。
- 编辑对话框：名称(maxlength 10)/内容(20行)+计数/关联资产；上一步/保存。
- 批量添加两步（50%）：Step1 分集正则输入（支持 `/.../flags`，实时校验非法即 error 态+提示 errRegexInvalid）+「获取AI正则」钮(loading，调 aiEpisodeRegex 回填)+上传/粘贴区；Step2 选择表（复选/序号/剧本名/内容截断）+已选字数+保存（batchAddScripts）。
- 导出：exportScripts → 系统保存对话框（file_selector）写 zip。
- 提取资产：选中卡片→extractAssets，状态即时随任务事件刷新；资产落库后 tag 呈现（点 tag P2 起跳素材库，P1 仅展示）。
- 三语 ARB `workbench.script.*` 全量移植。

- [ ] **Step 1（codex）**：widget test（四态卡片渲染；字数超限禁用确定；非法正则 error 提示；全选切换文案）→实现。
- [ ] **Step 2（审核方）**：analyze+test+真数据：手动建 2 剧本→提取资产→tag 出现；`git commit -m "feat(ui): 剧本页 1:1（卡片流/批量添加 AI 正则/提取资产）"`

### Task 13：E2E + 演示数据 v3 + 三语双端验收

**Files:**
- Rewrite: `app/tool/e2e_smoke.dart`、`app/tool/populate_demo.dart`；Modify: `docs/…parity-design.md`（回填 spike/偏差记录）
- Test: 全量回归

- [ ] **Step 1（codex）**：e2e_smoke v3：临时目录起 Engine→建项目→addNovels(demo_novel.txt parseNovel)→generateEvents（真 LLM）→手建剧本→extractAssets（真 LLM）→断言各状态=1、o_event/o_assets 行数>0；populate_demo v3 同链生成演示项目。
- [ ] **Step 2（审核方）**：`dart run tool/e2e_smoke.dart` 真跑通过；populate 灌演示项目；macOS + iPhone 模拟器各页操作路径走一遍；locale 切 en/ja 全页扫（无中文残留/无溢出），截图留档。
- [ ] **Step 3（审核方）**：`git commit -m "feat: P1 收尾（e2e v3/演示项目/三语双端验收）"`；合并回 master。

---

## Self-Review 结论（已执行）

- **Spec 覆盖**：P1 范围（schema 全量/设计系统/导航壳/项目/章节/事件/剧本可编辑）逐项有任务；i18n §5B → T1+各页 ARB 步；错误码化 §5B.4 → T3；双形态 §5.3 → 各 UI 任务内建+T13 验收。剧本生成（scriptAgent）明确划归 P5，P1 剧本=管理页语义（与 ToonFlow 页面职责一致）。
- **占位符扫描**：无 TBD；T2 色值标注「frontend-design 定稿回填、接口不变」为显式流程而非空洞；T4 Step0/T1 Step0 为审核方取材动作，产物路径明确。
- **类型一致性**：id 全 int；EngineException/errKey 命名 T3 定义、T5-T12 引用一致；ChapterItem 字段 T5 定义、T11 引用一致；分页返回 record 形状统一 `(data|list, total)` 按 ToonFlow 各自命名保留。

## 执行偏差记录（审核方维护）

- **T3**：`database.d.ts` 实为 26 表（计划初稿误记 22），已按 26 表全量落库。
- **T5 起改为 Claude 亲自开发**（luke 2026-07-03 指示，Codex T5 长时间零产出后弃用）。
- **T6 对 ToonFlow 半成品的补齐**：① ToonFlow 后端无任何代码写入 o_event/o_eventChapter（事件列表页读空表），DramaFlow 在逐章事件生成成功时解析管道格式落表（name=首字段，detail=整行），重跑同章替换不重复；② 前端调用的 /novel/event/eventAnalysis 在 ToonFlow 后端不存在，DramaFlow 以可编辑提示词（o_prompt type=eventAnalysis）实现真实分析；③ 新增 stage `event_extract`（text 类）与其种子绑定；④ 事件任务粒度：单章失败不失败整任务，全部失败才判任务失败（首个错误上抛）。

## P1 进度快照（2026-07-03，审核方维护）

- ✅ T1 i18n 基建（a44e661）/ T2 设计系统（6667900）/ T3 schema v3 26 表（902bccf）/ T4 提示词种子（f296bfd）
- ✅ T5 章节引擎（f953f46）/ T6 事件引擎（a7b1471）/ T7 剧本引擎（09f069a）
- ✅ T8 导航壳（724f343）/ T9+T10 项目页+手册（ee95bd4）/ T11 章节页（35c854b）/ T12 剧本页（56f2c61）
- ✅ T13 部分：语言切换入口+工具 v3（1748bbc）；**真实 E2E 全链通过**（章节→事件 2/2→o_event 落表→剧本→资产提取 2/2→o_assets 8 行，azt gpt-5.5，管道格式与 resultTool 均正常）；macOS debug 构建+启动冒烟通过；109 单测全绿 analyze 零告警
- ⏳ T13 余项：populate 演示项目（进行中）/ iPhone 模拟器双端验收 / en·ja 三语扫查截图
- P1 完成后进入 P2（素材库全量：4 tabs/子资产/润色/批量生图 + 画风库），按 spec §6 继续

## P2 进度快照（2026-07-03，审核方维护）

- ✅ P2 引擎层素材模块（f0e5e47）：assets.dart 全量——父子层级 CRUD / 音频资产 / polishAssetPrompt（视觉手册作 system，用户模板逐字）/ 批量润色任务 / generateAssetImages 生图任务 / 中文状态枚举（生成中·已完成·生成失败）/ 冷启动恢复；素材页三语 ARB 79 键补齐（ToonFlow 原语言包缺 70+ 键，全部自补）
- ✅ P2 UI（9526eeb）：资产中心 5 tabs + 父子展开表 + 生成图片双栏对话框（左表单/右版本网格三态）+ 批量生成对话框（提示词/图片双模式）+ 音频资产对话框；导航「资产中心」解禁
- ✅ 生图 Null 强转 bug 修复（343f344）：image_size_directive 在 P1 改为 useData=NULL 后，gateway 裸强转崩溃；已回落 data，加回归测试；确认引擎内无其他同类隐患
- ⏳ P2 真实生图端到端验收进行中（tool/e2e_assets.dart，真 LLM 润色已通过，gpt-image-2 生图验证中）
- 偏差补充：taskClass 统一英文（asset_prompt_polish/asset_image_generation），生图 aspectRatio 用项目 videoRatio（ToonFlow 写死 16:9）；均记于 assets.dart 头注释
- 下一步：P2 收尾后按 spec §6 进入 P3（制作画布 + 分镜表 + 节点式图片编辑器）

## P3 进度快照（2026-07-03，审核方维护）

- ✅ 分镜引擎（9a84cc2）：storyboard.dart 全量——CRUD+插入排序+批量删除重排/剧本→分镜
  tool-calling 生成（复用 P2 gateway.generateToolJson）/首帧图批量生成（复用资产关联图作参考图）/
  中文状态枚举（未生成·生成中·已完成·生成失败）/冷启动恢复；6 测全绿
- ✅ 图片编辑器引擎（d7c821f）：image_flow.dart（o_imageFlow 节点图持久化/生成，连线参考图
  取首张，同步直调不入队列，偏差已文档化）+ 通用无限画布组件 DFCanvas（InteractiveViewer+
  CustomPainter 贝塞尔边+网格背景+自动 fitView）；5 测全绿
- ✅ P3 UI（e00bf44, 2e397f3）：制作画布 6 节点链式布局（script/assets/storyboardTable/
  storyboard 全交互/workbench 与 scriptPlan 为 P4/P5 占位）+ 分镜网格（生成/编辑/删除/插入/
  批量选择/批量生图/缩放）+ 节点式图片编辑器（拖拽/连接手柄/连线驱动参考图/生成/应用回填）；
  移动端画布降级为纵向 Tab；4 个 widget 测试全绿；顺带修了一个既存测试 bug（project_page_test
  误用两个独立内存库导致 config 与 db 状态不同步）
- ⏳ P3 真实 E2E（tool/e2e_storyboard.dart）进行中：剧本→分镜 tool-calling 已知可行（复用 P2
  验证过的 gateway.generateToolJson 链路），首帧图生成中（gpt-image-2，耗时符合历史实测区间）
- 131 测全绿，analyze 零告警，macOS 启动冒烟通过
- Agent 对话框（rightChatBox）按 spec 明确归属 P5，P3 不做占位面板（画布内无入口，不构成半成品）
- 下一步：P3 收尾后按 spec §6 进入 P4（多轨工作台+配音+零 ffmpeg 合成导出）

## P4 进度快照（2026-07-03，审核方维护）

- ✅ P4 引擎层（13ff809）：video_track.dart（视频槽位/候选生成/首个自动选中/手动挑选/
  冷启动恢复）+ audio_bind.dart（LLM tool-calling 角色↔音频匹配/手动绑定）+
  compose_episode.dart（按分镜序取选中视频，复用零 ffmpeg VideoComposer 拼接）；
  新增 stage `video_prompt_gen`、taskClass `video_generation`/`audio_bind`；
  **顺带修复一个真 bug**：`Engine` 构造函数自 T3 schema 重写起就丢弃 `composer` 参数
  （从未存成字段，`engine.composer` 实际不存在）——已修复+回归测试锁定；16 测全绿
- ✅ P4 UI（dc71f30）：工作台（画布摘要节点+全屏页：镜头列表/运镜提示词生成/视频候选
  网格挑选/合成本集按钮+缺口提示）+ 配音页（角色列表/手动绑定下拉/AI 批量自动匹配）；
  解禁「配音」菜单；8 个 widget 测试全绿
- ✅ 真实 E2E 验收：配音 LLM 匹配真跑通过（"清冷孤傲少年"→"清亮少年音"，
  "威严掌门"→"低沉长者音"，语义判断准确）；macOS 启动冒烟通过
- 明确不做（执行边界，已文档化非缺陷）：视频编辑器剪辑/转场/滤镜（ToonFlow 用 WebAV
  AVCanvas，超出零 ffmpeg 顺序拼接定案）；语音合成 TTS（cornerScape 只做绑定，
  音频素材来自 P2 音频资产上传）；真实视频生成效果（seedance）留 luke 实机验证
- 156 测全绿，analyze 零告警
- 下一步：P4 收尾后按 spec §6 进入 P5（Agent 体系+全套设置页+新演示项目填充），
  这是 v0.3 spec 的最后一批

## P5 进度快照（2026-07-03，审核方维护）

- ✅ P5 引擎层（017b2f9）：agent.dart——单层 AgentRunner 瘦身版（spec §4 既定
  决策，明确不做 ToonFlow 真实的多层 Claude 子代理编排+向量 RAG，理由见文件
  头注释）；8 个工具（get_status/generate_events/extract_assets/
  generate_storyboards/generate_shot_images/generate_videos/bind_audio/
  compose_episode）1:1 映射到已有真实流水线方法，全部经 o_tasks 队列，绝不出现
  "对话说做了但任务表查无此事"；manual（每轮 1 个工具调用后停等用户）/auto
  （`_maxAutoTurns=5` 安全上限连续执行）双模式；消息仅短期历史存
  `o_agentWorkData`（key=`agentChat`，project 级，非向量 RAG）
- ✅ P5 UI（a43120d）：AgentChatScreen（消息气泡区分 user/assistant/tool、
  工具执行摘要卡片、manual/auto 模式开关、清空记忆确认弹窗、内置能力说明弹窗）；
  路由 `/p/:pid/scriptAgent` 接线，「剧本Agent」菜单解禁
- ✅ Settings 补齐：新增 stage `event_extract`/`video_prompt_gen` 及对应
  prompt 项的绑定入口（此前完全不可见/不可配置，属于 P1/P4 遗留缺口，本批一并
  修复）；`_StageMeta` 从硬编码中文改为 l10n 方法（对齐既有 `_PromptMeta` 模式）
- ✅ YAGNI 清理：`comingBatch` 占位徽标机制随 P2-P5 全部菜单上线而彻底成为死码，
  删除 `shell.dart` 中的整套机制与 `coming_soon_screen.dart`；`_projectMenus`
  6 项全部无条件启用
- ✅ **真实 E2E 发现并修复一个真 bug**：`tool/e2e_agent.dart` 首次真跑时，模型
  对可选 id 数组参数用了显式 `[]` 而非省略字段（真实模型常见写法），但
  `_intList` 只把"完全未传字段"识别为可回退默认集合，显式空数组被当成
  "精确指定零个"，导致 `generate_events` 等工具在明明有待处理项时误报
  "没有需要处理的"——已修复（空数组与未传字段同等回退）+ 补充回归测试；
  同时发现并修正 E2E 脚本本身的验收场景缺陷（用"导入章节→令 Agent 生成事件"
  会与 `addNovels` 的 `onNovelsAdded` 自动触发钩子竞态，真实 LLM 调用在 Agent
  第二轮前就已跑完，"没有需要处理的章节"其实是完全正确的回答而非工具失效），
  改用剧本+资产提取（该阶段无自动触发钩子）作验收场景
- ✅ 真实 E2E 验收（修复后重跑通过）：Agent 正确调用 `get_status` 查看进度、
  正确调用 `extract_assets` 对剧本发起资产提取，任务表 `asset_extraction` 记录
  可查；macOS `flutter build macos --debug` + 启动冒烟通过（BOOT OK，日志无异常）
- 明确不做（P5 是 spec 既定的范围裁剪，非缺陷）：ToonFlow 真实的决策/执行/监督
  多层子代理编排；向量 RAG 长期记忆；自定义 JS 技能执行——均判定与本项目
  "显式流水线可见可恢复"的核心设计相悖，规模也与项目整体不成比例
- 168 测全绿，analyze 零告警
- 下一步：P5（v0.3 spec 最后一批）功能与真实验收均已合入；剩余为收尾项——
  重跑 `tool/populate_demo.dart` 对齐最终 v3 schema 产出完整演示项目、
  iPhone 模拟器移动端双端验收、en/ja 语言视觉扫查

## ToonFlow 全量对齐补缺快照（2026-07-03 深夜，审核方维护）

用户质疑"功能没全迁移"，遂派 5 个深度审计代理逐区对照 ToonFlow 源码，
得出真实缺口清单（docs 外的 scratchpad/parity_gaps.md），再分批修复：

- **引擎地基（自做，7ce069f/5328383）**：`generateImage` 支持多参考图 +
  ratio/quality/modelOverride（一次修复 3 处 HIGH：分镜只用首个参考图、
  节点编辑器 model/画幅/清晰度死控件、素材单图模型死选择）；`resolveModelById`；
  其他设置 config 键（chapterReg/scriptEpisodeLength/assetsBatchGenereateSize）
  接入导入/事件/资产调用点；供应商分模态连通测试（文·图·视频，视频 submitOnly）。
- **5 个特性 worktree 代理并行 → 逐个 ARB 并集合并**：
  - NOVEL（c6b8d8b）：小说列表「生成选中章节事件」触发 + 批量加剧本字数上限门
  - ART（f80e291）：画风库 CRUD（o_artStyle 首次接线）+ 素材文件上传 +
    批量/单图生成参数（模型/分辨率/并发/otherTextPrompt）+ 手册 docx/md 导入
  - PROD-EDIT（83d5864）：分镜表/剧本画布节点可编辑 + 分镜前插 +
    节点编辑器多源选图（素材库/分镜/本地）+ 点击删连线
  - VIDEO（178dc99）：工作台视频播放 + 配音试听（media_kit，macOS 原生验证）+
    每镜时长/运镜提示词编辑 + 候选删除按钮 + 运镜提示词生成增强上下文
  - SETTINGS（2ee0b6f）：其他设置面板 + 任务 taskClass/状态筛选 + 任务详情 +
    存储清理/打开目录/库信息 + 关于面板 + 分模态测试 UI + Agent 模式持久化
- 明确未做（有据）：ToonFlow 多层子代理编排+向量 RAG（spec 裁剪）、WebAV 视频剪辑器、
  TTS 语音合成、从参考图反推画风提示词（网关无视觉输入路径）、逐模型 prompt 映射
  （modelMap，较大子系统，留待后续）。
- 238 测全绿、analyze 零告警、macOS 可构建。
- 收尾中：settings/tasks/组件层遗留硬编码文案的最终 i18n pass（代理进行中）+
  完整 test + macOS 构建 + iOS 启动冒烟。

## Codex 接力收尾与移动端补强（2026-07-04）

- ✅ 最终 i18n pass 已落地并提交（adbfd61）：settings/tasks/shared widgets 的
  UI 中文硬编码改为 `AppLocalizations`；新增静态测试
  `test/ui_i18n_static_test.dart` 防止设置页、任务页、共享组件再次出现中文硬编码；
  `df_widgets_test` 测试壳补齐三语 delegate。
- ✅ 收尾验证已跑：`flutter analyze` 零 issue；`flutter test` 239/239 通过；
  `flutter build macos --debug` 通过；`flutter build ios --simulator --debug` 通过并已
  安装启动到 iPhone 模拟器（进程可查）。
- ✅ Web 从“编译直接失败”推进到“可构建开发预览”（b8c3e98）：`main.dart` 拆为
  条件 bootstrap，IO 端继续启动完整 `DramaFlowApp + Engine`，Web 端进入独立
  `DramaFlowWebPreviewApp`，避免把 `dart:io`、sqlite FFI、媒体文件系统和原生合成器
  拉进 Web 编译图；`flutter build web` 通过，Wasm dry run 通过。
- ⚠️ Web/H5 仍不是完整流程：当前 Web 只是明确标注限制的预览入口。要成为一等公民，
  仍需要继续移植 Web 数据库（sqlite3-WASM/OPFS 或浏览器端适配）、浏览器文件存储、
  WebCodecs/Mediabunny 合成器、媒体预览与文件选择的 Web 版本。
- ✅ Android 移动端合成从“不支持”推进到“可构建的原生通道”（ffc784b）：
  `main.dart` 将 Android 接入 `dramaflow/composer`；`MainActivity.kt` 注册
  `probeDuration`/`concat`，使用 Android 系统 `MediaMetadataRetriever` +
  `MediaExtractor` + `MediaMuxer` 做零 ffmpeg 的同编码 MP4 顺序拼接；新增
  `test/platform/android_composer_static_test.dart` 锁定 Android 不再走
  `UnsupportedComposer`。
- ✅ Android 验证已跑：先看见静态测试红灯（缺少 MethodChannel），实现后
  `flutter test test/platform/android_composer_static_test.dart` 通过；
  `flutter analyze` 零 issue；`flutter test` 240/240 通过；
  `flutter build apk --debug` 通过，产物：
  `app/build/app/outputs/flutter-apk/app-debug.apk`。
- ⚠️ Android 合成器限制：当前是同编码/同分辨率/同音频参数的 remux 快路径，
  适合 Seedance 统一规格输出；它不是完整 Media3 Transformer 转码器。若后续要
  支持混合分辨率、不同编码、音频补静音、转场或滤镜，仍需按 spec 升级到
  Media3 Transformer 或等价原生转码管线。
- 已知构建警告：macOS/iOS 的 `media_kit_video` 插件暂不支持 Swift Package
  Manager（未来 Flutter 可能变错误）；Android 构建提示 `wakelock_plus` 使用旧式
  Kotlin Gradle Plugin；这些不是当前功能失败，但属于升级风险。
- ✅ 最新验证补跑：`flutter test` 241/241 通过；`flutter build web` 通过；
  `flutter build macos --debug` 通过；`flutter build apk --debug` 通过；
  `flutter build ios --simulator --debug` 通过。
- ✅ TTS 最小闭环已补齐：新增 `ProviderGateway.generateSpeech` 与
  OpenAI-compatible `/audio/speech` 适配，`MediaStore.saveAudio` 落盘；
  `TtsApi.synthesizeAudioAsset` 可把文本生成的音频挂到现有 `o_assets(type=audio)` +
  `o_image(type=audio)` 结构，`addSynthesizedAudioAsset` 可从文本直接创建可试听音频素材；
  资产中心「音频」tab 新增「文本配音」入口（音色名/性别/描述/配音文本/Voice ID）。
  新增 `tts_test`、`providers_test.generateSpeech`、`assets_tts_screen_test` 覆盖引擎、
  网关和 UI 路径。
- ⚠️ TTS 仍是素材级最小闭环，不等于完整配音生产线：逐分镜台词批量生成、角色 voice
  规则化管理、配音与成片合成混音仍待后续任务补齐。
- ✅ TTS 补缺验证已跑：`flutter analyze` 零 issue；`flutter test` 245/245 通过；
  `flutter build web` 通过；`flutter build macos --debug` 通过；
  `flutter build apk --debug` 通过；`flutter build ios --simulator --debug` 通过。
- ✅ 分镜配音绑定地基已补齐（schema v4）：`o_storyboard` 增加
  `audioAssetId/audioText/audioPath/audioState/audioError`，`StoryboardRow` 可回读；
  新增 `StoryboardAudioApi.bindStoryboardAudio` 与 `orderedStoryboardAudioPaths`，先把
  “每个镜头绑定哪段配音”这层数据打通，为后续合成混音做准备。
- ✅ 分镜配音已接入整集合成时间线：`composeEpisode` 会按分镜顺序生成
  `ComposeSegment(videoAbsPath,audioAbsPath)`，有任一镜头绑定配音时走
  `VideoComposer.compose`，无配音时保持原 `concat` 快路径；回归测试锁定
  “纯视频仍 concat / 带配音传视频+音频时间线”两条分支。
- ✅ macOS/iOS AVFoundation 合成器已支持配音混入：Flutter method channel 新增
  `compose(segments, output)`；Swift 插件逐段插入视频轨、保留原视频音轨，并将分镜
  配音作为额外音轨按镜头时长裁剪插入。`concat` 复用同一 compose 实现，减少双路径漂移。
- ⚠️ Android 配音混音仍未完成：Android method channel 已新增 `compose`，无配音时退回
  当前 `MediaMuxer` 直拼；有配音时明确抛出“Android 当前合成器暂未支持分镜配音混合”。
  要在 Android 上真正混音，仍需升级到 Media3 Transformer/FFmpeg Kit 等可转码管线。
- ✅ 本轮接力验证已跑：`flutter analyze` 零 issue；`flutter test` 248/248 通过；
  `flutter build macos --debug` 通过；`flutter build ios --simulator` 通过；
  `flutter build apk --debug` 通过。
- ✅ macOS 真实合成 smoke 已补齐：新增
  `integration_test/composer_audio_smoke_test.dart` 和极小媒体 fixture（无声 mp4 + m4a
  配音），在真实 macOS app 沙盒内调用 `AVFoundationComposer.compose`，导出后用新增
  `inspectMedia` 原生自检确认输出含 1 条视频轨 + 1 条音频轨，并验证时长区间。
- ✅ smoke 首跑发现并修复一个真实导出 bug：AVFoundation 组合一开始创建了空的“原视频音轨”，
  当输入视频本身无声但有独立配音时，导出失败（AVFoundationErrorDomain -11800 /
  OSStatus -12123）。现已改为原视频音轨懒创建，仅在源视频存在音频时插入；配音轨独立懒创建。
  同时增强 macOS/iOS 原生错误透传，后续导出失败会带 domain/code/underlying error。
- ✅ smoke 补强验证已跑：`flutter test integration_test/composer_audio_smoke_test.dart -d macos`
  通过；`flutter analyze` 零 issue；`flutter test` 248/248 通过；
  `flutter build macos --debug`、`flutter build ios --simulator`、
  `flutter build apk --debug`、`flutter build web` 均通过。
- ✅ Android 配音导出从“遇到 audioPath 直接降级”推进到“无重编码封装独立配音轨”：
  `MainActivity.compose` 在存在 `audioPath` 时不再直接抛“暂不支持”，而是用
  `MediaMuxer` 复制视频轨，并将每个分镜的外部 AAC/M4A 音频轨按该镜头时长裁剪后写入
  输出音轨；无 `audioPath` 时保留原 `concat` 快路径。限制仍然明确：这不是 PCM 混音器，
  若要“源视频原声 + 配音 + BGM”真正叠混，仍需 Media3 Transformer/FFmpeg Kit。
- ✅ Android 配音封装验证已跑：先用
  `flutter test test/platform/android_composer_static_test.dart` 观察到缺口红灯，再实现；
  之后该测试通过，`flutter build apk --debug` 通过，`flutter analyze` 零 issue，
  `flutter test` 248/248 通过。
- ✅ Android 媒体自检通道已补齐：`dramaflow/composer` 现在支持 `inspectMedia`，
  返回 `videoTrackCount/audioTrackCount/durationSec`，与 macOS/iOS 的
  `AVFoundationComposer.inspectMedia` 对齐。这样后续 Android 实机 smoke 可以直接验证
  导出 MP4 是否真的含音频轨，而不依赖外部 ffprobe。
