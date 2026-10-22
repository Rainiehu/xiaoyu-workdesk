import Foundation

/// 取 Claude 的限流状态。
///
/// 这份数据**不在本地任何文件里** —— `~/.claude/projects/**.jsonl` 只记每次调用花了多少 token，
/// 没有任何配额字段。`/usage` 显示的百分比来自 `/api/oauth/usage`，要带 OAuth token 调。
/// 于是本地日志负责「用了多少」，这个接口负责「还剩多少」，两件事各有各的来源。
#if os(macOS)
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
        let found = Self.credential()
        guard case .token(let token) = found else {
            return Result(problem: found.problem)
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

    /// 钥匙串那段 JSON 到底算不算有凭证。
    ///
    /// 分开几种说，而不是笼统一句「读不到」：卡片上那行字是给人看的，而最常见的实情并不是程序
    /// 读失败 —— 条目好端端在钥匙串里，里头的 token 是空串。CLI 的那份过期之后会被清空，
    /// 桌面版的登录又不走这条路，于是「有条目、没凭证」才是常态。说清是哪一种，
    /// 看的人才知道下一步该干什么。
    enum Credential: Equatable {
        case token(String)
        /// 钥匙串里压根没有这条目。
        case missing
        /// 条目在，却一个非空 token 也没有 —— 没登录。
        case loggedOut
        /// 条目在，但不是认得的形状。
        case unreadable
        /// 条目也许在，钥匙串却没放行（授权框上点了拒绝，或 `security` 根本没跑起来）。
        /// 与「没有条目」分开说：这时该做的是重试时点允许，不是再登录一遍。
        case inaccessible

        /// 卡片上那一行。真有凭证时没话说。
        var problem: String? {
            switch self {
            case .token: nil
            // 不带工具名：行头上就写着 Claude Code，再说一遍只会把这行挤成两行。
            case .missing: "钥匙串里没有凭证"
            case .loggedOut: "未登录 · 在终端登录一次"
            case .unreadable: "凭证的格式不认得"
            case .inaccessible: "钥匙串没放行 · 重试时点允许"
            }
        }
    }

    /// `security` 找不到条目时的退出码（errSecItemNotFound 截到一个字节）。
    private static let itemNotFoundStatus: Int32 = 44

    /// 跑一趟 `security` 把那段 JSON 取回来。只有退出码 44（找不到条目）才算没这条目，
    /// 其余的失败都是钥匙串没放行。
    ///
    /// 刻意走 `/usr/bin/security` 这个子进程，而不是直接调 Security 框架：钥匙串条目的授权
    /// 是绑在**调用方的代码签名**上的。直接调框架，调用方就是本应用，而它每次重新签名都会被当成
    /// 另一个程序，于是每次重建后都要再授权一次；`security` 是 Apple 签的、签名不变，
    /// 授权过一次就一直有效。
    ///
    /// 代价是这个授权对所有调用 `security` 的进程都成立 —— 本机个人工具，这个交换划得来。
    private static func credential() -> Credential {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return .inaccessible }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        switch task.terminationStatus {
        case 0: return credential(in: data)
        case Self.itemNotFoundStatus: return .missing
        default: return .inaccessible
        }
    }

    /// 在钥匙串那段 JSON 里认凭证。
    ///
    /// **名字里带 claude 的那一支先找。** 同一份 JSON 里还躺着一堆 MCP 服务器各自的
    /// `accessToken`（`mcpOAuth` 底下，每个 connector 一份）。不分先后地撞见哪个算哪个，
    /// 取到的就是字典序碰巧排在前面的那个 —— 哪天某个 connector 授权了，发出去的可能是它的
    /// token，接口回 401，而卡片会指着一份没过期的凭证喊「已过期」。
    ///
    /// 带 claude 名字的根键可能不止一支（哪天多出个设置项也叫 claude 什么），所以按名字排好、
    /// 逐支去找，第一个非空的算数 —— 结果不随字典的散列顺序变。`claudeAiOauth` 是今天的真名，
    /// 排在最前。
    static func credential(in data: Data) -> Credential {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return .unreadable }
        let root = object as? [String: Any] ?? [:]
        let claudeBranches = root.keys
            .filter { $0.lowercased().contains("claude") }
            .sorted { ($0 == "claudeAiOauth" ? 0 : 1, $0) < ($1 == "claudeAiOauth" ? 0 : 1, $1) }
            .map { root[$0] as Any }
        // 找得到带 claude 名字的那一支，就**只认它们**：它们空着的时候，
        // 正确答案是「没登录」，而不是从隔壁 MCP 那儿借一个 token 发出去。
        // 连一支都没有：形状兴许又挪了窝，这才值得全局找一遍。
        let searched = claudeBranches.isEmpty ? [object] : claudeBranches
        var sawTokenKey = false
        for branch in searched {
            if let token = accessToken(in: branch, sawKey: &sawTokenKey) { return .token(token) }
        }
        return sawTokenKey ? .loggedOut : .unreadable
    }

    /// 认名字里带 accessToken 的那个非空字符串 —— 凭证 JSON 的形状由 Claude Code 定，
    /// 不归我们管，所以不硬编码路径，它挪了窝也还找得到。数组也钻进去：形状既然不归我们管，
    /// 就不该假定它一路都是字典。
    ///
    /// `sawKey` 记的是「见没见过这个名字」。见过、却一个非空的也没有，那是没登录，
    /// 与「形状完全不认得」是两回事，卡片上说的话也不一样。
    private static func accessToken(in object: Any?, sawKey: inout Bool) -> String? {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                if key.lowercased().contains("accesstoken") {
                    sawKey = true
                    if let token = value as? String, !token.isEmpty { return token }
                }
                if let found = accessToken(in: value, sawKey: &sawKey) { return found }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = accessToken(in: value, sawKey: &sawKey) { return found }
            }
        }
        return nil
    }
}

#endif
