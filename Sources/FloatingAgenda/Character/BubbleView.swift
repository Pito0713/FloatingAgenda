import SwiftUI

/// 小精靈左邊的對話泡泡（M9 計畫 §4.2、§4.4）。
///
/// 這個 View **不認識任何 store**：要顯示的那一行由外面注入，
/// `--snapshot` 才能用固定文字渲染。
struct BubbleView: View {
    let text: String
    /// 滑鼠停在泡泡上時暫停輪播（§4.2）
    var onHoverChange: (Bool) -> Void = { _ in }

    /// 泡泡最寬 220pt、最多 3 行，超過就截斷加「…」（§4.2）
    static let maxWidth: CGFloat = 220
    static let maxLines = 3

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .lineLimit(Self.maxLines)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: Self.maxWidth, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
            .onHover(perform: onHoverChange)
    }
}
