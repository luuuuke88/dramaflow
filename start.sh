#!/bin/bash
# DramaFlow 一键启动：azt 网关 + 后端。Flutter 桌面 App 单独用 open 打开（见 README）。
set -e
cd "$(dirname "$0")"

echo "== 1/3 检查 azt (127.0.0.1:8787) =="
if ! curl -sS -m 3 http://127.0.0.1:8787/v1/models -H 'Authorization: Bearer local' > /dev/null 2>&1; then
  echo "   azt 未运行，正在启动..."
  screen -dmS azt-serve azt serve
  sleep 5
fi
curl -sS -m 5 http://127.0.0.1:8787/v1/models -H 'Authorization: Bearer local' > /dev/null \
  && echo "   ✅ azt 就绪" || { echo "   ❌ azt 启动失败，请手动运行: azt serve"; exit 1; }

echo "== 2/3 启动 DramaFlow 后端 (127.0.0.1:8620) =="
if curl -sS -m 3 http://127.0.0.1:8620/api/health > /dev/null 2>&1; then
  echo "   ✅ 后端已在运行"
else
  (cd server && nohup npm start > ../server.log 2>&1 &)
  for i in $(seq 1 15); do
    sleep 1
    curl -sS -m 2 http://127.0.0.1:8620/api/health > /dev/null 2>&1 && break
  done
  curl -sS -m 3 http://127.0.0.1:8620/api/health > /dev/null \
    && echo "   ✅ 后端已启动（日志: server.log）" || { echo "   ❌ 后端启动失败，查看 server.log"; exit 1; }
fi

echo "== 3/3 完成 =="
echo "   后端:   http://127.0.0.1:8620  (token: local-dev)"
echo "   桌面App: open app/build/macos/Build/Products/Release/dramaflow.app"
echo "   开发运行: cd app && flutter run -d macos"
