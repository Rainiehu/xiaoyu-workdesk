import Foundation

/// 建一个空的临时目录跑 `body`，跑完删掉。测试因此不碰使用者真实的 Application Support。
func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("WorkdeskTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}
