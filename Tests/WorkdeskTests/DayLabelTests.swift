import Foundation
import Testing

@testable import Workdesk

@Suite("日期显示")
struct DayLabelTests {
    private func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) throws -> Date {
        try #require(Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        ))
    }

    @Test("同一天里的两个时刻算同一天，跨过零点就不是")
    func sameDayIgnoresTheTimeOfDay() throws {
        let morning = try moment(2026, 3, 5, 9, 0)
        let lateNight = try moment(2026, 3, 5, 23, 30)
        let justAfterMidnight = try moment(2026, 3, 6, 0, 10)

        #expect(morning.isSameDay(as: lateNight))
        #expect(!lateNight.isSameDay(as: justAfterMidnight))
    }

    @Test("昨天今天明天说人话，再远写月日，跨年才带上年份")
    func dayLabelReadsAsADay() throws {
        let today = try moment(2026, 3, 5, 14, 30)

        #expect(try moment(2026, 3, 5, 8, 0).dayLabel(relativeTo: today) == "今天")
        #expect(try moment(2026, 3, 6, 22, 0).dayLabel(relativeTo: today) == "明天")
        #expect(try moment(2026, 3, 4).dayLabel(relativeTo: today) == "昨天")
        #expect(try moment(2026, 3, 20).dayLabel(relativeTo: today) == "3月20日")
        #expect(try moment(2026, 1, 8).dayLabel(relativeTo: today) == "1月8日")
        #expect(try moment(2025, 12, 31).dayLabel(relativeTo: today) == "2025年12月31日")
        #expect(try moment(2027, 2, 1).dayLabel(relativeTo: today) == "2027年2月1日")
    }

    @Test("界面上的日期一律只到天，不出现时刻")
    func dayLabelNeverShowsATime() throws {
        let today = try moment(2026, 3, 5)
        let moments = [
            try moment(2026, 3, 5, 23, 59),
            try moment(2026, 3, 6, 16, 45),
            try moment(2026, 4, 1, 8, 5),
            try moment(2024, 1, 2, 12, 0),
        ]
        for m in moments {
            let label = m.dayLabel(relativeTo: today)
            #expect(!label.contains(":"))
            #expect(!label.contains("时"))
            #expect(!label.contains("分"))
        }
    }
}
