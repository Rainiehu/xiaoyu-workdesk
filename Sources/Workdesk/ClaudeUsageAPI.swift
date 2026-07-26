import Foundation

/// 取 Claude 的限流状态。
///
/// 这份数据**不在本地任何文件里** —— `~/.claude/projects/**.jsonl` 只记每次调用花了多少 token，
/// 没有任何配额字段。`/usage` 显示的百分比来自 `/api/oauth/usage`，要带 OAuth token 调。
/// 于是本地日志负责「用了多少」，这个接口负责「还剩多少」，两件事各有各的来源。
enum ClaudeUsageAPI {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// 凭证在钥匙串里的条目名，由 Claude Code 自己写入。
    private static let keychainService = "Claude Code-credentials"

    struct Result: Sendable {
        var windows: [UsageWindow] = []
        var spend: ExtraSpend?
        /// 没拿到时说明为什么。说出来比让卡片默默空着强。
        var problem: String?
        /// 被限流了。调用方据此退避 —— 接着按原节奏问只会一直被挡在门外。
        var isRateLimited = false
    }

    static func fetch() async -> Result {
        guard let token = accessToken() else {
            return Result(problem: "读不到 Claude Code 的登录凭证")
        }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("workdesk/0.1", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            // token 是 Claude Code 在维护的，过期了得它去续 —— 这里只能说清楚，不能代劳。
            if code == 401 { return Result(problem: "凭证已过期，在 Claude Code 里重新登录即可") }
            // 这个接口问太勤会被挡。响应里的 retry-after 给的是 0，不足为凭，退避多久由调用方定。
            if code == 429 { return Result(problem: "问得太勤，稍后自动重试", isRateLimited: true) }
            guard code == 200 else { return Result(problem: "接口返回 \(code)") }
            let parsed = UsageLimits.parseClaudeUsage(data)
            return Result(windows: parsed.windows, spend: parsed.spend)
        } catch {
            return Result(problem: "连不上 Anthropic")
        }
    }

    /// 从钥匙串取 access token。
    ///
    /// 刻意走 `/usr/bin/security` 这个子进程，而不是直接调 Security 框架：钥匙串条目的授权
    /// 是绑在**调用方的代码签名**上的。直接调框架，调用方就是本应用，而它每次重新签名都会被当成
    /// 另一个程序，于是每次重建后都要再授权一次；`security` 是 Apple 签的、签名不变，
    /// 授权过一次就一直有效。
    ///
    /// 代价是这个授权对所有调用 `security` 的进程都成立 —— 本机个人工具，这个交换划得来。
    private static func accessToken() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return findAccessToken(in: try? JSONSerialization.jsonObject(with: data))
    }

    /// 凭证 JSON 的形状由 Claude Code 定，不归我们管，所以不硬编码路径 ——
    /// 认名字里带 accessToken 的那个字符串，它挪了窝也还找得到。
    private static func findAccessToken(in object: Any?) -> String? {
        guard let dict = object as? [String: Any] else { return nil }
        for (key, value) in dict {
            if key.lowercased().contains("accesstoken"), let token = value as? String, !token.isEmpty {
                return token
            }
            if let found = findAccessToken(in: value) { return found }
        }
        return nil
    }
}
