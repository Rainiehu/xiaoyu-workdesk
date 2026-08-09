#!/bin/bash
# 编译并组装 Workdesk.app（./build/案头.app）
set -e
cd "$(dirname "$0")"

swift build -c release

APP="build/案头.app"
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
    <key>CFBundleName</key><string>案头</string>
    <key>CFBundleDisplayName</key><string>案头</string>
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

# 签名分三档，从高到低逐档退，哪一档都出得来产物 —— 签名的事永远不挡构建：
# 1) 开发者证书 + iCloud provisioning profile（Resources/provision.sh 讨来的那份）：
#    app 拿到 iCloud 权限，收藏的同步就此启动。
# 2) 本机自签证书（Resources/make-signing-cert.sh 建的）：签名稳定，按程序记的授权
#    点一次就够，但没有 iCloud —— 同步安静地不启动，app 是完整的单机 app。
# 3) ad-hoc：随时可用，只是每次重建都会被系统当成一个新程序。

# 限时 15 秒签名。私钥若被设成「使用前需确认」，codesign 会弹框然后一直等下去 ——
# 构建脚本不该挂在一个没人看见的对话框上，超时就算没签成，让上层逐档退。
# wait 和 kill 都可能返回非零（签名被掐、计时器已自己退出），而脚本开头是 set -e ——
# 不兜住的话它会在这儿默默退出，产物看着像没构建完。
timed_sign() {
    codesign "$@" >/dev/null 2>&1 &
    local signer=$!
    ( sleep 15; kill -TERM $signer 2>/dev/null ) 2>/dev/null &
    local killer=$!
    local status
    if wait $signer 2>/dev/null; then status=0; else status=$?; fi
    kill $killer 2>/dev/null || true
    return $status
}
sign_adhoc() { codesign --force -s - "$APP" >/dev/null 2>&1; }

PROFILE="Resources/provisioning/Workdesk.provisionprofile"
# 认哈希不认名字 —— 同名的开发者证书常常不止一张，按名字签会因为「有歧义」而失败。
DEV_HASH=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')
LOCAL_IDENTITY="Workdesk Local Signing"

signed=false
if [ -f "$PROFILE" ] && [ -n "$DEV_HASH" ]; then
    # 签名用的 entitlements 直接从 profile 里取 —— 两边永远一致，
    # 不会签出一个 profile 不认、系统于是拒绝启动的 app。
    ENT="build/entitlements.plist"
    if security cms -D -i "$PROFILE" 2>/dev/null | plutil -extract Entitlements xml1 -o "$ENT" - 2>/dev/null; then
        # profile 里写的是「允许什么」的模式，签名要的是「就是什么」的具体值。
        # 模式原样签进去，CloudKit 启动时会当场抛 malformed entitlements 把 app 掀翻：
        # icloud-services 的 "*" 落成 ["CloudKit"]；环境落定 Development ——
        # 只有它会随写随建 schema，Production 里没部署过的记录类型一保存就无声失败。
        # 哪天真要换环境也不迁移：本地永远是事实来源，云端换成空的就整体重传。
        # kvstore 那条是没用上的通配模式，直接去掉。
        /usr/libexec/PlistBuddy \
            -c "Delete :com.apple.developer.icloud-services" \
            -c "Add :com.apple.developer.icloud-services array" \
            -c "Add :com.apple.developer.icloud-services:0 string CloudKit" \
            -c "Delete :com.apple.developer.icloud-container-environment" \
            -c "Add :com.apple.developer.icloud-container-environment string Development" \
            "$ENT"
        /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.ubiquity-kvstore-identifier" "$ENT" 2>/dev/null || true
        cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
        if timed_sign --force --entitlements "$ENT" -s "$DEV_HASH" "$APP"; then
            signed=true
            echo "已用开发者证书签名，带 iCloud 权限。"
        else
            rm -f "$APP/Contents/embedded.provisionprofile"
            echo "注意：开发者证书签名没成，退往下一档（那一档没有 iCloud，同步不启动）。"
        fi
    fi
fi

if ! $signed && security find-identity -v -p codesigning 2>/dev/null | grep -q "$LOCAL_IDENTITY"; then
    if timed_sign --force -s "$LOCAL_IDENTITY" "$APP"; then
        signed=true
    else
        echo "注意：用本机证书签名没成（多半是私钥要求每次确认），已退回 ad-hoc 签名。"
        echo "      跑一次 ./Resources/make-signing-cert.sh 可以把它修好。"
    fi
fi

if ! $signed; then
    sign_adhoc
fi

echo "Built: $APP"
