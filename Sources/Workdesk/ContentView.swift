import SwiftUI
import WorkdeskCore

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
                // 常驻的同步记号。只在同步真开着的构建里挂 —— 单机构建不该挂一朵云说谎。
                if sync.active {
                    SyncStatusMark(status: SyncStatus(
                        trouble: sync.trouble,
                        sending: !store.syncLog.isEmpty,
                        lastSuccessAt: sync.lastSuccessAt
                    ))
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

