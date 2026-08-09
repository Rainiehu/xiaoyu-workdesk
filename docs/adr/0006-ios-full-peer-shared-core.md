# iOS 是完整对等端，与 Mac 同仓共用核心

做 iPhone 版（ADR-0005 里「将来的 iPhone」到了），定两件事：**功能上是完整对等端** —— Mac 上能对待办做的事手机上都能做，连分类视图左列的拖拽排序也不例外；**代码上同仓抽共享核心** —— Models、Store 与同步三件套（CloudSync / SyncChangeLog / SyncRecords）抽成平台中立的 target，Mac UI 与 iOS UI 各一个 target 共用它。两端的差别只在呈现（见 [CONTEXT-iOS.md](../../CONTEXT-iOS.md)），规矩一条不改。

## Considered Options

- **随身伴侣端（手机只管记下来和看今天，重操作留给 Mac）** —— 拒绝：「这件事只能回 Mac 做」正是 ADR-0003 拆掉的那类要人记住的规矩的放大版；同步那条「规矩一条不改」的精神也容不下按设备划权限。
- **另起仓库，只共享 CloudKit 容器与记录格式约定** —— 拒绝：字段级合并、墓碑、记录打包解包恰恰是最不能漂移的部分，两端跑同一份代码是唯一可靠的保证；靠文档约定对齐，迟早漂成两副脾气。

## Consequences

- iOS 构建走一个最小 Xcode 工程（真机部署、签名、iCloud entitlement 都绕不开 Xcode），工程引用本仓库的 SwiftPM 包；SPM 直接构建的仍是 Mac 那份。
- 最低 iOS 17 —— CKSyncEngine 的硬要求，别无选择。
- 同一个 CloudKit 容器，不然就不是「同一份待办」。
- 开发者证书插线直装，不走 TestFlight / App Store —— 一个人的 app，审核与分发是为不存在的听众付成本；哪天想不插线更新再补 TestFlight，两条路不冲突。
- 收藏流不上 iOS 界面，但共享核心照旧同步收藏 —— 数据在，界面不画；同步范围仍是待办、分类与收藏。
- 域语言单份不复制：根 CONTEXT.md 是概念与跨端规矩的唯一出处，CONTEXT-iOS.md 只写呈现 —— 概念写两遍就埋下漂移的种子。
