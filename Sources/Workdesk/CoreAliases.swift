import WorkdeskCore

/// 模型搬进 WorkdeskCore 之后，`Category` 这个名字在这儿会输给 ObjectiveC 的
/// `Category`（OpaquePointer）—— 同模块的名字总是赢过 import 进来的。
/// 这个别名把名字接回来，UI 代码照旧写 `Category`，不必到处带模块前缀。
typealias Category = WorkdeskCore.Category
