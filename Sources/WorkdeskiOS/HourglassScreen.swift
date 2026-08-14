#if os(iOS)
import SwiftUI
import WorkdeskCore

/// 沙漏屏：横跨所有分类的一条连续时间轴，按计划日铺开，今天锚在中间、上方是过去、
/// 下方是未来，打开时就滚到今天。分组由 `Store.timeline(today:)` 给出，这里不自己聚合。
///
/// 屏底是记事输入栏（写字的地方挨着手）：在这儿记下的待办自动排在今天，
/// 立刻出现在眼前这条轴上。「今天居中不看今天是不是尽头」的垫高逻辑与 Mac 同一套。
struct HourglassScreen: View {
    @Environment(Store.self) private var store
    @Environment(TodayClock.self) private var clock

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    /// 未排期面板拉开着。
    @State private var unscheduledOpen = false

    /// 今天那一组在轴内容里的纵向中点，和轴内容的总高 —— 「按需垫高」的量具，与 Mac 同一套。
    @State private var todayCenterY: CGFloat?
    @State private var contentHeight: CGFloat?

    /// 中线上锚着哪一天。打开时指今天；用户一滚，绑定就改指中线上的那一天。
    @State private var anchorDay: Date?

    private static let contentSpace = "hourglassTimeline"

    var body: some View {
        let today = clock.today

        return timeline(today: today)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let category = store.recordingCategory {
                    input(category: category, today: today)
                }
            }
            // 未排期是沙漏屏的副列，从右缘拉出 —— 轴答「排在哪天」，它答「还有什么没安排」。
            .pullOutPanel(isOpen: $unscheduledOpen) {
                UnscheduledPanel()
            }
    }

    private func timeline(today: Date) -> some View {
        GeometryReader { geo in
            let insets = endInsets(half: geo.size.height / 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.timeline(today: today)) { day in
                        DayGroup(day: day, today: today)
                            .id(day.day)
                            .onGeometryChange(for: CGFloat.self) {
                                $0.frame(in: .named(Self.contentSpace)).midY
                            } action: { midY in
                                // 亚点级的抖动不写回状态 —— 写了就会「测量 → 垫高 → 再测量」
                                // 空转下去，iOS 上这个循环不像 Mac 那样自己停。
                                if day.day.isSameDay(as: today), significantChange(todayCenterY, midY) {
                                    todayCenterY = midY
                                }
                            }
                    }
                }
                .scrollTargetLayout()
                .coordinateSpace(name: Self.contentSpace)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if significantChange(contentHeight, height) { contentHeight = height }
                }
                .padding(.horizontal, ScreenLayout.screenEdge)
                .padding(.top, insets.top)
                .padding(.bottom, insets.bottom)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollPosition(id: $anchorDay, anchor: .center)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .topEdgeFade()
            // 那只眼浮在轴滚动区的右上角，与 Mac 同一个部位：它管的就是这片内容，
            // 站在这片内容的角上。挂在顶缘淡出之后 —— 开关是浮物，不该跟着内容隐进纸里。
            .overlay(alignment: .topTrailing) {
                TimelineEyeToggle()
                    .padding(.top, 8)
                    .padding(.trailing, 14)
            }
            .onAppear {
                anchorDay = today.dayStart
            }
            // 过了一天就重新锚回今天，跟刚打开一样 —— 手机上 app 常驻后台好几天是常态。
            .onChange(of: today) { _, now in
                withAnimation(.easeInOut(duration: 0.3)) {
                    anchorDay = now.dayStart
                }
            }
        }
    }

    /// 半个点以上才算真变了。测量值喂回布局的循环里，浮点的微抖必须在这儿拦住。
    private func significantChange(_ old: CGFloat?, _ new: CGFloat) -> Bool {
        guard let old else { return true }
        return abs(old - new) > 0.5
    }

    /// 轴两头按需垫的空白，与 Mac 的 `endInsets` 同一套：今天哪一侧的内容不够半屏，
    /// 就在那头垫上差的那一截，够了的一侧一点不垫。
    ///
    /// 内容不满一屏时一点不垫，从顶排下来：那时一眼看得全，「今天在中线」换来的
    /// 只是头顶一段没来由的空白。满了一屏才有滚动可言，锚定才值得垫。
    private func endInsets(half: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        guard let center = todayCenterY, let height = contentHeight else {
            return (half, half)
        }
        guard height > half * 2 else { return (0, 0) }
        return (max(0, half - center), max(0, half - (height - center)))
    }

    private func input(category: Category, today: Date) -> some View {
        InputBar(
            tint: .teal,
            prompt: "记一件事，记在今天…",
            text: $draft,
            focused: $inputFocused,
            submit: { record(today: today) }
        ) {
            RecordingCategoryPicker(current: category)
        }
    }

    /// 记下草稿里的那件事。归到哪个分类、排在哪一天都由 `Store` 定；
    /// 这里只管清空并留住焦点，好让记事可以一条接一条。
    private func record(today: Date) {
        store.recordOnTimeline(draft, today: today)
        draft = ""
        inputFocused = true
    }
}

/// 轴上的一天：一个日期头，下面是这天的待办。今天这一组用强调样式，它是锚点；
/// 别的日子一律同一副模样 —— 与 Mac 同一套。
private struct DayGroup: View {
    @Environment(Store.self) private var store
    let day: TimelineDay
    let today: Date

    private var isToday: Bool { day.day.isSameDay(as: today) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            ForEach(day.todos) { todo in
                // 删除态的行是原位占位：撤销窗口开着的那几秒它还站在这儿，见 ADR-0007。
                if todo.isDeleted {
                    DeletedTodoRow(todo: todo)
                } else {
                    TimelineRow(todo: todo, today: today)
                    // 子树常开，就摊在行底下 —— 轴上也不例外，圈随轴取青。
                    SubTodoTree(parentID: todo.id, tint: .teal)
                }
            }
            if isToday && day.todos.isEmpty {
                Text("今天还没有安排")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        // 行融在纸底里，不描框不垫卡 —— 只有今天罩一层青，锚点靠色说话。
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isToday ? AnyShapeStyle(.teal.opacity(0.08)) : AnyShapeStyle(.clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        // 拖着的行悬进哪一天，当场就排进那一天 —— 轴本身就是预览，
        // 松手即所见即所得；已经在这天的悬过也不折腾。
        .todoDropTarget(entered: { id in
            guard !day.todos.contains(where: { $0.id == id }) else { return }
            withAnimation(.spring(duration: 0.2)) {
                if store.reschedule(id, to: day.day) {
                    Buzz.light.impactOccurred(); Buzz.warm()
                }
            }
        }, perform: { _ in
            Buzz.notify.notificationOccurred(.success)
            return true
        })
    }

    /// 日期头。今天的写得大些、重些、是青的 —— 强调它靠字本身。
    private var header: some View {
        Text(day.day.dayLabel(relativeTo: today))
            .font(.system(size: isToday ? 17 : 14, weight: isToday ? .semibold : .medium, design: .rounded))
            .foregroundStyle(isToday ? AnyShapeStyle(.teal) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
    }
}

/// 轴上的一行待办：打勾的圈、正文、所属分类的 tag（光板，不着色）。
/// 勾圈填整体主调的青色 —— 一屏几十行，每行一个彩色勾圈就成了噪点，
/// 而这一屏该抢眼的是「今天」。与 Mac 同一条理由。
private struct TimelineRow: View {
    @Environment(Store.self) private var store
    let todo: TodoItem
    let today: Date

    /// 正在就地改写这一行。三处的行都是这一套。
    @State private var editing = TodoEditing()

    private var category: Category? { store.category(todo.categoryID) }
    private let tint: Color = .teal

    var body: some View {
        HStack(spacing: TodoRowLayout.spacing) {
            TodoToggle(done: todo.done, overdue: todo.isOverdue(today: today), tint: tint) {
                // 带动画：那只眼闭着时，勾下去这一行就随动画淡出 —— 开关说不看已完成，
                // 打完勾的当场就走，全完成的日子连组一起收。睁着时这下动画只动样式，无妨。
                withAnimation(.easeOut(duration: 0.2)) { store.toggleTodo(todo) }
            }

            TodoText(todo: todo, editing: $editing)
                .foregroundStyle(todo.done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

            Spacer(minLength: 8)

            // 排期入口只有图标，不带日期标签：这一行就躺在它计划日的分组底下，
            // 那天写在组头上，行上再挂一遍就是一列重复的灰字。
            PlannedDayEntry(todo: todo, showsDate: false)

            if let category {
                CategoryTag(category: category, chip: false)
            }
        }
        .todoRowChrome()
        .contentShape(Rectangle())
        .todoRowActions(todo, editing: $editing)
        // 整行都拖得动，包括已完成的 —— 做完的事也照样可以改它排在哪天。
        .todoDragSource(todo)
        .swipeToDelete(deleteTodo)
    }

    private func deleteTodo() {
        withAnimation { store.deleteTodo(todo) }
    }
}

// MARK: - 轴右上角的那只眼

/// 睁着 = 已完成都在；闭上 = 眼不见为净。点一下翻面，全轴生效、没有哪一天是例外；
/// 选择由 `Store` 记着、本地各记各的 —— 这是「怎么看」的习惯，不是数据，两端各看各的。
///
/// SF Symbols 只有 eye / eye.slash、没有闭眼，所以两副形态都自绘：同一条轮廓
/// 在睁闭之间连续变形，拨那一下是一次真的眨眼，不是两张图的硬切。与 Mac 同一副。
/// 灰调、垫一层薄材质底 —— 行从它底下滚过时压得住，又不与「今天」抢戏。
private struct TimelineEyeToggle: View {
    @Environment(Store.self) private var store

    var body: some View {
        let hidden = store.hidesCompletedOnTimeline
        Button {
            Buzz.light.impactOccurred()
            withAnimation(.easeInOut(duration: 0.22)) {
                store.toggleHidesCompletedOnTimeline()
            }
        } label: {
            ZStack {
                EyeLids(openness: hidden ? 0 : 1)
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                // 瞳孔与睫毛不参与变形，随睁闭各自淡入淡出 —— 眨到一半的眼里
                // 既不该有整颗瞳孔，也不该已经长出睫毛。
                Circle()
                    .fill(.secondary)
                    .frame(width: 4.5, height: 4.5)
                    .opacity(hidden ? 0 : 1)
                EyeLashes()
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .opacity(hidden ? 1 : 0)
            }
            .frame(width: 16, height: 16)
            // 点击域到 44pt：图形小、手指不小。薄材质底只垫在图形那一圈。
            .frame(width: 28, height: 28)
            .background(.ultraThinMaterial, in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hidden ? "显示已完成" : "隐藏已完成")
    }
}

/// 眼睑的轮廓：`openness` 从 1（睁）到 0（闭）连续可变。睁着是杏仁形的上下睑，
/// 闭上时两条睑合到同一道下弯的弧上 —— 弧朝下，闭着的眼才不会被读成一条抿直的嘴。
private struct EyeLids: Shape {
    var openness: CGFloat

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let left = CGPoint(x: rect.minX + 0.09 * rect.width, y: rect.minY + 0.47 * rect.height)
        let right = CGPoint(x: rect.maxX - 0.09 * rect.width, y: left.y)
        // 二次曲线的控制点：睁着时上睑弓到顶、下睑坠到底（都越出格子，弓出来的
        // 顶点才落在格内），闭上时两条一起落到同一个点 —— 那道下弯的弧。
        let closed = rect.minY + 0.66 * rect.height
        let top = closed + (rect.minY - 0.03 * rect.height - closed) * openness
        let bottom = closed + (rect.minY + 1.03 * rect.height - closed) * openness
        var path = Path()
        path.move(to: left)
        path.addQuadCurve(to: right, control: CGPoint(x: rect.midX, y: top))
        path.addQuadCurve(to: left, control: CGPoint(x: rect.midX, y: bottom))
        return path
    }
}

/// 闭眼时那三根睫毛。只在闭合时露面，露不露由外面的透明度管，形状本身不变。
private struct EyeLashes: Shape {
    func path(in rect: CGRect) -> Path {
        let lashes: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 0.26, y: 0.59), CGPoint(x: 0.20, y: 0.71)),
            (CGPoint(x: 0.50, y: 0.63), CGPoint(x: 0.50, y: 0.76)),
            (CGPoint(x: 0.74, y: 0.59), CGPoint(x: 0.80, y: 0.71)),
        ]
        var path = Path()
        for (from, to) in lashes {
            path.move(to: CGPoint(x: rect.minX + from.x * rect.width, y: rect.minY + from.y * rect.height))
            path.addLine(to: CGPoint(x: rect.minX + to.x * rect.width, y: rect.minY + to.y * rect.height))
        }
        return path
    }
}
#endif
