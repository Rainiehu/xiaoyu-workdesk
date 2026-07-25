import Foundation
import Testing

@testable import Workdesk

/// 一个确定的日子（当天零点）。断言因此不随「今天是几号」漂移。
func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
    try #require(Calendar.current.date(from: DateComponents(year: year, month: month, day: day)))
}

/// 记一条待办并当场排上计划日。
/// 分类的类型要写全名 —— 光写 `Category` 会撞上 Objective-C 运行时里的同名类型。
@MainActor
func schedule(_ text: String, in category: Workdesk.Category, on day: Date, _ store: Store) throws {
    store.addTodo(text, in: category.id)
    store.setPlannedDay(day, for: try #require(store.todos.last))
}

/// 建一个空的临时目录跑 `body`，跑完删掉。测试因此不碰使用者真实的 Application Support。
func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("WorkdeskTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}
