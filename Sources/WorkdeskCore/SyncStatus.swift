import Foundation

/// 同步此刻的一句实话。三态互斥，按要紧程度裁定：停着 > 同步中 > 已同步 ——
/// 一次只说最要紧的一件，与 `CloudSync.trouble` 同一副脾气。
public enum SyncStatus: Equatable {
    /// 账清了，两边对上了。带着上次说上话的时刻 —— 悬停时的「多久之前」说的就是它。
    case synced(lastSuccessAt: Date?)
    /// 账本上还有欠账在路上。
    case sending
    /// 持久性故障，同步停着。
    case stopped(SyncTrouble)

    public init(trouble: SyncTrouble?, sending: Bool, lastSuccessAt: Date?) {
        if let trouble { self = .stopped(trouble) }
        else if sending { self = .sending }
        else { self = .synced(lastSuccessAt: lastSuccessAt) }
    }

    /// 三态各一副云的形态：两讫的勾、在送的箭头、停着的斜线。形态说话，颜色不说 ——
    /// 唯一的例外是「在送」取主调的青，它是三态里唯一「正在动」的。
    public var symbolName: String {
        switch self {
        case .synced: "checkmark.icloud"
        case .sending: "arrow.clockwise.icloud"
        case .stopped: "icloud.slash"
        }
    }

    /// 悬停浮出的那句话。已同步说「多久之前」，其余两态说自己是什么 ——
    /// 悬停问的是「现在什么情况」，哪种情况就答哪句。
    public func hoverLabel(now: Date) -> String {
        switch self {
        case .synced(let at): at.map { Self.relativeLabel(from: $0, to: now) } ?? "尚未同步过"
        case .sending: "同步中…"
        case .stopped: "同步停着"
        }
    }

    /// 点开 popover 的详情，比悬停那句多说一层。故障沿用它自己那段解释 ——
    /// 以「本机的一切完好」收尾的那套话，这里不另起炉灶。
    public func detail(now: Date) -> String {
        switch self {
        case .synced(let at):
            let when = at.map { Self.relativeLabel(from: $0, to: now) } ?? "还没有过"
            return "上次同步：\(when)。\n改动都已送达云端，本机与云端两讫。"
        case .sending:
            return "有改动正在送往云端，送达后这朵云自己会安静下来。"
        case .stopped(let trouble):
            return trouble.explanation
        }
    }

    /// 「多久之前」的中文写法。一分钟内是「刚刚」，往上只分到分钟/小时/天 ——
    /// 这句话回答的是「心里有没有底」，不是计时，不必更细。
    /// 时钟偏差出来的负数也算「刚刚」：未来时刻没有别的诚实说法。
    public static func relativeLabel(from: Date, to now: Date) -> String {
        let s = max(0, now.timeIntervalSince(from))
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(Int(s / 60)) 分钟前" }
        if s < 86400 { return "\(Int(s / 3600)) 小时前" }
        return "\(Int(s / 86400)) 天前"
    }
}
