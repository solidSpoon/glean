#!/usr/bin/env bash
# 生成 Xcode 工程并打开。改完 project.yml 重跑一次即可。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "缺少 xcodegen，先装一下：brew install xcodegen" >&2
  exit 1
fi

cd "$ROOT"
xcodegen generate
open "$ROOT/glean.xcodeproj"

cat <<'TIP'

提示：Xcode 里工具栏的 scheme 要选 Glean（App），不要选 GleanApp。
      GleanApp 是 SwiftPM 的裸可执行文件，跑起来没有窗口、也读不到相册。
TIP
