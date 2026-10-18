#!/usr/bin/env bash
# 编译 + 拼出 Graze.app + 签名。
#
# 为什么需要这一步：PhotoKit 要求进程是带 Info.plist 的 app bundle，裸可执行文件
# 一访问相册就会被系统直接杀掉。
#
# 签名身份：
#   GRAZE_SIGN_ID 未设置 → 临时签名（ad-hoc）。缺点是每次重编译 cdhash 都变，
#   系统的照片访问授权会失效并重新弹窗。
#   建议一次性在「钥匙串访问 → 证书助理 → 创建证书」里建一个「代码签名」证书，
#   然后 GRAZE_SIGN_ID="graze-dev" ./scripts/build-app.sh，授权就能一直记住。
#
# 工具链：
#   Xcode 升级后如果许可证还没接受，`swift` 会直接报
#   "You have not agreed to the Xcode license agreements"，此时自动回退到
#   Command Line Tools 的 swift（CLT 有独立许可证，不受影响）。
#   也可以显式指定：SWIFT_BIN=/path/to/swift ./scripts/build-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-debug}"

pick_swift() {
  if [ -n "${SWIFT_BIN:-}" ]; then
    echo "$SWIFT_BIN"
    return
  fi

  local xcode_plist="/Applications/Xcode.app/Contents/Info.plist"
  local agreed=""
  if [ -f "$xcode_plist" ]; then
    agreed="$(defaults read /Library/Preferences/com.apple.dt.Xcode IDEXcodeVersionForAgreedToGMLicense 2>/dev/null || true)"
    local installed
    installed="$(defaults read "$xcode_plist" CFBundleShortVersionString 2>/dev/null || true)"
    # 已接受许可证的版本号和当前安装的 Xcode 不一致 → 用 CLT 工具链绕过去
    if [ -n "$agreed" ] && [ -n "$installed" ] && [ "$agreed" != "$installed" ]; then
      local clt="/Library/Developer/CommandLineTools/usr/bin/swift"
      if [ -x "$clt" ]; then
        echo "note: Xcode $installed 的许可证未接受（已接受的是 $agreed），改用 Command Line Tools 工具链。" >&2
        echo "$clt"
        return
      fi
    fi
  fi
  echo "swift"
}

SWIFT="$(pick_swift)"
APP="$ROOT/build/Graze.app"

"$SWIFT" build -c "$CONFIG" --package-path "$ROOT" --product GrazeApp
BIN_DIR="$("$SWIFT" build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GrazeApp" "$APP/Contents/MacOS/Graze"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Graze.icns" "$APP/Contents/Resources/Graze.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

SIGN_ID="${GRAZE_SIGN_ID:--}"
if [ "$SIGN_ID" = "-" ]; then
  echo "warning: 使用临时签名，重编译后相册授权会失效。设置 GRAZE_SIGN_ID 可避免（见脚本注释）。"
fi

codesign --force --sign "$SIGN_ID" --timestamp=none "$APP"
codesign -dv "$APP" 2>&1 | sed 's/^/  /'
echo "built: $APP"
