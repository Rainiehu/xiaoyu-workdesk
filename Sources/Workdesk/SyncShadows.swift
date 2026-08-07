import Foundation

/// 一个分类和它在 tab 栏上的位置。本地不给位置立字段（`categories` 数组的顺序就是顺序），
/// 但影子与殉葬品说的是云端那一侧的样子 —— 位置在那儿是每条记录自己的字段，得一起留着。
struct PlacedCategory: Codable, Equatable {
    var category: Category
    var position: Int
}

/// 同步的记性：影子副本与分类的殉葬品。与账本一样随数据落盘 ——
/// 账本记「还欠云端什么」，这儿记「上次跟云端对齐时它长什么样」。
///
/// 影子是字段级合并的那个「上一次」：冲突时拿影子、本地、服务端三方对比，
/// 才分得出哪边改过哪个字段。没有影子就分不出，只好退回整条后写胜。
/// 影子只在两边说的是同一句话的时刻对齐 —— 保存送达云端时、云端的版本落进本地时。
struct SyncShadows: Codable, Equatable {
    /// 每条待办上次与云端对齐时的样子，按记录名存。
    private(set) var todos: [String: TodoItem] = [:]
    /// 每个分类上次与云端对齐时的样子（带位置），按记录名存。
    private(set) var categories: [String: PlacedCategory] = [:]
    /// 殉葬品：删掉的分类带走的名字、颜色与位置。删分类与往里记待办打架时待办胜，
    /// 分类要带着原名原色复活 —— 复活的料就从这儿取。墓碑撤了它也不撤：
    /// 删除送达云端之后，归属它的待办仍可能从另一台设备晚一步到来。
    private(set) var buriedCategories: [String: PlacedCategory] = [:]

    func todo(named recordName: String) -> TodoItem? {
        todos[recordName]
    }

    func category(named recordName: String) -> PlacedCategory? {
        categories[recordName]
    }

    mutating func align(todo: TodoItem) {
        todos[todo.recordName] = todo
    }

    /// 分类对齐还顺手撤掉同名的殉葬品 —— 云端有它、本地有它，谈不上下过葬。
    mutating func align(category placed: PlacedCategory) {
        categories[placed.category.recordName] = placed
        buriedCategories[placed.category.recordName] = nil
    }

    /// 这条记录不在了（本地删的送达了云端，或云端删的落回了本地）：影子跟着撤。
    /// 殉葬品不动 —— 它就是为记录不在了之后的日子准备的。
    mutating func drop(recordName: String) {
        todos[recordName] = nil
        categories[recordName] = nil
    }

    /// 分类下葬：留足复活要用的料。影子一并撤 —— 它说的是一条还活着的记录。
    mutating func bury(_ placed: PlacedCategory) {
        buriedCategories[placed.category.recordName] = placed
        drop(recordName: placed.category.recordName)
    }

    /// 起坟：取回殉葬品，坟就平了 —— 复活只发生一次，之后它就是个普通分类。
    mutating func exhumeCategory(named recordName: String) -> PlacedCategory? {
        guard let buried = buriedCategories[recordName] else { return nil }
        buriedCategories[recordName] = nil
        return buried
    }

    /// 云端整个换了脸（zone 被删、换了账号）：影子说的是旧库的样子，全部作废。
    /// 殉葬品照留 —— 它记的是本地删过什么，与对面是哪个库无关。
    mutating func forgetAlignments() {
        todos = [:]
        categories = [:]
    }
}
