#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

./scripts/build_app.sh

RELEASE_DIR="$PROJECT_DIR/releases"
mkdir -p "$RELEASE_DIR"

echo "==> Packaging macOS .zip release..."
rm -f "$RELEASE_DIR/OrbitHUD-macOS.zip"
(
  cd "$PROJECT_DIR/dist"
  ditto -c -k --sequesterRsrc --keepParent "OrbitHUD.app" "$RELEASE_DIR/OrbitHUD-macOS.zip"
)

echo "==> Packaging macOS .dmg installer..."
rm -f "$RELEASE_DIR/OrbitHUD-macOS.dmg"
DMG_STAGING="/tmp/orbithud-dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$PROJECT_DIR/dist/OrbitHUD.app" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

if hdiutil create -volname "OrbitHUD" -srcfolder "$DMG_STAGING" -ov -format UDZO "$RELEASE_DIR/OrbitHUD-macOS.dmg" >/dev/null 2>&1; then
  echo "  ✓ Created $RELEASE_DIR/OrbitHUD-macOS.dmg"
else
  echo "  ℹ hdiutil unavailable in sandbox; OrbitHUD-macOS.zip is ready at $RELEASE_DIR/OrbitHUD-macOS.zip"
fi
rm -rf "$DMG_STAGING"

echo "✅ Release packages ready in $RELEASE_DIR"
