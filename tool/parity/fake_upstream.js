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
    if (req.method === 'GET' && req.url === '/__health') {
      return json(200, { pid: process.pid, mode: MODE });
    }
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
