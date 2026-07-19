# 剧本批量导入对照

状态：**已验证等价**。范围仅限剧本文本的拆集、选择与保存；不触发任何真实模型或视频供应商。

## 基线与对应

| ToonFlow 1.1.8 | DramaFlow Flutter | 结论 |
| --- | --- | --- |
| `Toonflow-web/src/utils/parseScript.ts` | `app/lib/src/engine/novel_parse.dart` 的 `parseScript` | 独立的剧本拆集器，不能复用小说的拆卷拆章器。 |
| `Toonflow-web/src/views/script/components/batchAddScript.vue` | `app/lib/src/screens/script/batch_add_dialog.dart` | 同样是“解析与选择 → 批量保存”两步流程。 |
| `Toonflow-app/src/routes/script/batchAddScript.ts` | `app/lib/src/engine/scripts.dart` 的 `batchAddScripts` | 标题和正文按选中集逐条落库；空标题是合法数据。 |

## 行为核对

| 用户可见行为 | ToonFlow 证据 | Flutter 实现与自动化证据 |
| --- | --- | --- |
| 空规则默认按“第 X 集 标题”拆分 | `parseScript.ts` 的 `DEFAULT_EPISODE_REGEX` | `parseScript` 使用单独的 `_defaultEpisodeRegex`；`novel_parse_test.dart` 验证第 2 集在前时仍按集号排序。 |
| 小说章节文本不应再拆开剧本 | 原版剧本正则只匹配“集” | 引擎回归把“第1章”留在第 1 集正文，防止重新误用 `parseNovel`。 |
| 支持 `/pattern/flags` 自定义正则 | 原版 `parseRegStr` | 支持原版 `i/m/u/y` 标志；`y` 以 Dart 的 `matchAsPrefix` 模拟 JavaScript 的粘滞匹配，避免退化为全文扫描。 |
| 自定义规则必须以第一个捕获组给出集号 | 原版 `parseScript` 无条件读取 `matches[i][1]`，缺失时调用方捕获错误并显示空表 | `parseScript` 在无第一个捕获组时抛 `StateError`，批量页捕获后显示空解析表，不产生错误的“第0集”。一组捕获正则只提供集号时，标题保留为空。 |
| 无集标记时整段文本是第 1 集 | 原版 `matches.length === 0` 分支 | 引擎回归断言 `index=1`、空标题和已裁剪的全文。 |
| 批量表可分别勾选每一集 | 原版选择键为 `index` | Flutter `DFDataRow.id` 和选中集合均使用集号；移动端空标题以“第N集”显示，仍保存空标题。 |
| 选择步骤不预选分集 | 原版 `selectedRowKeys` 初始为空，保存前校验是否有选中行 | Flutter 进入第二步清空选择；390dp widget 先断言“已勾选：0字”，无选择保存不写库，再手动点选后保存。 |
| AI 解析规则可回填后重新拆分 | 原版 `getAiRegex` 后重算表格 | Flutter `aiEpisodeRegex` 返回去围栏的规则，批量页回填后调用同一拆集器；引擎测试使用假网关验证规则清理。 |

## 跨端验证

| 视口 | 用例 | 已证明的链路 |
| --- | --- | --- |
| 390dp 移动端 | `移动端剧本页：批量添加两集并落库` | 默认“第1集/第2集”粘贴、解析、进入选择页默认不勾选、手动选择后保存两条剧本。 |
| 390dp 移动端 | `移动端批量添加保留空集标题，并按集号分别保存` | 自定义一组捕获正则、两条空标题记录、集号选择键和独立入库。 |
| 引擎 | `novel_parse_test.dart` 的 5 条剧本用例 | 默认排序、章节文本保留、无标记回退、自定义正则、`y` 粘滞语义和无集号捕获组拒绝。 |

当前 `develop` 基线重新验证了批量添加的完整本地链路：

```bash
cd /Users/luke/Documents/aivideo/dramaflow/app
flutter test --concurrency=1 \
  test/widgets/batch_add_dialog_test.dart test/widgets/script_screen_test.dart \
  test/engine/novel_parse_test.dart test/engine/scripts_test.dart
flutter analyze lib/src/engine/novel_parse.dart lib/src/engine/scripts.dart \
  lib/src/screens/script/script_screen.dart lib/src/screens/script/batch_add_dialog.dart
```

44 条测试通过、静态分析无诊断。其中前三条批量对话框测试明确使用“第 N 集”输入，进入第二步后先手动勾选目标分集，再验证限额与落库，防止未来将 ToonFlow 的默认零勾选契约误改成自动全选。测试只使用本地数据库和假网关，不会调用真实模型或视频生成。

## 验收边界

验证只覆盖纯文本解析、UI 状态和 SQLite 落库。AI 解析规则用假网关验证协议处理；没有请求真实文本模型，也没有提交、轮询或下载任何视频任务。
