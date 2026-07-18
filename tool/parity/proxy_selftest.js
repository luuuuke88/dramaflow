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
// 开场即删旧 sentinel：本次自测异常退出时不会留下过期绿灯。
for (const f of [LOG, CAPTURE, SENTINEL]) fs.rmSync(f, { force: true });

function probe(port) {
  return new Promise((resolve) => {
    const r = http.request(
      { host: '127.0.0.1', port, path: '/__health', method: 'GET', timeout: 500 },
      (res) => { const bs = []; res.on('data', (c) => bs.push(c)); res.on('end', () => resolve(Buffer.concat(bs).toString('utf8'))); });
    r.on('error', () => resolve(null));
    r.on('timeout', () => { r.destroy(); resolve(null); });
    r.end();
  });
}

function req(method, path, body, headers) {
  return new Promise((resolve, reject) => {
    const r = http.request({ host: '127.0.0.1', port: 8791, method, path, headers, timeout: 5000 }, (res) => {
      const bs = [];
      res.on('data', (c) => bs.push(c));
      res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(bs).toString('utf8') }));
      res.on('error', reject);
    });
    r.on('error', reject);
    r.on('timeout', () => { r.destroy(new Error(`req timeout ${method} ${path}`)); });
    if (body) r.write(body);
    r.end();
  });
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// kill 只是发信号：必须等 exit 事件确认进程退出、端口释放，
// 否则同端口重启会在慢机器上撞 EADDRINUSE。
function killAndWait(child) {
  return new Promise((resolve) => {
    if (child.exitCode !== null || child.signalCode !== null) return resolve();
    child.once('exit', () => resolve());
    child.kill();
  });
}
let failed = 0;
const check = (name, ok) => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`); if (!ok) failed += 1; };

// 全程登记 spawn 的子进程，无论中途哪一步抛错都在 finally 里收尸——
// 否则泄漏的子进程占着 8791/8792，下一次自测在端口预检处失败，把真正的
// 报错掩盖成"端口被占用"。
const children = [];
const track = (child) => { children.push(child); return child; };

(async () => {
  // 端口占用预检：任何进程已在 8791/8792 监听 → 立即中止，避免请求打到外来进程。
  if ((await probe(8791)) !== null || (await probe(8792)) !== null) {
    console.error('FATAL: 8791/8792 已被占用，先清理旧进程再自测');
    process.exit(1);
  }
  const fake = track(spawn('node', ['tool/parity/fake_upstream.js'], {
    env: { ...process.env, P0_FAKE_MODE: 'ok', P0_FAKE_CAPTURE: CAPTURE }, stdio: 'inherit' }));
  const proxy = track(spawn('node', ['tool/parity/sanitizing_proxy.js'], {
    env: { ...process.env, P0_PORT: '8791', P0_UPSTREAM: 'http://127.0.0.1:8792', P0_LOG: LOG }, stdio: 'inherit' }));
  await sleep(500);
  const proxyHealth = await probe(8791);
  const fakeHealth = await probe(8792);
  check('proxy port owned by spawned pid',
    !!proxyHealth && JSON.parse(proxyHealth).pid === proxy.pid);
  check('fake upstream port owned by spawned pid',
    !!fakeHealth && JSON.parse(fakeHealth).pid === fake.pid);

  const post = await req('POST', '/api/v3/contents/generations/tasks?debug=1', FAKE_BODY,
    { 'content-type': 'application/json', authorization: FAKE_AUTH });
  check('POST 200 with task id', post.status === 200 && JSON.parse(post.body).id === 'fake-task-1');
  await req('POST', '/__mark', JSON.stringify({ mark: 'RESTART' }), { 'content-type': 'application/json' });
  const get = await req('GET', '/api/v3/contents/generations/tasks/fake-task-1', null, { authorization: FAKE_AUTH });
  check('GET poll succeeded passthrough', get.status === 200 && JSON.parse(get.body).status === 'succeeded');
  // 控制端点带 query 也必须本地应答，不得漏到上游（sanitizing_proxy pathOnly 修复的回归锁）。
  const healthQ = await req('GET', '/__health?x=1', null, {});
  check('control route with query answered locally',
    healthQ.status === 200 && JSON.parse(healthQ.body).pid === proxy.pid);

  const cap = fs.readFileSync(CAPTURE, 'utf8');
  check('upstream received Authorization intact', cap.includes(FAKE_AUTH));
  check('upstream received body intact', cap.includes('SECRET-PROMPT'));
  // 查询串必须原样到达上游——若代理误用 pathOnly 转发，这里会先红。
  check('upstream received query string intact', cap.includes('debug=1'));

  const logLines = fs.readFileSync(LOG, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  // 结构性断言：日志行的键集合只允许 {ts,mark} 或 {ts,method,path,status,ms}。
  // 单纯 grep 秘密串是恒真检查（logLine 根本收不到 headers/body/query）；
  // 键集合校验才能拦住未来某次调试把 headers 塞进 logLine 的改动。
  const allowedKeySets = [['mark', 'ts'], ['method', 'ms', 'path', 'status', 'ts']];
  check('proxy log lines carry only whitelisted keys',
    logLines.every((l) => {
      const keys = Object.keys(l).sort().join(',');
      return allowedKeySets.some((s) => s.join(',') === keys);
    }));
  const log = logLines.map((l) => JSON.stringify(l)).join('\n');
  check('proxy log has no Authorization value', !log.includes('FAKE-SELFTEST-SECRET'));
  check('proxy log has no body content', !log.includes('SECRET-PROMPT') && !log.includes('selftest'));
  check('proxy log has no query string', !log.includes('debug=1'));
  check('proxy log counted exactly 1 submit POST',
    logLines.filter((l) => l.method === 'POST' && String(l.path).includes('/contents/generations/tasks')).length === 1);
  check('proxy log has RESTART mark', log.includes('"mark":"RESTART"'));

  await Promise.all([killAndWait(fake), killAndWait(proxy)]);
  // 5xx 透传单测
  const fake2 = track(spawn('node', ['tool/parity/fake_upstream.js'], {
    env: { ...process.env, P0_FAKE_MODE: 'fail', P0_FAKE_CAPTURE: CAPTURE }, stdio: 'inherit' }));
  const proxy2 = track(spawn('node', ['tool/parity/sanitizing_proxy.js'], {
    env: { ...process.env, P0_PORT: '8791', P0_UPSTREAM: 'http://127.0.0.1:8792', P0_LOG: LOG }, stdio: 'inherit' }));
  await sleep(500);
  const proxyHealth2 = await probe(8791);
  check('phase-2 proxy port owned by spawned pid',
    !!proxyHealth2 && JSON.parse(proxyHealth2).pid === proxy2.pid);
  const fail500 = await req('POST', '/api/v3/contents/generations/tasks', FAKE_BODY, { authorization: FAKE_AUTH });
  check('5xx propagated', fail500.status === 500);
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
  process.exitCode = failed === 0 ? 0 : 1;
})().catch((err) => {
  console.error('SELFTEST ERROR:', err);
  process.exitCode = 1;
}).finally(async () => {
  await Promise.all(children.map(killAndWait));
});
