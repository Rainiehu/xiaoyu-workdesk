import Foundation

/// 一个工具的 token 用量。四种 token 分开记 —— 缓存读写往往比真正的输入输出大两个数量级，
/// 合成一个数字就看不出钱花在哪儿了。
struct ToolUsage: Equatable, Sendable {
    var sessions = 0
    var input = 0
    var output = 0
    /// 写进缓存的（Claude 的 `cache_creation_input_tokens`）
    var cacheWrite = 0
    /// 从缓存读的（Claude 的 `cache_read_input_tokens`）。日常用量里这一项通常最大。
    var cacheRead = 0

    var total: Int { input + output + cacheWrite + cacheRead }

    /// Codex 把缓存读算在 `input_tokens` 里面，Claude 分开报。都摊平成四项之后两边才可比 ——
    /// 早前的卡片只加 input+output，于是 Claude 少算了缓存那一大块，两个数字根本不是一回事。
    var isEmpty: Bool { total == 0 }
}

/// 一个限流窗口的状态：用掉百分之多少，什么时候重置。
/// 百分比是服务端给的，不是我们estimate的 —— 本地日志算得出用量，算不出上限。
struct UsageWindow: Equatable, Sendable, Identifiable {
    /// 窗口的叫法，直接显示：「5 小时」「7 天」。
    var name: String
    /// 0...100
    var percent: Double
    var resetsAt: Date?

    var id: String { name }
}

/// 额外用量：撞上套餐限额之后按钱计的那部分。
struct ExtraSpend: Equatable, Sendable {
    var percent: Double
    var used: Double
    var limit: Double
    var currency: String
}

struct UsageSnapshot: Sendable {
    var claude = ToolUsage()
    var codex = ToolUsage()
    /// Claude 的限流窗口，来自 `/api/oauth/usage`。拿不到时是空的。
    var claudeWindows: [UsageWindow] = []
    /// Codex 的限流窗口，来自 rollout 日志里的 `rate_limits`。
    var codexWindows: [UsageWindow] = []
    var extraSpend: ExtraSpend?
    /// Claude 的限流为什么没拿到。空表示拿到了 —— 说清楚比默默显示不出来强。
    var claudeLimitsProblem: String?
    var scannedAt: Date = .now
}

// MARK: - 解析

enum UsageLimits {
    /// 把窗口长度说成人话。Codex 用分钟数描述窗口，Claude 直接给命名窗口。
    static func windowName(minutes: Int) -> String {
        if minutes % (60 * 24) == 0 { return "\(minutes / (60 * 24)) 天" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时" }
        return "\(minutes) 分钟"
    }

    /// 解析 `/api/oauth/usage` 的返回。
    ///
    /// 只认 `five_hour` 和 `seven_day` 两个顶层窗口 —— 返回里还有一串按模型、按产品线细分的字段
    /// （`seven_day_opus`、`tangelo` 之类），眼下全是 null，等真有值了再说。
    /// 任何一个窗口缺了就跳过它，而不是让整次解析失败：拿到一个也比一个不拿好。
    static func parseClaudeUsage(_ data: Data) -> (windows: [UsageWindow], spend: ExtraSpend?) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return ([], nil)
        }
        var windows: [UsageWindow] = []
        for (key, name) in [("five_hour", "5 小时"), ("seven_day", "7 天")] {
            guard let w = root[key] as? [String: Any],
                  let percent = w["utilization"] as? Double else { continue }
            windows.append(UsageWindow(name: name, percent: percent,
                                       resetsAt: date(from: w["resets_at"])))
        }

        var spend: ExtraSpend?
        if let extra = root["extra_usage"] as? [String: Any],
           extra["is_enabled"] as? Bool == true,
           let percent = extra["utilization"] as? Double,
           let limit = extra["monthly_limit"] as? Double,
           let used = extra["used_credits"] as? Double {
            // 额度是以「分」计的整数，换算成通常写的那个数。
            let places = extra["decimal_places"] as? Int ?? 2
            let scale = pow(10.0, Double(places))
            spend = ExtraSpend(percent: percent, used: used / scale, limit: limit / scale,
                               currency: extra["currency"] as? String ?? "")
        }
        return (windows, spend)
    }

    /// ISO8601 带小数秒 —— 接口给的是 `2026-07-26T14:49:59.679695+00:00` 这种。
    private static func date(from value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

// MARK: - 显示

extension UsageWindow {
    /// 「还有 2 小时 14 分重置」这句话。已经过了就是 nil —— 那说明数据陈旧，不如什么都不说。
    func resetText(from now: Date) -> String? {
        guard let resetsAt, resetsAt > now else { return nil }
        let minutes = Int(resetsAt.timeIntervalSince(now) / 60)
        if minutes < 60 { return "\(max(minutes, 1)) 分钟后重置" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "\(hours) 小时后重置" : "\(hours) 小时 \(minutes % 60) 分后重置" }
        return "\(hours / 24) 天后重置"
    }

    /// 满了多少才算该留神。用色而不用图标 —— 一个感叹号会把这张安静的卡片变成告警面板。
    var isTight: Bool { percent >= 80 }
}

extension Double {
    /// 百分比写成整数，除非小到 1% 以下 —— 那时写 0% 会让人以为没在用。
    var percentString: String {
        self > 0 && self < 1 ? "<1%" : String(format: "%.0f%%", self)
    }
}
