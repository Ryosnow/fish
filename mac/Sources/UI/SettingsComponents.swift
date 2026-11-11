// 设置面板通用组件：细分隔线、分组卡片、复选框行

import SwiftUI

/// 卡片内行间细分隔线（Cursor 设置页风格）
struct CardSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}

/// 分组卡片：分组标题在卡片外、白底细边框、行间细线分隔（Cursor 设置页风格）
struct SettingsCard<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(PanelColor.secondary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PanelColor.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )
        }
    }
}

/// macOS 原生复选框（替代蓝色胶囊开关）：标题 + 可选一行说明
struct CheckRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: $isOn) {
                Text(title).font(.body).foregroundStyle(.primary)
            }
            .toggleStyle(.checkbox)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PanelColor.secondary)
                    .padding(.leading, 20)
            }
        }
        .padding(.vertical, 9)
    }
}

