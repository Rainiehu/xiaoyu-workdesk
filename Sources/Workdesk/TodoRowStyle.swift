import SwiftUI

/// 三处待办行共用的那几样东西：度量、打勾的圈、悬停浮出的删除、拖起来时手上跟着的那一小块。
///
/// 分类视图、沙漏视图的轴、未排期列，三处的行是同一副结构：
///
///     圈 → 正文 → Spacer → 日期/排期入口 → 删除 → 分类 tag
///
/// 差别只在「哪几格是空的」：分类视图不画 tag（在哪个分类里是不言自明的），未排期列的 tag
/// 在组头上，轴上的位置本身就是计划日、于是没有排期入口。顺序与度量都定在这儿，三处照着来 ——
/// 先前没有这么一处共同的定义，三行才各自漂移成了三副模样。

/// 一行待办的度量。三处共用，改一处三处一起动。
enum TodoRowLayout {
    /// 行内元素之间的距离。
    static let spacing: CGFloat = 10
    static let horizontalInset: CGFloat = 10
    /// 竖直内缩。比横向留得多一点 —— 行里最高的是那个 16pt 的圈，它得有呼吸。
    static let verticalInset: CGFloat = 8
    static let cornerRadius: CGFloat = 8
}

/// 一条待办的完成状态：空心圈是还没做，实心勾圈是做完了，点一下就翻面。
///
/// 已完成的圈填成这条待办所属分类的颜色 —— 打勾于是把这一行「点亮」成它的分类色。
/// 未完成的一律是灰圈：那时颜色还没什么好说的，而一行上只该有一处彩色抢眼。
///
/// 画哪个状态由调用方给，不自己去问 `todo.done` —— 未排期列里打完勾的那条要先亮一下再走，
/// 那一拍里圈画的是「已完成」，而待办本身还没变。
struct TodoToggle: View {
    let done: Bool
    /// 打勾之后填的颜色，就是这条待办所属分类的颜色。
    let tint: Color
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(done ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(done ? "取消完成" : "标记完成")
    }
}

/// 悬停时浮出的删除。三处摆在同一个位置上：行尾那个常驻元素的左边 ——
/// 轴上它靠着分类 tag，另外两处它自己就是最右。
///
/// 删除没有撤销、没有回收站，所以它只在悬停时露面，静止时一点痕迹也不留。
struct TodoDeleteButton: View {
    let delete: () -> Void

    var body: some View {
        Button(action: delete) {
            Image(systemName: "trash")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("删除")
    }
}

/// 拖起来时手上跟着的那一小块：就是这条待办的正文。
/// 整行连着悬停底色一起拖会盖住下面的落点，只带一句字轻便得多。
struct TodoDragPreview: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: TodoRowLayout.cornerRadius).fill(tint.opacity(0.15))
            )
    }
}

extension View {
    /// 一行待办的内缩与悬停底色。三处都要那块底色 —— 行上摆着打勾和删除、整行还抓得动，
    /// 手落在哪一行必须当场看得见。
    func todoRowChrome(hovering: Bool) -> some View {
        padding(.horizontal, TodoRowLayout.horizontalInset)
            .padding(.vertical, TodoRowLayout.verticalInset)
            .background(
                RoundedRectangle(cornerRadius: TodoRowLayout.cornerRadius)
                    .fill(hovering ? AnyShapeStyle(.quaternary.opacity(0.35)) : AnyShapeStyle(.clear))
            )
    }
}
