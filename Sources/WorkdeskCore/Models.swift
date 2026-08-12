import Foundation

/// 用户自建的一组待办。数组里的位置就是它在 tab 栏上的显示顺序。
public struct Category: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var name: String
    public var color: CategoryColor
    /// 删除时刻。删除是打记号，不是抹掉：有值就是删除态，从一切界面消失，记录永远留着。
    /// 见 ADR-0007。
    public var deletedAt: Date?

    public init(id: UUID = UUID(), name: String, color: CategoryColor, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }
}

/// 分类可用的颜色。只存色名不存色值 —— 具体色值由视图层决定，
/// 于是配色可以整体调整而不动已经落盘的数据。
///
/// 这些色名绕色相环走一圈，任意两个都看得出差别 —— tab 栏上一排彩色的字，
/// 「像是同一个颜色」和「就是同一个颜色」一样让人认错分类。末尾的 `slate` 是唯一的中性色。
public enum CategoryColor: String, Codable, CaseIterable, Hashable {
    case red, orange, amber, lime, green, mint, teal, cyan, blue, indigo, purple, fuchsia, pink, slate

    /// 新建分类按这个顺序取色。它不是色相环的顺序，是跳着走的 ——
    /// 连着建的几个分类因此拿到的是隔得最远的几种颜色，而不是相邻的几档绿。
    /// 首位仍是青色：一个分类的人，看到的是整体主调。
    ///
    /// 这份名单是手写的，每一种颜色都要在里头出现一次 —— 加了新色名记得也加到这儿来。
    public static let palette: [CategoryColor] = [
        .teal, .orange, .indigo, .pink, .green, .amber, .cyan, .purple,
        .lime, .blue, .red, .mint, .fuchsia, .slate,
    ]

    /// 这个颜色叫什么。选色盘上的色块看得见颜色，不写字 —— 名字是给悬停提示和读屏用的。
    public var label: String {
        switch self {
        case .red: "红"
        case .orange: "橙"
        case .amber: "琥珀"
        case .lime: "黄绿"
        case .green: "绿"
        case .mint: "薄荷"
        case .teal: "青"
        case .cyan: "天蓝"
        case .blue: "蓝"
        case .indigo: "靛蓝"
        case .purple: "紫"
        case .fuchsia: "品红"
        case .pink: "粉"
        case .slate: "石墨"
        }
    }
}

public struct TodoItem: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var text: String
    /// 所属分类。每条待办属于且只属于一个分类。
    public var categoryID: Category.ID
    public var done: Bool = false
    /// 创建时刻。带着时刻落盘 —— 同一天记下的几条待办要靠它分出先后。
    public var createdAt: Date = .now
    /// 完成时刻。同样带着时刻落盘，显示时才截到天。没完成就没有完成日。
    public var completedAt: Date?
    /// 安排去做的那一天。可空 —— 「总得做但不急」的事可以永远不排期。
    /// 与创建日、完成日各自独立存储，谁都不会覆盖谁。
    public var plannedOn: Date?
    /// 在所属分类里的位置，数越小越靠上 —— 分类视图左列照着它铺，见 ADR-0002。
    /// 只在同一个分类里可比，跨分类比大小没有意义。
    ///
    /// 可空只是为了读得进还没有这个字段的旧数据：`Store` 载入时会照老规矩给缺的补上，
    /// 补完之后每条都有。别把「没有位置」当成一种状态来用。
    public var order: Int?
    /// 删除时刻。删除是打记号，不是抹掉：有值就是删除态，从一切界面消失，记录永远留着。
    /// 其余字段一概不动 —— 撤销摘掉记号，它就原样回到原来的位置。见 ADR-0007。
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(), text: String, categoryID: Category.ID, done: Bool = false,
        createdAt: Date = .now, completedAt: Date? = nil, plannedOn: Date? = nil, order: Int? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.categoryID = categoryID
        self.done = done
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.plannedOn = plannedOn
        self.order = order
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }

    /// 过期：未完成，且计划日在「今天」之前。见 ADR-0004（修订了 ADR-0001 的「不设过期」）。
    ///
    /// 是个安静的事实，不是催办信号 —— 界面上只有勾圈描成琥珀这一处弱记号。
    /// 当天不算（今天还没过完）；已完成的不算，哪怕完成得再晚（打勾那一下顺手把记号抹掉）；
    /// 未排期的没有计划日，谈不上过没过。派生判断，不落盘。
    ///
    /// - Parameter today: 「今天」是哪天。取出来当参数，与 `dayLabel(relativeTo:)` 同一条理由：
    ///   可测，且整条主线共用 `TodayClock` 的那一个值。
    public func isOverdue(today: Date) -> Bool {
        guard !done, let plannedOn else { return false }
        // 比的是「哪一天」不是「哪一刻」：两头都先落到 `dayStart` 再比 ——
        // 计划日带着零点、今天可能带着时刻，直接比时刻会把当天误判成过期。
        return plannedOn.dayStart < today.dayStart
    }
}

/// 一次删除分类请求的下场。删不掉有两种，说清楚是哪一种 ——
/// 视图层照着它决定要不要提示，而那句提示要说的数字也一并带回来，不必让它自己去数一遍。
public enum CategoryDeletion: Equatable {
    case deleted
    /// 里头还有这么多条待办（无论完成与否），所以没删，一条也没动。
    case refused(todoCount: Int)
    /// 根本没这个分类。什么也没发生，也没什么好提示的。
    case noSuchCategory
}

/// 分类视图里左右两列的内容：左边待完成，右边已完成。
/// 排序在 `Store` 里定死，这里只是分好的一份结果 —— 视图层照着铺就是，不自行排序。
public struct CategoryColumns: Equatable {
    /// 左列。
    public var unfinished: [TodoItem]
    /// 右列。
    public var finished: [TodoItem]

    public init(unfinished: [TodoItem], finished: [TodoItem]) {
        self.unfinished = unfinished
        self.finished = finished
    }

    /// 这个分类一件事都没有。视图层照着它决定不分列 —— 判断放在这儿，
    /// 免得视图自己去聚合两个数组。
    public var isEmpty: Bool { unfinished.isEmpty && finished.isEmpty }
}

/// 沙漏视图右列里的一组：一个分类，和它名下还没排期的未完成待办。
/// 只是 `Store` 分好的一份结果，不带任何行为 —— 聚合在 `Store` 里做，视图层照着铺就是。
public struct UnscheduledGroup: Identifiable, Equatable {
    public var category: Category
    public var todos: [TodoItem]

    public init(category: Category, todos: [TodoItem]) {
        self.category = category
        self.todos = todos
    }

    public var id: Category.ID { category.id }
}

/// 沙漏视图里的一天：一个计划日，和被安排在这天的待办。
/// 只是 `Store` 分好的一份结果，不带任何行为 —— 聚合在 `Store` 里做，视图层照着铺就是。
public struct TimelineDay: Identifiable, Equatable {
    /// 这一天的零点。按天分组的键，也是它的身份。
    public var day: Date
    public var todos: [TodoItem]

    public init(day: Date, todos: [TodoItem]) {
        self.day = day
        self.todos = todos
    }

    public var id: Date { day }
}

/// 记着用户上一次怎么选的那些小事。它们不是数据，是习惯 ——
/// 单独存一份，与待办、分类各不相干。
struct Preferences: Codable, Equatable {
    /// 沙漏视图记事时上次选中的分类。还没选过就是 `nil`。
    var recordingCategoryID: Category.ID?
    /// 沙漏轴那只眼闭着（不展示已完成）。老文件没有这个键，读出来是 `nil`，按睁眼算。
    var hidesCompletedOnTimeline: Bool?
}

public struct FavoriteItem: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var title: String
    public var urlString: String?
    public var note: String?
    public var createdAt: Date = .now
    /// 删除时刻。删除是打记号，不是抹掉 —— 与待办、分类同一套，见 ADR-0007。
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(), title: String, urlString: String? = nil,
        note: String? = nil, createdAt: Date = .now, deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.note = note
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }

    public var url: URL? {
        guard let s = urlString else { return nil }
        return URL(string: s)
    }

    public var domain: String? {
        url?.host()?.replacingOccurrences(of: "www.", with: "")
    }
}

extension Date {
    public var dayStart: Date { Calendar.current.startOfDay(for: self) }

    /// 是不是同一天。底下存的是全时刻，所以「同一天」永远要问 `Calendar`，不能拿 `==` 比时刻。
    public func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    /// 界面上写这个日子的写法。截到天是显示层的事 —— 这里是唯一做这件截断的地方，
    /// 底下的时刻原样留在数据里。收藏流的时间戳不走这条路，它显示带时刻。
    public var dayLabel: String { dayLabel(relativeTo: .now) }

    /// - Parameter today: 「今天」是哪天。取出来当参数，好让这套写法可测且不随时钟漂移。
    public func dayLabel(relativeTo today: Date) -> String {
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
    public var tokenString: String {
        if self >= 1_000_000 { return String(format: "%.2fM", Double(self) / 1_000_000) }
        if self >= 1_000 { return String(format: "%.1fk", Double(self) / 1_000) }
        return "\(self)"
    }
}
