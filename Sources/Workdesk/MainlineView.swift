import SwiftUI

/// tab 栏上的一项。沙漏是唯一不代表分类的那一项，永远排在首位。
enum MainlineTab: Hashable {
    case hourglass
    case category(Category.ID)
}

/// 主线：顶部一排 tab（首位是沙漏，其后是各个分类），下面是选中那一项的内容。
/// 一个分类都没有的时候（首次启动，或分类被删光），整个界面是一段引导 ——
/// 那时连一条待办都不可能有，时间轴也就无从铺起。
struct MainlineView: View {
    @Environment(Store.self) private var store
    /// 打开主线默认落在沙漏视图上，不落在任何分类里。
    @State private var selection: MainlineTab = .hourglass

    /// 选中的那个分类。选中沙漏时是 `nil`；选中的分类没了（被删了）也是 `nil` ——
    /// 于是「找不着分类」和「落回沙漏」是同一件事，只在这儿判一次。
    private var selectedCategory: Category? {
        guard case .category(let id) = selection else { return nil }
        return store.category(id)
    }

    /// 落到实处的选中项。分类没了就退回沙漏 —— 它永远在。
    private var selected: MainlineTab {
        selectedCategory.map { .category($0.id) } ?? .hourglass
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.categories.isEmpty {
                onboarding
            } else {
                MainlineTabBar(selected: selected) { selection = $0 }
                Divider()
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if let selectedCategory {
            CategoryTodoList(category: selectedCategory)
        } else {
            HourglassView()
        }
    }

    private var onboarding: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 40))
                .foregroundStyle(.teal.opacity(0.6))
            VStack(spacing: 6) {
                Text("还没有分类")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("待办按分类组织，从这里建第一个")
                    .foregroundStyle(.secondary)
            }
            // 刚建好第一个分类的人要的是往里记事，所以直接落到那个分类里，不留在沙漏上。
            NewCategoryButton(onCreate: { selection = .category($0.id) }) {
                Label("新建分类", systemImage: "plus")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.teal.opacity(0.15)))
                    .foregroundStyle(.teal)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tab 栏

struct MainlineTabBar: View {
    @Environment(Store.self) private var store
    /// 正在显示的那一项 —— 由主线算出来，好让高亮的 tab 和内容区永远是同一个。
    let selected: MainlineTab
    let select: (MainlineTab) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                HourglassTab(isSelected: selected == .hourglass) { select(.hourglass) }
                // 一道细竖线把沙漏和分类分开：它是唯一不代表分类的一项，这里就说明白。
                Divider().frame(height: 16)
                ForEach(store.categories) { category in
                    CategoryTab(category: category, isSelected: selected == .category(category.id)) {
                        select(.category(category.id))
                    }
                }
                NewCategoryButton(onCreate: { select(.category($0.id)) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .help("新建分类")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.never)
    }
}

/// 沙漏 tab：只有一个沙漏图标，不带文字。一排文字 tab 里就它没有字，
/// 于是一眼就看得出它不代表任何分类。它不属于任何分类，所以取整体主调的青色。
private struct HourglassTab: View {
    let isSelected: Bool
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            Image(systemName: "hourglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.teal) : AnyShapeStyle(.secondary))
                .frame(width: 30, height: 26)
                .tabChip(.teal, isSelected: isSelected, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("沙漏视图")
        .accessibilityLabel("沙漏视图")
    }
}

private struct CategoryTab: View {
    let category: Category
    let isSelected: Bool
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            Text(category.name)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(category.color.tint) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .tabChip(category.color.tint, isSelected: isSelected, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension View {
    /// tab 的胶囊底：选中最重，悬停轻一点，静止什么也不画。
    /// 沙漏 tab 与分类 tab 共用它，两种 tab 因此只在「有没有字」上不一样。
    fileprivate func tabChip(_ tint: Color, isSelected: Bool, hovering: Bool) -> some View {
        background(Capsule().fill(fill(tint, isSelected: isSelected, hovering: hovering)))
            .overlay(Capsule().stroke(isSelected ? tint.chipStroke : .clear, lineWidth: 1))
            .contentShape(Capsule())
    }

    private func fill(_ tint: Color, isSelected: Bool, hovering: Bool) -> AnyShapeStyle {
        if isSelected { return AnyShapeStyle(tint.chipFill) }
        if hovering { return AnyShapeStyle(.quaternary.opacity(0.4)) }
        return AnyShapeStyle(.clear)
    }
}

extension Color {
    /// 胶囊的底色与描边。tab 的选中态和沙漏视图里的分类 tag 都从这儿取 ——
    /// 两处要求是同一个颜色，所以只留这一处定义，免得各自漂移。
    var chipFill: Color { opacity(0.15) }
    var chipStroke: Color { opacity(0.5) }
}

// MARK: - 新建分类

/// 点开一个小面板，输入名字即建。颜色由 `Store` 分配，这里不给任何选色的入口。
struct NewCategoryButton<Label: View>: View {
    @Environment(Store.self) private var store
    let onCreate: (Category) -> Void
    @ViewBuilder let label: () -> Label

    @State private var presented = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Button { presented = true } label: { label() }
            .buttonStyle(.plain)
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("新建分类")
                        .font(.headline)
                    TextField("给它起个名字", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .focused($focused)
                        .onSubmit(create)
                    HStack {
                        Spacer()
                        Button("创建", action: create)
                            .keyboardShortcut(.defaultAction)
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
                .onAppear { focused = true }
            }
    }

    private func create() {
        guard let category = store.addCategory(draft) else { return }
        draft = ""
        presented = false
        onCreate(category)
    }
}

extension CategoryColor {
    /// 色名到色值。落盘的只有色名，于是这套配色可以随时整体调整。
    var tint: Color {
        switch self {
        case .teal: .teal
        case .mint: .mint
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        }
    }
}
