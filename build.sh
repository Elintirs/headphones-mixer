#!/bin/zsh
# Собирает «Громкость наушников.app» (universal: Apple Silicon + Intel) в dist/.
# ./build.sh            собрать
# ./build.sh --install  собрать, положить в ~/Applications и запустить
set -euo pipefail
cd "$(dirname "$0")"

NAME="Громкость наушников"
BIN=HeadphonesMixer
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-1.0.0}"
APP="dist/$NAME.app"

rm -rf dist
mkdir -p "$APP/Contents/MacOS" dist/obj
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13.0" main.swift -o "dist/obj/$BIN-$arch"
done
lipo -create dist/obj/$BIN-* -output "$APP/Contents/MacOS/$BIN"
rm -rf dist/obj

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$BIN</string>
  <key>CFBundleIdentifier</key><string>io.github.elintirs.headphones-mixer</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force -s - "$APP"
(cd dist && ditto -c -k --keepParent "$NAME.app" HeadphonesMixer.zip)
echo "Собрано: $APP, архив dist/HeadphonesMixer.zip"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x "$BIN" 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/$NAME.app"
  ditto "$APP" "$HOME/Applications/$NAME.app"
  open "$HOME/Applications/$NAME.app"
  echo "Установлено в ~/Applications и запущено"
fi
