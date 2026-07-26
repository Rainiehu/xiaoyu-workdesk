#!/bin/bash
# 编译并组装 Workdesk.app（./build/我的工作台.app）
set -e
cd "$(dirname "$0")"

swift build -c release

APP="build/我的工作台.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Workdesk "$APP/Contents/MacOS/Workdesk"
# 图标。要在 codesign 之前放进去 —— 签名封的是整个 bundle，之后再塞东西会让签名失效。
# 它由 Resources/makeicon.swift 生成，改设计就重跑那个脚本，见 README。
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

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
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <!-- 拖拽时传的两个自家类型：沙漏视图里拖着条目改期用前者，tab 栏上拖着分类调顺序用后者。
         与 HourglassView.swift 的 UTType.workdeskTodo、MainlineView.swift 的
         UTType.workdeskCategory 是同一批标识符，两边要一起改；在这儿声明过，
         系统才认得它们是本应用自家的类型。 -->
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>cc.huxiaoyu.workdesk.todo</string>
            <key>UTTypeDescription</key><string>待办</string>
            <key>UTTypeConformsTo</key>
            <array><string>public.data</string></array>
            <key>UTTypeTagSpecification</key><dict/>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>cc.huxiaoyu.workdesk.category</string>
            <key>UTTypeDescription</key><string>分类</string>
            <key>UTTypeConformsTo</key>
            <array><string>public.data</string></array>
            <key>UTTypeTagSpecification</key><dict/>
        </dict>
    </array>
    <key>NSHumanReadableCopyright</key><string></string>
</dict>
</plist>
EOF

codesign --force -s - "$APP" >/dev/null 2>&1

echo "Built: $APP"
