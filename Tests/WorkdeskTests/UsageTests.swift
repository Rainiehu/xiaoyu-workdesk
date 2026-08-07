import Foundation
import Testing

@testable import Workdesk

@Suite("用量与限流")
struct UsageTests {
    /// `/api/oauth/usage` 的真实返回形状，数字改过。留着整份而不是精简版 ——
    /// 那一串眼下全是 null 的细分字段（seven_day_opus、tangelo…）正是解析要绕开的东西。
    static let claudeUsageJSON = """
    {"five_hour":{"utilization":19.0,"resets_at":"2026-07-26T14:49:59.679695+00:00",
     "limit_dollars":null,"used_dollars":null,"remaining_dollars":null},
     "seven_day":{"utilization":34.0,"resets_at":"2026-07-27T09:59:59.679715+00:00",
     "limit_dollars":null},
     "seven_day_opus":null,"tangelo":null,"nimbus_quill":null,
     "extra_usage":{"is_enabled":true,"monthly_limit":10000,"used_credits":3072.0,
     "utilization":30.72,"currency":"AUD","decimal_places":2,"user_disabled":false},
     "limits":[{"kind":"session","percent":19,"severity":"normal","is_active":false}],
     "member_dashboard_available":false}
    """.data(using: .utf8)!

    @Test("两个限流窗口都解析出来，百分比与重置时刻都在")
    func parsesBothWindows() throws {
        let (windows, _) = UsageLimits.parseClaudeUsage(Self.claudeUsageJSON)

        #expect(windows.map(\.name) == ["5 小时", "7 天"])
        #expect(windows.map(\.percent) == [19.0, 34.0])

        let fiveHour = try #require(windows.first)
        let resets = try #require(fiveHour.resetsAt)
        // 2026-07-26T14:49:59.679695Z —— 带小数秒，普通 ISO8601 解析器会在这儿栽跟头。
        #expect(abs(resets.timeIntervalSince1970 - 1785077399.679) < 1)
    }

    @Test("额外用量按 decimal_places 换算成通常写的那个数")
    func parsesExtraSpend() throws {
        let (_, spend) = UsageLimits.parseClaudeUsage(Self.claudeUsageJSON)

        let spend2 = try #require(spend)
        #expect(spend2.used == 30.72)   // 3072 分
        #expect(spend2.limit == 100)    // 10000 分
        #expect(spend2.currency == "AUD")
    }

    @Test("额外用量没开时就不显示，不是显示成零")
    func skipsDisabledExtraSpend() {
        let json = #"{"extra_usage":{"is_enabled":false,"monthly_limit":10000,"used_credits":0.0,"utilization":0.0}}"#
        let (_, spend) = UsageLimits.parseClaudeUsage(json.data(using: .utf8)!)
        #expect(spend == nil)
    }

    @Test("返回是空的或坏的，解析不炸，只是什么也没有")
    func survivesGarbage() {
        for bad in ["", "{}", "not json at all", #"{"five_hour":null}"#] {
            let (windows, spend) = UsageLimits.parseClaudeUsage(bad.data(using: .utf8)!)
            #expect(windows.isEmpty)
            #expect(spend == nil)
        }
    }

    @Test("窗口长度说成人话")
    func namesWindows() {
        #expect(UsageLimits.windowName(minutes: 300) == "5 小时")
        #expect(UsageLimits.windowName(minutes: 10080) == "7 天")
        #expect(UsageLimits.windowName(minutes: 45) == "45 分钟")
    }

    @Test("四种 token 都算进总量 —— 缓存那两项曾经被漏掉")
    func totalCountsCacheTokens() {
        let usage = ToolUsage(sessions: 1, input: 2, output: 524,
                              cacheWrite: 798, cacheRead: 214_421)
        #expect(usage.total == 215_745)
        // 只加 input+output 的老口径会得出 526 —— 差了四百倍。
        #expect(usage.total != usage.input + usage.output)
    }

    @Test("还有多久重置，说到分钟；已经过了就什么也不说")
    func describesReset() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func window(after seconds: TimeInterval) -> UsageWindow {
            UsageWindow(name: "5 小时", percent: 19, resetsAt: now.addingTimeInterval(seconds))
        }
        #expect(window(after: 30 * 60).resetText(from: now) == "30 分钟后重置")
        #expect(window(after: 2 * 3600).resetText(from: now) == "2 小时后重置")
        #expect(window(after: 2 * 3600 + 14 * 60).resetText(from: now) == "2 小时 14 分后重置")
        // 已经过去的重置时刻说明数据陈旧，那时不如闭嘴。
        #expect(window(after: -60).resetText(from: now) == nil)
    }

    @Test("被限流就翻倍退避，到封顶为止；一次成功就回到常规节奏")
    func backsOffWhenRateLimited() {
        let normal = Store.usageLimitsInterval

        // 第一次被挡，从常规间隔起步，之后每次翻倍。
        var backoff = Store.nextBackoff(from: 0, rateLimited: true)
        #expect(backoff == normal)
        backoff = Store.nextBackoff(from: backoff, rateLimited: true)
        #expect(backoff == normal * 2)
        backoff = Store.nextBackoff(from: backoff, rateLimited: true)
        #expect(backoff == normal * 4)

        // 一直被挡也不会无限往上涨 —— 封顶多少是可以调的，「有个顶」才是这条测的东西。
        for _ in 0..<20 { backoff = Store.nextBackoff(from: backoff, rateLimited: true) }
        let capped = backoff
        #expect(Store.nextBackoff(from: capped, rateLimited: true) == capped)
        #expect(capped >= normal)

        // 成功一次就清零 —— 下次仍按常规间隔，不带着上次的惩罚。
        #expect(Store.nextBackoff(from: backoff, rateLimited: false) == 0)
    }

    @Test("接口的节奏比本地扫描慢得多 —— 每分钟问一次真的会被 429")
    func limitsIntervalIsSlowerThanScan() {
        #expect(Store.usageLimitsInterval > Store.usageRefreshInterval)
    }

    @Test("「今日」按本地的今天算，不是 UTC 的今天")
    func todayIsLocal() {
        let now = Date.now
        let start = UsageScanner.todayStart(now: now)

        // 本地零点：和 Calendar 说的同一刻。UTC+10 那边这跟 UTC 零点差十个小时，
        // 早前按 UTC 筛，本地 00:00–10:00 干的活就整个丢了。
        #expect(start == Calendar.current.startOfDay(for: now))
        #expect(start <= now)
        #expect(now.timeIntervalSince(start) < 24 * 3600)
    }

    @Test("时间戳写成日志里那种定长 UTC 格式，好按字典序比")
    func formatsTimestampLikeTheLogs() {
        // 日志里长这样：2026-07-27T12:49:23.654Z
        let s = UsageScanner.timestampString(Date(timeIntervalSince1970: 1_785_156_563.654))
        #expect(s.hasSuffix("Z"))
        #expect(s.count == "2026-07-27T12:49:23.654Z".count)

        // 定长同格式，所以字典序就是时间序 —— 筛选靠这条成立，不必逐行解析日期。
        let earlier = UsageScanner.timestampString(Date(timeIntervalSince1970: 1_785_100_000))
        let later = UsageScanner.timestampString(Date(timeIntervalSince1970: 1_785_200_000))
        #expect(earlier < later)
    }

    /// 一条 Codex `token_count` 事件，真实形状。`total_token_usage` 后面紧跟着
    /// `last_token_usage`，字段名一模一样 —— 解析必须认准前一段。
    static func codexEvent(at ts: String, input: Int, cached: Int, output: Int) -> String {
        """
        {"timestamp":"\(ts)","type":"event_msg","payload":{"type":"token_count","info":\
        {"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),\
        "cache_write_input_tokens":0,"output_tokens":\(output),"reasoning_output_tokens":7,\
        "total_tokens":\(input + output)},\
        "last_token_usage":{"input_tokens":999999,"cached_input_tokens":999999,\
        "cache_write_input_tokens":0,"output_tokens":999999,"reasoning_output_tokens":9,\
        "total_tokens":999999},"model_context_window":258400}}}
        """
    }

    @Test("Codex 只算今天新花的，不把整个会话的累计当今天")
    func codexCountsOnlyToday() {
        // 一个前天建、今天又 resume 的会话：累计 5M，其中今天只花了 1M。
        let text = [
            Self.codexEvent(at: "2026-07-29T09:00:00.000Z", input: 4_000_000, cached: 3_800_000, output: 20_000),
            Self.codexEvent(at: "2026-07-30T01:00:00.000Z", input: 4_980_000, cached: 4_750_000, output: 30_000),
        ].joined(separator: "\n")

        let usage = UsageScanner.codexUsage(in: text, since: "2026-07-30T00:00:00.000Z")

        // 今天新花的：input 涨了 980k（其中缓存读 950k），output 涨了 10k。
        #expect(usage.cacheRead == 950_000)
        #expect(usage.input == 30_000)      // 980k 减去缓存那部分
        #expect(usage.output == 10_000)
        #expect(usage.total == 990_000)
        #expect(usage.sessions == 1)
        // 老口径会把整个会话的 5,010,000 全记到今天头上 —— 差了五倍。
        #expect(usage.total != 5_010_000)
    }

    @Test("会话建在今天，那今天就该是它的全部")
    func codexCountsWholeSessionWhenItStartedToday() {
        let text = [
            Self.codexEvent(at: "2026-07-30T01:00:00.000Z", input: 100_000, cached: 90_000, output: 500),
            Self.codexEvent(at: "2026-07-30T02:00:00.000Z", input: 300_000, cached: 280_000, output: 1_500),
        ].joined(separator: "\n")

        let usage = UsageScanner.codexUsage(in: text, since: "2026-07-30T00:00:00.000Z")

        #expect(usage.cacheRead == 280_000)
        #expect(usage.input == 20_000)
        #expect(usage.output == 1_500)
    }

    @Test("今天没动过的会话，一个 token 也不算")
    func codexIgnoresIdleSession() {
        let text = Self.codexEvent(at: "2026-07-29T09:00:00.000Z", input: 4_000_000, cached: 3_800_000, output: 20_000)

        let usage = UsageScanner.codexUsage(in: text, since: "2026-07-30T00:00:00.000Z")

        #expect(usage.isEmpty)
        #expect(usage.sessions == 0)   // 会话数也不能加 —— 它今天没出场
    }

    @Test("同一条事件里的 last_token_usage 不能被当成累计值读走")
    func codexReadsTotalNotLast() {
        // 两段字段名一模一样，从行首找会摸到哪个全看运气 —— 摸错就是 999999。
        let text = Self.codexEvent(at: "2026-07-30T01:00:00.000Z", input: 1_000, cached: 400, output: 50)

        let usage = UsageScanner.codexUsage(in: text, since: "2026-07-30T00:00:00.000Z")

        #expect(usage.total == 1_050)
    }

    @Test("百分比写成整数，但小于 1% 时不写成 0")
    func formatsPercent() {
        #expect(19.0.percentString == "19%")
        #expect(0.4.percentString == "<1%")
        #expect(0.0.percentString == "0%")
    }
}
