import Foundation

/// 扫描本机 Claude Code / Codex 的会话日志，统计今日 token 用量。
///
/// 日志只说「用了多少」。Claude 的「还剩多少」得走 `ClaudeUsageAPI`；Codex 则把限流状态
/// 一并写在 rollout 日志里，这里顺手取了。
// 扫的是这台 Mac 上的会话日志，iOS 上无此物 —— 整个文件只属于 macOS。
#if os(macOS)
enum UsageScanner {
    static func scan() -> (claude: ToolUsage, codex: ToolUsage, codexWindows: [UsageWindow]) {
        let (codex, windows) = scanCodex()
        return (scanClaude(), codex, windows)
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// 「今日」从哪一刻算起 —— **本地**的今天零点。
    ///
    /// 日志里的时间戳是 UTC，早前就按 UTC 的日历天筛行，结果卡片上的「今日」跟着 UTC 走：
    /// 在 UTC+10 这边，本地 00:00 到 10:00 干的活全被砍掉，数字凭空少一大截。
    /// 侧边栏上写着「今日」，那就得是看它的人所在的今日。
    static func todayStart(now: Date = .now) -> Date { now.dayStart }

    /// 把某一刻写成日志里那种时间戳，好拿去跟行里的时间戳直接比字符串。
    ///
    /// 两边的日志都用定长的 `YYYY-MM-DDTHH:MM:SS.sssZ`，这种格式按字典序比就等于按时间比 ——
    /// 于是筛选不必逐行解析日期，几万行也只是字符串比较。
    static func timestampString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    /// 取出一行里的时间戳。取不到就当这行没有时间，调用方跳过它。
    private static func timestamp(in line: some StringProtocol) -> String? {
        guard let r = line.range(of: "\"timestamp\":\"") else { return nil }
        let rest = line[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    // MARK: - Claude Code (~/.claude/projects/**/*.jsonl)

    private static func scanClaude() -> ToolUsage {
        var tool = ToolUsage()
        let root = home.appendingPathComponent(".claude/projects")
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return tool }

        let dayStart = todayStart()
        let cutoff = timestampString(dayStart)
        for case let url as URL in en {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let mtime = values?.contentModificationDate, mtime >= dayStart else { continue }
            if let size = values?.fileSize, size > 150_000_000 { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            var counted = false
            for line in text.split(separator: "\n") where line.contains("\"usage\"") {
                // 与本地今天零点比。两边同一种定长 UTC 写法，字典序即时间序。
                guard let ts = timestamp(in: line), ts >= cutoff else { continue }
                // 四种都要算。早前只加 input+output，把缓存读漏掉了 —— 而缓存读通常比它们
                // 大两个数量级，于是那个数字比真实用量小得离谱，也没法和 Codex 比。
                tool.input += firstInt(after: "\"input_tokens\":", in: line) ?? 0
                tool.output += firstInt(after: "\"output_tokens\":", in: line) ?? 0
                tool.cacheWrite += firstInt(after: "\"cache_creation_input_tokens\":", in: line) ?? 0
                tool.cacheRead += firstInt(after: "\"cache_read_input_tokens\":", in: line) ?? 0
                counted = true
            }
            if counted { tool.sessions += 1 }
        }
        return tool
    }

    // MARK: - Codex (~/.codex/sessions/YYYY/MM/DD/*.jsonl)

    private static func scanCodex() -> (ToolUsage, [UsageWindow]) {
        var tool = ToolUsage()
        var windows: [UsageWindow] = []

        let dayStart = todayStart()
        let cutoff = timestampString(dayStart)
        let root = home.appendingPathComponent(".codex/sessions")
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return (tool, windows)
        }

        // 路径里的日期是会话**建**在哪天，不是它**活动**在哪天 —— resume 会往老目录里接着写，
        // 见过一个 7/20 建的会话一路活到 7/29。所以不挑目录，挑「今天动过的文件」：
        // 改动时间早于今天零点的，里面不可能有今天的事件。
        var files: [(url: URL, mtime: Date)] = []
        for case let url as URL in en {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let mtime = values?.contentModificationDate, mtime >= dayStart else { continue }
            if let size = values?.fileSize, size > 150_000_000 { continue }
            files.append((url, mtime))
        }
        // 按改动先后排，好让最后读到的那份是最新的 —— 限流状态取最后一份。
        files.sort { $0.mtime < $1.mtime }

        for (url, _) in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let usage = codexUsage(in: text, since: cutoff)
            if !usage.isEmpty {
                tool.sessions += usage.sessions
                tool.input += usage.input
                tool.output += usage.output
                tool.cacheWrite += usage.cacheWrite
                tool.cacheRead += usage.cacheRead
            }
            // 限流状态：最后一条 rate_limits 就是此刻的状态，后来的覆盖先前的。
            if let latest = codexWindows(in: text) { windows = latest }
        }
        return (tool, windows)
    }

    /// 一个会话文件里，落在 `cutoff` 之后的那部分用量。
    ///
    /// `token_count` 事件带的 `total_token_usage` 是**会话开天辟地以来**的累计，早前取最后
    /// 一条，得到的是整个会话 —— 而会话可以被 resume 很多天。于是同一个数字既漏又多：
    /// 活动在今天但建在上周的会话，目录不对，整个漏掉；建在今天的长会话，则把前几天的量
    /// 一并算进今天。
    ///
    /// 这里改成取差：切点前最后一份累计值当基线，用最终值减掉它，剩下的才是今天新花的。
    /// 累计值是单调的，所以减法成立；一天都没动过的会话减出来是零，自然不计。
    static func codexUsage(in text: String, since cutoff: String) -> ToolUsage {
        var base: CodexTotals?      // 今天开始之前，这个会话已经花掉的
        var latest: CodexTotals?    // 到眼下为止的累计
        var active = false          // 今天到底动过没有

        for line in text.split(separator: "\n") where line.contains("\"total_token_usage\"") {
            guard let ts = timestamp(in: line), let totals = codexTotals(in: line) else { continue }
            if ts < cutoff { base = totals } else { active = true }
            latest = totals
        }
        guard active, let latest else { return ToolUsage() }

        let start = base ?? CodexTotals()
        var usage = ToolUsage()
        usage.sessions = 1
        // Codex 的 input_tokens 已经含了缓存读，cached_input_tokens 是其中的一部分，
        // 所以拆出来单独记，再从 input 里减掉 —— 不减就会把缓存那部分算两遍。
        let input = max(latest.input - start.input, 0)
        let cached = max(latest.cached - start.cached, 0)
        usage.input = max(input - cached, 0)
        usage.cacheRead = cached
        usage.cacheWrite = max(latest.cacheWrite - start.cacheWrite, 0)
        usage.output = max(latest.output - start.output, 0)
        return usage
    }

    /// 一条 `token_count` 事件里的会话累计值。
    struct CodexTotals: Equatable {
        var input = 0
        var cached = 0
        var cacheWrite = 0
        var output = 0
    }

    /// 只认 `total_token_usage` 那一段 —— 同一行里紧跟着还有个 `last_token_usage`，
    /// 字段名一模一样，从行首找会摸到哪个全看运气。
    private static func codexTotals(in line: some StringProtocol) -> CodexTotals? {
        guard let r = line.range(of: "\"total_token_usage\":") else { return nil }
        let slice = line[r.upperBound...].prefix(300)
        guard let input = firstInt(after: "\"input_tokens\":", in: slice) else { return nil }
        return CodexTotals(input: input,
                           cached: firstInt(after: "\"cached_input_tokens\":", in: slice) ?? 0,
                           cacheWrite: firstInt(after: "\"cache_write_input_tokens\":", in: slice) ?? 0,
                           output: firstInt(after: "\"output_tokens\":", in: slice) ?? 0)
    }

    /// 从 rollout 日志里取最后一次 `rate_limits`。primary / secondary 两个窗口都要 ——
    /// 窗口长度由日志里的 `window_minutes` 说了算，不写死「周额度」。
    private static func codexWindows(in text: String) -> [UsageWindow]? {
        guard let range = text.range(of: "\"rate_limits\":", options: .backwards) else { return nil }
        let tail = String(text[range.upperBound...].prefix(700))
        var windows: [UsageWindow] = []
        for key in ["\"primary\":", "\"secondary\":"] {
            guard let r = tail.range(of: key) else { continue }
            let slice = tail[r.upperBound...].prefix(200)
            guard let percent = firstDouble(after: "\"used_percent\":", in: slice),
                  let minutes = firstInt(after: "\"window_minutes\":", in: slice) else { continue }
            let resets = firstInt(after: "\"resets_at\":", in: slice).map {
                Date(timeIntervalSince1970: TimeInterval($0))
            }
            windows.append(UsageWindow(name: UsageLimits.windowName(minutes: minutes),
                                       percent: percent, resetsAt: resets))
        }
        return windows.isEmpty ? nil : windows
    }

    // MARK: - Helpers

    private static func firstInt(after key: String, in text: some StringProtocol) -> Int? {
        guard let r = text.range(of: key) else { return nil }
        let digits = text[r.upperBound...].prefix(while: { $0.isNumber })
        return Int(digits)
    }

    private static func firstDouble(after key: String, in text: some StringProtocol) -> Double? {
        guard let r = text.range(of: key) else { return nil }
        let chars = text[r.upperBound...].prefix(while: { $0.isNumber || $0 == "." })
        return Double(chars)
    }
}

#endif
