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

    // MARK: - Todos

    /// 侧边栏徽标要的数字。派生数据一律从这里出，视图层不自己聚合。
    var unfinishedTodoCount: Int {
        todos.filter { !$0.done }.count
    }

    /// 一个分类的清单，按记下的先后排列。分类之间因此互不干扰。
    func todos(in categoryID: Category.ID) -> [TodoItem] {
        todos.filter { $0.categoryID == categoryID }
    }

    /// 记一条待办。所属分类是必填的 —— 指向一个不存在的分类时什么也不发生，
    /// 于是「每条待办都落在某个分类里」这条约束由 `Store` 保证，不依赖视图层自觉。
    func addTodo(_ text: String, in categoryID: Category.ID) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, categories.contains(where: { $0.id == categoryID }) else { return }
        todos.append(TodoItem(text: t, categoryID: categoryID))
        saveTodos()
    }

    func toggleTodo(_ item: TodoItem) {
        guard let i = todos.firstIndex(where: { $0.id == item.id }) else { return }
        todos[i].done.toggle()
        todos[i].completedAt = todos[i].done ? .now : nil
        saveTodos()
    }

    func deleteTodo(_ item: TodoItem) {
        todos.removeAll { $0.id == item.id }
        saveTodos()
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
    /// 待办的存放位置。刻意不叫 `todos.json` —— 那是待办还没有所属分类时的旧文件，
    /// 已经废弃：不读取、不转换，装着旧数据的机器首次运行就是空状态。
    private static let todosFile = "todos-v2.json"

    private func saveCategories() { save(categories, to: Self.categoriesFile) }
    private func saveTodos() { save(todos, to: Self.todosFile) }
    private func saveFavorites() { save(favorites, to: "favorites.json") }

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
