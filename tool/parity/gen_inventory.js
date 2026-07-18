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
for (const f of listFiles(WEB, 'src/components', '.vue')) add(`web.component:${f}`, `src/components/${f}`);
for (const f of listFiles(WEB, 'src/stores', '.ts')) add(`web.store:${f}`, `src/stores/${f}`);
for (const f of listFiles(WEB, 'src/lib', '.ts')) add(`web.featureLib:lib/${f}`, `src/lib/${f}`);
for (const f of listFiles(WEB, 'src/utils', '.ts')) add(`web.featureLib:utils/${f}`, `src/utils/${f}`);
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
