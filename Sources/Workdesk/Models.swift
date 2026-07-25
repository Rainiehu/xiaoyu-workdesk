import Foundation

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var done: Bool = false
    var createdAt: Date = .now
    var completedAt: Date?
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
    var isToday: Bool { Calendar.current.isDateInToday(self) }

    var friendlyDay: String {
        if Calendar.current.isDateInToday(self) { return "今天" }
        if Calendar.current.isDateInYesterday(self) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: self)
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
