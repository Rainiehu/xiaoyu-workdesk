#if os(iOS)
import SwiftUI
import WorkdeskCore

/// 三处待办行共用的那几样东西，iOS 版。结构与 Mac 完全同一副：
///
///     圈 → 正文 → Spacer → 日期/排期入口 → 分类 tag
///
/// 差别只在「哪几格是空的」，与 Mac 同一条规矩；悬停没有了，替换成触屏的总规矩
/// （见 CONTEXT-iOS.md）：左滑＝删除，排期入口常驻，单击正文＝就地改写，长按菜单 ≙ 右键菜单。
enum TodoRowLayout {
    static let spacing: CGFloat = 10
    static let horizontalInset: CGFloat = 10
    static let verticalInset: CGFloat = 8
    static let cornerRadius: CGFloat = 8
}

/// 一条待办的完成状态圈。空心圈是还没做，实心勾圈是做完了，点一下就翻面。
/// 过期只换描边成琥珀 —— 安静的记号，不是警报。画哪个状态由调用方给，
/// 与 Mac 同一条理由：未排期面板里打完勾要先亮一拍。
struct TodoToggle: View {
    let done: Bool
    var overdue: Bool = false
    let tint: Color
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(circleStyle)
                // 圈本身 18pt，手指要的可点范围比这大 —— 内缩摊进按钮里。
                .padding(6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var circleStyle: AnyShapeStyle {
        if done { return AnyShapeStyle(tint) }
        return overdue ? AnyShapeStyle(Color.overdueAmber) : AnyShapeStyle(.tertiary)
    }
}

/// 待办所属分类的 tag，与 Mac 的 `CategoryTag` 同两副样子：
/// 带胶囊的用在未排期面板的组头上；光板的用在轴上每一行 —— 一屏几十行，
/// 每行挂一个彩色胶囊就成了噪点，而那儿该抢眼的是「今天」。
struct CategoryTag: View {
    let category: Category
    var chip: Bool = true

    var body: some View {
        if chip {
            Text(category.name)
                .font(.caption)
                .foregroundStyle(category.color.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(category.color.tint.chipFill))
                .overlay(Capsule().stroke(category.color.tint.chipStroke, lineWidth: 1))
        } else {
            Text(category.name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// 一行待办的内缩。三处都从这儿走，改一处三处一起动。
    func todoRowChrome() -> some View {
        padding(.horizontal, TodoRowLayout.horizontalInset)
            .padding(.vertical, TodoRowLayout.verticalInset)
    }
}
#endif
