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
const candidateRows = sql('SELECT filePath FROM o_video');
const upstreamIds = sql("SELECT count(DISTINCT upstreamTaskId) c FROM o_video WHERE upstreamTaskId IS NOT NULL")[0].c;
const mediaDir = path.join(DATA, 'media');
const videos = execFileSync('find', [mediaDir, '-type', 'f', '-name', '*.mp4']).toString().trim().split('\n').filter(Boolean);
const candidateFile = candidateRows.length === 1 && candidateRows[0].filePath
  ? path.join(mediaDir, candidateRows[0].filePath) : null;

let failed = 0;
const check = (name, ok, detail) => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ` (${detail})` : ''}`); if (!ok) failed += 1; };
check('真实 POST 提交次数 == 1', posts.length === 1, `posts=${posts.length}`);
check('upstreamTaskId 数量 == 1', upstreamIds === 1, `distinct=${upstreamIds}`);
check('重启后只有轮询/下载类请求（无 POST）', restartIdx >= 0 && afterRestart.every((l) => l.method !== 'POST'), `afterRestart=${afterRestart.length}`);
check('o_video 候选行数 == 1（主断言）', candidateRows.length === 1, `rows=${candidateRows.length}`);
check('候选 filePath 文件真实存在', !!candidateFile && fs.existsSync(candidateFile), `file=${candidateFile}`);
check('媒体目录 MP4 数量 == 1（辅助断言）', videos.length === 1, `videos=${videos.length}`);
process.exit(failed === 0 ? 0 : 1);
