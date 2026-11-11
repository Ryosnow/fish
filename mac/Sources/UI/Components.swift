// 共享展示组件：倒计时数字与进度条

import SwiftUI

struct DigitsText: View {
    let st: CountdownState
    let size: CGFloat
    let color: Color
    var body: some View {
        Text(st.digits)
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(color)
    }
}

struct ProgressBar: View {
    let value: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 7)
        .animation(.easeInOut(duration: 0.7), value: value)
    }
}

