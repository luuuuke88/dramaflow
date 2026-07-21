# 技能库目录树复刻实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让托管技能库以 ToonFlow 风格的相对路径目录树在桌面和移动端浏览、搜索、预览及编辑所有已有 Markdown 文件。

**Architecture:** `assistant_skill_library.dart` 是唯一的受限文件清单、读取和写入边界；它从应用自有 `dataDir/skills/<id>/` 构建稳定文件清单，不新增 schema。`_AssistantSkillsPane` 将该清单纯转换为目录树：桌面双栏展开，紧凑屏逐层进入；编辑入口 `SKILL.md` 继续走元数据同步 API，资源编辑走受限资源写入 API。

**Tech Stack:** Flutter/Dart、SQLite 既有 `o_skillList`、`path`、`flutter_test`、现有 l10n。

## Global Constraints

- 不修改 `/Users/luke/Documents/aivideo/Toonflow-app` 或 `Toonflow-web`。
- 不新增数据库表、迁移、文件选择插件或后台 HTTP 服务。
- 所有文件只允许存在应用自有 `dataDir/skills/<skill-id>/`；Markdown 资源不因浏览/编辑变成第二个技能。
- 仅既有常规 `.md` 文件可列出和编辑；拒绝绝对路径、空路径、`..`、符号链接和新建文件。
- `SKILL.md` 必须仍经 `saveManagedAssistantSkill()` 保存，保持稳定 ID 和元数据；资源写入不改 `o_skillList`。
- 840dp 以上和 390dp 都可完成选择、预览、编辑、保存与返回；无 hover 必需操作。
- 测试只用临时目录、内存 SQLite、fake gateway；不得调用文字、图片、音频或视频供应商。
- 不暂存 `.superpowers/sdd/progress.md` 或 `docs/superpowers/acceptance/`。

---

### Task 1: 托管 Markdown 文件清单与受限写入

**Files:**
- Modify: `app/lib/src/engine/assistant_skill_library.dart`
- Modify: `app/lib/src/engine/assistant_skills.dart`
- Test: `app/test/engine/assistant_skill_library_test.dart`

**Produces:**

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

// Agent protocol only: accepts any existing regular package resource.
String readManagedAssistantSkillResource(String skillId, String relativePath);
```

- [x] **Step 1: Write failing engine tests**

Add a `managed skill library files` group. Its fixture imports a `camera_guide/SKILL.md`,
creates `notes.md`, `references/shot-list.md`, `photo.png`, and an `escape.md` symlink to a
file outside the package. Add these exact assertions:

```dart
test('递归列出稳定排序的托管 Markdown，忽略二进制和符号链接', () {
  final skill = importPackage('camera_guide');
  final root = File(engine.managedAssistantSkillPath(skill.id)).parent;
  File(p.join(root.path, 'notes.md')).writeAsStringSync('笔记');
  Directory(p.join(root.path, 'references')).createSync();
  File(p.join(root.path, 'references', 'shot-list.md')).writeAsStringSync('镜头');
  File(p.join(root.path, 'photo.png')).writeAsBytesSync([0]);
  final outside = File(p.join(dir.path, 'outside.md'))..writeAsStringSync('外部');
  Link(p.join(root.path, 'escape.md')).createSync(outside.path);

  expect(engine.managedSkillLibraryFiles().map((file) => file.displayPath), [
    'camera_guide/SKILL.md',
    'camera_guide/notes.md',
    'camera_guide/references/shot-list.md',
  ]);
});

test('入口编辑同步元数据，资源编辑只替换同包既有 Markdown', () {
  final skill = importPackage('camera_guide');
  final root = File(engine.managedAssistantSkillPath(skill.id)).parent;
  File(p.join(root.path, 'notes.md')).writeAsStringSync('旧资源');
  final before = db.select('SELECT name,description,md5 FROM o_skillList WHERE id=?', [skill.id]).single;

  engine.saveManagedSkillLibraryFile(skill.id, 'notes.md', '新资源');
  expect(engine.readManagedSkillLibraryFile(skill.id, 'notes.md'), '新资源');
  expect(db.select('SELECT name,description,md5 FROM o_skillList WHERE id=?', [skill.id]).single, before);

  engine.saveManagedSkillLibraryFile(skill.id, 'SKILL.md',
      '---\\nname: camera_guide\\ndescription: 新说明\\n---\\n新正文');
  expect(engine.assistantSkills().singleWhere((item) => item.id == skill.id).description, '新说明');
});

test('资源读写拒绝路径逃逸、链接和不存在的 Markdown', () {
  final skill = importPackage('camera_guide');
  for (final path in ['../outside.md', '/tmp/outside.md', 'new.md']) {
    expect(
      () => engine.saveManagedSkillLibraryFile(skill.id, path, 'x'),
      throwsA(isA<EngineException>()),
    );
  }
});
```

- [x] **Step 2: Run RED**

```bash
cd app
flutter test test/engine/assistant_skill_library_test.dart \
  --plain-name "managed skill library files"
```

Expected: compilation failure because the three file-library APIs do not exist.

- [x] **Step 3: Implement the safe file boundary**

Add `ManagedSkillLibraryFile` near `ManagedAssistantSkill`. `managedSkillLibraryFiles()` selects
managed skill rows in stable ID order, obtains each canonical `SKILL.md` via `_managedFile`, and
recursively collects only `FileSystemEntityType.file` entities whose suffix is `.md`. It calls
`resolveSymbolicLinksSync()` and keeps a file only when `p.isWithin(packageRoot, resolved)`;
the relative path is `p.relative(resolved, from: packageRoot).replaceAll('\\\\', '/')`. Sort by
`displayPath`, where `displayPath` is `$skillId/$relativePath`.

`readManagedAssistantSkillResource()` is the shared canonical read boundary: it accepts only an
existing non-link regular file inside the selected package and rejects absolute paths, `..`, empty
paths, symlinks, and missing files. Move the duplicated safe read in `assistant_skills.dart` to this
API so the existing Agent `read_skill_file` protocol continues to read safe non-Markdown resources.
`readManagedSkillLibraryFile()` delegates to that shared read boundary only after additionally
requiring a `.md` path. `saveManagedSkillLibraryFile()` validates the same Markdown-specific path
conditions before writing. For `SKILL.md`, delegate to `readManagedAssistantSkill()` and
`saveManagedAssistantSkill()`. For other files, use a sibling `.<microseconds>.tmp` file followed by
`renameSync()`; the target must already be a non-link regular Markdown file.

- [x] **Step 4: Run GREEN**

```bash
cd app
flutter test test/engine/assistant_skill_library_test.dart \
  test/engine/assistant_skills_deploy_test.dart --concurrency=1
flutter analyze lib/src/engine/assistant_skill_library.dart \
  lib/src/engine/assistant_skills.dart test/engine/assistant_skill_library_test.dart
```

Expected: the new tests and existing on-demand Agent resource tests pass; analyzer has zero issues.

- [x] **Step 5: Commit Task 1**

```bash
git add app/lib/src/engine/assistant_skill_library.dart \
  app/lib/src/engine/assistant_skills.dart \
  app/test/engine/assistant_skill_library_test.dart
git commit -m "feat(skills): expose managed markdown file tree"
```

### Task 2: 桌面树形导航与紧凑屏逐层浏览

**Files:**
- Modify: `app/lib/src/screens/agent/agent_chat_screen.dart`
- Modify: `app/lib/l10n/app_zh.arb`
- Modify: `app/lib/l10n/app_en.arb`
- Modify: `app/lib/l10n/app_ja.arb`
- Test: `app/test/widgets/agent_chat_screen_test.dart`

**Consumes:** Task 1 `ManagedSkillLibraryFile` APIs.

**Produces:** A private immutable `_SkillTreeNode` with `label`, `path`, `file`, and `children`; it is
built from `displayPath` without database writes. `_AssistantSkillsPane` stores
`_selectedSkillId`, `_selectedRelativePath`, and compact `_directoryPath` instead of one selected ID.

- [x] **Step 1: Write failing cross-platform widget tests**

Add a package fixture with `camera_guide/SKILL.md`, `camera_guide/references/shot-list.md`, and
`style_guide/SKILL.md`. Add these exact flows:

```dart
testWidgets('桌面技能树展开深层 Markdown，预览并保存资源文件', (tester) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await openSkillsTab(tester);

  await tester.tap(find.byKey(const ValueKey('skill-tree-toggle-camera_guide')));
  await tester.tap(find.byKey(const ValueKey('skill-tree-toggle-camera_guide/references')));
  await tester.tap(find.byKey(const ValueKey('skill-tree-file-camera_guide/references/shot-list.md')));
  await tester.pumpAndSettle();
  expect(find.textContaining('深层镜头表'), findsOneWidget);

  await tester.tap(find.byKey(const ValueKey('assistant-skill-file-edit')));
  await tester.enterText(find.byKey(const ValueKey('assistant-skill-editor')), '改后的深层镜头表');
  await tester.tap(find.byKey(const ValueKey('assistant-skill-file-save')));
  expect(engine.readManagedSkillLibraryFile('camera_guide', 'references/shot-list.md'), '改后的深层镜头表');
});

testWidgets('390dp 技能树可进入目录、搜索深层文件并逐层返回', (tester) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await openSkillsTab(tester);

  await tester.tap(find.byKey(const ValueKey('skill-tree-directory-camera_guide')));
  await tester.tap(find.byKey(const ValueKey('skill-tree-directory-camera_guide/references')));
  await tester.tap(find.byKey(const ValueKey('skill-tree-file-camera_guide/references/shot-list.md')));
  expect(find.textContaining('深层镜头表'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('assistant-skill-back')));
  expect(find.byKey(const ValueKey('skill-tree-directory-camera_guide/references')), findsOneWidget);

  await tester.enterText(find.byKey(const ValueKey('assistant-skills-search')), 'shot-list');
  expect(find.text('camera_guide/references/shot-list.md'), findsOneWidget);
});
```

- [x] **Step 2: Run RED**

```bash
cd app
flutter test test/widgets/agent_chat_screen_test.dart \
  --plain-name "桌面技能树展开深层 Markdown，预览并保存资源文件"
```

Expected: failure because no tree node keys or resource-file editor exist.

- [x] **Step 3: Implement the responsive tree**

Create `_SkillTreeNode.fromFiles(List<ManagedSkillLibraryFile>)` in the same screen file. Split each
`displayPath` on `/`, insert directory nodes into a `SplayTreeMap<String, _SkillTreeNode>`, and expose
directories before files in lexical order. File nodes hold their originating `ManagedSkillLibraryFile`.

On desktop, replace the flat Markdown portion of `_buildList` with recursive `ExpansionTile` nodes;
use `skill-tree-toggle-<path>` for directory toggles and `skill-tree-file-<displayPath>` for files.
Keep built-in actions as their existing flat, toggleable cards beneath an `agentSkillsBuiltinTitle` header.
On compact screens, filter children by `_directoryPath`, show directories with
`skill-tree-directory-<path>`, push a segment on tap, and make the leading back action pop one segment
before clearing selection. A nonempty search produces matching file rows labelled with full
`displayPath`.

The detail pane reads/saves through `readManagedSkillLibraryFile` and
`saveManagedSkillLibraryFile`; its action keys are `assistant-skill-file-edit` and
`assistant-skill-file-save`. Add three localized labels in every ARB: `agentSkillsRoot` (技能文件),
`agentSkillsFiles` (文件), and `agentSkillsOpenFolder` (打开目录). Run Flutter l10n generation using
the repository's existing `flutter gen-l10n` command if generated localization sources change.

- [x] **Step 4: Run GREEN and regressions**

```bash
cd app
flutter test test/widgets/agent_chat_screen_test.dart \
  test/engine/assistant_skill_library_test.dart \
  test/engine/assistant_skills_deploy_test.dart --concurrency=1
flutter analyze
```

Expected: existing import/search/scan/detail behavior, desktop tree, and 390dp drill-down all pass;
analyzer has zero issues.

- [x] **Step 5: Commit Task 2**

```bash
git add app/lib/src/screens/agent/agent_chat_screen.dart \
  app/lib/l10n/app_zh.arb app/lib/l10n/app_en.arb app/lib/l10n/app_ja.arb \
  app/lib/l10n/app_localizations.dart app/lib/l10n/app_localizations_zh.dart \
  app/lib/l10n/app_localizations_en.dart app/lib/l10n/app_localizations_ja.dart \
  app/test/widgets/agent_chat_screen_test.dart
git commit -m "feat(skills): add responsive managed skill tree"
```

### Task 3: Parity closeout and complete verification

**Files:**
- Modify: `docs/parity/skill-runtime-matrix.md`
- Modify: `docs/parity/master-checklist.md`
- Modify: `docs/parity/feature-parity-execution-report.md`
- Modify: `docs/superpowers/plans/2026-07-21-skill-library-tree.md`

- [x] **Step 1: Update only the closed capability**

Mark `W6D-SKILL-001` as verified only if the actual implementation provides recursive Markdown tree
browsing, deep file edit/save, search and 1200dp/390dp evidence. State explicitly that folder import,
ZIP, arbitrary external folders, creation/deletion/rename, and stage-specific Agent attribution were
not added because they are outside the original page or separate parity rows. Keep W2 Agent status
unchanged.

- [x] **Step 2: Run full verification**

```bash
node tool/parity/check_no_orphans.js
cd app
flutter test --concurrency=1 --reporter compact
flutter analyze
flutter build macos --debug
cd ..
git diff --check
```

Expected: `538/538` inventory coverage, all offline tests pass, analyzer is clean, macOS debug app
builds, and whitespace check is empty. No command invokes a real video provider.

- [x] **Step 3: Commit Task 3**

```bash
git add docs/parity/skill-runtime-matrix.md \
  docs/parity/master-checklist.md \
  docs/parity/feature-parity-execution-report.md \
  docs/superpowers/plans/2026-07-21-skill-library-tree.md
git commit -m "docs(parity): close skill library tree gap"
```
