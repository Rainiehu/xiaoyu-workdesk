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

    /// 一个分类里的待办，按记下的先后排列。分类之间因此互不干扰。
    func todos(in categoryID: Category.ID) -> [TodoItem] {
        todos.filter { $0.categoryID == categoryID }
    }

    /// 分类视图要的两列。三套排序规则都在这儿定死，视图层照着铺就是。
    ///
    /// 左列是两段直接拼起来的，不设分组标题：已排期的在上，按计划日从早到晚；
    /// 未排期的在下，按创建日从新到旧 —— 最近才想到的事不该沉到底部。
    /// 计划日只到天，同一天排了几条是常事，那时按记下的先后排 ——
    /// 顺序写在比较里，不指望 `sorted` 碰巧稳定。
    ///
    /// 右列按完成日从新到旧，最近的成果在最上面。
    func columns(in categoryID: Category.ID) -> CategoryColumns {
        let mine = todos(in: categoryID)
        let unfinished = mine.filter { !$0.done }
        // 排期与否在这儿一次分清：拆出计划日随着待办一起走，下面排序就不必再问它在不在。
        let scheduled = unfinished.compactMap { todo in todo.plannedOn.map { (todo: todo, day: $0) } }
            .sorted { ($0.day, $0.todo.createdAt) < ($1.day, $1.todo.createdAt) }
            .map(\.todo)
        let unscheduled = unfinished.filter { $0.plannedOn == nil }
            .sorted { $0.createdAt > $1.createdAt }
        // 打了勾就必然有完成日；万一数据里缺了，退回创建日 ——
        // 宁可这一条排得不准，也不让它从两列里消失。
        let finished = mine.filter(\.done)
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
        return CategoryColumns(unfinished: scheduled + unscheduled, finished: finished)
    }

    /// 记一条待办。所属分类是必填的 —— 指向一个不存在的分类时什么也不发生，
    /// 于是「每条待办都落在某个分类里」这条约束由 `Store` 保证，不依赖视图层自觉。
    /// - Parameter day: 一并排上的计划日，默认不排 —— 分类视图里记事就是不排期的，
    ///   排期是之后另点一下的事。沙漏视图里记事则当场交一个日子进来，
    ///   好让新记下的这条立刻出现在使用者正看着的那条轴上。
    func addTodo(_ text: String, in categoryID: Category.ID, plannedOn day: Date? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, categories.contains(where: { $0.id == categoryID }) else { return }
        todos.append(TodoItem(text: t, categoryID: categoryID, plannedOn: day))
        saveTodos()
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
        guard categories.contains(where: { $0.id == categoryID }) else { return }
        update(item.id) { $0.categoryID = categoryID }
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

    func refreshUsage() {
        guard !usageLoading else { return }
        usageLoading = true
        Task.detached(priority: .utility) {
            let snapshot = UsageScanner.scan()
            await MainActor.run {
                self.usage = snapshot
                self.usageLoading = false
            }
        }
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
