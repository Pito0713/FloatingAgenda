import SwiftUI

/// 小精靈的**靜態**畫面，只給 `--snapshot` 用。
///
/// 正式 App 走 `CharacterLiveView`（NSView 直接繪圖，理由見 `CharacterHostView`）。
/// 這裡必須是純 SwiftUI：`ImageRenderer` 畫不出 `NSViewRepresentable`
/// （M5 記錄過同一個限制——`Toggle(.switch)` 會渲染成佔位方塊）。
struct CharacterView: View {
    let mood: Mood
    /// 用哪個皮膚畫。預設是內建角色
    var skin: Skin = CharacterAnimation.builtinSkin
    /// 要畫第幾個動畫格。不套用眨眼，輸出才可重現
    var frameIndex = 0

    @ViewBuilder
    var body: some View {
        if let image = frameImage {
            Image(decorative: image, scale: 1)
            // 最近鄰插值，放大後像素要銳利（§4.6）
            .interpolation(.none)
            .resizable()
            .frame(width: PanelMetrics.characterSize, height: PanelMetrics.characterSize)
            .padding(PanelMetrics.characterPadding)
        }
    }

    /// 外部皮膚沒有「每種心情各一張眨眼格」的概念，指定格號時一律取動畫格
    private var frameImage: CGImage? {
        if skin.id == BuiltinCharacter.id {
            return CharacterAnimation.image(
                rows: CharacterAnimation.animationFrame(mood: mood, index: frameIndex),
                mood: mood)
        }
        return skin.image(mood: mood, index: frameIndex)
    }
}
