import SwiftUI

/// 记事的那一条：一个加号、一个输入框，右边还能挂点别的（沙漏视图挂的是记到哪个分类）。
/// 分类视图与沙漏视图共用它 —— 记事在两处看着就是同一件事，样子也不会各自漂移。
///
/// 它只管长相和「回车了」这件事：空白输入交给 `Store` 挡掉，清空与留住焦点由使用方做 ——
/// 记完之后该发生什么，两处并不一样。
struct TodoInputField<Trailing: View>: View {
    /// 着色。分类视图用那个分类的颜色，沙漏视图用当前记事分类的颜色 ——
    /// 「这条会记到哪儿」于是不用读字也看得出来。
    let tint: Color
    let prompt: String
    @Binding var text: String
    /// 焦点由使用方拿着：记下一条之后要不要把焦点留住，是使用方的事。
    var focused: FocusState<Bool>.Binding
    let submit: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    /// 这一条的高度。写成常量而不是由内容撑开：分类视图的右列要照着它在顶上留出一段，
    /// 好让两列的第一行齐平 —— 两列因此看着是一块板，不是两块各自开始的东西。
    static var height: CGFloat { 42 }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(tint.opacity(0.8))
                .imageScale(.large)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused(focused)
                .onSubmit(submit)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))
    }
}
