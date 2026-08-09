#if os(iOS)
import WorkdeskCore

/// `Category` 在这儿会输给 ObjectiveC 的 `Category`（OpaquePointer）——
/// 同模块的名字总是赢过 import 进来的。别名把名字接回来，与 Mac 端同一招。
typealias Category = WorkdeskCore.Category
#endif
