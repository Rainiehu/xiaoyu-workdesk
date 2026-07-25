import Foundation
import Observation

@Observable
@MainActor
final class Store {
    var todos: [TodoItem] = []
    var favorites: [FavoriteItem] = []
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
        todos = load("todos.json") ?? []
        favorites = load("favorites.json") ?? []
    }

    // MARK: - Todos

    var todayTodos: [TodoItem] {
        todos.filter { $0.createdAt.isToday }
    }

    /// 早前创建、至今未完成的
    var overdueTodos: [TodoItem] {
        todos.filter { !$0.done && !$0.createdAt.isToday }
    }

    /// 历史：按天倒序分组（不含今天）
    var historyByDay: [(day: Date, items: [TodoItem])] {
        let past = todos.filter { !$0.createdAt.isToday }
        let groups = Dictionary(grouping: past) { $0.createdAt.dayStart }
        return groups.keys.sorted(by: >).map { (day: $0, items: groups[$0]!.sorted { $0.createdAt < $1.createdAt }) }
    }

    func addTodo(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        todos.append(TodoItem(text: t))
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

    /// 把早前未完成的挪到今天
    func moveToToday(_ item: TodoItem) {
        guard let i = todos.firstIndex(where: { $0.id == item.id }) else { return }
        todos[i].createdAt = .now
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

    private func saveTodos() { save(todos, to: "todos.json") }
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
