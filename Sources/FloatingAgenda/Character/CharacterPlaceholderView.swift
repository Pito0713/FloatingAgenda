import SwiftUI

/// M9.2 的暫時佔位：一個 64×64pt 的色塊。
///
/// 存在的唯一目的是讓 M9.2 能單獨驗證「面板的右上角錨點與寬高同步」這件事，
/// 不必等真正的像素小精靈做完。M9.3 會用 `CharacterView` 取代它。
///
/// 刻意不畫任何細節：這個里程碑要證明的是面板幾何，不是外觀。
struct CharacterPlaceholderView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.accentColor)
            .frame(width: PanelMetrics.characterSize, height: PanelMetrics.characterSize)
            .overlay(
                Text("M9.2")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            )
            .padding(PanelMetrics.characterPadding)
            // 純顯示，不擋拖曳（拖曳與點擊的判斷是 M9.3 的範圍）
            .allowsHitTesting(false)
    }
}
