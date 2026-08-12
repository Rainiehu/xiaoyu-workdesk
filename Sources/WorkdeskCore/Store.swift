import Foundation
import Observation

/// 一扇还开着的撤销窗口：一次删除对应一扇，各自倒计时、各自撤。
/// 视图层不拿它画占位（占位就是数组里带记号的那条记录），只有 ⌘Z 的从新到旧靠它排队。
public struct PendingUndo: Identifiable, Equatable {
    public enum Target: Equatable {
        case todo(TodoItem.ID)
        case category(Category.ID)
        case favorite(FavoriteItem.ID)
    }

    /// 窗口自己的身份，不是记录的 —— 同一条记录删了撤、撤了又删，是两扇窗口，
    /// 第一扇的倒计时不该关得掉第二扇。
    public let id = UUID()
    public let target: Target
    /// 那一斧落下的时刻，只有删待办才有：删父连子，整棵树打的是同一个时刻。
    /// 窗口关上时按它清扫进池子 —— 树里哪怕有谁先被单独救活（同步来的复活只救祖先链），
    /// 剩下的也一个不漏。
    let fellAt: Date?

    init(target: Target, fellAt: Date? = nil) {
        self.target = target
        self.fellAt = fellAt
    }
}

/// 同一窝兄弟的身份：同一个分类里挂在同一个父下面的那些，顶层是父为空的兄弟。
/// 位置（`order`）只在一窝之内可比 —— 换位置、编号、播种，说范围说的都是它。
private struct SiblingGroup: Hashable {
    var categoryID: Category.ID
    var parentID: TodoItem.ID?
}

extension TodoItem {
    fileprivate var siblingGroup: SiblingGroup {
        SiblingGroup(categoryID: categoryID, parentID: parentID)
    }
}

@Observable
@MainActor
public final class Store {
    /// 分类的显示顺序就是这个数组的顺序。
    ///
    /// 三个数组里住的是活人，外加**还开着撤销窗口的删除态记录**（打着 `deletedAt` 记号）——
    /// 占位跟着死者的原位走，行留在数组里位置才留得住。窗口一关（或下次启动时清扫），
    /// 删除态的搬进下面的池子，从此不在任何界面露面。见 ADR-0007。
    public private(set) var categories: [Category] = []
    public private(set) var todos: [TodoItem] = []
    public private(set) var favorites: [FavoriteItem] = []

    /// 删除态的池子：窗口关了的删除记录永远住这儿 —— 不清理、不设回收站，
    /// 数据留着，哪天要做回收站（或又一次事后好几天才发现的误删）都还有救。
    /// 分类带着死时的位置（活人中的第几位），撤销的路虽已关，同步的复活还用得着。
    private(set) var deletedTodos: [TodoItem] = []
    private(set) var deletedCategories: [PlacedCategory] = []
    private(set) var deletedFavorites: [FavoriteItem] = []

    /// 还开着的撤销窗口，新的在后。会话态，不落盘 —— 重启后窗口都视作已关
    /// （`init` 里把落盘时还带着记号的记录清扫进池子）。
    public private(set) var pendingUndos: [PendingUndo] = []
    #if os(macOS)
    public var usage: UsageSnapshot?
    public var usageLoading = false
    #endif

    /// 上次选来记事的分类。可能指向一个已经不在了的分类 —— 对外的 `recordingCategory` 管这件事。
    private var chosenRecordingCategoryID: Category.ID?

    /// 沙漏轴那只眼闭着：已完成的不进 `timeline(today:)` 的分组。
    /// 这是「怎么看」的习惯，不是数据 —— 随偏好落盘、不进同步，两台机器各看各的。
    public private(set) var hidesCompletedOnTimeline = false

    /// 展开着子树的那些待办。与那只眼同一个待遇：习惯不是数据，随偏好落盘、不进同步。
    /// 三处的行共享这一份 —— 在轴上展开的树，切到分类视图它也开着。
    public private(set) var expandedTodoIDs: Set<TodoItem.ID> = []

    /// 同步的账本：本地增删改先记账，云端慢慢结清。待办、分类与收藏都记在这一本上。
    /// 没有同步引擎的构建里它照记不误 —— 账不会丢，哪天引擎接上了照账补发。
    public private(set) var syncLog = SyncChangeLog()

    /// 同步的记性：影子副本（字段级合并的「上一次」）与分类的殉葬品（复活的料）。
    /// 与账本一样随数据落盘 —— 冲突可能隔着一次重启才撞上。
    private(set) var syncShadows = SyncShadows()

    /// 云端先送来了待办、它归属的分类却还没到 —— 那条待办先在这儿候着，
    /// 分类一落地就跟着落。落了盘：分类可能等到下次启动才来，候着的不能跟着重启丢了。
    /// 界面永远只看 `todos`，候着的这些一概不露面 —— 露面就成了无归属的待办。
    private(set) var orphanTodos: [TodoItem] = []

    /// 账本添了新账时喊一声，同步引擎听着 —— `Store` 自己不认识 CloudKit，
    /// 谁在听、听了做什么，都不是它的事。
    @ObservationIgnored var syncLogDidChange: (() -> Void)?

    /// 正常运行时的存储位置。只算路径，不建目录 —— 建目录是 `init` 的事。
    public nonisolated static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("XiaoyuWorkdesk", isDirectory: true)
    }

    private let directory: URL

    /// - Parameter directory: 存储目录，默认是 `defaultDirectory`。测试传一个临时目录进来。
    public init(directory: URL = Store.defaultDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        categories = load(Self.categoriesFile) ?? []
        todos = load(Self.todosFile) ?? []
        favorites = load("favorites.json") ?? []
        deletedTodos = load(Self.deletedTodosFile) ?? []
        deletedCategories = load(Self.deletedCategoriesFile) ?? []
        deletedFavorites = load(Self.deletedFavoritesFile) ?? []
        syncLog = load(Self.syncLogFile) ?? SyncChangeLog()
        syncShadows = load(Self.shadowsFile) ?? SyncShadows()
        orphanTodos = load(Self.orphansFile) ?? []
        let preferences: Preferences? = load(Self.preferencesFile)
        chosenRecordingCategoryID = preferences?.recordingCategoryID
        hidesCompletedOnTimeline = preferences?.hidesCompletedOnTimeline ?? false
        expandedTodoIDs = Set(preferences?.expandedTodoIDs ?? [])
        sweepInterruptedDeletions()
        seedOrders()
    }

    /// 上次退出时撤销窗口还开着的删除态记录：窗口随会话已关，进池子。
    /// 分类先量好它在活人中的位置再搬 —— 池子里的位置是同步和复活都要用的料。
    private func sweepInterruptedDeletions() {
        if todos.contains(where: \.isDeleted) {
            deletedTodos.append(contentsOf: todos.filter(\.isDeleted))
            todos.removeAll(where: \.isDeleted)
            saveTodos()
            saveDeletedTodos()
        }
        if categories.contains(where: \.isDeleted) {
            while let i = categories.firstIndex(where: \.isDeleted) {
                deletedCategories.append(
                    PlacedCategory(category: categories.remove(at: i), position: livingPosition(before: i))
                )
            }
            saveCategories()
            saveDeletedCategories()
        }
        if favorites.contains(where: \.isDeleted) {
            deletedFavorites.append(contentsOf: favorites.filter(\.isDeleted))
            favorites.removeAll(where: \.isDeleted)
            saveFavorites()
            saveDeletedFavorites()
        }
    }

    /// 给还没有位置的待办补上位置：按老规矩铺一遍 —— 已排期的在上，按计划日从早到晚；
    /// 未排期的在下，按创建日从新到旧。升级上来的人第一眼看到的顺序因此和升级前一模一样，
    /// 从那以后顺序就归自己拖了，见 ADR-0002。
    ///
    /// 已完成的也一并给上位置：它们此刻在右列，但取消打勾就回到左列，那时得有个落脚处。
    /// 一条也不缺就什么都不做 —— 这是一次性的补写，不是每次启动都重排一遍。
    private func seedOrders() {
        guard todos.contains(where: { $0.order == nil }) else { return }
        for group in Set(todos.map(\.siblingGroup)) {
            renumber(group, as: Self.seededOrder(todos.filter { $0.siblingGroup == group }))
        }
        saveTodos()
    }

    /// 老规矩铺出来的顺序：已排期的在上，按计划日从早到晚（同一天按记下的先后）；
    /// 未排期的在下，按创建日从新到旧 —— 最近才想到的事不沉到底部。
    /// 只在补写位置时用得着；平时的顺序由使用者自己拖出来。
    private static func seededOrder(_ todos: [TodoItem]) -> [TodoItem] {
        // 排期与否在这儿一次分清：拆出计划日随着待办一起走，下面排序就不必再问它在不在。
        let scheduled = todos.compactMap { todo in todo.plannedOn.map { (todo: todo, day: $0) } }
            .sorted { ($0.day, $0.todo.createdAt) < ($1.day, $1.todo.createdAt) }
            .map(\.todo)
        let unscheduled = todos.filter { $0.plannedOn == nil }
            .sorted { $0.createdAt > $1.createdAt }
        return scheduled + unscheduled
    }

    // MARK: - Categories

    /// 新建一个分类。只要一个名字 —— 颜色从色板里按顺序取下一个还没被占用的，用户不参与选色。
    /// 名字为空（或只有空白）时不建，返回 `nil`。
    @discardableResult
    public func addCategory(_ name: String) -> Category? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        let category = Category(name: n, color: nextColor())
        categories.append(category)
        saveCategories()
        // 落在末尾，谁的位置都没动 —— 只有它自己欠云端一笔。
        logSyncChange { $0.recordSave(category.changeEntry) }
        return category
    }

    /// 色板中第一个还没被占用的颜色；都被占用了就从头循环，好让分类数量不受色板长度限制。
    private func nextColor() -> CategoryColor {
        let taken = Set(categories.map(\.color))
        return CategoryColor.palette.first { !taken.contains($0) }
            ?? CategoryColor.palette[categories.count % CategoryColor.palette.count]
    }

    /// 按 id 找回一个分类。沙漏视图里每条待办旁的彩色 tag 靠它取名字和颜色 ——
    /// 找不着（分类被删了，含删除态）就是 `nil`，视图层照着这个决定要不要画那个 tag。
    /// 只认活人：删除态的分类对一切「在用」的语义等于不存在，只有占位和撤销认得它。
    public func category(_ id: Category.ID) -> Category? {
        categories.first { $0.id == id && !$0.isDeleted }
    }

    /// 活着的分类。`categories` 数组本身可能夹着还开着撤销窗口的删除态记录（占位靠它站在原位），
    /// 一切「在用」的场合（记事选择器、移到分类的名单）看的都是这一份。
    public var livingCategories: [Category] {
        categories.filter { !$0.isDeleted }
    }

    /// 一个分类此刻在活人中排第几（数组里它前面有几个活人）。
    /// 云端的 `position` 字段说的就是这个数 —— 删除态的记录不占位置。
    private func livingPosition(before index: Int) -> Int {
        categories[..<index].filter { !$0.isDeleted }.count
    }

    /// 把一个分类插到活人中的第 `position` 位。数组里可能夹着删除态的占位，
    /// 所以「第几位」要跳着数；超出末尾就贴在最后。
    private func insertCategory(_ category: Category, atLivingPosition position: Int) {
        var living = 0
        for i in categories.indices where !categories[i].isDeleted {
            if living == position {
                categories.insert(category, at: i)
                return
            }
            living += 1
        }
        categories.append(category)
    }

    /// 改名。空白名字不改 —— 与 `addCategory` 同一副脾气：分类总得有个名字。
    /// 名字只是称呼，改它碰不到分类的身份，里头的待办一条也不动。
    public func renameCategory(_ id: Category.ID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        updateCategory(id) { $0.name = n }
    }

    /// 换颜色。新建时颜色是自动分配的，这里是唯一由用户指定颜色的入口。
    /// 不拦重色 —— 两个分类撞色是用户自己的选择，不该被拦下。
    public func recolorCategory(_ id: Category.ID, to color: CategoryColor) {
        updateCategory(id) { $0.color = color }
    }

    /// 把一个分类挪到另一个分类现在的位置上，其余的依次让开 ——
    /// tab 栏上拖着一个 tab 放到另一个 tab 上时走这条路，于是最常用的可以排到前头。
    /// 说的是「放到谁身上」而不是第几位：顺序是 `Store` 的事，视图层不必先去数位置。
    /// 两个都是同一个分类、或者哪一个不存在，都什么也不发生。
    public func moveCategory(_ id: Category.ID, onto targetID: Category.ID) {
        guard let from = categories.firstIndex(where: { $0.id == id }),
              let to = categories.firstIndex(where: { $0.id == targetID }), from != to else { return }
        categories.insert(categories.remove(at: from), at: to)
        saveCategories()
        // 位置在云端是每条记录自己的字段，这一挪让两头之间的分类都换了位置 ——
        // 一批记录同时变脏，都得记。
        logSyncChange { log in
            for category in categories[min(from, to)...max(from, to)] {
                log.recordSave(category.changeEntry)
            }
        }
    }

    /// 除了这一个之外活着的分类。待办的「移到分类」菜单列的就是它们 ——
    /// 一条待办没法移到它已经在的地方，也没法移进一个删除态的分类。
    public func categories(besides categoryID: Category.ID) -> [Category] {
        livingCategories.filter { $0.id != categoryID }
    }

    /// 删掉一个分类。**只删得掉空的** —— 里头还有活着的待办（无论完成与否，删除态的不算数）
    /// 就拒绝，一条待办也不动。撤销窗口救得回一条手滑，救不回一批：整个分类连着几十条待办
    /// 一起进删除态，几秒钟里看不清丢了什么，所以宁可在这儿拦住，也不要事后无声地丢失待办。
    /// 这条约束由 `Store` 保证，不依赖视图层自觉。
    ///
    /// 疏通的路子是 `moveTodo(_:to:)` 或删掉那些待办：分类空了，它自然就删得掉了。
    /// 删到一个不剩是允许的 —— 那时主线回到引导空态，与首次启动是同一个状态。
    ///
    /// 删除是打记号：分类留在数组原位撑着占位胶囊，窗口一关才搬进池子。
    /// 云端那头这只是一次字段更新 —— 记录不消失，见 ADR-0007。
    @discardableResult
    public func deleteCategory(_ id: Category.ID) -> CategoryDeletion {
        guard let index = categories.firstIndex(where: { $0.id == id }), !categories[index].isDeleted
        else { return .noSuchCategory }
        let living = livingTodos(in: id)
        guard living.isEmpty else { return .refused(todoCount: living.count) }
        categories[index].deletedAt = .now
        saveCategories()
        logSyncChange { log in
            log.recordSave(categories[index].changeEntry)
            // 身后活着的分类都往前挪了一位 —— 位置在云端是记录的字段，挪了就是变了。
            for category in categories[(index + 1)...] where !category.isDeleted {
                log.recordSave(category.changeEntry)
            }
        }
        openUndoWindow(.category(id))
        return .deleted
    }

    /// 改一个分类，落盘并记账。找不着就什么也不发生 —— 与 `update(_:_:)` 同一副脾气。
    private func updateCategory(_ id: Category.ID, _ change: (inout Category) -> Void) {
        guard let i = categories.firstIndex(where: { $0.id == id }) else { return }
        change(&categories[i])
        saveCategories()
        logSyncChange { $0.recordSave(categories[i].changeEntry) }
    }

    // MARK: - 记事的分类

    /// 沙漏视图记事时归到哪个分类：上次选的那个。还没选过、或选的那个分类没了，
    /// 就落回第一个分类 —— 「记不起来」于是不是一个要视图层去应付的状态。
    /// 一个分类都没有时是 `nil`：那时无处可记，也就不该记出一条无归属的待办。
    public var recordingCategory: Category? {
        chosenRecordingCategoryID.flatMap(category) ?? livingCategories.first
    }

    /// 选一个分类来记事。这个选择跨重启保留，好让连续记同一类事情不必反复选。
    /// 指向不存在（含删除态）的分类时什么也不发生，与 `addTodo` 同一副脾气。
    public func chooseRecordingCategory(_ id: Category.ID) {
        guard category(id) != nil else { return }
        chosenRecordingCategoryID = id
        savePreferences()
    }

    /// 在沙漏视图记一条待办：归到当前选来记事的分类，并当场排在今天 ——
    /// 于是它立刻落在那条轴上，而不是凭空消失到某个分类里去。
    /// 「归到哪个分类」和「排在哪一天」这两个决定都在这儿，视图层只管把字交过来。
    /// 一个分类都没有时什么也不发生：那时无处可记，也就不该记出一条无归属的待办。
    /// - Parameter today: 「今天」由调用方交进来，与 `timeline(today:)` 同一副脾气 ——
    ///   这件事因此可测，也没有哪一处偷偷去问一次时钟。交的是时刻，排上的是那个日子。
    public func recordOnTimeline(_ text: String, today: Date) {
        guard let category = recordingCategory else { return }
        addTodo(text, in: category.id, plannedOn: today.dayStart)
    }

    // MARK: - Todos

    /// 侧边栏徽标要的数字。派生数据一律从这里出，视图层不自己聚合。
    /// 删除态的不算 —— 占位还站在原位，但那件事已经不在「要做」的名下了。
    /// 子待办也不算：徽标数的是**事**，一件带五步的事是一件事，不是六件。
    public var unfinishedTodoCount: Int {
        todos.filter { !$0.done && !$0.isDeleted && $0.parentID == nil }.count
    }

    /// 沙漏视图要的分组：所有分类中排了计划日的待办，按计划日铺成一条轴，日期升序。
    /// 没有计划日的待办不出现在这里；没有待办的日期不产生分组，于是滚动是紧凑的。
    /// 但今天这一组恒定存在 —— 它是那条轴的锚点，空无一事也照样在。
    ///
    /// 已完成的待办落在它的**计划日**，不是完成日：打勾不会让条目跳到别的日期去。
    /// 计划日在过去而未完成的待办也只是留在它那一天，这里不给它任何特殊位置，见 ADR-0001。
    ///
    /// 那只眼闭着（`hidesCompletedOnTimeline`）时已完成的一概不进组，没有哪一天是例外 ——
    /// 含删除态的占位：它闭眼前就没显示，占位凭空冒出来才怪。整天都做完的日子
    /// 于是不成组，过去段随之收短。
    /// - Parameter today: 「今天」是哪天。刻意没有默认值 —— 由调用方交进来，
    ///   分组因此既可测，也不会有哪一处偷偷去问一次时钟。
    public func timeline(today: Date) -> [TimelineDay] {
        var byDay: [Date: [TodoItem]] = [today.dayStart: []]
        for todo in todos {
            // 轴上只有顶层：子待办是父的内部结构，没有自己的计划日，不单独占一行。
            // （正常路径上子待办的 plannedOn 恒为空，这里再挡一道是防同步合出来的怪状态。）
            guard let planned = todo.plannedOn, todo.parentID == nil else { continue }
            if hidesCompletedOnTimeline && todo.done { continue }
            byDay[planned.dayStart, default: []].append(todo)
        }
        return byDay
            .sorted { $0.key < $1.key }
            .map { TimelineDay(day: $0.key, todos: $0.value) }
    }

    /// 拨一下沙漏轴的那只眼：睁 ↔ 闭。选择跨重启保留，与记事分类同一份偏好文件。
    public func toggleHidesCompletedOnTimeline() {
        hidesCompletedOnTimeline.toggle()
        savePreferences()
    }

    /// 这条待办的子树展开着吗。默认收起 —— 轴上一屏几十行，不该因为谁有步骤就成了一片树。
    public func isExpanded(_ id: TodoItem.ID) -> Bool {
        expandedTodoIDs.contains(id)
    }

    /// 拨一下展开/收起。选择跨重启保留，三处共享。
    public func toggleExpanded(_ id: TodoItem.ID) {
        if expandedTodoIDs.contains(id) {
            expandedTodoIDs.remove(id)
        } else {
            expandedTodoIDs.insert(id)
        }
        savePreferences()
    }

    /// 把这条待办展开（已开着就什么也不做）。「添加子待办」用它 —— 加的那步得当场看得见。
    public func expand(_ id: TodoItem.ID) {
        guard !expandedTodoIDs.contains(id) else { return }
        expandedTodoIDs.insert(id)
        savePreferences()
    }

    /// 沙漏视图右列要的分组：还没排期的未完成待办，按分类分开，分类的顺序就是 tab 栏上的顺序。
    ///
    /// 它们不在那条轴上（轴按计划日铺），却也不该因此看不见 —— 「总得做但不急」是个正常状态，
    /// 不是缺失。已完成的不在这儿：这一列问的是「还有什么没安排」。
    /// 一条也没有的分类不成组，右列因此是紧凑的。
    /// 组内的先后与分类视图左列一致（使用者自己拖出来的那个），两处看到的顺序永远是同一个。
    public var unscheduled: [UnscheduledGroup] {
        categories.compactMap { category in
            let mine = Self.ordered(todos(in: category.id).filter {
                // 这一列同样只有顶层：步骤不是「还没安排的事」，它跟着父走。
                !$0.done && $0.plannedOn == nil && $0.parentID == nil
            })
            return mine.isEmpty ? nil : UnscheduledGroup(category: category, todos: mine)
        }
    }

    /// 一个分类里的待办，按记下的先后排列。分类之间因此互不干扰。
    /// 里头可能夹着还开着撤销窗口的删除态记录 —— 视图层靠它们把占位画在原位；
    /// 一切「数人头」的场合（非空判断、徽标）用 `livingTodos(in:)`。
    public func todos(in categoryID: Category.ID) -> [TodoItem] {
        todos.filter { $0.categoryID == categoryID }
    }

    /// 同上，只数活人。「非空分类删不掉」数的就是这一份 —— 删除态的不算数。
    private func livingTodos(in categoryID: Category.ID) -> [TodoItem] {
        todos.filter { $0.categoryID == categoryID && !$0.isDeleted }
    }

    /// 分类视图要的两列。两套排序规则都在这儿定死，视图层照着铺就是。
    ///
    /// 左列按使用者自己拖出来的顺序，不按日期 —— 分类里关心的是「哪件先做」，
    /// 「排在哪天」是沙漏视图的事，见 ADR-0002。已排期与未排期因此不再分成两段，
    /// 混在一列里，靠行尾日期标签的有无自然区分。
    ///
    /// 右列按完成日从新到旧，最近的成果在最上面 —— 那是一份记录，不由人排。
    ///
    /// 两列铺的都只是**顶层**：归哪列只看顶层的完成状态，子待办打了勾也不迁列，
    /// 就在父的树里原地显示为已勾；父完成了，整棵树跟着父行去右列。
    public func columns(in categoryID: Category.ID) -> CategoryColumns {
        let mine = todos(in: categoryID).filter { $0.parentID == nil }
        let unfinished = Self.ordered(mine.filter { !$0.done })
        // 打了勾就必然有完成日；万一数据里缺了，退回创建日 ——
        // 宁可这一条排得不准，也不让它从两列里消失。
        let finished = mine.filter(\.done)
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
        return CategoryColumns(unfinished: unfinished, finished: finished)
    }

    /// 按位置从上到下排。载入时每条都补过位置，所以缺位置只可能是编码错误 ——
    /// 真缺了就排到末尾，并按创建日兜底，宁可位置不准也不让它消失。
    private static func ordered(_ todos: [TodoItem]) -> [TodoItem] {
        todos.sorted { ($0.order ?? .max, $0.createdAt) < ($1.order ?? .max, $1.createdAt) }
    }

    /// 记一条待办。所属分类是必填的 —— 指向一个不存在的分类时什么也不发生，
    /// 于是「每条待办都落在某个分类里」这条约束由 `Store` 保证，不依赖视图层自觉。
    /// - Parameter day: 一并排上的计划日，默认不排 —— 分类视图里记事就是不排期的，
    ///   排期是之后另点一下的事。沙漏视图里记事则当场交一个日子进来，
    ///   好让新记下的这条立刻出现在使用者正看着的那条轴上。
    public func addTodo(_ text: String, in categoryID: Category.ID, plannedOn day: Date? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, category(categoryID) != nil else { return }
        let item = TodoItem(text: t, categoryID: categoryID, plannedOn: day, order: topOrder(in: categoryID))
        todos.append(item)
        saveTodos()
        logSyncChange { $0.recordSave(item.changeEntry) }
    }

    /// 落在这个分类顶层最上面要多小的位置。刚记下的事就在眼前，不必先滚到底去找 ——
    /// 不满意再拖走就是。
    private func topOrder(in categoryID: Category.ID) -> Int {
        (siblings(of: SiblingGroup(categoryID: categoryID, parentID: nil)).compactMap(\.order).min() ?? 0) - 1
    }

    /// 打勾/取消打勾。完成时刻原样落盘 —— 截到天是显示层的事，底下留着全时刻，
    /// 于是同一天完成的几条仍分得出先后。取消打勾就把它清掉，
    /// 于是「没有完成日」和「没完成」永远是同一件事。
    public func toggleTodo(_ item: TodoItem) {
        update(item.id) {
            $0.done.toggle()
            $0.completedAt = $0.done ? .now : nil
        }
    }

    /// 改写一条待办的正文。字打错了、事情说法变了，就地改这一句 ——
    /// 不必删掉重记，那样会连计划日、创建日、完成日一起丢掉。
    ///
    /// 只动正文：归属分类、三个日子与完成状态都不变。
    /// 空白正文不改，与 `addTodo`、`renameCategory` 同一副脾气 —— 待办总得有句话；
    /// 删除是另一条路，不该由「把字删光」触发。
    public func editTodo(_ item: TodoItem, to text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        update(item.id) { $0.text = t }
    }

    /// 排上计划日，或改到另一天。只动计划日 —— 创建日与完成日各存各的，改期碰不到它们。
    public func setPlannedDay(_ day: Date, for item: TodoItem) {
        update(item.id) { $0.plannedOn = day }
    }

    /// 改期到某一天。沙漏视图里把一条待办从一个日期分组拖到另一个分组时走这条路。
    /// 与 `setPlannedDay` 是同一件事，只是认 id 不认待办本身 —— 拖着走的一路上只有一个身份。
    ///
    /// 只动计划日 —— 归属分类、创建日、完成日都不因这一拖而变。往哪一天拖是时间轴上的事，
    /// 归属是横轴上的事，两条轴在这里不交叉。
    /// - Parameter day: 目标那一天。交进来的就是分组那一天，`Store` 不替它截断。
    /// - Returns: 这一放是否落到了实处。找不着那条待办（比如它同时被删了）就是 `false`，
    ///   视图层照着它告诉系统这次拖拽接住了没有。
    @discardableResult
    public func reschedule(_ id: TodoItem.ID, to day: Date) -> Bool {
        update(id) { $0.plannedOn = day }
    }

    /// 清除计划日，待办回到未排期。未排期是个正常状态，不是缺失 ——
    /// 「总得做但不急」的事就该一直待在这儿。
    public func clearPlannedDay(_ item: TodoItem) {
        update(item.id) { $0.plannedOn = nil }
    }

    /// 把一条待办改到另一个分类。归类的想法会变，事情该能换地方；这也是把一个分类腾空的那条路 ——
    /// 非空分类删不掉，没有它就永远删不掉。
    ///
    /// 只改归属：计划日、创建日、完成日与完成状态都不因换分类而变 —— 横轴上的移动不碰纵轴。
    /// 目标分类不存在时什么也不发生，于是「每条待办都落在某个分类里」这条约束在这儿也守得住。
    public func moveTodo(_ item: TodoItem, to categoryID: Category.ID) {
        moveTodo(item.id, to: categoryID)
    }

    /// 同一件事，只是认 id 不认待办本身 —— 从分类视图把一行拖到 tab 栏另一个分类上时走这条路，
    /// 拖着走的一路上只有一个身份。
    ///
    /// 落在新分类的最上面：这条待办在原来那个分类里的位置在新分类里没有意义，
    /// 而「刚移过去的那条」该一眼看得见。
    /// 目标就是它已经在的那个分类时什么也不发生 —— 那不是一次移动，位置也不该因此被动过。
    ///
    /// 只有顶层能换分类 —— 子待办的分类跟着根走，子行上本没有「移到分类」这回事。
    /// 换的是整棵树：名下的子待办（不论几层）一并跟过去，树永远在同一个分类里。
    /// - Returns: 这一移是否落到了实处。视图层照着它告诉系统这次拖拽接住了没有。
    @discardableResult
    public func moveTodo(_ id: TodoItem.ID, to categoryID: Category.ID) -> Bool {
        guard category(categoryID) != nil,
              let item = todos.first(where: { $0.id == id }),
              item.parentID == nil, item.categoryID != categoryID else { return false }
        let top = topOrder(in: categoryID)
        let moved = update(id) {
            $0.categoryID = categoryID
            $0.order = top
        }
        if moved { carryDescendants(of: id, to: categoryID) }
        return moved
    }

    /// 整棵树换分类的后一半：把名下子孙的归属改成根的新分类（已经对的不碰）。
    /// 各自在兄弟组里的位置不动 —— 父没换，兄弟还是那些兄弟。
    private func carryDescendants(of id: TodoItem.ID, to categoryID: Category.ID) {
        let carried = descendantIDs(of: id).filter { did in
            todos.first { $0.id == did }?.categoryID != categoryID
        }
        guard !carried.isEmpty else { return }
        for i in todos.indices where carried.contains(todos[i].id) {
            todos[i].categoryID = categoryID
        }
        saveTodos()
        logSyncChange { log in
            for todo in todos where carried.contains(todo.id) { log.recordSave(todo.changeEntry) }
        }
    }

    /// 把一条待办放到另一条现在的位置上，其余的依次让开 —— 分类视图左列里拖着一行
    /// 放到另一行上时走这条路，说的是「放到谁身上」而不是第几位，与 `moveCategory(_:onto:)` 同一副脾气。
    ///
    /// 只动这一列的顺序：归属分类、三个日子与完成状态都不因这一拖而变。
    /// 两条不在同一个分类、是同一条、或哪一条已经不在了，都什么也不发生 ——
    /// 跨分类的拖拽不存在，改归属是把它拖到 tab 上的事。
    /// - Returns: 这一放是否落到了实处。视图层照着它告诉系统这次拖拽接住了没有。
    @discardableResult
    public func reorderTodo(_ id: TodoItem.ID, onto targetID: TodoItem.ID) -> Bool {
        guard id != targetID,
              let moved = todos.first(where: { $0.id == id }),
              let target = todos.first(where: { $0.id == targetID }),
              moved.siblingGroup == target.siblingGroup else { return false }
        // 整组兄弟一起排 —— 已完成的也在这条队伍里，它们此刻在右列，但取消打勾就回到左列。
        var queue = Self.ordered(siblings(of: moved.siblingGroup))
        guard let from = queue.firstIndex(where: { $0.id == id }),
              let to = queue.firstIndex(where: { $0.id == targetID }) else { return false }
        queue.insert(queue.remove(at: from), at: to)
        renumber(moved.siblingGroup, as: queue)
        saveTodos()
        return true
    }

    /// 把一组兄弟的位置从头编一遍：交进来的顺序就是从上到下的顺序。
    /// 每次都全编而不是插空，于是位置永远是紧挨着的一串小整数，不会越拖越挤 ——
    /// 代价是这一编让整组兄弟的记录同时变脏，账上都得记（ADR-0002 的紧凑整数不动）。
    private func renumber(_ group: SiblingGroup, as order: [TodoItem]) {
        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element.id, $0.offset) })
        for i in todos.indices where todos[i].siblingGroup == group {
            todos[i].order = positions[todos[i].id]
        }
        logSyncChange { log in
            for todo in todos where todo.siblingGroup == group { log.recordSave(todo.changeEntry) }
        }
    }

    // MARK: - 子待办的树

    /// 一条待办的直接子待办，按兄弟间的位置从上到下 —— 三处展开的树都照这份铺。
    /// 里头可能夹着还开着撤销窗口的删除态记录（占位靠它站在原位），与 `todos(in:)` 同一副脾气；
    /// 数进度用 `childProgress(of:)`，它只数活人。
    public func children(of id: TodoItem.ID) -> [TodoItem] {
        Self.ordered(todos.filter { $0.parentID == id })
    }

    /// 父行上那个安静的进度：直接子女里勾了几个、共几个（删除态的不算数）。
    /// 只数直接子女，不数全后代 —— 每一层只替自己的孩子说话，更深的进度展开了自然看见。
    /// 一个孩子都没有就是 `nil`，视图层照着它决定画不画。
    /// 勾是解耦的：孩子全勾完也不推父，「齐了、该勾父了」由人自己看出来。
    public func childProgress(of id: TodoItem.ID) -> (done: Int, total: Int)? {
        let kids = todos.filter { $0.parentID == id && !$0.isDeleted }
        guard !kids.isEmpty else { return nil }
        return (kids.filter(\.done).count, kids.count)
    }

    /// 在一条待办下面添一步。子待办生在**兄弟末尾** —— 步骤有天然先后，人是按
    /// 1、2、3 的顺序写的，追加在尾才保得住书写顺序（顶层「新记的落最上面」为的是
    /// 「最近的最要紧」，这里刻意不同）。归属分类跟着父；没有自己的计划日。
    /// 父不在或在删除态就什么也不发生 —— 不给死人添孩子。
    public func addSubTodo(_ text: String, under parentID: TodoItem.ID) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty,
              let parent = todos.first(where: { $0.id == parentID }), !parent.isDeleted else { return }
        let group = SiblingGroup(categoryID: parent.categoryID, parentID: parentID)
        let item = TodoItem(
            text: t, categoryID: parent.categoryID, parentID: parentID,
            order: (siblings(of: group).compactMap(\.order).max() ?? -1) + 1
        )
        todos.append(item)
        saveTodos()
        logSyncChange { $0.recordSave(item.changeEntry) }
    }

    /// 入怀：把一条待办连同名下整棵子树挂到另一条下面，落在它孩子的末尾。
    /// 拖一行落在另一行**身上**走这条路；Tab 缩进（挂到上一个兄弟下面）也从这儿过。
    ///
    /// 挂进怀里就离开轴：子待办没有计划日，这一挂顺手撤掉排期 —— 不是一次动了两样，
    /// 是「步骤不单独排期」这条定义的直接推论。完成状态与三个日子里的另两个原样带着。
    /// 挂到自己肚子里不行（目标是自己或自己的子孙），目标在删除态也不行。
    /// - Returns: 这一挂是否落到了实处。视图层照着它告诉系统这次拖拽接住了没有。
    @discardableResult
    public func nestTodo(_ id: TodoItem.ID, under targetID: TodoItem.ID) -> Bool {
        guard let target = todos.first(where: { $0.id == targetID }) else { return false }
        return relocate(id, under: targetID, in: target.categoryID, at: nil)
    }

    /// 落缝：把一条待办放到另一条的**旁边**当兄弟，落在它前头。
    /// 拖一行落在两行之间的缝里走这条路 —— 缝在哪一层，就挂到哪一层：
    /// 顶层两行之间的缝天然就是升级的落点，子树里的缝就是降级或换爹。
    @discardableResult
    public func placeTodo(_ id: TodoItem.ID, before targetID: TodoItem.ID) -> Bool {
        place(id, at: targetID, offset: 0)
    }

    /// 同上，落在它后头 —— 一组兄弟末尾的那道缝只有「谁的后面」说得清。
    @discardableResult
    public func placeTodo(_ id: TodoItem.ID, after targetID: TodoItem.ID) -> Bool {
        place(id, at: targetID, offset: 1)
    }

    private func place(_ id: TodoItem.ID, at targetID: TodoItem.ID, offset: Int) -> Bool {
        guard id != targetID, let target = todos.first(where: { $0.id == targetID }) else { return false }
        let queue = Self.ordered(siblings(of: target.siblingGroup)).filter { $0.id != id }
        guard let at = queue.firstIndex(where: { $0.id == targetID }) else { return false }
        return relocate(id, under: target.parentID, in: target.categoryID, at: at + offset)
    }

    /// Tab 那一下：挂到上一个活着的兄弟下面，成为它的末子。头一个兄弟没有「上一个」，
    /// 什么也不发生 —— 缩不进去就是缩不进去，不发明别的去处。
    @discardableResult
    public func indentTodo(_ id: TodoItem.ID) -> Bool {
        guard let item = todos.first(where: { $0.id == id }) else { return false }
        let queue = Self.ordered(siblings(of: item.siblingGroup)).filter { !$0.isDeleted }
        guard let i = queue.firstIndex(where: { $0.id == id }), i > 0 else { return false }
        return nestTodo(id, under: queue[i - 1].id)
    }

    /// Shift+Tab 那一下，也是右键的「升一级」：升到父的旁边、紧跟在父后面 ——
    /// 从哪儿钻出来就站在哪儿的边上，一眼找得着。顶层没有再往上，什么也不发生。
    @discardableResult
    public func promoteTodo(_ id: TodoItem.ID) -> Bool {
        guard let item = todos.first(where: { $0.id == id }), let parentID = item.parentID else { return false }
        return place(id, at: parentID, offset: 1)
    }

    /// 树上一切挪动的最后一站：挂到新位置（换位置、入怀、升降级、换爹说的都是这一件事）。
    /// - Parameters:
    ///   - newParent: 挂到谁下面，`nil` 是顶层。
    ///   - categoryID: 落进哪个分类。有父随父（调用处已对齐），顶层由落点说了算。
    ///   - index: 在新兄弟组里的第几位，`nil` 贴末尾。
    private func relocate(
        _ id: TodoItem.ID, under newParent: TodoItem.ID?, in categoryID: Category.ID, at index: Int?
    ) -> Bool {
        guard let item = todos.first(where: { $0.id == id }), !item.isDeleted,
              category(categoryID) != nil else { return false }
        if let newParent {
            // 挂到自己肚子里会把整棵树拎离地面 —— 自己、或自己的子孙，都不接。
            guard newParent != id, !descendantIDs(of: id).contains(newParent),
                  let parent = todos.first(where: { $0.id == newParent }), !parent.isDeleted,
                  parent.categoryID == categoryID else { return false }
        }
        let oldGroup = item.siblingGroup
        let newGroup = SiblingGroup(categoryID: categoryID, parentID: newParent)
        var queue = Self.ordered(siblings(of: newGroup)).filter { $0.id != id }
        update(id) {
            $0.parentID = newParent
            $0.categoryID = categoryID
            if newParent != nil { $0.plannedOn = nil }
        }
        if categoryID != oldGroup.categoryID { carryDescendants(of: id, to: categoryID) }
        guard let moved = todos.first(where: { $0.id == id }) else { return false }
        queue.insert(moved, at: min(max(index ?? queue.count, 0), queue.count))
        renumber(newGroup, as: queue)
        saveTodos()
        return true
    }

    /// 名下所有子孙的 id，不含自己，一层层收。只看住在 `todos` 数组里的
    /// （活人与还开着窗口的删除态）—— 池子里的各有各的路。
    /// 见过环不再进（同步可能合出怪状态），于是永远收得完。
    private func descendantIDs(of id: TodoItem.ID) -> Set<TodoItem.ID> {
        var seen: Set<TodoItem.ID> = []
        var frontier: Set<TodoItem.ID> = [id]
        while !frontier.isEmpty {
            let next = Set(
                todos.filter { todo in
                    guard let parent = todo.parentID else { return false }
                    return frontier.contains(parent) && !seen.contains(todo.id) && todo.id != id
                }.map(\.id))
            seen.formUnion(next)
            frontier = next
        }
        return seen
    }

    /// 同一窝兄弟里的成员。
    private func siblings(of group: SiblingGroup) -> [TodoItem] {
        todos.filter { $0.siblingGroup == group }
    }

    /// 删掉一条待办。删除是打记号：行留在数组原位撑着占位，窗口一关才搬进池子。
    /// 云端那头这只是一次字段更新 —— 记录不消失，见 ADR-0007。
    ///
    /// 删父连子：名下整棵子树一并打记号，打的是**同一个时刻** —— 一扇窗口、一起去、
    /// 一起回。「这事不干了」天然包含它的步骤。先前已各自死掉的子孙带着各自的时刻，
    /// 不搭这趟车，各走各的窗口。
    public func deleteTodo(_ item: TodoItem) {
        guard let i = todos.firstIndex(where: { $0.id == item.id }), !todos[i].isDeleted else { return }
        let fellAt = Date.now
        let felled = ([item.id] + descendantIDs(of: item.id)).filter { id in
            todos.first { $0.id == id }?.isDeleted == false
        }
        for j in todos.indices where felled.contains(todos[j].id) {
            todos[j].deletedAt = fellAt
        }
        saveTodos()
        logSyncChange { log in
            for todo in todos where felled.contains(todo.id) { log.recordSave(todo.changeEntry) }
        }
        openUndoWindow(.todo(item.id), fellAt: fellAt)
    }

    /// 改一条待办，落盘并记账。手里那份可能是视图层拿着的旧副本，所以一律按 id 现找现改 ——
    /// 没找着（比如同时被删了）就什么也不发生，返回 `false`。
    /// 打勾、改写、排期、改期、换分类都从这儿过，账因此一处也漏不掉。
    @discardableResult
    private func update(_ id: TodoItem.ID, _ change: (inout TodoItem) -> Void) -> Bool {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return false }
        change(&todos[i])
        saveTodos()
        logSyncChange { $0.recordSave(todos[i].changeEntry) }
        return true
    }

    // MARK: - Favorites

    public func addFavorite(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let item: FavoriteItem
        if t.lowercased().hasPrefix("http://") || t.lowercased().hasPrefix("https://"),
           let url = URL(string: t) {
            let title = url.host()?.replacingOccurrences(of: "www.", with: "") ?? t
            item = FavoriteItem(title: title, urlString: t)
        } else {
            item = FavoriteItem(title: t)
        }
        favorites.append(item)
        saveFavorites()
        logSyncChange { $0.recordSave(item.changeEntry) }
    }

    /// 删掉一条收藏。与待办同一套：打记号、占位、窗口一关进池子。
    public func deleteFavorite(_ item: FavoriteItem) {
        guard let i = favorites.firstIndex(where: { $0.id == item.id }), !favorites[i].isDeleted else { return }
        favorites[i].deletedAt = .now
        saveFavorites()
        logSyncChange { $0.recordSave(favorites[i].changeEntry) }
        openUndoWindow(.favorite(item.id))
    }

    // MARK: - 撤销窗口

    /// 每次删除各开一个窗口、各自倒计时、各自撤 —— 连删几条也救得准中间那条。
    /// 窗口的寿命就是占位的寿命：几秒一到占位塌掉，记录沉进池子。见 ADR-0007。
    public static let undoWindowSeconds: TimeInterval = 5

    /// 撤销：⌘Z 按删除时间从新到旧收，不管那个占位当下在不在眼前。
    /// 一路点得回去 —— 每收一条，再上一条就是下一个。
    public func undoLastDelete() {
        guard let entry = pendingUndos.last else { return }
        switch entry.target {
        case .todo(let id): undeleteTodo(id)
        case .category(let id): undeleteCategory(id)
        case .favorite(let id): undeleteFavorite(id)
        }
    }

    /// 撤销一条待办的删除：摘掉记号，它原样回到原来的位置（所有字段都没动过）。
    /// 活着的待办的分类必须活着 —— 分类若也在删除态，先把它救活；
    /// 活着的子的父也必须活着 —— 祖先链一并救，见 ADR-0007 的不变式。
    ///
    /// 删父连子的另一半：和它**同一时刻**倒下的整棵子树一起回来 ——
    /// 先前各自死掉的带着各自的时刻，不搭这趟车，各归各的窗口。
    public func undeleteTodo(_ id: TodoItem.ID) {
        if let i = todos.firstIndex(where: { $0.id == id }), todos[i].isDeleted {
            let fellAt = todos[i].deletedAt
            undeleteCategoryIfNeeded(todos[i].categoryID)
            reviveAncestorsIfNeeded(from: todos[i].parentID)
            let revived = ([id] + descendantIDs(of: id)).filter { rid in
                todos.first { $0.id == rid }?.deletedAt == fellAt
            }
            for j in todos.indices where revived.contains(todos[j].id) {
                todos[j].deletedAt = nil
            }
            saveTodos()
            logSyncChange { log in
                for todo in todos where revived.contains(todo.id) { log.recordSave(todo.changeEntry) }
            }
            dismissUndoEntry(for: .todo(id))
            return
        }
        // 窗口已关、记录在池子里：本地界面到不了这儿，同步的复活走的是这条路。
        // 只救这一条 —— 云端的复活一条记录一条记录地来，各救各的。
        guard let j = deletedTodos.firstIndex(where: { $0.id == id }) else { return }
        var item = deletedTodos.remove(at: j)
        saveDeletedTodos()
        item.deletedAt = nil
        undeleteCategoryIfNeeded(item.categoryID)
        reviveAncestorsIfNeeded(from: item.parentID)
        let at = todos.firstIndex { $0.createdAt > item.createdAt } ?? todos.endIndex
        todos.insert(item, at: at)
        saveTodos()
        logSyncChange { $0.recordSave(item.changeEntry) }
    }

    /// 不变式的另一半：活着的子，父必须活着 —— 哪条路救活一条待办，祖先链就跟着复活。
    /// 只救链上的节点自己，不连带它们的子树：陪祖先一起死的别的孩子没人叫它，不回来
    /// （与「待办胜、分类复活」同一个分寸 —— 复活只救到不变式要求的最少那几个）。
    /// 祖先的撤销窗口**不**就此关上：窗口到点照样清扫，剩在删除态里的那些一个不漏。
    /// 见过环不再走（同步可能合出怪状态），于是永远走得完。
    private func reviveAncestorsIfNeeded(from parentID: TodoItem.ID?) {
        var next = parentID
        var walked = Set<TodoItem.ID>()
        while let id = next, walked.insert(id).inserted {
            if let i = todos.firstIndex(where: { $0.id == id }) {
                if todos[i].isDeleted {
                    todos[i].deletedAt = nil
                    saveTodos()
                    logSyncChange { $0.recordSave(todos[i].changeEntry) }
                }
                undeleteCategoryIfNeeded(todos[i].categoryID)
                next = todos[i].parentID
            } else if let j = deletedTodos.firstIndex(where: { $0.id == id }) {
                var item = deletedTodos.remove(at: j)
                saveDeletedTodos()
                item.deletedAt = nil
                undeleteCategoryIfNeeded(item.categoryID)
                let at = todos.firstIndex { $0.createdAt > item.createdAt } ?? todos.endIndex
                todos.insert(item, at: at)
                saveTodos()
                logSyncChange { $0.recordSave(item.changeEntry) }
                next = item.parentID
            } else {
                // 父根本不在本地（记录还没送到）：这儿救不了，孤儿机制管到底。
                next = nil
            }
        }
    }

    /// 撤销一个分类的删除：摘掉记号（占位还开着），或从池子里按死时的位置插回活人堆。
    /// 两条路都要把身后活人的位置重新记账 —— 它一回来，后面的都往后挪了一位。
    public func undeleteCategory(_ id: Category.ID) {
        if let i = categories.firstIndex(where: { $0.id == id }), categories[i].isDeleted {
            categories[i].deletedAt = nil
            saveCategories()
            dismissUndoEntry(for: .category(id))
            logSyncChange { log in
                for category in categories[i...] where !category.isDeleted {
                    log.recordSave(category.changeEntry)
                }
            }
            return
        }
        guard let j = deletedCategories.firstIndex(where: { $0.category.id == id }) else { return }
        var placed = deletedCategories.remove(at: j)
        saveDeletedCategories()
        placed.category.deletedAt = nil
        insertCategory(placed.category, atLivingPosition: placed.position)
        saveCategories()
        guard let at = categories.firstIndex(where: { $0.id == id }) else { return }
        logSyncChange { log in
            for category in categories[at...] where !category.isDeleted {
                log.recordSave(category.changeEntry)
            }
        }
    }

    /// 撤销一条收藏的删除。
    public func undeleteFavorite(_ id: FavoriteItem.ID) {
        if let i = favorites.firstIndex(where: { $0.id == id }), favorites[i].isDeleted {
            favorites[i].deletedAt = nil
            saveFavorites()
            dismissUndoEntry(for: .favorite(id))
            logSyncChange { $0.recordSave(favorites[i].changeEntry) }
            return
        }
        guard let j = deletedFavorites.firstIndex(where: { $0.id == id }) else { return }
        var item = deletedFavorites.remove(at: j)
        saveDeletedFavorites()
        item.deletedAt = nil
        let at = favorites.firstIndex { $0.createdAt > item.createdAt } ?? favorites.endIndex
        favorites.insert(item, at: at)
        saveFavorites()
        logSyncChange { $0.recordSave(item.changeEntry) }
    }

    /// 不变式的执行处：哪条路救活一条待办，分类就跟着复活。活着的就什么也不做。
    private func undeleteCategoryIfNeeded(_ id: Category.ID) {
        guard category(id) == nil else { return }
        undeleteCategory(id)
    }

    /// 开一扇撤销窗口，几秒后自己关上。窗口是会话态：不落盘，重启即全关。
    private func openUndoWindow(_ target: PendingUndo.Target, fellAt: Date? = nil) {
        let entry = PendingUndo(target: target, fellAt: fellAt)
        pendingUndos.append(entry)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoWindowSeconds))
            self?.expireUndoWindow(entry.id)
        }
    }

    /// 窗口到点关上：占位塌掉，记录搬进池子。已经撤销过（条目没了）就什么也不做。
    /// 内部可见只为可测 —— 测试不必真等那几秒。
    func expireUndoWindow(_ token: PendingUndo.ID) {
        guard let index = pendingUndos.firstIndex(where: { $0.id == token }) else { return }
        let entry = pendingUndos.remove(at: index)
        switch entry.target {
        case .todo(let id):
            // 按那一斧的时刻清扫，不只认树根：树里可能有谁先被单独救活了
            // （同步来的复活只救祖先链），剩下还躺着的照样一个不漏地进池子。
            let felled = todos.filter { $0.isDeleted && ($0.id == id || $0.deletedAt == entry.fellAt) }
            guard !felled.isEmpty else { return }
            let felledIDs = Set(felled.map(\.id))
            deletedTodos.append(contentsOf: felled)
            todos.removeAll { felledIDs.contains($0.id) }
            saveTodos()
            saveDeletedTodos()
        case .category(let id):
            guard let i = categories.firstIndex(where: { $0.id == id }), categories[i].isDeleted else { return }
            deletedCategories.append(
                PlacedCategory(category: categories.remove(at: i), position: livingPosition(before: i))
            )
            saveCategories()
            saveDeletedCategories()
        case .favorite(let id):
            guard let i = favorites.firstIndex(where: { $0.id == id }), favorites[i].isDeleted else { return }
            deletedFavorites.append(favorites.remove(at: i))
            saveFavorites()
            saveDeletedFavorites()
        }
    }

    /// 撤销落定（本地点了撤销，或云端来的版本说它活着）：这扇窗口不再有事可做。
    private func dismissUndoEntry(for target: PendingUndo.Target) {
        pendingUndos.removeAll { $0.target == target }
    }

    // MARK: - 同步

    /// 云端来的一条收藏，静静落在该在的位置。收藏没有编辑，唯一会变的方面是删除记号 ——
    /// 本地还欠着它一笔保存（刚删或刚撤销、还没送出去）就以本地为准：云端这份是迟到的旧样子，
    /// 不该被网络时序顶回来（从前墓碑挡的就是这一手）。
    /// 活着的：已有同名的原样替换，没有的按收藏时刻插进流里 —— 两台设备各收各的，
    /// 最后看到的是同一条按时间铺开的流。删除态的进池子；占位还开着就留在原位。
    func applyRemoteFavorite(_ item: FavoriteItem) {
        guard !syncLog.isTombstoned(item.changeEntry) else { return }
        guard !syncLog.pendingSaves.contains(item.changeEntry) else { return }
        if item.isDeleted {
            if pendingUndos.contains(where: { $0.target == .favorite(item.id) }),
               let i = favorites.firstIndex(where: { $0.id == item.id }) {
                favorites[i] = item
            } else {
                favorites.removeAll { $0.id == item.id }
                deletedFavorites.removeAll { $0.id == item.id }
                deletedFavorites.append(item)
                saveDeletedFavorites()
            }
        } else {
            deletedFavorites.removeAll { $0.id == item.id }
            saveDeletedFavorites()
            dismissUndoEntry(for: .favorite(item.id))
            if let i = favorites.firstIndex(where: { $0.id == item.id }) {
                favorites[i] = item
            } else {
                let at = favorites.firstIndex { $0.createdAt > item.createdAt } ?? favorites.endIndex
                favorites.insert(item, at: at)
            }
        }
        saveFavorites()
    }

    /// 云端来的一条收藏的**记录删除**。新语义下记录只增改不消失（ADR-0007），
    /// 这只可能来自还没升级的旧客户端 —— 转成本地的删除态进池子，内容能留多少留多少。
    /// 远端来的删除不开撤销窗口，静静落下。
    func applyRemoteFavoriteDeletion(recordName: String) {
        guard let id = UUID(uuidString: recordName) else { return }
        dismissUndoEntry(for: .favorite(id))
        if let i = favorites.firstIndex(where: { $0.id == id }) {
            var item = favorites.remove(at: i)
            if item.deletedAt == nil { item.deletedAt = .now }
            deletedFavorites.removeAll { $0.id == id }
            deletedFavorites.append(item)
            saveFavorites()
            saveDeletedFavorites()
        }
        settleSyncSave(recordName: recordName)
    }

    /// 引擎发记录时按名字取货。删除态的照发 —— 删除在云端就是一次字段更新，
    /// 池子里的记录也是记录。真取不着才是本地根本没有这条，引擎照着 `nil` 放弃那次保存。
    func favorite(recordName: String) -> FavoriteItem? {
        guard let id = UUID(uuidString: recordName) else { return nil }
        return favorites.first { $0.id == id } ?? deletedFavorites.first { $0.id == id }
    }

    /// 同上，取的是待办。
    func todo(recordName: String) -> TodoItem? {
        guard let id = UUID(uuidString: recordName) else { return nil }
        return todos.first { $0.id == id } ?? deletedTodos.first { $0.id == id }
    }

    /// 同上，取的是分类。此刻在活人中排第几一并带出 —— 位置不落在模型上
    /// （`categories` 数组的顺序就是顺序），云端的记录却少不了这个字段。
    /// 删除态的带死时的位置：那是它撤销时该回去的地方。
    func category(recordName: String) -> (category: Category, position: Int)? {
        guard let id = UUID(uuidString: recordName) else { return nil }
        if let i = categories.firstIndex(where: { $0.id == id }) {
            return (categories[i], livingPosition(before: i))
        }
        if let placed = deletedCategories.first(where: { $0.category.id == id }) {
            return (placed.category, placed.position)
        }
        return nil
    }

    /// 云端来的一条待办，静静落在该在的位置。本地没动过它就整条照收；本地还欠着
    /// 它的一笔保存（两边同时在改）就三方合并：影子、本地、云端对比，本地改过的
    /// 方面重放到云端版上 —— 一边改写、一边改期，两边都保住。删除记号也是普通的
    /// 一个方面：这台删、那台改字，合出来是一条带着新改的字、躺在删除态里的记录 ——
    /// 撤销救回来的正是改过的版本；两台都动记号，后写的算。见 ADR-0007。
    ///
    /// 合并后活着的落回活人堆（占位开着就当场撤销落定）；删除态的进池子 ——
    /// 除非它的占位还开着：那是本地刚删、云端回声，占位继续站着。
    ///
    /// 活着的待办要有活着的分类：归属的分类还没到（云端的抓取不保证先送分类）
    /// 就先去候着，一条也不丢；归属的分类在本地是删除态，那是「删分类」对上了
    /// 「往里记待办」—— 待办胜，分类复活（不变式，同步也不例外）。
    /// 删除态的待办没有这个要求，分类在不在都进池子。
    /// - Parameter modifiedAt: 云端这份的 modificationDate，判「后写」的云端一半。
    func applyRemoteTodo(_ item: TodoItem, modifiedAt: Date? = nil) {
        guard !syncLog.isTombstoned(item.changeEntry) else { return }
        var landed = item
        if let local = todos.first(where: { $0.id == item.id }) ?? deletedTodos.first(where: { $0.id == item.id }),
           syncLog.pendingSaves.contains(item.changeEntry) {
            landed = SyncMerge.todo(
                shadow: syncShadows.todo(named: item.recordName),
                local: local,
                remote: item,
                localIsLater: localWroteLater(item.recordName, than: modifiedAt)
            )
        }
        if landed.isDeleted, todos.contains(where: { child in
            child.parentID == landed.id && !child.isDeleted
                && syncLog.pendingSaves.contains(child.changeEntry)
        }) {
            // 这台往树里加子（或改子）、那台删父 —— 子胜，父复活，与「待办胜、分类复活」
            // 同一条不变式。只看本地还欠着账的孩子：不欠账而暂时活着的，多半是它自己的
            // 删除记录还在路上，不该拿来翻案。复活是本地的表态，记账推回云端。
            landed.deletedAt = nil
            logSyncChange { $0.recordSave(landed.changeEntry) }
        }
        if landed.isDeleted {
            if pendingUndos.contains(where: { $0.target == .todo(item.id) }),
               let i = todos.firstIndex(where: { $0.id == item.id }) {
                todos[i] = landed
            } else {
                todos.removeAll { $0.id == item.id }
                deletedTodos.removeAll { $0.id == item.id }
                deletedTodos.append(landed)
                saveDeletedTodos()
            }
        } else {
            if category(landed.categoryID) == nil {
                undeleteCategoryIfDeletedState(landed.categoryID)
                if category(landed.categoryID) == nil, !reviveBuriedCategory(landed.categoryID) {
                    stashOrphan(landed)
                    return
                }
            }
            if let parentID = landed.parentID {
                guard todos.contains(where: { $0.id == parentID })
                        || deletedTodos.contains(where: { $0.id == parentID }) else {
                    // 父的记录还没送到 —— 与分类同一个待遇：先候着，父一落地就跟着落。
                    stashOrphan(landed)
                    return
                }
                // 活着的子要有活着的父：父在本地是删除态，就是「删父」对上了「改子」——
                // 子胜，祖先链复活。
                reviveAncestorsIfNeeded(from: parentID)
            }
            deletedTodos.removeAll { $0.id == item.id }
            saveDeletedTodos()
            dismissUndoEntry(for: .todo(item.id))
            if let i = todos.firstIndex(where: { $0.id == item.id }) {
                todos[i] = landed
            } else {
                // 按创建时刻插进数组 —— 数组的先后就是轴上同一天里的先后，
                // 两台设备各收各的，最后同一天里看到的次序也该是同一个。
                let at = todos.firstIndex { $0.createdAt > landed.createdAt } ?? todos.endIndex
                todos.insert(landed, at: at)
            }
            healTreeShape(around: landed.id)
            adoptOrphans(childrenOf: landed.id)
        }
        saveTodos()
        // 影子对齐到云端此刻的样子 —— 合并后本地多出的那些改动还挂在账上，
        // 下一轮推上去；影子先说清「云端现在是什么」，下次冲突才对得出账。
        syncShadows.align(todo: item)
        saveShadows()
    }

    /// 云端来的一条待办的**记录删除**。新语义下记录只增改不消失（ADR-0007），
    /// 这只可能来自还没升级的旧客户端 —— 转成本地的删除态进池子，内容能留多少留多少；
    /// 还在候着没落地的一并撤掉。远端来的删除不开撤销窗口，静静落下。
    func applyRemoteTodoDeletion(recordName: String) {
        guard let id = UUID(uuidString: recordName) else { return }
        dismissUndoEntry(for: .todo(id))
        if let i = todos.firstIndex(where: { $0.id == id }) {
            var item = todos.remove(at: i)
            if item.deletedAt == nil { item.deletedAt = .now }
            deletedTodos.removeAll { $0.id == id }
            deletedTodos.append(item)
            saveTodos()
            saveDeletedTodos()
        }
        settleSyncSave(recordName: recordName)
        syncShadows.drop(recordName: recordName)
        saveShadows()
        if orphanTodos.contains(where: { $0.id == id }) {
            orphanTodos.removeAll { $0.id == id }
            saveOrphans()
        }
    }

    /// 不变式在同步里的那一半：分类在本地是删除态（占位开着或已进池子）就救活它。
    /// 复活是本地的一次表态，`undeleteCategory` 会把它记上账、推回云端。
    private func undeleteCategoryIfDeletedState(_ id: Category.ID) {
        if categories.contains(where: { $0.id == id && $0.isDeleted })
            || deletedCategories.contains(where: { $0.category.id == id }) {
            undeleteCategory(id)
        }
    }

    /// 云端来的一个分类，落到它记录里写的那个位置上（活人中的第几位）。本地没动过它
    /// 就整条照收；本地还欠着它的一笔保存就三方合并 —— 一边改名、一边换色，两边都保住，
    /// 删除记号也是普通的一个方面。两台各自建过同名分类就是两个分类 —— UUID 不同，
    /// 并集里并存，不做自动合并。
    ///
    /// 合并后删除态的：里头还有活着的待办就是「删分类」对上了「往里记待办」——
    /// 待办胜、分类复活，复活是本地的表态，记账推回云端；真空的进池子（占位开着就留在原位）。
    /// 活着的落回活人堆，并把候着的孤儿待办接回来。
    ///
    /// 一批里有好几个分类时，调用方按位置从小到大交进来（`CloudSync.landingOrder`
    /// 摆正次序）—— 这儿逐条「插到第几位」，从小到大插完的一排才是记录说的那一排。
    /// - Parameter modifiedAt: 云端这份的 modificationDate，判「后写」的云端一半。
    func applyRemoteCategory(_ category: Category, position: Int, modifiedAt: Date? = nil) {
        guard !syncLog.isTombstoned(category.changeEntry) else { return }
        var landing = PlacedCategory(category: category, position: position)
        let local: PlacedCategory? =
            if let i = categories.firstIndex(where: { $0.id == category.id }) {
                PlacedCategory(category: categories[i], position: livingPosition(before: i))
            } else {
                deletedCategories.first { $0.category.id == category.id }
            }
        if let local, syncLog.pendingSaves.contains(category.changeEntry) {
            landing = SyncMerge.category(
                shadow: syncShadows.category(named: category.recordName),
                local: local,
                remote: landing,
                localIsLater: localWroteLater(category.recordName, than: modifiedAt)
            )
        }
        if landing.category.isDeleted, !livingTodos(in: category.id).isEmpty {
            // 待办胜：云端说删，本地里头还有活人 —— 分类留下，把复活说给云端。
            landing.category.deletedAt = nil
            logSyncChange { $0.recordSave(landing.category.changeEntry) }
        }
        if landing.category.isDeleted {
            if pendingUndos.contains(where: { $0.target == .category(category.id) }),
               let i = categories.firstIndex(where: { $0.id == category.id }) {
                categories[i] = landing.category
                saveCategories()
            } else {
                categories.removeAll { $0.id == category.id }
                deletedCategories.removeAll { $0.category.id == category.id }
                deletedCategories.append(landing)
                saveCategories()
                saveDeletedCategories()
            }
        } else {
            deletedCategories.removeAll { $0.category.id == category.id }
            saveDeletedCategories()
            dismissUndoEntry(for: .category(category.id))
            categories.removeAll { $0.id == category.id }
            insertCategory(landing.category, atLivingPosition: max(landing.position, 0))
            saveCategories()
        }
        syncShadows.align(category: PlacedCategory(category: category, position: position))
        saveShadows()
        if !landing.category.isDeleted { adoptOrphans(of: category.id) }
    }

    /// 云端来的一个分类的**记录删除**。新语义下记录只增改不消失（ADR-0007），
    /// 这只可能来自还没升级的旧客户端。里头还有活着的待办就是「删分类」对上了
    /// 「往里记待办」：待办胜，分类留下，复活记账推回云端。真空的转成删除态进池子 ——
    /// 归属它的待办仍可能从别处晚一步到来，复活的料就在池子里。
    func applyRemoteCategoryDeletion(recordName: String) {
        guard let id = UUID(uuidString: recordName),
              let index = categories.firstIndex(where: { $0.id == id }) else { return }
        guard livingTodos(in: id).isEmpty else {
            logSyncChange { $0.recordSave(categories[index].changeEntry) }
            return
        }
        dismissUndoEntry(for: .category(id))
        var buried = PlacedCategory(category: categories[index], position: livingPosition(before: index))
        if buried.category.deletedAt == nil { buried.category.deletedAt = .now }
        categories.remove(at: index)
        deletedCategories.removeAll { $0.category.id == id }
        deletedCategories.append(buried)
        saveCategories()
        saveDeletedCategories()
        // 欠着的改名换色已无处可去 —— 云端删了它，本地也认了，那笔账就此勾销。
        settleSyncSave(recordName: recordName)
    }

    /// 云端来的待办指认的分类躺在**旧版本的殉葬品**里（硬删除时代埋下的）：
    /// 待办胜，分类带着名字、颜色与位置复活。新语义下不再下葬（池子接了这活儿），
    /// 这条路只为迁移期还埋着的旧坟留着。
    private func reviveBuriedCategory(_ id: Category.ID) -> Bool {
        guard let buried = syncShadows.exhumeCategory(named: id.uuidString) else { return false }
        saveShadows()
        insertCategory(buried.category, atLivingPosition: max(buried.position, 0))
        saveCategories()
        logSyncChange { $0.recordSave(buried.category.changeEntry) }
        return true
    }

    /// 本地这笔欠账是不是比云端那份写得晚。本地一半是账本上记的改动时刻，
    /// 云端一半是记录的 modificationDate —— 两个都是「写下的那一刻」的近似，
    /// 平手让云端胜：它至少是双方都看得见的那一份。
    private func localWroteLater(_ recordName: String, than remote: Date?) -> Bool {
        (syncLog.editedAt[recordName] ?? .distantPast) > (remote ?? .distantPast)
    }

    /// 一条没处落的云端待办先在这儿候着。同一条来了新版本就换掉旧的 —— 候着的也讲后写胜。
    private func stashOrphan(_ item: TodoItem) {
        orphanTodos.removeAll { $0.id == item.id }
        orphanTodos.append(item)
        saveOrphans()
    }

    /// 分类落地了，把候着的它名下的待办接回来。走 `applyRemoteTodo` 的原路 ——
    /// 墓碑、整条替换、按创建时刻插队，规矩一条不少。
    private func adoptOrphans(of categoryID: Category.ID) {
        let adoptable = orphanTodos.filter { $0.categoryID == categoryID }
        guard !adoptable.isEmpty else { return }
        orphanTodos.removeAll { $0.categoryID == categoryID }
        saveOrphans()
        for item in adoptable { applyRemoteTodo(item) }
    }

    /// 父落地了，把候着的它名下的孩子接回来 —— 与分类接孤儿同一条路。
    /// 一层接一层：孩子落了地，孙辈的候着的跟着这条路再落。
    private func adoptOrphans(childrenOf parentID: TodoItem.ID) {
        let adoptable = orphanTodos.filter { $0.parentID == parentID }
        guard !adoptable.isEmpty else { return }
        orphanTodos.removeAll { $0.parentID == parentID }
        saveOrphans()
        for item in adoptable { applyRemoteTodo(item) }
    }

    /// 同步落地后把树修圆。字段级合并对的是单条记录，跨记录的形状只能事后看一眼：
    /// 两台各把对方挂进自己怀里会合出一个**环**，断在刚落地的这条 —— 升它到顶层；
    /// 树的**分类**永远跟着根走 —— 子随父正，再把自己名下的正过来。
    /// 修补是本地的表态，记账推回云端；两台各修各的，修出来是同一个形状。
    private func healTreeShape(around id: TodoItem.ID) {
        var walked: Set<TodoItem.ID> = []
        var next = todos.first(where: { $0.id == id })?.parentID
        while let n = next {
            guard n != id, walked.insert(n).inserted else {
                if let i = todos.firstIndex(where: { $0.id == id }) {
                    todos[i].parentID = nil
                    logSyncChange { $0.recordSave(todos[i].changeEntry) }
                }
                break
            }
            next = (todos.first { $0.id == n } ?? deletedTodos.first { $0.id == n })?.parentID
        }
        guard let item = todos.first(where: { $0.id == id }) else { return }
        var expected = item.categoryID
        if let parentID = item.parentID,
           let parent = todos.first(where: { $0.id == parentID })
            ?? deletedTodos.first(where: { $0.id == parentID }),
           parent.categoryID != expected {
            expected = parent.categoryID
            update(id) { $0.categoryID = expected }
        }
        carryDescendants(of: id, to: expected)
    }

    /// 保存送达云端，销账。
    func settleSyncSave(recordName: String) {
        syncLog.settleSave(recordName: recordName)
        save(syncLog, to: Self.syncLogFile)
    }

    /// 删除送达云端（或云端确认根本没这条），墓碑撤掉。影子跟着撤 ——
    /// 它说的是一条两边都还有的记录。殉葬品不撤：复活的机会比墓碑活得久。
    func settleSyncDelete(recordName: String) {
        syncLog.settleDelete(recordName: recordName)
        save(syncLog, to: Self.syncLogFile)
        syncShadows.drop(recordName: recordName)
        saveShadows()
    }

    /// 保存送达云端的那一刻，本地与云端说的是同一句话 —— 影子对齐到送达的那份。
    /// 送达的间隙里若又有新改动，那是账上的下一笔：影子记的是云端此刻的样子，正合适。
    func alignShadow(todo: TodoItem) {
        syncShadows.align(todo: todo)
        saveShadows()
    }

    /// 同上，对齐的是分类（带它送达时的位置）。
    func alignShadow(category: Category, position: Int) {
        syncShadows.align(category: PlacedCategory(category: category, position: position))
        saveShadows()
    }

    /// 云端整个换了脸（zone 被删、换了账号）：影子说的全是旧库的样子，作废。
    /// 殉葬品照留 —— 本地删过什么与对面是哪个库无关。
    func forgetSyncShadows() {
        syncShadows.forgetAlignments()
        saveShadows()
    }

    /// 首次接上云端时把本地已有的一切记账 —— 同步来之前的存量数据从没进过账本，
    /// 不补这一笔，它们就永远只待在这一台机器上。集合语义，多跑一次也只是同一笔账。
    func enqueueAllForSync() {
        for category in categories { syncLog.recordSave(category.changeEntry) }
        for todo in todos { syncLog.recordSave(todo.changeEntry) }
        for item in favorites { syncLog.recordSave(item.changeEntry) }
        // 池子里的也是记录：不补这一笔，删除态就只留在这一台机器上。
        for placed in deletedCategories { syncLog.recordSave(placed.category.changeEntry) }
        for todo in deletedTodos { syncLog.recordSave(todo.changeEntry) }
        for item in deletedFavorites { syncLog.recordSave(item.changeEntry) }
        save(syncLog, to: Self.syncLogFile)
        syncLogDidChange?()
    }

    /// 记一笔账、落盘、喊一声。本地增删走这条路；云端来的改动不走 —— 那不是欠账。
    private func logSyncChange(_ change: (inout SyncChangeLog) -> Void) {
        change(&syncLog)
        save(syncLog, to: Self.syncLogFile)
        syncLogDidChange?()
    }

    // MARK: - Usage
    // 用量整段只属于 macOS：数据源（本地会话日志、钥匙串）都在那台 Mac 上，
    // 「偏好与用量是这台机器自己的事」—— iOS 构建里这一段整个不存在。
    #if os(macOS)

    /// 本地日志多久重扫一次。读几个文件而已，不花什么，一分钟一次。
    public nonisolated static let usageRefreshInterval: TimeInterval = 60

    /// 限流接口多久调一次。刻意比扫描慢得多：5 小时的窗口最快也就涨 0.33%/分钟，
    /// 一刻钟问一次，两次之间最多动 5%，看这种数字足够了。
    ///
    /// 更要紧的是对方的配额很小 —— 早前按一分钟一次打，很快就被 429，而且罚时不短。
    /// 这个数字是拿罚单换来的，别再往下调。
    nonisolated static let usageLimitsInterval: TimeInterval = 900

    /// 被 429 之后退避到多久。翻倍增长，到这儿封顶。
    nonisolated private static let usageLimitsBackoffCap: TimeInterval = 3600

    /// 下次最早什么时候可以再调那个接口。
    private var limitsNextFetch = Date.distantPast
    private var limitsBackoff: TimeInterval = 0

    /// - Parameter force: 手动点刷新时为真，越过接口自己的节奏立刻问一次 ——
    ///   人点了按钮却什么都不动，比多发一次请求更糟。定时刷新不走这条路。
    public func refreshUsage(force: Bool = false) {
        guard !usageLoading else { return }
        usageLoading = true
        // 接口有它自己的节奏，跟本地扫描分开 —— 扫描每分钟一次，它五分钟一次，被限流还要再退。
        let shouldFetchLimits = force || Date.now >= limitsNextFetch
        // 上一次拿到的限流数据。这次没拿到就接着用它 ——
        // 一次网络抖动不该把卡片上已有的东西擦成一行报错。
        let previous = usage

        Task.detached(priority: .utility) {
            // 本地日志说「用了多少」，接口说「还剩多少」。两件事互不依赖 ——
            // 先把请求发出去，再扫本地日志，等回来时扫描往往已经做完了。
            async let limits = shouldFetchLimits ? ClaudeUsageAPI.fetch() : nil
            async let codexLimits = shouldFetchLimits ? CodexUsageAPI.fetch() : nil
            let local = UsageScanner.scan()
            let claude = await limits
            let codex = await codexLimits

            var snapshot = UsageSnapshot()
            snapshot.claude = local.claude
            snapshot.codex = local.codex
            // 限流窗口说的是「还剩多少」，那是状态，不随日期翻篇 —— 周窗口昨天用掉的量今天
            // 还占着。接口的数字是账号级的实时值，优先；拿不到就退回日志里的快照 ——
            // 快照只在本地跑 Codex 时才更新，云端和别的设备的用量它看不见，陈旧但聊胜于无；
            // 连快照也没有（今天没开过 Codex）就接着显示上次那份，跟 Claude 一个待遇。
            if let codex, !codex.windows.isEmpty {
                snapshot.codexWindows = codex.windows
            } else {
                snapshot.codexWindows = local.codexWindows.isEmpty
                    ? (previous?.codexWindows ?? [])
                    : local.codexWindows
                if snapshot.codexWindows.isEmpty {
                    snapshot.codexLimitsProblem = codex?.problem ?? previous?.codexLimitsProblem
                }
            }

            if let claude, !claude.windows.isEmpty {
                snapshot.claudeWindows = claude.windows
                snapshot.extraSpend = claude.spend
            } else {
                // 没去问，或者问了没拿到 —— 两种情况都接着显示上次那份。
                snapshot.claudeWindows = previous?.claudeWindows ?? []
                snapshot.extraSpend = previous?.extraSpend
                // 只有一份都没有的时候才把原因说出来；有旧数据时报错反而是噪音。
                if snapshot.claudeWindows.isEmpty {
                    snapshot.claudeLimitsProblem = claude?.problem ?? previous?.claudeLimitsProblem
                }
            }

            let final = snapshot
            // 两个接口共用一套节奏与退避 —— 任何一边被 429，下一轮就整体放慢。
            // 分开记账当然更精细，但两份计时器换来的只是「一边挨罚另一边照常」，不值。
            let rateLimited = claude?.isRateLimited == true || codex?.isRateLimited == true
            let fetched = claude != nil || codex != nil
            await MainActor.run {
                self.usage = final
                self.usageLoading = false
                if fetched { self.scheduleNextLimitsFetch(rateLimited: rateLimited) }
            }
        }
    }

    /// 定下次什么时候再问那两个接口。拿到了就回到常规节奏；被限流就翻倍退避，到半小时封顶。
    /// 退避是必须的 —— 被 429 之后继续按原节奏硬打，只会一直 429 下去。
    private func scheduleNextLimitsFetch(rateLimited: Bool) {
        limitsBackoff = Self.nextBackoff(from: limitsBackoff, rateLimited: rateLimited)
        limitsNextFetch = .now.addingTimeInterval(max(limitsBackoff, Self.usageLimitsInterval))
    }

    /// 下一次的退避时长。被挡就翻倍（从常规间隔起步），到封顶为止；一旦成功就清零回常规节奏。
    nonisolated static func nextBackoff(from current: TimeInterval, rateLimited: Bool) -> TimeInterval {
        guard rateLimited else { return 0 }
        return min(max(current * 2, usageLimitsInterval), usageLimitsBackoffCap)
    }

    #endif

    // MARK: - Persistence

    private static let categoriesFile = "categories.json"
    /// 用户的选择偏好。与数据分开存 —— 偏好丢了只是少记住一次选择，不该跟待办同生共死。
    private static let preferencesFile = "preferences.json"
    /// 待办的存放位置。刻意不叫 `todos.json` —— 那是待办还没有所属分类时的旧文件，
    /// 已经废弃：不读取、不转换，装着旧数据的机器首次运行就是空状态。
    private static let todosFile = "todos-v2.json"
    /// 同步的账本。与数据同目录、分开存 —— 它说的是「欠云端什么」，不是数据本身。
    private static let syncLogFile = "sync-changes.json"
    /// 同步的记性：影子副本与殉葬品。同样不是数据本身 —— 丢了顶多让下一次冲突
    /// 退回整条后写胜、让一次复活少了料，本机的待办一条不少。
    private static let shadowsFile = "sync-shadows.json"
    /// 候着的孤儿待办：云端先到的待办，归属的分类还没到。同样与数据分开存 ——
    /// 它们还不是这台机器的数据，只是在等落地的资格。
    private static let orphansFile = "sync-orphans.json"
    /// 删除态的池子。与活人分开存 —— 它们不再是界面要看的数据，只是永远留着的记号，
    /// 见 ADR-0007。
    private static let deletedTodosFile = "deleted-todos.json"
    private static let deletedCategoriesFile = "deleted-categories.json"
    private static let deletedFavoritesFile = "deleted-favorites.json"

    private func saveCategories() { save(categories, to: Self.categoriesFile) }
    private func saveTodos() { save(todos, to: Self.todosFile) }
    private func saveFavorites() { save(favorites, to: "favorites.json") }
    private func saveDeletedTodos() { save(deletedTodos, to: Self.deletedTodosFile) }
    private func saveDeletedCategories() { save(deletedCategories, to: Self.deletedCategoriesFile) }
    private func saveDeletedFavorites() { save(deletedFavorites, to: Self.deletedFavoritesFile) }
    private func saveOrphans() { save(orphanTodos, to: Self.orphansFile) }
    private func saveShadows() { save(syncShadows, to: Self.shadowsFile) }

    private func savePreferences() {
        save(Preferences(
            recordingCategoryID: chosenRecordingCategoryID,
            hidesCompletedOnTimeline: hidesCompletedOnTimeline,
            expandedTodoIDs: expandedTodoIDs.sorted { $0.uuidString < $1.uuidString }
        ), to: Self.preferencesFile)
    }

    private func load<T: Decodable>(_ name: String) -> T? {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(value) {
            try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
    }
}
