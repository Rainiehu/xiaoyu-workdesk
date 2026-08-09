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

    func body(content: Content) -> some View {
        content
            .overlay {
                if enabled {
                    panelOverlay
                }
            }
            // 把手挂在面板外面：面板收着时它就是右缘那一枚常驻记号。
            .overlay(alignment: .trailing) {
                if enabled && !isOpen { edgeHandle }
            }
            .onChange(of: enabled) { _, enabled in
                if !enabled { isOpen = false }
            }
    }

    private var panelOverlay: some View {
        GeometryReader { geo in
            let panelWidth = geo.size.width * 0.76
            ZStack(alignment: .trailing) {
                // 面板开着时主列退成背景：变暗、点一下就回去。
                Color.black.opacity(isOpen ? 0.22 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { setOpen(false) }
                    .allowsHitTesting(isOpen)

                panelBody(width: panelWidth)
                    .offset(x: isOpen ? 0 : panelWidth + 40)
            }
            .animation(.spring(duration: 0.3), value: isOpen)
        }
    }

    private func panelBody(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            // 面板左缘的把手原位留着：拉出它的那只手，推回去还是它。
            PanelGrabber()
                .padding(.leading, 5)
            panel()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: width)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 17, x: -6, y: 0)
        )
        .ignoresSafeArea(edges: .bottom)
        // 面板上往右一划就是收回 —— 与拉出是同一个手势的两个方向。
        .gesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    if value.translation.width > 40 { setOpen(false) }
                }
        )
    }

    /// 右缘常驻的竖把手。画出来的只有一枚细条，接手势的范围比它大得多 ——
    /// 指头要的是「往右缘一按一划」，不是精确命中四个点宽的线。
    private var edgeHandle: some View {
        PanelGrabber()
            .padding(.trailing, 5)
            .frame(width: 32, height: 140)
            .contentShape(Rectangle())
            .onTapGesture { setOpen(true) }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        if value.translation.width < -25 { setOpen(true) }
                    }
            )
    }

    private func setOpen(_ open: Bool) {
        withAnimation(.spring(duration: 0.3)) { isOpen = open }
    }
}

/// 把手那一枚竖条本身。收着时在屏右缘，开着时在面板左缘 —— 同一枚。
private struct PanelGrabber: View {
    var body: some View {
        Capsule()
            .fill(.tertiary)
            .frame(width: 4.5, height: 52)
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
