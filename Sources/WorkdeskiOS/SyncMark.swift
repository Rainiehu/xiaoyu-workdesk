#if os(iOS)
import SwiftUI
import WorkdeskCore

/// tab 条右端常驻的同步记号。三态只换云的形态，平时一个字不说；
/// 点开才见详情（「多久之前」写在里面）—— 触屏没有悬停，中间那一档并进详情里。
/// 它是个可查的事实，不是一个要人处理的警报，所以停着也不上色。
struct SyncMark: View {
    @Environment(Store.self) private var store
    @Environment(CloudSync.self) private var sync

    @State private var showingDetail = false

    var body: some View {
        let status = SyncStatus(
            trouble: sync.trouble,
            sending: !store.syncLog.isEmpty,
            lastSuccessAt: sync.lastSuccessAt
        )

        Button {
            showingDetail = true
        } label: {
            Image(systemName: status.symbolName)
                .font(.system(size: 14))
                .foregroundStyle(iconStyle(status))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingDetail) {
            Text(status.detail(now: .now))
                .font(.callout)
                .lineSpacing(3)
                .padding(16)
                .frame(width: 270, alignment: .leading)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("同步状态")
    }

    /// 在送的箭头取主调的青 —— 三态里唯一「正在动」的；其余与次要信息同灰。
    private func iconStyle(_ status: SyncStatus) -> AnyShapeStyle {
        if case .sending = status { AnyShapeStyle(.teal) } else { AnyShapeStyle(.secondary) }
    }
}
#endif
