import SwiftUI
import WorkdeskCore
import WorkdeskUI

/// tab 栏最右端的档案盒（标语的右边）：归档的分类待着的地方，有归档的才露面。点开是档案名单，
/// 点一个就在内容区看它 —— 那时盒子是选中态，穿着正在看的那个分类的颜色。
///
/// 收进去的那一下盒子跳一拍：tab 从栏上消失了，人得看得见它去了哪儿。
/// 归档不开撤销窗口，这一跳就是全部的交代 —— 回头路就在这个盒子里。见 ADR-0011。
struct ArchiveBox: View {
    @Environment(Store.self) private var store
    let selected: MainlineTab
    let select: (MainlineTab) -> Void
    @State private var presented = false
    /// 收进去一个就加一：盒子只在「有东西进来」时跳，取回、删掉都不跳 ——
    /// 这一跳说的是「它去了这儿」。
    @State private var arrivals = 0
    @State private var hovering = false

    /// 正从档案里点开着看的那个分类。
    private var viewing: Category? {
        guard case .category(let id) = selected, let category = store.category(id), category.isArchived
        else { return nil }
        return category
    }

    var body: some View {
        // 盒子常驻在视图树里、空了才不画：名单浮层挂在它身上，在名单里取回最后一个时
        // 挂点若跟着没了，浮层就是被硬拆掉的。浮层开着时盒子留着，空了就收浮层。
        ZStack {
            if !store.archivedCategories.isEmpty || presented {
                // 与沙漏右边那道细竖线同一副，左右照着摆：沙漏是最左的「不是分类」，
                // 档案盒是最右的「不是分类」。线跟着盒子走 —— 盒子不在，线也不在。
                HStack(spacing: 6) {
                    Divider().frame(height: 16)
                    box
                }
                // 标语是光字、没有胶囊内衬，多让一截，线两侧看着才与沙漏那边一样宽。
                .padding(.leading, 14)
            }
        }
        .onChange(of: store.archivedCategories.count) { old, new in
            if new > old { arrivals += 1 }
            if new == 0 { presented = false }
        }
    }

    private var box: some View {
        let tint = viewing?.color.tint ?? .secondary
        return Button { presented = true } label: {
            Image(systemName: "archivebox")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(viewing == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
                .symbolEffect(.bounce, value: arrivals)
                .frame(width: 30, height: 26)
                .tabChip(tint, isSelected: viewing != nil, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("档案")
        .accessibilityLabel("档案")
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            ArchiveList(viewingID: viewing?.id) { id in
                select(.category(id))
                presented = false
            }
        }
    }
}

/// 档案名单：最近归档的在最上面。在这儿删掉的，占位就留在它那一行 —— 与 tab 栏上同一副。
private struct ArchiveList: View {
    @Environment(Store.self) private var store
    let viewingID: Category.ID?
    let open: (Category.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("档案")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            ForEach(store.archivedCategories) { category in
                if category.isDeleted {
                    DeletedCategoryChip(category: category)
                } else {
                    ArchiveRow(category: category, isViewing: category.id == viewingID) { open(category.id) }
                }
            }
        }
        .padding(10)
        .frame(minWidth: 200, alignment: .leading)
    }
}

/// 名单上的一项。点它打开；右键是取回与删除 —— 改名、换色先取回再说：
/// 那两块面板从 tab 上弹出来，档案名单本身就是个浮层，浮层上再叠浮层，收的时候就乱了。
private struct ArchiveRow: View {
    @Environment(Store.self) private var store
    let category: Category
    let isViewing: Bool
    let open: () -> Void
    @State private var hovering = false
    @State private var refusedTodoCount = 0
    @State private var refusedHeadingCount = 0
    @State private var refusedDeletion = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Circle()
                    .fill(category.color.tint)
                    .frame(width: 8, height: 8)
                Text(category.name)
                    .foregroundStyle(isViewing ? AnyShapeStyle(category.color.tint) : AnyShapeStyle(.primary))
                Spacer(minLength: 0)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isViewing ? AnyShapeStyle(category.color.tint.chipFill)
                          : hovering ? AnyShapeStyle(.quaternary.opacity(0.4)) : AnyShapeStyle(.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("取回") { withAnimation(.easeOut(duration: 0.2)) { store.retrieveCategory(category.id) } }
            Divider()
            Button("删除分类", role: .destructive) { delete() }
        }
        // 与 tab 上那一处逐字同款：拦下来只说为什么，不给「连同待办一起删」的入口。
        .alert(
            CategoryDeletionRefusal.title(categoryName: category.name, todoCount: refusedTodoCount),
            isPresented: $refusedDeletion
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(CategoryDeletionRefusal.message(
                todoCount: refusedTodoCount, headingCount: refusedHeadingCount, isArchived: true
            ))
        }
    }

    private func delete() {
        switch store.deleteCategory(category.id) {
        case .deleted, .noSuchCategory:
            break
        case .refused(let todoCount, let headingCount):
            refusedTodoCount = todoCount
            refusedHeadingCount = headingCount
            refusedDeletion = true
        }
    }
}

/// 从档案里点开一个分类时，分类视图顶上的那一行：说清它在档案里，取回只差一下。
/// 在档案里做的事（记一条、取消打勾）都留在档案里 —— 回到 tab 栏只有这一条路。
struct ArchivedCategoryBanner: View {
    @Environment(Store.self) private var store
    @Environment(TodayClock.self) private var clock
    let category: Category

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "archivebox")
                .foregroundStyle(.secondary)
            Text(category.name)
                .fontWeight(.medium)
            if let archivedAt = category.archivedAt {
                Text("归档于\(archivedAt.dayLabel(relativeTo: clock.today))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // 取回钮穿这个分类的颜色：取回之后它在 tab 栏上就是这副胶囊。
            Button {
                withAnimation(.easeOut(duration: 0.2)) { store.retrieveCategory(category.id) }
            } label: {
                Text("取回")
                    .fontWeight(.medium)
                    .foregroundStyle(category.color.tint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(category.color.tint.chipFill))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("取回到 tab 栏")
        }
        .font(.callout)
        .padding(.horizontal, 28)
        .padding(.top, 16)
    }
}
