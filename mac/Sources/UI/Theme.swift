// 语义色、动态深浅配色与主题映射

import Foundation
import AppKit
import SwiftUI

extension Notification.Name {
    static let owOpenSettings = Notification.Name("com.rumor.offwork-countdown.openSettings")
}

func preferredScheme(_ theme: Int) -> ColorScheme? {
    if theme == 1 { return .dark }
    if theme == 2 { return .light }
    return nil
}

struct RGB {
    var r: Double, g: Double, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = min(max(r, 0), 1); self.g = min(max(g, 0), 1); self.b = min(max(b, 0), 1)
    }

    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 6, let v = UInt32(s, radix: 16) {
            self.init(Double((v >> 16) & 0xFF) / 255,
                      Double((v >> 8) & 0xFF) / 255,
                      Double(v & 0xFF) / 255)
        } else {
            self.init(0.486, 0.576, 0.659) // 默认雾蓝 #7C93A8
        }
    }

    init(_ color: Color) {
        if let cg = color.cgColor,
           let ns = NSColor(cgColor: cg)?.usingColorSpace(.deviceRGB) {
            self.init(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
        } else {
            self.init(hex: "#7C93A8")
        }
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    var hex: String {
        String(format: "#%02X%02X%02X", UInt32(r * 255), UInt32(g * 255), UInt32(b * 255))
    }

}

/// apple.com 官网风格的克制配色：近黑 / 次要灰 / 官网蓝 + 低饱和金属色，纯色无渐变。
/// 每色都有浅色、深色两套值（官网深色模式会把文字反相），两种外观下都保证可读。
/// 索引 0-4 保持不变以兼容旧设置。
func appleColor(light: String, dark: String) -> Color {
    Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let c = RGB(hex: isDark ? dark : light)
        return NSColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g),
                       blue: CGFloat(c.b), alpha: 1)
    }))
}

/// 设置面板语义色：白底 + apple.com 灰阶，浅色/深色两套值（HIG 层级色，不用手动 opacity）
enum PanelColor {
    static let background = appleColor(light: "#FFFFFF", dark: "#1C1C1E")
    static let card       = appleColor(light: "#F5F5F7", dark: "#2C2C2E")
    static let secondary  = appleColor(light: "#6E6E73", dark: "#A1A1A6")
}

/// 固定主色：近黑（浅色）/ 近白（深色），与设置面板一样走系统黑白灰，不再提供配色自定义。
func paletteColor(_ p: Prefs) -> Color { Color.primary }


