# 技能库目录树复刻设计

日期：2026-07-21

范围：`W6D-SKILL-001` 的目录树浏览、搜索、预览与编辑差异。
基线：ToonFlow 1.1.8 `skillManagement.vue` 与
`setting/skillManagement/{getSkillList,getSkillContent,saveSkillContent}`。

## 目标

在不引入 Electron 文件系统权限、后台 HTTP 路由或新的数据库表的前提下，让 DramaFlow
的托管 Markdown 技能库提供与 ToonFlow 相同的可观察工作流：按相对路径浏览、搜索、选择、
预览与编辑 Markdown。桌面和移动端使用同一份树数据，任一端都能完成查看和编辑。

这项工作不修改 Agent 工具、技能激活协议、供应商、视频生成或真实供应商测试。

## 已核实的原版行为

原版先枚举 `skills/**/*.md` 的相对路径，再将路径分段构造成目录在前、文件在后的树；搜索
只过滤 Markdown 相对路径。用户只能选择文件节点，右侧显示原始 Markdown 预览，保存时只
覆写该既有相对路径。原版没有在此页创建、删除或移动文件的功能。

## DramaFlow 映射

DramaFlow 的安全边界比原版更严格：所有内容都在应用自有
`dataDir/skills/<skill-id>/`，并由既有 `managedAssistantSkillPath()` 校验。该目录在用户
可观察层映射成原版 `skills/` 根：

```text
skills/
  camera_guide/
    SKILL.md
    notes.md
    references/
      shot-list.md
  style_guide/
    SKILL.md
```

树节点只来自常规 Markdown 文件，忽略符号链接、二进制资源和越界路径。入口 `SKILL.md`
显示为技能名称，其余节点显示相对文件名。搜索按显示路径、技能名称、描述和文件名过滤；
命中子项时祖先目录保留。目录永远不可编辑。

编辑入口 `SKILL.md` 必须继续调用 `saveManagedAssistantSkill()`，以维持稳定 ID、名称、
描述和摘要同步。编辑其他 Markdown 资源走新的受限资源写入 API：只能写入已存在的常规
文件，写入前和重命名前后均校验真实路径仍在同一技能包；不允许创建文件、删除文件或改变
扩展名。这样不会让资源文件被扫描器误注册成第二个技能。

## 跨端交互

- **桌面（>=840dp）**：保持左侧 300dp 导航、右侧预览/编辑。目录可以展开、收起；首个
  选中的 Markdown 文件在右侧打开。内置动作仍独立显示在树下方的“内置技能”组，不伪装成
  文件。
- **紧凑屏（<840dp）**：初始显示树根；点目录进入下一层，点 Markdown 进入全屏详情；
  返回依次回到父目录而不是跳回根。搜索结果直接列出命中的完整相对路径，点选仍进入详情。
- 两端继续使用可见的编辑、保存、导入和重扫动作；不引入 hover 必需操作、拖放目录或仅
  macOS 可用的文件夹选择器。

## 引擎接口

在 `assistant_skill_library.dart` 定义不可变目录节点和文件读写接口：

```dart
class ManagedSkillLibraryFile {
  final String skillId;
  final String relativePath;
  final String displayPath;
  final bool isEntry;
}

List<ManagedSkillLibraryFile> managedSkillLibraryFiles();
String readManagedSkillLibraryFile(String skillId, String relativePath);
void saveManagedSkillLibraryFile(
  String skillId,
  String relativePath,
  String content,
);
```

返回值按相对路径稳定排序。`relativePath` 始终以 `/` 表示，不接受空路径、绝对路径、
`..` 或符号链接。`SKILL.md` 读写委托既有入口 API；资源使用同一真实路径校验后原子
替换。目录树是 UI 纯函数，不写数据库。

## 验收与非目标

引擎测试必须覆盖：递归 Markdown 清单、稳定排序、非 Markdown/符号链接排除、相对路径
逃逸拒绝、入口编辑保持元数据、资源编辑不影响技能元数据。Widget 测试必须在 1200dp 和
390dp 覆盖目录展开/进入、搜索命中深层文件、预览/编辑资源、返回路径和既有导入/重扫。

全量 `flutter test`、`flutter analyze` 和 `flutter build macos --debug` 必须通过；所有
测试使用临时目录、内存 SQLite 和 fake gateway。不会发起文字、图片、音频或视频供应商
请求。

非目标：文件夹导入、ZIP、创建/删除/重命名目录、任意外部路径浏览、阶段级技能归属、
Agent 子编排和真实视频生成。这些不是 ToonFlow 此页面的既有行为，或属于单独的 W2/W6D
差异，不能搭车加入。

## 文档状态

实现完成后，更新 `docs/parity/skill-runtime-matrix.md`、
`docs/parity/master-checklist.md` 与 `docs/parity/feature-parity-execution-report.md`：
`W6D-SKILL-001` 只在目录树、深层 Markdown 编辑和跨端验收全部具备时才从“部分实现”
提升；不影响 W2 Agent 的部分实现状态。
