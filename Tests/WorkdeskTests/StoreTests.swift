import Foundation
import Testing

@testable import Workdesk

@MainActor
@Suite("Store")
struct StoreTests {
    /// 不传目录时，落点还是 Application Support 下原来那个位置。
    /// `defaultDirectory` 只算路径不建目录，所以这条测试不会碰使用者的真实数据。
    @Test("默认存储目录仍指向 Application Support 下的老位置")
    nonisolated func defaultDirectoryIsUnchanged() {
        let path = Store.defaultDirectory.standardizedFileURL.path
        #expect(path.hasPrefix(NSHomeDirectory()))
        #expect(path.hasSuffix("/Library/Application Support/XiaoyuWorkdesk"))
    }

    /// 收藏流往返：写进去的收藏，换一个指向同一目录的 Store 读回来还是同一批。
    @Test("收藏流在同一目录的两个 Store 之间往返")
    func favoritesRoundTrip() throws {
        try withTemporaryDirectory { dir in
            let store = Store(directory: dir)
            store.addFavorite("https://www.example.com/a")
            store.addFavorite("一段随手记下的文字")

            let reopened = Store(directory: dir)
            #expect(reopened.favorites.map(\.title) == ["example.com", "一段随手记下的文字"])
            #expect(reopened.favorites.map(\.urlString) == ["https://www.example.com/a", nil])

            // 除时间外逐字段一致；时间单独比，因为落盘用的 ISO8601 不含小数秒，
            // 读回来的 createdAt 只精确到秒，跟内存里的那个不会全等。
            #expect(withoutTimestamps(reopened.favorites) == withoutTimestamps(store.favorites))
            for (before, after) in zip(store.favorites, reopened.favorites) {
                #expect(abs(after.createdAt.timeIntervalSince(before.createdAt)) < 1)
            }
        }
    }
}

/// 把 `createdAt` 抹平，好让其余字段（id、标题、链接、备注）能整个结构体比。
private func withoutTimestamps(_ items: [FavoriteItem]) -> [FavoriteItem] {
    items.map {
        var item = $0
        item.createdAt = .distantPast
        return item
    }
}
