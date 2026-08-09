import Foundation
import Testing

@testable import WorkdeskCore

@MainActor
@Suite("沙漏视图的记事")
struct HourglassRecordingTests {
    @Test("在沙漏视图记下的待办归到记事的分类、排在今天，立刻落在那条轴上")
    func recordedTodoLandsOnTodaysGroup() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let today = try day(2026, 3, 5)
            // 交进去的是一个时刻，排上的却该是那个日子 —— 计划日只到天。
            let afternoon = try #require(Calendar.current.date(byAdding: .hour, value: 14, to: today))

            store.recordOnTimeline("写周报", today: afternoon)

            let todo = try #require(store.todos.last)
            #expect(todo.categoryID == work.id)
            #expect(todo.plannedOn == today)
            #expect(store.timeline(today: today).first?.todos.map(\.text) == ["写周报"])
        }
    }

    @Test("记事的分类换一个，之后记下的待办就归到新选的那个")
    func recordingFollowsTheChosenCategory() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addCategory("工作")
            let life = try #require(store.addCategory("生活"))
            let today = try day(2026, 3, 5)

            store.chooseRecordingCategory(life.id)
            store.recordOnTimeline("买菜", today: today)

            #expect(store.todos.last?.categoryID == life.id)
        }
    }

    @Test("还没选过时，记事的分类落在第一个分类上；选过之后就是选的那个")
    func recordingCategoryStartsAtTheFirstAndFollowsTheChoice() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let life = try #require(store.addCategory("生活"))

            #expect(store.recordingCategory == work)

            store.chooseRecordingCategory(life.id)
            #expect(store.recordingCategory == life)
        }
    }

    @Test("上次选的记事分类在重启后仍然是它")
    func theChosenRecordingCategorySurvivesARestart() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addCategory("工作")
            let life = try #require(store.addCategory("生活"))
            store.chooseRecordingCategory(life.id)

            #expect(Store(directory: dir).recordingCategory == life)
        }
    }

    @Test("一个分类都没有时无处记事，也记不出一条无归属的待办")
    func withoutACategoryNothingCanBeRecorded() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)

            #expect(store.recordingCategory == nil)

            store.recordOnTimeline("无处安放", today: try day(2026, 3, 5))
            #expect(store.todos.isEmpty)
        }
    }

    @Test("选一个不存在的分类不作数，上次的选择留着")
    func choosingAMissingCategoryChangesNothing() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addCategory("工作")
            let life = try #require(store.addCategory("生活"))
            store.chooseRecordingCategory(life.id)

            store.chooseRecordingCategory(UUID())

            #expect(store.recordingCategory == life)
        }
    }
}
