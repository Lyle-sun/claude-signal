#!/bin/bash
set -e

APP_NAME="ClaudeSignal.app"
BUILD_DIR=".build/arm64-apple-macosx/release"
APP_BUNDLE=".build/$APP_NAME"

echo "Building release..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/ClaudeSignal" "$APP_BUNDLE/Contents/MacOS/"

# 复制图标资源
RESOURCES_SRC="Sources/ClaudeSignal/Resources"
if [ -d "$RESOURCES_SRC" ]; then
    cp "$RESOURCES_SRC"/*.png "$APP_BUNDLE/Contents/Resources/"
    # App icon
    if [ -f "$RESOURCES_SRC/AppIcon.icns" ]; then
        cp "$RESOURCES_SRC/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    fi
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>ClaudeSignal</string>
	<key>CFBundleIdentifier</key>
	<string>com.claude-signal.app</string>
	<key>CFBundleName</key>
	<string>Claude Signal</string>
	<key>CFBundleVersion</key>
	<string>1.0.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
EOF

echo "Codesigning..."
codesign -s - "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
