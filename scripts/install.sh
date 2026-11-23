#!/usr/bin/env bash
set -euo pipefail

REPO="${ORBITHUD_REPO:-mojtaba-afraz/OrbitHUD}"
OS="$(uname -s)"

echo "==> Installing OrbitHUD for $OS..."

if [ "$OS" = "Darwin" ]; then
  TMP_ZIP="/tmp/OrbitHUD-macOS.zip"
  DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/OrbitHUD-macOS.zip"
  echo "==> Downloading latest macOS release from $DOWNLOAD_URL..."
  curl -fL "$DOWNLOAD_URL" -o "$TMP_ZIP"
  killall OrbitHUD AntigravityUsageWidget 2>/dev/null || true
  rm -rf /Applications/OrbitHUD.app /Applications/AntigravityUsageWidget.app
  ditto -x -k "$TMP_ZIP" /Applications/
  rm -f "$TMP_ZIP"
  xattr -cr /Applications/OrbitHUD.app 2>/dev/null || true
  open /Applications/OrbitHUD.app
  echo "✅ OrbitHUD installed to /Applications/OrbitHUD.app and launched!"
elif [ "$OS" = "Linux" ]; then
  INSTALL_DIR="$HOME/.local/bin"
  mkdir -p "$INSTALL_DIR"
  TARGET="$INSTALL_DIR/OrbitHUD.AppImage"
  DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/OrbitHUD-Linux-x86_64.AppImage"
  echo "==> Downloading latest Linux AppImage from $DOWNLOAD_URL..."
  curl -fL "$DOWNLOAD_URL" -o "$TARGET"
  chmod +x "$TARGET"
  nohup "$TARGET" >/dev/null 2>&1 &
  echo "✅ OrbitHUD installed to $TARGET and launched!"
else
  echo "Unsupported OS for install.sh ($OS). On Windows, please download OrbitHUD-Windows-Setup.exe from GitHub Releases."
  exit 1
fi
