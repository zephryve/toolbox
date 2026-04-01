#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/SleepToggle.app/Contents/MacOS"

echo "编译 SleepToggle..."
mkdir -p "$APP_DIR"
swiftc "$SCRIPT_DIR/SleepToggle.swift" -o "$APP_DIR/SleepToggle" -framework Cocoa

# 创建 Info.plist
cat > "$SCRIPT_DIR/SleepToggle.app/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>SleepToggle</string>
    <key>CFBundleIdentifier</key>
    <string>com.zephryve.sleeptoggle</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleExecutable</key>
    <string>SleepToggle</string>
</dict>
</plist>
EOF

echo "编译完成: $SCRIPT_DIR/SleepToggle.app"
