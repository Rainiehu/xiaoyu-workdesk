import Foundation

/// 色名到色值的那张表。落盘的只有色名（见 `CategoryColor`），色值本属视图层 ——
/// 但两端（macOS 与 iOS）各抄一张表就埋下漂移的种子，所以数值定在这儿一处，
/// 两端只做「数值 → 各自平台的动态颜色」那一步。
extension CategoryColor {
    /// (浅色外观, 深色外观)，0xRRGGBB。同一档明度上绕色相环取的一圈，于是整块色板浓淡一致；
    /// tab 上的字是这个颜色本身，两种外观下都得压得住背景读得清。
    public var rgbValues: (light: UInt32, dark: UInt32) {
        switch self {
        case .red: (0xDC2626, 0xF87171)
        case .orange: (0xEA580C, 0xFB923C)
        case .amber: (0xD97706, 0xFBBF24)
        case .lime: (0x65A30D, 0xA3E635)
        case .green: (0x16A34A, 0x4ADE80)
        case .mint: (0x059669, 0x34D399)
        case .teal: (0x0E96A8, 0x3FCEDC)
        case .cyan: (0x0284C7, 0x38BDF8)
        case .blue: (0x2563EB, 0x60A5FA)
        case .indigo: (0x4F46E5, 0x818CF8)
        case .purple: (0x9333EA, 0xC084FC)
        case .fuchsia: (0xC026D3, 0xE879F9)
        case .pink: (0xDB2777, 0xF472B6)
        case .slate: (0x52525B, 0xA1A1AA)
        }
    }
}

/// 过期记号的琥珀，同样两副色值一处定。刻意不取分类色板里的 amber ——
/// 那是某个分类的记号，这是一层状态，撞了色就分不清，所以压灰压暗一档。
public enum OverdueAmber {
    public static let light: UInt32 = 0xC2801F
    public static let dark: UInt32 = 0xD9A558
}
