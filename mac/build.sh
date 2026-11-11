#!/bin/bash
# 一键编译打包「下班倒计时.app」
# 需要：Xcode / Command Line Tools（swiftc、iconutil、codesign）
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/../下班倒计时.app"
BUILD="$HERE/.build"
CONTENTS="$APP/Contents"

mkdir -p "$BUILD/ModuleCache" "$BUILD/AppIcon.iconset" "$CONTENTS/MacOS" "$CONTENTS/Resources"

echo "▸ 1/4 生成图标"
python3 "$HERE/make_icon.py" "$BUILD/icon_1024.png"
ICONSET="$BUILD/AppIcon.iconset"
sips -z 16   16   "$BUILD/icon_1024.png" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32   32   "$BUILD/icon_1024.png" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32   32   "$BUILD/icon_1024.png" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64   64   "$BUILD/icon_1024.png" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128  128  "$BUILD/icon_1024.png" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256  256  "$BUILD/icon_1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256  256  "$BUILD/icon_1024.png" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512  512  "$BUILD/icon_1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512  512  "$BUILD/icon_1024.png" --out "$ICONSET/icon_512x512.png"    >/dev/null
sips -z 1024 1024 "$BUILD/icon_1024.png" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

echo "▸ 2/4 编译 Swift"
# main.swift 只放入口；其余按职责拆到 Sources/ 子目录，这里收集全部 .swift 一起编译
SWIFT_FILES=()
while IFS= read -r f; do SWIFT_FILES+=("$f"); done < <(find "$HERE/Sources" -name '*.swift' -type f | sort)
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 \
  -module-cache-path "$BUILD/ModuleCache" \
  -o "$CONTENTS/MacOS/OffWorkCountdown" "${SWIFT_FILES[@]}"
cp "$HERE/Info.plist" "$CONTENTS/Info.plist"
plutil -lint "$CONTENTS/Info.plist"

echo "▸ 3/4 签名"
codesign --force --sign - --identifier com.rumor.offwork-countdown "$APP"

echo "▸ 4/4 校验"
codesign -v --verbose=1 "$APP"
"$CONTENTS/MacOS/OffWorkCountdown" --version-check
"$CONTENTS/MacOS/OffWorkCountdown" --hotkey-check
"$CONTENTS/MacOS/OffWorkCountdown" --selftest

echo ""
echo "✅ 已生成：$APP"
echo "   双击即可运行；⌃⌥⌘H 一键隐身 / 恢复，悬浮窗右上角可收缩成小图标。"
