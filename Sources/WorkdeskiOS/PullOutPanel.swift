#if os(iOS)
import SwiftUI

/// 右缘把手拉出的面板 —— 每屏主列之外那块副列的容器，两屏同一副（见 CONTEXT-iOS.md）。
/// Mac 上这两块副列都在右边，手机上就从右缘拉出：空间事实原样带过来。
///
/// 把手常驻在右缘中部；拉它或从右缘向左一划，面板滑出，盖住约七成半屏宽，
/// 左边留一条露着主列 —— 点它或往右一划就回去。面板开着时把手留在面板左缘原位。
struct PullOutPanel<Panel: View>: ViewModifier {
    /// 这一屏眼下有没有副列可谈。没有（比如分类整个是空的）就连把手也不挂 ——
    /// 拉开一块空面板不如不给入口，与 Mac 的「一件事都没有时不分列」同一条。
    var enabled: Bool = true
    @Binding var isOpen: Bool
    @ViewBuilder let panel: () -> Panel

    /// 手指拖着面板走过的横向位移（相对这次拖动的起点）。nil ＝ 没在拖。
    /// 拖动中面板直接跟手 —— 「自己一点点拉出来」的感觉全在这层跟随上；
    /// 松手才按预测落点定去留。
    @State private var dragX: CGFloat?

    func body(content: Content) -> some View {
        content
            .overlay {
                if enabled {
                    panelOverlay
                }
            }
            .onChange(of: enabled) { _, enabled in
                if !enabled { isOpen = false }
            }
    }

    private var panelOverlay: some View {
        GeometryReader { geo in
            let panelWidth = geo.size.width * 0.76
            // 面板此刻实际停在哪：静止时在开/收的位子上，拖着就跟手，两头不出界。
            let restX: CGFloat = isOpen ? 0 : panelWidth
            let offsetX = min(max(restX + (dragX ?? 0), 0), panelWidth)
            let progress = 1 - offsetX / panelWidth

            ZStack(alignment: .trailing) {
                // 主列随拉出的进度退暗 —— 暗几分也跟着手走。点一下就回去。
                Color.black.opacity(0.22 * progress)
                    .ignoresSafeArea()
                    .onTapGesture { setOpen(false) }
                    .allowsHitTesting(isOpen)

                // 收着时面板本体正好整个滑出屏外，只剩钉在左缘的拉带露在屏缘 ——
                // 右缘那一枚把手就是面板自己的把手，不是另画的记号。
                panelBody(width: panelWidth, progress: progress)
                    .offset(x: offsetX)

                // 收着时罩在拉带上的命中区 —— 拉带本体钉在面板上，这层只接手势。
                if !isOpen { edgeHitZone(panelWidth: panelWidth) }
            }
        }
    }

    private func panelBody(width: CGFloat, progress: CGFloat) -> some View {
        panel()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(width: width)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22)
                    .fill(PaperTheme.paper)
                    // 影子随拉出的进度显影：收着时面板贴在屏外，右缘不该常年洇着一道黑。
                    .shadow(color: .black.opacity(0.18 * progress), radius: 17, x: -6, y: 0)
            )
            // 拉带钉在面板左缘、探出缘外 —— 拉开收回全程它与面板相对位置不变：
            // 把手装在这页上，人只是顺着把手把这一页拉出来。
            .overlay(alignment: .leading) {
                LeatherPullTab()
                    .offset(x: -(LeatherPullTab.size.width - 2))
            }
            .ignoresSafeArea(edges: .bottom)
            // 面板上往右一划就是收回 —— 与拉出是同一个手势的两个方向。
            .gesture(panelDrag(panelWidth: width, minimumDistance: 25))
    }

    /// 右缘的命中区，收着时罩在拉带上方。画的什么都没有 —— 拉带本体在面板上；
    /// 这儿只管接手势：44pt 宽一条带，起笔落在带内的一划归把手，
    /// 落在带外的归行上的左滑删除。起笔位置定归属，两个同方向的横划就此分家。
    private func edgeHitZone(panelWidth: CGFloat) -> some View {
        Color.clear
            .frame(width: 44, height: 140)
            .contentShape(Rectangle())
            .onTapGesture { setOpen(true) }
            .gesture(panelDrag(panelWidth: panelWidth, minimumDistance: 10))
    }

    /// 拖面板的那一个手势，开与收共用：拖动中面板跟手，松手按预测落点定去留 ——
    /// 甩的速度折在预测里，轻甩一下也走得完。门槛略偏向开：预测落点过了六成就算开。
    private func panelDrag(panelWidth: CGFloat, minimumDistance: CGFloat) -> some Gesture {
        // 位移必须在全局坐标系里量：收回的手势挂在面板上，面板又跟着手指动，
        // 用本地坐标系量位移就成了自己追自己 —— 每帧来回跳，看起来是闪。
        DragGesture(minimumDistance: minimumDistance, coordinateSpace: .global)
            .onChanged { value in
                // 方向门只把第一下：横移胜过纵移才接手 —— 顺着列表竖滚不该拖动面板；
                // 一旦接了手，指头走到哪面板跟到哪。
                guard dragX != nil || abs(value.translation.width) > abs(value.translation.height)
                else { return }
                dragX = value.translation.width
            }
            .onEnded { value in
                guard dragX != nil else { return }
                let restX: CGFloat = isOpen ? 0 : panelWidth
                let predicted = restX + value.predictedEndTranslation.width
                withAnimation(.spring(duration: 0.3)) {
                    dragX = nil
                    isOpen = predicted < panelWidth * 0.6
                }
            }
    }

    private func setOpen(_ open: Bool) {
        withAnimation(.spring(duration: 0.3)) { isOpen = open }
    }
}

/// 把手本体：一小截缝线皮革拉带，一粒铆钉 —— 看着就是拿来拽的实物，
/// 不会认成滚动条。它钉死在面板左缘，收着时露在屏缘的、拉开后探在页边的，
/// 从头到尾是同一枚。
private struct LeatherPullTab: View {
    static let size = CGSize(width: 26, height: 50)

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let hide: [UInt32] = scheme == .dark
            ? [0x8A6A42, 0x6E5230, 0x543D20]
            : [0xCB9D69, 0xB07D47, 0x9A6931]
        let shape = UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)

        shape
            .fill(LinearGradient(
                colors: hide.map { Color(UIColor(rgb: $0)) },
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .overlay(
                // 缝线：一圈奶白的虚线，内缩在皮面上。
                UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7)
                    .strokeBorder(
                        Color(UIColor(rgb: 0xFFF4E1)).opacity(0.55),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])
                    )
                    .padding(3)
            )
            .overlay(alignment: .leading) {
                // 铆钉：把皮条钉在缘上的那一粒。
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(UIColor(rgb: 0xF6ECDC)), Color(UIColor(rgb: 0x8A6A3F))],
                        center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 4
                    ))
                    .frame(width: 5.5, height: 5.5)
                    .padding(.leading, 7)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .shadow(color: .black.opacity(0.28), radius: 3, x: -2, y: 2)
    }
}

extension View {
    /// 给一屏挂上右缘把手与它拉出的面板。
    func pullOutPanel<Panel: View>(
        enabled: Bool = true, isOpen: Binding<Bool>, @ViewBuilder panel: @escaping () -> Panel
    ) -> some View {
        modifier(PullOutPanel(enabled: enabled, isOpen: isOpen, panel: panel))
    }
}

/// 面板顶上那句说明。轻到几乎不占分量 —— 它不是标题栏，是个标签。与 Mac 的列头同一副。
struct PanelHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .tracking(1)
            .padding(.horizontal, 14)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }
}
#endif
