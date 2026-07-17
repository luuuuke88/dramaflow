# P0 Provider Preflight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 W1–W4 开发前暴露视频链路风险：完成**恰好一次**真实 Seedance 付费生成（含强杀重启恢复、四项独立证据断言）与**零真实调用**的失败重试演练，产出脱敏证据文档。

**Architecture:** 预检不跑 GUI——用 `Engine.boot()` 在**隔离数据目录**（绝不触碰 `~/Documents/dramaflow` 现用库）驱动与 App 完全相同的嵌入引擎代码路径。真实提交经过本地脱敏转发代理（`model.baseUrl` 指向 loopback，`providers/volcengine_video.dart:121` 已核实可配），代理只记次数不记正文与鉴权。失败演练指向本地假上游，不触达真实供应商。

**Tech Stack:** Node 20（零依赖代理/假上游/断言脚本）、Flutter test（引擎线束）、sqlite3、git worktree。

**Authority:** `docs/superpowers/specs/2026-07-17-toonflow-100-parity-master-roadmap-and-w0-audit-design.md` 第 7 节。

**计划级偏差声明（评审已接受，附范围限定）：**
1. key 只进进程内存（`InMemoryCredentialStore`，零持久化），Keychain 写入推迟到终验收准备。**范围限定：P0 据此只验证引擎/供应商协议路径的凭证使用，不验证 Keychain、设置页与打包 App 凭证路径**——后者由终验收 12 步承担。
2. azt 文本/图片按**服务级 curl 冒烟**执行；引擎侧文本/图片链路由既有测试与 M0–M4 真实生成史覆盖，不在 P0 重复付费验证。
3. `Engine.boot` 直驱 = **引擎冷恢复预检**，不等于真实 App 生命周期验证；GUI 与 macOS 打包行为由终验收 12 步承担。

## Global Constraints

- **修复纪律（spec §7）**：P0 期间默认只诊断与记录。确需修复才能完成预检的阻塞缺陷，单独立任务卡（文件白名单 + 验收命令），在独立 worktree 执行，审核后合入——本计划自身不含任何产品代码修改。
- **key 卫生（spec §7）**：key 不得出现在日志、文档、SQLite 明文、git 提交、终端回显；探测旧库结构只允许输出**键名**，禁止输出值。
- **恰好一次（spec §7）**：真实供应商提交全程 == 1 次。Task 2 自测门未通过前，禁止任何真实调用；失败演练（Task 4）不得触达真实供应商。
- **数据隔离**：线束数据目录固定 `~/Documents/dramaflow-p0-preflight/`，与现用 `~/Documents/dramaflow` 无交集；对旧 ToonFlow 运行库只读。
- 新增线束测试文件必须 env 变量守卫（`P0_LIVE` / `P0_DRILL_CASE`），默认 `flutter test` 全量跑时零副作用、零网络。
- 分支纪律：worktree 分支 `p0-preflight`，逐行审核后合入 `develop`；提交只 add 明确列出的文件（spec §9）。
- 证据文档 `docs/parity/p0-provider-preflight.md` 记录任务 id、耗时、产物路径与断言输出；不含 key 与完整 prompt（spec §7）。

---

### Task 1: Worktree + 脱敏转发代理 + 假上游

**Files:**
- Create: `tool/parity/sanitizing_proxy.js`
- Create: `tool/parity/fake_upstream.js`

**Interfaces:**
- Produces: 代理监听 `P0_PORT`（默认 8791）转发到 `P0_UPSTREAM`；日志 JSONL 每行 `{ts, mark?, method, path, status, ms}`——**永不记录 headers 与 body**；本地控制端点 `POST /__mark`（body `{"mark":"..."}`）向日志插入阶段标记，控制请求不转发不计数。假上游监听 `P0_FAKE_PORT`（默认 8792），`P0_FAKE_MODE=ok|fail|acceptThenFail`（fail=提交即 500；acceptThenFail=接受提交、轮询返回终态 failed）。Task 2/3/5 消费这两个进程。

- [ ] **Step 1: 建 worktree**

```bash
cd /Users/luke/Documents/aivideo/dramaflow
git worktree add ../dramaflow-p0 -b p0-preflight develop
cd ../dramaflow-p0
```

- [ ] **Step 2: 写代理**

创建 `tool/parity/sanitizing_proxy.js`：

```js
#!/usr/bin/env node
'use strict';
const http = require('http');
const https = require('https');
const fs = require('fs');
const { URL } = require('url');

const PORT = Number(process.env.P0_PORT || 8791);
const UPSTREAM = new URL(process.env.P0_UPSTREAM || 'https://ark.cn-beijing.volces.com');
const LOG = process.env.P0_LOG || '/tmp/p0-proxy-log.jsonl';

// 唯一允许落盘的字段。绝不写 headers/body/query。
function logLine(obj) {
  fs.appendFileSync(LOG, JSON.stringify({ ts: new Date().toISOString(), ...obj }) + '\n');
}

http.createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/__mark') {
    let buf = '';
    req.on('data', (c) => (buf += c));
    req.on('end', () => {
      let mark = 'mark';
      try { mark = JSON.parse(buf).mark || 'mark'; } catch (_) {}
      logLine({ mark });
      res.writeHead(204).end();
    });
    return;
  }
  const started = Date.now();
  const pathOnly = req.url.split('?')[0];
  const client = UPSTREAM.protocol === 'https:' ? https : http;
  const proxied = client.request(
    {
      protocol: UPSTREAM.protocol,
      hostname: UPSTREAM.hostname,
      port: UPSTREAM.port || (UPSTREAM.protocol === 'https:' ? 443 : 80),
      method: req.method,
      path: (UPSTREAM.pathname === '/' ? '' : UPSTREAM.pathname) + req.url,
      headers: { ...req.headers, host: UPSTREAM.host },
    },
    (up) => {
      logLine({ method: req.method, path: pathOnly, status: up.statusCode, ms: Date.now() - started });
      res.writeHead(up.statusCode || 502, up.headers);
      up.pipe(res);
    },
  );
  proxied.on('error', (err) => {
    logLine({ method: req.method, path: pathOnly, status: -1, ms: Date.now() - started });
    res.writeHead(502).end(String(err.code || 'proxy_error'));
  });
  req.pipe(proxied);
}).listen(PORT, '127.0.0.1', () => console.log(`proxy 127.0.0.1:${PORT} -> ${UPSTREAM.href} log=${LOG}`));
```

- [ ] **Step 3: 写假上游**

创建 `tool/parity/fake_upstream.js`（模拟 volcengine `contents/generations/tasks` 契约，形状对齐 `app/lib/src/engine/providers/volcengine_video.dart:41-104`）：

```js
#!/usr/bin/env node
'use strict';
const http = require('http');
const fs = require('fs');

const PORT = Number(process.env.P0_FAKE_PORT || 8792);
const MODE = process.env.P0_FAKE_MODE || 'ok'; // ok | fail | acceptThenFail
const CAPTURE = process.env.P0_FAKE_CAPTURE || '/tmp/p0-fake-capture.jsonl';
// 自测需要检查"上游确实收到了 Authorization 与 body"——capture 只写进假上游自己的文件，
// 与代理日志分离；该文件仅在 Task 2 自测中使用假凭证，不会出现真实 key。
let submits = 0;

http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    fs.appendFileSync(CAPTURE, JSON.stringify({
      method: req.method, url: req.url,
      auth: req.headers.authorization || null, bodyLen: body.length, body,
    }) + '\n');
    const json = (code, obj) => {
      res.writeHead(code, { 'content-type': 'application/json' });
      res.end(JSON.stringify(obj));
    };
    if (req.method === 'POST' && req.url.endsWith('/contents/generations/tasks')) {
      submits += 1;
      if (MODE === 'fail') return json(500, { error: { message: 'deterministic preflight failure' } });
      return json(200, { id: `fake-task-${submits}` });
    }
    if (req.method === 'GET' && req.url.includes('/contents/generations/tasks/')) {
      if (MODE === 'fail') return json(500, { error: { message: 'deterministic preflight failure' } });
      if (MODE === 'acceptThenFail') {
        return json(200, { status: 'failed', error: { message: 'deterministic terminal failure' } });
      }
      return json(200, { status: 'succeeded', content: { video_url: `http://127.0.0.1:${PORT}/video.mp4` } });
    }
    if (req.method === 'GET' && req.url === '/video.mp4') {
      res.writeHead(200, { 'content-type': 'video/mp4' });
      return res.end(Buffer.from([0, 0, 0, 24, 102, 116, 121, 112]));
    }
    json(404, { error: 'not found' });
  });
}).listen(PORT, '127.0.0.1', () => console.log(`fake upstream :${PORT} mode=${MODE}`));
```

- [ ] **Step 4: 提交**

```bash
git add tool/parity/sanitizing_proxy.js tool/parity/fake_upstream.js
git commit -m "test(preflight): add sanitizing proxy and fake upstream"
```

---

### Task 2: 代理自测门（假上游，先于一切真实调用）

**Files:**
- Create: `tool/parity/proxy_selftest.js`

**Interfaces:**
- Consumes: Task 1 两个进程。
- Produces: 自测退出码 0 = 允许后续真实调用（评审约束 2 的机器门）。断言：① 上游收到完整 Authorization 与 body；② 代理日志不含 Authorization 值、body 内容、query 串；③ 提交计数、mark、GET 透传、5xx 透传正确。

- [ ] **Step 1: 写自测**

创建 `tool/parity/proxy_selftest.js`：

```js
#!/usr/bin/env node
'use strict';
const { spawn } = require('child_process');
const fs = require('fs');
const http = require('http');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const SENTINEL = path.join(os.homedir(), 'Documents', 'dramaflow-p0-preflight', 'proxy-selftest.ok');
const LOG = '/tmp/p0-selftest-proxy.jsonl';
const CAPTURE = '/tmp/p0-selftest-capture.jsonl';
const FAKE_AUTH = 'Bearer FAKE-SELFTEST-SECRET-DO-NOT-LOG';
const FAKE_BODY = JSON.stringify({ model: 'selftest', content: [{ type: 'text', text: 'SECRET-PROMPT' }] });
for (const f of [LOG, CAPTURE]) fs.rmSync(f, { force: true });

function req(method, path, body, headers) {
  return new Promise((resolve, reject) => {
    const r = http.request({ host: '127.0.0.1', port: 8791, method, path, headers }, (res) => {
      let buf = '';
      res.on('data', (c) => (buf += c));
      res.on('end', () => resolve({ status: res.statusCode, body: buf }));
    });
    r.on('error', reject);
    if (body) r.write(body);
    r.end();
  });
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failed = 0;
const check = (name, ok) => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`); if (!ok) failed += 1; };

(async () => {
  const fake = spawn('node', ['tool/parity/fake_upstream.js'], {
    env: { ...process.env, P0_FAKE_MODE: 'ok', P0_FAKE_CAPTURE: CAPTURE }, stdio: 'inherit' });
  const proxy = spawn('node', ['tool/parity/sanitizing_proxy.js'], {
    env: { ...process.env, P0_PORT: '8791', P0_UPSTREAM: 'http://127.0.0.1:8792', P0_LOG: LOG }, stdio: 'inherit' });
  await sleep(500);

  const post = await req('POST', '/api/v3/contents/generations/tasks?debug=1', FAKE_BODY,
    { 'content-type': 'application/json', authorization: FAKE_AUTH });
  check('POST 200 with task id', post.status === 200 && JSON.parse(post.body).id === 'fake-task-1');
  await req('POST', '/__mark', JSON.stringify({ mark: 'RESTART' }), { 'content-type': 'application/json' });
  const get = await req('GET', '/api/v3/contents/generations/tasks/fake-task-1', null, { authorization: FAKE_AUTH });
  check('GET poll succeeded passthrough', get.status === 200 && JSON.parse(get.body).status === 'succeeded');

  const cap = fs.readFileSync(CAPTURE, 'utf8');
  check('upstream received Authorization intact', cap.includes(FAKE_AUTH));
  check('upstream received body intact', cap.includes('SECRET-PROMPT'));

  const log = fs.readFileSync(LOG, 'utf8');
  check('proxy log has no Authorization value', !log.includes('FAKE-SELFTEST-SECRET'));
  check('proxy log has no body content', !log.includes('SECRET-PROMPT') && !log.includes('selftest'));
  check('proxy log has no query string', !log.includes('debug=1'));
  check('proxy log counted exactly 1 submit POST',
    log.split('\n').filter((l) => l.includes('"method":"POST"') && l.includes('/contents/generations/tasks')).length === 1);
  check('proxy log has RESTART mark', log.includes('"mark":"RESTART"'));

  fake.kill(); proxy.kill();
  await sleep(200);
  // 5xx 透传单测
  const fake2 = spawn('node', ['tool/parity/fake_upstream.js'], {
    env: { ...process.env, P0_FAKE_MODE: 'fail', P0_FAKE_CAPTURE: CAPTURE }, stdio: 'inherit' });
  const proxy2 = spawn('node', ['tool/parity/sanitizing_proxy.js'], {
    env: { ...process.env, P0_PORT: '8791', P0_UPSTREAM: 'http://127.0.0.1:8792', P0_LOG: LOG }, stdio: 'inherit' });
  await sleep(500);
  const fail500 = await req('POST', '/api/v3/contents/generations/tasks', FAKE_BODY, { authorization: FAKE_AUTH });
  check('5xx propagated', fail500.status === 500);
  fake2.kill(); proxy2.kill();
  if (failed === 0) {
    // 机器门：sentinel 内容 = 通过自测的代理文件哈希。真实调用前必须复核。
    fs.mkdirSync(path.dirname(SENTINEL), { recursive: true });
    const hash = crypto.createHash('sha256')
      .update(fs.readFileSync('tool/parity/sanitizing_proxy.js')).digest('hex');
    fs.writeFileSync(SENTINEL, hash + '\n');
    console.log(`SENTINEL ${SENTINEL}`);
  } else {
    fs.rmSync(SENTINEL, { force: true });
  }
  process.exit(failed === 0 ? 0 : 1);
})();
```

- [ ] **Step 2: 运行自测（机器门）**

```bash
node tool/parity/proxy_selftest.js \
  && shasum -a 256 tool/parity/sanitizing_proxy.js | awk '{print $1}' \
  && cat "$HOME/Documents/dramaflow-p0-preflight/proxy-selftest.ok"
```

预期：全部 `PASS` + `SENTINEL ...` 行，且最后两行输出的哈希**一致**（sentinel 记录的就是通过自测的代理文件哈希）。任何 `FAIL` → 自测会删除 sentinel、以非零码退出，`&&` 链中断——**sentinel 不存在或哈希不匹配时，Task 5 的真实调用被门禁**（Task 5 Step 5 会复核）。

- [ ] **Step 3: 清理自测残留 + 提交**

```bash
rm -f /tmp/p0-selftest-proxy.jsonl /tmp/p0-selftest-capture.jsonl
git add tool/parity/proxy_selftest.js
git commit -m "test(preflight): gate proxy hygiene behind fake-upstream selftest"
```

---

### Task 3: 失败与重试演练线束（零真实调用，两用例）

**Files:**
- Create: `app/test/preflight/p0_failure_drill_test.dart`

**Interfaces:**
- Consumes: `Engine.boot`（`app/lib/src/engine/engine.dart:395`）、`InMemoryCredentialStore` + `providerCredentialRef`（`credentials.dart`）、`engine.batchGenerateVideos`、`engine.retryJob`（`engine.dart:986`）、假上游（`fail` 与 `acceptThenFail` 两模式）。种子模式取自 `app/test/engine/video_track_test.dart:95-102`。
- Produces: env 守卫（`P0_DRILL_CASE=uncertain|acceptedFail`）的两用例演练。**设计依据（已核实源码）**：提交异常时 `video_track.dart:812` 将候选置 `submissionState='uncertain'`（供应商可能已收到但客户端没拿到 ID 的危险态），恢复/重试路径区别对待 `uncertain` 与 `accepted`（`video_track.dart:1103-1109`）。演练必须走 `retryJob` 验证该保护，**禁止**用再次 `batchGenerateVideos` 冒充重试（那会绕过防重复提交机制）：
  - 用例 A（uncertain）：提交遇 500 → 任务 failed、候选 `uncertain`；`retryJob` 必须**拒绝重提**；假上游 POST 总数保持 1。
  - 用例 B（acceptedFail）：提交被接受（拿到 ID）→ 轮询终态 failed；`retryJob` **允许**重试并发出第二次假 POST（总数 2）。
  - 若实际语义与上述预期不符：按修复纪律记录为 P0 发现并上报审核方，不得强改断言迁就现状。

- [ ] **Step 1: 写演练线束（两用例）**

创建 `app/test/preflight/p0_failure_drill_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _model = 'doubao-seedance-2-0-mini-260615';

Future<({Engine engine, int projectId, int sbId})> _bootDrill(
    String sub) async {
  final workRoot = p.join(
      Platform.environment['HOME']!, 'Documents', 'dramaflow-p0-preflight');
  final dataDir = p.join(workRoot, 'drill-$sub');
  if (Directory(dataDir).existsSync()) {
    Directory(dataDir).deleteSync(recursive: true);
  }
  final credentials = InMemoryCredentialStore()
    ..seed(providerCredentialRef('volcengine'), 'drill-dummy-key');
  final engine = await Engine.boot(
    dataDir: dataDir,
    isMobile: false,
    credentialStore: credentials,
  );
  final db = engine.db;
  // baseUrl → 假上游（loopback），保留 inputValues 其他键。
  final row = db
      .select("SELECT inputValues FROM o_vendorConfig WHERE id='volcengine'")
      .first;
  final iv = (jsonDecode((row['inputValues'] as String?) ?? '{}') as Map)
      .cast<String, dynamic>();
  iv['baseUrl'] = 'http://127.0.0.1:8792/api/v3';
  db.execute("UPDATE o_vendorConfig SET inputValues=? WHERE id='volcengine'",
      [jsonEncode(iv)]);
  db.execute("INSERT OR REPLACE INTO o_setting (key,value) VALUES "
      "('binding.shot_video','volcengine:$_model')");
  engine.saveVisualManual(
      name: 'P0视觉', pack: 'p0_pack', data: const {'art_storyboard_video': '预检'});
  final projectId = engine.addProject(
      projectType: 'novel', name: 'P0演练-$sub', artStyle: 'p0_pack');
  engine.editProject(projectId,
      videoModel: 'volcengine:$_model', videoRatio: '9:16');
  final scriptId =
      engine.addScript(projectId: projectId, name: 'P0', content: '预检');
  final sbId = engine.addStoryboard(
      projectId: projectId, scriptId: scriptId, prompt: '硬币在桌面缓慢旋转');
  final frame = File(engine.mediaAbsPath('p0/frame.png'))
    ..parent.createSync(recursive: true);
  File('/Users/luke/Documents/aivideo/azt-gpt-image2-test.png')
      .copySync(frame.path);
  db.execute(
      "UPDATE o_storyboard SET filePath='p0/frame.png' WHERE id=?", [sbId]);
  return (engine: engine, projectId: projectId, sbId: sbId);
}

Future<String> _waitTask(Engine engine, int taskId) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final state = engine.db.select(
        'SELECT state FROM o_tasks WHERE id=?', [taskId]).first['state'] as String;
    if (state == 'failed' || state == 'success') return state;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('演练任务 60s 未达终态');
}

void main() {
  test('p0 drill A: uncertain submission must not be resubmitted', () async {
    if (Platform.environment['P0_DRILL_CASE'] != 'uncertain') return;
    final ctx = await _bootDrill('uncertain');
    addTearDown(ctx.engine.dispose);
    final db = ctx.engine.db;

    final taskId = ctx.engine.batchGenerateVideos(ctx.projectId, [ctx.sbId]);
    expect(await _waitTask(ctx.engine, taskId), 'failed',
        reason: '假上游 500 必须以 failed 落库');
    final reason = db
        .select('SELECT reason FROM o_tasks WHERE id=?', [taskId])
        .first['reason'] as String?;
    expect(reason, isNotEmpty, reason: '失败原因必须可见（任务中心语义）');
    final sub = db
        .select('SELECT submissionState FROM o_video ORDER BY id DESC')
        .first['submissionState'];
    expect(sub, 'uncertain',
        reason: '提交异常必须落 uncertain（video_track.dart:812 语义）');

    // 核心断言：retryJob 面对 uncertain 不得重新提交。
    final candidatesBefore =
        db.select('SELECT count(*) c FROM o_video').first['c'] as int;
    Object? refusal;
    try {
      await ctx.engine.retryJob(taskId);
    } catch (e) {
      refusal = e;
    }
    final candidatesAfter =
        db.select('SELECT count(*) c FROM o_video').first['c'] as int;
    expect(candidatesAfter, candidatesBefore,
        reason: 'uncertain 重试不得产生新候选（防重复付费保护）');
    stdout.writeln(
        'P0_DRILL_UNCERTAIN_OK refusal=${refusal?.runtimeType ?? "silent-no-resubmit"}');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('p0 drill B: accepted terminal failure retries with a new submission',
      () async {
    if (Platform.environment['P0_DRILL_CASE'] != 'acceptedFail') return;
    final ctx = await _bootDrill('accepted-fail');
    addTearDown(ctx.engine.dispose);
    final db = ctx.engine.db;

    final taskId = ctx.engine.batchGenerateVideos(ctx.projectId, [ctx.sbId]);
    expect(await _waitTask(ctx.engine, taskId), 'failed',
        reason: '轮询终态 failed 必须以 failed 落库');
    final row = db
        .select('SELECT submissionState, upstreamTaskId FROM o_video '
            'ORDER BY id DESC')
        .first;
    expect(row['submissionState'], 'accepted',
        reason: '假上游已返回任务 ID，提交态必须是 accepted');
    expect((row['upstreamTaskId'] as String?) ?? '', isNotEmpty);

    // 核心断言：accepted+终态失败允许 retryJob，产生第二次（假）提交。
    final retryTaskId = await ctx.engine.retryJob(taskId);
    expect(await _waitTask(ctx.engine, retryTaskId), 'failed',
        reason: '假上游仍确定性失败，但重试链路必须走通');
    final candidates =
        db.select('SELECT count(*) c FROM o_video').first['c'];
    stdout.writeln('P0_DRILL_ACCEPTED_FAIL_OK candidates=$candidates');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
```

- [ ] **Step 2: 验证默认套件零副作用**

```bash
cd app
flutter test test/preflight/p0_failure_drill_test.dart --reporter expanded
```

预期：两个用例均 PASS（守卫直接返回），无网络、无目录创建。

- [ ] **Step 3: 运行用例 A（uncertain，POST 总数必须保持 1）**

```bash
rm -f /tmp/p0-fake-capture-a.jsonl
P0_FAKE_MODE=fail P0_FAKE_CAPTURE=/tmp/p0-fake-capture-a.jsonl node tool/parity/fake_upstream.js &
FAKE_PID=$!
sleep 1
(cd app && P0_DRILL_CASE=uncertain flutter test test/preflight/p0_failure_drill_test.dart --reporter expanded)
kill $FAKE_PID
jq -s '[.[]|select(.method=="POST")]|length' /tmp/p0-fake-capture-a.jsonl
```

预期：测试 PASS 且输出 `P0_DRILL_UNCERTAIN_OK`；最后一行 POST 计数 == **1**（`retryJob` 拒绝了 uncertain 重提——这是防重复付费保护的直接证据）。

- [ ] **Step 4: 运行用例 B（acceptedFail，POST 总数必须为 2）**

```bash
rm -f /tmp/p0-fake-capture-b.jsonl
P0_FAKE_MODE=acceptThenFail P0_FAKE_CAPTURE=/tmp/p0-fake-capture-b.jsonl node tool/parity/fake_upstream.js &
FAKE_PID=$!
sleep 1
(cd app && P0_DRILL_CASE=acceptedFail flutter test test/preflight/p0_failure_drill_test.dart --reporter expanded)
kill $FAKE_PID
jq -s '[.[]|select(.method=="POST")]|length' /tmp/p0-fake-capture-b.jsonl
```

预期：测试 PASS 且输出 `P0_DRILL_ACCEPTED_FAIL_OK`；POST 计数 == **2**（原提交 + retryJob 允许的重试）。任一用例与预期不符：按修复纪律**只记录**（P0 发现，上报审核方），不在本分支修产品代码、不强改断言。

- [ ] **Step 5: 提交**

```bash
git add app/test/preflight/p0_failure_drill_test.dart
git commit -m "test(preflight): drill uncertain refusal and accepted retry"
```

---

### Task 4: azt 文本/图片服务冒烟（无单次账单，耗订阅额度）

**Files:**
- Modify: `docs/parity/p0-provider-preflight.md`（Task 6 创建骨架后回填；本任务先落临时记录 `/tmp/p0-azt-smoke.txt`）

- [ ] **Step 1: 文本冒烟**

```bash
curl -sS -m 60 http://127.0.0.1:8787/v1/chat/completions \
  -H 'Content-Type: application/json' -H 'Authorization: Bearer local' \
  -d '{"model":"gpt-5.5","messages":[{"role":"user","content":"只回复 OK"}],"max_completion_tokens":16}' \
  | tee /tmp/p0-azt-smoke.txt | jq -r '.choices[0].message.content'
```

预期：输出含 `OK`。若 azt 未启动：`azt serve` 后重试（`aivideo/AGENTS.md` 启动手册）。

- [ ] **Step 2: 图片冒烟（一次，低质量档）**

```bash
time curl -sS -m 960 http://127.0.0.1:8787/v1/images/generations \
  -H 'Content-Type: application/json' -H 'Authorization: Bearer local' \
  -d '{"model":"gpt-image-2","prompt":"A plain gray square, no text.","size":"1024x1024","quality":"low","response_format":"b64_json"}' \
  | jq -r '.data[0].b64_json | length' | tee -a /tmp/p0-azt-smoke.txt
```

预期：输出一个大于 10000 的长度值（返回了真实图片 base64），耗时数分钟属正常（AGENTS.md 记载 195-342s）。记录耗时进临时记录。

---

### Task 5: 真实恰好一次预检（唯一付费步骤）

**Files:**
- Create: `app/test/preflight/p0_live_preflight_test.dart`
- Create: `tool/parity/p0_assert.js`

**Interfaces:**
- Consumes: Task 2 绿灯（前置门）、代理（真实上游模式）、旧 ToonFlow 运行库（只读取 key 入内存）。
- Produces: 两阶段线束（`P0_PHASE=submit`：提交→`upstreamTaskId` 落库→`exit(9)` 硬杀；`P0_PHASE=resume`：`Engine.boot` 冷启恢复→终态）；`p0_assert.js` 输出四项断言结果。

- [ ] **Step 1: 探测旧库 key 字段名（只输出键名）**

```bash
sqlite3 "$HOME/Library/Application Support/toonflow/data/db2.sqlite" \
  "SELECT je.key FROM o_vendorConfig, json_each(o_vendorConfig.inputValues) je WHERE o_vendorConfig.id='volcengine';"
```

预期：键名列表中有一个 key 字段（如 `apiKey`）。记下字段名，下一步经 `P0_KEY_FIELD` 传入；**禁止查询该字段的值**。若旧库无 volcengine 行或无 key 字段：按 spec §7 退化路径——用户在正式 App 设置页填一次后，由审核方另定注入方式；本任务暂停上报。

- [ ] **Step 2: 写两阶段线束**

创建 `app/test/preflight/p0_live_preflight_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sq;

const _model = 'doubao-seedance-2-0-mini-260615';

void main() {
  test('p0 live preflight', () async {
    final phase = Platform.environment['P0_PHASE'];
    if (Platform.environment['P0_LIVE'] != '1' || phase == null) {
      return; // 默认套件零副作用
    }
    final home = Platform.environment['HOME']!;
    final dataDir =
        p.join(home, 'Documents', 'dramaflow-p0-preflight', 'live-data');

    // key：旧库只读 → 进程内存。绝不打印、绝不写盘。
    final keyField = Platform.environment['P0_KEY_FIELD'] ?? 'apiKey';
    final tf = sq.sqlite3.open(
        p.join(home, 'Library/Application Support/toonflow/data/db2.sqlite'),
        mode: sq.OpenMode.readOnly);
    final keyRow = tf.select(
        "SELECT json_extract(inputValues, '\$.' || ?) AS k "
        "FROM o_vendorConfig WHERE id='volcengine'",
        [keyField]);
    final key = keyRow.isEmpty ? null : keyRow.first['k'] as String?;
    tf.dispose();
    if (key == null || key.isEmpty) {
      fail('旧库未取到 key（字段 $keyField）：走用户填入一次的退化路径');
    }
    final credentials = InMemoryCredentialStore()
      ..seed(providerCredentialRef('volcengine'), key);
    final engine = await Engine.boot(
      dataDir: dataDir,
      isMobile: false,
      credentialStore: credentials,
    );
    final db = engine.db;

    if (phase == 'submit') {
      final row = db
          .select(
              "SELECT inputValues FROM o_vendorConfig WHERE id='volcengine'")
          .first;
      final iv = (jsonDecode((row['inputValues'] as String?) ?? '{}') as Map)
          .cast<String, dynamic>();
      iv['baseUrl'] = 'http://127.0.0.1:8791/api/v3';
      db.execute(
          "UPDATE o_vendorConfig SET inputValues=? WHERE id='volcengine'",
          [jsonEncode(iv)]);
      db.execute("INSERT OR REPLACE INTO o_setting (key,value) VALUES "
          "('binding.shot_video','volcengine:$_model')");
      // 最低成本档：声明能力里的最短时长 + 最低分辨率。
      final modelsRaw = db
          .select("SELECT models FROM o_vendorConfig WHERE id='volcengine'")
          .first['models'] as String?;
      final models = (jsonDecode(modelsRaw ?? '[]') as List).cast<Map>();
      final mini = models.firstWhere((m) => m['modelId'] == _model);
      final caps = ((mini['capabilities'] as Map?)?['video'] as Map?) ?? {};
      final durations =
          ((caps['durations'] as List?) ?? [5]).cast<num>().toList()..sort();
      final resolutions =
          ((caps['resolutions'] as List?) ?? ['720p']).cast<String>();
      final resolution =
          resolutions.contains('480p') ? '480p' : resolutions.first;
      db.execute("INSERT OR REPLACE INTO o_setting (key,value) VALUES "
          "('videoResolution','$resolution')");
      db.execute("INSERT OR REPLACE INTO o_setting (key,value) VALUES "
          "('videoDuration','${durations.first}')");

      engine.saveVisualManual(
          name: 'P0视觉',
          pack: 'p0_pack',
          data: const {'art_storyboard_video': '预检'});
      final projectId = engine.addProject(
          projectType: 'novel', name: 'P0真实预检', artStyle: 'p0_pack');
      engine.editProject(projectId,
          videoModel: 'volcengine:$_model', videoRatio: '9:16');
      final scriptId =
          engine.addScript(projectId: projectId, name: 'P0', content: '预检');
      final sbId = engine.addStoryboard(
          projectId: projectId, scriptId: scriptId, prompt: '一枚硬币在木桌上缓慢旋转，特写，柔和光线');
      final frame = File(engine.mediaAbsPath('p0/frame.png'))
        ..parent.createSync(recursive: true);
      File('/Users/luke/Documents/aivideo/azt-gpt-image2-test.png')
          .copySync(frame.path);
      db.execute(
          "UPDATE o_storyboard SET filePath='p0/frame.png' WHERE id=?", [sbId]);

      final taskId = engine.batchGenerateVideos(projectId, [sbId]);
      stdout.writeln('P0_MARK submitted taskId=$taskId '
          'resolution=$resolution duration=${durations.first}');
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (DateTime.now().isBefore(deadline)) {
        final rows = db.select(
            "SELECT id, upstreamTaskId FROM o_video "
            "WHERE submissionState='accepted' AND upstreamTaskId IS NOT NULL");
        if (rows.isNotEmpty) {
          stdout.writeln(
              'P0_MARK upstream_persisted upstreamTaskId=${rows.first['upstreamTaskId']}');
          exit(9); // 硬杀：不给引擎任何收尾机会（模拟强制退出）
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      fail('180s 内 upstreamTaskId 未持久化');
    }

    if (phase == 'resume') {
      // Engine.boot 已执行 recoverOnColdStart + queue.start：只等终态。
      final deadline = DateTime.now().add(const Duration(minutes: 20));
      while (DateTime.now().isBefore(deadline)) {
        final rows = db.select(
            'SELECT upstreamState, filePath FROM o_video '
            'WHERE upstreamTaskId IS NOT NULL');
        if (rows.isNotEmpty) {
          final state = rows.first['upstreamState'] as String?;
          final filePath = rows.first['filePath'] as String?;
          if (state == 'succeeded' && filePath != null && filePath.isNotEmpty) {
            stdout.writeln('P0_MARK done filePath=$filePath');
            engine.dispose();
            return;
          }
          if (state == 'failed' || state == 'canceled') {
            fail('上游终态异常: $state');
          }
        }
        await Future<void>.delayed(const Duration(seconds: 5));
      }
      fail('20 分钟未达终态（记录后人工检查上游任务状态，勿重复提交）');
    }
  }, timeout: const Timeout(Duration(minutes: 25)));
}
```

- [ ] **Step 3: 写断言脚本**

创建 `tool/parity/p0_assert.js`：

```js
#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const LOG = process.env.P0_LOG || '/tmp/p0-live-proxy.jsonl';
const DATA = path.join(os.homedir(), 'Documents/dramaflow-p0-preflight/live-data');
const lines = fs.readFileSync(LOG, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
const restartIdx = lines.findIndex((l) => l.mark === 'RESTART');
const posts = lines.filter((l) => l.method === 'POST' && l.path.endsWith('/contents/generations/tasks'));
const afterRestart = restartIdx >= 0 ? lines.slice(restartIdx + 1).filter((l) => l.method) : [];
const sql = (q) => JSON.parse(execFileSync('sqlite3', ['-json', path.join(DATA, 'dramaflow.sqlite'), q]).toString() || '[]');
const upstreamIds = sql("SELECT count(DISTINCT upstreamTaskId) c FROM o_video WHERE upstreamTaskId IS NOT NULL")[0].c;
const mediaDir = path.join(DATA, 'media');
const videos = execFileSync('find', [mediaDir, '-type', 'f', '-name', '*.mp4']).toString().trim().split('\n').filter(Boolean);

let failed = 0;
const check = (name, ok, detail) => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ` (${detail})` : ''}`); if (!ok) failed += 1; };
check('真实 POST 提交次数 == 1', posts.length === 1, `posts=${posts.length}`);
check('upstreamTaskId 数量 == 1', upstreamIds === 1, `distinct=${upstreamIds}`);
check('重启后只有轮询/下载类请求（无 POST）', restartIdx >= 0 && afterRestart.every((l) => l.method !== 'POST'), `afterRestart=${afterRestart.length}`);
check('本地生成候选数量 == 1', videos.length === 1, `videos=${videos.length}`);
process.exit(failed === 0 ? 0 : 1);
```

- [ ] **Step 4: 默认套件零副作用验证 + 提交线束**

```bash
cd app && flutter test test/preflight/p0_live_preflight_test.dart --reporter expanded && cd ..
git add app/test/preflight/p0_live_preflight_test.dart tool/parity/p0_assert.js
git commit -m "test(preflight): add exactly-once live harness and assertions"
```

预期：默认（无 env）PASS 且零网络零目录。

- [ ] **Step 5: 执行真实预检（唯一付费步骤，由 Claude 主会话亲自执行）**

强杀阶段的退出码非零是预期，**不允许用 `|| true` 吞错**——判定改由三道证据门承担，三门全过才允许写 RESTART 标记并进入 resume：

```bash
WORK="$HOME/Documents/dramaflow-p0-preflight"
# 门 0：自测 sentinel 复核（代理文件被改动或自测未过 → 禁止真实调用）
[ "$(shasum -a 256 tool/parity/sanitizing_proxy.js | awk '{print $1}')" = "$(cat "$WORK/proxy-selftest.ok" 2>/dev/null)" ] \
  || { echo 'GATE0 FAIL: sentinel 缺失或代理文件已改动，先重跑 Task 2'; exit 1; }
rm -f /tmp/p0-live-proxy.jsonl /tmp/p0-submit-out.txt
rm -rf "$WORK/live-data"
P0_PORT=8791 P0_UPSTREAM=https://ark.cn-beijing.volces.com P0_LOG=/tmp/p0-live-proxy.jsonl \
  node tool/parity/sanitizing_proxy.js &
PROXY_PID=$!
sleep 1
( cd app && P0_LIVE=1 P0_PHASE=submit P0_KEY_FIELD=<Step1记下的字段名> \
    flutter test test/preflight/p0_live_preflight_test.dart --reporter expanded 2>&1 \
    | tee /tmp/p0-submit-out.txt )
# 门 1：达到强杀点（编译失败/缺 key/模型错误都到不了这里）
grep -q 'P0_MARK upstream_persisted' /tmp/p0-submit-out.txt \
  || { kill $PROXY_PID; echo 'GATE1 FAIL: 未达强杀点，读 /tmp/p0-submit-out.txt 诊断'; exit 1; }
# 门 2：库中恰有一个 accepted + upstreamTaskId 候选
[ "$(sqlite3 "$WORK/live-data/dramaflow.sqlite" \
    "SELECT count(*) FROM o_video WHERE submissionState='accepted' AND trim(coalesce(upstreamTaskId,''))<>'';")" = "1" ] \
  || { kill $PROXY_PID; echo 'GATE2 FAIL: accepted 候选数异常'; exit 1; }
# 门 3：代理恰记录一次成功提交 POST
[ "$(jq -s '[.[]|select(.method=="POST" and ((.path//"")|endswith("/contents/generations/tasks")) and .status==200)]|length' /tmp/p0-live-proxy.jsonl)" = "1" ] \
  || { kill $PROXY_PID; echo 'GATE3 FAIL: 成功提交 POST 计数异常'; exit 1; }
curl -sS -X POST http://127.0.0.1:8791/__mark -H 'Content-Type: application/json' -d '{"mark":"RESTART"}'
( cd app && P0_LIVE=1 P0_PHASE=resume P0_KEY_FIELD=<同上> \
    flutter test test/preflight/p0_live_preflight_test.dart --reporter expanded ) \
  || { kill $PROXY_PID; echo 'RESUME FAIL: 恢复阶段必须以退出码 0 结束'; exit 1; }
kill $PROXY_PID
```

预期：GATE0–3 依次通过；submit 输出 `P0_MARK upstream_persisted ...`；resume 输出 `P0_MARK done filePath=...` 且退出码 0。任何门失败：证据保全（`/tmp/p0-submit-out.txt` + 代理日志 + live-data 只读封存），按修复纪律记录诊断，**不得重试真实提交**，上报审核方。

- [ ] **Step 6: 跑四项断言**

```bash
node tool/parity/p0_assert.js; echo "exit=$?"
```

预期：四行 `PASS`，`exit=0`。任何 FAIL：证据保全（代理日志 + live-data 只读封存），诊断结论进证据文档，按任务卡纪律处理。

---

### Task 6: 证据文档与 P0 验收门

**Files:**
- Create: `docs/parity/p0-provider-preflight.md`

- [ ] **Step 1: 写证据文档**

`docs/parity/p0-provider-preflight.md` 固定章节（填入真实值；**不含 key、不含完整 prompt**）：

```markdown
# P0 供应商预检记录

## 结论
（一句话：恰好一次真实生成是否达成；四项断言是否全 PASS）

## 真实付费场景
- 提交时间 / upstreamTaskId / 分辨率与时长档 / 各阶段耗时
- 强杀点：P0_MARK upstream_persisted 输出行（原样粘贴）
- 恢复结果：P0_MARK done 输出行（原样粘贴）
- p0_assert.js 完整输出（原样粘贴）

## 失败与重试演练（零真实调用）
- 用例 A（uncertain）：POST 计数（必须 1）/ retryJob 拒绝形态 / P0_DRILL_UNCERTAIN_OK 输出行
- 用例 B（acceptedFail）：POST 计数（必须 2）/ 重试任务终态 / P0_DRILL_ACCEPTED_FAIL_OK 输出行
- o_tasks.reason 样例（截断 40 字符内）

## azt 服务冒烟
- 文本耗时与返回；图片耗时与 base64 长度（/tmp/p0-azt-smoke.txt 摘录）

## 发现的缺陷与处置
（逐条：现象 → 诊断 → 记录去向[总清单条目/任务卡]；P0 期间零产品代码改动）

## 凭证处置声明
key 仅在线束进程内存存在，未持久化；Keychain 迁移按计划偏差声明推迟至终验收准备。

## 覆盖范围声明
本预检验证的是引擎/供应商协议路径（含冷启恢复），**不覆盖**：Keychain/设置页/打包 App 凭证路径、GUI 与 macOS App 生命周期——均由终验收 12 步承担。
```

- [ ] **Step 2: 防泄漏自检**

```bash
grep -icE 'sk-|Bearer [A-Za-z0-9]{8,}|"apiKey"\s*:\s*"[^<]' docs/parity/p0-provider-preflight.md || echo CLEAN
```

预期：`CLEAN`。

- [ ] **Step 3: 提交、合入、推送**

```bash
git add docs/parity/p0-provider-preflight.md
git commit -m "docs(parity): record P0 provider preflight evidence"
```

审核方逐行审阅 `p0-preflight` 全部提交后：

```bash
cd /Users/luke/Documents/aivideo/dramaflow
git checkout develop && git merge --no-ff p0-preflight -m "merge: P0 provider preflight"
git push origin develop
git worktree remove ../dramaflow-p0 && git branch -d p0-preflight
```

- [ ] **Step 4: P0 验收门（全部满足才算关闭）**

- Task 2 自测 exit=0（真实调用前置门已过）。
- 四项断言全 PASS（恰好一次 / 单 upstreamTaskId / 重启仅轮询 / 单候选）。
- 失败演练零真实外联且失败原因落库可重试。
- 证据文档防泄漏自检 CLEAN，已合入 develop 并推送。
- 预检工作目录 `~/Documents/dramaflow-p0-preflight` 保留至终验收（内含零秘密），供追溯。

---

## 执行方式（评审定案）

- 混合子代理驱动：Task 1–3 的脚本/假上游/线束与 Task 6 文档可逐任务派子代理，**每个任务过审核门（逐行 diff 审阅 + 命令复跑）后才开下一个**。
- **Task 5（唯一一次真实付费调用）由 Claude 主会话亲自执行与审核，绝不交给后台子代理**；Task 4 的 azt 冒烟同样在主会话执行（消耗订阅额度，需实时观察）。
- 所有子代理只在 `p0-preflight` worktree 内工作，遵守本计划 Global Constraints 的文件范围与 key 卫生纪律。
