import Foundation
import Testing
@testable import WorkdeskCore

@Suite("同步记号的三态")
struct SyncStatusTests {
    let someday = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("停着压过同步中：一次只说最要紧的一件")
    func stoppedBeatsSending() {
        let status = SyncStatus(trouble: .noAccount, sending: true, lastSuccessAt: someday)
        #expect(status == .stopped(.noAccount))
    }

    @Test("有欠账就是同步中，哪怕刚成功过")
    func sendingBeatsSynced() {
        let status = SyncStatus(trouble: nil, sending: true, lastSuccessAt: someday)
        #expect(status == .sending)
    }

    @Test("无事时是已同步，带着上次的时刻")
    func syncedCarriesLastSuccess() {
        let status = SyncStatus(trouble: nil, sending: false, lastSuccessAt: someday)
        #expect(status == .synced(lastSuccessAt: someday))
    }

    @Test("悬停那句话：三态各说各的")
    func hoverLabels() {
        let now = someday
        #expect(SyncStatus.sending.hoverLabel(now: now) == "同步中…")
        #expect(SyncStatus.stopped(.quotaExceeded).hoverLabel(now: now) == "同步停着")
        #expect(SyncStatus.synced(lastSuccessAt: now.addingTimeInterval(-120)).hoverLabel(now: now) == "2 分钟前")
        #expect(SyncStatus.synced(lastSuccessAt: nil).hoverLabel(now: now) == "尚未同步过")
    }

    @Test("停着的详情沿用故障自己那段解释")
    func stoppedDetailIsTroubleExplanation() {
        let status = SyncStatus.stopped(.stale(days: 3))
        #expect(status.detail(now: someday) == SyncTrouble.stale(days: 3).explanation)
    }
}

@Suite("「多久之前」的写法")
struct RelativeLabelTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func label(_ secondsAgo: TimeInterval) -> String {
        SyncStatus.relativeLabel(from: now.addingTimeInterval(-secondsAgo), to: now)
    }

    @Test("一分钟内都是刚刚")
    func justNow() {
        #expect(label(0) == "刚刚")
        #expect(label(59) == "刚刚")
    }

    @Test("分钟档：60 秒起，向下取整")
    func minutes() {
        #expect(label(60) == "1 分钟前")
        #expect(label(119) == "1 分钟前")
        #expect(label(3599) == "59 分钟前")
    }

    @Test("小时档：整时起步，23 小时封顶")
    func hours() {
        #expect(label(3600) == "1 小时前")
        #expect(label(86399) == "23 小时前")
    }

    @Test("天档：一天起不再细分")
    func days() {
        #expect(label(86400) == "1 天前")
        #expect(label(86400 * 9) == "9 天前")
    }

    @Test("时钟偏差出来的未来时刻也算刚刚")
    func futureIsJustNow() {
        #expect(SyncStatus.relativeLabel(from: now.addingTimeInterval(300), to: now) == "刚刚")
    }
}
