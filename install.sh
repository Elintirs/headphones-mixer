#!/bin/zsh
# Установка «Громкости наушников» в ~/Applications.
# curl -fsSL https://raw.githubusercontent.com/Elintirs/headphones-mixer/main/install.sh | zsh
set -euo pipefail

REPO="Elintirs/headphones-mixer"
NAME="Громкость наушников"
DEST="$HOME/Applications"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Скачиваю последний релиз $REPO…"
curl -fsSL "https://github.com/$REPO/releases/latest/download/HeadphonesMixer.zip" -o "$TMP/app.zip"
ditto -x -k "$TMP/app.zip" "$TMP"

pkill -x HeadphonesMixer 2>/dev/null || true
mkdir -p "$DEST"
rm -rf "$DEST/$NAME.app"
ditto "$TMP/$NAME.app" "$DEST/$NAME.app"
xattr -dr com.apple.quarantine "$DEST/$NAME.app" 2>/dev/null || true
open "$DEST/$NAME.app"
echo "Готово: иконка наушников появилась в строке меню. Приложение: $DEST/$NAME.app"
