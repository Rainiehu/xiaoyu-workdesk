import SwiftUI

/// 侧边栏底部的小卡片：Claude Code / Codex 今日用量
struct UsageCard: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI 用量 · 今日")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.refreshUsage()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("重新扫描本地日志")
            }

            if store.usageLoading && store.usage == nil {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("扫描中…").font(.caption).foregroundStyle(.tertiary)
                }
            } else if let u = store.usage {
                row(dot: .orange, name: "Claude Code", tool: u.claude)
                row(dot: .indigo, name: "Codex", tool: u.codex)

                if let percent = u.codexWeeklyUsedPercent {
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(value: min(percent, 100), total: 100)
                            .tint(percent > 80 ? .red : .indigo)
                            .controlSize(.small)
                        Text("Codex 周额度已用 \(percent, specifier: "%.0f")%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 2)
                }
            } else {
                Text("暂无数据").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.4))
        )
    }

    private func row(dot: Color, name: String, tool: UsageSnapshot.Tool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(name).font(.caption)
            Spacer()
            if tool.sessions == 0 {
                Text("—").font(.caption).foregroundStyle(.tertiary)
            } else {
                Text("\(tool.totalTokens.tokenString) tok")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("\(tool.sessions) 个会话 · 输入 \(tool.inputTokens.tokenString) / 输出 \(tool.outputTokens.tokenString)")
            }
        }
    }
}
