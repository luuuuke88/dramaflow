#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const APP = '/Users/luke/Documents/aivideo/Toonflow-app';
const REPO = path.join(__dirname, '..', '..');
const OUT = path.join(REPO, 'docs', 'parity', 'license-trace.json');

function sha(f) { return crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex'); }
function tree(root) {
  const out = {};
  if (!fs.existsSync(root)) return out;
  for (const f of execFileSync('find', [root, '-type', 'f']).toString().trim().split('\n').filter(Boolean)) {
    out[path.relative(root, f)] = sha(f);
  }
  return out;
}
function compare(name, dfRoot, tfRoot) {
  const df = tree(dfRoot);
  const tf = tree(tfRoot);
  const files = [...new Set([...Object.keys(df), ...Object.keys(tf)])].sort();
  const rows = files.map((f) => ({
    file: f,
    status: !(f in df) ? 'onlyInToonflow'
      : !(f in tf) ? 'onlyInDramaflow'
      : df[f] === tf[f] ? 'identical' : 'differs',
  }));
  const stats = rows.reduce((acc, r) => ((acc[r.status] = (acc[r.status] || 0) + 1), acc), {});
  return { name, toonflowRoot: tfRoot, stats, rows };
}

const unz = fs.mkdtempSync(path.join(os.tmpdir(), 'license-trace-'));
let result;
try {
  execFileSync('unzip', ['-q', path.join(REPO, 'app/assets/default_skills/toonflow_default_skills.zip'), '-d', path.join(unz, 'skills')]);
  execFileSync('unzip', ['-q', path.join(REPO, 'app/assets/default_prompts/toonflow_model_prompts.zip'), '-d', path.join(unz, 'prompts')]);
  result = {
    generatedAt: new Date().toISOString(),
    comparisons: [
      compare('default_skills', path.join(unz, 'skills', 'skills'), path.join(APP, 'data', 'skills')),
      compare('model_prompts', path.join(unz, 'prompts', 'model_prompts'), path.join(APP, 'data', 'modelPrompt')),
    ],
  };
} finally {
  fs.rmSync(unz, { recursive: true, force: true });
}
fs.writeFileSync(OUT, JSON.stringify(result, null, 2) + '\n');
for (const c of result.comparisons) console.log(c.name, JSON.stringify(c.stats));
