import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// 界面上「今天是哪天」的那一个答案。整条主线共用它 —— 轴的锚点、今天/昨天/明天的写法、
/// 回车记事落在哪一天、排期面板上那个「今天」，说的永远是同一天。
///
/// 它自己跟着日子走。这台机器上的这个窗口常常一开就是几天，跨过零点之后界面若还停在昨天，
/// 看到的就是一份对不上的安排 —— 更糟的是那时在记事栏敲回车，待办会被排到昨天去。
/// 所以不等谁来叫醒：日子一变当场跟上，不管窗口在不在前台，也不管有没有人正看着。
///
/// **只在日子变了时才动。** 时刻一直在走，但那不是它要说的事；`today` 一变就意味着「过天了」，
/// 视图于是可以拿它当那一下的信号（沙漏视图正是靠这个重新锚回今天的），而不必自己比日期。
///
/// `Store` 仍旧不问时钟：「今天」照样是交进去的参数，那些分组与记事因此照样定得住、测得了。
/// 这里只负责回答「现在是哪天」这一件事。
@Observable
@MainActor
final class TodayClock {
    private(set) var today: Date

    init(now: Date = .now) {
        today = now
    }

    /// 跟上时钟。还是同一天就一动不动 —— 依赖它的视图因此不会因为时刻走动反复重画，
    /// 「值变了」也就干干净净地只表示「过天了」。
    /// - Returns: 这一下是不是真的过天了。
    @discardableResult
    func catchUp(to now: Date = .now) -> Bool {
        guard !today.isSameDay(as: now) else { return false }
        today = now
        return true
    }

    /// 一直守着，直到界面消失。三个信号都听：
    ///
    /// - 系统的跨天通知 —— 正经的那一个，零点、改时区、改系统日期都发；
    /// - 睡醒 —— 合上盖子过一夜是最常见的跨天方式，而机器睡着时没有谁在数零点；
    /// - 窗口重新激活 —— 兜底。前两个都没送到时，至少回到它面前的那一刻是对的。
    ///
    /// 三个都只是「去问一次时钟」，问多了不要紧：日子没变时 `catchUp` 什么也不做。
    func watch() async {
        await withTaskGroup(of: Void.self) { group in
            for name in Self.watchedNames {
                group.addTask { @MainActor [weak self] in
                    for await _ in NotificationCenter.default.notifications(named: name) {
                        self?.catchUp()
                    }
                }
            }
            #if canImport(AppKit)
            group.addTask { @MainActor [weak self] in
                let center = NSWorkspace.shared.notificationCenter
                for await _ in center.notifications(named: NSWorkspace.didWakeNotification) {
                    self?.catchUp()
                }
            }
            #endif
            await group.waitForAll()
        }
    }

    private static var watchedNames: [Notification.Name] {
        var names: [Notification.Name] = [.NSCalendarDayChanged]
        #if canImport(AppKit)
        names.append(NSApplication.didBecomeActiveNotification)
        #endif
        return names
    }
}
