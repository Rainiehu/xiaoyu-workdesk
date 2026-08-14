import SwiftUI
import WorkdeskCore
import UniformTypeIdentifiers

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
                // tab 栏下的分界不用系统 hairline：两端缩进到 tab 栏的内容边距、
                // 颜色取墨的一成 —— 是排版里的一条线，不是窗口构件的一道缝。
                Rectangle()
                    .fill(.primary.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 20)
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
        HStack(spacing: 0) {
            tabs
            motto
        }
    }

    /// 钉在 tab 栏右端的一句话。放在可滚动区外面 —— 分类再多、横着滚起来，它也留在原处。
    ///
    /// 它只是一句话，不是控件：没有底、不接受点击、也没有悬停态。字号最小、颜色最淡、
    /// 字距拉开一点，于是它读起来像墙上贴的一张纸，而不是一个还没点过的按钮。
    private var motto: some View {
        Text("无视中断")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .tracking(2)
            // 不许被压缩：窗口窄了该让 tab 那边先滚，而不是把这句话挤成省略号。
            .fixedSize()
            .padding(.trailing, 20)
            .accessibilityHidden(true)
    }

    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                HourglassTab(isSelected: selected == .hourglass) { select(.hourglass) }
                // 一道细竖线把沙漏和分类分开：它是唯一不代表分类的一项，这里就说明白。
                Divider().frame(height: 16)
                ForEach(store.categories) { category in
                    // 删除态的 tab 是原位占位胶囊：撤销窗口开着的那几秒它还占着位置，
                    // 别的 tab 不合拢，见 ADR-0007。
                    if category.isDeleted {
                        DeletedCategoryChip(category: category)
                    } else {
                        CategoryTab(category: category, isSelected: selected == .category(category.id)) {
                            select(.category(category.id))
                        }
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

/// 分类 tab。点它切过去，右键是这个分类的全部管理动作：改名、换色、删除。
/// 拖着它放到另一个 tab 上就换了顺序 —— 最常用的分类因此可以排到靠前的位置。
/// 它同时接得住从分类视图里拖上来的待办：松手那条待办就归到这个分类。
private struct CategoryTab: View {
    @Environment(Store.self) private var store
    let category: Category
    let isSelected: Bool
    let select: () -> Void
    @State private var hovering = false
    /// 右键菜单点开的那个小面板 —— 改名和选色是同一个位置上的两件事，一次只开一个。
    @State private var panel: CategoryPanel?
    /// 刚刚有一次删除被拦下时，里头还剩多少条待办。非空分类删不掉这件事由 `Store` 判，
    /// 连同这个数字一起交回来，这儿只负责把话说清楚。
    @State private var refusedTodoCount = 0
    @State private var refusedDeletion = false
    /// 有别的 tab 正悬在这个 tab 上方。松手它就落到这个位置上。
    @State private var targeted = false

    var body: some View {
        Button(action: select) {
            Text(category.name)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(category.color.tint) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .tabChip(category.color.tint, isSelected: isSelected, hovering: hovering)
                // 落点指示与沙漏视图里那圈一样是青色描边：「松手会落在这儿」两处是同一句话。
                .overlay(Capsule().strokeBorder(.teal.opacity(targeted ? 0.7 : 0), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu { menu }
        .popover(item: $panel, arrowEdge: .bottom) { which in
            switch which {
            case .renaming:
                // 起名和改名是同一件事，所以是同一个面板，只是这次先装着原来的名字。
                CategoryNamePanel(title: "重命名分类", confirm: "改名", initial: category.name) { name in
                    store.renameCategory(category.id, to: name)
                    panel = nil
                }
            case .recoloring:
                // 选完就收 —— 换色是一下的事，不必再点一次「好」。
                ColorPalettePanel(selected: category.color) { color in
                    store.recolorCategory(category.id, to: color)
                    panel = nil
                }
            }
        }
        // 拦下来之后只说明为什么，不在这儿给「连同待办一起删」的入口 ——
        // 那正是这条约束要防的事。疏通的路子在待办行的右键菜单里。
        .alert("「\(category.name)」里还有待办", isPresented: $refusedDeletion) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("先把这 \(refusedTodoCount) 条待办移到别的分类，或者删掉，再来删这个分类。")
        }
        .draggable(DraggedCategory(id: category.id))
        // 一个 tab 上只挂一个落点，两种载荷都由它接 —— 挂两个的话上面那个会把下面那个整个挡住，
        // 见 `DraggedOntoTab`。
        .dropDestination(for: DraggedOntoTab.self) { dropped, _ in
            // 一次拖一个 —— tab 栏上没有多选，落下的就只会是刚才抓起的那一个。
            guard let dropped = dropped.first else { return false }
            switch dropped {
            case .category(let id):
                // 落到这个 tab 的位置上，其余的依次让开。
                store.moveCategory(id, onto: category.id)
                return true
            case .todo(let id):
                // 手势版的「移到分类」。只改归属：三个日子与完成状态都不变，
                // 与待办行右键菜单里那条路是同一件事。
                return store.moveTodo(id, to: category.id)
            }
        } isTargeted: { targeted = $0 }
        .animation(.easeOut(duration: 0.12), value: targeted)
    }

    @ViewBuilder
    private var menu: some View {
        Button("重命名…") { panel = .renaming }
        // 一整盘颜色摊开来看比一串色名的菜单好挑，所以换色也走面板，不做二级菜单。
        Button("换颜色…") { panel = .recoloring }
        Divider()
        Button("删除分类", role: .destructive) { delete() }
    }

    /// 空分类直接删，不弹确认 —— 清理的动作不该啰嗦。非空的由 `Store` 拦下，
    /// 这儿只把「为什么没删成」说出来。分类本身已经不在了就什么也不说：没什么好提示的。
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

/// 原位占位胶囊：刚删掉的分类在 tab 栏原来的位置上留下的口子，撤销窗口开着的
/// 那几秒里点一下就回来 —— 与待办行的 `DeletedTodoRow` 同一副分寸，见 ADR-0007。
/// 整个胶囊就是撤销按钮：占位上没有第二件可做的事，不必让人瞄准那枚小图标。
private struct DeletedCategoryChip: View {
    @Environment(Store.self) private var store
    let category: Category

    var body: some View {
        Button {
            store.undeleteCategory(category.id)
        } label: {
            HStack(spacing: 6) {
                Text("已删除")
                    .foregroundStyle(.tertiary)
                // 撤销钮穿死者自己的颜色 —— 占的是谁的位，就还谁的色。
                Image(systemName: "arrow.uturn.backward")
                    .fontWeight(.semibold)
                    .foregroundStyle(category.color.tint)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(.quaternary.opacity(0.4)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("撤销删除")
    }
}

/// tab 右键点开的小面板是哪一个。两个面板从同一个位置弹出来，所以是一个状态而不是两个 ——
/// 「一次只开一个」这件事就不必靠视图自己守着了。
private enum CategoryPanel: String, Identifiable {
    case renaming, recoloring

    var id: String { rawValue }
}

/// 摊开的一盘颜色。整块色板一次全在眼前，点哪个就是哪个 ——
/// 色块本身就是它要说的话，所以不写色名，名字只留给悬停提示和读屏。
private struct ColorPalettePanel: View {
    /// 这个分类现在是什么颜色。带一圈环的那个。
    let selected: CategoryColor
    let pick: (CategoryColor) -> Void

    /// 一行几个。14 种颜色排成整齐的两行。
    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 8), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            // 这儿按色相环的顺序铺（也就是 `allCases`），不按 `palette` 那个跳着走的取色顺序 ——
            // 挑颜色的人要的是一条顺下来的光谱，好找。
            ForEach(CategoryColor.allCases, id: \.self) { color in
                swatch(color)
            }
        }
        .padding(14)
    }

    private func swatch(_ color: CategoryColor) -> some View {
        Button { pick(color) } label: {
            Circle()
                .fill(color.tint)
                .frame(width: 20, height: 20)
                // 选中的那个外面套一圈同色的细环。撞色是允许的，所以别的一个都不灰掉。
                .padding(3)
                .overlay(
                    Circle().strokeBorder(color == selected ? color.tint : .clear, lineWidth: 1.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color.label)
        .accessibilityLabel(color.label)
    }
}

/// 拖拽时在两个 tab 之间递过去的东西：一个分类的身份，仅此而已。
/// 与沙漏视图里的 `DraggedTodo` 是同一套路数：只带 id，落下时现找现挪。
/// 类型是自家的，于是外来的文字、链接接不住，从 tab 栏拖出去别的应用也接不住。
private struct DraggedCategory: Codable, Transferable {
    var id: Category.ID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .workdeskCategory)
    }
}

/// 落到一个 tab 上的东西。两种载荷，落下时做的是两件事：一个分类落在另一个 tab 上是换顺序，
/// 一条待办落在 tab 上是改归属。
///
/// 合成这一个类型，是因为**一个视图上只能挂一个 `dropDestination`**。挂两个的话，上面那个会把
/// 下面那个整个挡住：`dropDestination` 在 AppKit 那层注册的是 `public.data` 这样的通用类型，
/// 两个落点长得一模一样，拖拽进来只命中最上面那个；它一看载荷不是自己要的就拒收，
/// 而 AppKit 不会再往下传 —— 于是下面那个永远等不到。
///
/// 只导入不导出：tab 从来不用这个类型往外拖，往外拖的是 `DraggedCategory` 本身。
enum DraggedOntoTab: Transferable {
    case category(Category.ID)
    case todo(TodoItem.ID)

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { (dragged: DraggedCategory) in DraggedOntoTab.category(dragged.id) }
        ProxyRepresentation { (dragged: DraggedTodo) in DraggedOntoTab.todo(dragged.id) }
    }
}

extension UTType {
    /// 只有 tab 栏自己拖出来的分类认得这个类型。与 `build.sh` 里 Info.plist 的
    /// `UTExportedTypeDeclarations` 是同一个标识符，两边要一起改。
    fileprivate static let workdeskCategory = UTType(exportedAs: "cc.huxiaoyu.workdesk.category")
}

/// 给分类起名字的小面板：新建和改名共用一副样子 —— 在界面上它们是同一个动作，
/// 只有标题、按钮上的字、以及输入框里先装着什么不一样。
/// 空白名字由 `Store` 挡掉，这儿只负责把字交出去。
private struct CategoryNamePanel: View {
    let title: String
    let confirm: String
    /// 输入框里先装着的字。新建时空着，改名时是原来的名字。
    var initial: String = ""
    let submit: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            TextField("给它起个名字", text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .focused($focused)
                .onSubmit { submit(draft) }
            HStack {
                Spacer()
                Button(confirm) { submit(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        // 每次打开都从头装一遍 —— 上一次改到一半的草稿不该留到下一次。
        .onAppear {
            draft = initial
            focused = true
        }
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

    var body: some View {
        Button { presented = true } label: { label() }
            .buttonStyle(.plain)
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                CategoryNamePanel(title: "新建分类", confirm: "创建", submit: create)
            }
    }

    private func create(_ name: String) {
        guard let category = store.addCategory(name) else { return }
        presented = false
        onCreate(category)
    }
}

extension CategoryColor {
    /// 色名到色值。落盘的只有色名，于是这套配色可以随时整体调整。
    /// 数值定在核心的 `rgbValues` 一处（两端共用），这儿只做 macOS 的动态颜色：
    /// 浅色外观下用深的那副，深色外观下用浅的那副。
    var tint: Color {
        let (light, dark) = rgbValues
        return Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(rgb: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }

    /// 这个颜色叫什么。选色盘上的色块看得见颜色，不写字 —— 名字是给悬停提示和读屏用的。
    var label: String {
        switch self {
        case .red: "红"
        case .orange: "橙"
        case .amber: "琥珀"
        case .lime: "黄绿"
        case .green: "绿"
        case .mint: "薄荷"
        case .teal: "青"
        case .cyan: "天蓝"
        case .blue: "蓝"
        case .indigo: "靛蓝"
        case .purple: "紫"
        case .fuchsia: "品红"
        case .pink: "粉"
        case .slate: "石墨"
        }
    }
}

extension NSColor {
    /// 0xRRGGBB。色板里的色值就是照着这个写的 —— 十六进制读起来比三个小数直观。
    /// 过期记号的琥珀（`Color.overdueAmber`）也从这儿走，全部色值因此是同一种写法。
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
