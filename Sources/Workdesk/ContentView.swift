import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case mainline = "主线"
    case favorites = "收藏流"

    var id: Self { self }

    var icon: String {
        switch self {
        case .mainline: "checklist"
        case .favorites: "bookmark"
        }
    }
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(TodayClock.self) private var clock
    @Environment(CloudSync.self) private var sync
    @State private var selection: SidebarSection? = .mainline

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(SidebarSection.allCases) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .badge(badge(for: section))
                            .tag(section)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)

                Spacer(minLength: 0)
                if let trouble = sync.trouble {
                    SyncTroubleMark(trouble: trouble)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                }
                UsageCard()
                    .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            switch selection ?? .mainline {
            case .mainline: MainlineView()
            case .favorites: FavoritesView()
            }
        }
        // 「今天」从这儿开始一直守着，直到界面消失 —— 挂在最外层而不是沙漏视图上：
        // 眼下开着的是哪一屏跟日子过没过天无关，切到收藏流去也不该把它停掉。
        .task { await clock.watch() }
    }

    private func badge(for section: SidebarSection) -> Int {
        switch section {
        case .mainline: store.unfinishedTodoCount
        case .favorites: 0
        }
    }
}

/// 侧边栏底部那个低调的同步记号。日常它不存在；只在持久性故障时出现 ——
/// 与过期琥珀同一副分寸：不冒泡、不弹窗，就一行灰色小字，点开才见原因。
/// 连颜色都不给 —— 它是个可查的事实，不是一个要人处理的警报。
struct SyncTroubleMark: View {
    let trouble: SyncTrouble
    @State private var showingReason = false

    var body: some View {
        Button {
            showingReason.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "icloud.slash")
                Text("同步停着")
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("同步遇到了点事，点开看看")
        .popover(isPresented: $showingReason, arrowEdge: .trailing) {
            Text(trouble.explanation)
                .font(.callout)
                .lineSpacing(3)
                .padding(16)
                .frame(width: 260, alignment: .leading)
        }
    }
}
