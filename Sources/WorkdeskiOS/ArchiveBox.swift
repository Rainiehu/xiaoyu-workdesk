#if os(iOS)
import SwiftUI
import WorkdeskCore
import WorkdeskUI

/// tab 条末端的档案盒：与 Mac 同一个位置、同一副规矩 —— 有归档的分类才露面，点开是档案名单，
/// 点一个就在内容区看它，那时盒子是选中态、穿着那个分类的颜色。见 ADR-0010。
struct ArchiveBox: View {
    @Environment(Store.self) private var store
    let selected: MainlineTab
    let select: (MainlineTab) -> Void
    @State private var presented = false
    /// 收进去一个就加一：盒子只在「有东西进来」时跳，取回、删掉都不跳 ——
    /// 这一跳说的是「它去了这儿」。
    @State private var arrivals = 0

    private var viewing: Category? {
        guard case .category(let id) = selected, let category = store.category(id), category.isArchived
        else { return nil }
        return category
    }

    var body: some View {
        // 盒子常驻在视图树里、空了才不画：名单挂在它身上，在名单里取回最后一个时
        // 挂点若跟着没了，名单就是被硬拆掉的。名单开着时盒子留着，空了就收名单。
        ZStack {
            if !store.archivedCategories.isEmpty || presented { box }
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
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(viewing == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
                // 收进去的那一下跳一拍：tab 从条上没了，得让人看见它去了哪儿。
                .symbolEffect(.bounce, value: arrivals)
                .frame(width: 34, height: 30)
                .tabChip(tint, isSelected: viewing != nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("档案")
        .sheet(isPresented: $presented) {
            ArchiveSheet(viewingID: viewing?.id) { id in
                select(.category(id))
                presented = false
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// 档案名单：最近归档的在最上面。在这儿删掉的，占位留在它那一行 —— 与 tab 条上同一副。
private struct ArchiveSheet: View {
    @Environment(Store.self) private var store
    let viewingID: Category.ID?
    let open: (Category.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("档案")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.archivedCategories) { category in
                        if category.isDeleted {
                            DeletedCategoryChip(category: category)
                                .padding(.vertical, 4)
                        } else {
                            ArchiveSheetRow(category: category, isViewing: category.id == viewingID) {
                                open(category.id)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, ScreenLayout.screenEdge)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .paperGround()
        .foregroundStyle(PaperTheme.ink)
    }
}

/// 名单上的一项。点它打开；长按是取回与删除 —— 改名、换色先取回再说，与 Mac 同一条分寸。
private struct ArchiveSheetRow: View {
    @Environment(Store.self) private var store
    let category: Category
    let isViewing: Bool
    let open: () -> Void
    @State private var refusedTodoCount = 0
    @State private var refusedHeadingCount = 0
    @State private var refusedDeletion = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Circle()
                    .fill(category.color.tint)
                    .frame(width: 9, height: 9)
                Text(category.name)
                    .foregroundStyle(isViewing ? AnyShapeStyle(category.color.tint) : AnyShapeStyle(PaperTheme.ink))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isViewing ? AnyShapeStyle(category.color.tint.chipFill) : AnyShapeStyle(.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("取回") { withAnimation(.easeOut(duration: 0.2)) { store.retrieveCategory(category.id) } }
            Divider()
            Button("删除分类", role: .destructive) { delete() }
        }
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

/// 从档案里点开一个分类时，分类屏顶上的那一行：说清它在档案里，取回只差一下。
/// 在档案里做的事都留在档案里 —— 回到 tab 条只有这一条路。与 Mac 同一副。
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
                .lineLimit(1)
            if let archivedAt = category.archivedAt {
                Text("归档于\(archivedAt.dayLabel(relativeTo: clock.today))")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { store.retrieveCategory(category.id) }
                Buzz.notify.notificationOccurred(.success)
            } label: {
                Text("取回")
                    .fontWeight(.medium)
                    .foregroundStyle(category.color.tint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(category.color.tint.chipFill))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .font(.callout)
        .padding(.horizontal, ScreenLayout.screenEdge)
        .padding(.top, 10)
    }
}
#endif
