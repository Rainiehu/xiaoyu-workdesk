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
