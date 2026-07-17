#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const OUT = path.join(__dirname, '..', '..', 'docs', 'parity', 'baseline-runtime-capabilities.json');
const URL_FIELDS = new Set(['baseUrl', 'chatBaseUrl', 'imageBaseUrl']);
const PLAIN_FIELDS = new Set(['imageQuality', 'imageSize', 'imageTimeoutMs']);
// 已只读核实（2026-07-18）：本机运行库模型条目实际字段为
// modelName/name/type/think/mode/audio/durationResolutionMap（无 modelId/capabilities）。
// 白名单取"实测字段 ∪ DramaFlow 风格字段"，防止丢模型 ID 与视频能力声明。
const MODEL_FIELDS = new Set(['modelName', 'name', 'type', 'think', 'mode', 'audio',
  'durationResolutionMap', 'modelId', 'kind', 'enabled', 'capabilities', 'promptTemplate', 'modelPrompt']);

function sanitizeUrl(value) {
  try {
    const u = new URL(String(value));
    return `${u.protocol}//${u.host}${u.pathname}`; // 去 userinfo / query / fragment
  } catch (_) {
    return '<non-url>';
  }
}

function exportInputValues(iv) {
  const out = { keys: Object.keys(iv).sort() };
  for (const [k, v] of Object.entries(iv)) {
    if (URL_FIELDS.has(k)) out[k] = sanitizeUrl(v);
    else if (PLAIN_FIELDS.has(k)) out[k] = v;
    // 其余键：只出现在 keys 里，绝不输出值
  }
  return out;
}

function exportModel(m) {
  const out = {};
  for (const k of Object.keys(m)) if (MODEL_FIELDS.has(k)) out[k] = m[k];
  return out;
}

function assertStructure(vendors) {
  const allowed = new Set(['keys', ...URL_FIELDS, ...PLAIN_FIELDS]);
  for (const v of vendors) {
    for (const k of Object.keys(v.inputValues)) {
      if (!allowed.has(k)) throw new Error(`whitelist violation: inputValues.${k}`);
    }
    for (const m of v.models) {
      for (const k of Object.keys(m)) {
        if (!MODEL_FIELDS.has(k)) throw new Error(`whitelist violation: models[].${k}`);
      }
    }
  }
}

function selftest() {
  const fixture = {
    ak: 'AKLT-FIXTURE-SECRET', sk: 'SK-FIXTURE-SECRET', apiKey: 'FIXTURE-KEY',
    credential: 'FIXTURE-CRED', token: 'FIXTURE-TOKEN',
    baseUrl: 'https://user:pass@ark.example.com/api/v3?token=FIXTURE-QS#frag',
    imageSize: '1024x1024',
  };
  const out = exportInputValues(fixture);
  const text = JSON.stringify(out);
  const leaks = ['AKLT-FIXTURE-SECRET', 'SK-FIXTURE-SECRET', 'FIXTURE-KEY',
    'FIXTURE-CRED', 'FIXTURE-TOKEN', 'FIXTURE-QS', 'user:pass'];
  for (const s of leaks) {
    if (text.includes(s)) { console.error(`SELFTEST FAIL leaked: ${s}`); process.exit(1); }
  }
  if (out.baseUrl !== 'https://ark.example.com/api/v3') {
    console.error(`SELFTEST FAIL url: ${out.baseUrl}`); process.exit(1);
  }
  if (!out.keys.includes('ak') || !out.keys.includes('sk')) {
    console.error('SELFTEST FAIL keys missing'); process.exit(1);
  }
  console.log('SELFTEST PASS');
}

if (process.argv.includes('--selftest')) { selftest(); process.exit(0); }

const DB = path.join(os.homedir(), 'Library/Application Support/toonflow/data/db2.sqlite');
const rows = JSON.parse(execFileSync('sqlite3', ['-json', DB,
  "SELECT id, enable, inputValues, models FROM o_vendorConfig ORDER BY id;"]).toString() || '[]');
const vendors = rows.map((r) => ({
  id: r.id,
  enable: r.enable,
  inputValues: exportInputValues(JSON.parse(r.inputValues || '{}')),
  models: (JSON.parse(r.models || '[]')).map(exportModel),
}));
assertStructure(vendors); // 违反白名单 → 抛错退出，不写文件
// 模型→提示词映射冻结：o_modelPrompt(vendorId, model, fileName, path)，只取安全字段，
// path 缩减为 basename（原值含用户主目录路径）。
const modelPrompts = JSON.parse(execFileSync('sqlite3', ['-json', DB,
  'SELECT vendorId, model, fileName, path FROM o_modelPrompt ORDER BY vendorId, model;']).toString() || '[]')
  .map((r) => ({
    vendorId: r.vendorId,
    model: r.model,
    fileName: r.fileName,
    pathBasename: r.path ? path.basename(r.path) : null,
  }));
const promptDir = path.join(os.homedir(), 'Library/Application Support/toonflow/data/modelPrompt');
const promptFiles = fs.existsSync(promptDir)
  ? execFileSync('find', [promptDir, '-type', 'f', '-name', '*.md']).toString().trim().split('\n')
      .filter(Boolean).map((p) => path.relative(promptDir, p)).sort()
  : [];
fs.writeFileSync(OUT, JSON.stringify(
  { generatedAt: new Date().toISOString(), vendors, modelPrompts, promptFiles }, null, 2) + '\n');
console.log(`vendors=${vendors.length} modelPrompts=${modelPrompts.length} promptFiles=${promptFiles.length}`);
