#if os(iOS)
import SwiftUI
import WorkdeskCore

/// tab 栏上的一项。沙漏是唯一不代表分类的那一项，永远排在首位 —— 与 Mac 同一副骨架。
enum MainlineTab: Hashable {
    case hourglass
    case category(Category.ID)
}

/// 主线：顶部 tab 条（首位是沙漏，其后是各个分类），下面是选中那一项的内容。
/// 一个分类都没有的时候，整个界面是一段引导 —— 那时连一条待办都不可能有。
///
/// 切屏靠点 tab。整屏的左右滑刻意不做：行上的左滑是删除、右缘的一划是面板，
/// 三种横向手势挤在同一屏谁都接不稳 —— 一个手势只干一件事。
struct MainlineScreen: View {
    @Environment(Store.self) private var store
    @Environment(CloudSync.self) private var sync
    /// 打开主线默认落在沙漏视图上，不落在任何分类里。
    @State private var selection: MainlineTab = .hourglass
    /// 新建分类的名字面板开着。iOS 上是一个带输入框的 alert —— 起名是一句话的事。
    @State private var naming = false
    @State private var draftName = ""

    /// 选中的那个分类。选中沙漏时是 `nil`；选中的分类没了（被删了）也是 `nil` ——
    /// 「找不着分类」和「落回沙漏」是同一件事，只在这儿判一次。
    private var selectedCategory: Category? {
        guard case .category(let id) = selection else { return nil }
        return store.category(id)
    }

    private var selected: MainlineTab {
        selectedCategory.map { .category($0.id) } ?? .hourglass
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.categories.isEmpty {
                onboarding
            } else {
                TabStrip(
                    selected: selected, select: { selection = $0 }, newCategory: { naming = true },
                    trailingInset: sync.active ? 44 : 0
                )
                // 同步记号浮在 tab 条右端上方 —— 分类再多、横着滚起来它也留在原处。
                // 身下垫一道纸色渐变：胶囊滑到它跟前是淡出去，不是被一刀切掉。
                // 只在同步真开着的构建里挂：单机构建不该挂一朵云说谎。
                .overlay(alignment: .trailing) {
                    if sync.active {
                        HStack(spacing: 0) {
                            LinearGradient(
                                colors: [PaperTheme.paper.opacity(0), PaperTheme.paper],
                                startPoint: .leading, endPoint: .trailing
                            )
                            .frame(width: 24)
                            SyncMark()
                                .padding(.trailing, 10)
                                .background(PaperTheme.paper)
                        }
                    }
                }
                // tab 条与内容之间不画线：靠 tab 条自身的高度与留白分界，
                // 与输入栏同一条处理 —— 整张纸从上到下连成一体。
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 整个主线铺在同一张纸上，正文一律是墨 —— .secondary/.tertiary 会自己从墨里
        // 淡出去，灰阶因此都是暖的。
        .paperGround()
        .foregroundStyle(PaperTheme.ink)
        .alert("新建分类", isPresented: $naming) {
            TextField("给它起个名字", text: $draftName)
            Button("创建") {
                if let category = store.addCategory(draftName) { selection = .category(category.id) }
                draftName = ""
            }
            Button("取消", role: .cancel) { draftName = "" }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let selectedCategory {
            CategoryScreen(category: selectedCategory)
                .id(selectedCategory.id)
        } else {
            HourglassScreen()
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
            // 刚建好第一个分类的人要的是往里记事，所以直接落到那个分类里。
            Button {
                naming = true
            } label: {
                Label("新建分类", systemImage: "plus")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.teal.opacity(0.15)))
                    .foregroundStyle(.teal)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
