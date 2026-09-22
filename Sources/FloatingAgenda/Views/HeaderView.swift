import SwiftUI

/// 卡片標題：紅色星期 + 粗體日期（仿原生小工具）
struct HeaderView: View {
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Formatting.weekdayTitle(for: date))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
            Text(Formatting.dateTitle(for: date))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
        }
    }
}
