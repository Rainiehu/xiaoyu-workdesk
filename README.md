# 我的工作台 · Workdesk

一个清新简洁的 macOS 个人桌面工作台，用 SwiftUI 原生构建。

## 功能

- **主线** — 待办按自建的分类组织，分类以顶部 tab 呈现，新建只需输入名字、颜色自动分配；点进一个分类就是它的清单，敲字回车记事，打勾完成、悬停删除
- **收藏流** — 粘贴链接或文字即收藏，链接卡片带域名标签、点击直达
- **AI 用量** — 侧边栏底部小卡片，扫描本机 Claude Code / Codex 会话日志，展示今日 token 用量与周额度占比

## 构建 & 运行

需要 macOS 14+ 和 Swift 6 工具链（Xcode 26 自带）。

```bash
./build.sh
open "build/我的工作台.app"
```

`build.sh` 会以 release 模式编译并组装出 `build/我的工作台.app`。

跑测试：

```bash
swift test
```

测试用 swift-testing。读写数据的测试都指向临时目录，不碰 `~/Library/Application Support/` 下的真实数据。

## 数据存储

分类、待办与收藏各自保存在 `~/Library/Application Support/XiaoyuWorkdesk/`（`categories.json` / `todos-v2.json` / `favorites.json`），重启不丢。

待办改为按分类组织后，旧的 `todos.json` 已废弃：不读取、不转换，装着旧数据的机器首次运行就是空状态。

## 项目结构

```
Sources/Workdesk/
  WorkdeskApp.swift    应用入口
  ContentView.swift    侧边栏 + 分栏导航
  Models.swift         数据模型
  Store.swift          状态与持久化
  MainlineView.swift   主线：分类 tab 栏、新建分类、引导空态
  TodoListView.swift   分类内的待办清单：记事输入框、打勾、删除
  FavoritesView.swift  收藏流
  UsageCard.swift      AI 用量卡片
  UsageScanner.swift   扫描本地日志统计 token
Tests/WorkdeskTests/
  StoreTests.swift     存储目录与收藏流的持久化
  CategoryTests.swift  分类的新建、配色与持久化
  TodoTests.swift      待办的归属、打勾、删除与持久化
  TestSupport.swift    临时目录等测试夹具
```
