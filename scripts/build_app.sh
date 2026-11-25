#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="OrbitHUD"
BUILD_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "==> Building $APP_NAME (Release)..."
mkdir -p "$BUILD_DIR" /tmp/swift-module-cache
BIN_PATH="$BUILD_DIR/$APP_NAME-bin"

swiftc -O \
    -module-cache-path /tmp/swift-module-cache \
    -target arm64-apple-macosx13.0 \
    Sources/Core/*.swift \
    Sources/App/*.swift \
    -o "$BIN_PATH"

echo "==> Creating macOS Application Bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE" "$BUILD_DIR/AntigravityUsageWidget.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
rm -f "$BIN_PATH"

if [ -f "$PROJECT_DIR/assets/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
if [ -f "$PROJECT_DIR/assets/logo.png" ]; then
    cp "$PROJECT_DIR/assets/logo.png" "$APP_BUNDLE/Contents/Resources/logo.png"
fi
if [ -f "$PROJECT_DIR/assets/logo.svg" ]; then
    cp "$PROJECT_DIR/assets/logo.svg" "$APP_BUNDLE/Contents/Resources/logo.svg"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.orbithud.antigravity</string>
    <key>CFBundleName</key>
    <string>OrbitHUD</string>
    <key>CFBundleDisplayName</key>
    <string>OrbitHUD</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.1</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "==> Signing $APP_BUNDLE (ad-hoc local signature)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✅ Done! Application bundle created at:"
echo "   $APP_BUNDLE"
