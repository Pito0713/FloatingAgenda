import SwiftUI

/// 小精靈的**靜態**畫面，只給 `--snapshot` 用。
///
/// 正式 App 走 `CharacterLiveView`（NSView 直接繪圖，理由見 `CharacterHostView`）。
/// 這裡必須是純 SwiftUI：`ImageRenderer` 畫不出 `NSViewRepresentable`
/// （M5 記錄過同一個限制——`Toggle(.switch)` 會渲染成佔位方塊）。
struct CharacterView: View {
    let mood: Mood
    /// 要畫第幾個動畫格。不套用眨眼，輸出才可重現
    var frameIndex = 0

    var body: some View {
        Image(decorative: CharacterAnimation.image(
            rows: CharacterAnimation.animationFrame(mood: mood, index: frameIndex),
            mood: mood), scale: 1)
            // 最近鄰插值，放大後像素要銳利（§4.6）
            .interpolation(.none)
            .resizable()
            .frame(width: PanelMetrics.characterSize, height: PanelMetrics.characterSize)
            .padding(PanelMetrics.characterPadding)
    }
}
