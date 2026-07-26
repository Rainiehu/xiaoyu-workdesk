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

# 有本机那张自签名证书就用它，签名因此每次都一样，钥匙串之类按程序记的授权点一次就够。
# 没有就退回 ad-hoc —— app 照样能跑，只是每次重建都会被系统当成一个新程序。
# 那张证书由 Resources/make-signing-cert.sh 建，只需跑一次。
IDENTITY="Workdesk Local Signing"
sign_adhoc() { codesign --force -s - "$APP" >/dev/null 2>&1; }

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    # 限时 15 秒。私钥若被设成「使用前需确认」，codesign 会弹框然后一直等下去 ——
    # 构建脚本不该挂在一个没人看见的对话框上，超时就退回 ad-hoc，照样出得来产物。
    codesign --force -s "$IDENTITY" "$APP" >/dev/null 2>&1 &
    signer=$!
    ( sleep 15; kill -TERM $signer 2>/dev/null ) 2>/dev/null &
    killer=$!
    # 这两句都可能返回非零（签名被掐、计时器已自己退出），而脚本开头是 set -e ——
    # 不兜住的话它会在这儿默默退出，产物看着像没构建完。
    if wait $signer 2>/dev/null; then status=0; else status=$?; fi
    kill $killer 2>/dev/null || true
    if [ $status -ne 0 ]; then
        sign_adhoc
        echo "注意：用证书签名没成（多半是私钥要求每次确认），已退回 ad-hoc 签名。"
        echo "      跑一次 ./Resources/make-signing-cert.sh 可以把它修好。"
    fi
else
    sign_adhoc
fi

echo "Built: $APP"
