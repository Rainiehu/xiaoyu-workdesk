import Foundation
import Observation

@Observable
@MainActor
final class Store {
    /// 分类的显示顺序就是这个数组的顺序。
    private(set) var categories: [Category] = []
    private(set) var todos: [TodoItem] = []
    private(set) var favorites: [FavoriteItem] = []
    var usage: UsageSnapshot?
    var usageLoading = false

    /// 上次选来记事的分类。可能指向一个已经不在了的分类 —— 对外的 `recordingCategory` 管这件事。
    private var chosenRecordingCategoryID: Category.ID?

    /// 正常运行时的存储位置。只算路径，不建目录 —— 建目录是 `init` 的事。
    nonisolated static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("XiaoyuWorkdesk", isDirectory: true)
    }

    private let directory: URL

    /// - Parameter directory: 存储目录，默认是 `defaultDirectory`。测试传一个临时目录进来。
    init(directory: URL = Store.defaultDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        categories = load(Self.categoriesFile) ?? []
        todos = load(Self.todosFile) ?? []
        favorites = load("favorites.json") ?? []
        chosenRecordingCategoryID = (load(Self.preferencesFile) as Preferences?)?.recordingCategoryID
        seedOrders()
    }

    /// 给还没有位置的待办补上位置：按老规矩铺一遍 —— 已排期的在上，按计划日从早到晚；
    /// 未排期的在下，按创建日从新到旧。升级上来的人第一眼看到的顺序因此和升级前一模一样，
    /// 从那以后顺序就归自己拖了，见 ADR-0002。
    ///
    /// 已完成的也一并给上位置：它们此刻在右列，但取消打勾就回到左列，那时得有个落脚处。
    /// 一条也不缺就什么都不做 —— 这是一次性的补写，不是每次启动都重排一遍。
    private func seedOrders() {
        guard todos.contains(where: { $0.order == nil }) else { return }
        for categoryID in Set(todos.map(\.categoryID)) {
            renumber(categoryID, as: Self.seededOrder(todos(in: categoryID)))
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
    func addCategory(_ name: String) -> Category? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        let category = Category(name: n, color: nextColor())
        categories.append(category)
        saveCategories()
        return category
    }

    /// 色板中第一个还没被占用的颜色；都被占用了就从头循环，好让分类数量不受色板长度限制。
    private func nextColor() -> CategoryColor {
        let taken = Set(categories.map(\.color))
        return CategoryColor.palette.first { !taken.contains($0) }
            ?? CategoryColor.palette[categories.count % CategoryColor.palette.count]
    }

    /// 按 id 找回一个分类。沙漏视图里每条待办旁的彩色 tag 靠它取名字和颜色 ——
    /// 找不着（分类被删了）就是 `nil`，视图层照着这个决定要不要画那个 tag。
    func category(_ id: Category.ID) -> Category? {
        categories.first { $0.id == id }
    }

    /// 改名。空白名字不改 —— 与 `addCategory` 同一副脾气：分类总得有个名字。
    /// 名字只是称呼，改它碰不到分类的身份，里头的待办一条也不动。
    func renameCategory(_ id: Category.ID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        updateCategory(id) { $0.name = n }
    }

    /// 换颜色。新建时颜色是自动分配的，这里是唯一由用户指定颜色的入口。
    /// 不拦重色 —— 两个分类撞色是用户自己的选择，不该被拦下。
    func recolorCategory(_ id: Category.ID, to color: CategoryColor) {
        updateCategory(id) { $0.color = color }
    }

    /// 把一个分类挪到另一个分类现在的位置上，其余的依次让开 ——
    /// tab 栏上拖着一个 tab 放到另一个 tab 上时走这条路，于是最常用的可以排到前头。
    /// 说的是「放到谁身上」而不是第几位：顺序是 `Store` 的事，视图层不必先去数位置。
    /// 两个都是同一个分类、或者哪一个不存在，都什么也不发生。
    func moveCategory(_ id: Category.ID, onto targetID: Category.ID) {
        guard let from = categories.firstIndex(where: { $0.id == id }),
              let to = categories.firstIndex(where: { $0.id == targetID }), from != to else { return }
        categories.insert(categories.remove(at: from), at: to)
        saveCategories()
    }

    /// 除了这一个之外的分类。待办的「移到分类」菜单列的就是它们 ——
    /// 一条待办没法移到它已经在的地方。
    func categories(besides categoryID: Category.ID) -> [Category] {
        categories.filter { $0.id != categoryID }
    }

    /// 删掉一个分类。**只删得掉空的** —— 里头还有待办（无论完成与否）就拒绝，
    /// 一条待办也不动。删除没有撤销、没有回收站，所以宁可在这儿拦住，
    /// 也不要连带无声地丢掉一批待办。这条约束由 `Store` 保证，不依赖视图层自觉。
    ///
    /// 疏通的路子是 `moveTodo(_:to:)` 或删掉那些待办：分类空了，它自然就删得掉了。
    /// 删到一个不剩是允许的 —— 那时主线回到引导空态，与首次启动是同一个状态。
    @discardableResult
    func deleteCategory(_ id: Category.ID) -> CategoryDeletion {
        guard categories.contains(where: { $0.id == id }) else { return .noSuchCategory }
        let mine = todos(in: id)
        guard mine.isEmpty else { return .refused(todoCount: mine.count) }
        categories.removeAll { $0.id == id }
        saveCategories()
        return .deleted
    }

    /// 改一个分类并落盘。找不着就什么也不发生 —— 与 `update(_:_:)` 同一副脾气。
    private func updateCategory(_ id: Category.ID, _ change: (inout Category) -> Void) {
        guard let i = categories.firstIndex(where: { $0.id == id }) else { return }
        change(&categories[i])
        saveCategories()
    }

    // MARK: - 记事的分类

    /// 沙漏视图记事时归到哪个分类：上次选的那个。还没选过、或选的那个分类没了，
    /// 就落回第一个分类 —— 「记不起来」于是不是一个要视图层去应付的状态。
    /// 一个分类都没有时是 `nil`：那时无处可记，也就不该记出一条无归属的待办。
    var recordingCategory: Category? {
        chosenRecordingCategoryID.flatMap(category) ?? categories.first
    }

    /// 选一个分类来记事。这个选择跨重启保留，好让连续记同一类事情不必反复选。
    /// 指向不存在的分类时什么也不发生，与 `addTodo` 同一副脾气。
    func chooseRecordingCategory(_ id: Category.ID) {
        guard categories.contains(where: { $0.id == id }) else { return }
        chosenRecordingCategoryID = id
        savePreferences()
    }

    /// 在沙漏视图记一条待办：归到当前选来记事的分类，并当场排在今天 ——
    /// 于是它立刻落在那条轴上，而不是凭空消失到某个分类里去。
    /// 「归到哪个分类」和「排在哪一天」这两个决定都在这儿，视图层只管把字交过来。
    /// 一个分类都没有时什么也不发生：那时无处可记，也就不该记出一条无归属的待办。
    /// - Parameter today: 「今天」由调用方交进来，与 `timeline(today:)` 同一副脾气 ——
    ///   这件事因此可测，也没有哪一处偷偷去问一次时钟。交的是时刻，排上的是那个日子。
    func recordOnTimeline(_ text: String, today: Date) {
        guard let category = recordingCategory else { return }
        addTodo(text, in: category.id, plannedOn: today.dayStart)
    }

    // MARK: - Todos

    /// 侧边栏徽标要的数字。派生数据一律从这里出，视图层不自己聚合。
    var unfinishedTodoCount: Int {
        todos.filter { !$0.done }.count
    }

    /// 沙漏视图要的分组：所有分类中排了计划日的待办，按计划日铺成一条轴，日期升序。
    /// 没有计划日的待办不出现在这里；没有待办的日期不产生分组，于是滚动是紧凑的。
    /// 但今天这一组恒定存在 —— 它是那条轴的锚点，空无一事也照样在。
    ///
    /// 已完成的待办落在它的**计划日**，不是完成日：打勾不会让条目跳到别的日期去。
    /// 计划日在过去而未完成的待办也只是留在它那一天，这里不给它任何特殊位置，见 ADR-0001。
    /// - Parameter today: 「今天」是哪天。刻意没有默认值 —— 由调用方交进来，
    ///   分组因此既可测，也不会有哪一处偷偷去问一次时钟。
    func timeline(today: Date) -> [TimelineDay] {
        var byDay: [Date: [TodoItem]] = [today.dayStart: []]
        for todo in todos {
            guard let planned = todo.plannedOn else { continue }
            byDay[planned.dayStart, default: []].append(todo)
        }
        return byDay
            .sorted { $0.key < $1.key }
            .map { TimelineDay(day: $0.key, todos: $0.value) }
    }

    /// 沙漏视图右列要的分组：还没排期的未完成待办，按分类分开，分类的顺序就是 tab 栏上的顺序。
    ///
    /// 它们不在那条轴上（轴按计划日铺），却也不该因此看不见 —— 「总得做但不急」是个正常状态，
    /// 不是缺失。已完成的不在这儿：这一列问的是「还有什么没安排」。
    /// 一条也没有的分类不成组，右列因此是紧凑的。
    /// 组内的先后与分类视图左列一致（使用者自己拖出来的那个），两处看到的顺序永远是同一个。
    var unscheduled: [UnscheduledGroup] {
        categories.compactMap { category in
            let mine = Self.ordered(todos(in: category.id).filter { !$0.done && $0.plannedOn == nil })
            return mine.isEmpty ? nil : UnscheduledGroup(category: category, todos: mine)
        }
    }

    /// 一个分类里的待办，按记下的先后排列。分类之间因此互不干扰。
    func todos(in categoryID: Category.ID) -> [TodoItem] {
        todos.filter { $0.categoryID == categoryID }
    }

    /// 分类视图要的两列。两套排序规则都在这儿定死，视图层照着铺就是。
    ///
    /// 左列按使用者自己拖出来的顺序，不按日期 —— 分类里关心的是「哪件先做」，
    /// 「排在哪天」是沙漏视图的事，见 ADR-0002。已排期与未排期因此不再分成两段，
    /// 混在一列里，靠行尾日期标签的有无自然区分。
    ///
    /// 右列按完成日从新到旧，最近的成果在最上面 —— 那是一份记录，不由人排。
    func columns(in categoryID: Category.ID) -> CategoryColumns {
        let mine = todos(in: categoryID)
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
    func addTodo(_ text: String, in categoryID: Category.ID, plannedOn day: Date? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, categories.contains(where: { $0.id == categoryID }) else { return }
        todos.append(TodoItem(text: t, categoryID: categoryID, plannedOn: day, order: topOrder(in: categoryID)))
        saveTodos()
    }

    /// 落在这个分类最上面要多小的位置。刚记下的事就在眼前，不必先滚到底去找 ——
    /// 不满意再拖走就是。
    private func topOrder(in categoryID: Category.ID) -> Int {
        (todos(in: categoryID).compactMap(\.order).min() ?? 0) - 1
    }

    /// 打勾/取消打勾。完成时刻原样落盘 —— 截到天是显示层的事，底下留着全时刻，
    /// 于是同一天完成的几条仍分得出先后。取消打勾就把它清掉，
    /// 于是「没有完成日」和「没完成」永远是同一件事。
    func toggleTodo(_ item: TodoItem) {
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
    func editTodo(_ item: TodoItem, to text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        update(item.id) { $0.text = t }
    }

    /// 排上计划日，或改到另一天。只动计划日 —— 创建日与完成日各存各的，改期碰不到它们。
    func setPlannedDay(_ day: Date, for item: TodoItem) {
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
    func reschedule(_ id: TodoItem.ID, to day: Date) -> Bool {
        update(id) { $0.plannedOn = day }
    }

    /// 清除计划日，待办回到未排期。未排期是个正常状态，不是缺失 ——
    /// 「总得做但不急」的事就该一直待在这儿。
    func clearPlannedDay(_ item: TodoItem) {
        update(item.id) { $0.plannedOn = nil }
    }

    /// 把一条待办改到另一个分类。归类的想法会变，事情该能换地方；这也是把一个分类腾空的那条路 ——
    /// 非空分类删不掉，没有它就永远删不掉。
    ///
    /// 只改归属：计划日、创建日、完成日与完成状态都不因换分类而变 —— 横轴上的移动不碰纵轴。
    /// 目标分类不存在时什么也不发生，于是「每条待办都落在某个分类里」这条约束在这儿也守得住。
    func moveTodo(_ item: TodoItem, to categoryID: Category.ID) {
        moveTodo(item.id, to: categoryID)
    }

    /// 同一件事，只是认 id 不认待办本身 —— 从分类视图把一行拖到 tab 栏另一个分类上时走这条路，
    /// 拖着走的一路上只有一个身份。
    ///
    /// 落在新分类的最上面：这条待办在原来那个分类里的位置在新分类里没有意义，
    /// 而「刚移过去的那条」该一眼看得见。
    /// 目标就是它已经在的那个分类时什么也不发生 —— 那不是一次移动，位置也不该因此被动过。
    /// - Returns: 这一移是否落到了实处。视图层照着它告诉系统这次拖拽接住了没有。
    @discardableResult
    func moveTodo(_ id: TodoItem.ID, to categoryID: Category.ID) -> Bool {
        guard categories.contains(where: { $0.id == categoryID }),
              let item = todos.first(where: { $0.id == id }), item.categoryID != categoryID else { return false }
        let top = topOrder(in: categoryID)
        return update(id) {
            $0.categoryID = categoryID
            $0.order = top
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
    func reorderTodo(_ id: TodoItem.ID, onto targetID: TodoItem.ID) -> Bool {
        guard id != targetID,
              let moved = todos.first(where: { $0.id == id }),
              let target = todos.first(where: { $0.id == targetID }),
              moved.categoryID == target.categoryID else { return false }
        // 整个分类一起排 —— 已完成的也在这条队伍里，它们此刻在右列，但取消打勾就回到左列。
        var queue = Self.ordered(todos(in: moved.categoryID))
        guard let from = queue.firstIndex(where: { $0.id == id }),
              let to = queue.firstIndex(where: { $0.id == targetID }) else { return false }
        queue.insert(queue.remove(at: from), at: to)
        renumber(moved.categoryID, as: queue)
        saveTodos()
        return true
    }

    /// 把一个分类的位置从头编一遍：交进来的顺序就是从上到下的顺序。
    /// 每次都全编而不是插空，于是位置永远是紧挨着的一串小整数，不会越拖越挤。
    private func renumber(_ categoryID: Category.ID, as order: [TodoItem]) {
        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element.id, $0.offset) })
        for i in todos.indices where todos[i].categoryID == categoryID {
            todos[i].order = positions[todos[i].id]
        }
    }

    func deleteTodo(_ item: TodoItem) {
        todos.removeAll { $0.id == item.id }
        saveTodos()
    }

    /// 改一条待办并落盘。手里那份可能是视图层拿着的旧副本，所以一律按 id 现找现改 ——
    /// 没找着（比如同时被删了）就什么也不发生，返回 `false`。
    @discardableResult
    private func update(_ id: TodoItem.ID, _ change: (inout TodoItem) -> Void) -> Bool {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return false }
        change(&todos[i])
        saveTodos()
        return true
    }

    // MARK: - Favorites

    func addFavorite(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if t.lowercased().hasPrefix("http://") || t.lowercased().hasPrefix("https://"),
           let url = URL(string: t) {
            let title = url.host()?.replacingOccurrences(of: "www.", with: "") ?? t
            favorites.append(FavoriteItem(title: title, urlString: t))
        } else {
            favorites.append(FavoriteItem(title: t))
        }
        saveFavorites()
    }

    func deleteFavorite(_ item: FavoriteItem) {
        favorites.removeAll { $0.id == item.id }
        saveFavorites()
    }

    // MARK: - Usage

    /// 本地日志多久重扫一次。读几个文件而已，不花什么，一分钟一次。
    nonisolated static let usageRefreshInterval: TimeInterval = 60

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
    func refreshUsage(force: Bool = false) {
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
            let local = UsageScanner.scan()
            let claude = await limits

            var snapshot = UsageSnapshot()
            snapshot.claude = local.claude
            snapshot.codex = local.codex
            // 限流窗口说的是「还剩多少」，那是状态，不随日期翻篇 —— 周窗口昨天用掉的量今天
            // 还占着。而它只能从今天动过的会话日志里读到，今天没开过 Codex 就一条也读不着，
            // 于是卡片上两条进度条整个消失。读不着就接着显示上次那份，跟 Claude 一个待遇。
            snapshot.codexWindows = local.codexWindows.isEmpty
                ? (previous?.codexWindows ?? [])
                : local.codexWindows

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
            let outcome = claude
            await MainActor.run {
                self.usage = final
                self.usageLoading = false
                if let outcome { self.scheduleNextLimitsFetch(after: outcome) }
            }
        }
    }

    /// 定下次什么时候再问那个接口。拿到了就回到常规节奏；被限流就翻倍退避，到半小时封顶。
    /// 退避是必须的 —— 被 429 之后继续按原节奏硬打，只会一直 429 下去。
    private func scheduleNextLimitsFetch(after result: ClaudeUsageAPI.Result) {
        limitsBackoff = Self.nextBackoff(from: limitsBackoff, rateLimited: result.isRateLimited)
        limitsNextFetch = .now.addingTimeInterval(max(limitsBackoff, Self.usageLimitsInterval))
    }

    /// 下一次的退避时长。被挡就翻倍（从常规间隔起步），到封顶为止；一旦成功就清零回常规节奏。
    nonisolated static func nextBackoff(from current: TimeInterval, rateLimited: Bool) -> TimeInterval {
        guard rateLimited else { return 0 }
        return min(max(current * 2, usageLimitsInterval), usageLimitsBackoffCap)
    }

    // MARK: - Persistence

    private static let categoriesFile = "categories.json"
    /// 用户的选择偏好。与数据分开存 —— 偏好丢了只是少记住一次选择，不该跟待办同生共死。
    private static let preferencesFile = "preferences.json"
    /// 待办的存放位置。刻意不叫 `todos.json` —— 那是待办还没有所属分类时的旧文件，
    /// 已经废弃：不读取、不转换，装着旧数据的机器首次运行就是空状态。
    private static let todosFile = "todos-v2.json"

    private func saveCategories() { save(categories, to: Self.categoriesFile) }
    private func saveTodos() { save(todos, to: Self.todosFile) }
    private func saveFavorites() { save(favorites, to: "favorites.json") }

    private func savePreferences() {
        save(Preferences(recordingCategoryID: chosenRecordingCategoryID), to: Self.preferencesFile)
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
