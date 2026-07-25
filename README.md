# 我的工作台 · Workdesk

一个清新简洁的 macOS 个人桌面工作台，用 SwiftUI 原生构建。

## 功能

- **今日待办** — 快速添加、打勾完成，未完成项自动归入「早前未完成」并可一键挪到今天
- **历史** — 过往待办按天倒序归档，随时回看
- **收藏流** — 粘贴链接或文字即收藏，链接卡片带域名标签、点击直达
- **AI 用量** — 侧边栏底部小卡片，扫描本机 Claude Code / Codex 会话日志，展示今日 token 用量与周额度占比

## 构建 & 运行

需要 macOS 14+ 和 Swift 6 工具链（Xcode 26 自带）。

```bash
./build.sh
open "build/我的工作台.app"
```

`build.sh` 会以 release 模式编译并组装出 `build/我的工作台.app`。

## 数据存储

待办与收藏保存在 `~/Library/Application Support/XiaoyuWorkdesk/`（`todos.json` / `favorites.json`），重启不丢。

## 项目结构

```
Sources/Workdesk/
  WorkdeskApp.swift    应用入口
  ContentView.swift    侧边栏 + 分栏导航
  Models.swift         数据模型
  Store.swift          状态与持久化
  TodoViews.swift      今日 / 历史待办
  FavoritesView.swift  收藏流
  UsageCard.swift      AI 用量卡片
  UsageScanner.swift   扫描本地日志统计 token
```
