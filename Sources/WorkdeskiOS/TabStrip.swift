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
    /// 右端被同步记号浮盖的那一截：滚动内容多留这一段，
    /// 滚到头时最后一枚胶囊仍能整个走出记号底下。
    var trailingInset: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                hourglassTab
                // 一道细竖线把沙漏和分类分开：它是唯一不代表分类的一项，这里就说明白。
                Divider().frame(height: 16)
                ForEach(store.categories) { category in
                    // 删除态的 tab 是原位占位胶囊：撤销窗口开着的那几秒它还占着位置，
                    // 别的 tab 不合拢，见 ADR-0007。
                    if category.isDeleted {
                        DeletedCategoryChip(id: category.id)
                    } else {
                        CategoryTabChip(category: category, isSelected: selected == .category(category.id)) {
                            select(.category(category.id))
                        }
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
            .padding(.horizontal, ScreenLayout.screenEdge)
            .padding(.trailing, trailingInset)
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
    /// 有一条待办正悬在这个 tab 上方。松手它就归到这个分类。
    @State private var targeted = false

    var body: some View {
        Button(action: select) {
            Text(category.name)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(category.color.tint) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .tabChip(category.color.tint, isSelected: isSelected)
                // 落点指示与轴上、主列行上那圈同一句话：「松手会落在这儿」。
                .overlay(Capsule().strokeBorder(.teal.opacity(targeted ? 0.7 : 0), lineWidth: 2))
        }
        .buttonStyle(.plain)
        // 手势版的「移到分类」。只改归属：三个日子与完成状态都不变。
        // 沙漏 tab 不接落点：它不代表任何分类，没有「归到沙漏」这回事。
        .dropDestination(for: DraggedTodo.self) { dropped, _ in
            guard let dropped = dropped.first else { return false }
            return store.moveTodo(dropped.id, to: category.id)
        } isTargeted: { targeted = $0 }
        .animation(.easeOut(duration: 0.12), value: targeted)
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

/// 原位占位胶囊：刚删掉的分类在 tab 条原来的位置上留下的口子，撤销窗口开着的
/// 那几秒里点一下就回来 —— 与 Mac 的同名占位同一副，见 ADR-0007。
/// 整个胶囊就是撤销按钮：占位上没有第二件可做的事。
private struct DeletedCategoryChip: View {
    @Environment(Store.self) private var store
    let id: Category.ID

    var body: some View {
        Button {
            store.undeleteCategory(id)
        } label: {
            HStack(spacing: 6) {
                Text("已删除")
                    .foregroundStyle(.tertiary)
                Text("撤销")
                    .fontWeight(.semibold)
                    .foregroundStyle(.teal)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(.quaternary.opacity(0.4)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
