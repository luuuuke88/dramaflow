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
