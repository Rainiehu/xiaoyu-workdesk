import Foundation

/// 用户自建的一组待办。数组里的位置就是它在 tab 栏上的显示顺序。
struct Category: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var color: CategoryColor
}

/// 分类可用的颜色。只存色名不存色值 —— 具体色值由视图层决定，
/// 于是配色可以整体调整而不动已经落盘的数据。
enum CategoryColor: String, Codable, CaseIterable, Hashable {
    case teal, mint, cyan, blue, indigo, purple, pink, orange

    /// 与整体青色主调协调的预设色板，新建分类按这个顺序取色。
    static let palette = allCases
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    /// 所属分类。每条待办属于且只属于一个分类。
    var categoryID: Category.ID
    var done: Bool = false
    /// 创建时刻。带着时刻落盘 —— 同一天记下的几条待办要靠它分出先后。
    var createdAt: Date = .now
    /// 完成时刻。同样带着时刻落盘，显示时才截到天。没完成就没有完成日。
    var completedAt: Date?
    /// 安排去做的那一天。可空 —— 「总得做但不急」的事可以永远不排期。
    /// 与创建日、完成日各自独立存储，谁都不会覆盖谁。
    var plannedOn: Date?
}

struct FavoriteItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var urlString: String?
    var note: String?
    var createdAt: Date = .now

    var url: URL? {
        guard let s = urlString else { return nil }
        return URL(string: s)
    }

    var domain: String? {
        url?.host()?.replacingOccurrences(of: "www.", with: "")
    }
}

extension Date {
    var dayStart: Date { Calendar.current.startOfDay(for: self) }

    /// 是不是同一天。底下存的是全时刻，所以「同一天」永远要问 `Calendar`，不能拿 `==` 比时刻。
    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    /// 界面上写这个日子的写法。截到天是显示层的事 —— 这里是唯一做这件截断的地方，
    /// 底下的时刻原样留在数据里。收藏流的时间戳不走这条路，它显示带时刻。
    var dayLabel: String { dayLabel(relativeTo: .now) }

    /// - Parameter today: 「今天」是哪天。取出来当参数，好让这套写法可测且不随时钟漂移。
    func dayLabel(relativeTo today: Date) -> String {
        if isSameDay(as: today) { return "今天" }
        let calendar = Calendar.current
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), isSameDay(as: tomorrow) {
            return "明天"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), isSameDay(as: yesterday) {
            return "昨天"
        }
        let sameYear = calendar.component(.year, from: self) == calendar.component(.year, from: today)
        return (sameYear ? Self.dayFormatter : Self.dayWithYearFormatter).string(from: self)
    }

    private static let dayFormatter = dateFormatter("M月d日")
    private static let dayWithYearFormatter = dateFormatter("yyyy年M月d日")

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = format
        return f
    }
}

extension Int {
    /// 12_345 -> "12.3k", 1_234_567 -> "1.23M"
    var tokenString: String {
        if self >= 1_000_000 { return String(format: "%.2fM", Double(self) / 1_000_000) }
        if self >= 1_000 { return String(format: "%.1fk", Double(self) / 1_000) }
        return "\(self)"
    }
}
