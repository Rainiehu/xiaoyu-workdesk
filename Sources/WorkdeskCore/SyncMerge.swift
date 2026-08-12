import Foundation

/// 冲突时的字段级合并：影子（上次与云端对齐的样子）、本地、服务端三方对比，
/// 找出本地改过的方面，重放到服务器版上 —— A 实例改写正文、B 实例同时改期，两边都保住。
/// 纯函数：谁算「后写」由调用方比好时刻交进来，这儿只管按规矩合。
///
/// 合并按「方面」走，不按裸字段：打勾一下动的是 `done` 和 `completedAt` 两个字段，
/// 拆开各归各家会合出「打了勾却没有完成时刻」这种谁也没写过的状态。
/// 本地的每种操作恰好各动一个方面 —— 「一次只动一样」在并发世界里的直接推论，
/// 就是两台设备各动一样时两样都保得住。
enum SyncMerge {
    /// 合并一条待办。方面：正文、完成（打勾 + 完成时刻）、计划日、
    /// 挂靠与位置（分类 + 父 + 第几位 —— 「挂在哪儿」是一件事，位置也只在兄弟之间才有意义）、
    /// 创建时刻、删除记号。
    /// 删除不是特例（「删除胜」已随 ADR-0007 退役）：这台删、那台改字，两边都保住 ——
    /// 合出来是一条带着新改的字、躺在删除态里的记录；两台都动记号，后写的算。
    static func todo(shadow: TodoItem?, local: TodoItem, remote: TodoItem, localIsLater: Bool) -> TodoItem {
        var merged = remote
        replay(\.text, shadow: shadow, local: local, localIsLater: localIsLater, into: &merged)
        replay(\.completion, shadow: shadow, local: local, localIsLater: localIsLater, into: &merged)
        replay(\.plannedOn, shadow: shadow, local: local, localIsLater: localIsLater, into: &merged)
        replay(\.placement, shadow: shadow, local: local, localIsLater: localIsLater, into: &merged)
        replay(\.createdAt, shadow: shadow, local: local, localIsLater: localIsLater, into: &merged)
        replay(\.deletedAt, shadow: shadow, local: local, localIsLater: localIsLater, into: &merged)
        return merged
    }

    /// 合并一个分类（带位置）。方面：名字、颜色、位置、删除记号 ——
    /// 改名、换色、挪动、删除各是一次操作。
    static func category(
        shadow: PlacedCategory?, local: PlacedCategory, remote: PlacedCategory, localIsLater: Bool
    ) -> PlacedCategory {
        var merged = remote
        replay(\.category.name, shadow: shadow, local: local, localIsLater: localIsLater, into: &merged)
        replay(\.category.color, shadow: shadow, local: local, localIsLater: localIsLater, into: &merged)
        replay(\.position, shadow: shadow, local: local, localIsLater: localIsLater, into: &merged)
        replay(\.category.deletedAt, shadow: shadow, local: local, localIsLater: localIsLater, into: &merged)
        return merged
    }

    /// 一个方面的取舍。`merged` 以服务器版打底，所以进来时它带的就是服务端的值：
    /// 只有本地改过、服务端没改的，重放本地的；两边都改的才轮到后写胜。
    /// 没有影子（这条记录从没与云端对齐过）就分不出谁改过 —— 凡不一致都当两边都改过，
    /// 整体退化成 #35 的整条后写胜，不多丢也不多留。
    private static func replay<T, V: Equatable>(
        _ aspect: WritableKeyPath<T, V>, shadow: T?, local: T, localIsLater: Bool, into merged: inout T
    ) {
        let mine = local[keyPath: aspect]
        guard mine != merged[keyPath: aspect] else { return }
        guard let shadow else {
            if localIsLater { merged[keyPath: aspect] = mine }
            return
        }
        let iChanged = mine != shadow[keyPath: aspect]
        let theyChanged = merged[keyPath: aspect] != shadow[keyPath: aspect]
        if iChanged && (!theyChanged || localIsLater) {
            merged[keyPath: aspect] = mine
        }
    }
}

/// 打勾那一下动的两个字段，捆成一个方面 —— 「没有完成日」和「没完成」永远是同一件事，
/// 合并也不许把它们拆散。
private struct Completion: Equatable {
    var done: Bool
    var completedAt: Date?
}

/// 挂靠与位置捆成一个方面：「挂在哪个分类、哪个父下面的第几位」是一件事 ——
/// 升降级、换爹、换分类、换位置，本地都是这一个方面的一次改动，拆开会合出
/// 「挂着 A 的父却在 B 的分类里」这种谁也没写过的状态。
private struct Placement: Equatable {
    var categoryID: Category.ID
    var parentID: TodoItem.ID?
    var order: Int?
}

private extension TodoItem {
    var completion: Completion {
        get { Completion(done: done, completedAt: completedAt) }
        set {
            done = newValue.done
            completedAt = newValue.completedAt
        }
    }

    var placement: Placement {
        get { Placement(categoryID: categoryID, parentID: parentID, order: order) }
        set {
            categoryID = newValue.categoryID
            parentID = newValue.parentID
            order = newValue.order
        }
    }
}
