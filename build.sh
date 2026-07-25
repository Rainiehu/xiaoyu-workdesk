#!/bin/bash
# 编译并组装 Workdesk.app（./build/我的工作台.app）
set -e
cd "$(dirname "$0")"

swift build -c release

APP="build/我的工作台.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/Workdesk "$APP/Contents/MacOS/Workdesk"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Workdesk</string>
    <key>CFBundleIdentifier</key><string>cc.huxiaoyu.workdesk</string>
    <key>CFBundleName</key><string>我的工作台</string>
    <key>CFBundleDisplayName</key><string>我的工作台</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string></string>
</dict>
</plist>
EOF

codesign --force -s - "$APP" >/dev/null 2>&1

echo "Built: $APP"
