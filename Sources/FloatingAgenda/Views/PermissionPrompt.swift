import SwiftUI

/// 權限不足時的區塊內容（PLAN §4.6）：說明文字 ＋ 直接打開對應的系統設定頁。
///
/// 按鈕刻意自繪而不用 `.buttonStyle(.link)`：後者是 AppKit 控件，
/// `ImageRenderer` 畫不出來（snapshot 會變成佔位方塊），而且外觀不如自繪的貼近原生小工具。
struct PermissionPrompt: View {
    let message: String
    /// 收合模式的內容會放大 1.25 倍，這裡跟著放大才不會只有權限提示特別小
    var fontSize: CGFloat = 11
    let openSettings: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(message)
                .font(.system(size: fontSize))
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)

            Button(action: openSettings) {
                Text("打開系統設定")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .underline(isHovering)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
        }
    }
}
