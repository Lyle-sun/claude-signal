#!/bin/bash
set -e

APP_NAME="ClaudeSignal.app"
BUILD_DIR=".build/release"
APP_BUNDLE=".build/$APP_NAME"

echo "Building release..."
swift build -c release

echo "Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/ClaudeSignal" "$APP_BUNDLE/Contents/MacOS/"

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
