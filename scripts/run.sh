#!/usr/bin/env bash
# 编译、打包、启动。改完代码直接跑这个。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/build-app.sh"

# 先关掉旧的实例，否则 open 只会把窗口切到前面，跑的还是旧二进制。
osascript -e 'quit app "Graze"' 2>/dev/null || true
sleep 0.3

open "$ROOT/build/Graze.app"
