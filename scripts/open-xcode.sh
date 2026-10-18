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
