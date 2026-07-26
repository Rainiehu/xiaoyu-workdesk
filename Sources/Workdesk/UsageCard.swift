import SwiftUI

/// 侧边栏底部的小卡片：两个工具今日的 token 用量，各自的限流窗口还剩多少。
///
/// 两件事分两行说：粗体那行是「今天花了多少」，底下细条是「离限流还有多远」。
/// 前者来自本地日志，后者 Claude 走接口、Codex 走它自己的 rollout 日志。
struct UsageCard: View {
    @Environment(Store.self) private var store
    /// 每分钟自己重扫一次。窗口以小时计，这个频率足够，也不至于让界面上的数字像秒表。
    @State private var ticker = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if store.usage == nil && store.usageLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("扫描中…").font(.caption).foregroundStyle(.tertiary)
                }
            } else if let u = store.usage {
                tool(dot: .orange, name: "Claude Code", usage: u.claude,
                     windows: u.claudeWindows, problem: u.claudeLimitsProblem)
                tool(dot: .indigo, name: "Codex", usage: u.codex, windows: u.codexWindows)
                if let spend = u.extraSpend { extraSpendRow(spend) }
            } else {
                Text("暂无数据").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.4)))
        .task {
            // 一直重扫，直到卡片从界面上消失。间隔写在 Store 里，两处不会各说各的。
            while !Task.isCancelled {
                store.refreshUsage()
                try? await Task.sleep(for: .seconds(Store.usageRefreshInterval))
                ticker = .now
            }
        }
    }

    private var header: some View {
        HStack {
            Text("AI 用量 · 今日")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            // 上次扫完到现在多久。数字自己会动，所以得让人看得出它是什么时候的。
            if let scannedAt = store.usage?.scannedAt {
                Text(agoText(scannedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Button { store.refreshUsage() } label: {
                Image(systemName: "arrow.clockwise").font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(store.usageLoading)
            .help("立刻重新扫描")
        }
    }

    /// 一个工具：名字与今日总量一行，底下每个限流窗口各一条。
    @ViewBuilder
    private func tool(dot: Color, name: String, usage: ToolUsage,
                      windows: [UsageWindow], problem: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(name).font(.caption)
                Spacer()
                if usage.isEmpty {
                    Text("—").font(.caption).foregroundStyle(.tertiary)
                } else {
                    Text("\(usage.total.tokenString) tok")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        // 细分放在悬停里：卡片上要的是一个总数，追究细节是偶尔的事。
                        .help("""
                        \(usage.sessions) 个会话
                        输入 \(usage.input.tokenString) · 输出 \(usage.output.tokenString)
                        缓存读 \(usage.cacheRead.tokenString) · 缓存写 \(usage.cacheWrite.tokenString)
                        """)
                }
            }
            ForEach(windows) { window in
                windowRow(window, tint: dot)
            }
            if let problem, windows.isEmpty {
                Text(problem)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 12)
            }
        }
    }

    /// 一个限流窗口：名字、进度条、百分比，外加还有多久重置。
    private func windowRow(_ window: UsageWindow, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(window.name)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .leading)
            ProgressView(value: min(window.percent, 100), total: 100)
                .tint(window.isTight ? .red : tint)
                .controlSize(.small)
            Text(window.percent.percentString)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(window.isTight ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.leading, 12)
        .help(window.resetText(from: ticker) ?? "\(window.name)窗口")
    }

    /// 额外用量：撞上套餐限额之后按钱计的那部分。只在开着的时候出现。
    private func extraSpendRow(_ spend: ExtraSpend) -> some View {
        HStack(spacing: 6) {
            Text("额外用量")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("\(money(spend.used)) / \(money(spend.limit))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 1)
        .help("按 \(spend.currency) 计，已用 \(spend.percent.percentString)")
    }

    private func money(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    /// 「刚刚 / 3 分钟前」。超过一小时就不再数分钟了 —— 那时它多久前扫的已经不重要，
    /// 重要的是它早该重扫了。
    private func agoText(_ date: Date) -> String {
        let seconds = Int(ticker.timeIntervalSince(date))
        if seconds < 90 { return "刚刚" }
        let minutes = seconds / 60
        return minutes < 60 ? "\(minutes) 分钟前" : "\(minutes / 60) 小时前"
    }
}
