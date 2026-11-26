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
ARM64_BIN="$BUILD_DIR/$APP_NAME-arm64"
X86_64_BIN="$BUILD_DIR/$APP_NAME-x86_64"

swiftc -O \
    -module-cache-path /tmp/swift-module-cache \
    -target arm64-apple-macosx13.0 \
    Sources/Core/*.swift \
    Sources/App/*.swift \
    -o "$ARM64_BIN"

if swiftc -O \
    -module-cache-path /tmp/swift-module-cache \
    -target x86_64-apple-macosx13.0 \
    Sources/Core/*.swift \
    Sources/App/*.swift \
    -o "$X86_64_BIN" 2>/dev/null; then
    echo "==> Creating Universal binary (arm64 + x86_64)..."
    lipo -create -output "$BIN_PATH" "$ARM64_BIN" "$X86_64_BIN"
    rm -f "$ARM64_BIN" "$X86_64_BIN"
else
    echo "ℹ x86_64 cross-compile unavailable; using arm64 binary."
    mv "$ARM64_BIN" "$BIN_PATH"
fi

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
    <string>1.2.6</string>
    <key>CFBundleVersion</key>
    <string>8</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

if [ -n "${APPLE_SIGN_IDENTITY:-}" ]; then
    echo "==> Signing $APP_BUNDLE with Developer ID ($APPLE_SIGN_IDENTITY)..."
    codesign --force --deep --options runtime --timestamp --sign "$APPLE_SIGN_IDENTITY" "$APP_BUNDLE"
else
    echo "==> Signing $APP_BUNDLE (ad-hoc local signature)..."
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "✅ Done! Application bundle created at:"
echo "   $APP_BUNDLE"
