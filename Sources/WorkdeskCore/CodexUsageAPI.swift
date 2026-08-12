import Foundation

/// 取 Codex 的限流状态。
///
/// rollout 日志里的 `rate_limits` 只是**写下当刻**的快照 —— 周额度是整个账号共用的，
/// 云端任务、别的设备的用量都算在里面，本地不跑 Codex，快照就停在旧数字上。
/// 见过快照停在 9% 而账号实际已用到 37% 的。所以照 Claude 的样子直接问服务端，
/// 这个接口就是 Codex 桌面版「剩余用量」那块的数据来源；日志里的快照降级成备胎。
#if os(macOS)
enum CodexUsageAPI {
    private static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    struct Result: Sendable {
        var windows: [UsageWindow] = []
        /// 没拿到时说明为什么。说出来比让卡片默默空着强。
        var problem: String?
        /// 被限流了。调用方据此退避 —— 接着按原节奏问只会一直被挡在门外。
        var isRateLimited = false
    }

    static func fetch() async -> Result {
        guard let auth = credentials() else {
            return Result(problem: "读不到 Codex 的登录凭证")
        }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        request.setValue(auth.accountId, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue("workdesk/0.1", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            // token 是 Codex 在维护的，过期了得它去续 —— 这里只能说清楚，不能代劳。
            if code == 401 { return Result(problem: "凭证已过期，在 Codex 里重新登录即可") }
            if code == 429 { return Result(problem: "问得太勤，稍后自动重试", isRateLimited: true) }
            guard code == 200 else { return Result(problem: "接口返回 \(code)") }
            return Result(windows: UsageLimits.parseCodexUsage(data))
        } catch {
            return Result(problem: "连不上 OpenAI")
        }
    }

    /// 凭证在 `~/.codex/auth.json` 里，Codex 自己写入、自己续期。
    /// 明文文件，不像 Claude 那样要过钥匙串的授权，直接读即可。
    private static func credentials() -> (token: String, accountId: String)? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty,
              let account = tokens["account_id"] as? String, !account.isEmpty else { return nil }
        return (token, account)
    }
}

#endif
