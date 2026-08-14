#if os(iOS)
import SwiftUI
import WorkdeskCore

/// 屏底常驻的记事入口，两屏同一副（见 CONTEXT-iOS.md：写字的地方该挨着手）。
/// 只管长相和「回车了」：空白输入交给 `Store` 挡掉，清空与留住焦点由使用方做。
struct InputBar<Trailing: View>: View {
    /// 加号的颜色。沙漏屏用整体主调的青（那一屏不属于任何分类，「记到哪儿」由
    /// 右边的分类选择器说）；分类屏用那个分类的颜色。与 Mac 同一条规矩。
    let tint: Color
    let prompt: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let submit: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(tint.opacity(0.8))
                .imageScale(.large)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused(focused)
                .onSubmit(submit)
                .submitLabel(.done)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        // 输入栏也是一块浮在纸上的卡片 —— 与行、分组同一副做法。
        .paperCard(cornerRadius: 21)
        .padding(.horizontal, ScreenLayout.screenEdge)
        .padding(.vertical, 8)
        .background { PaperTheme.paper.ignoresSafeArea() }
    }
}

/// 记到哪个分类。列的是活人名单（`livingCategories`）—— 删除态的正从一切界面消失，
/// 不该在这儿露面。与 Mac 的 `RecordingCategoryPicker` 同一副：光板的名字加一个小箭头，不抢眼。
struct RecordingCategoryPicker: View {
    @Environment(Store.self) private var store
    let current: Category

    var body: some View {
        Menu {
            ForEach(store.livingCategories) { category in
                Button {
                    store.chooseRecordingCategory(category.id)
                } label: {
                    if category.id == current.id {
                        Label(category.name, systemImage: "checkmark")
                    } else {
                        Text(category.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current.name)
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
    }
}
#endif
