#if os(iOS)
import SwiftUI
import WorkdeskCore

/// 顶部那条可横滚的 tab 条：沙漏 + 各分类 + 新建。与 Mac 的 tab 栏同构 ——
/// 沙漏在最左、分类依序排开，空间感原样成立。
struct TabStrip: View {
    @Environment(Store.self) private var store
    let selected: MainlineTab
    let select: (MainlineTab) -> Void
    let newCategory: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                hourglassTab
                // 一道细竖线把沙漏和分类分开：它是唯一不代表分类的一项，这里就说明白。
                Divider().frame(height: 16)
                ForEach(store.categories) { category in
                    CategoryTabChip(category: category, isSelected: selected == .category(category.id)) {
                        select(.category(category.id))
                    }
                }
                Button(action: newCategory) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
    }

    /// 沙漏 tab：只有图标，不带文字 —— 一排文字 tab 里就它没有字，一眼看得出它不代表分类。
    /// 取整体主调的青色。
    private var hourglassTab: some View {
        Button { select(.hourglass) } label: {
            let isSelected = selected == .hourglass
            Image(systemName: "hourglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.teal) : AnyShapeStyle(.secondary))
                .frame(width: 34, height: 30)
                .tabChip(.teal, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("沙漏视图")
    }
}

/// 分类 tab。点它切过去；管理动作（改名、换色、删除）在长按菜单里 —— 对应 Mac 的右键。
struct CategoryTabChip: View {
    @Environment(Store.self) private var store
    let category: Category
    let isSelected: Bool
    let select: () -> Void

    /// 改名面板开着。与新建同一副：一个带输入框的 alert。
    @State private var renaming = false
    @State private var draftName = ""
    /// 换色面板开着。摊开的一盘颜色，点哪个就是哪个。
    @State private var recoloring = false
    /// 刚刚有一次删除被拦下时，里头还剩多少条待办。
    @State private var refusedTodoCount = 0
    @State private var refusedDeletion = false

    var body: some View {
        Button(action: select) {
            Text(category.name)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(category.color.tint) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .tabChip(category.color.tint, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("重命名…") {
                draftName = category.name
                renaming = true
            }
            Button("换颜色…") { recoloring = true }
            Divider()
            Button("删除分类", role: .destructive) { delete() }
        }
        .alert("重命名分类", isPresented: $renaming) {
            TextField("给它起个名字", text: $draftName)
            Button("改名") { store.renameCategory(category.id, to: draftName) }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $recoloring) {
            ColorPaletteSheet(selected: category.color) { color in
                store.recolorCategory(category.id, to: color)
                recoloring = false
            }
            .presentationDetents([.height(180)])
        }
        // 拦下来之后只说明为什么，不给「连同待办一起删」的入口 —— 那正是这条约束要防的事。
        .alert("「\(category.name)」里还有待办", isPresented: $refusedDeletion) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("先把这 \(refusedTodoCount) 条待办移到别的分类，或者删掉，再来删这个分类。")
        }
    }

    private func delete() {
        switch store.deleteCategory(category.id) {
        case .deleted, .noSuchCategory:
            break
        case .refused(let todoCount):
            refusedTodoCount = todoCount
            refusedDeletion = true
        }
    }
}

/// 摊开的一盘颜色。整块色板一次全在眼前，点哪个就是哪个 —— 与 Mac 的选色盘同一副，
/// 按色相环的顺序铺，挑起来好找。
private struct ColorPaletteSheet: View {
    let selected: CategoryColor
    let pick: (CategoryColor) -> Void

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(CategoryColor.allCases, id: \.self) { color in
                Button { pick(color) } label: {
                    Circle()
                        .fill(color.tint)
                        .frame(width: 28, height: 28)
                        .padding(4)
                        .overlay(
                            Circle().strokeBorder(color == selected ? color.tint : .clear, lineWidth: 2)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.label)
            }
        }
        .padding(20)
    }
}

extension View {
    /// tab 的胶囊底：选中最重，静止什么也不画。与 Mac 同一个公式（只是没有悬停那一档）。
    func tabChip(_ tint: Color, isSelected: Bool) -> some View {
        background(Capsule().fill(isSelected ? AnyShapeStyle(tint.chipFill) : AnyShapeStyle(.clear)))
            .overlay(Capsule().stroke(isSelected ? tint.chipStroke : .clear, lineWidth: 1))
            .contentShape(Capsule())
    }
}
#endif
