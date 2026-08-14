import CoreGraphics

/// 沙漏轴的布局算术，两端同一套 —— 纯算法，与呈现无关，所以住在共享层。
public enum TimelineLayout {
    /// 轴两头按需垫的空白：今天哪一侧的内容不够半屏，就在那头垫上差的那一截，
    /// 够了的一侧一点不垫 —— `scrollTo(anchor: .center)` 只在目标两边都还有内容可滚时
    /// 才居得了中，这两段垫的就是「可滚」的下限。还没量出今天在哪之前先按半屏垫着
    /// （等于从前的行为），量到了再收 —— 所以这里的空白只会少、不会多。
    ///
    /// 内容不满一屏时一点不垫，从顶排下来：那时一眼看得全，「今天在中线」换来的
    /// 只是头顶一段没来由的空白。满了一屏才有滚动可言，锚定才值得垫。
    public static func endInsets(
        half: CGFloat, todayCenterY: CGFloat?, contentHeight: CGFloat?
    ) -> (top: CGFloat, bottom: CGFloat) {
        guard let center = todayCenterY, let height = contentHeight else {
            return (half, half)
        }
        guard height > half * 2 else { return (0, 0) }
        return (max(0, half - center), max(0, half - (height - center)))
    }
}
