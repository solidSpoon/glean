#!/usr/bin/env bash
# 编译 + 拼出 Glean.app + 签名。
#
# 为什么需要这一步：PhotoKit 要求进程是带 Info.plist 的 app bundle，裸可执行文件
# 一访问相册就会被系统直接杀掉。
#
# 签名身份：
#   GLEAN_SIGN_ID 未设置 → 临时签名（ad-hoc）。缺点是每次重编译 cdhash 都变，
#   系统的照片访问授权会失效并重新弹窗。
#   建议一次性在「钥匙串访问 → 证书助理 → 创建证书」里建一个「代码签名」证书，
#   然后 GLEAN_SIGN_ID="glean-dev" ./scripts/build-app.sh，授权就能一直记住。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
APP="$ROOT/build/Glean.app"

swift build -c "$CONFIG" --package-path "$ROOT" --product GleanApp
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GleanApp" "$APP/Contents/MacOS/Glean"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

SIGN_ID="${GLEAN_SIGN_ID:--}"
if [ "$SIGN_ID" = "-" ]; then
  echo "warning: 使用临时签名，重编译后相册授权会失效。设置 GLEAN_SIGN_ID 可避免（见脚本注释）。"
fi

codesign --force --sign "$SIGN_ID" --timestamp=none "$APP"
codesign -dv "$APP" 2>&1 | sed 's/^/  /'
echo "built: $APP"
