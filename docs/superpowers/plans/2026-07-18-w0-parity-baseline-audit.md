# W0 Parity Baseline Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 冻结 ToonFlow 1.1.8 三元基线（Toonflow-app + Toonflow-web + 打包 ToonFlow.app），机械生成库存清单，产出无孤儿项的《100% 复刻总对照清单》与许可证审计，供 L0b 决策与 W1–W4 立项。

**Architecture:** 全部产物落在 `dramaflow` 仓库 `docs/parity/`；生成与校验脚本落在 `tool/parity/`（零依赖 Node 脚本，node ≥ 20 已随 Toonflow-app 环境存在）。W0 对 `Toonflow-app` / `Toonflow-web` 严格只读；黑盒验证按第 6 节隔离协议执行。审计判定六态写入 `master-checklist.md`，`check_no_orphans.js` 机器校验库存全覆盖。

**Tech Stack:** Node 20（零依赖脚本）、sqlite3 CLI、shasum、git worktree、jq。

**Authority:** `docs/superpowers/specs/2026-07-17-toonflow-100-parity-master-roadmap-and-w0-audit-design.md` 第 3、5 节。

## Global Constraints

- 审计期间**不修改** `/Users/luke/Documents/aivideo/Toonflow-app` 与 `/Users/luke/Documents/aivideo/Toonflow-web` 的任何文件（spec §3）。
- W0 零产品代码改动：只允许新增 `docs/parity/**` 与 `tool/parity/**`（spec §4 "只读审计"）。
- 运行库能力快照（Task 2）必须在任何黑盒验证会话（Task 7+）之前生成并提交（spec §3）。
- 黑盒验证六条硬约束（spec §5.2）全部强制；隔离方案**锁定为"移动目录 + 全新临时数据"**（见 Task 6，不留执行者临场决定）。
- 所有审计产物（截图/日志/文档）不得含 API key、小说正文、个人数据（spec §5.2）。
- 分支纪律：本计划在独立 worktree 分支 `w0-audit` 执行，逐行审核后合入 `develop`；提交只 add 明确列出的文件，禁止 `git add .`（spec §9）。
- 状态六态：`未审计 / 缺失 / 部分实现 / 已验证等价 / 已验证更优 / 不适用`；只有后三者算绿；"已验证更优"必须附打包版对照用例（spec §5.1、§2）。
- 旧 parity checklist（`docs/superpowers/progress/2026-07-04-page-parity-checklist.md`）只作线索，其结论不自动继承（spec §5.2）。

---

### Task 1: Worktree 与基线 SHA-256 清单生成器

**Files:**
- Create: `tool/parity/gen_baseline_manifest.js`
- Create: `docs/parity/baseline-manifest.json`（脚本产物）

**Interfaces:**
- Produces: `docs/parity/baseline-manifest.json`，结构 `{generatedAt, toonflowApp:{version,fileCount,files:{<relPath>:<sha256>}}, toonflowWeb:{commit,dirty}, packagedApp:{root,fileCount,files:{...}}, correspondenceNote}`。后续任务以此为基线漂移检测依据。

- [ ] **Step 1: 建 worktree 分支**

```bash
cd /Users/luke/Documents/aivideo/dramaflow
git worktree add ../dramaflow-w0 -b w0-audit develop
cd ../dramaflow-w0
```

预期：新目录 `../dramaflow-w0`，分支 `w0-audit` 基于 `develop`。

- [ ] **Step 2: 写清单生成器**

创建 `tool/parity/gen_baseline_manifest.js`：

```js
#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync } = require('child_process');

const APP = '/Users/luke/Documents/aivideo/Toonflow-app';
const WEB = '/Users/luke/Documents/aivideo/Toonflow-web';
const OUT = path.join(__dirname, '..', '..', 'docs', 'parity', 'baseline-manifest.json');
const EXCLUDE_DIRS = new Set(['node_modules', '.git', 'tmp']);

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function walk(root, rel, out) {
  const abs = path.join(root, rel);
  const st = fs.lstatSync(abs);
  if (st.isSymbolicLink()) return;
  if (st.isDirectory()) {
    if (EXCLUDE_DIRS.has(path.basename(abs))) return;
    for (const name of fs.readdirSync(abs).sort()) walk(root, path.join(rel, name), out);
  } else if (st.isFile()) {
    out[rel] = sha256(abs);
  }
}

function manifestFor(root, subpaths) {
  const files = {};
  for (const p of subpaths) {
    if (fs.existsSync(path.join(root, p))) walk(root, p, files);
  }
  return { fileCount: Object.keys(files).length, files };
}

const appVersion = JSON.parse(fs.readFileSync(path.join(APP, 'package.json'), 'utf8')).version;
const webCommit = execSync('git rev-parse HEAD', { cwd: WEB }).toString().trim();
const webDirty = execSync('git status --porcelain', { cwd: WEB }).toString().trim();

const manifest = {
  generatedAt: new Date().toISOString(),
  toonflowApp: { version: appVersion, ...manifestFor(APP, ['src', 'data', 'package.json', 'build', 'scripts', 'LICENSE', 'NOTICES.txt']) },
  toonflowWeb: { commit: webCommit, dirty: webDirty === '' ? false : webDirty.split('\n') },
  packagedApp: { root: 'dist/mac-arm64/ToonFlow.app', ...manifestFor(APP, ['dist/mac-arm64/ToonFlow.app/Contents/Resources']) },
  correspondenceNote: '前端源码 commit 与 data/web/index.html 无构建指纹可严格对应；行为歧义以打包版 ToonFlow.app 实际行为为仲裁（spec §3）。',
};
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(manifest, null, 2) + '\n');
console.log(`app files=${manifest.toonflowApp.fileCount} packaged files=${manifest.packagedApp.fileCount} web=${webCommit.slice(0, 7)} dirty=${manifest.toonflowWeb.dirty !== false}`);
```

- [ ] **Step 3: 运行并验证产物**

```bash
node tool/parity/gen_baseline_manifest.js
jq -r '.toonflowApp.version, .toonflowWeb.commit[0:7], (.toonflowApp.fileCount>100), (.packagedApp.fileCount>10)' docs/parity/baseline-manifest.json
```

预期输出四行：`1.1.8`、`9c4cb0e`、`true`、`true`。若 `toonflowWeb.dirty != false`，停下向审核方报告（基线不干净必须先记录说明，spec §3 漂移条款）。

- [ ] **Step 4: 提交**

```bash
git add tool/parity/gen_baseline_manifest.js docs/parity/baseline-manifest.json
git commit -m "docs(parity): freeze toonflow baseline manifest"
```

---

### Task 2: 运行库能力快照（无密钥，黑盒会话前置门）

**Files:**
- Create: `tool/parity/gen_runtime_capabilities.js`
- Create: `docs/parity/baseline-runtime-capabilities.json`（脚本产物）

**Interfaces:**
- Consumes: `~/Library/Application Support/toonflow/data/db2.sqlite` 的 `o_vendorConfig(id, inputValues, models, enable)`（只读）。
- Produces: 无密钥快照 JSON；Task 6+ 黑盒会话的前置条件。

- [ ] **Step 1: 写快照生成器（白名单式脱敏）**

创建 `tool/parity/gen_runtime_capabilities.js`。脱敏采用**白名单反向策略**：凡键名匹配 `/key|token|secret|password|authorization|cookie/i` 的值一律替换为 `"<redacted>"`（保留键名以冻结结构）：

```js
#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const DB = path.join(os.homedir(), 'Library/Application Support/toonflow/data/db2.sqlite');
const OUT = path.join(__dirname, '..', '..', 'docs', 'parity', 'baseline-runtime-capabilities.json');
const SECRET = /key|token|secret|password|authorization|cookie/i;

function redact(value) {
  if (Array.isArray(value)) return value.map(redact);
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = SECRET.test(k) ? '<redacted>' : redact(v);
    return out;
  }
  return value;
}

const rows = JSON.parse(execFileSync('sqlite3', ['-json', DB,
  "SELECT id, enable, inputValues, models FROM o_vendorConfig ORDER BY id;"]).toString() || '[]');
const vendors = rows.map((r) => ({
  id: r.id,
  enable: r.enable,
  inputValues: redact(JSON.parse(r.inputValues || '{}')),
  models: redact(JSON.parse(r.models || '[]')),
}));
const promptDir = path.join(os.homedir(), 'Library/Application Support/toonflow/data/modelPrompt');
const promptFiles = fs.existsSync(promptDir)
  ? execFileSync('find', [promptDir, '-type', 'f', '-name', '*.md']).toString().trim().split('\n')
      .map((p) => path.relative(promptDir, p)).sort()
  : [];
fs.writeFileSync(OUT, JSON.stringify({ generatedAt: new Date().toISOString(), vendors, promptFiles }, null, 2) + '\n');
console.log(`vendors=${vendors.length} promptFiles=${promptFiles.length}`);
```

- [ ] **Step 2: 运行并做防泄漏自检**

```bash
node tool/parity/gen_runtime_capabilities.js
grep -icE '"(api)?key[^"]*"\s*:\s*"[^<]' docs/parity/baseline-runtime-capabilities.json || echo CLEAN
jq -r '[.vendors[].id] | join(",")' docs/parity/baseline-runtime-capabilities.json
```

预期：第二条输出 `CLEAN`（任何秘密键名的值都不是明文）；第三条含 `volcengine`（Seedance Mini 运行时模型所在 vendor）。若非 `CLEAN`：**禁止提交**，修脚本重跑。

- [ ] **Step 3: 提交**

```bash
git add tool/parity/gen_runtime_capabilities.js docs/parity/baseline-runtime-capabilities.json
git commit -m "docs(parity): snapshot runtime capabilities without secrets"
```

---

### Task 3: 库存清单机械生成器（inventory）

**Files:**
- Create: `tool/parity/gen_inventory.js`
- Create: `docs/parity/inventory.json`（脚本产物）

**Interfaces:**
- Produces: `docs/parity/inventory.json`：`{generatedAt, items:[{id, kind, source}]}`。`id` 稳定格式（下列 kind 前缀）；Task 4 校验器与 Task 6–10 审计单元都以 `id` 为对账主键：
  - `web.route:<path>`（Toonflow-web/src/router/** 的 route path）
  - `web.page:<relPath>`（src/pages/**、src/views/** 的 .vue 文件）
  - `app.route:<relDir>/<file>`（Toonflow-app/src/routes/** 的 .ts 文件，登记即路由单元）
  - `app.socket:<relPath>`（src/socket/routes/** 的 .ts 文件）
  - `app.agentTool:<agent>/<relPath>`（src/agents/** 的 .ts 文件）
  - `app.agentUtil:<relPath>`（src/utils/agent/** 的 .ts 文件）
  - `db.table:<name>`（运行库 db2.sqlite 全部表）
  - `asset.vendor:<file>`、`asset.modelPrompt:<relPath>`、`asset.skill:<relPath>`（data/vendor、data/modelPrompt、data/skills）
  - `platform.electron:<symbol>`（build/main.js 中的 `ipcMain.handle/on` 通道名与 `new BrowserWindow` 等平台面；无 ipc 时登记 `platform.electron:main.js` 单条）
  - `config.setting:<key>`（打包版 data 目录与 src 中 `o_setting`/config 默认键，来源 `src/lib` 与运行库 `o_setting` 表键名——键名非秘密，值不采集）

- [ ] **Step 1: 写生成器**

创建 `tool/parity/gen_inventory.js`：

```js
#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const APP = '/Users/luke/Documents/aivideo/Toonflow-app';
const WEB = '/Users/luke/Documents/aivideo/Toonflow-web';
const DB = path.join(os.homedir(), 'Library/Application Support/toonflow/data/db2.sqlite');
const OUT = path.join(__dirname, '..', '..', 'docs', 'parity', 'inventory.json');
const items = [];
const add = (id, source) => items.push({ id, source });

function listFiles(root, sub, ext) {
  const dir = path.join(root, sub);
  if (!fs.existsSync(dir)) return [];
  return execFileSync('find', [dir, '-type', 'f', '-name', `*${ext}`]).toString().trim()
    .split('\n').filter(Boolean).map((p) => path.relative(dir, p)).sort();
}

// web routes: 提取 router 目录中所有 path: 'xxx' / path: "xxx"
for (const f of listFiles(WEB, 'src/router', '.ts')) {
  const text = fs.readFileSync(path.join(WEB, 'src/router', f), 'utf8');
  for (const m of text.matchAll(/path:\s*['"]([^'"]+)['"]/g)) add(`web.route:${m[1]}`, `src/router/${f}`);
}
for (const f of listFiles(WEB, 'src/pages', '.vue')) add(`web.page:pages/${f}`, `src/pages/${f}`);
for (const f of listFiles(WEB, 'src/views', '.vue')) add(`web.page:views/${f}`, `src/views/${f}`);
// app backend
for (const f of listFiles(APP, 'src/routes', '.ts')) add(`app.route:${f}`, `src/routes/${f}`);
for (const f of listFiles(APP, 'src/socket/routes', '.ts')) add(`app.socket:${f}`, `src/socket/routes/${f}`);
for (const f of listFiles(APP, 'src/agents', '.ts')) add(`app.agentTool:${f}`, `src/agents/${f}`);
for (const f of listFiles(APP, 'src/utils/agent', '.ts')) add(`app.agentUtil:${f}`, `src/utils/agent/${f}`);
// db tables
for (const r of JSON.parse(execFileSync('sqlite3', ['-json', DB,
  "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;"]).toString() || '[]')) {
  add(`db.table:${r.name}`, 'db2.sqlite');
}
// data assets
for (const f of listFiles(APP, 'data/vendor', '.ts')) add(`asset.vendor:${f}`, `data/vendor/${f}`);
for (const f of listFiles(APP, 'data/modelPrompt', '.md')) add(`asset.modelPrompt:${f}`, `data/modelPrompt/${f}`);
for (const f of listFiles(APP, 'data/skills', '.md')) add(`asset.skill:${f}`, `data/skills/${f}`);
// settings keys（运行库 o_setting 键名；键名非秘密）
for (const r of JSON.parse(execFileSync('sqlite3', ['-json', DB,
  "SELECT key FROM o_setting ORDER BY key;"]).toString() || '[]')) {
  add(`config.setting:${r.key}`, 'db2.sqlite:o_setting');
}
// electron 平台面
const mainJs = path.join(APP, 'build/main.js');
if (fs.existsSync(mainJs)) {
  const text = fs.readFileSync(mainJs, 'utf8');
  const channels = [...text.matchAll(/ipcMain\.(?:handle|on)\(\s*['"]([^'"]+)['"]/g)].map((m) => m[1]);
  if (channels.length === 0) add('platform.electron:main.js', 'build/main.js');
  for (const c of [...new Set(channels)].sort()) add(`platform.electron:${c}`, 'build/main.js');
}
const dedup = [...new Map(items.map((i) => [i.id, i])).values()];
fs.writeFileSync(OUT, JSON.stringify({ generatedAt: new Date().toISOString(), items: dedup }, null, 2) + '\n');
const byKind = {};
for (const i of dedup) { const k = i.id.split(':')[0]; byKind[k] = (byKind[k] || 0) + 1; }
console.log(JSON.stringify(byKind));
```

维度说明：spec §5.2 的"菜单与主要操作"不可靠地机械正则化——它们是页面的行为面，归并进对应 `web.page:*` / `web.route:*` 条目的行为审计（Task 6 的"用户行为"列必须覆盖该页菜单入口与主要操作），不单设库存 id。

- [ ] **Step 2: 运行并抽查**

```bash
node tool/parity/gen_inventory.js
jq '[.items[].id] | length' docs/parity/inventory.json
jq -r '.items[].id' docs/parity/inventory.json | grep -cE '^db\.table:o_novel$|^app\.agentTool:'
```

预期：总数 > 100；第二条 ≥ 2（`o_novel` 表与至少一个 agent 工具文件存在）。把 Step 1 打印的分类计数记入 commit message。若 `web.route` 计数为 0：读 `Toonflow-web/src/router/` 实际文件调整正则后重跑（路由声明写法可能不同），不许带 0 提交。

- [ ] **Step 3: 提交**

```bash
git add tool/parity/gen_inventory.js docs/parity/inventory.json
git commit -m "docs(parity): generate mechanical toonflow inventory"
```

---

### Task 4: 总对照清单骨架 + 无孤儿校验器

**Files:**
- Create: `docs/parity/master-checklist.md`
- Create: `docs/parity/inventory-na.md`
- Create: `tool/parity/check_no_orphans.js`

**Interfaces:**
- Consumes: `docs/parity/inventory.json`（Task 3）。
- Produces: 清单行格式（下述）与校验器退出码协议：孤儿数 >0 时 exit 1 并列出孤儿 id。Task 6–10 每单元收尾必须跑校验器；Task 11 收尾必须全绿。

- [ ] **Step 1: 写清单骨架**

创建 `docs/parity/master-checklist.md`，只含表头与格式约定（行由审计单元逐步追加）：

```markdown
# ToonFlow 100% 复刻总对照清单

法定定义文件（spec §5.1）。状态六态：未审计 / 缺失 / 部分实现 / 已验证等价 / 已验证更优 / 不适用。
只有"已验证等价 / 已验证更优 / 不适用"算绿；"已验证更优"必须附打包版对照用例。

行格式（管道表，一行一条目）：

| ID | 模块/页面 | ToonFlow 源码证据 | 用户行为 | 数据依赖 | DramaFlow 实现证据 | 状态 | 验收方法 | 自动化测试 | 覆盖库存 | 备注 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
```

`覆盖库存` 列 = 逗号分隔的 inventory id（对账主键）。跨多库存项的行为条目可covering多个 id；一个 id 也可被多行覆盖。

创建 `docs/parity/inventory-na.md`：

```markdown
# 库存 N/A 判定表

不进入总对照清单的库存项。每条必须有理由（spec §5.1："不适用"仅限 Electron/浏览器平台特有且 macOS 原生形态无对应用户价值）。

| 库存 ID | 理由 |
| --- | --- |
```

- [ ] **Step 2: 写无孤儿校验器**

创建 `tool/parity/check_no_orphans.js`：

```js
#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const DOCS = path.join(__dirname, '..', '..', 'docs', 'parity');
const inv = JSON.parse(fs.readFileSync(path.join(DOCS, 'inventory.json'), 'utf8'));
const checklist = fs.readFileSync(path.join(DOCS, 'master-checklist.md'), 'utf8');
const na = fs.readFileSync(path.join(DOCS, 'inventory-na.md'), 'utf8');
const covered = new Set();
for (const line of checklist.split('\n')) {
  const cells = line.split('|').map((c) => c.trim());
  if (cells.length < 12 || cells[1] === 'ID' || cells[1].startsWith('---')) continue;
  for (const id of cells[10].split(',').map((s) => s.trim()).filter(Boolean)) covered.add(id);
}
for (const line of na.split('\n')) {
  const cells = line.split('|').map((c) => c.trim());
  if (cells.length >= 3 && cells[1] && !['库存 ID', ''].includes(cells[1]) && !cells[1].startsWith('---')) {
    if (!cells[2]) { console.error(`NA missing reason: ${cells[1]}`); process.exitCode = 1; }
    covered.add(cells[1]);
  }
}
const orphans = inv.items.map((i) => i.id).filter((id) => !covered.has(id));
const unknown = [...covered].filter((id) => !inv.items.some((i) => i.id === id));
if (unknown.length) console.error(`WARN unknown ids referenced: ${unknown.length}\n` + unknown.slice(0, 20).join('\n'));
if (orphans.length) {
  console.error(`ORPHANS ${orphans.length}/${inv.items.length}`);
  console.error(orphans.join('\n'));
  process.exit(1);
}
console.log(`OK all ${inv.items.length} inventory items covered`);
```

- [ ] **Step 3: 验证校验器按预期失败（TDD）**

```bash
node tool/parity/check_no_orphans.js; echo "exit=$?"
```

预期：`ORPHANS <总数>/<总数>` 且 `exit=1`（清单为空，全部孤儿=待办清单）。随后临时在 `inventory-na.md` 加一行任意库存 id + 理由，重跑应见孤儿数减 1，然后**删掉这行测试数据**再重跑回到全孤儿。

- [ ] **Step 4: 提交**

```bash
git add docs/parity/master-checklist.md docs/parity/inventory-na.md tool/parity/check_no_orphans.js
git commit -m "docs(parity): add master checklist skeleton and orphan gate"
```

---

### Task 5: 黑盒会话隔离工具（方案锁定：移动目录 + 全新临时数据）

**Files:**
- Create: `tool/parity/blackbox_toonflow.sh`

**Interfaces:**
- Produces: `backup` / `isolate` / `restore` / `verify` 四个子命令；Task 6–10 中任何需要运行打包版 `ToonFlow.app` 的步骤，必须按 `backup → verify → isolate → (运行/取证) → restore → verify` 顺序调用本脚本，禁止手工 mv。

隔离方案在此锁定（评审约束 3）：**不使用独立 macOS 用户**（需要管理员操作、不可脚本化审计）；采用"退出应用 → 校验备份 → 原目录整体移出 → 打包版在全新数据目录上运行 → 会话后删除临时数据 → 原目录移回 → 哈希与项目数复核"。

- [ ] **Step 1: 写脚本**

创建 `tool/parity/blackbox_toonflow.sh`：

```bash
#!/bin/bash
set -euo pipefail
LIVE="$HOME/Library/Application Support/toonflow"
WORK="$HOME/Documents/dramaflow-w0-blackbox"
BACKUP="$WORK/backup"
ASIDE="$WORK/live-aside"
MANIFEST="$WORK/backup.sha256"

die() { echo "FATAL: $1" >&2; exit 1; }
assert_quit() { pgrep -x ToonFlow >/dev/null && die "ToonFlow 正在运行，先退出"; return 0; }

case "${1:-}" in
  backup)
    assert_quit
    [ -d "$LIVE" ] || die "$LIVE 不存在"
    mkdir -p "$WORK"
    rsync -a --delete "$LIVE/" "$BACKUP/"
    (cd "$BACKUP" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256) > "$MANIFEST"
    sqlite3 "$BACKUP/data/db2.sqlite" "SELECT count(*) FROM o_project;" > "$WORK/project-count.txt"
    echo "backup ok: $(wc -l < "$MANIFEST") files, projects=$(cat "$WORK/project-count.txt")"
    ;;
  verify)
    (cd "$BACKUP" && shasum -a 256 -c "$MANIFEST" --quiet) && echo "backup manifest OK"
    ;;
  isolate)
    assert_quit
    [ -f "$MANIFEST" ] || die "先 backup"
    [ -e "$ASIDE" ] && die "已处于隔离态"
    mv "$LIVE" "$ASIDE"
    echo "isolated: 打包版下次启动将创建全新数据目录"
    ;;
  restore)
    assert_quit
    [ -d "$ASIDE" ] || die "不在隔离态"
    [ -e "$LIVE" ] && rm -rf "$LIVE"   # 会话产生的临时数据，整体丢弃
    mv "$ASIDE" "$LIVE"
    (cd "$LIVE" && shasum -a 256 -c "$MANIFEST" --quiet) || die "恢复后哈希不一致，用 $BACKUP 排查"
    LIVE_COUNT=$(sqlite3 "$LIVE/data/db2.sqlite" "SELECT count(*) FROM o_project;")
    [ "$LIVE_COUNT" = "$(cat "$WORK/project-count.txt")" ] || die "项目数不一致"
    echo "restore ok: projects=$LIVE_COUNT"
    ;;
  *) die "usage: blackbox_toonflow.sh backup|verify|isolate|restore" ;;
esac
```

```bash
chmod +x tool/parity/blackbox_toonflow.sh
```

- [ ] **Step 2: 用夹具目录自测恢复逻辑（不碰真实目录）**

```bash
FIXTURE=$(mktemp -d)/toonflow-fixture
mkdir -p "$FIXTURE/data" && echo demo > "$FIXTURE/data/f.txt"
sqlite3 "$FIXTURE/data/db2.sqlite" "CREATE TABLE o_project(id); INSERT INTO o_project VALUES (1);"
sed -e "s|\$HOME/Library/Application Support/toonflow|$FIXTURE|" \
    -e "s|\$HOME/Documents/dramaflow-w0-blackbox|$FIXTURE-work|" \
    tool/parity/blackbox_toonflow.sh > /tmp/bb_test.sh && chmod +x /tmp/bb_test.sh
/tmp/bb_test.sh backup && /tmp/bb_test.sh verify && /tmp/bb_test.sh isolate
echo polluted > "$FIXTURE/data/x.txt" 2>/dev/null || mkdir -p "$FIXTURE/data" && echo polluted > "$FIXTURE/data/x.txt"
/tmp/bb_test.sh restore
rm -rf "$FIXTURE" "$FIXTURE-work" /tmp/bb_test.sh
```

预期：backup/verify/isolate 依次成功；隔离期写入的污染数据在 restore 时被丢弃；restore 输出 `restore ok: projects=1`。

- [ ] **Step 3: 对真实目录执行一次 backup + verify（只读操作）**

```bash
tool/parity/blackbox_toonflow.sh backup
tool/parity/blackbox_toonflow.sh verify
```

预期：`backup ok` + `backup manifest OK`。此时**不执行 isolate**——隔离只在审计单元确需黑盒时按需进入并当场 restore。

- [ ] **Step 4: 提交**

```bash
git add tool/parity/blackbox_toonflow.sh
git commit -m "docs(parity): add black-box isolation protocol tooling"
```

---

### Task 6: 审计单元——前端页面 / 路由 / 菜单

**Files:**
- Modify: `docs/parity/master-checklist.md`（追加行）
- Modify: `docs/parity/inventory-na.md`（如有 N/A）

**Interfaces:**
- Consumes: `inventory.json` 中 `web.route:*`、`web.page:*`；`Toonflow-web/src`（只读）；黑盒协议（Task 5）。
- Produces: 覆盖全部 `web.*` 库存 id 的清单行。

审计程序（Task 7–10 同构，均按此四步；后续任务不再重复展开）：

- [ ] **Step 1: 生成本单元工作清单**

```bash
node tool/parity/check_no_orphans.js 2>&1 | grep -E '^web\.' > /tmp/w0-unit-web.txt
wc -l /tmp/w0-unit-web.txt
```

- [ ] **Step 2: 逐项审计并追加清单行**

对工作清单每个 id：通读对应源码（页面组件、路由守卫、菜单入口、页面内主要操作）→ 提取**用户可观察行为**（禁止"页面存在"式断言，spec §5.1）→ 对照 DramaFlow（`app/lib/src/screens/**` + `app/test/**`）判六态 → 追加行。示例行（格式基准）：

```markdown
| W-PROD-001 | 制作画布 | Toonflow-web/src/views/production/xxx.vue:1 | 拖拽节点后画布保存节点位置，刷新后位置不变 | o_agentWorkData | app/lib/src/screens/production/production_screen.dart; app/test/widgets/production_screen_test.dart | 部分实现 | 黑盒对照：打包版拖拽→刷新 vs DramaFlow 同操作 | production_screen_test.dart | web.page:views/production/xxx.vue | 位置持久化未见测试 |
```

判定纪律（spec §5.1）：DramaFlow 有代码无测试/运行证据 → 最高"部分实现"；源码看不出用户可观察效果的 → 按 Task 5 协议进入黑盒会话确认（backup→verify→isolate→取证→restore→verify 全链），产物脱敏。

- [ ] **Step 3: 跑孤儿校验（本单元清零）**

```bash
node tool/parity/check_no_orphans.js 2>&1 | grep -cE '^web\.' || echo WEB-CLEAR
```

预期：`WEB-CLEAR`。

- [ ] **Step 4: 提交**

```bash
git add docs/parity/master-checklist.md docs/parity/inventory-na.md
git commit -m "docs(parity): audit web pages and routes unit"
```

---

### Task 7: 审计单元——后端 HTTP 路由 + Socket 事件

**Files:**
- Modify: `docs/parity/master-checklist.md`、`docs/parity/inventory-na.md`

**Interfaces:**
- Consumes: `app.route:*`、`app.socket:*` 库存；`Toonflow-app/src/routes`、`src/socket`（只读）。
- Produces: 覆盖全部 `app.route:*`、`app.socket:*` 的清单行。

- [ ] **Step 1–4**: 按 Task 6 审计程序执行，工作清单过滤命令：

```bash
node tool/parity/check_no_orphans.js 2>&1 | grep -E '^app\.(route|socket):' > /tmp/w0-unit-approute.txt
```

行为提取要点：每个 route 文件 = 一组用户可触发的后端行为（入参校验、副作用、错误语义）；DramaFlow 对照物是 `app/lib/src/engine/**` 与其测试。收尾孤儿过滤清零后提交：

```bash
git add docs/parity/master-checklist.md docs/parity/inventory-na.md
git commit -m "docs(parity): audit backend routes and socket unit"
```

---

### Task 8: 审计单元——Agent 工具面

**Files:**
- Modify: `docs/parity/master-checklist.md`、`docs/parity/inventory-na.md`

**Interfaces:**
- Consumes: `app.agentTool:*`、`app.agentUtil:*` 库存；`src/agents/{scriptAgent,productionAgent}`、`src/utils/agent`（只读）。
- Produces: Agent 面清单行 + **W2 前置证据**：JS 解释器 / ES-DSL 是否存在于 ToonFlow 原版的正式留证行（spec §8 W2 复核要求）。

- [ ] **Step 1–4**: 按 Task 6 程序执行，工作清单过滤命令：

```bash
node tool/parity/check_no_orphans.js 2>&1 | grep -E '^app\.agent' > /tmp/w0-unit-agent.txt
```

额外硬性要求：W2 前置留证写进 `master-checklist.md` 专用行（ID 前缀 `W2-EVIDENCE-`），内容为对 `src/agents/**`、`src/utils/agent/**` 与 `Toonflow-web/src/**` 全量检索 JS 解释器 / ES-DSL 痕迹的命中结果与结论（spec §8 要求 W0 在完整基线上正式留证）。检索命令（结果原样记录进该行）：

```bash
grep -rniE "custom-js|new Function|queryPlan" \
  /Users/luke/Documents/aivideo/Toonflow-app/src \
  /Users/luke/Documents/aivideo/Toonflow-web/src | grep -v node_modules | head -30
```

收尾提交：

```bash
git add docs/parity/master-checklist.md docs/parity/inventory-na.md
git commit -m "docs(parity): audit agent tool surface unit"
```

---

### Task 9: 审计单元——资产面 + 数据库表 + 设置键

**Files:**
- Modify: `docs/parity/master-checklist.md`、`docs/parity/inventory-na.md`

**Interfaces:**
- Consumes: `asset.*`、`db.table:*`、`config.setting:*` 库存；运行库快照（Task 2）。
- Produces: 资产/表/设置面清单行；本地扩展标记（spec §3：ima2.ts、azt.ts、Seedance Mini 运行时模型、fixDB 等标注"本地扩展"来源）。

- [ ] **Step 1–4**: 按 Task 6 程序执行，过滤前缀 `^(asset|db\.table|config\.setting)`。要点：`db.table` 行为=该表承载的用户可观察数据语义（如 o_novel.eventState 的成功/失败可见性）；vendor/prompt/skill 资产行为=其对生成效果的用户可见影响；"本地扩展"在备注列显式标注。收尾提交：

```bash
git add docs/parity/master-checklist.md docs/parity/inventory-na.md
git commit -m "docs(parity): audit assets, tables and settings unit"
```

---

### Task 10: 审计单元——Electron 平台面（IPC / 导入导出 / 更新）

**Files:**
- Modify: `docs/parity/master-checklist.md`、`docs/parity/inventory-na.md`

**Interfaces:**
- Consumes: `platform.electron:*` 库存；`Toonflow-app/build/main.js`（package.json `main` 字段所指，只读）与 `electron-builder.yml`。
- Produces: 平台面清单行；"不适用"判定集中在本单元（Electron 特有且 macOS 原生无对应用户价值的，逐条写理由进 `inventory-na.md`）。

- [ ] **Step 1–4**: 按 Task 6 程序执行，过滤前缀 `^platform\.`。文件导入导出（docx 导入、成片导出路径）、自动更新、窗口管理逐项判定；纯 Electron 壳机制（如 BrowserWindow 生命周期）允许 N/A 但必须写理由。收尾提交：

```bash
git add docs/parity/master-checklist.md docs/parity/inventory-na.md
git commit -m "docs(parity): audit electron platform unit"
```

---

### Task 11: 许可证审计（供 L0b 决策）

**Files:**
- Create: `docs/parity/license-audit.md`

**Interfaces:**
- Consumes: `Toonflow-app/LICENSE`（258 行全文）、`NOTICES.txt`、`app/assets/default_skills/toonflow_default_skills.zip`、`app/assets/default_prompts/toonflow_model_prompts.zip`、master-checklist 中标注"本地扩展/移植"的行。
- Produces: 事实清单 + 义务清单 + L0b 三选项决策材料（spec §5.3、§6.2）。**不构成法律意见**。

- [ ] **Step 1: 衍生内容溯源**

解包两个 zip 到临时目录（**只读对照，不改仓库内容**），逐文件对照 ToonFlow 源：

```bash
UNZ=$(mktemp -d)
unzip -q app/assets/default_skills/toonflow_default_skills.zip -d "$UNZ/skills"
unzip -q app/assets/default_prompts/toonflow_model_prompts.zip -d "$UNZ/prompts"
diff -rq "$UNZ/skills" "/Users/luke/Documents/aivideo/Toonflow-app/data/skills" | head -20
diff -rq "$UNZ/prompts" "/Users/luke/Documents/aivideo/Toonflow-app/data/modelPrompt" | head -20
rm -rf "$UNZ"
```

把"完全同源 / 有修改 / DramaFlow 原创"的分类结果写入审计文档。

- [ ] **Step 2: 写审计文档**

`docs/parity/license-audit.md` 章节固定为：

```markdown
# ToonFlow 许可证审计（不构成法律意见）

## 1. ToonFlow 许可证事实
（LICENSE 258 行结构：Apache-2.0 正文 + 补充协议逐条摘录：≥2 第三方分发需书面商业授权、
定价表、品牌保留条款、永久免费场景、AGPL v1.0.8 前不追溯条款——逐条给行号）

## 2. DramaFlow 内 ToonFlow 衍生内容清单
（Step 1 溯源结果：两个 zip 的逐目录同源性 + master-checklist 标注"移植"的行为逻辑清单）

## 3. 第三方资产
（DramaFlow app/assets 与 pubspec 中字体/图片/素材的许可证逐项）

## 4. 义务清单
（Apache-2.0 正文义务：LICENSE 副本、NOTICE 保留、修改声明；补充协议义务：分发授权、品牌保留）

## 5. 品牌条款——需专业意见项
（"不得删除或修改 Toonflow 标识"与改名产品 DramaFlow 的关系；只列问题不下结论）

## 6. L0b 决策选项
（spec §6.2 三选项，各选项的义务后果与所需动作清单）
```

- [ ] **Step 3: 防泄漏自检 + 提交**

```bash
grep -icE 'sk-|Bearer [A-Za-z0-9]|api[_-]?key\s*[:=]\s*[A-Za-z0-9]' docs/parity/license-audit.md || echo CLEAN
git add docs/parity/license-audit.md
git commit -m "docs(parity): complete license audit for L0b"
```

预期 `CLEAN`。

---

### Task 12: W0 完成门（验收）

**Files:**
- Modify: `docs/parity/master-checklist.md`（终检）

W0 验收门（spec §5.4，逐项机器可查）：

- [ ] **Step 1: 全量孤儿校验绿灯**

```bash
node tool/parity/check_no_orphans.js
```

预期：`OK all N inventory items covered`，exit 0。

- [ ] **Step 2: 无"未审计"残留**

```bash
grep -c '| 未审计 |' docs/parity/master-checklist.md || echo NO-UNAUDITED
```

预期：`NO-UNAUDITED`。

- [ ] **Step 3: 基线漂移复检**

```bash
node tool/parity/gen_baseline_manifest.js
git diff --stat docs/parity/baseline-manifest.json
```

预期：无 diff（审计期间基线未漂移）。若有 diff：按 spec §3 显式说明后重新冻结，不许无声吸收。

- [ ] **Step 4: 汇总统计并提交终检**

```bash
grep -oE '\| (缺失|部分实现|已验证等价|已验证更优|不适用) \|' docs/parity/master-checklist.md | sort | uniq -c
git add docs/parity/master-checklist.md
git commit -m "docs(parity): finalize W0 audit gate"
```

- [ ] **Step 5: 合入与推送**

审核方逐行审阅 `w0-audit` 分支全部提交后：

```bash
cd /Users/luke/Documents/aivideo/dramaflow
git checkout develop && git merge --no-ff w0-audit -m "merge: W0 parity baseline audit"
git push origin develop
git worktree remove ../dramaflow-w0 && git branch -d w0-audit
```

- [ ] **Step 6: 用户范围确认（人工门，不可跳过）**

向用户提交：六态统计 + `master-checklist.md` + `inventory-na.md` + `license-audit.md`，请求**范围确认**（确认清单条目与 N/A 判定；这是范围决策，不是测试）。用户确认后 W0 关闭，L0b 决策与 W1–W4 立项解锁。
