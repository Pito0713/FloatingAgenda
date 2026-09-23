import AppKit
import SwiftUI

/// 小精靈左邊的對話泡泡（M9 計畫 §4.2、§4.4）。
///
/// 這個 View **不認識任何 store**：要顯示的那一行由外面注入，
/// `--snapshot` 才能用固定文字渲染。
struct BubbleView: View {
    let text: String
    /// App 內用毛玻璃（半透明），snapshot 用不透明底色——
    /// `ImageRenderer` 畫不出 `NSVisualEffectView`（與卡片同一個理由）
    var background: CardBackground = .blur
    /// 滑鼠停在泡泡上時暫停輪播（§4.2）
    var onHoverChange: (Bool) -> Void = { _ in }

    /// 泡泡的**固定**寬度。
    ///
    /// 計畫 §4.2 原本是「最寬 220pt、12pt 字」。使用者 2026-09-23 實際看過之後
    /// 定案為固定 250pt、16pt 字：字要大一點才看得清楚，框要固定才不會隨每則
    /// 文字長短改變寬度（不固定時泡泡會隨輪播一直變寬變窄，看起來像畫面在跳）。
    ///
    /// 用 `frame(width:)` 而不是 `maxWidth` 就是為了固定這件事。
    static let width: CGFloat = 250
    static let fontSize: CGFloat = 16
    /// 泡泡的高度上限。超過就在尾端截斷加「…」（使用者 2026-09-23 要求）。
    ///
    /// 用**高度**而不是寫死行數：字級或內距改了之後，能塞幾行會跟著變，
    /// 寫死行數會讓實際高度偏離這個上限
    static let maxHeight: CGFloat = 300
    /// 內距也跟著放大，字大了邊距不跟著加會很擠
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.system(size: Self.fontSize))
            .foregroundStyle(.primary)
            // 高度隨斷行自己長，到上限就截斷加「…」
            .lineLimit(Self.maxLines)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: Self.width, alignment: .leading)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background(backgroundLayer)
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    .allowsHitTesting(false)
            )
            .onHover(perform: onHoverChange)
    }

    /// 由高度上限換算出來的行數上限。
    /// `lineLimit` 才會在尾端補「…」——直接用 `.frame(maxHeight:)` 是**裁切**不是截斷
    static var maxLines: Int {
        let font = NSFont.systemFont(ofSize: fontSize)
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        let available = maxHeight - verticalPadding * 2
        return max(1, Int(available / lineHeight))
    }

    private static let cornerRadius: CGFloat = 10

    @ViewBuilder
    private var backgroundLayer: some View {
        switch background {
        case .blur:
            // 跟卡片同一種毛玻璃，所以桌布會透出來
            WidgetBackground(cornerRadius: Self.cornerRadius)
        case .opaque:
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
    }
}

extension VerticalAlignment {
    /// 讓**泡泡的底部**對齊**小精靈的垂直中線**（M9，使用者 2026-09-23 定案）。
    ///
    /// SwiftUI 內建的 `.top`／`.center`／`.bottom` 都做不到「兩邊各取不同的基準線」，
    /// 只有自訂 `AlignmentID` 可以：泡泡回報自己的 `.bottom`、小精靈回報自己的 `.center`，
    /// HStack 就會把這兩條線對在一起。
    private enum BubbleBottomToCharacterCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let bubbleBottomToCharacterCenter =
        VerticalAlignment(BubbleBottomToCharacterCenter.self)
}
