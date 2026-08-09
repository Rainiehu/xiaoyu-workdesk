import SwiftUI
import WorkdeskCore

/// 侧边栏底部常驻的同步记号。三态只换云的形态，平时一个字不说；
/// 悬停浮出一句相对时间，点开才见详情 —— 与过期琥珀同一副分寸：常驻但不吵。
/// 它是个可查的事实，不是一个要人处理的警报，所以停着也不上色。
struct SyncStatusMark: View {
    let status: SyncStatus
    @State private var hovering = false
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: status.symbolName)
                    .foregroundStyle(iconStyle)
                if hovering || showingDetail {
                    // 相对时间在露面的那一刻现算。这儿问的是时刻不是日子，不归 TodayClock 管；
                    // 悬停一次算一次，也就不存在「挂着挂着说法过时了」。
                    Text(status.hoverLabel(now: .now))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $showingDetail, arrowEdge: .trailing) {
            Text(status.detail(now: .now))
                .font(.callout)
                .lineSpacing(3)
                .padding(16)
                .frame(width: 260, alignment: .leading)
        }
    }

    /// 在送的箭头取主调的青 —— 三态里唯一「正在动」的；其余与行尾的次要信息同灰。
    private var iconStyle: AnyShapeStyle {
        if case .sending = status { AnyShapeStyle(.teal) } else { AnyShapeStyle(.secondary) }
    }
}
