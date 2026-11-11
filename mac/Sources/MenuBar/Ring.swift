// 菜单栏进度环：自绘 NSView、色点与百分比绘制参数

import AppKit

/// 右下角进度阶段色点（低饱和 RGB，0...1）
struct RingDot: Equatable {
    var r: Double, g: Double, b: Double
}

/// 四段纯色，到边界直接切换；只在「等下班」阶段显示
func ringDotColor(phase: Phase, progress: Double, isStealth: Bool) -> RingDot? {
    guard !isStealth, (phase == .working || phase == .before) else { return nil }
    let green  = RingDot(r: 0.357, g: 0.682, b: 0.518) // #5BAE84
    let yellow = RingDot(r: 0.875, g: 0.761, b: 0.369) // #DFC25E
    let orange = RingDot(r: 0.878, g: 0.639, b: 0.333) // #E0A355
    let red    = RingDot(r: 1.0, g: 0.176, b: 0.176)  // #FF2D2D 正红（不偏橙、不偏粉）
    let p = min(max(progress, 0), 1)
    if p < 0.25 { return green  }   // 0–25%   绿
    if p < 0.50 { return yellow }   // 25–50%  黄
    if p < 0.75 { return orange }   // 50–75%  橙
    return red                      // 75–100% 红
}

/// 色点几何：右下角、稍微压住环的一小段（纯函数，便于自测越界）
struct RingDotGeometry {
    var center: CGPoint
    var radius: CGFloat
}

func ringDotGeometry(ringCenter: CGPoint, ringRadius: CGFloat) -> RingDotGeometry {
    let angle = -CGFloat.pi / 4
    let dist = ringRadius + 1.5   // 比原来更贴近环，让色点盖住环右下角一点
    return RingDotGeometry(
        center: CGPoint(x: ringCenter.x + dist * cos(angle),
                        y: ringCenter.y + dist * sin(angle)),
        radius: 3.0)             // 直径 6pt（原 4.4pt）
}

/// 进度环右侧的百分比文字；隐身时不显示
func menuPercentText(progress: Double, isStealth: Bool) -> String? {
    guard !isStealth else { return nil }
    let p = min(max(progress, 0), 1)
    return "\(Int(p * 100))%"
}

/// 绘制参数（纯数据，便于自测）
struct RingSpec {
    var baseAlpha: Double   // 底环透明度
    var progress: Double    // clamp 后的进度 0...1
    var dashed: Bool        // 休息日虚线环
    var filled: Bool        // 是否画实色弧（含满环）
    var centerDot: Bool     // 已下班的中心完成点
}

func ringSegments(phase: Phase, progress: Double, isStealth: Bool) -> RingSpec {
    let p = min(max(progress, 0), 1)
    if isStealth {
        return RingSpec(baseAlpha: 0.10, progress: 0, dashed: false, filled: false, centerDot: false)
    }
    switch phase {
    case .before, .working:
        return RingSpec(baseAlpha: 0.20, progress: p, dashed: false, filled: true, centerDot: false)
    case .off:
        return RingSpec(baseAlpha: 0.20, progress: 1, dashed: false, filled: true, centerDot: true)
    case .rest:
        return RingSpec(baseAlpha: 0, progress: 0, dashed: true, filled: false, centerDot: false)
    }
}

/// 菜单栏自绘进度环：14pt 细环，按今日进度填充，不显示任何数字
final class RingStatusView: NSView {
    var phase: Phase = .working
    var progress: Double = 0
    var isStealth = false
    var isBreak = false
    var showPercent = true

    // 只负责画内容；点击 / 高亮 / 菜单全部交给系统的 NSStatusBarButton
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let spec = ringSegments(phase: phase, progress: progress, isStealth: isStealth)
        let color = NSColor.controlTextColor   // 自动适配深浅模式
        // 环固定在左侧 x=10：纯环时(宽20)居中，带百分比时(宽48)靠左
        let c = CGPoint(x: 10, y: bounds.midY)
        let r: CGFloat = 7
        let lw: CGFloat = 2.5   // 稍粗一点，视觉重量更接近相邻的实心图标

        // 高亮由系统 NSStatusBarButton 绘制，这里只画内容（背景保持透明）
        if spec.baseAlpha > 0 {
            ctx.setStrokeColor(color.withAlphaComponent(spec.baseAlpha).cgColor)
            ctx.setLineWidth(lw)
            ctx.addArc(center: c, radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            ctx.strokePath()
        }

        if spec.dashed {
            ctx.setStrokeColor(color.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(lw)
            ctx.setLineCap(.butt)
            for i in 0..<8 {
                let a0 = CGFloat.pi / 2 - CGFloat(i) * .pi / 4 - 0.12
                ctx.addArc(center: c, radius: r, startAngle: a0, endAngle: a0 - 0.42, clockwise: true)
                ctx.strokePath()
            }
        } else if spec.filled {
            ctx.setStrokeColor(color.withAlphaComponent(0.95).cgColor)
            ctx.setLineWidth(lw)
            ctx.setLineCap(.round)
            let start = CGFloat.pi / 2
            let end = start - 2 * .pi * CGFloat(spec.progress)
            ctx.addArc(center: c, radius: r, startAngle: start, endAngle: end, clockwise: true)
            ctx.strokePath()
            if isBreak {
                // 午休：弧末端加一个小圆点表示暂停
                let p = CGPoint(x: c.x + r * cos(end), y: c.y + r * sin(end))
                color.withAlphaComponent(0.95).setFill()
                NSBezierPath(ovalIn: NSRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)).fill()
            }
        }

        if spec.centerDot {
            color.withAlphaComponent(0.95).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)).fill()
        }

        // 右下角进度阶段色点（绿 → 橙 → 红），最后绘制以盖住环的一小段
        if let dot = ringDotColor(phase: phase, progress: progress, isStealth: isStealth) {
            let geo = ringDotGeometry(ringCenter: c, ringRadius: r)
            let rad = geo.radius
            NSColor(red: CGFloat(dot.r), green: CGFloat(dot.g),
                    blue: CGFloat(dot.b), alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: geo.center.x - rad, y: geo.center.y - rad,
                                        width: rad * 2, height: rad * 2)).fill()
        }

        // 右侧百分比进度（参考其他菜单栏 app 的「图标 + 百分比」）
        if showPercent, let text = menuPercentText(progress: progress, isStealth: isStealth) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13.5, weight: .regular),
                .foregroundColor: color
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            // 右对齐：右边距固定 2pt，位数变化时空白不会堆在右侧；坐标取整避免半像素发虚
            let x = round(bounds.width - 2 - size.width)
            let y = round((bounds.height - size.height) / 2)
            (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

