import Foundation

/// 扫描本机 Claude Code / Codex 的会话日志，统计今日 token 用量。
///
/// 日志只说「用了多少」。Claude 的「还剩多少」得走 `ClaudeUsageAPI`；Codex 则把限流状态
/// 一并写在 rollout 日志里，这里顺手取了。
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

    /// 一个会话文件里最后一次事件的时间戳。用来判断这个会话是不是落在本地今天。
    private static func lastTimestamp(in text: String) -> String? {
        guard let r = text.range(of: "\"timestamp\":\"", options: .backwards) else { return nil }
        let rest = text[r.upperBound...]
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

        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        f.timeZone = TimeZone(identifier: "UTC")
        let dayStart = todayStart()

        // 目录是按 **UTC** 日期分的，而我们要的是**本地**今天 —— 在时区偏移不为零的地方，
        // 本地的一天必然横跨两个 UTC 目录，所以昨天那个也得看。
        let dirs = [Date.now, dayStart].map {
            home.appendingPathComponent(".codex/sessions/\(f.string(from: $0))")
        }
        let files = Set(dirs).flatMap { dir in
            ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "jsonl" }
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        let cutoff = timestampString(dayStart)
        for url in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // 昨天那个 UTC 目录里也有本地今天之前就结束的会话，把它们挡掉。
            // 这里按会话整体算：跨过本地午夜的那个会话会被整个计入 —— 取的是会话累计值，
            // 本来就没法拆到某一天，宁可多算这一个也好过把它整个丢掉。
            guard let last = lastTimestamp(in: text), last >= cutoff else { continue }
            // 每个 token_count 事件带会话累计值，取最后一条即整个会话的用量。
            guard let range = text.range(of: "\"total_token_usage\":", options: .backwards) else { continue }
            let tail = text[range.upperBound...].prefix(400)
            tool.sessions += 1
            // Codex 的 input_tokens 已经含了缓存读，cached_input_tokens 是其中的一部分，
            // 所以拆出来单独记，再从 input 里减掉 —— 不减就会把缓存那部分算两遍。
            let input = firstInt(after: "\"input_tokens\":", in: tail) ?? 0
            let cached = firstInt(after: "\"cached_input_tokens\":", in: tail) ?? 0
            tool.input += max(input - cached, 0)
            tool.cacheRead += cached
            tool.cacheWrite += firstInt(after: "\"cache_write_input_tokens\":", in: tail) ?? 0
            tool.output += firstInt(after: "\"output_tokens\":", in: tail) ?? 0

            // 限流状态：最后一条 rate_limits 就是此刻的状态，后来的覆盖先前的。
            if let latest = codexWindows(in: text) { windows = latest }
        }
        return (tool, windows)
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
