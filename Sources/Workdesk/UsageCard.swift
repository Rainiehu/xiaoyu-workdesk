import SwiftUI
import WorkdeskCore

/// 侧边栏底部的小卡片：两个工具今日的 token 用量，各自的限流窗口还剩多少。
///
/// 两件事分两行说：粗体那行是「今天花了多少」，底下细条是「离限流还有多远」。
/// 前者来自本地日志，后者两家都走各自的接口 —— Codex 拿不到接口时退回 rollout 日志里的快照。
struct UsageCard: View {
    @Environment(Store.self) private var store
    /// 每分钟自己重扫一次。窗口以小时计，这个频率足够，也不至于让界面上的数字像秒表。
    @State private var ticker = Date.now

    /// 刷新图标转到的角度。只增不减、每次只加整圈 —— 箭头停下来永远是正位。
    @State private var spinAngle = 0.0
    /// 圈的接力棒正在手上：completion 链跑着的时候不再另起一条，免得两条链叠着转出双倍速。
    @State private var spinning = false

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
                tool(dot: .indigo, name: "Codex", usage: u.codex,
                     windows: u.codexWindows, problem: u.codexLimitsProblem)
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

    /// 转一整圈，转完还在扫就接着转。有限的圈首尾相接，而不是 repeatForever ——
    /// 那种动画是顶不掉的（后起的曲线动画跟它并行叠加，不替换），一旦请上就请不走了。
    /// 一圈起步也正好解决「快扫描一眨眼就完」：真正的停点永远落在整圈末尾，
    /// 再快的一次刷新也看得见一次完整旋转。
    private func spinTurn() {
        spinning = true
        withAnimation(.linear(duration: 0.8)) {
            spinAngle += 360
        } completion: {
            if store.usageLoading { spinTurn() } else { spinning = false }
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
            // 手动点就是要它现在去问，越过接口自己那套节奏。
            Button { store.refreshUsage(force: true) } label: {
                Image(systemName: "arrow.clockwise").font(.caption2)
                    .rotationEffect(.degrees(spinAngle))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(store.usageLoading)
            .help("立刻重新扫描并查限流")
            // 扫着、问着的那一会儿图标转圈 —— 点了按钮界面却纹丝不动，看着就像坏的。
            // 每分钟的例行重扫转的也是这同一个圈：图标只说一件事，「这一刻正在干活」。
            // initial 也接：卡片重建时若刷新正在飞，圈从露面那一刻就该转着。
            .onChange(of: store.usageLoading, initial: true) { _, loading in
                if loading && !spinning { spinTurn() }
            }
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
