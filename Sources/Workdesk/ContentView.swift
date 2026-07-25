import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case today = "今日待办"
    case history = "历史"
    case favorites = "收藏流"

    var id: Self { self }

    var icon: String {
        switch self {
        case .today: "checkmark.circle"
        case .history: "clock.arrow.circlepath"
        case .favorites: "bookmark"
        }
    }
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @State private var selection: SidebarSection? = .today

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
            switch selection ?? .today {
            case .today: TodayView()
            case .history: HistoryView()
            case .favorites: FavoritesView()
            }
        }
        .task { store.refreshUsage() }
    }

    private func badge(for section: SidebarSection) -> Int {
        switch section {
        case .today: store.todayTodos.filter { !$0.done }.count + store.overdueTodos.count
        case .favorites: 0
        case .history: 0
        }
    }
}
