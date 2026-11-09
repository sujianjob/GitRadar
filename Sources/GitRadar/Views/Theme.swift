import AppKit
import SwiftUI

// MARK: - 借鉴 Linear / Fork / GitHub Desktop 的克制专业桌面配色方案
enum AppTheme {
    // 面板与卡片表面色（克制的石墨/岩石中性色系，拒绝高饱和度 AI 霓虹感）
    static let canvasBackground = Color(nsColor: .windowBackgroundColor)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let subtleSurface = Color.primary.opacity(0.035)
    static let elevatedSurface = Color.primary.opacity(0.055)

    // 边框线（1px 极细发丝分割线）
    static let hairlineBorder = Color.primary.opacity(0.08)
    static let hoverBorder = Color.primary.opacity(0.18)
    static let selectedBorder = Color(red: 0.27, green: 0.48, blue: 0.72) // 岩石钢蓝

    // 品牌与交互主色（低饱和度专业岩石蓝 Slate Blue）
    static let accent = Color(red: 0.25, green: 0.46, blue: 0.70)

    // 语义状态色（仅用于 6px 状态圆点与关键小字，参照 GitHub Desktop / Fork 规范）
    static let statusClean = Color(red: 0.18, green: 0.63, blue: 0.26)     // #2EA043 森林绿
    static let statusDirty = Color(red: 0.78, green: 0.56, blue: 0.15)     // #C69026 琥珀黄
    static let statusSync = Color(red: 0.32, green: 0.52, blue: 0.76)      // #5285C2 岩石蓝
    static let statusDanger = Color(red: 0.81, green: 0.13, blue: 0.18)    // #CF222E 警示红
    static let statusNeutral = Color(red: 0.45, green: 0.49, blue: 0.54)   // #737D8A 石墨灰

    // 仓库头像低饱和莫兰迪/石墨底色池（用于无图片时的专属图标背景，沉稳耐看）
    static let avatarPalettes: [(bg: Color, fg: Color)] = [
        (Color(red: 0.19, green: 0.24, blue: 0.31), Color(red: 0.78, green: 0.85, blue: 0.94)), // 岩石深蓝
        (Color(red: 0.20, green: 0.27, blue: 0.24), Color(red: 0.75, green: 0.89, blue: 0.82)), // 松石深绿
        (Color(red: 0.27, green: 0.23, blue: 0.20), Color(red: 0.93, green: 0.84, blue: 0.74)), // 暖褐岩灰
        (Color(red: 0.24, green: 0.22, blue: 0.29), Color(red: 0.84, green: 0.80, blue: 0.93)), // 石墨暗紫
        (Color(red: 0.26, green: 0.21, blue: 0.22), Color(red: 0.93, green: 0.78, blue: 0.80)), // 暗砖灰红
        (Color(red: 0.18, green: 0.26, blue: 0.28), Color(red: 0.74, green: 0.88, blue: 0.91)), // 青灰深海
        (Color(red: 0.23, green: 0.24, blue: 0.26), Color(red: 0.85, green: 0.87, blue: 0.89))  // 钛空暗灰
    ]

    static func palette(for text: String) -> (bg: Color, fg: Color) {
        var hash: UInt64 = 5381
        for byte in text.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let idx = Int(hash % UInt64(avatarPalettes.count))
        return avatarPalettes[idx]
    }
}
