# 案头 · Workdesk

一个清新简洁的 macOS 个人桌面工作台，用 SwiftUI 原生构建。

## 功能

- **主线** — 待办按自建的分类组织，分类以顶部 tab 呈现，新建只需输入名字、颜色自动分配；tab 上右键可改名、换色、删除，拖着 tab 就调顺序；点进一个分类就看到左右两列，左边待完成、右边已完成，敲字回车记事，打勾完成、悬停删除，双击正文就地改写；左列的顺序自己拖（拖一行放到另一行上），把一行拖到 tab 栏另一个分类上就换了归属，右键菜单里也有同样这几件事
- **沙漏视图** — 横跨所有分类的时间轴，按计划日铺开，今天锚在中间，上方是过去、下方是未来；顶上就能记事，旁边的分类选择器记着上次的选择，记下的待办自动排在今天；条目拖到另一个日期分组就改了期，落点当场框出来；每一行都能就地打勾（勾上就点亮成它的分类色）、悬停浮出删除；右边单开一列「未排期」，按分类分组、自己滚，悬停选个日子或者直接拖到轴上某一天就排上了，在那儿打了勾的会亮一下再淡出
- **收藏流** — 粘贴链接或文字即收藏，链接卡片带域名标签、点击直达
- **AI 用量** — 侧边栏底部小卡片，每分钟自动刷新。今日 token 用量来自本机 Claude Code / Codex 的会话日志（四种 token 分开算，悬停看细分）；限流窗口 Claude 走 `/api/oauth/usage`（5 小时与 7 天两个窗口的真实百分比与重置时刻），Codex 走它自己 rollout 日志里的 `rate_limits`

## 构建 & 运行

需要 macOS 14+ 和 Swift 6 工具链（Xcode 26 自带）。

```bash
./build.sh
open "build/案头.app"
```

`build.sh` 会以 release 模式编译并组装出 `build/案头.app`，把图标放进去，并做一次 ad-hoc 签名。ad-hoc 签名只够本机自己跑 —— 拷给别人时对方仍会被 Gatekeeper 拦下，得右键「打开」。

### 装进 /Applications

只装一次，之后 `./build.sh` 就直接生效，不用再拷：

```bash
ln -s "$PWD/build/案头.app" "/Applications/案头.app"
```

`/Applications` 里放的是软链接，app 实体始终只有仓库里这一份 —— 不会出现装好的那份悄悄落后于代码。代价是这个仓库不能随便移走或删掉，否则链接就断了。

### 签名

`build.sh` 默认用 ad-hoc 签名，而 ad-hoc 签名**每次重建都不一样** —— macOS 于是把每次构建当成另一个程序，钥匙串之类按程序记的授权每次都要重点一遍。跑一次下面这个就换成一张固定的本机证书，之后授权点一次就够（会问一次登录密码）：

```bash
./Resources/make-signing-cert.sh
```

这张证书只在本机有效，不能用于分发。

### AI 用量的数据从哪来

- **用了多少** — 本地日志。Claude 在 `~/.claude/projects/**/*.jsonl`，Codex 在 `~/.codex/sessions/`。Claude 把缓存读写单列在 `cache_read_input_tokens` / `cache_creation_input_tokens`，Codex 则把缓存读算进 `input_tokens` 里 —— 两边都摊平成输入/输出/缓存读/缓存写四项之后才可比。
- **还剩多少** — Claude 不写本地，得调 `https://api.anthropic.com/api/oauth/usage`，凭证取自钥匙串的 `Claude Code-credentials`（Claude Code 自己写入并维护，过期了要去 Claude Code 里重新登录）。Codex 把 `rate_limits` 直接写在 rollout 日志里，不用联网。

取钥匙串时刻意走 `/usr/bin/security` 子进程而不是 Security 框架：钥匙串授权绑在调用方的代码签名上，`security` 是 Apple 签的、签名不变，授权一次长期有效。

### 图标

`Resources/AppIcon.icns` 由 `Resources/makeicon.swift` 生成，十个尺寸各自矢量重绘（不是缩放），改了设计就重跑：

```bash
mkdir -p /tmp/AppIcon.iconset
swift Resources/makeicon.swift /tmp/AppIcon.iconset
iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
```

图案是一只黑白手绘的钢笔线稿沙漏 —— 时间是这个 app 的纵轴，沙漏的腰正是「今天」。暖白纸底、墨色线条，抖动在 1024 坐标系里算好再按比例缩放，十个尺寸抖的是同一只手。

跑测试：

```bash
swift test
```

测试用 swift-testing。读写数据的测试都指向临时目录，不碰 `~/Library/Application Support/` 下的真实数据。

## 数据存储

分类、待办与收藏各自保存在 `~/Library/Application Support/XiaoyuWorkdesk/`（`categories.json` / `todos-v2.json` / `favorites.json`），重启不丢。用户的选择偏好（比如沙漏视图记事时选的分类）单独落在 `preferences.json`，与数据分开。

待办改为按分类组织后，旧的 `todos.json` 已废弃：不读取、不转换，装着旧数据的机器首次运行就是空状态。

## 项目结构

```
Sources/Workdesk/
  WorkdeskApp.swift       应用入口
  ContentView.swift       侧边栏 + 分栏导航
  Models.swift            数据模型
  Store.swift             状态与持久化
  MainlineView.swift      主线：分类 tab 栏、新建分类、引导空态
  CategoryTodoList.swift  分类视图：记事输入框，待完成/已完成两列
  HourglassView.swift     沙漏视图：顶部记事输入区，按计划日铺开的时间轴，拖拽改期
  UnscheduledColumn.swift 沙漏视图右边那一列：还没排期的事，按分类分组
  TodoRowStyle.swift      三处待办行共用的结构：度量、打勾的圈、删除、拖拽预览
  TodoInputField.swift    记事输入框，两个视图共用
  PlannedDayControl.swift 一条待办的排期入口与计划日面板
  FavoritesView.swift     收藏流
  UsageCard.swift         AI 用量卡片，每分钟自刷
  UsageScanner.swift      扫描本地日志统计 token，并取 Codex 的限流窗口
  UsageLimits.swift       用量与限流的数据模型，以及接口返回的解析
  ClaudeUsageAPI.swift    取 Claude 的限流状态（钥匙串 + /api/oauth/usage）
Tests/WorkdeskTests/
  StoreTests.swift           存储目录与收藏流的持久化
  CategoryTests.swift        分类的新建、配色与持久化
  CategoryManagementTests.swift 分类的改名、换色、排序与删除，以及待办改分类
  TodoTests.swift            待办的归属、打勾、删除与持久化
  PlannedDayTests.swift      排期、改期与清除计划日
  CategoryColumnsTests.swift 分类视图两列的拼接与三套排序
  TimelineTests.swift        沙漏视图的按日分组
  HourglassRecordingTests.swift 沙漏视图记事：归属分类、计划日与记住的选择
  TimelineDragTests.swift    沙漏视图里拖着条目改期
  DayLabelTests.swift        日期在界面上的写法
  TestSupport.swift          临时目录等测试夹具
```
