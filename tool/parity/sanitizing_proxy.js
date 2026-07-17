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
  if (req.method === 'GET' && req.url === '/__health') {
    // 端口归属证明：调用方比对 pid 与自己 spawn 的子进程 pid。
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ pid: process.pid, upstream: UPSTREAM.href }));
  }
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
