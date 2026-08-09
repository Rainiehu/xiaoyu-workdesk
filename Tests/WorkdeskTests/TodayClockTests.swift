import Foundation
import Testing

@testable import WorkdeskCore

@MainActor
@Suite("今天")
struct TodayClockTests {
    private func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) throws -> Date {
        try #require(Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        ))
    }

    @Test("时刻一直在走，但同一天之内它一动不动")
    func staysPutWithinTheSameDay() throws {
        let morning = try moment(2026, 3, 5, 9, 0)
        let clock = TodayClock(now: morning)

        #expect(!clock.catchUp(to: try moment(2026, 3, 5, 9, 1)))
        #expect(!clock.catchUp(to: try moment(2026, 3, 5, 23, 59)))
        #expect(clock.today == morning)
    }

    @Test("跨过零点就跟上，并且说得出这一下过天了")
    func catchesUpAcrossMidnight() throws {
        let clock = TodayClock(now: try moment(2026, 3, 5, 23, 59))
        let justAfterMidnight = try moment(2026, 3, 6, 0, 1)

        #expect(clock.catchUp(to: justAfterMidnight))
        #expect(clock.today == justAfterMidnight)
        #expect(clock.today.isSameDay(as: justAfterMidnight))
    }

    @Test("睡了几天再醒来，一次就跟到当天，不是一天一天补")
    func catchesUpAfterSeveralDays() throws {
        let clock = TodayClock(now: try moment(2026, 3, 5, 22, 0))
        let backFromTheWeekend = try moment(2026, 3, 9, 10, 0)

        #expect(clock.catchUp(to: backFromTheWeekend))
        #expect(clock.today.isSameDay(as: backFromTheWeekend))
    }

    @Test("时钟往回走也算过天 —— 改了系统日期就该跟着改")
    func catchesUpBackwardsToo() throws {
        let clock = TodayClock(now: try moment(2026, 3, 5))
        let yesterday = try moment(2026, 3, 4, 8, 0)

        #expect(clock.catchUp(to: yesterday))
        #expect(clock.today.isSameDay(as: yesterday))
    }

    @Test("跨过零点之后记事，落在新的一天，不是昨天")
    func recordingAfterMidnightLandsOnTheNewDay() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            store.chooseRecordingCategory(work.id)

            let lateNight = try moment(2026, 3, 5, 23, 30)
            let clock = TodayClock(now: lateNight)
            store.recordOnTimeline("熬夜前记的", today: clock.today)

            // 窗口一直开着，日子自己过去了。
            let justAfterMidnight = try moment(2026, 3, 6, 0, 20)
            #expect(clock.catchUp(to: justAfterMidnight))
            store.recordOnTimeline("零点后记的", today: clock.today)

            let before = try #require(store.todos.first { $0.text == "熬夜前记的" })
            let after = try #require(store.todos.first { $0.text == "零点后记的" })
            #expect(try before.plannedOn == moment(2026, 3, 5))
            #expect(try after.plannedOn == moment(2026, 3, 6))
        }
    }

    @Test("跨过零点之后，轴的锚点是新的那一天")
    func theTimelineAnchorMovesWithTheDay() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            let work = try #require(store.addCategory("工作"))
            let lateNight = try moment(2026, 3, 5, 23, 30)
            store.addTodo("写周报", in: work.id, plannedOn: lateNight.dayStart)

            let clock = TodayClock(now: lateNight)
            // 空无一事也照样成组的只有今天，所以「哪一组是今天」问 timeline 就看得出来。
            #expect(store.timeline(today: clock.today).map(\.day) == [try moment(2026, 3, 5)])

            clock.catchUp(to: try moment(2026, 3, 6, 0, 20))
            #expect(store.timeline(today: clock.today).map(\.day) == [
                try moment(2026, 3, 5),
                try moment(2026, 3, 6),
            ])
        }
    }
}
