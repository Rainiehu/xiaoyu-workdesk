# 上架 App Store，自用与公开各走一个 CloudKit 环境

ADR-0006 定过「插线直装，不走 TestFlight / App Store」。现在想把 iOS 版上架给别人用，那一条改掉；其余照旧。上架带出来的真问题只有一个：数据放在哪个 CloudKit 环境。

CloudKit 每个容器天生分两份互不相通的库：开发与生产。连哪份由签名决定 —— 开发证书签的连开发库，App Store / TestFlight 的包只能连生产库。本决定：**自己的 Mac 与 iPhone 照旧用开发构建、连开发库；生产库只给从 App Store 装的人用。** 自己的数据与公开用户隔开，开发库也继续是能随便改字段、随便清空的地方。

## Considered Options

- **自己的两台设备也切到生产库**（entitlement 里写 `com.apple.developer.icloud-container-environment = Production`，开发构建也能连）—— 拒绝：自己的数据就和公开版走同一套只能加不能删的 schema，改同步字段时再没有一个能放手试的库。真想让自己用上架版的数据，回来改这一条就是，本地 JSON 是事实来源，清掉 `sync-engine.json` 重传一遍即可。

## Consequences

- 每次改了同步记录的类型或字段，发版之前先在 CloudKit Console 把 schema 部署到生产（Deploy Schema Changes）。生产的 schema 只能加不能删。
- 同一个 bundle id 在一台手机上只装得下一份。用 TestFlight 或 App Store 装上架版会盖掉插线装的开发版，连的也是生产库、看不到自己的数据 —— 测上架版用另一台设备或另一个 Apple ID；测完插线装回开发版，本地数据还在。
- 「有没有 iCloud 权限」不能再拿 `embedded.mobileprovision` 判断：上架包里没有这个文件。真机一律当有，没登录 iCloud 交给引擎的账号事件。
- Mac 版不进 Mac App Store：沙盒读不了 `~/.claude`、`~/.codex` 的日志，也调不了 `/usr/bin/security`，AI 用量卡整个活不了。要给别人用就走 Developer ID 签名加公证。
