import Foundation

struct UsageSnapshot: Sendable {
    struct Tool: Sendable {
        var sessions = 0
        var inputTokens = 0
        var outputTokens = 0
        var totalTokens: Int { inputTokens + outputTokens }
    }

    var claude = Tool()
    var codex = Tool()
    /// Codex 周额度已用百分比（来自 rollout 日志里的 rate_limits）
    var codexWeeklyUsedPercent: Double?
    var scannedAt: Date = .now
}

/// 扫描本机 Claude Code / Codex 的会话日志，统计今日 token 用量。
enum UsageScanner {
    static func scan() -> UsageSnapshot {
        var snap = UsageSnapshot()
        snap.claude = scanClaude()
        (snap.codex, snap.codexWeeklyUsedPercent) = scanCodex()
        return snap
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private static var todayPrefix: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: .now)
    }

    // MARK: - Claude Code (~/.claude/projects/**/*.jsonl)

    private static func scanClaude() -> UsageSnapshot.Tool {
        var tool = UsageSnapshot.Tool()
        let root = home.appendingPathComponent(".claude/projects")
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return tool }

        let dayStart = Date().dayStart
        for case let url as URL in en {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let mtime = values?.contentModificationDate, mtime >= dayStart else { continue }
            if let size = values?.fileSize, size > 150_000_000 { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            var counted = false
            // 日志里 timestamp 是 UTC；按 UTC 的“今天”过滤各行
            let prefix = "\"timestamp\":\"\(todayPrefix)"
            for line in text.split(separator: "\n") where line.contains(prefix) && line.contains("\"usage\"") {
                tool.outputTokens += firstInt(after: "\"output_tokens\":", in: line) ?? 0
                tool.inputTokens += firstInt(after: "\"input_tokens\":", in: line) ?? 0
                counted = true
            }
            if counted { tool.sessions += 1 }
        }
        return tool
    }

    // MARK: - Codex (~/.codex/sessions/YYYY/MM/DD/*.jsonl)

    private static func scanCodex() -> (UsageSnapshot.Tool, Double?) {
        var tool = UsageSnapshot.Tool()
        var usedPercent: Double?

        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        f.timeZone = TimeZone(identifier: "UTC")
        let dir = home.appendingPathComponent(".codex/sessions/\(f.string(from: .now))")

        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // 每个 token_count 事件带会话累计值，取最后一条即整个会话的用量
            guard let range = text.range(of: "\"total_token_usage\":", options: .backwards) else { continue }
            let tail = text[range.upperBound...].prefix(400)
            tool.sessions += 1
            tool.inputTokens += firstInt(after: "\"input_tokens\":", in: tail) ?? 0
            tool.outputTokens += firstInt(after: "\"output_tokens\":", in: tail) ?? 0
            if let pRange = text.range(of: "\"used_percent\":", options: .backwards) {
                let pTail = text[pRange.upperBound...].prefix(32)
                if let p = firstDouble(in: pTail) { usedPercent = p }
            }
        }
        return (tool, usedPercent)
    }

    // MARK: - Helpers

    private static func firstInt(after key: String, in text: some StringProtocol) -> Int? {
        guard let r = text.range(of: key) else { return nil }
        let digits = text[r.upperBound...].prefix(while: { $0.isNumber })
        return Int(digits)
    }

    private static func firstDouble(in text: some StringProtocol) -> Double? {
        let chars = text.prefix(while: { $0.isNumber || $0 == "." })
        return Double(chars)
    }
}
