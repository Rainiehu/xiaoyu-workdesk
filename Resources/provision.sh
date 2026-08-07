#!/bin/bash
# 找 Apple 要一份带 iCloud 容器的 provisioning profile。
# 只需在第一次、换机器或换开发者账号后跑一次；产物落在
# Resources/provisioning/Workdesk.provisionprofile（不入库），之后 ./build.sh 每次都会把它封进 app。
#
# 做法是借 Xcode 的管理式签名：这儿有个什么也不干的最小工程（bundle id 与真 app 相同），
# 拿 -allowProvisioningUpdates 构建一遍，Xcode 就会注册 App ID、开通 iCloud 容器、
# 登记这台 Mac、签发并下载 profile —— 全程用 Xcode 里已登录的开发者账号，
# 不需要去开发者网站手点。构建产物本身没有用，要的只是封在里头的那份 profile。
set -e
cd "$(dirname "$0")/.."

DERIVED="build/provisioning-derived"
PROFILE="Resources/provisioning/Workdesk.provisionprofile"

# SYMROOT 而不是 -derivedDataPath：后者只配 -scheme 用，而一个用完就扔的工程犯不上养 scheme。
if ! xcodebuild -project Resources/provisioning/Provisioning.xcodeproj \
    -target Provisioning -configuration Release \
    SYMROOT="$PWD/$DERIVED" \
    -allowProvisioningUpdates \
    build; then
    echo "✗ xcodebuild 没走通。" >&2
    echo "  若上面写着 No Accounts，是 Xcode 里没登录开发者账号 —— 打开 Xcode →" >&2
    echo "  Settings → Accounts 登录一次（只这一步没法替你做），然后再跑这个脚本。" >&2
    echo "  没有这份 profile 时 ./build.sh 照常出产物，只是那份 app 没有 iCloud、同步不启动。" >&2
    exit 1
fi

BUILT="$DERIVED/Release/Provisioning.app/Contents/embedded.provisionprofile"
if [ ! -f "$BUILT" ]; then
    echo "✗ 构建成了，却没见到 embedded.provisionprofile —— Xcode 没把 profile 封进去。" >&2
    echo "  多半是 Xcode 里没登录开发者账号（Settings → Accounts），登录后再跑一次。" >&2
    exit 1
fi

cp "$BUILT" "$PROFILE"
echo "✓ Profile 已就位：$PROFILE"
echo "  跑 ./build.sh 就会得到带 iCloud 权限的签名 bundle。"
