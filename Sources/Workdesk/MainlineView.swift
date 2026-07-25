import SwiftUI

/// 主线：顶部一排分类 tab，下面是选中分类的内容。
/// 一个分类都没有的时候（首次启动，或分类被删光），整个界面是一段引导。
struct MainlineView: View {
    @Environment(Store.self) private var store
    @State private var selectedCategoryID: Category.ID?

    /// 选中的分类。选中项不在（还没选过，或选中的那个没了）时退回第一个。
    private var selected: Category? {
        store.categories.first { $0.id == selectedCategoryID } ?? store.categories.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if let selected {
                CategoryTabBar(selected: selected.id) { selectedCategoryID = $0 }
                Divider()
                CategoryPlaceholder(category: selected)
            } else {
                onboarding
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
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
            NewCategoryButton(onCreate: { selectedCategoryID = $0.id }) {
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

struct CategoryTabBar: View {
    @Environment(Store.self) private var store
    /// 正在显示的那个分类 —— 由主线算出来，好让高亮的 tab 和内容区永远是同一个分类。
    let selected: Category.ID
    let select: (Category.ID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(store.categories) { category in
                    CategoryTab(category: category, isSelected: category.id == selected) {
                        select(category.id)
                    }
                }
                NewCategoryButton(onCreate: { select($0.id) }) {
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
                .background(
                    Capsule().fill(background)
                )
                .overlay(
                    Capsule().stroke(isSelected ? category.color.tint.opacity(0.5) : .clear, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(category.color.tint.opacity(0.15)) }
        if hovering { return AnyShapeStyle(.quaternary.opacity(0.4)) }
        return AnyShapeStyle(.clear)
    }
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

// MARK: - 分类内容（下一张票交付真正的清单）

private struct CategoryPlaceholder: View {
    let category: Category

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 34))
                .foregroundStyle(category.color.tint.opacity(0.5))
            Text("「\(category.name)」还是空的")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
