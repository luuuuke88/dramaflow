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
  // 控制端点必须按去 query 的路径匹配（fake_upstream.js 同款修复 d3a9214）：
  // 否则 '/__health?x=1' 会掉进转发分支、把杂散请求发到真实上游。
  const pathOnly = req.url.split('?')[0];
  if (req.method === 'GET' && pathOnly === '/__health') {
    // 端口归属证明：调用方比对 pid 与自己 spawn 的子进程 pid。
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ pid: process.pid, upstream: UPSTREAM.href }));
  }
  if (req.method === 'POST' && pathOnly === '/__mark') {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      let mark = 'mark';
      try { mark = JSON.parse(Buffer.concat(chunks).toString('utf8')).mark || 'mark'; } catch (_) {}
      logLine({ mark });
      res.writeHead(204).end();
    });
    req.on('error', () => res.destroy());
    return;
  }
  const started = Date.now();
  const client = UPSTREAM.protocol === 'https:' ? https : http;
  const proxied = client.request(
    {
      protocol: UPSTREAM.protocol,
      hostname: UPSTREAM.hostname,
      port: UPSTREAM.port || (UPSTREAM.protocol === 'https:' ? 443 : 80),
      method: req.method,
      // 转发保留完整 req.url（含 query）——只有日志走 pathOnly。
      path: (UPSTREAM.pathname === '/' ? '' : UPSTREAM.pathname) + req.url,
      headers: { ...req.headers, host: UPSTREAM.host },
    },
    (up) => {
      logLine({ method: req.method, path: pathOnly, status: up.statusCode, ms: Date.now() - started });
      res.writeHead(up.statusCode || 502, up.headers);
      up.pipe(res);
      // 上游响应流中途出错（如连接被重置）：终止客户端连接即可，
      // 不能再次 writeHead——头已发出，重复调用会抛 ERR_HTTP_HEADERS_SENT
      // 并击穿整个代理进程。
      up.on('error', () => res.destroy());
    },
  );
  proxied.on('error', (err) => {
    logLine({ method: req.method, path: pathOnly, status: -1, ms: Date.now() - started });
    if (res.headersSent) {
      res.destroy();
    } else {
      res.writeHead(502).end(String(err.code || 'proxy_error'));
    }
  });
  // 客户端中途断开：销毁上游连接，避免真实付费 API 的连接泄漏
  // （pipe 的语义是源出错不会关闭目的端）。
  req.on('error', () => proxied.destroy());
  res.on('close', () => {
    if (!res.writableEnded) proxied.destroy();
  });
  req.pipe(proxied);
}).listen(PORT, '127.0.0.1', () => console.log(`proxy 127.0.0.1:${PORT} -> ${UPSTREAM.href} log=${LOG}`));
