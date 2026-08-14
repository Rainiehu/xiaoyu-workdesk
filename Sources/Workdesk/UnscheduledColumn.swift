import SwiftUI
import WorkdeskCore

/// 沙漏视图右边那一列：所有还没排期的未完成待办，按分类分组，分组的顺序就是 tab 栏的顺序。
/// 分组由 `Store.unscheduled` 给出，这里不自己聚合、一行排序也不做。
///
/// 「总得做但不急」的事都在这儿。它们不在轴上（轴按计划日铺），却也不该因此看不见 ——
/// 这一列就是它们的去处：一眼扫得完，随时挑一件排上。
///
/// 它自己滚自己的：轴滚到哪一天，这一列都停在原处 —— 「还有什么没安排」不随时间轴漂移。
/// 排上计划日的一刻它就离开这一列，出现在轴上，于是这一列永远只是「还没安排的事」。
/// 打勾也一样让它离开，只是没有看得见的去处（做完的事在分类视图右列），所以那一下走得慢一点。
struct UnscheduledColumn: View {
    @Environment(Store.self) private var store

    /// 这一列的宽度。定死一个值而不是按比例分 —— 轴于是随窗口一起长，
    /// 「哪边是主角」不随窗口宽度动摇。与分类视图右列同一个数：两处的右列看着是同一块东西。
    static let width: CGFloat = 264

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            groups
        }
        .frame(width: Self.width, alignment: .leading)
    }

    /// 一句话说明这一列是什么。轻到几乎不占分量 —— 它不是标题栏，是个标签。
    private var header: some View {
        Text("未排期")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .tracking(1)
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 10)
    }

    @ViewBuilder
    private var groups: some View {
        let groups = store.unscheduled
        if groups.isEmpty {
            Text("每件事都排上了")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(groups) { group in
                        UnscheduledCategoryGroup(group: group)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
    }
}

/// 右列里的一组：一个分类的彩色 tag 当组头，下面是它名下还没排期的待办。
/// 组头是这一列里唯一着色的 tag：一组的颜色就是这一组的标题，一屏只有几个。
/// 轴上每行那副同形状但不着色 —— 见 `CategoryTag`。
private struct UnscheduledCategoryGroup: View {
    @Environment(Store.self) private var store
    let group: UnscheduledGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 组头不额外内缩：它的胶囊与下面每一行悬停时那块底色因此左边缘对齐，
            // 一组读起来是一块，而不是标题歪在行的里侧。
            CategoryTag(category: group.category)
                .padding(.bottom, 2)
            ForEach(group.todos) { todo in
                // 删除态的行是原位占位：撤销窗口开着的那几秒它还站在这儿，见 ADR-0007。
                if todo.isDeleted {
                    DeletedTodoRow(todo: todo)
                        .font(.callout)
                } else {
                    UnscheduledRow(todo: todo, tint: group.category.color.tint)
                    // 子树常开，就摊在行底下 —— 这一列也不例外。窄列的树跟着用 callout。
                    SubTodoTree(parentID: todo.id, tint: group.category.color.tint)
                        .font(.callout)
                }
            }
        }
    }
}

/// 右列里的一行：打勾的圈、正文，悬停时右边浮出排期的入口和删除。
/// 元素的顺序与另外两处的行一样，排期入口也是同一个日历图标 ——
/// 只是这儿的待办都没排期，行上自然没有日期标签。
///
/// 单击整行就地改写，右键还有「改写」与「移到分类」—— 三处的行本事一致，见 ADR-0003。
/// 这一列只有 264pt 宽，改写时字挤了些，但「点一行就能改」不该因为它站在哪一列而失效。
///
/// 整行可以拖到轴上某一天去排期，也可以拖到 tab 栏上换分类，
/// 与轴上条目那两个动作是同一个手势、同一套落点指示。
private struct UnscheduledRow: View {
    @Environment(Store.self) private var store
    let todo: TodoItem
    let tint: Color
    @State private var hovering = false

    /// 正在就地改写这一行。改写时删除让开，排期入口留着。
    @State private var editing = TodoEditing()

    /// 刚在这一行上打了勾，这条正在离开这一列。
    ///
    /// 打勾和删除在这一列都以「行没了」收场（这儿的待办按定义都是未完成的，一勾就不再属于这一列），
    /// 可两件事完全不是一回事。所以打勾先把圈填实、亮一拍，再让它淡出；删除则直接收走。
    /// 那一拍里圈画的是「已完成」而待办本身还没变，所以状态记在这儿，不去问 `todo.done`。
    @State private var completing = false

    var body: some View {
        HStack(spacing: TodoRowLayout.spacing) {
            TodoToggle(done: completing, tint: tint, toggle: complete)

            // 字号罩在外面而不是写在 `Text` 上：改写时那格换成输入框，两种模样的字因此一样大。
            TodoText(todo: todo, editing: $editing)
                .font(.callout)

            Spacer(minLength: 8)

            PlannedDayControl(todo: todo, rowHovering: hovering)

            // 改写时不浮出删除：手正放在字上，旁边不该还摆着一个删得掉整条的按钮。
            if hovering && !editing.active {
                TodoDeleteButton { withAnimation { store.deleteTodo(todo) } }
            }
        }
        .todoRowChrome(hovering: hovering)
        .onHover { hovering = $0 }
        // 内缩一并算进拖拽范围里，免得只有正文那几个字抓得住。
        .contentShape(Rectangle())
        .todoRowEditing(todo, editing: $editing)
        .draggable(DraggedTodo(id: todo.id)) {
            TodoDragPreview(text: todo.text, tint: tint)
        }
        // 落间换位、落身入怀：组内的顺序与分类视图左列是同一份，缝也照样接。
        .todoTreeDropTarget(todo, allowsGaps: true)
    }

    /// 打勾：圈先亮起来，过一拍这条才真的记成完成、跟着淡出这一列。
    /// 中间那一拍是说给人看的 —— 没有它，点下去只看得见一行凭空消失。
    private func complete() {
        // 那一拍里圈还画得出来、行也还在，手快的话点得到第二下 ——
        // 放它过去就会打两次勾，第二下把第一下取消掉，行留在原地而圈仍旧亮着。
        guard !completing else { return }
        completing = true
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeOut(duration: 0.2)) { store.toggleTodo(todo) }
        }
    }
}
